#!/usr/bin/env python3
"""
Converter-to-Magnetic Design API Bridge

Calls PyOpenMagnetics.design_magnetics_from_converter() to go directly from
converter specs to designed magnetics. This replaces the 6-script chain:
  generate_om_topology.py → build_mas_structure.m → call_pyopenmagnetics_api.py
  → generate_om_recommendations.py → process_inputs + calculate_advised_magnetics

Usage:
  python call_converter_api.py <config_json> [output_json]

Input JSON:
  {
    "topology": "two_switch_forward",
    "converter": {
      "inputVoltage": {"minimum": 100, "maximum": 190},
      "desiredInductance": 3.5e-3,
      "desiredTurnsRatios": [7.9],
      "diodeVoltageDrop": 0.7,
      "currentRippleRatio": 0.2,
      "operatingPoints": [{
        "outputVoltages": [5.0],
        "outputCurrents": [5.0],
        "switchingFrequency": 200000,
        "ambientTemperature": 25
      }]
    },
    "max_results": 3,
    "use_ngspice": false,
    "weights": {"COST": 0.3, "EFFICIENCY": 0.4, "DIMENSIONS": 0.3},
    "adviser_settings": { ... }
  }

Output JSON:
  {
    "status": "OK",
    "count": N,
    "data": [{ core_name, material, total_losses_w, score, recommendation: {...} }, ...]
  }
"""

import json
import os
import sys
import time

from om_shared import _log, as_float, sanitize_local_key, strip_nulls, import_pyopenmagnetics


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
    out = {}
    if not isinstance(db_map, dict):
        return out
    for key, val in db_map.items():
        if isinstance(key, str):
            safe_key = sanitize_local_key(key)
            out[key.strip().lower()] = safe_key
        if isinstance(val, dict):
            name = val.get("name")
            if isinstance(name, str) and name.strip():
                safe_key = sanitize_local_key(key) if isinstance(key, str) else sanitize_local_key(name)
                out[name.strip().lower()] = safe_key
    return out


def load_local_catalog_index(base_dir):
    core_db = _load_local_json_map(os.path.join(base_dir, "openmagnetics_core_database.json"))
    material_db = _load_local_json_map(os.path.join(base_dir, "openmagnetics_material_database.json"))
    wire_db = _load_local_json_map(os.path.join(base_dir, "openmagnetics_wire_database.json"))
    return {
        "core_keys": set(sanitize_local_key(k) for k in core_db.keys()),
        "core_name_to_key": _build_name_to_key_map(core_db),
        "material_keys": set(sanitize_local_key(k) for k in material_db.keys()),
        "material_name_to_key": _build_name_to_key_map(material_db),
        "wire_keys": set(sanitize_local_key(k) for k in wire_db.keys()),
        "wire_name_to_key": _build_name_to_key_map(wire_db),
    }


def resolve_local_key(raw_name, keys_set, name_to_key):
    if not raw_name or not isinstance(raw_name, str):
        return ""
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
    core_raw = rec.get("core_shape_raw", rec.get("core_shape", ""))
    mat_raw = rec.get("material_raw", rec.get("material", ""))
    rec["core_shape_raw"] = core_raw
    rec["material_raw"] = mat_raw
    rec["core_shape_local_key"] = resolve_local_key(
        core_raw, local_idx.get("core_keys", set()), local_idx.get("core_name_to_key", {}))
    rec["material_local_key"] = resolve_local_key(
        mat_raw, local_idx.get("material_keys", set()), local_idx.get("material_name_to_key", {}))
    wire_fields = [k for k in list(rec.keys()) if k.endswith("_wire")]
    for wf in wire_fields:
        prefix = wf[:-5]
        raw_wire = rec.get(wf, "")
        rec[f"{prefix}_wire_raw"] = raw_wire
        matched_wire = rec.get(f"{prefix}_wire_matched", "")
        local_wire_key = ""
        if matched_wire:
            local_wire_key = resolve_local_key(
                matched_wire, local_idx.get("wire_keys", set()), local_idx.get("wire_name_to_key", {}))
        if not local_wire_key:
            local_wire_key = resolve_local_key(
                raw_wire, local_idx.get("wire_keys", set()), local_idx.get("wire_name_to_key", {}))
        if local_wire_key:
            rec[f"{prefix}_wire_local_key"] = local_wire_key
    return rec


