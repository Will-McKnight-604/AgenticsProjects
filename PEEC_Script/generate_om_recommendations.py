#!/usr/bin/env python3
"""
Generate design recommendations using PyOpenMagnetics advisor APIs.

Modes:
  recommend  - Build MAS inputs from converter specs, call calculate_advised_magnetics()
  export_mas - Export a complete design as a MAS JSON file

Usage:
    python generate_om_recommendations.py config.json
"""

import json
import math
import os
import sys

try:
    import PyOpenMagnetics as pm
except Exception as exc:
    print(f"ImportError: {exc}", file=sys.stderr)
    sys.exit(1)


def clamp(value, lo, hi):
    return max(lo, min(hi, value))


def as_float(value, default=0.0):
    try:
        return float(value)
    except Exception:
        return float(default)


def generate_current_waveform(rms_target, duty, phase_deg, samples):
    """Generate CCM trapezoidal current waveform for forward converter."""
    rms_target = abs(as_float(rms_target, 0.0))
    duty = clamp(as_float(duty, 0.4), 0.02, 0.98)

    if rms_target <= 0.0:
        return [0.0] * samples

    values = [0.0] * samples
    d_count = max(1, int(round(duty * samples)))
    d_count = min(samples, d_count)

    ripple_ratio = 0.25
    denom = max(duty * (1.0 + ripple_ratio * ripple_ratio / 3.0), 1e-12)
    i_avg_on = rms_target / math.sqrt(denom)
    for n in range(d_count):
        u = float(n) / float(max(d_count - 1, 1))
        values[n] = i_avg_on * (1.0 + ripple_ratio * (2.0 * u - 1.0))

    # Apply phase shift
    shift = int(round((phase_deg / 360.0) * samples))
    if shift != 0:
        shift = shift % samples
        values = values[-shift:] + values[:-shift]

    return values


def generate_voltage_waveform(rms_target, duty, winding_index, phase_deg, samples):
    """Generate voltage waveform for forward converter."""
    duty = clamp(as_float(duty, 0.4), 0.02, 0.98)
    target_rms = abs(as_float(rms_target, 0.0))

    values = [0.0] * samples
    d_count = max(1, int(round(duty * samples)))
    d_count = min(samples, d_count)

    if winding_index == 0:
        v_on = 1.0
        v_off = -duty / max(1.0 - duty, 1e-6)
        for n in range(samples):
            values[n] = v_on if n < d_count else v_off
    else:
        for n in range(d_count):
            values[n] = -1.0

    # Scale to target RMS
    rms_val = math.sqrt(sum(v * v for v in values) / len(values))
    if target_rms > 0 and rms_val > 1e-12:
        scale = target_rms / rms_val
        values = [scale * v for v in values]

    # Phase shift
    shift = int(round((phase_deg / 360.0) * samples))
    if shift != 0:
        shift = shift % samples
        values = values[-shift:] + values[:-shift]

    return values


