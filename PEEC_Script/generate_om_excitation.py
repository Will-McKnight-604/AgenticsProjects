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

from om_shared import _log, as_float, as_list, clamp, import_pyopenmagnetics, TOPOLOGY_MAP

try:
    pm = import_pyopenmagnetics()
except Exception as exc:
    print(f"ImportError: {exc}", file=sys.stderr)
    print(f"Python executable: {sys.executable}", file=sys.stderr)
    print(f"Python path: {sys.path}", file=sys.stderr)
    sys.exit(1)


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

    # Handle case where MATLAB's jsonencode converts single-element arrays to scalars
    if isinstance(line_scales, (int, float)):
        line_scales = [line_scales]
    if isinstance(load_scales, (int, float)):
        load_scales = [load_scales]

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


def _resample_pwl(time_pts, data_pts, n_samples, period):
    """Resample piecewise-linear waveform to n_samples uniformly-spaced points.

    Args:
        time_pts: list of time breakpoints (monotonic, starting at 0)
        data_pts: list of values at each breakpoint
        n_samples: number of output samples
        period: T = 1/frequency

    Returns:
        list of n_samples uniformly-spaced values
    """
    if not time_pts or not data_pts or len(time_pts) < 2:
        return [0.0] * n_samples

    out = []
    j = 0  # index into PWL segments
    n_seg = len(time_pts) - 1
    for i in range(n_samples):
        t = float(i) / float(n_samples) * period
        # Advance to the correct segment
        while j < n_seg - 1 and time_pts[j + 1] <= t:
            j += 1
        # Interpolate
        t0, t1 = time_pts[j], time_pts[j + 1]
        d0, d1 = data_pts[j], data_pts[j + 1]
        dt = t1 - t0
        if dt > 0:
            frac = (t - t0) / dt
            frac = max(0.0, min(1.0, frac))
            out.append(d0 + frac * (d1 - d0))
        else:
            out.append(d1)
    return out


def _build_excitation_converter(cfg, line_scale, load_scale):
    """Build MAS converter dict from excitation config for a specific operating point.

    Scales Vin by line_scale and Iout by load_scale.
    """
    converter = cfg.get("converter", {})
    topology_results = cfg.get("topology_results", {})
    if not converter:
        return None, None

    vin_min = as_float(converter.get("vin_min"), 0)
    vin_max = as_float(converter.get("vin_max"), 0)
    if vin_min <= 0 or vin_max <= 0:
        return None, None

    topology_key = cfg.get("topology", "two_switch_forward")
    if topology_key not in TOPOLOGY_MAP:
        return None, None

    vd = as_float(converter.get("vd"), 0.5)
    fsw_khz = as_float(converter.get("fsw_khz"), 0)
    fsw_hz = as_float(cfg.get("frequency_hz"), fsw_khz * 1000.0)
    if fsw_hz <= 0:
        return None, None

    eff = as_float(converter.get("efficiency"), 90)
    if eff > 1:
        eff = eff / 100.0

    ripple = as_float(converter.get("max_ripple"), 30)
    if ripple > 1:
        ripple = ripple / 100.0

    max_duty = as_float(converter.get("max_duty"), 0)
    if max_duty > 1:
        max_duty = max_duty / 100.0

    vouts = converter.get("output_voltages")
    iouts = converter.get("output_currents")
    if not isinstance(vouts, list):
        vouts = [as_float(vouts if vouts is not None else converter.get("vout"), 12)]
    if not isinstance(iouts, list):
        iouts = [as_float(iouts if iouts is not None else converter.get("iout"), 5)]
    while len(iouts) < len(vouts):
        iouts.append(iouts[-1] if iouts else 1.0)
    vouts = [as_float(v) for v in vouts]
    iouts = [as_float(i) * load_scale for i in iouts]

    # Scale input voltage by line_scale — set both min and max to the scaled point
    vin_nom = (vin_min + vin_max) / 2.0
    vin_scaled = vin_nom * line_scale
    ambient = as_float(converter.get("ambient_temp"), 25)

    non_isolated = topology_key in ("buck", "boost")
    op = {"switchingFrequency": fsw_hz, "ambientTemperature": ambient}
    if non_isolated:
        op["outputVoltage"] = vouts[0]
        op["outputCurrent"] = iouts[0]
    else:
        op["outputVoltages"] = vouts
        op["outputCurrents"] = iouts

    mas_conv = {
        "inputVoltage": {"minimum": vin_scaled, "maximum": vin_scaled},
        "diodeVoltageDrop": vd,
        "currentRippleRatio": ripple,
        "efficiency": eff,
        "operatingPoints": [op],
    }

    if max_duty > 0:
        mas_conv["maximumDutyCycle"] = max_duty

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

        if topology_key == "single_switch_forward" and tr_list:
            n_secondaries = len(vouts)
            if len(tr_list) == n_secondaries:
                nd_np = as_float(topology_results.get("nd_np"), 1.0)
                tr_list.append(nd_np)

        if tr_list:
            mas_conv["desiredTurnsRatios"] = tr_list

        d_nom = as_float(topology_results.get("duty_nom"))
        d_worst = as_float(topology_results.get("duty_max_vin"))
        if d_nom > 0:
            if d_worst <= 0:
                d_worst = d_nom
            mas_conv["desiredDutyCycle"] = [[d_nom, d_worst]]

    # Normalize arrays
    for key in ("desiredTurnsRatios",):
        if key in mas_conv and not isinstance(mas_conv[key], list):
            mas_conv[key] = [mas_conv[key]]
    for op_item in mas_conv.get("operatingPoints", []):
        for key in ("outputVoltages", "outputCurrents"):
            if key in op_item and not isinstance(op_item[key], list):
                op_item[key] = [op_item[key]]

    return topology_key, mas_conv


