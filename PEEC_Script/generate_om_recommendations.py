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
import re
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


def sanitize_local_key(raw):
    """Match MATLAB make_valid_name/sanitize_field_name behavior."""
    if raw is None:
        raw = "Unknown"
    if not isinstance(raw, str):
        raw = str(raw)
    name = re.sub(r"[^a-zA-Z0-9_]", "_", raw)
    if not name:
        name = "Unknown"
    if not name[0].isalpha():
        name = f"W_{name}"
    return name


def _load_local_json_map(path):
    try:
        if not os.path.exists(path):
            return {}
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {}


def _build_name_to_key_map(db_map):
    """Build case-insensitive name->key map from local exported DB JSON."""
    out = {}
    if not isinstance(db_map, dict):
        return out
    for key, val in db_map.items():
        if isinstance(key, str):
            out[key.strip().lower()] = key
        if isinstance(val, dict):
            name = val.get("name")
            if isinstance(name, str) and name.strip():
                out[name.strip().lower()] = key
    return out


def load_local_catalog_index(base_dir):
    """Load local core/material/wire catalogs used by interactive GUI."""
    core_db = _load_local_json_map(os.path.join(base_dir, "openmagnetics_core_database.json"))
    material_db = _load_local_json_map(os.path.join(base_dir, "openmagnetics_material_database.json"))
    wire_db = _load_local_json_map(os.path.join(base_dir, "openmagnetics_wire_database.json"))

    return {
        "core_keys": set(core_db.keys()),
        "core_name_to_key": _build_name_to_key_map(core_db),
        "material_keys": set(material_db.keys()),
        "material_name_to_key": _build_name_to_key_map(material_db),
        "wire_keys": set(wire_db.keys()),
        "wire_name_to_key": _build_name_to_key_map(wire_db),
    }


def resolve_local_key(raw_name, keys_set, name_to_key):
    """Resolve raw advisor name to local GUI DB key."""
    if not raw_name:
        return ""
    if not isinstance(raw_name, str):
        raw_name = str(raw_name)
    norm = raw_name.strip().lower()
    if norm in name_to_key:
        return name_to_key[norm]
    safe = sanitize_local_key(raw_name)
    if safe in keys_set:
        return safe
    return ""


def apply_local_ids(rec, local_idx):
    """Attach dual ID fields (raw + local key) for core/material/wires."""
    if not isinstance(rec, dict):
        return rec

    # Core/material dual IDs
    core_raw = rec.get("core_shape_raw", rec.get("core_shape", ""))
    mat_raw = rec.get("material_raw", rec.get("material", ""))
    rec["core_shape_raw"] = core_raw
    rec["material_raw"] = mat_raw
    rec["core_shape_local_key"] = resolve_local_key(
        core_raw, local_idx.get("core_keys", set()), local_idx.get("core_name_to_key", {})
    )
    rec["material_local_key"] = resolve_local_key(
        mat_raw, local_idx.get("material_keys", set()), local_idx.get("material_name_to_key", {})
    )

    # Wire dual IDs for all winding entries (primary, secondary, secondary_2, ...)
    wire_fields = [k for k in list(rec.keys()) if k.endswith("_wire")]
    for wf in wire_fields:
        prefix = wf[:-5]
        raw_wire = rec.get(wf, "")
        rec[f"{prefix}_wire_raw"] = raw_wire
        matched_wire = rec.get(f"{prefix}_wire_matched", "")
        local_wire_key = ""
        if matched_wire:
            local_wire_key = resolve_local_key(
                matched_wire, local_idx.get("wire_keys", set()), local_idx.get("wire_name_to_key", {})
            )
        if not local_wire_key:
            local_wire_key = resolve_local_key(
                raw_wire, local_idx.get("wire_keys", set()), local_idx.get("wire_name_to_key", {})
            )
        if local_wire_key:
            rec[f"{prefix}_wire_local_key"] = local_wire_key

    return rec


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


