#!/usr/bin/env python3
"""
Generate converter-driven excitation profile for PEEC harmonic analysis.

This script creates harmonic current/voltage phasors for transformer windings
using a simplified two-switch-forward model (CCM/DCM) and OpenMagnetics
waveform processing helpers.

Usage:
    python generate_om_excitation.py om_excitation_config.json
"""

import cmath
import hashlib
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


def clamp(value, lo, hi):
    return max(lo, min(hi, value))


def as_float(value, default=0.0):
    try:
        return float(value)
    except Exception:
        return float(default)


def normalize_source_mode(value):
    s = str(value or "converter").strip().lower()
    if s.startswith("manual"):
        return "manual"
    return "converter"


def normalize_conduction_mode(value):
    s = str(value or "ccm+dcm").strip().lower()
    if s in ("ccm", "dcm", "ccm+dcm"):
        return s
    if "ccm" in s and "dcm" in s:
        return "ccm+dcm"
    if "dcm" in s:
        return "dcm"
    return "ccm"


def normalize_sweep_mode(value):
    s = str(value or "grid").strip().lower()
    if s in ("nominal", "corners", "grid"):
        return s
    return "grid"


def normalize_duty_mode(value):
    s = str(value or "derived").strip().lower()
    if s in ("derived", "manual"):
        return s
    return "derived"


def periodic_shift(values, shift_samples):
    n = len(values)
    if n == 0:
        return values
    s = int(shift_samples) % n
    if s == 0:
        return list(values)
    return list(values[-s:] + values[:-s])


def rms(values):
    if not values:
        return 0.0
    acc = 0.0
    for v in values:
        acc += v * v
    return math.sqrt(acc / float(len(values)))


def estimate_duty(cfg, line_scale):
    duty_mode = normalize_duty_mode(cfg.get("duty_mode", "derived"))
    if duty_mode == "manual":
        return clamp(as_float(cfg.get("manual_duty", 0.40), 0.40), 0.05, 0.49)

    windings = cfg.get("windings", []) or []
    if len(windings) < 2:
        return 0.40

    wp = windings[0]
    ws = windings[1]
    vp = abs(as_float(wp.get("rms_voltage_v", 0.0), 0.0)) * line_scale
    vs = abs(as_float(ws.get("rms_voltage_v", 0.0), 0.0)) * line_scale
    np_ = max(1.0, as_float(wp.get("n_turns", 1), 1.0))
    ns_ = max(1.0, as_float(ws.get("n_turns", 1), 1.0))

    if vp > 1e-9 and vs > 1e-9:
        duty = (vs / vp) * (np_ / ns_)
        return clamp(duty, 0.08, 0.48)
    return 0.40


def build_grid(cfg):
    sweep_mode = normalize_sweep_mode(cfg.get("sweep_mode", "grid"))
    line_scales = cfg.get("line_scales", [1.0]) or [1.0]
    load_scales = cfg.get("load_scales", [1.0]) or [1.0]

    line_scales = [as_float(v, 1.0) for v in line_scales]
    load_scales = [as_float(v, 1.0) for v in load_scales]
    line_scales = sorted(set(line_scales))
    load_scales = sorted(set(load_scales))
    if not line_scales:
        line_scales = [1.0]
    if not load_scales:
        load_scales = [1.0]

    mode = normalize_conduction_mode(cfg.get("conduction_mode", "ccm+dcm"))
    if mode == "ccm+dcm":
        conduction_modes = ["ccm", "dcm"]
    else:
        conduction_modes = [mode]

    points = []
    if sweep_mode == "nominal":
        points = [(1.0, 1.0)]
    elif sweep_mode == "corners":
        lmin = min(line_scales)
        lmax = max(line_scales)
        omin = min(load_scales)
        omax = max(load_scales)
        points = [(lmin, omin), (lmin, omax), (lmax, omin), (lmax, omax)]
    else:
        for ls in line_scales:
            for os_ in load_scales:
                points.append((ls, os_))

    ops = []
    for ls, os_ in points:
        for cmode in conduction_modes:
            ops.append((ls, os_, cmode))
    return ops