def resolve_wire_info(wire_ref):
    """Resolve wire reference to type and dimensions via PyOpenMagnetics."""
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
    try:
        wire_data = pm.find_wire_by_name(wire_ref)
        if isinstance(wire_data, dict) and "data" not in wire_data:
            wtype = wire_data.get("type", "")
            if isinstance(wtype, str):
                info["wire_type"] = wtype.lower().replace(" ", "_")
            cd = wire_data.get("conductingDiameter", {})
            if isinstance(cd, dict):
                info["conducting_diameter"] = as_float(cd.get("nominal", cd.get("maximum", 0)), 0)
            elif isinstance(cd, (int, float)):
                info["conducting_diameter"] = as_float(cd, 0)
            cw = wire_data.get("conductingWidth", {})
            if isinstance(cw, dict):
                info["conducting_width"] = as_float(cw.get("nominal", cw.get("maximum", 0)), 0)
            elif isinstance(cw, (int, float)):
                info["conducting_width"] = as_float(cw, 0)
            ch = wire_data.get("conductingHeight", {})
            if isinstance(ch, dict):
                info["conducting_height"] = as_float(ch.get("nominal", ch.get("maximum", 0)), 0)
            elif isinstance(ch, (int, float)):
                info["conducting_height"] = as_float(ch, 0)
            nc = wire_data.get("numberConductors", 1)
            info["number_conductors"] = int(as_float(nc, 1))
    except Exception as exc:
        _log(f"  [WIRE] find_wire_by_name('{wire_ref}') failed: {exc}")
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
    return info


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
    mas = item.get("mas", item)
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

    # Number of stacked cores (e.g. 4 toroids stacked = 4x Ae)
    rec["numberStacks"] = int(as_float(core_fd.get("numberStacks", 1), 1))

    # Core name (from top-level core)
    rec["core_name"] = core.get("name", rec["core_shape"])

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
            wire_info = resolve_wire_info(wire_name)
            rec[f"{prefix}_wire_info"] = wire_info
            if wire_info.get("matched_name"):
                rec[f"{prefix}_wire_matched"] = wire_info["matched_name"]

    # Extract outputs (losses, inductance, flux density)
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

            # Core losses + flux density
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

        # Promote nominal (first) operating point values to top-level
        nom = rec["operating_point_outputs"][0]
        rec["Lm_uH"] = nom.get("Lm_H", 0.0) * 1e6
        rec["Llk_uH"] = nom.get("Llk_H", 0.0) * 1e6
        rec["B_peak_mT"] = nom.get("B_peak_T", 0.0) * 1e3
        rec["B_pp_mT"] = nom.get("B_pp_T", 0.0) * 1e3
        rec["B_offset_mT"] = nom.get("B_offset_T", 0.0) * 1e3
        rec["core_losses_w"] = nom.get("core_loss_W", 0.0)
        rec["winding_losses_w"] = nom.get("winding_loss_W", 0.0)
        rec["total_losses_w"] = rec["core_losses_w"] + rec["winding_losses_w"]
        rec["loss_source"] = "adviser_outputs"

    # Core effective parameters
    core_pd = core.get("processedDescription", {})
    if isinstance(core_pd, dict):
        eff = core_pd.get("effectiveParameters", {})
        if isinstance(eff, dict):
            rec["Ae_m2"] = as_float(eff.get("effectiveArea"), 0.0)
            rec["le_m"] = as_float(eff.get("effectiveLength"), 0.0)
            rec["Ve_m3"] = as_float(eff.get("effectiveVolume"), 0.0)

    # Material saturation flux density
    mat_data = core_fd.get("material", {})
    if isinstance(mat_data, dict):
        sat = mat_data.get("saturation", mat_data.get("bSat", None))
        if isinstance(sat, (int, float)):
            rec["B_sat_T"] = float(sat)
        elif isinstance(sat, dict):
            rec["B_sat_T"] = as_float(sat.get("nominal", sat.get("typical")), 0.0)

    return rec