def _build_excitations_for_op(op_windings, freq_hz, duty):
    """Build MAS excitationsPerWinding from an operating point's winding list.

    Supports two modes:
      1. Explicit waveform params: waveform_label, i_pp, i_offset, v_pp, v_offset
      2. Legacy RMS mode: rms_current_a, rms_voltage_v (backward compatible)
    """
    # Handle windings as list (may come as dict from Octave cell array encoding)
    if isinstance(op_windings, dict):
        op_windings = [op_windings[k] for k in sorted(op_windings.keys())]

    excitations = []
    for idx, w in enumerate(op_windings):
        if isinstance(w, str):
            continue

        waveform_label = w.get("waveform_label", None)

        if waveform_label and ("i_pp" in w or "v_pp" in w):
            # Explicit waveform mode (new format from topology wizard)
            i_pp = as_float(w.get("i_pp", 0.0), 0.0)
            i_offset = as_float(w.get("i_offset", 0.0), 0.0)
            v_pp = as_float(w.get("v_pp", 0.0), 0.0)
            v_offset = as_float(w.get("v_offset", 0.0), 0.0)

            # For secondary with RMS fallback
            if i_pp == 0 and "rms_current_a" in w:
                rms_i = as_float(w.get("rms_current_a", 0.0), 0.0)
                if rms_i > 0 and duty > 0:
                    i_peak = rms_i / math.sqrt(duty)
                    i_pp = i_peak
                    i_offset = i_peak * duty / 2.0

            if v_pp == 0 and "rms_voltage_v" in w:
                rms_v = as_float(w.get("rms_voltage_v", 0.0), 0.0)
                if rms_v > 0 and duty > 0:
                    v_pp = rms_v / math.sqrt(duty)
                    v_offset = 0

            # Determine voltage label (default Rectangular for all topologies)
            v_label = w.get("voltage_label", "Rectangular")

            excitations.append({
                "name": w.get("name", f"Winding {idx+1}"),
                "frequency": freq_hz,
                "current": {
                    "processed": {
                        "label": waveform_label,
                        "peakToPeak": i_pp,
                        "offset": i_offset,
                        "dutyCycle": duty
                    }
                },
                "voltage": {
                    "processed": {
                        "label": v_label,
                        "peakToPeak": v_pp,
                        "offset": v_offset,
                        "dutyCycle": duty
                    }
                }
            })
        else:
            # Legacy RMS-based mode (backward compatible)
            rms_i = as_float(w.get("rms_current_a", 0.0), 0.0)
            rms_v = as_float(w.get("rms_voltage_v", 0.0), 0.0)

            if rms_i > 0 and duty > 0:
                i_peak = rms_i / math.sqrt(duty)
                i_offset = i_peak * duty / 2.0
                i_pp = i_peak
            else:
                i_pp = 0
                i_offset = 0

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

    return excitations


def build_mas_inputs(config):
    """Build MAS inputs structure from recommendation config.

    Supports two config formats:
      - New: config.operating_points[] array (each with .windings, .duty, .vin, etc.)
      - Legacy: config.operating_point + config.windings (single operating point)
    """

    dr = config.get("design_requirements", {})
    samples = int(as_float(config.get("samples_per_period", 512), 512))

    # --- Build operating points ---
    operating_points_cfg = config.get("operating_points", None)

    # Handle Octave cell array encoding (dict with numeric keys)
    if isinstance(operating_points_cfg, dict):
        operating_points_cfg = [operating_points_cfg[k]
                                for k in sorted(operating_points_cfg.keys())]

    mas_op_points = []

    if operating_points_cfg and isinstance(operating_points_cfg, list):
        # New multi-operating-point format
        for op_cfg in operating_points_cfg:
            if isinstance(op_cfg, str):
                continue
            freq_hz = as_float(op_cfg.get("frequency_hz", 100e3), 100e3)
            duty = as_float(op_cfg.get("duty", 0.4), 0.4)
            ambient_temp = as_float(op_cfg.get("ambient_temperature", 25), 25)
            op_windings = op_cfg.get("windings", [])

            excitations = _build_excitations_for_op(op_windings, freq_hz, duty)
            mas_op_points.append({
                "name": op_cfg.get("name", "operating_point"),
                "conditions": {
                    "ambientTemperature": ambient_temp
                },
                "excitationsPerWinding": excitations
            })
    else:
        # Legacy single operating point format
        op = config.get("operating_point", {})
        windings = config.get("windings", [])
        if isinstance(windings, dict):
            windings = [windings[k] for k in sorted(windings.keys())]

        freq_hz = as_float(op.get("frequency_hz", 100e3), 100e3)
        duty = as_float(op.get("duty", 0.4), 0.4)
        ambient_temp = as_float(op.get("ambient_temperature", 25), 25)

        excitations = _build_excitations_for_op(windings, freq_hz, duty)
        mas_op_points.append({
            "name": "nominal",
            "conditions": {
                "ambientTemperature": ambient_temp
            },
            "excitationsPerWinding": excitations
        })

    # --- Build turns ratios ---
    turns_ratios = []
    tr = dr.get("turnsRatios", None)
    if tr is not None:
        if isinstance(tr, dict):
            turns_ratios.append(tr)
        elif isinstance(tr, list):
            turns_ratios = tr
        else:
            turns_ratios = [{"nominal": float(tr)}]

    # --- Build magnetizing inductance ---
    mag_ind = dr.get("magnetizingInductance", {})
    if isinstance(mag_ind, (int, float)):
        mag_ind = {"nominal": float(mag_ind)}

    # --- Map topology names ---
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

    # --- Assemble MAS inputs ---
    design_req = {
        "topology": topology,
        "magnetizingInductance": mag_ind,
        "turnsRatios": turns_ratios,
    }

    # Forward optional design requirements
    for key in ("operatingTemperature", "insulation", "maximumDimensions",
                "maximumWeight", "leakageInductance", "market"):
        val = dr.get(key)
        if val is not None:
            design_req[key] = val

    inputs = {
        "designRequirements": design_req,
        "operatingPoints": mas_op_points,
    }

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

    # Rank by UI-weighted score so weight sliders influence the ordering
    # of the returned recommendation set.
    recommendations.sort(key=lambda r: as_float(r.get("ui_weighted_score", 0.0), 0.0), reverse=True)
    return recommendations