def build_mas_inputs(config):
    """Build MAS inputs structure from recommendation config."""

    dr = config.get("design_requirements", {})
    op = config.get("operating_point", {})
    windings = config.get("windings", [])

    # Handle windings as list (may come as dict from Octave cell array encoding)
    if isinstance(windings, dict):
        windings = [windings[k] for k in sorted(windings.keys())]

    freq_hz = as_float(op.get("frequency_hz", 100e3), 100e3)
    duty = as_float(op.get("duty", 0.4), 0.4)
    samples = int(as_float(config.get("samples_per_period", 512), 512))
    ambient_temp = as_float(op.get("ambient_temperature", 25), 25)

    # Time vector
    period = 1.0 / freq_hz
    time_vec = [float(i) / float(samples) * period for i in range(samples)]

    # Build excitations per winding using the MAS "processed" label format
    # (matches the format used by the OpenMagnetics web tool)
    excitations = []
    for idx, w in enumerate(windings):
        if isinstance(w, str):
            continue
        rms_i = as_float(w.get("rms_current_a", 0.0), 0.0)
        rms_v = as_float(w.get("rms_voltage_v", 0.0), 0.0)

        # For forward converter: primary current is rectangular (on during D),
        # secondary is also rectangular. Voltage is rectangular.
        # Compute peak-to-peak and offset from RMS and duty cycle.

        # Current: approximate as rectangular pulse with duty D
        # I_peak = I_rms / sqrt(D), offset = I_peak * D / 2
        if rms_i > 0 and duty > 0:
            i_peak = rms_i / math.sqrt(duty)
            i_offset = i_peak * duty / 2.0
            i_pp = i_peak
        else:
            i_peak = 0
            i_offset = 0
            i_pp = 0

        # Voltage: rectangular pulse
        if rms_v > 0 and duty > 0:
            v_peak = rms_v / math.sqrt(duty)
            v_pp = v_peak * (1.0 + duty / max(1.0 - duty, 0.01))
            v_offset = 0
        else:
            v_pp = 0
            v_offset = 0

        excitations.append({
            "name": w.get("name", f"Winding {idx+1}"),
            "frequency": freq_hz,
            "current": {
                "processed": {
                    "label": "Rectangular",
                    "peakToPeak": i_pp,
                    "offset": i_offset,
                    "dutyCycle": duty
                }
            },
            "voltage": {
                "processed": {
                    "label": "Rectangular",
                    "peakToPeak": v_pp,
                    "offset": v_offset,
                    "dutyCycle": duty
                }
            }
        })

    # Build turns ratios
    turns_ratios = []
    tr = dr.get("turnsRatios", None)
    if tr is not None:
        if isinstance(tr, dict):
            turns_ratios.append(tr)
        elif isinstance(tr, list):
            turns_ratios = tr
        else:
            turns_ratios = [{"nominal": float(tr)}]

    # Build magnetizing inductance
    mag_ind = dr.get("magnetizingInductance", {})
    if isinstance(mag_ind, (int, float)):
        mag_ind = {"nominal": float(mag_ind)}

    # Map internal topology names to MAS schema enum values
    topology_map = {
        "two_switch_forward": "Two Switch Forward Converter",
        "2-switch forward": "Two Switch Forward Converter",
        "forward": "Two Switch Forward Converter",
        "flyback": "Flyback Converter",
        "buck": "Buck Converter",
        "boost": "Boost Converter",
        "push_pull": "Push-Pull Converter",
        "half_bridge": "Half-Bridge Converter",
        "full_bridge": "Full-Bridge Converter",
    }
    raw_topo = dr.get("topology", "Two Switch Forward Converter")
    topology = topology_map.get(raw_topo.lower().replace("-", "_").replace(" ", "_"), raw_topo)

    inputs = {
        "designRequirements": {
            "topology": topology,
            "magnetizingInductance": mag_ind,
        },
        "operatingPoints": [
            {
                "name": "nominal",
                "conditions": {
                    "ambientTemperature": ambient_temp
                },
                "excitationsPerWinding": excitations
            }
        ]
    }

    # turnsRatios is required by MAS schema (empty array for inductors)
    inputs["designRequirements"]["turnsRatios"] = turns_ratios

    return inputs


def strip_nulls(obj):
    """Recursively strip None/null values from dicts and lists.

    process_inputs() adds many null fields that violate the MAS JSON Schema
    (the schema uses strict types without nullable), so we must remove them
    before passing to the advisor functions.
    """
    if isinstance(obj, dict):
        return {k: strip_nulls(v) for k, v in obj.items() if v is not None}
    elif isinstance(obj, list):
        return [strip_nulls(v) for v in obj]
    return obj


def ensure_databases_loaded():
    """Load all bundled databases (core shapes, materials, wires) if empty.

    The advisor functions require loaded databases to search for candidate
    cores.  Call load_databases({}) to load all bundled data from the
    PyOpenMagnetics/MKF compiled-in NDJSON files.
    """
    try:
        if pm.is_core_shape_database_empty() or pm.is_core_material_database_empty():
            pm.load_databases({})
            n_shapes = len(pm.get_available_core_shapes())
            print(f"Loaded databases: {n_shapes} core shapes available", file=sys.stderr)
    except Exception as exc:
        print(f"Warning: database loading failed: {exc}", file=sys.stderr)


def run_recommendations(config):
    """Run PyOpenMagnetics advisor to get design recommendations."""

    max_results = int(as_float(config.get("max_results", 5), 5))

    weights = config.get("weights", {})
    if isinstance(weights, str):
        weights = json.loads(weights)

    # Ensure core databases are loaded before calling advisor
    ensure_databases_loaded()

    # Build MAS inputs
    inputs = build_mas_inputs(config)

    # Process inputs through PyOpenMagnetics
    # process_inputs expects a Python dict, returns a dict with added harmonics
    try:
        processed = pm.process_inputs(inputs)
    except Exception as exc:
        return {
            "status": "ERROR",
            "error": f"process_inputs failed: {exc}",
            "recommendations": []
        }

    # Check for processing errors
    if isinstance(processed, dict) and "data" in processed:
        data_val = processed["data"]
        if isinstance(data_val, str) and "Exception" in data_val:
            return {
                "status": "ERROR",
                "error": f"process_inputs returned error: {data_val}",
                "recommendations": []
            }

    # Strip null values added by process_inputs — MAS schema doesn't allow nulls
    if isinstance(processed, dict):
        processed = strip_nulls(processed)

    # Call advisor — pass dict directly (pybind11 handles conversion)
    # IMPORTANT: core_mode must be lowercase "available cores" not "AVAILABLE_CORES"
    # (MKF C++ enum parser expects exact lowercase strings)
    try:
        results = pm.calculate_advised_magnetics(
            processed,
            max_results,
            "available cores"
        )
    except Exception as exc:
        return {
            "status": "ERROR",
            "error": f"calculate_advised_magnetics failed: {exc}",
            "recommendations": []
        }

    # Parse results
    recommendations = []
    result_data = results if isinstance(results, list) else results.get("data", []) if isinstance(results, dict) else []

    if isinstance(result_data, str):
        try:
            result_data = json.loads(result_data)
        except Exception:
            return {
                "status": "ERROR",
                "error": f"Could not parse advisor results: {result_data[:200]}",
                "recommendations": []
            }

    for item in result_data:
        rec = extract_recommendation(item)
        if rec:
            recommendations.append(rec)

    return {
        "status": "OK",
        "n_results": len(recommendations),
        "recommendations": recommendations,
        "weights": weights,
        "inputs_used": inputs
    }