def apply_adviser_settings(config):
    """Apply real PyOpenMagnetics settings before the adviser call.

    Only sets settings that actually exist in the C++ engine:
      Tier 1 (returned by get_settings()):
        - useOnlyCoresInStock
      Tier 2 (accepted by set_settings() but not returned by get_settings()):
        - coreAdviserMaximumMagneticsAfterFiltering
        - maximumNumberParallels
        - coreAdviserMaximumNumberStacks

    Returns (settings_overridden, previous_settings) for cleanup.
    """
    adv = config.get("adviser_settings", {})
    if not isinstance(adv, dict) or not adv:
        return False, None

    try:
        settings_obj = pm.get_settings()
        if not isinstance(settings_obj, dict) or "data" in settings_obj:
            return False, None

        previous_settings = dict(settings_obj)
        changed = False

        # Tier 1: useOnlyCoresInStock (real, returned by get_settings)
        use_in_stock = bool(adv.get("cores_in_stock", False))
        if settings_obj.get("useOnlyCoresInStock", True) != use_in_stock:
            settings_obj["useOnlyCoresInStock"] = use_in_stock
            changed = True

        # Tier 2: coreAdviserMaximumMagneticsAfterFiltering (real, hidden)
        max_after_filter = int(adv.get("max_cores_after_filtering", 100))
        if settings_obj.get("coreAdviserMaximumMagneticsAfterFiltering", 500) != max_after_filter:
            settings_obj["coreAdviserMaximumMagneticsAfterFiltering"] = max_after_filter
            changed = True

        # Tier 2: maximumNumberParallels (real, hidden)
        max_parallels = adv.get("max_parallels")
        if max_parallels is not None:
            settings_obj["maximumNumberParallels"] = int(max_parallels)
            changed = True

        # Tier 2: coreAdviserMaximumNumberStacks (real, hidden)
        max_stacks = adv.get("max_stacks")
        if max_stacks is not None:
            settings_obj["coreAdviserMaximumNumberStacks"] = int(max_stacks)
            changed = True

        # Core shape filters (match generate_om_recommendations.py logic)
        inc_toroidal = bool(adv.get("include_toroidal_cores", True))
        if settings_obj.get("useToroidalCores", True) != inc_toroidal:
            settings_obj["useToroidalCores"] = inc_toroidal
            changed = True

        inc_stacks = bool(adv.get("include_stacked_cores", False))
        if settings_obj.get("coreAdviserIncludeStacks", True) != inc_stacks:
            settings_obj["coreAdviserIncludeStacks"] = inc_stacks
            changed = True

        inc_dist_gaps = bool(adv.get("include_distributed_gaps", False))
        if settings_obj.get("coreAdviserIncludeDistributedGaps", True) != inc_dist_gaps:
            settings_obj["coreAdviserIncludeDistributedGaps"] = inc_dist_gaps
            changed = True

        if changed:
            pm.set_settings(settings_obj)
            _log(f"[CONVERTER_API] Applied settings: inStock={use_in_stock}, "
                 f"maxFilter={max_after_filter}, toroidal={inc_toroidal}, "
                 f"stacks={inc_stacks}, distGaps={inc_dist_gaps}")
            return True, previous_settings

        return False, previous_settings

    except Exception as exc:
        _log(f"[CONVERTER_API] Warning: could not apply settings: {exc}")
        return False, None


def restore_settings(overridden, previous):
    """Restore original settings after adviser call."""
    if overridden and previous is not None:
        try:
            pm.set_settings(previous)
        except Exception as exc:
            _log(f"[CONVERTER_API] Warning: failed to restore settings: {exc}")