def _normalize_wire_family_mode(raw_mode):
    mode = str(raw_mode or "auto_all").strip().lower()
    if mode in ("auto", "all", "auto_all"):
        return "auto_all"
    if mode in ("round_litz_rect", "round/litz/rectangular", "round_litz_rectangular"):
        return "round_litz_rect"
    if mode in ("foil_planar", "foil/planar"):
        return "foil_planar"
    return "auto_all"


def _extract_wire_types(rec):
    out = []
    if not isinstance(rec, dict):
        return out
    for key, value in rec.items():
        if not key.endswith("_wire_info") or not isinstance(value, dict):
            continue
        wtype = str(value.get("wire_type", "")).strip().lower()
        if wtype:
            out.append(wtype)
    return out


def _extract_wire_names(rec):
    out = []
    if not isinstance(rec, dict):
        return out
    for key, value in rec.items():
        if not key.endswith("_wire"):
            continue
        if isinstance(value, str) and value.strip():
            out.append(value.strip().lower())
    return out


def recommendation_matches_wire_family(rec, wire_family_mode):
    """Return True if recommendation matches requested wire family mode."""
    mode = _normalize_wire_family_mode(wire_family_mode)
    if mode == "auto_all":
        return True

    wire_types = _extract_wire_types(rec)
    wire_names = _extract_wire_names(rec)
    has_planar_name = any("planar" in name for name in wire_names)
    has_foil = any(wt == "foil" for wt in wire_types)
    has_planar = has_planar_name

    if mode == "foil_planar":
        return has_foil or has_planar

    # round_litz_rect mode: keep non-foil/non-planar solutions.
    return not (has_foil or has_planar)