def generate_current_waveform(rms_target, duty, conduction_mode, phase_deg, samples):
    rms_target = abs(as_float(rms_target, 0.0))
    duty = clamp(as_float(duty, 0.4), 0.02, 0.98)
    phase_deg = as_float(phase_deg, 0.0)

    if rms_target <= 0.0:
        return [0.0] * samples

    values = [0.0] * samples
    d_count = max(1, int(round(duty * samples)))
    d_count = min(samples, d_count)

    if conduction_mode == "dcm":
        i_peak = rms_target * math.sqrt(3.0 / max(duty, 1e-9))
        for n in range(d_count):
            u = float(n) / float(max(d_count - 1, 1))
            tri = 1.0 - abs(2.0 * u - 1.0)
            values[n] = i_peak * tri
    else:
        ripple_ratio = 0.25
        i_avg_on = rms_target / math.sqrt(max(duty * (1.0 + ripple_ratio * ripple_ratio / 3.0), 1e-12))
        for n in range(d_count):
            u = float(n) / float(max(d_count - 1, 1))
            values[n] = i_avg_on * (1.0 + ripple_ratio * (2.0 * u - 1.0))

    shift = int(round((phase_deg / 360.0) * samples))
    return periodic_shift(values, shift)


def generate_voltage_waveform(rms_target, duty, winding_index, phase_deg, samples):
    duty = clamp(as_float(duty, 0.4), 0.02, 0.98)
    phase_deg = as_float(phase_deg, 0.0)
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
        sign = -1.0
        for n in range(d_count):
            values[n] = sign
        for n in range(d_count, samples):
            values[n] = 0.0

    base_rms = rms(values)
    if target_rms > 0 and base_rms > 1e-12:
        scale = target_rms / base_rms
        values = [scale * v for v in values]

    shift = int(round((phase_deg / 360.0) * samples))
    return periodic_shift(values, shift)


def dft_harmonics(values, max_order):
    n = len(values)
    if n <= 0:
        return []

    harmonics = []
    for k in range(1, max_order + 1):
        coeff = 0.0 + 0.0j
        for idx, x in enumerate(values):
            ang = -2.0 * math.pi * k * idx / float(n)
            coeff += x * complex(math.cos(ang), math.sin(ang))
        coeff /= float(n)
        amp_rms = math.sqrt(2.0) * abs(coeff)
        phase_deg = math.degrees(cmath.phase(coeff))
        harmonics.append((amp_rms, phase_deg))
    return harmonics


def select_harmonic_orders(curr_harmonics_per_winding, target_pct, small_pct, small_consecutive):
    if not curr_harmonics_per_winding:
        return [1]

    n_w = len(curr_harmonics_per_winding)
    max_order = len(curr_harmonics_per_winding[0])
    if max_order <= 0:
        return [1]

    total_energy = 0.0
    for k in range(max_order):
        for w in range(n_w):
            total_energy += curr_harmonics_per_winding[w][k][0] ** 2
    if total_energy <= 1e-18:
        return [1]

    thresholds = []
    for w in range(n_w):
        fundamental = curr_harmonics_per_winding[w][0][0] if len(curr_harmonics_per_winding[w]) >= 1 else 0.0
        thresholds.append(fundamental * small_pct / 100.0)

    keep = []
    cumulative = 0.0
    consecutive_small = 0
    target = clamp(target_pct, 50.0, 100.0) / 100.0

    for k in range(max_order):
        order = k + 1
        energy_k = 0.0
        all_small = True
        for w in range(n_w):
            amp = curr_harmonics_per_winding[w][k][0]
            energy_k += amp ** 2
            if amp >= thresholds[w]:
                all_small = False
        cumulative += energy_k
        keep.append(order)

        if all_small:
            consecutive_small += 1
        else:
            consecutive_small = 0

        if cumulative / total_energy >= target and consecutive_small >= max(1, int(small_consecutive)):
            break

    if 1 not in keep:
        keep.insert(0, 1)
    return sorted(set(keep))


