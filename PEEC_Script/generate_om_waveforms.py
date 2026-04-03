#!/usr/bin/env python3
"""
Waveform generator using PyOpenMagnetics process_converter() API.

Generates topology-aware voltage/current waveforms for each winding using
the C++ engine's built-in waveform synthesis. This produces volt-second-balanced,
topology-specific waveforms (demagnetization timing, dead time, etc.) instead
of simplified analytical approximations.

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
import sys
import os
import traceback

from om_shared import _log, as_float, as_list, import_pyopenmagnetics, TOPOLOGY_MAP


NON_ISOLATED_TOPOLOGIES = {"buck", "boost"}


def _gui_to_mas_converter(topology_key, converter, topology_results):
    """Convert GUI-format converter spec to MAS format for process_converter().

    GUI format uses: vin_min, vin_max, output_voltages, fsw_khz, efficiency (%), etc.
    MAS format uses: inputVoltage.{minimum,maximum}, operatingPoints[].outputVoltages, etc.
    """
    vin_min = as_float(converter.get("vin_min"), 100)
    vin_max = as_float(converter.get("vin_max"), 400)

    vd = as_float(converter.get("vd"), 0.5)
    fsw_khz = as_float(converter.get("fsw_khz"), 200)
    fsw_hz = fsw_khz * 1000.0

    # Efficiency: GUI sends %, MAS needs decimal
    eff = as_float(converter.get("efficiency"), 90)
    if eff > 1:
        eff = eff / 100.0

    # Current ripple ratio: GUI sends %, MAS needs decimal
    ripple = as_float(converter.get("max_ripple"), 30)
    if ripple > 1:
        ripple = ripple / 100.0

    # Output voltages/currents — ensure arrays
    vouts = converter.get("output_voltages")
    iouts = converter.get("output_currents")
    if not isinstance(vouts, list):
        vouts = [as_float(vouts if vouts is not None else converter.get("vout"), 12)]
    if not isinstance(iouts, list):
        iouts = [as_float(iouts if iouts is not None else converter.get("iout"), 5)]
    while len(iouts) < len(vouts):
        iouts.append(iouts[-1] if iouts else 1.0)
    vouts = [as_float(v) for v in vouts]
    iouts = [as_float(i) for i in iouts]

    ambient = as_float(converter.get("ambient_temp"), 25)

    # Max duty cycle
    max_duty = as_float(converter.get("max_duty"), 0)
    if max_duty > 1:
        max_duty = max_duty / 100.0

    # Build operating point — non-isolated topologies use singular keys
    op = {
        "switchingFrequency": fsw_hz,
        "ambientTemperature": ambient,
    }
    if topology_key in NON_ISOLATED_TOPOLOGIES:
        op["outputVoltage"] = vouts[0]
        op["outputCurrent"] = iouts[0]
    else:
        op["outputVoltages"] = vouts
        op["outputCurrents"] = iouts

    # Build MAS converter dict
    mas_conv = {
        "inputVoltage": {"minimum": vin_min, "maximum": vin_max},
        "diodeVoltageDrop": vd,
        "currentRippleRatio": ripple,
        "efficiency": eff,
        "operatingPoints": [op],
    }

    if max_duty > 0:
        mas_conv["maximumDutyCycle"] = max_duty

    # Add topology results if available
    if topology_results:
        lm_uh = as_float(topology_results.get("Lm_uH"))
        if lm_uh > 0:
            mas_conv["desiredInductance"] = lm_uh * 1e-6

        tr = topology_results.get("turns_ratios")
        if isinstance(tr, list) and len(tr) > 0:
            tr_list = [as_float(t) for t in tr]
        elif isinstance(tr, (int, float)) and as_float(tr) > 0:
            tr_list = [as_float(tr)]
        else:
            tr_list = []

        # Single-switch forward needs extra entry for demagnetization winding
        if topology_key == "single_switch_forward" and tr_list:
            n_secondaries = len(vouts)
            if len(tr_list) == n_secondaries:
                nd_np = as_float(topology_results.get("nd_np"), 1.0)
                tr_list.append(nd_np)

        if tr_list:
            mas_conv["desiredTurnsRatios"] = tr_list

        # Duty cycles — computed by generate_om_topology.py, passed through by Octave GUI
        d_nom = as_float(topology_results.get("duty_nom"))
        d_worst = as_float(topology_results.get("duty_max_vin"))
        if d_nom > 0:
            if d_worst <= 0:
                d_worst = d_nom
            mas_conv["desiredDutyCycle"] = [[d_nom, d_worst]]

    return mas_conv


def _ensure_list(value):
    """Ensure a value is a list (wrap scalars)."""
    if isinstance(value, list):
        return value
    if value is None:
        return []
    return [value]


def _normalize_converter_for_process(converter):
    """Normalize converter spec fields to arrays as required by process_converter()."""
    conv = dict(converter)
    for key in ("desiredTurnsRatios",):
        if key in conv:
            conv[key] = _ensure_list(conv[key])
    for op in conv.get("operatingPoints", []):
        for key in ("outputVoltages", "outputCurrents"):
            if key in op:
                op[key] = _ensure_list(op[key])
    return conv


def generate_waveforms(topology_key, converter, topology_results):
    """Generate topology-aware waveforms via pm.process_converter().

    Returns the same output format as the previous analytical generator:
    {
        "status": "OK",
        "mode": "analytical",
        "topology": topology_key,
        "operatingPoints": [{ "label": ..., "excitationsPerWinding": [...] }],
        "designRequirements": {}
    }
    """
    # Validate topology key
    if topology_key not in TOPOLOGY_MAP:
        return {"status": "ERROR", "message": f"Unknown topology: {topology_key}"}

    # Convert GUI-format converter to MAS format
    mas_conv = _gui_to_mas_converter(topology_key, converter, topology_results)
    mas_conv = _normalize_converter_for_process(mas_conv)

    _log(f"[WAVEFORM] Topology: {topology_key}")
    _log(f"[WAVEFORM] Vin: {mas_conv['inputVoltage']['minimum']}-"
         f"{mas_conv['inputVoltage']['maximum']}V, "
         f"Fsw: {mas_conv['operatingPoints'][0]['switchingFrequency']/1e3:.0f}kHz")

    # Import PyOpenMagnetics
    try:
        pm = import_pyopenmagnetics()
    except ImportError as e:
        return {"status": "ERROR", "message": f"PyOpenMagnetics not available: {e}"}

    # Call process_converter to get topology-aware waveforms
    try:
        mas = pm.process_converter(topology_key, mas_conv, False)
    except Exception as e:
        _log(f"[WAVEFORM] process_converter failed: {e}")
        try:
            traceback.print_exc(file=sys.stderr)
        except (OSError, IOError):
            pass
        return {"status": "ERROR", "message": f"process_converter failed: {e}"}

    if isinstance(mas, dict) and "error" in mas:
        return {"status": "ERROR", "message": f"process_converter error: {mas['error']}"}

    ops = mas.get("operatingPoints", [])
    dr = mas.get("designRequirements", {})

    if not ops:
        return {"status": "ERROR", "message": "process_converter returned no operating points"}

    # Add labels to operating points for the GUI viewer
    vin_min = mas_conv["inputVoltage"]["minimum"]
    vin_max = mas_conv["inputVoltage"]["maximum"]
    for idx, op in enumerate(ops):
        if "label" not in op:
            if idx == 0:
                op["label"] = f"Vin Min ({vin_min:.0f}V)"
            elif idx == len(ops) - 1:
                op["label"] = f"Vin Max ({vin_max:.0f}V)"
            else:
                op["label"] = f"Operating Point {idx + 1}"

        # Add winding names for display
        for w_idx, exc in enumerate(op.get("excitationsPerWinding", [])):
            if "name" not in exc:
                if w_idx == 0:
                    exc["name"] = "Primary"
                else:
                    exc["name"] = f"Secondary {w_idx}"

    n_ops = len(ops)
    n_windings = len(ops[0].get("excitationsPerWinding", [])) if ops else 0
    _log(f"[WAVEFORM] Generated {n_ops} operating points, {n_windings} windings each")

    return {
        "status": "OK",
        "mode": "analytical",
        "topology": topology_key,
        "operatingPoints": ops,
        "designRequirements": dr,
    }


def main():
    if len(sys.argv) < 2:
        _log("Usage: python generate_om_waveforms.py config.json")
        sys.exit(1)

    config_path = sys.argv[1]

    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
    except Exception as e:
        _log(f"[WAVEFORM] ERROR reading config: {e}")
        sys.exit(1)

    topology = config.get("topology", "two_switch_forward")
    converter = config.get("converter", {})
    topology_results = config.get("topology_results", {})
    output_file = config.get("output_file", "om_waveform_results.json")

    _log(f"[WAVEFORM] Topology: {topology}")

    result = generate_waveforms(topology, converter, topology_results)

    # Write output
    output_path = output_file
    if not os.path.isabs(output_path):
        output_path = os.path.join(os.path.dirname(os.path.abspath(config_path)), output_path)

    try:
        with open(output_path, 'w') as f:
            json.dump(result, f, default=str)
        _log(f"[WAVEFORM] Results written to {output_path}")
    except Exception as e:
        _log(f"[WAVEFORM] ERROR writing output: {e}")
        sys.exit(1)

    # Print status for MATLAB/Octave to detect
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