def _estimate_fill_factor(rec, local_idx):
    """Estimate window fill factor from recommendation data + local databases.

    Uses π/4 × OD² for round/litz wire, W × H for rectangular/foil wire.

    Returns (fill_factor, conductor_area_mm2, window_area_mm2) or (None, 0, 0) if
    insufficient data.
    """
    import math

    core_db = local_idx.get("_core_db")
    wire_db = local_idx.get("_wire_db")
    if not core_db or not wire_db:
        return None, 0, 0

    # Get window area from local core database
    core_key = rec.get("core_shape_local_key", "")
    core_data = core_db.get(core_key, {})
    ww = core_data.get("windingWindow", {})
    if isinstance(ww, dict):
        w_width = ww.get("width") or 0
        w_height = ww.get("height") or 0
        window_area = w_width * w_height  # m²
        # For toroidal cores, use area directly (radial window)
        if window_area <= 0 and ww.get("area"):
            window_area = ww["area"]
    else:
        window_area = 0
    if window_area <= 0:
        return None, 0, 0

    # Sum conductor cross-sectional area across all windings
    total_cond_area = 0.0
    for prefix in ["primary", "secondary", "secondary_2", "secondary_3"]:
        n_turns = rec.get(f"{prefix}_turns", 0)
        n_par = rec.get(f"{prefix}_parallels", 1) or 1
        if n_turns <= 0:
            continue

        wire_key = rec.get(f"{prefix}_wire_local_key", "")
        wire_data = wire_db.get(wire_key, {})
        wire_type = (wire_data.get("type", "") or "").lower()

        od = wire_data.get("outerDiameter", 0) or 0
        ow = wire_data.get("outerWidth", 0) or 0
        oh = wire_data.get("outerHeight", 0) or 0

        if wire_type in ("foil", "rectangular") and ow > 0 and oh > 0:
            # Rectangular/foil: width × height
            cond_area = ow * oh  # m²
        elif od > 0:
            # Round or Litz: π/4 × OD²
            cond_area = math.pi / 4 * od * od  # m²
        elif ow > 0 and oh > 0:
            # Fallback to rectangular if OD not available
            cond_area = ow * oh
        else:
            continue  # Can't estimate without wire dimensions

        total_cond_area += n_turns * n_par * cond_area

    if total_cond_area <= 0:
        return None, 0, 0

    fill = total_cond_area / window_area
    return fill, total_cond_area * 1e6, window_area * 1e6  # return mm² for logging