def extract_recommendation(item):
    """Extract a flat recommendation dict from an advisor result item."""

    rec = {}

    if isinstance(item, str):
        try:
            item = json.loads(item)
        except Exception:
            return None

    # Score
    rec["score"] = as_float(item.get("scoring", 0.0), 0.0)
    rec["scoring_per_filter"] = item.get("scoringPerFilter", {})

    # Navigate to magnetic
    mas = item.get("mas", item)  # might be nested or flat
    magnetic = mas.get("magnetic", {})

    # Core info
    core = magnetic.get("core", {})
    core_fd = core.get("functionalDescription", {})

    shape = core_fd.get("shape", {})
    if isinstance(shape, dict):
        rec["core_shape"] = shape.get("name", "Unknown")
    else:
        rec["core_shape"] = str(shape)

    material = core_fd.get("material", "Unknown")
    if isinstance(material, dict):
        rec["material"] = material.get("name", str(material))
    else:
        rec["material"] = str(material)

    # Gapping
    rec["gapping"] = core_fd.get("gapping", [])

    # Coil / winding info
    coil = magnetic.get("coil", {})
    func_desc = coil.get("functionalDescription", [])
    if isinstance(func_desc, list):
        rec["n_windings"] = len(func_desc)
        for idx, wd in enumerate(func_desc):
            prefix = "primary" if idx == 0 else f"secondary_{idx}" if idx > 1 else "secondary"
            rec[f"{prefix}_turns"] = int(as_float(wd.get("numberTurns", 0), 0))
            rec[f"{prefix}_parallels"] = int(as_float(wd.get("numberParallels", 1), 1))
            wire = wd.get("wire", "")
            if isinstance(wire, dict):
                rec[f"{prefix}_wire"] = wire.get("name", str(wire))
            else:
                rec[f"{prefix}_wire"] = str(wire)

    # Outputs (losses if available — may be dict or list of dicts)
    outputs = mas.get("outputs", {})
    if isinstance(outputs, list) and outputs:
        outputs = outputs[0] if isinstance(outputs[0], dict) else {}
    if isinstance(outputs, dict) and outputs:
        rec["core_losses_w"] = as_float(outputs.get("coreLosses", 0), 0)
        rec["winding_losses_w"] = as_float(outputs.get("windingLosses", 0), 0)
        rec["total_losses_w"] = rec["core_losses_w"] + rec["winding_losses_w"]

    return rec


def run_export_mas(config):
    """Export a design as a MAS JSON file."""

    inputs = build_mas_inputs(config)

    # Add magnetic section if recommendation data is provided
    rec = config.get("recommendation", {})
    magnetic = {}

    if rec and rec.get("core_shape"):
        magnetic["core"] = {
            "functionalDescription": {
                "shape": {"name": rec["core_shape"]},
                "material": rec.get("material", "N87"),
                "gapping": rec.get("gapping", [])
            }
        }

    if rec and rec.get("windings"):
        windings_fd = []
        wds = rec["windings"]
        if isinstance(wds, dict):
            wds = [wds[k] for k in sorted(wds.keys())]
        for w in wds:
            wd = {
                "name": w.get("name", ""),
                "numberTurns": int(as_float(w.get("n_turns", 1), 1)),
                "numberParallels": int(as_float(w.get("n_parallels", 1), 1)),
            }
            if w.get("wire"):
                wd["wire"] = w["wire"]
            windings_fd.append(wd)

        magnetic["coil"] = {"functionalDescription": windings_fd}

    mas = {"inputs": inputs}
    if magnetic:
        mas["magnetic"] = magnetic

    return {"status": "OK", "mas": mas}


def main():
    if len(sys.argv) < 2:
        print("Usage: python generate_om_recommendations.py config.json", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]
    if not os.path.exists(config_path):
        print(f"ERROR: Config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    with open(config_path, "r", encoding="utf-8") as fh:
        config = json.load(fh)

    mode = config.get("mode", "recommend")
    output_path = config.get("output_file", "om_recommendation_results.json")

    if mode == "export_mas":
        result = run_export_mas(config)
    else:
        result = run_recommendations(config)

    with open(output_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)

    if result.get("status") == "OK":
        print("OK")
    else:
        print(f"ERROR: {result.get('error', 'unknown')}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
