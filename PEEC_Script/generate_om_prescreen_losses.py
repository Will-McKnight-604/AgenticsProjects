#!/usr/bin/env python3
"""
Rank excitation operating points with a fast OpenMagnetics winding-loss pre-screen.

Usage:
    python generate_om_prescreen_losses.py om_prescreen_config.json
"""

import cmath
import json
import math
import os
import sys

try:
    import PyOpenMagnetics as pm
except Exception as exc:
    print(f"ImportError: {exc}", file=sys.stderr)
    print(f"Python executable: {sys.executable}", file=sys.stderr)
    print(f"Python path: {sys.path}", file=sys.stderr)
    sys.exit(1)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

try:
    import generate_om_visualization as gov
except Exception as exc:
    print(f"ImportError: {exc}", file=sys.stderr)
    sys.exit(1)


def as_float(value, default=0.0):
    try:
        return float(value)
    except Exception:
        return float(default)


def as_int(value, default=0):
    try:
        return int(round(float(value)))
    except Exception:
        return int(default)


def clamp(value, lo, hi):
    return max(lo, min(hi, value))


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh)


def ensure_list(value):
    if isinstance(value, list):
        return value
    if value is None:
        return []
    if isinstance(value, tuple):
        return list(value)
    return [value]


def get_idx(values, idx, default=0.0):
    if isinstance(values, list) and idx < len(values):
        return as_float(values[idx], default)
    return as_float(default, default)


def normalize_harmonics(harmonics):
    hs = ensure_list(harmonics)
    out = []
    for h in hs:
        if not isinstance(h, dict):
            continue
        order = as_int(h.get("order", 0), 0)
        if order <= 0:
            continue
        out.append(h)
    out.sort(key=lambda x: as_int(x.get("order", 0), 0))
    return out


def infer_fundamental_frequency(op, harmonics, default_hz):
    f0 = as_float(op.get("frequency_hz", 0.0), 0.0)
    if f0 > 0:
        return f0
    for h in harmonics:
        order = as_int(h.get("order", 0), 0)
        fh = as_float(h.get("frequency_hz", 0.0), 0.0)
        if order > 0 and fh > 0:
            return fh / float(order)
    return default_hz


def build_waveforms_from_harmonics(op, n_windings, samples, max_harmonics, default_hz):
    harmonics = normalize_harmonics(op.get("harmonics", []))
    if max_harmonics > 0 and len(harmonics) > max_harmonics:
        harmonics = harmonics[:max_harmonics]
    if not harmonics:
        raise RuntimeError("Operating point has no harmonics")

    f0 = infer_fundamental_frequency(op, harmonics, default_hz)
    if f0 <= 0:
        raise RuntimeError("Invalid fundamental frequency")

    n = max(64, samples)
    t = [float(i) / (float(n) * f0) for i in range(n)]
    i_w = [[0.0] * n for _ in range(n_windings)]
    v_w = [[0.0] * n for _ in range(n_windings)]

    sqrt2 = math.sqrt(2.0)
    for h in harmonics:
        order = as_int(h.get("order", 0), 0)
        if order <= 0:
            continue
        i_re = ensure_list(h.get("currents_real_a", []))
        i_im = ensure_list(h.get("currents_imag_a", []))
        v_re = ensure_list(h.get("voltages_real_v", []))
        v_im = ensure_list(h.get("voltages_imag_v", []))
        w_h = 2.0 * math.pi * f0 * float(order)

        for wi in range(n_windings):
            i_ph = complex(get_idx(i_re, wi, 0.0), get_idx(i_im, wi, 0.0))
            v_ph = complex(get_idx(v_re, wi, 0.0), get_idx(v_im, wi, 0.0))
            for ti, tt in enumerate(t):
                e = cmath.exp(1j * w_h * tt)
                i_w[wi][ti] += float((sqrt2 * i_ph * e).real)
                v_w[wi][ti] += float((sqrt2 * v_ph * e).real)

    return f0, t, i_w, v_w, len(harmonics)


def build_pm_operating_point(op_name, winding_names, f0, t, i_w, v_w, temperature_c):
    ex = []
    for wi, wname in enumerate(winding_names):
        ex.append(
            {
                "name": str(wname),
                "frequency": f0,
                "current": {"waveform": {"data": i_w[wi], "time": t}},
                "voltage": {"waveform": {"data": v_w[wi], "time": t}},
            }
        )
    return {
        "name": op_name,
        "conditions": {"ambientTemperature": temperature_c},
        "excitationsPerWinding": ex,
    }


def extract_losses(loss_data, winding_names):
    if not isinstance(loss_data, dict):
        raise RuntimeError("Invalid winding losses output")
    if isinstance(loss_data.get("data"), str) and "Exception:" in loss_data.get("data", ""):
        raise RuntimeError(loss_data["data"])

    n_w = len(winding_names)
    per = [0.0] * n_w

    per_w = loss_data.get("windingLossesPerWinding")
    if isinstance(per_w, dict):
        for wi, name in enumerate(winding_names):
            if name in per_w:
                per[wi] = as_float(per_w[name], 0.0)
        if all(v == 0.0 for v in per) and per_w:
            vals = list(per_w.values())
            for wi in range(min(n_w, len(vals))):
                per[wi] = as_float(vals[wi], 0.0)
    elif isinstance(per_w, list):
        for wi in range(min(n_w, len(per_w))):
            per[wi] = as_float(per_w[wi], 0.0)

    total = sum(per)
    return total, per