def format_raw_results(raw_data, t_start, config=None):
    """Format adviser raw results into display-ready output items.

    Applies window fill factor filtering and scoring:
      - Hard reject: fill < fill_min_pct (default 20%)
      - Score penalty: fill between min and target (40%) — score *= sqrt(fill/target)
      - Warning flags: approaching min limit, or above fill_max_pct (manufacturability)

    Fill factor uses π/4 × OD² for round/litz, W × H for rectangular/foil.
    """
    import math

    if not isinstance(raw_data, list):
        raw_data = [raw_data]

    if config is None:
        config = {}
    adv_cfg = config.get("adviser_settings", {})

    t_format = time.perf_counter()
    base_dir = os.path.dirname(os.path.abspath(__file__))
    local_idx = load_local_catalog_index(base_dir)
    core_filter_active = len(local_idx.get("core_keys", set())) > 0

    # Load full core and wire databases for fill factor estimation
    try:
        core_db_path = os.path.join(base_dir, "openmagnetics_core_database.json")
        wire_db_path = os.path.join(base_dir, "openmagnetics_wire_database.json")
        with open(core_db_path, "r", encoding="utf-8") as f:
            local_idx["_core_db"] = json.load(f)
        with open(wire_db_path, "r", encoding="utf-8") as f:
            local_idx["_wire_db"] = json.load(f)
    except Exception as exc:
        _log(f"[FILL] Could not load databases for fill estimation: {exc}")
        local_idx["_core_db"] = {}
        local_idx["_wire_db"] = {}

    # Fill factor thresholds (user-configurable from topology wizard)
    FILL_MIN_PCT = float(adv_cfg.get("fill_min_pct", 20))   # Hard reject below this
    FILL_MAX_PCT = float(adv_cfg.get("fill_max_pct", 60))   # Manufacturability warning above
    TARGET_FILL = 0.40                                        # Ideal fill for scoring (40%)
    WARN_MARGIN_PCT = 5.0                                     # "Approaching limit" margin

    _log(f"[FILL] Thresholds: reject<{FILL_MIN_PCT:.0f}%, warn_approach<{FILL_MIN_PCT+WARN_MARGIN_PCT:.0f}%, "
         f"target={TARGET_FILL*100:.0f}%, mfg_warn>{FILL_MAX_PCT:.0f}%")

    formatted_results = []
    rejected_count = 0
    for item in raw_data:
        rec = extract_recommendation(item)
        if not rec:
            continue
        rec = apply_local_ids(rec, local_idx)

        if core_filter_active and not rec.get("core_shape_local_key"):
            _log(f"[CONVERTER_API] Core not in local DB: {rec.get('core_shape', '?')}")

        raw_score = rec.get("score", 0.0)
        core_label = rec.get("core_shape", "?")

        # Window utilization analysis
        fill, cond_mm2, win_mm2 = _estimate_fill_factor(rec, local_idx)
        fill_pct = fill * 100 if fill is not None else -1
        fill_penalty = 1.0
        fill_warning = ""

        if fill is not None:
            if fill_pct < FILL_MIN_PCT:
                # Hard reject
                _log(f"[FILL] REJECT {core_label}: fill={fill_pct:.1f}% < {FILL_MIN_PCT:.0f}% "
                     f"(cond={cond_mm2:.1f}mm2 / win={win_mm2:.0f}mm2)")
                rejected_count += 1
                continue

            elif fill_pct < FILL_MIN_PCT + WARN_MARGIN_PCT:
                # Approaching lower limit
                fill_penalty = max(0.3, math.sqrt(fill / TARGET_FILL))
                fill_warning = f"Approaching min fill limit ({fill_pct:.0f}%)"
                _log(f"[FILL] WARN {core_label}: fill={fill_pct:.1f}% approaching "
                     f"min={FILL_MIN_PCT:.0f}%, penalty={fill_penalty:.3f}")

            elif fill_pct > FILL_MAX_PCT:
                # Above manufacturability threshold — no score penalty, just warning
                fill_warning = f"Fill {fill_pct:.0f}% > {FILL_MAX_PCT:.0f}%: may be difficult to manufacture"
                _log(f"[FILL] MFG_WARN {core_label}: fill={fill_pct:.1f}% > {FILL_MAX_PCT:.0f}%")

            elif fill < TARGET_FILL:
                # Below target — score penalty
                fill_penalty = max(0.3, math.sqrt(fill / TARGET_FILL))
                _log(f"[FILL] {core_label}: fill={fill_pct:.1f}% penalty={fill_penalty:.3f}")

            else:
                # Between target and max — ideal range
                _log(f"[FILL] {core_label}: fill={fill_pct:.1f}% (good)")

        adjusted_score = raw_score * fill_penalty
        rec["fill_factor"] = fill if fill is not None else -1
        rec["fill_factor_pct"] = fill_pct
        rec["fill_penalty"] = fill_penalty
        rec["fill_warning"] = fill_warning
        rec["score_original"] = raw_score
        rec["score"] = adjusted_score

        out_item = {
            "core_name": rec.get("core_name", rec.get("core_shape", "Unknown")),
            "core_shape": rec.get("core_shape", "Unknown"),
            "material": rec.get("material", "Unknown"),
            "total_losses_w": rec.get("total_losses_w", 0.0),
            "core_losses_w": rec.get("core_losses_w", 0.0),
            "winding_losses_w": rec.get("winding_losses_w", 0.0),
            "Lm_uH": rec.get("Lm_uH", 0.0),
            "Llk_uH": rec.get("Llk_uH", 0.0),
            "B_peak_mT": rec.get("B_peak_mT", 0.0),
            "score": adjusted_score,
            "recommendation": rec,
        }
        if isinstance(item, dict) and "mas" in item:
            out_item["mas_data"] = item["mas"]
        formatted_results.append(out_item)

    if rejected_count > 0:
        _log(f"[FILL] Rejected {rejected_count} recommendation(s) below {FILL_MIN_PCT:.0f}% fill")

    # Sort by adjusted score (highest first)
    formatted_results.sort(key=lambda x: x.get("score", 0), reverse=True)

    t_format_done = time.perf_counter()
    _log(f"[TIMER] Format results:     {t_format_done - t_format:.3f}s")
    _log(f"[TIMER] Total:              {t_format_done - t_start:.1f}s")

    return {
        "status": "OK",
        "count": len(formatted_results),
        "rejected_by_fill": rejected_count,
        "data": formatted_results,
    }