def build_processed_summary_with_pm(op_name, frequency_hz, windings, wave_t, i_waveforms, v_waveforms):
    inputs = {
        "designRequirements": {
            "topology": "2-switch forward",
            "magnetizingInductance": {"minimum": 1e-6, "nominal": 2e-6},
            "turnsRatios": [{"nominal": 1.0}],
        },
        "operatingPoints": [
            {
                "name": op_name,
                "conditions": {"ambientTemperature": 25},
                "excitationsPerWinding": [],
            }
        ],
    }

    for idx, w in enumerate(windings):
        inputs["operatingPoints"][0]["excitationsPerWinding"].append(
            {
                "name": str(w.get("name", f"W{idx+1}")),
                "frequency": frequency_hz,
                "current": {"waveform": {"data": i_waveforms[idx], "time": wave_t}},
                "voltage": {"waveform": {"data": v_waveforms[idx], "time": wave_t}},
            }
        )

    out = pm.process_inputs(inputs)
    if isinstance(out, dict) and "data" in out and isinstance(out["data"], str) and "Exception:" in out["data"]:
        return {"ok": False, "error": out["data"], "windings": []}

    summary = {"ok": True, "error": "", "windings": []}
    try:
        ex = out["operatingPoints"][0]["excitationsPerWinding"]
        for item in ex:
            cur_proc = item.get("current", {}).get("processed", {}) or {}
            vol_proc = item.get("voltage", {}).get("processed", {}) or {}
            summary["windings"].append(
                {
                    "name": item.get("name", ""),
                    "current_rms": as_float(cur_proc.get("rms", 0.0), 0.0),
                    "current_thd": as_float(cur_proc.get("thd", 0.0), 0.0),
                    "current_duty": as_float(cur_proc.get("dutyCycle", 0.0), 0.0),
                    "voltage_rms": as_float(vol_proc.get("rms", 0.0), 0.0),
                    "voltage_thd": as_float(vol_proc.get("thd", 0.0), 0.0),
                }
            )
    except Exception as exc:
        summary = {"ok": False, "error": str(exc), "windings": []}
    return summary


def build_excitation(cfg):
    source_mode = normalize_source_mode(cfg.get("source_mode", "converter"))
    if source_mode != "converter":
        return {"status": "ERROR", "error": "Only converter source mode is supported in this generator."}

    frequency_hz = as_float(cfg.get("frequency_hz", 100e3), 100e3)
    windings = cfg.get("windings", []) or []
    if not windings:
        return {"status": "ERROR", "error": "Config has no windings."}

    samples = int(as_float(cfg.get("samples_per_period", 1024), 1024))
    samples = max(128, min(4096, samples))
    max_order = int(as_float(cfg.get("harmonic_max_order", 60), 60))
    max_order = max(1, min(200, max_order))
    target_pct = as_float(cfg.get("harmonic_energy_pct", 99.5), 99.5)
    small_pct = as_float(cfg.get("small_harmonic_pct", 1.0), 1.0)
    small_consecutive = int(as_float(cfg.get("small_harmonic_consecutive", 5), 5))

    time_vec = [float(i) / float(samples) / frequency_hz for i in range(samples)]
    sweep_mode = normalize_sweep_mode(cfg.get("sweep_mode", "grid"))
    conduction_mode_cfg = normalize_conduction_mode(cfg.get("conduction_mode", "ccm+dcm"))
    op_grid = build_grid(cfg)
    operating_points = []

    for (line_scale, load_scale, conduction_mode) in op_grid:
        duty = estimate_duty(cfg, line_scale)
        if conduction_mode == "dcm":
            duty = clamp(duty * 0.7, 0.05, 0.42)

        i_waveforms = []
        v_waveforms = []
        op_rms_currents = []
        op_rms_voltages = []
        i_harm_all = []
        v_harm_all = []

        for idx, w in enumerate(windings):
            base_i = as_float(w.get("rms_current_a", 0.0), 0.0)
            base_v = as_float(w.get("rms_voltage_v", 0.0), 0.0)
            phase = as_float(w.get("phase_deg", 0.0), 0.0)

            i_rms = abs(base_i) * load_scale
            v_rms = abs(base_v) * line_scale
            op_rms_currents.append(i_rms)
            op_rms_voltages.append(v_rms)

            iw = generate_current_waveform(i_rms, duty, conduction_mode, phase, samples)
            vw = generate_voltage_waveform(v_rms, duty, idx, phase, samples)
            i_waveforms.append(iw)
            v_waveforms.append(vw)

            i_harm_all.append(dft_harmonics(iw, max_order))
            v_harm_all.append(dft_harmonics(vw, max_order))

        keep_orders = select_harmonic_orders(i_harm_all, target_pct, small_pct, small_consecutive)
        harmonics = []
        for order in keep_orders:
            k = order - 1
            c_re = []
            c_im = []
            v_re = []
            v_im = []
            for w_idx in range(len(windings)):
                i_amp, i_phase = i_harm_all[w_idx][k]
                v_amp, v_phase = v_harm_all[w_idx][k]
                ic = cmath.rect(i_amp, math.radians(i_phase))
                vc = cmath.rect(v_amp, math.radians(v_phase))
                c_re.append(ic.real)
                c_im.append(ic.imag)
                v_re.append(vc.real)
                v_im.append(vc.imag)

            harmonics.append(
                {
                    "order": order,
                    "frequency_hz": frequency_hz * order,
                    "currents_real_a": c_re,
                    "currents_imag_a": c_im,
                    "voltages_real_v": v_re,
                    "voltages_imag_v": v_im,
                }
            )

        op_name = f"line_{line_scale:.2f}_load_{load_scale:.2f}_{conduction_mode}"
        proc_summary = build_processed_summary_with_pm(op_name, frequency_hz, windings, time_vec, i_waveforms, v_waveforms)

        operating_points.append(
            {
                "name": op_name,
                "line_scale": line_scale,
                "load_scale": load_scale,
                "conduction_mode": conduction_mode,
                "frequency_hz": frequency_hz,
                "duty": duty,
                "rms_currents_a": op_rms_currents,
                "rms_voltages_v": op_rms_voltages,
                "harmonic_count": len(harmonics),
                "harmonics": harmonics,
                "processed_summary": proc_summary,
            }
        )

    return {
        "status": "OK",
        "source": "om_converter_2switch_forward",
        "topology": "two_switch_forward",
        "sweep_mode": sweep_mode,
        "conduction_mode": conduction_mode_cfg,
        "frequency_hz": frequency_hz,
        "harmonic_energy_pct": target_pct,
        "harmonic_max_order": max_order,
        "operating_points": operating_points,
    }