def estimate_fallback_score(op, n_windings):
    harmonics = normalize_harmonics(op.get("harmonics", []))
    per = [0.0] * n_windings
    for h in harmonics:
        i_re = ensure_list(h.get("currents_real_a", []))
        i_im = ensure_list(h.get("currents_imag_a", []))
        for wi in range(n_windings):
            re_i = get_idx(i_re, wi, 0.0)
            im_i = get_idx(i_im, wi, 0.0)
            per[wi] += re_i * re_i + im_i * im_i
    return sum(per), per


def score_operating_point(magnetic, op, winding_names, cfg):
    samples = clamp(as_int(cfg.get("waveform_samples", 128), 128), 64, 512)
    max_harm = as_int(cfg.get("max_harmonics_for_waveform", 0), 0)
    temperature_c = as_float(cfg.get("temperature_c", 25.0), 25.0)
    default_hz = as_float(cfg.get("default_frequency_hz", 100e3), 100e3)
    topology = str(cfg.get("topology", "2-switch forward") or "2-switch forward")

    f0, t, i_w, v_w, harmonics_used = build_waveforms_from_harmonics(
        op, len(winding_names), samples, max_harm, default_hz
    )
    op_name = str(op.get("name", "op"))
    op_pm = build_pm_operating_point(op_name, winding_names, f0, t, i_w, v_w, temperature_c)

    inputs = {
        "designRequirements": {
            "topology": topology,
            "magnetizingInductance": {"minimum": 1e-6, "nominal": 2e-6},
            "turnsRatios": [{"nominal": 1.0}],
        },
        "operatingPoints": [op_pm],
    }
    processed = pm.process_inputs(inputs)
    if isinstance(processed, dict) and isinstance(processed.get("data"), str) and "Exception:" in processed["data"]:
        raise RuntimeError(processed["data"])

    op_proc = processed.get("operatingPoints", [None])[0]
    if not isinstance(op_proc, dict):
        raise RuntimeError("process_inputs returned invalid operating point")

    loss_data = gov.ensure_dict(pm.calculate_winding_losses(magnetic, op_proc, temperature_c))
    total_w, per_w = extract_losses(loss_data, winding_names)
    return total_w, per_w, harmonics_used, "om_winding_losses"


def main():
    if len(sys.argv) < 2:
        print("Usage: python generate_om_prescreen_losses.py config.json", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]
    if not os.path.exists(config_path):
        print(f"ERROR: Config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    cfg = load_json(config_path)
    om_cfg_path = cfg.get("om_config_file", "om_viz_config.json")
    profile_path = cfg.get("excitation_profile_file", "om_excitation_profile.json")
    output_path = cfg.get("output_file", "om_prescreen_losses.json")

    if not os.path.exists(om_cfg_path):
        print(f"ERROR: OM config file not found: {om_cfg_path}", file=sys.stderr)
        sys.exit(1)
    if not os.path.exists(profile_path):
        print(f"ERROR: Excitation profile file not found: {profile_path}", file=sys.stderr)
        sys.exit(1)

    om_cfg = load_json(om_cfg_path)
    profile = load_json(profile_path)
    ops = ensure_list(profile.get("operating_points", []))
    if not ops:
        print("ERROR: Excitation profile has no operating points", file=sys.stderr)
        sys.exit(1)

    magnetic, wind_meta, _, _ = gov.build_magnetic_from_config(om_cfg)
    winding_names = []
    for i, w in enumerate(ensure_list(om_cfg.get("windings", []))):
        winding_names.append(str(w.get("name", f"winding_{i}")))
    if not winding_names:
        print("ERROR: OM config has no windings", file=sys.stderr)
        sys.exit(1)

    scores = []
    fallback_count = 0
    for idx, op in enumerate(ops, start=1):
        op_name = str(op.get("name", f"op_{idx}"))
        entry = {
            "index": idx,
            "name": op_name,
            "score_w": 0.0,
            "status": "ok",
            "loss_per_winding_w": [0.0] * len(winding_names),
            "harmonics_used": 0,
            "method": "om_winding_losses",
            "error": "",
        }
        try:
            score_w, per_w, harmonics_used, method = score_operating_point(magnetic, op, winding_names, cfg)
            entry["score_w"] = as_float(score_w, 0.0)
            entry["loss_per_winding_w"] = [as_float(v, 0.0) for v in per_w]
            entry["harmonics_used"] = as_int(harmonics_used, 0)
            entry["method"] = method
        except Exception as exc:
            fallback_count += 1
            score_est, per_est = estimate_fallback_score(op, len(winding_names))
            entry["score_w"] = as_float(score_est, 0.0)
            entry["loss_per_winding_w"] = [as_float(v, 0.0) for v in per_est]
            entry["status"] = "fallback_estimate"
            entry["method"] = "harmonic_current_energy"
            entry["error"] = str(exc)
        scores.append(entry)

    scores_sorted = sorted(scores, key=lambda x: x.get("score_w", 0.0), reverse=True)
    ranked_indices = [int(s.get("index", 0)) for s in scores_sorted if int(s.get("index", 0)) > 0]

    result = {
        "status": "OK",
        "total_operating_points": len(ops),
        "scored_operating_points": len(scores),
        "fallback_count": fallback_count,
        "ranked_indices": ranked_indices,
        "scores": scores_sorted,
        "winding_names": winding_names,
        "winding_mode": wind_meta.get("winding_mode", ""),
        "used_api_wind": bool(wind_meta.get("used_api_wind", False)),
        "api_wind_success": bool(wind_meta.get("api_wind_success", False)),
        "generator": {
            "script": "generate_om_prescreen_losses.py",
            "python": sys.executable,
            "waveform_samples": clamp(as_int(cfg.get("waveform_samples", 128), 128), 64, 512),
            "max_harmonics_for_waveform": as_int(cfg.get("max_harmonics_for_waveform", 0), 0),
        },
    }

    write_json(output_path, result)
    print("OK")


if __name__ == "__main__":
    main()
