#!/usr/bin/env python3
"""
Waveform generator using C++-equivalent converter topology equations.

Generates analytical voltage/current waveforms for each winding at min/max input
voltage operating points. Equations ported from MKF C++ source to match the
WebFrontEnd's analytical waveform output exactly.

Usage:
    python generate_om_waveforms.py config.json

Input JSON (om_waveform_config.json):
  {
    "topology": "two_switch_forward",
    "converter": {
      "vin_min": 120, "vin_max": 375, "vin_nom": 145,
      "vd": 0.5, "fsw_khz": 200,
      "output_voltages": [12, 3.3],
      "output_currents": [5, 5],
      "efficiency": 90,
      "max_ripple": 30,
      "ambient_temp": 25
    },
    "topology_results": {
      "Lm_uH": 3552.6,
      "turns_ratios": [7.89],
      "Lout_uH": 12.7
    },
    "numberOfPeriods": 2,
    "mode": "analytical",
    "output_file": "om_waveform_results.json"
  }
"""

import json
import math
import sys
import os
import traceback


# ── Import ported topology waveform generators ────────────────────────────────
from forward_waveforms import (
    generate_all_two_switch_forward_operating_points,
    generate_all_single_switch_forward_operating_points,
    generate_all_active_clamp_forward_operating_points,
    compute_two_switch_forward_design,
    compute_single_switch_forward_design,
    compute_active_clamp_forward_design,
)
from converter_waveform_models import (
    generate_flyback_multi_voltage,
    generate_push_pull_multi_voltage,
)
from generate_topology_waveforms import (
    generate_buck_waveforms_all_voltages,
    generate_boost_waveforms_all_voltages,
    generate_isolated_buck_waveforms_all_voltages,
    generate_isolated_buck_boost_waveforms_all_voltages,
)


def safe_float(val, default=0.0):
    """Safely convert to float, handling None and non-numeric values."""
    if val is None:
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def extract_params(converter, topology_results):
    """Extract common parameters from converter GUI config and topology results.

    Returns a dict with all parameters needed by the waveform generators.
    """
    vin_min = safe_float(converter.get("vin_min"), 100)
    vin_max = safe_float(converter.get("vin_max"), 400)
    vin_nom = safe_float(converter.get("vin_nom"))
    if vin_nom <= 0:
        vin_nom = (vin_min + vin_max) / 2

    input_voltage = {"minimum": vin_min, "nominal": vin_nom, "maximum": vin_max}

    vd = safe_float(converter.get("vd"), 0.5)
    fsw_khz = safe_float(converter.get("fsw_khz"), 200)
    fsw_hz = fsw_khz * 1000.0

    # Efficiency: GUI sends %, convert to decimal
    eff = safe_float(converter.get("efficiency"), 90)
    if eff > 1:
        eff = eff / 100.0

    # Current ripple ratio: GUI sends %, convert to decimal
    ripple = safe_float(converter.get("max_ripple"), 30)
    if ripple > 1:
        ripple = ripple / 100.0

    # Output voltages/currents
    vouts = converter.get("output_voltages")
    iouts = converter.get("output_currents")
    if not isinstance(vouts, list) or len(vouts) == 0:
        vouts = [safe_float(converter.get("vout"), 12)]
    if not isinstance(iouts, list) or len(iouts) == 0:
        iouts = [safe_float(converter.get("iout"), 5)]
    # Ensure same length
    while len(iouts) < len(vouts):
        iouts.append(iouts[-1] if iouts else 1.0)
    vouts = [safe_float(v) for v in vouts]
    iouts = [safe_float(i) for i in iouts]

    # Max duty cycle
    max_duty = safe_float(converter.get("max_duty"), 0)
    if max_duty > 1:
        max_duty = max_duty / 100.0
    if max_duty <= 0:
        max_duty = 0.45  # Default

    # Inductance from topology results
    lm_h = 0
    lout_h = 0
    turns_ratios = []
    if topology_results:
        lm_uh = safe_float(topology_results.get("Lm_uH"))
        if lm_uh > 0:
            lm_h = lm_uh * 1e-6
        lout_uh = safe_float(topology_results.get("Lout_uH"))
        if lout_uh > 0:
            lout_h = lout_uh * 1e-6
        tr = topology_results.get("turns_ratios")
        if isinstance(tr, list):
            turns_ratios = [safe_float(t) for t in tr]

    # Auto-extend turns_ratios for multi-output forward topologies
    # All secondaries share the same duty cycle, so:
    # Np/Ns_i = Np/Ns_0 * (Vout_0 + Vd) / (Vout_i + Vd)
    if len(turns_ratios) == 1 and len(vouts) > 1 and turns_ratios[0] > 0:
        tr0 = turns_ratios[0]
        v0 = vouts[0] + vd
        for i in range(1, len(vouts)):
            vi = vouts[i] + vd
            if vi > 0:
                turns_ratios.append(tr0 * v0 / vi)
            else:
                turns_ratios.append(tr0)

    return {
        "input_voltage": input_voltage,
        "vin_min": vin_min,
        "vin_max": vin_max,
        "vin_nom": vin_nom,
        "vd": vd,
        "fsw_hz": fsw_hz,
        "efficiency": eff,
        "current_ripple_ratio": ripple,
        "output_voltages": vouts,
        "output_currents": iouts,
        "max_duty": max_duty,
        "magnetizing_inductance": lm_h,
        "output_inductance": lout_h,
        "turns_ratios": turns_ratios,
        "ambient_temp": safe_float(converter.get("ambient_temp"), 25),
    }