def run_converter_design(config):
    """Run the converter-to-magnetic design pipeline using design_magnetics_from_converter().
    This is the legacy path — may recommend undersized cores due to internal duty cycle halving bug.
    """
    t_start = time.perf_counter()

    topology = config.get("topology", "")
    converter = config.get("converter", {})
    max_results = int(config.get("max_results", 3))
    use_ngspice = bool(config.get("use_ngspice", False))
    api_weights = None

    if not topology:
        return {"status": "ERROR", "error": "No topology specified", "data": [], "count": 0}
    if not converter:
        return {"status": "ERROR", "error": "No converter spec provided", "data": [], "count": 0}

    _log(f"[CONVERTER_API] topology={topology}, max_results={max_results}, "
         f"use_ngspice={use_ngspice}, weights={api_weights}")
    _log(f"[CONVERTER_API] converter keys: {list(converter.keys())}")

    t_settings = time.perf_counter()
    settings_overridden, previous_settings = apply_adviser_settings(config)
    _log(f"[TIMER] Apply settings:     {time.perf_counter() - t_settings:.3f}s")

    t_api = time.perf_counter()
    try:
        result = pm.design_magnetics_from_converter(
            topology, converter, max_results, 'available cores', use_ngspice, api_weights
        )
    except Exception as exc:
        return {
            "status": "ERROR",
            "error": f"design_magnetics_from_converter failed: {exc}",
            "data": [], "count": 0
        }
    finally:
        restore_settings(settings_overridden, previous_settings)

    _log(f"[TIMER] design_magnetics:   {time.perf_counter() - t_api:.1f}s")

    if not isinstance(result, dict) or "data" not in result:
        error_msg = "Unknown error"
        if isinstance(result, dict) and "error" in result:
            error_msg = str(result["error"])
        else:
            error_msg = f"Unexpected result: {type(result).__name__}"
        _log(f"[CONVERTER_API] API error: {error_msg}")
        return {"status": "ERROR", "error": error_msg, "data": [], "count": 0}

    raw_data = result.get("data", [])

    # The adviser sometimes returns data as a string (error message) instead of a list.
    if isinstance(raw_data, str):
        _log(f"[CONVERTER_API] Adviser returned error string: {raw_data[:200]}")
        return {
            "status": "ERROR",
            "error": f"Adviser internal error: {raw_data[:300]}",
            "data": [], "count": 0
        }

    return format_raw_results(raw_data, t_start, config)


def _ensure_list(value):
    """Ensure a value is a list (wrap scalars)."""
    if isinstance(value, list):
        return value
    if value is None:
        return []
    return [value]


def _normalize_converter_for_process(converter):
    """Normalize converter spec fields for process_converter().

    The MATLAB/Octave GUI may pass scalars for fields that the C++ engine expects
    as arrays, and may pass efficiency as percentage instead of decimal.
    """
    conv = dict(converter)  # shallow copy
    for key in ("desiredTurnsRatios",):
        if key in conv:
            conv[key] = _ensure_list(conv[key])
    # Normalize per-operating-point array fields
    for op in conv.get("operatingPoints", []):
        for key in ("outputVoltages", "outputCurrents"):
            if key in op:
                op[key] = _ensure_list(op[key])
    # Efficiency: GUI stores as percent (90), C++ expects decimal (0.9)
    eff = conv.get("efficiency")
    if eff is not None and eff > 1:
        conv["efficiency"] = eff / 100.0
    return conv


def _relax_mas_constraints(mas):
    """Relax over-constraining fields in MAS designRequirements.

    process_converter() locks magnetizingInductance and turnsRatios to exact
    nominal values from our pre-computed converter spec.  This forces the
    adviser into oversized cores because it must find a core that fits those
    exact parameters.  The web frontend (Method A) lets PyOM optimize freely.

    This function widens the acceptable ranges so the adviser can explore
    smaller cores while still respecting the transformer topology structure.
    """
    dr = mas.get("designRequirements", {})

    # Widen magnetizingInductance: allow adviser to explore smaller/larger Lm
    # Keep range moderate so waveforms (computed at nominal Lm) stay valid
    mi = dr.get("magnetizingInductance")
    if isinstance(mi, dict) and mi.get("nominal"):
        nom = mi["nominal"]
        dr["magnetizingInductance"] = {
            "nominal": nom,
            "minimum": nom * 0.3,
            "maximum": nom * 3.0,
        }

    # Widen turnsRatios: keep close to nominal (voltage ratios are fixed
    # by the converter spec) but allow some flexibility for core selection
    for tr in dr.get("turnsRatios", []):
        if isinstance(tr, dict) and tr.get("nominal"):
            nom = tr["nominal"]
            tr["minimum"] = nom * 0.8
            tr["maximum"] = nom * 1.3
            tr.pop("excludeMinimum", None)
            tr.pop("excludeMaximum", None)

    # Strip all None/null values — C++ pybind11 crashes on them
    return strip_nulls(mas)