def _get_topology_waveforms(cfg, line_scale, load_scale, n_windings, samples, frequency_hz):
    """Get topology-aware waveforms from pm.process_converter(), resampled to uniform samples.

    Returns:
        (i_waveforms, v_waveforms) — lists of lists, one per winding, each with `samples` points.
        Returns (None, None) if process_converter is not available or fails.
    """
    topology_key, mas_conv = _build_excitation_converter(cfg, line_scale, load_scale)
    if mas_conv is None:
        return None, None

    try:
        mas = pm.process_converter(topology_key, mas_conv, False)
    except Exception as exc:
        _log(f"[EXCITATION] process_converter failed for line={line_scale:.2f} load={load_scale:.2f}: {exc}")
        return None, None

    if isinstance(mas, dict) and "error" in mas:
        _log(f"[EXCITATION] process_converter error: {mas['error']}")
        return None, None

    ops = mas.get("operatingPoints", [])
    if not ops:
        return None, None

    # Use first operating point (we set min==max Vin for this specific condition)
    op = ops[0]
    excitations = op.get("excitationsPerWinding", [])

    period = 1.0 / frequency_hz
    i_waveforms = []
    v_waveforms = []

    for w_idx in range(n_windings):
        if w_idx < len(excitations):
            exc = excitations[w_idx]
            # Current waveform
            c_wf = exc.get("current", {}).get("waveform", {})
            c_time = c_wf.get("time", [])
            c_data = c_wf.get("data", [])
            if c_time and c_data:
                i_waveforms.append(_resample_pwl(c_time, c_data, samples, period))
            else:
                i_waveforms.append([0.0] * samples)

            # Voltage waveform
            v_wf = exc.get("voltage", {}).get("waveform", {})
            v_time = v_wf.get("time", [])
            v_data = v_wf.get("data", [])
            if v_time and v_data:
                v_waveforms.append(_resample_pwl(v_time, v_data, samples, period))
            else:
                v_waveforms.append([0.0] * samples)
        else:
            # More windings in excitation config than process_converter returned
            i_waveforms.append([0.0] * samples)
            v_waveforms.append([0.0] * samples)

    return i_waveforms, v_waveforms


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

    try:
        out = pm.process_inputs(inputs)
    except Exception as exc:
        return {"ok": False, "error": f"process_inputs failed: {exc}", "windings": []}
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

    # NEW: Get topology for waveform dispatch
    topology_key = cfg.get("topology", "two_switch_forward")
    if not isinstance(topology_key, str):
        topology_key = "two_switch_forward"
    topology_key = topology_key.lower().replace(" ", "_").replace("-", "_")

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

    # Check if topology-aware waveforms via process_converter are available
    has_converter = bool(cfg.get("converter"))
    if has_converter:
        _log(f"[EXCITATION] Converter data available — using process_converter() for topology-aware waveforms")
    else:
        _log(f"[EXCITATION] No converter data — using simplified analytical waveforms")

    for (line_scale, load_scale, conduction_mode) in op_grid:
        duty = estimate_duty(cfg, line_scale)
        if conduction_mode == "dcm":
            duty = clamp(duty * 0.7, 0.05, 0.42)

        i_waveforms = None
        v_waveforms = None

        # Try topology-aware waveforms from process_converter (CCM only — DCM not modeled by PyOM)
        if has_converter and conduction_mode != "dcm":
            i_waveforms, v_waveforms = _get_topology_waveforms(
                cfg, line_scale, load_scale, len(windings), samples, frequency_hz)
            if i_waveforms is not None:
                _log(f"[EXCITATION] process_converter OK for line={line_scale:.2f} load={load_scale:.2f}")

        # Fallback: simplified analytical waveforms
        if i_waveforms is None:
            i_waveforms = []
            v_waveforms = []
            for idx, w in enumerate(windings):
                base_i = as_float(w.get("rms_current_a", 0.0), 0.0)
                base_v = as_float(w.get("rms_voltage_v", 0.0), 0.0)
                phase = as_float(w.get("phase_deg", 0.0), 0.0)
                i_rms = abs(base_i) * load_scale
                v_rms = abs(base_v) * line_scale
                i_waveforms.append(generate_current_waveform(i_rms, duty, conduction_mode, phase, samples))
                v_waveforms.append(generate_voltage_waveform(v_rms, duty, idx, phase, samples))

        op_rms_currents = [rms(iw) for iw in i_waveforms]
        op_rms_voltages = [rms(vw) for vw in v_waveforms]

        i_harm_all = []
        v_harm_all = []
        for idx in range(len(windings)):
            i_harm_all.append(dft_harmonics(i_waveforms[idx], max_order))
            v_harm_all.append(dft_harmonics(v_waveforms[idx], max_order))

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

    waveform_source = "process_converter" if has_converter else "simplified_analytical"
    return {
        "status": "OK",
        "source": "om_converter_multi_topology",
        "waveform_source": waveform_source,
        "topology": topology_key,
        "topology_display": topology_key.replace("_", " ").title(),
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