def compute_hash(cfg):
    filtered = dict(cfg)
    for k in ["output_file", "cache_file", "use_cache", "use_import", "import_file"]:
        if k in filtered:
            del filtered[k]
    payload = json.dumps(filtered, sort_keys=True, separators=(",", ":"))
    return hashlib.sha1(payload.encode("utf-8")).hexdigest()


def try_load_json(path):
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return None


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh)


def main():
    if len(sys.argv) < 2:
        print("Usage: python generate_om_excitation.py config.json", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]
    if not os.path.exists(config_path):
        print(f"ERROR: Config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    with open(config_path, "r", encoding="utf-8") as fh:
        cfg = json.load(fh)

    out_path = cfg.get("output_file", "om_excitation_profile.json")
    cache_path = cfg.get("cache_file", "om_excitation_cache.json")
    use_cache = bool(cfg.get("use_cache", True))
    use_import = bool(cfg.get("use_import", False))
    import_file = cfg.get("import_file", "")
    cfg_hash = compute_hash(cfg)

    if use_import:
        imported = try_load_json(import_file)
        if imported and isinstance(imported, dict) and imported.get("status") == "OK":
            imported["loaded_from_import"] = True
            imported["config_hash"] = cfg_hash
            write_json(out_path, imported)
            print("OK")
            return

    if use_cache:
        cached = try_load_json(cache_path)
        if cached and isinstance(cached, dict) and cached.get("config_hash") == cfg_hash and cached.get("status") == "OK":
            write_json(out_path, cached)
            print("OK")
            return

    result = build_excitation(cfg)
    result["config_hash"] = cfg_hash
    result["generator"] = {
        "script": "generate_om_excitation.py",
        "python": sys.executable,
        "pyopenmagnetics_available": True,
    }

    write_json(out_path, result)
    if use_cache and result.get("status") == "OK":
        write_json(cache_path, result)

    if result.get("status") == "OK":
        print("OK")
        return

    print(f"ERROR: {result.get('error', 'unknown error')}", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()