def run_process_and_advise(config):
    """Run the adviser pipeline using process_converter() for topology-aware waveforms.

    Uses PyOpenMagnetics' built-in topology processor to generate correct
    volt-second-balanced waveforms, then feeds the result directly to
    calculate_advised_magnetics().
    """
    t_start = time.perf_counter()

    topology = config.get("topology", "")
    converter = config.get("converter", {})
    max_results = int(config.get("max_results", 3))

    if not topology:
        return {"status": "ERROR", "error": "No topology specified", "data": [], "count": 0}
    if not converter:
        return {"status": "ERROR", "error": "No converter spec provided", "data": [], "count": 0}

    _log(f"[PROCESS_ADVISE] topology={topology}, max_results={max_results}")

    # Step 1: Normalize converter spec and call process_converter()
    t_process = time.perf_counter()
    conv_normalized = _normalize_converter_for_process(converter)
    use_ngspice = bool(config.get("use_ngspice", False))

    try:
        mas = pm.process_converter(topology, conv_normalized, use_ngspice)
    except Exception as exc:
        return {
            "status": "ERROR",
            "error": f"process_converter failed: {exc}",
            "data": [], "count": 0
        }

    if isinstance(mas, dict) and "error" in mas:
        return {
            "status": "ERROR",
            "error": f"process_converter error: {mas['error']}",
            "data": [], "count": 0
        }

    ops = mas.get("operatingPoints", [])
    dr = mas.get("designRequirements", {})
    _log(f"[PROCESS_ADVISE] process_converter produced {len(ops)} operating point(s)")
    _log(f"[PROCESS_ADVISE] topology={dr.get('topology')}, "
         f"Lm={dr.get('magnetizingInductance', {}).get('nominal', 0)*1e6:.1f}uH")
    _log(f"[TIMER] process_converter:  {time.perf_counter() - t_process:.3f}s")

    # Step 1b: Relax constraints so adviser can optimize freely
    mas = _relax_mas_constraints(mas)
    _log(f"[PROCESS_ADVISE] Relaxed MAS constraints for adviser optimization")

    # Step 2: Apply adviser settings
    t_settings = time.perf_counter()
    settings_overridden, previous_settings = apply_adviser_settings(config)
    _log(f"[TIMER] Apply settings:     {time.perf_counter() - t_settings:.3f}s")

    # Step 3: Call calculate_advised_magnetics to search cores
    # Dual search: run for both toroidal and non-toroidal when include_all_core_shapes=true
    adv_cfg = config.get("adviser_settings", {})
    include_all_shapes = bool(adv_cfg.get("include_all_core_shapes", False))

    t_advise = time.perf_counter()
    all_raw_data = []
    try:
        if include_all_shapes:
            _log("[PROCESS_ADVISE] Dual search: running for both toroidal + non-toroidal")
            for pass_label, use_toroidal in [("non-toroidal", False), ("toroidal", True)]:
                cur_settings = pm.get_settings()
                if isinstance(cur_settings, dict) and "data" not in cur_settings:
                    cur_settings["useToroidalCores"] = use_toroidal
                    pm.set_settings(cur_settings)
                _log(f"[PROCESS_ADVISE] Running {pass_label} pass (useToroidalCores={use_toroidal})")
                try:
                    pass_result = pm.calculate_advised_magnetics(mas, max_results, 'available cores')
                    if isinstance(pass_result, dict) and "data" in pass_result:
                        pass_data = pass_result.get("data", [])
                        if isinstance(pass_data, list):
                            all_raw_data.extend(pass_data)
                            _log(f"[PROCESS_ADVISE] {pass_label}: got {len(pass_data)} results")
                        elif pass_data:
                            all_raw_data.append(pass_data)
                    elif isinstance(pass_result, list):
                        all_raw_data.extend(pass_result)
                except Exception as pass_exc:
                    _log(f"[PROCESS_ADVISE] {pass_label} pass failed: {pass_exc}")
        else:
            result = pm.calculate_advised_magnetics(mas, max_results, 'available cores')
            if isinstance(result, dict) and "data" in result:
                all_raw_data = result.get("data", [])
            elif isinstance(result, dict) and "error" in result:
                _log(f"[PROCESS_ADVISE] API error: {result['error']}")
            elif isinstance(result, list):
                all_raw_data = result
    except Exception as exc:
        restore_settings(settings_overridden, previous_settings)
        return {
            "status": "ERROR",
            "error": f"calculate_advised_magnetics failed: {exc}",
            "data": [], "count": 0
        }
    finally:
        restore_settings(settings_overridden, previous_settings)

    _log(f"[TIMER] advised_magnetics:  {time.perf_counter() - t_advise:.1f}s")
    _log(f"[PROCESS_ADVISE] Total raw results: {len(all_raw_data)}")

    raw_data = all_raw_data
    if not raw_data:
        return {"status": "ERROR", "error": "No results from adviser", "data": [], "count": 0}

    # The adviser sometimes returns data as a string (error message) instead of a list.
    if isinstance(raw_data, str):
        _log(f"[PROCESS_ADVISE] Adviser returned error string: {raw_data[:200]}")
        return {
            "status": "ERROR",
            "error": f"Adviser internal error: {raw_data[:300]}",
            "data": [], "count": 0
        }

    _log(f"[PROCESS_ADVISE] Adviser returned {len(raw_data)} result(s)")

    return format_raw_results(raw_data, t_start, config)


