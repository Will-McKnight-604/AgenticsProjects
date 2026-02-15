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
import importlib.metadata

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


def get_pm_runtime_version():
    """Return installed PyOpenMagnetics package version when available."""
    try:
        return importlib.metadata.version("PyOpenMagnetics")
    except Exception:
        return "unknown"


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
        "2_switch_forward": "Two Switch Forward Converter",
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
    topo_key = raw_topo.lower().replace("-", "_").replace(" ", "_")
    topology = topology_map.get(topo_key, raw_topo)

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


def apply_user_weights(recommendations, weights):
    """Compute a UI score without overriding the raw adviser score.

    The adviser returns a raw score (`raw_score`) that should remain the
    source of truth for ranking. We also compute a UI-weighted score from
    COST/LOSSES/DIMENSIONS so users can compare how slider preferences
    would rank the same candidates.
    """
    w_cost = as_float(weights.get("COST", 1.0), 1.0)
    w_losses = as_float(weights.get("LOSSES", 1.0), 1.0)
    w_dims = as_float(weights.get("DIMENSIONS", 1.0), 1.0)
    w_total = w_cost + w_losses + w_dims
    if w_total < 1e-12:
        w_total = 1.0  # avoid division by zero

    for rec in recommendations:
        spf = rec.get("scoring_per_filter", {})
        s_cost = as_float(spf.get("COST", 0.0), 0.0)
        s_losses = as_float(spf.get("LOSSES", 0.0), 0.0)
        s_dims = as_float(spf.get("DIMENSIONS", 0.0), 0.0)

        # Weighted sum normalized by total weight
        rec["ui_weighted_score"] = (
            w_cost * s_cost + w_losses * s_losses + w_dims * s_dims
        ) / w_total
        rec["ui_score"] = rec["ui_weighted_score"]

        # Backward-compatible aliases:
        # - score/raw_score are the adviser score (source of truth)
        # - weighted_score maps to ui_weighted_score
        raw = as_float(rec.get("raw_score", rec.get("score", 0.0)), 0.0)
        rec["raw_score"] = raw
        rec["score"] = raw
        rec["weighted_score"] = rec["ui_weighted_score"]
        rec["score_mode"] = "raw_mkf"

    # Keep adviser ordering semantics: rank by raw score.
    recommendations.sort(key=lambda r: as_float(r.get("raw_score", 0.0), 0.0), reverse=True)
    return recommendations