def generate_analytical_waveforms(topology, converter, topology_results):
    """Generate analytical waveforms using ported C++ equations.

    Dispatches to the appropriate topology waveform generator and produces
    operating points for min and max input voltage conditions.
    """
    p = extract_params(converter, topology_results)

    print(f"[WAVEFORM] Topology: {topology}", file=sys.stderr)
    print(f"[WAVEFORM] Vin: {p['vin_min']}-{p['vin_max']}V, "
          f"Fsw: {p['fsw_hz']/1e3:.0f}kHz, "
          f"Outputs: {p['output_voltages']}V / {p['output_currents']}A",
          file=sys.stderr)

    try:
        if topology == "two_switch_forward":
            # Compute design if not provided
            if not p["turns_ratios"] or p["magnetizing_inductance"] <= 0:
                design = compute_two_switch_forward_design(
                    p["input_voltage"], p["output_voltages"], p["output_currents"],
                    p["fsw_hz"], p["vd"], p["max_duty"], p["current_ripple_ratio"])
                if not p["turns_ratios"]:
                    p["turns_ratios"] = design["turnsRatios"]
                if p["magnetizing_inductance"] <= 0:
                    p["magnetizing_inductance"] = design["magnetizingInductance"]
                if p["output_inductance"] <= 0:
                    p["output_inductance"] = design.get("outputInductances", [1e-5])[0]

            ops = generate_all_two_switch_forward_operating_points(
                input_voltage_spec=p["input_voltage"],
                output_voltages=p["output_voltages"],
                output_currents=p["output_currents"],
                turns_ratios=p["turns_ratios"],
                magnetizing_inductance=p["magnetizing_inductance"],
                switching_frequency=p["fsw_hz"],
                diode_voltage_drop=p["vd"],
                duty_cycle=p["max_duty"],
                current_ripple_ratio=p["current_ripple_ratio"],
                output_inductances=[p["output_inductance"]] if p["output_inductance"] > 0 else None,
            )

        elif topology == "single_switch_forward":
            if not p["turns_ratios"] or p["magnetizing_inductance"] <= 0:
                design = compute_single_switch_forward_design(
                    p["input_voltage"], p["output_voltages"], p["output_currents"],
                    p["fsw_hz"], p["vd"], p["max_duty"], p["current_ripple_ratio"])
                if not p["turns_ratios"]:
                    p["turns_ratios"] = design["turnsRatios"]
                if p["magnetizing_inductance"] <= 0:
                    p["magnetizing_inductance"] = design["magnetizingInductance"]
                if p["output_inductance"] <= 0:
                    p["output_inductance"] = design.get("outputInductances", [1e-5])[0]

            ops = generate_all_single_switch_forward_operating_points(
                input_voltage_spec=p["input_voltage"],
                output_voltages=p["output_voltages"],
                output_currents=p["output_currents"],
                turns_ratios=p["turns_ratios"],
                magnetizing_inductance=p["magnetizing_inductance"],
                switching_frequency=p["fsw_hz"],
                diode_voltage_drop=p["vd"],
                duty_cycle=p["max_duty"],
                current_ripple_ratio=p["current_ripple_ratio"],
                output_inductances=[p["output_inductance"]] if p["output_inductance"] > 0 else None,
            )

        elif topology == "active_clamp_forward":
            if not p["turns_ratios"] or p["magnetizing_inductance"] <= 0:
                design = compute_active_clamp_forward_design(
                    p["input_voltage"], p["output_voltages"], p["output_currents"],
                    p["fsw_hz"], p["vd"], p["max_duty"], p["current_ripple_ratio"])
                if not p["turns_ratios"]:
                    p["turns_ratios"] = design["turnsRatios"]
                if p["magnetizing_inductance"] <= 0:
                    p["magnetizing_inductance"] = design["magnetizingInductance"]
                if p["output_inductance"] <= 0:
                    p["output_inductance"] = design.get("outputInductances", [1e-5])[0]

            ops = generate_all_active_clamp_forward_operating_points(
                input_voltage_spec=p["input_voltage"],
                output_voltages=p["output_voltages"],
                output_currents=p["output_currents"],
                turns_ratios=p["turns_ratios"],
                magnetizing_inductance=p["magnetizing_inductance"],
                switching_frequency=p["fsw_hz"],
                diode_voltage_drop=p["vd"],
                duty_cycle=p["max_duty"],
                current_ripple_ratio=p["current_ripple_ratio"],
                output_inductances=[p["output_inductance"]] if p["output_inductance"] > 0 else None,
            )

        elif topology == "flyback":
            ops = generate_flyback_multi_voltage(
                p["vin_min"], p["vin_nom"], p["vin_max"],
                p["output_voltages"],
                p["output_currents"],
                p["turns_ratios"] if p["turns_ratios"] else [1.0] * len(p["output_voltages"]),
                p["magnetizing_inductance"] if p["magnetizing_inductance"] > 0 else 100e-6,
                p["fsw_hz"],
                diodeVoltageDrop=p["vd"],
                efficiency=p["efficiency"],
                currentRippleRatio=p["current_ripple_ratio"],
            )

        elif topology == "push_pull":
            ops = generate_push_pull_multi_voltage(
                p["vin_min"], p["vin_nom"], p["vin_max"],
                p["output_voltages"],
                p["output_currents"],
                p["turns_ratios"] if p["turns_ratios"] else [1.0] * len(p["output_voltages"]),
                p["magnetizing_inductance"] if p["magnetizing_inductance"] > 0 else 100e-6,
                p["fsw_hz"],
                diodeVoltageDrop=p["vd"],
                currentRippleRatio=p["current_ripple_ratio"],
                outputInductance=p["output_inductance"] if p["output_inductance"] > 0 else 50e-6,
            )

        elif topology == "buck":
            inductance = p["output_inductance"] if p["output_inductance"] > 0 else p["magnetizing_inductance"]
            if inductance <= 0:
                inductance = 10e-6
            ops = generate_buck_waveforms_all_voltages(
                p["vin_min"], p["vin_nom"], p["vin_max"],
                p["output_voltages"][0],
                p["output_currents"][0],
                inductance,
                p["fsw_hz"],
                diodeVoltageDrop=p["vd"],
                efficiency=p["efficiency"],
            )

        elif topology == "boost":
            inductance = p["output_inductance"] if p["output_inductance"] > 0 else p["magnetizing_inductance"]
            if inductance <= 0:
                inductance = 100e-6
            ops = generate_boost_waveforms_all_voltages(
                p["vin_min"], p["vin_nom"], p["vin_max"],
                p["output_voltages"][0],
                p["output_currents"][0],
                inductance,
                p["fsw_hz"],
                diodeVoltageDrop=p["vd"],
                efficiency=p["efficiency"],
            )

        elif topology == "isolated_buck":
            lm = p["magnetizing_inductance"] if p["magnetizing_inductance"] > 0 else 80e-6
            ops = generate_isolated_buck_waveforms_all_voltages(
                p["vin_min"], p["vin_nom"], p["vin_max"],
                p["output_voltages"],
                p["output_currents"],
                p["turns_ratios"] if p["turns_ratios"] else [10.0],
                lm,
                p["fsw_hz"],
                diodeVoltageDrop=p["vd"],
                efficiency=p["efficiency"],
            )

        elif topology == "isolated_buck_boost":
            lm = p["magnetizing_inductance"] if p["magnetizing_inductance"] > 0 else 60e-6
            ops = generate_isolated_buck_boost_waveforms_all_voltages(
                p["vin_min"], p["vin_nom"], p["vin_max"],
                p["output_voltages"],
                p["output_currents"],
                p["turns_ratios"] if p["turns_ratios"] else [1.0],
                lm,
                p["fsw_hz"],
                diodeVoltageDrop=p["vd"],
                efficiency=p["efficiency"],
            )

        else:
            return {"status": "ERROR", "message": f"Unknown topology: {topology}"}

    except Exception as e:
        print(f"[WAVEFORM] ERROR generating waveforms: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        return {"status": "ERROR", "message": str(e)}

    # Filter to min + max operating points only
    result_ops = []
    for op in ops:
        label = op.get("label", "")
        if "Min" in label or "Max" in label:
            result_ops.append(op)

    # If no min/max labels found, take first and last
    if not result_ops and ops:
        result_ops = [ops[0]]
        if len(ops) > 1:
            result_ops.append(ops[-1])

    n_ops = len(result_ops)
    n_windings = len(result_ops[0].get("excitationsPerWinding", [])) if result_ops else 0
    print(f"[WAVEFORM] Generated {n_ops} operating points, {n_windings} windings each",
          file=sys.stderr)

    return {
        "status": "OK",
        "mode": "analytical",
        "topology": topology,
        "operatingPoints": result_ops,
        "designRequirements": {},
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: python generate_om_waveforms.py config.json", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]

    # Read config
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
    except Exception as e:
        print(f"[WAVEFORM] ERROR reading config: {e}", file=sys.stderr)
        sys.exit(1)

    topology = config.get("topology", "two_switch_forward")
    converter = config.get("converter", {})
    topology_results = config.get("topology_results", {})
    mode = config.get("mode", "analytical")
    output_file = config.get("output_file", "om_waveform_results.json")

    print(f"[WAVEFORM] Topology: {topology}, Mode: {mode}", file=sys.stderr)

    if mode == "analytical":
        result = generate_analytical_waveforms(topology, converter, topology_results)
    else:
        result = {"status": "ERROR", "message": f"Unsupported mode: {mode}"}

    # Write output
    output_path = output_file
    if not os.path.isabs(output_path):
        output_path = os.path.join(os.path.dirname(os.path.abspath(config_path)), output_path)

    try:
        with open(output_path, 'w') as f:
            json.dump(result, f, indent=2, default=str)
        print(f"[WAVEFORM] Results written to {output_path}", file=sys.stderr)
    except Exception as e:
        print(f"[WAVEFORM] ERROR writing output: {e}", file=sys.stderr)
        sys.exit(1)

    # Print status for MATLAB to detect
    if result.get("status") == "OK":
        n_ops = len(result.get("operatingPoints", []))
        n_windings = 0
        if n_ops > 0:
            n_windings = len(result["operatingPoints"][0].get("excitationsPerWinding", []))
        print(f"OK:{n_ops} operating points, {n_windings} windings")
    else:
        print(f"ERROR:{result.get('message', 'Unknown error')}")
        sys.exit(1)


if __name__ == "__main__":
    main()