def main():
    t_script_start = time.perf_counter()

    if len(sys.argv) < 2:
        _log("Usage: python call_converter_api.py <config_json> [output_json]")
        sys.exit(1)

    config_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else "om_converter_api_results.json"

    if not os.path.exists(config_path):
        _log(f"ERROR: Config file not found: {config_path}")
        sys.exit(1)

    # Load config
    with open(config_path, "r", encoding="utf-8") as fh:
        config = json.load(fh)

    # Import PyOpenMagnetics
    t_import = time.perf_counter()
    global pm
    try:
        pm = import_pyopenmagnetics()
    except ImportError as exc:
        result = {
            "status": "ERROR",
            "error": f"Cannot import PyOpenMagnetics: {exc}",
            "data": [],
            "count": 0
        }
        with open(output_path, "w", encoding="utf-8") as fh:
            json.dump(result, fh, indent=2)
        _log(f"ERROR: {result['error']}")
        sys.exit(1)
    _log(f"[TIMER] Import PyOpenMagnetics: {time.perf_counter() - t_import:.3f}s")

    # Select design pipeline:
    # "process_and_advise" (default): uses correct topology waveforms + calculate_advised_magnetics
    # "converter_api": uses design_magnetics_from_converter (legacy, may undersize cores)
    pipeline = config.get("pipeline", "process_and_advise")
    if pipeline == "converter_api":
        _log(f"[CONVERTER_API] Using legacy design_magnetics_from_converter pipeline")
        result = run_converter_design(config)
    else:
        _log(f"[CONVERTER_API] Using process_and_advise pipeline (correct waveforms)")
        result = run_process_and_advise(config)
        # Fallback to legacy if process_and_advise fails or returns zero results
        if result.get("status") == "ERROR" or result.get("count", 0) == 0:
            reason = result.get("error", "zero results")
            _log(f"[CONVERTER_API] process_and_advise failed ({reason}), falling back to legacy")
            result_legacy = run_converter_design(config)
            if result_legacy.get("status") == "OK" and result_legacy.get("count", 0) > 0:
                result = result_legacy
                result["pipeline_note"] = "fallback_to_legacy"

    # Write results
    with open(output_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2, default=str)

    t_total = time.perf_counter() - t_script_start
    _log(f"[TIMER] Script total:       {t_total:.1f}s")

    if result.get("status") == "OK":
        print("OK")
    else:
        _log(f"ERROR: {result.get('error', 'unknown')}")
        sys.exit(1)


# pm is set in main() after import
pm = None

if __name__ == "__main__":
    main()