def run_recommendations(config):
    """Run PyOpenMagnetics advisor to get design recommendations."""

    max_results = int(as_float(config.get("max_results", 5), 5))

    weights = config.get("weights", {})
    if isinstance(weights, str):
        weights = json.loads(weights)

    # Map weight keys: GUI uses LOSSES, API uses EFFICIENCY
    api_weights = {
        "COST": as_float(weights.get("COST", 1.0), 1.0),
        "EFFICIENCY": as_float(weights.get("LOSSES", weights.get("EFFICIENCY", 1.0)), 1.0),
        "DIMENSIONS": as_float(weights.get("DIMENSIONS", 1.0), 1.0),
    }

    # Ensure core databases are loaded before calling advisor
    ensure_databases_loaded()

    # Build MAS inputs
    inputs = build_mas_inputs(config)

    # Log key inputs for traceability
    dr = inputs.get("designRequirements", {})
    mag_ind = dr.get("magnetizingInductance", {})
    turns_ratios = dr.get("turnsRatios", [])
    ops = inputs.get("operatingPoints", [{}])
    freq = 0
    if ops and ops[0].get("excitationsPerWinding"):
        freq = ops[0]["excitationsPerWinding"][0].get("frequency", 0)
    print(f"[ADVISOR] Inputs: Lm={mag_ind}, turnsRatios={turns_ratios}, "
          f"freq={freq}Hz, weights={api_weights}", file=sys.stderr)

    # Process inputs through PyOpenMagnetics
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

    # Use "standard cores" mode to get E/ETD/PQ/RM cores (not just stocked toroids).
    # "available cores" only returns commercially stocked cores (mostly toroids).
    core_mode = "standard cores"

    # Request a larger pool so user weights can meaningfully re-rank results.
    pool_size = max(max_results * 3, 15)

    try:
        results = pm.calculate_advised_magnetics(
            processed,
            pool_size,
            core_mode
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

    # Compute UI-weighted scores while preserving raw adviser ranking, then trim.
    recommendations = apply_user_weights(recommendations, weights)
    recommendations = recommendations[:max_results]

    return {
        "status": "OK",
        "n_results": len(recommendations),
        "recommendations": recommendations,
        "weights": weights,
        "inputs_used": inputs,
        "score_convention": {
            "primary": "raw_score",
            "secondary": "ui_score",
            "ranking": "raw_score_desc"
        },
        "pyopenmagnetics_runtime_version": get_pm_runtime_version()
    }


def compute_losses_for_recommendation(mas_data):
    """Compute core and winding losses using PyOpenMagnetics APIs.

    Takes the full MAS dict (magnetic + inputs) from the advisor result
    and calls calculate_core_losses() and calculate_winding_losses().

    Returns (core_losses_w, winding_losses_w) or (0.0, 0.0) on failure.
    """
    magnetic = mas_data.get("magnetic", {})
    inputs_data = mas_data.get("inputs", {})
    core = magnetic.get("core", {})
    coil = magnetic.get("coil", {})

    if not core or not coil or not inputs_data:
        return 0.0, 0.0

    core_losses = 0.0
    winding_losses = 0.0

    # Core losses via calculate_core_losses(core, coil, inputs, models)
    try:
        models = {"coreLosses": "Steinmetz", "reluctance": "Zhang"}
        core_result = pm.calculate_core_losses(core, coil, inputs_data, models)
        if isinstance(core_result, dict) and "data" not in core_result:
            core_losses = as_float(core_result.get("coreLosses", 0.0), 0.0)
    except Exception as exc:
        print(f"  [LOSS] Core loss calc failed: {exc}", file=sys.stderr)

    # Winding losses via calculate_winding_losses(magnetic, operating_point, temperature)
    try:
        ops = inputs_data.get("operatingPoints", [])
        if not ops:
            ops = inputs_data.get("operating_points", [])
        if ops:
            op = ops[0]
            temperature = op.get("conditions", {}).get("ambientTemperature", 25.0)
            winding_result = pm.calculate_winding_losses(magnetic, op, temperature)
            if isinstance(winding_result, dict) and "data" not in winding_result:
                winding_losses = as_float(
                    winding_result.get("windingLosses", 0.0), 0.0
                )
    except Exception as exc:
        print(f"  [LOSS] Winding loss calc failed: {exc}", file=sys.stderr)

    return core_losses, winding_losses


def resolve_wire_info(wire_ref):
    """Resolve an advisor wire reference to its type and dimensions.

    The advisor returns internal wire names like 'Litz TXXL180/38TXXX-3(MWXX)'.
    This function uses find_wire_by_name() to look up the wire's actual
    type and conducting dimensions, then finds the closest match in the
    local wire database.

    Returns a dict with:
      - original_name: the raw advisor wire reference
      - wire_type: 'round', 'litz', 'foil', 'rectangular', or 'unknown'
      - conducting_diameter: in meters (for round/litz strand)
      - conducting_width: in meters (for rectangular/foil)
      - conducting_height: in meters (for rectangular/foil)
      - number_conductors: strand count for litz, else 1
      - matched_name: closest local DB wire name, or None
    """
    info = {
        "original_name": str(wire_ref),
        "wire_type": "unknown",
        "conducting_diameter": 0.0,
        "conducting_width": 0.0,
        "conducting_height": 0.0,
        "number_conductors": 1,
        "matched_name": None,
    }

    if not wire_ref or not isinstance(wire_ref, str):
        return info

    # Try PyOpenMagnetics find_wire_by_name
    try:
        wire_data = pm.find_wire_by_name(wire_ref)
        if isinstance(wire_data, dict) and "data" not in wire_data:
            # Extract wire type
            wtype = wire_data.get("type", "")
            if isinstance(wtype, str):
                info["wire_type"] = wtype.lower().replace(" ", "_")

            # Conducting diameter (round, litz strand)
            cd = wire_data.get("conductingDiameter", {})
            if isinstance(cd, dict):
                info["conducting_diameter"] = as_float(
                    cd.get("nominal", cd.get("maximum", 0)), 0
                )
            elif isinstance(cd, (int, float)):
                info["conducting_diameter"] = as_float(cd, 0)

            # Conducting width/height (rectangular, foil)
            cw = wire_data.get("conductingWidth", {})
            if isinstance(cw, dict):
                info["conducting_width"] = as_float(
                    cw.get("nominal", cw.get("maximum", 0)), 0
                )
            elif isinstance(cw, (int, float)):
                info["conducting_width"] = as_float(cw, 0)

            ch = wire_data.get("conductingHeight", {})
            if isinstance(ch, dict):
                info["conducting_height"] = as_float(
                    ch.get("nominal", ch.get("maximum", 0)), 0
                )
            elif isinstance(ch, (int, float)):
                info["conducting_height"] = as_float(ch, 0)

            # Number of conductors (litz strand count)
            nc = wire_data.get("numberConductors", 1)
            info["number_conductors"] = int(as_float(nc, 1))
    except Exception as exc:
        print(f"  [WIRE] find_wire_by_name('{wire_ref}') failed: {exc}",
              file=sys.stderr)

    # If find_wire_by_name didn't work, try to parse from the name string
    if info["wire_type"] == "unknown":
        name_lower = wire_ref.lower()
        if "litz" in name_lower:
            info["wire_type"] = "litz"
        elif "foil" in name_lower:
            info["wire_type"] = "foil"
        elif "rectangular" in name_lower:
            info["wire_type"] = "rectangular"
        elif "round" in name_lower:
            info["wire_type"] = "round"

    # Try to match against the local wire database
    info["matched_name"] = match_wire_in_local_db(info)

    return info


def match_wire_in_local_db(wire_info):
    """Find the closest wire in the local database by type and dimensions.

    Searches all wires from get_wire_names() and picks the closest match
    by conducting diameter (for round/litz) or conducting width (for foil).

    Returns the matched wire name string, or None if no match.
    """
    target_type = wire_info.get("wire_type", "unknown")
    target_dia = wire_info.get("conducting_diameter", 0)
    target_width = wire_info.get("conducting_width", 0)
    target_strands = wire_info.get("number_conductors", 1)

    if target_type == "unknown":
        return None

    try:
        all_wire_names = pm.get_wire_names()
        if isinstance(all_wire_names, dict) and "data" in all_wire_names:
            return None  # error response
        if not isinstance(all_wire_names, list):
            return None
    except Exception:
        return None

    best_name = None
    best_distance = float("inf")

    for wname in all_wire_names:
        if not isinstance(wname, str):
            continue

        # Quick type filter from the name
        wname_lower = wname.lower()
        if target_type == "litz" and "litz" not in wname_lower:
            continue
        if target_type == "round" and ("litz" in wname_lower or "foil" in wname_lower
                                        or "rectangular" in wname_lower):
            continue
        if target_type == "foil" and "foil" not in wname_lower:
            continue
        if target_type == "rectangular" and "rectangular" not in wname_lower:
            continue

        # Get this wire's dimensions
        try:
            wd = pm.find_wire_by_name(wname)
            if isinstance(wd, dict) and "data" not in wd:
                cd = wd.get("conductingDiameter", {})
                if isinstance(cd, dict):
                    dia = as_float(cd.get("nominal", cd.get("maximum", 0)), 0)
                else:
                    dia = as_float(cd, 0)

                cw = wd.get("conductingWidth", {})
                if isinstance(cw, dict):
                    width = as_float(cw.get("nominal", cw.get("maximum", 0)), 0)
                else:
                    width = as_float(cw, 0)

                nc = int(as_float(wd.get("numberConductors", 1), 1))

                # Compute distance metric
                if target_type in ("round",):
                    if target_dia > 0 and dia > 0:
                        dist = abs(dia - target_dia) / target_dia
                    else:
                        continue
                elif target_type == "litz":
                    # Match by strand diameter AND strand count
                    if target_dia > 0 and dia > 0:
                        dia_dist = abs(dia - target_dia) / max(target_dia, 1e-9)
                        strand_dist = abs(nc - target_strands) / max(target_strands, 1)
                        dist = dia_dist + 0.5 * strand_dist
                    else:
                        continue
                elif target_type in ("foil", "rectangular"):
                    if target_width > 0 and width > 0:
                        dist = abs(width - target_width) / target_width
                    else:
                        continue
                else:
                    continue

                if dist < best_distance:
                    best_distance = dist
                    best_name = wname
        except Exception:
            continue

    if best_name:
        print(f"  [WIRE] Matched '{wire_info['original_name']}' -> '{best_name}' "
              f"(dist={best_distance:.4f})", file=sys.stderr)

    return best_name


def extract_recommendation(item):
    """Extract a flat recommendation dict from an advisor result item."""

    rec = {}

    if isinstance(item, str):
        try:
            item = json.loads(item)
        except Exception:
            return None

    # Scores
    rec["raw_score"] = as_float(item.get("scoring", 0.0), 0.0)
    rec["score"] = rec["raw_score"]
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
                wire_name = wire.get("name", str(wire))
            else:
                wire_name = str(wire)
            rec[f"{prefix}_wire"] = wire_name

            # Resolve wire to type/dimensions and find local DB match
            wire_info = resolve_wire_info(wire_name)
            rec[f"{prefix}_wire_info"] = wire_info
            if wire_info.get("matched_name"):
                rec[f"{prefix}_wire_matched"] = wire_info["matched_name"]

    # Compute losses using OpenMagnetics APIs
    core_losses, winding_losses = compute_losses_for_recommendation(mas)
    rec["core_losses_w"] = core_losses
    rec["winding_losses_w"] = winding_losses
    rec["total_losses_w"] = core_losses + winding_losses
    rec["loss_source"] = "OpenMagnetics"

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