def run_recommendations(config):
    """Run PyOpenMagnetics advisor to get design recommendations."""

    max_results = int(as_float(config.get("max_results", 5), 5))
    wire_family_mode = _normalize_wire_family_mode(config.get("wire_family_mode", "auto_all"))

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
    n_ops = len(ops)
    has_insulation = "insulation" in dr
    has_max_dims = "maximumDimensions" in dr
    op_temp = dr.get("operatingTemperature", {})
    pri_label = "?"
    if ops and ops[0].get("excitationsPerWinding"):
        pri_label = ops[0]["excitationsPerWinding"][0].get("current", {}).get(
            "processed", {}).get("label", "?")
    print(f"[ADVISOR] Inputs: Lm={mag_ind}, turnsRatios={turns_ratios}, "
          f"freq={freq}Hz, weights={api_weights}, "
          f"ops={n_ops}, pri_current={pri_label}, "
          f"insulation={has_insulation}, maxDims={has_max_dims}, "
          f"opTemp={op_temp}", file=sys.stderr)

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

    # Match web-tool default behavior for faster recommendations.
    core_mode = "available cores"

    # For available-cores mode, include both stock and non-stock entries
    # so we get mixed core families (not predominantly toroids).
    settings_overridden = False
    previous_settings = None
    try:
        settings_obj = pm.get_settings()
        if isinstance(settings_obj, dict) and "data" not in settings_obj:
            previous_settings = dict(settings_obj)
            if settings_obj.get("useOnlyCoresInStock", True):
                settings_obj["useOnlyCoresInStock"] = False
                pm.set_settings(settings_obj)
                settings_overridden = True
                print(
                    "[ADVISOR] Set useOnlyCoresInStock=False "
                    "(available cores mode; mixed families enabled)",
                    file=sys.stderr,
                )
    except Exception as exc:
        print(f"[ADVISOR] Warning: could not update useOnlyCoresInStock: {exc}",
              file=sys.stderr)

    # Request a moderately larger pool so we get some core family diversity
    # after compatibility filtering.  Keep it small to avoid MKF crashes
    # (each result requires full winding computation which can segfault).
    pool_size = max(max_results * 2, 10)
    maximum_number_results = pool_size

    try:
        try:
            results = pm.calculate_advised_magnetics(
                processed,
                maximum_number_results,
                core_mode
            )
        finally:
            if settings_overridden and previous_settings is not None:
                try:
                    pm.set_settings(previous_settings)
                except Exception as exc:
                    print(f"[ADVISOR] Warning: failed to restore settings: {exc}",
                          file=sys.stderr)
    except Exception as exc:
        return {
            "status": "ERROR",
            "error": f"calculate_advised_magnetics failed: {exc}",
            "recommendations": []
        }

    # Load local GUI catalogs for compatibility filtering + dual IDs.
    base_dir = os.path.dirname(os.path.abspath(__file__))
    local_idx = load_local_catalog_index(base_dir)
    core_filter_active = len(local_idx.get("core_keys", set())) > 0

    # Parse results
    compatible_recommendations = []
    incompatible_recommendations = []
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

    if isinstance(result_data, dict):
        result_data = [result_data]

    for item in result_data:
        rec = extract_recommendation(item)
        if rec:
            rec = apply_local_ids(rec, local_idx)
            if core_filter_active and not rec.get("core_shape_local_key"):
                incompatible_recommendations.append(rec)
                print(
                    f"[ADVISOR] Incompatible core not in local DB: "
                    f"{rec.get('core_shape_raw', rec.get('core_shape', 'Unknown'))}",
                    file=sys.stderr,
                )
            else:
                compatible_recommendations.append(rec)

    compatibility_fallback_used = False
    skipped_incompatible_cores = 0
    if compatible_recommendations:
        recommendations = compatible_recommendations
        skipped_incompatible_cores = len(incompatible_recommendations)
        if skipped_incompatible_cores > 0:
            print(
                f"[ADVISOR] Filtered out {skipped_incompatible_cores} recommendation(s) "
                f"with cores missing from local GUI database",
                file=sys.stderr,
            )
    elif incompatible_recommendations:
        recommendations = incompatible_recommendations
        compatibility_fallback_used = True
        print(
            "[ADVISOR] No core recommendations matched local GUI DB. "
            "Falling back to unfiltered adviser results.",
            file=sys.stderr,
        )
    else:
        recommendations = []

    wire_filter_applied = (wire_family_mode != "auto_all")
    wire_filter_fallback_used = False
    wire_filtered_out = 0
    if wire_filter_applied and recommendations:
        before_wire_filter = len(recommendations)
        filtered = [
            rec for rec in recommendations
            if recommendation_matches_wire_family(rec, wire_family_mode)
        ]
        if filtered:
            recommendations = filtered
            wire_filtered_out = before_wire_filter - len(filtered)
            print(
                f"[ADVISOR] Wire family filter '{wire_family_mode}' kept "
                f"{len(filtered)}/{before_wire_filter} recommendation(s)",
                file=sys.stderr,
            )
        else:
            wire_filter_fallback_used = True
            print(
                f"[ADVISOR] Wire family filter '{wire_family_mode}' matched 0 results. "
                "Falling back to unfiltered wire families.",
                file=sys.stderr,
            )

    # Compute UI-weighted scores while preserving raw adviser ranking, then trim.
    recommendations = apply_user_weights(recommendations, weights)
    recommendations = recommendations[:max_results]

    return {
        "status": "OK",
        "n_results": len(recommendations),
        "recommendations": recommendations,
        "weights": weights,
        "compatibility_filter": {
            "core_filter_active": core_filter_active,
            "compatible_count": len(compatible_recommendations),
            "incompatible_count": len(incompatible_recommendations),
            "skipped_incompatible_cores": skipped_incompatible_cores,
            "fallback_to_incompatible": compatibility_fallback_used,
        },
        "wire_family_filter": {
            "requested_mode": wire_family_mode,
            "applied": wire_filter_applied,
            "filtered_out_count": wire_filtered_out,
            "fallback_to_unfiltered": wire_filter_fallback_used,
        },
        "inputs_used": inputs,
        "score_convention": {
            "primary": "ui_weighted_score",
            "secondary": "raw_score",
            "ranking": "ui_weighted_score_desc"
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
    rec["core_shape_raw"] = rec["core_shape"]

    material = core_fd.get("material", "Unknown")
    if isinstance(material, dict):
        rec["material"] = material.get("name", str(material))
    else:
        rec["material"] = str(material)
    rec["material_raw"] = rec["material"]

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
            rec[f"{prefix}_wire_raw"] = wire_name

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

    # Extract MKF-computed outputs per operating point (inductance, flux density, etc.)
    outputs = mas.get("outputs", [])
    if isinstance(outputs, list) and outputs:
        rec["operating_point_outputs"] = []
        for oi, op_out in enumerate(outputs):
            if not isinstance(op_out, dict):
                continue
            op_data = {"index": oi}

            # Inductance
            ind = op_out.get("inductance", {})
            if isinstance(ind, dict):
                mi = ind.get("magnetizingInductance", {})
                if isinstance(mi, dict):
                    lm_obj = mi.get("magnetizingInductance", mi)
                    if isinstance(lm_obj, dict):
                        op_data["Lm_H"] = as_float(lm_obj.get("nominal"), 0.0)
                    elif isinstance(lm_obj, (int, float)):
                        op_data["Lm_H"] = float(lm_obj)
                li = ind.get("leakageInductance", {})
                if isinstance(li, dict):
                    lpw = li.get("leakageInductancePerWinding", [])
                    if isinstance(lpw, list) and lpw:
                        first_leak = lpw[0]
                        if isinstance(first_leak, dict):
                            op_data["Llk_H"] = as_float(first_leak.get("nominal"), 0.0)

            # Core losses + magnetic flux density
            cl = op_out.get("coreLosses", {})
            if isinstance(cl, dict):
                op_data["core_loss_W"] = as_float(cl.get("coreLosses"), 0.0)
                mfd = cl.get("magneticFluxDensity", {})
                if isinstance(mfd, dict):
                    proc = mfd.get("processed", {})
                    if isinstance(proc, dict):
                        op_data["B_peak_T"] = as_float(proc.get("peak"), 0.0)
                        op_data["B_pp_T"] = as_float(proc.get("peakToPeak"), 0.0)
                        op_data["B_offset_T"] = as_float(proc.get("offset"), 0.0)

            # Winding losses
            wl = op_out.get("windingLosses", {})
            if isinstance(wl, dict):
                op_data["winding_loss_W"] = as_float(wl.get("windingLosses"), 0.0)

            rec["operating_point_outputs"].append(op_data)

        # Promote nominal (first) operating point values to top-level for easy access
        nom = rec["operating_point_outputs"][0]
        rec["Lm_uH"] = nom.get("Lm_H", 0.0) * 1e6
        rec["Llk_uH"] = nom.get("Llk_H", 0.0) * 1e6
        rec["B_peak_mT"] = nom.get("B_peak_T", 0.0) * 1e3
        rec["B_pp_mT"] = nom.get("B_pp_T", 0.0) * 1e3
        rec["B_offset_mT"] = nom.get("B_offset_T", 0.0) * 1e3

    # Core effective parameters for saturation context
    core_pd = core.get("processedDescription", {})
    if isinstance(core_pd, dict):
        eff = core_pd.get("effectiveParameters", {})
        if isinstance(eff, dict):
            rec["Ae_m2"] = as_float(eff.get("effectiveArea"), 0.0)
            rec["le_m"] = as_float(eff.get("effectiveLength"), 0.0)
            rec["Ve_m3"] = as_float(eff.get("effectiveVolume"), 0.0)

    # Material saturation flux density (if available)
    mat_data = core_fd.get("material", {})
    if isinstance(mat_data, dict):
        sat = mat_data.get("saturation", mat_data.get("bSat", None))
        if isinstance(sat, (int, float)):
            rec["B_sat_T"] = float(sat)
        elif isinstance(sat, dict):
            rec["B_sat_T"] = as_float(sat.get("nominal", sat.get("typical")), 0.0)

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
