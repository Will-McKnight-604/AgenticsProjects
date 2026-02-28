#!/usr/bin/env python3
"""
Forward-family converter waveform generators.

Ported from MKF C++ source:
  - MKF-main/src/converter_models/TwoSwitchForward.cpp
  - MKF-main/src/converter_models/SingleSwitchForward.cpp
  - MKF-main/src/converter_models/ActiveClampForward.cpp
  - MKF-main/src/processors/Inputs.cpp  (create_waveform)

Each function generates per-winding voltage/current waveforms in piecewise-linear
(time, data) format, with CCM/DCM detection and multi-output support.

Output format per operating point:
  {
    "label": "Nom. input volt.",
    "conditions": {"inputVoltage": <vin>},
    "excitationsPerWinding": [
      {
        "name": "Primary",
        "frequency": <fsw>,
        "voltage": {"waveform": {"time": [...], "data": [...]}},
        "current": {"waveform": {"time": [...], "data": [...]}}
      },
      ...
    ]
  }
"""

import math


# ---------------------------------------------------------------------------
# Standard waveform constructors (ported from Inputs::create_waveform)
# ---------------------------------------------------------------------------

def _make_flyback_primary(peak_to_peak, frequency, duty_cycle, offset, dead_time=0):
    """
    FLYBACK_PRIMARY waveform: ramp-up during on-time, zero during off-time.

    C++ reference (Inputs.cpp line 535-541):
        data = {0, min, max, 0, 0}
        time = {0, 0,   dc, dc, period}
    where min = offset, max = peakToPeak + offset.
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    v_min = offset
    v_max = peak_to_peak + offset
    data = [0.0, v_min, v_max, 0.0, 0.0]
    time = [0.0, 0.0, dc, dc, period]
    return {"time": time, "data": data}


def _make_flyback_secondary_with_deadtime(peak_to_peak, frequency, duty_cycle, offset, dead_time):
    """
    FLYBACK_SECONDARY_WITH_DEADTIME waveform: zero during on-time, ramp-down
    during off-time, zero during dead-time.

    C++ reference (Inputs.cpp line 551-557):
        data = {0, 0, max, min, 0, 0}
        time = {0, dc, dc, period-deadTime, period-deadTime, period}
    where min = offset, max = peakToPeak + offset.
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    v_min = offset
    v_max = peak_to_peak + offset
    data = [0.0, 0.0, v_max, v_min, 0.0, 0.0]
    time = [0.0, dc, dc, period - dead_time, period - dead_time, period]
    return {"time": time, "data": data}


def _make_rectangular_with_deadtime(peak_to_peak, frequency, duty_cycle, offset, dead_time):
    """
    RECTANGULAR_WITH_DEADTIME waveform.

    C++ reference (Inputs.cpp line 473-479):
        max = peakToPeak * (1 - dutyCycle) + offset
        min = -peakToPeak * dutyCycle + offset
        data = {0, max, max, min, min, 0, 0}
        time = {0, 0, dc, dc, period-deadTime, period-deadTime, period}
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    v_max = peak_to_peak * (1.0 - duty_cycle) + offset
    v_min = -peak_to_peak * duty_cycle + offset
    data = [0.0, v_max, v_max, v_min, v_min, 0.0, 0.0]
    time = [0.0, 0.0, dc, dc, period - dead_time, period - dead_time, period]
    return {"time": time, "data": data}


# ---------------------------------------------------------------------------
# Two-Switch Forward
# ---------------------------------------------------------------------------

def generate_two_switch_forward_waveforms(
    input_voltage,
    output_voltages,
    output_currents,
    turns_ratios,
    magnetizing_inductance,
    switching_frequency,
    diode_voltage_drop,
    duty_cycle=0.45,
    current_ripple_ratio=0.4,
    output_inductances=None,
    ambient_temperature=25.0,
    label=None,
):
    """
    Generate per-winding waveforms for a Two-Switch Forward converter at one
    input-voltage operating condition.

    Ported from TwoSwitchForward::process_operating_points_for_input_voltage()
    in TwoSwitchForward.cpp.

    Parameters
    ----------
    input_voltage : float
        DC bus voltage for this operating point (V).
    output_voltages : list[float]
        Per-secondary output voltages (V).
    output_currents : list[float]
        Per-secondary load currents (A).
    turns_ratios : list[float]
        Np/Ns for each secondary.  Length must equal len(output_voltages).
    magnetizing_inductance : float
        Magnetizing inductance Lm (H).
    switching_frequency : float
        Switching frequency (Hz).
    diode_voltage_drop : float
        Rectifier diode forward voltage (V).
    duty_cycle : float
        Maximum duty cycle (default 0.45).
    current_ripple_ratio : float
        Output current ripple as fraction of Iout (default 0.4).
    output_inductances : list[float] or None
        Per-secondary output filter inductances (H).  If None, the function
        uses only the main output inductance for DCM detection (set to a
        large value to force CCM, or pass an explicit list).
    ambient_temperature : float
        Ambient temperature in degrees C (default 25).
    label : str or None
        Operating-point label, e.g. "Nom. input volt.".

    Returns
    -------
    dict
        Operating point with excitationsPerWinding list.
    """
    n_sec = len(output_voltages)
    if len(turns_ratios) != n_sec:
        raise ValueError(
            f"turns_ratios length ({len(turns_ratios)}) must match "
            f"output_voltages length ({n_sec})"
        )

    vin = input_voltage
    fsw = switching_frequency
    vd = diode_voltage_drop
    lm = magnetizing_inductance
    period = 1.0 / fsw

    main_vout = output_voltages[0]
    main_iout = output_currents[0]
    main_n = turns_ratios[0]

    # Main output inductance (for DCM check)
    if output_inductances is not None and len(output_inductances) > 0:
        main_lout = output_inductances[0]
    else:
        # Compute from duty_cycle / ripple_ratio approximation
        t_on = duty_cycle / fsw
        main_lout = (vin / main_n - vd - main_vout) * t_on / current_ripple_ratio
        if main_lout <= 0:
            main_lout = 1e-3  # fallback

    # ---- Timing ----
    t1 = (period / 2.0) * (main_vout + vd) / (vin / main_n)
    if t1 > period / 2.0:
        raise ValueError(
            f"t1={t1:.3e} > period/2={period/2:.3e}: wrong topology configuration"
        )

    # ---- Magnetization current ----
    mag_current = vin * t1 / lm
    min_pri = -mag_current / 2.0
    max_pri = mag_current / 2.0

    # ---- Secondary currents (CCM assumption) ----
    min_sec = []
    max_sec = []
    for si in range(n_sec):
        ripple = current_ripple_ratio * output_currents[si]
        i_min = output_currents[si] - ripple / 2.0
        i_max = output_currents[si] + ripple / 2.0
        min_sec.append(i_min)
        max_sec.append(i_max)
        min_pri += i_min / turns_ratios[si]
        max_pri += i_max / turns_ratios[si]

    # ---- CCM / DCM detection ----
    is_dcm = min_pri < 0
    if is_dcm:
        t1 = math.sqrt(
            2.0 * main_iout * main_lout * (main_vout + vd)
            / (fsw * (vin / main_n - vd - main_vout) * (vin / main_n))
        )
        if t1 > period / 2.0:
            raise ValueError(
                f"DCM t1={t1:.3e} > period/2={period/2:.3e}: wrong topology configuration"
            )
        min_pri = 0.0
        max_pri = mag_current
        for si in range(n_sec):
            ripple = current_ripple_ratio * output_currents[si]
            min_sec[si] = 0.0
            max_sec[si] = ripple
            min_pri += min_sec[si] / turns_ratios[si]
            max_pri += max_sec[si] / turns_ratios[si]

    # ---- Primary-side transformer quantities ----
    min_pri_t1 = min_pri        # current at start of t1
    max_pri_t1 = max_pri        # current at end of t1
    min_pri_volt = -(vin + 2.0 * vd)   # voltage during demagnetization
    max_pri_volt = vin                  # voltage during on-time

    min_pri_td = 0.0            # current during demagnetization (mag only)
    max_pri_td = mag_current

    td = t1                     # demagnetization time = t1 for two-switch forward
    dead_time = period - t1 - td

    # ---- Build primary waveforms ----
    if not is_dcm:
        # CCM primary current: 7-point waveform
        pri_current = {
            "time": [0.0, 0.0, t1, t1, t1 + td, period, period],
            "data": [
                0.0,
                min_pri_t1,
                max_pri_t1,
                max_pri_td,
                min_pri_td,
                0.0,
                0.0,
            ],
        }
    else:
        # DCM primary current: 4-point waveform
        pri_current = {
            "time": [0.0, t1, t1, period],
            "data": [min_pri_t1, max_pri_t1, 0.0, 0.0],
        }

    # Primary voltage: 7-point waveform (same for CCM and DCM)
    pri_voltage = {
        "time": [0.0, 0.0, t1, t1, t1 + td, t1 + td, period],
        "data": [
            0.0,
            max_pri_volt,
            max_pri_volt,
            min_pri_volt,
            min_pri_volt,
            0.0,
            0.0,
        ],
    }

    excitations = [
        {
            "name": "Primary",
            "frequency": fsw,
            "voltage": {"waveform": pri_voltage},
            "current": {"waveform": pri_current},
        }
    ]

    # ---- Secondary waveforms ----
    for si in range(n_sec):
        sec_pp = max_sec[si] - min_sec[si]
        sec_v_min = -(vin + 2.0 * vd) / turns_ratios[si]
        sec_v_max = vin / turns_ratios[si]
        sec_v_pp = sec_v_max - sec_v_min
        sec_v_offset = sec_v_max + sec_v_min

        sec_current_wf = _make_flyback_primary(
            sec_pp, fsw, duty_cycle, min_sec[si], 0.0
        )
        sec_voltage_wf = _make_rectangular_with_deadtime(
            sec_v_pp, fsw, duty_cycle, sec_v_offset, dead_time
        )

        excitations.append(
            {
                "name": f"Secondary {si}",
                "frequency": fsw,
                "voltage": {"waveform": sec_voltage_wf},
                "current": {"waveform": sec_current_wf},
            }
        )

    return {
        "label": label or "Operating point",
        "conditions": {
            "inputVoltage": vin,
            "ambientTemperature": ambient_temperature,
        },
        "excitationsPerWinding": excitations,
    }


# ---------------------------------------------------------------------------
# Single-Switch Forward
# ---------------------------------------------------------------------------

def generate_single_switch_forward_waveforms(
    input_voltage,
    output_voltages,
    output_currents,
    turns_ratios,
    magnetizing_inductance,
    switching_frequency,
    diode_voltage_drop,
    duty_cycle=0.45,
    current_ripple_ratio=0.4,
    output_inductances=None,
    ambient_temperature=25.0,
    label=None,
):
    """
    Generate per-winding waveforms for a Single-Switch Forward converter.

    Ported from SingleSwitchForward::process_operating_points_for_input_voltage()
    in SingleSwitchForward.cpp.

    IMPORTANT: For Single-Switch Forward, turns_ratios[0] is the demagnetization
    winding ratio (typically 1.0 for Ndemag = Npri), and turns_ratios[1:] are the
    secondary winding ratios (Np/Ns).  This matches the C++ convention.

    The output has windings in order: [Primary, Demagnetization, Secondary 0, Secondary 1, ...].

    Parameters
    ----------
    input_voltage : float
        DC bus voltage (V).
    output_voltages : list[float]
        Per-secondary output voltages (V).  Does NOT include demag winding.
    output_currents : list[float]
        Per-secondary load currents (A).  Does NOT include demag winding.
    turns_ratios : list[float]
        turns_ratios[0] = Np/Ndemag (typically 1.0).
        turns_ratios[1..N] = Np/Ns for each secondary.
        Length must be len(output_voltages) + 1.
    magnetizing_inductance : float
        Magnetizing inductance Lm (H).
    switching_frequency : float
        Switching frequency (Hz).
    diode_voltage_drop : float
        Rectifier diode forward voltage (V).
    duty_cycle : float
        Maximum duty cycle (default 0.45).
    current_ripple_ratio : float
        Output current ripple fraction (default 0.4).
    output_inductances : list[float] or None
        Per-secondary output filter inductances (H).
    ambient_temperature : float
        Ambient temperature (C).
    label : str or None
        Operating-point label.

    Returns
    -------
    dict
        Operating point with excitationsPerWinding list.
    """
    n_out = len(output_voltages)
    if len(turns_ratios) != n_out + 1:
        raise ValueError(
            f"turns_ratios length ({len(turns_ratios)}) must be "
            f"len(output_voltages)+1 = {n_out + 1} "
            f"(first element is demagnetization winding ratio)"
        )

    vin = input_voltage
    fsw = switching_frequency
    vd = diode_voltage_drop
    lm = magnetizing_inductance
    period = 1.0 / fsw

    main_vout = output_voltages[0]
    main_iout = output_currents[0]
    main_n = turns_ratios[1]  # first secondary ratio (index 1, skipping demag)

    # Main output inductance for DCM check
    if output_inductances is not None and len(output_inductances) > 0:
        main_lout = output_inductances[0]
    else:
        t_on = duty_cycle / fsw
        main_lout = (vin / main_n - vd - main_vout) * t_on / current_ripple_ratio
        if main_lout <= 0:
            main_lout = 1e-3

    # ---- Timing (CCM assumption) ----
    t1 = (period / 2.0) * (main_vout + vd) / (vin / main_n)
    if t1 > period / 2.0:
        raise ValueError(
            f"t1={t1:.3e} > period/2: wrong topology configuration"
        )

    # ---- Magnetization current ----
    mag_current = vin * t1 / lm
    min_pri = -mag_current / 2.0
    max_pri = mag_current / 2.0

    # ---- Secondary currents (CCM) ----
    min_sec = []
    max_sec = []
    for si in range(n_out):
        ripple = current_ripple_ratio * output_currents[si]
        i_min = output_currents[si] - ripple / 2.0
        i_max = output_currents[si] + ripple / 2.0
        min_sec.append(i_min)
        max_sec.append(i_max)
        tr_idx = 1 + si  # skip demag winding ratio
        min_pri += i_min / turns_ratios[tr_idx]
        max_pri += i_max / turns_ratios[tr_idx]

    # ---- CCM / DCM ----
    is_dcm = min_pri < 0
    if is_dcm:
        t1 = math.sqrt(
            2.0 * main_iout * main_lout * (main_vout + vd)
            / (fsw * (vin / main_n - vd - main_vout) * (vin / main_n))
        )
        if t1 > period / 2.0:
            raise ValueError(
                f"DCM t1={t1:.3e} > period/2: wrong topology configuration"
            )
        min_pri = 0.0
        max_pri = mag_current
        for si in range(n_out):
            ripple = current_ripple_ratio * output_currents[si]
            min_sec[si] = 0.0
            max_sec[si] = ripple
            tr_idx = 1 + si
            min_pri += min_sec[si] / turns_ratios[tr_idx]
            max_pri += max_sec[si] / turns_ratios[tr_idx]

    # ---- Dead time for single-switch forward: td = t1, deadTime = T - 2*t1 ----
    dead_time = period - t1 * 2.0

    # ---- Primary winding ----
    # C++ uses FLYBACK_PRIMARY for current and RECTANGULAR_WITH_DEADTIME for voltage
    pri_i_pp = max_pri - min_pri
    pri_v_pp = 2.0 * vin  # voltage swings from +Vin to -Vin
    pri_current_wf = _make_flyback_primary(
        pri_i_pp, fsw, duty_cycle, min_pri, dead_time
    )
    pri_voltage_wf = _make_rectangular_with_deadtime(
        pri_v_pp, fsw, duty_cycle, 0.0, dead_time
    )

    excitations = [
        {
            "name": "Primary",
            "frequency": fsw,
            "voltage": {"waveform": pri_voltage_wf},
            "current": {"waveform": pri_current_wf},
        }
    ]

    # ---- Demagnetization winding ----
    # C++ uses FLYBACK_SECONDARY_WITH_DEADTIME for current,
    # RECTANGULAR_WITH_DEADTIME for voltage.
    # peakToPeak = magnetizationCurrent, offset = minimumPrimaryCurrent
    demag_current_wf = _make_flyback_secondary_with_deadtime(
        mag_current, fsw, duty_cycle, min_pri, dead_time
    )
    demag_v_pp = 2.0 * vin
    demag_voltage_wf = _make_rectangular_with_deadtime(
        demag_v_pp, fsw, duty_cycle, 0.0, dead_time
    )

    excitations.append(
        {
            "name": "Demagnetization winding",
            "frequency": fsw,
            "voltage": {"waveform": demag_voltage_wf},
            "current": {"waveform": demag_current_wf},
        }
    )

    # ---- Secondary windings ----
    for si in range(n_out):
        sec_pp = max_sec[si] - min_sec[si]
        tr_idx = 1 + si
        sec_v_min = -(vin + vd) / turns_ratios[tr_idx]
        sec_v_max = vin / turns_ratios[tr_idx]
        sec_v_pp = sec_v_max - sec_v_min
        sec_v_offset = sec_v_max + sec_v_min

        sec_current_wf = _make_flyback_primary(
            sec_pp, fsw, duty_cycle, min_sec[si], 0.0
        )
        sec_voltage_wf = _make_rectangular_with_deadtime(
            sec_v_pp, fsw, duty_cycle, sec_v_offset, dead_time
        )

        excitations.append(
            {
                "name": f"Secondary {si}",
                "frequency": fsw,
                "voltage": {"waveform": sec_voltage_wf},
                "current": {"waveform": sec_current_wf},
            }
        )

    return {
        "label": label or "Operating point",
        "conditions": {
            "inputVoltage": vin,
            "ambientTemperature": ambient_temperature,
        },
        "excitationsPerWinding": excitations,
    }


# ---------------------------------------------------------------------------
# Active Clamp Forward
# ---------------------------------------------------------------------------

def generate_active_clamp_forward_waveforms(
    input_voltage,
    output_voltages,
    output_currents,
    turns_ratios,
    magnetizing_inductance,
    switching_frequency,
    diode_voltage_drop,
    duty_cycle=0.45,
    current_ripple_ratio=0.4,
    output_inductances=None,
    ambient_temperature=25.0,
    label=None,
):
    """
    Generate per-winding waveforms for an Active Clamp Forward converter.

    Ported from ActiveClampForward::process_operating_points_for_input_voltage()
    in ActiveClampForward.cpp.

    The Active Clamp topology differs from Two-Switch Forward in two ways:
    1. The demagnetization voltage is -Vclamp (not -(Vin + 2*Vd)).
       Vclamp = t1 * fsw / (1 - t1 * fsw) * Vin
    2. The primary current waveform is a 4-point piecewise linear (always),
       and the primary voltage differs between CCM (5-point) and DCM (7-point).
    3. Dead time is 0 in CCM; computed in DCM.

    Parameters
    ----------
    input_voltage : float
        DC bus voltage (V).
    output_voltages : list[float]
        Per-secondary output voltages (V).
    output_currents : list[float]
        Per-secondary load currents (A).
    turns_ratios : list[float]
        Np/Ns for each secondary.  Length must equal len(output_voltages).
    magnetizing_inductance : float
        Magnetizing inductance Lm (H).
    switching_frequency : float
        Switching frequency (Hz).
    diode_voltage_drop : float
        Rectifier diode forward voltage (V).
    duty_cycle : float
        Maximum duty cycle (default 0.45).
    current_ripple_ratio : float
        Output current ripple fraction (default 0.4).
    output_inductances : list[float] or None
        Per-secondary output filter inductances (H).
    ambient_temperature : float
        Ambient temperature (C).
    label : str or None
        Operating-point label.

    Returns
    -------
    dict
        Operating point with excitationsPerWinding list.
    """
    n_sec = len(output_voltages)
    if len(turns_ratios) != n_sec:
        raise ValueError(
            f"turns_ratios length ({len(turns_ratios)}) must match "
            f"output_voltages length ({n_sec})"
        )

    vin = input_voltage
    fsw = switching_frequency
    vd = diode_voltage_drop
    lm = magnetizing_inductance
    period = 1.0 / fsw

    main_vout = output_voltages[0]
    main_iout = output_currents[0]
    main_n = turns_ratios[0]

    # Main output inductance for DCM check
    if output_inductances is not None and len(output_inductances) > 0:
        main_lout = output_inductances[0]
    else:
        t_on = duty_cycle / fsw
        main_lout = (vin / main_n - vd - main_vout) * t_on / current_ripple_ratio
        if main_lout <= 0:
            main_lout = 1e-3

    # ---- Timing ----
    t1 = (period / 2.0) * (main_vout + vd) / (vin / main_n)
    if t1 > period / 2.0:
        raise ValueError(
            f"t1={t1:.3e} > period/2: wrong topology configuration"
        )

    # CCM: t2 = period - t1, dead_time = 0
    t2 = period - t1
    dead_time = 0.0

    # ---- Magnetization current ----
    mag_current = vin * t1 / lm
    min_pri = -mag_current / 2.0
    max_pri = mag_current / 2.0

    # ---- Secondary currents (CCM) ----
    min_sec = []
    max_sec = []
    for si in range(n_sec):
        ripple = current_ripple_ratio * output_currents[si]
        i_min = output_currents[si] - ripple / 2.0
        i_max = output_currents[si] + ripple / 2.0
        min_sec.append(i_min)
        max_sec.append(i_max)
        min_pri += i_min / turns_ratios[si]
        max_pri += i_max / turns_ratios[si]

    # ---- CCM / DCM ----
    is_dcm = min_pri < 0
    if is_dcm:
        t1 = math.sqrt(
            2.0 * main_iout * main_lout * (main_vout + vd)
            / (fsw * (vin / main_n - vd - main_vout) * (vin / main_n))
        )
        if t1 > period / 2.0:
            raise ValueError(
                f"DCM t1={t1:.3e} > period/2: wrong topology configuration"
            )
        # DCM: t2 and dead_time differ
        t2 = t1 * vin / main_n / (main_vout + vd) - t1
        dead_time = period - t1 - t2

        min_pri = 0.0
        max_pri = mag_current
        for si in range(n_sec):
            ripple = current_ripple_ratio * output_currents[si]
            min_sec[si] = 0.0
            max_sec[si] = ripple
            min_pri += min_sec[si] / turns_ratios[si]
            max_pri += max_sec[si] / turns_ratios[si]

    # ---- Clamp voltage ----
    clamp_voltage = t1 * fsw / (1.0 - t1 * fsw) * vin

    # ---- Primary-side quantities ----
    min_pri_t1 = min_pri
    max_pri_t1 = max_pri
    min_pri_volt = -clamp_voltage
    max_pri_volt = vin

    # Magnetizing current during t2+dead time (clamp phase)
    min_pri_t2t3 = -mag_current / 2.0
    max_pri_t2t3 = mag_current / 2.0

    # ---- Build primary current waveform ----
    # Active clamp primary current: always 4-point (same for CCM and DCM)
    pri_current = {
        "time": [0.0, t1, t1, period],
        "data": [min_pri_t1, max_pri_t1, max_pri_t2t3, min_pri_t2t3],
    }

    # ---- Build primary voltage waveform ----
    if not is_dcm:
        # CCM: 5-point voltage
        pri_voltage = {
            "time": [0.0, t1, t1, period, period],
            "data": [
                max_pri_volt,
                max_pri_volt,
                min_pri_volt,
                min_pri_volt,
                max_pri_volt,
            ],
        }
    else:
        # DCM: 7-point voltage with zero dead-time segment
        pri_voltage = {
            "time": [0.0, t1, t1, t1 + t2, t1 + t2, period, period],
            "data": [
                max_pri_volt,
                max_pri_volt,
                min_pri_volt,
                min_pri_volt,
                0.0,
                0.0,
                max_pri_volt,
            ],
        }

    excitations = [
        {
            "name": "Primary",
            "frequency": fsw,
            "voltage": {"waveform": pri_voltage},
            "current": {"waveform": pri_current},
        }
    ]

    # ---- Secondary waveforms ----
    for si in range(n_sec):
        sec_pp = max_sec[si] - min_sec[si]
        sec_v_min = -clamp_voltage / turns_ratios[si]
        sec_v_max = vin / turns_ratios[si]
        sec_v_pp = sec_v_max - sec_v_min
        sec_v_offset = sec_v_max + sec_v_min

        sec_current_wf = _make_flyback_primary(
            sec_pp, fsw, duty_cycle, min_sec[si], 0.0
        )
        sec_voltage_wf = _make_rectangular_with_deadtime(
            sec_v_pp, fsw, duty_cycle, sec_v_offset, dead_time
        )

        excitations.append(
            {
                "name": f"Secondary {si}",
                "frequency": fsw,
                "voltage": {"waveform": sec_voltage_wf},
                "current": {"waveform": sec_current_wf},
            }
        )

    return {
        "label": label or "Operating point",
        "conditions": {
            "inputVoltage": vin,
            "ambientTemperature": ambient_temperature,
        },
        "excitationsPerWinding": excitations,
    }


# ---------------------------------------------------------------------------
# Multi-voltage-point helpers (ported from collect_input_voltages)
# ---------------------------------------------------------------------------

def _collect_input_voltages(input_voltage_spec):
    """
    Expand an input voltage specification into (voltages, labels) lists.

    input_voltage_spec may be:
      - A scalar float  -> single operating point
      - A dict with keys "nominal", "minimum", "maximum" (any subset)
    """
    if isinstance(input_voltage_spec, (int, float)):
        return [float(input_voltage_spec)], ["Nom."]

    voltages = []
    names = []
    if isinstance(input_voltage_spec, dict):
        for key, label in [("nominal", "Nom."), ("minimum", "Min."), ("maximum", "Max.")]:
            if key in input_voltage_spec and input_voltage_spec[key] is not None:
                voltages.append(float(input_voltage_spec[key]))
                names.append(label)
    if not voltages:
        raise ValueError("No input voltages found in spec")
    return voltages, names


def generate_all_two_switch_forward_operating_points(
    input_voltage_spec,
    output_voltages,
    output_currents,
    turns_ratios,
    magnetizing_inductance,
    switching_frequency,
    diode_voltage_drop,
    duty_cycle=0.45,
    current_ripple_ratio=0.4,
    output_inductances=None,
    ambient_temperature=25.0,
):
    """
    Generate operating points for all input voltage conditions
    (min/nom/max) for a Two-Switch Forward converter.

    Parameters
    ----------
    input_voltage_spec : float or dict
        Either a scalar or {"nominal": ..., "minimum": ..., "maximum": ...}.
    (remaining parameters as in generate_two_switch_forward_waveforms)

    Returns
    -------
    list[dict]
        List of operating points, one per input voltage condition.
    """
    voltages, names = _collect_input_voltages(input_voltage_spec)
    results = []
    for vin, name in zip(voltages, names):
        op = generate_two_switch_forward_waveforms(
            input_voltage=vin,
            output_voltages=output_voltages,
            output_currents=output_currents,
            turns_ratios=turns_ratios,
            magnetizing_inductance=magnetizing_inductance,
            switching_frequency=switching_frequency,
            diode_voltage_drop=diode_voltage_drop,
            duty_cycle=duty_cycle,
            current_ripple_ratio=current_ripple_ratio,
            output_inductances=output_inductances,
            ambient_temperature=ambient_temperature,
            label=f"{name} input volt.",
        )
        results.append(op)
    return results


def generate_all_single_switch_forward_operating_points(
    input_voltage_spec,
    output_voltages,
    output_currents,
    turns_ratios,
    magnetizing_inductance,
    switching_frequency,
    diode_voltage_drop,
    duty_cycle=0.45,
    current_ripple_ratio=0.4,
    output_inductances=None,
    ambient_temperature=25.0,
):
    """
    Generate operating points for all input voltage conditions
    for a Single-Switch Forward converter.

    Parameters
    ----------
    input_voltage_spec : float or dict
        Either a scalar or {"nominal": ..., "minimum": ..., "maximum": ...}.
    turns_ratios : list[float]
        turns_ratios[0] = Np/Ndemag, turns_ratios[1:] = Np/Ns per secondary.
    (remaining parameters as in generate_single_switch_forward_waveforms)

    Returns
    -------
    list[dict]
        List of operating points.
    """
    voltages, names = _collect_input_voltages(input_voltage_spec)
    results = []
    for vin, name in zip(voltages, names):
        op = generate_single_switch_forward_waveforms(
            input_voltage=vin,
            output_voltages=output_voltages,
            output_currents=output_currents,
            turns_ratios=turns_ratios,
            magnetizing_inductance=magnetizing_inductance,
            switching_frequency=switching_frequency,
            diode_voltage_drop=diode_voltage_drop,
            duty_cycle=duty_cycle,
            current_ripple_ratio=current_ripple_ratio,
            output_inductances=output_inductances,
            ambient_temperature=ambient_temperature,
            label=f"{name} input volt.",
        )
        results.append(op)
    return results


def generate_all_active_clamp_forward_operating_points(
    input_voltage_spec,
    output_voltages,
    output_currents,
    turns_ratios,
    magnetizing_inductance,
    switching_frequency,
    diode_voltage_drop,
    duty_cycle=0.45,
    current_ripple_ratio=0.4,
    output_inductances=None,
    ambient_temperature=25.0,
):
    """
    Generate operating points for all input voltage conditions
    for an Active Clamp Forward converter.

    Parameters
    ----------
    input_voltage_spec : float or dict
        Either a scalar or {"nominal": ..., "minimum": ..., "maximum": ...}.
    (remaining parameters as in generate_active_clamp_forward_waveforms)

    Returns
    -------
    list[dict]
        List of operating points.
    """
    voltages, names = _collect_input_voltages(input_voltage_spec)
    results = []
    for vin, name in zip(voltages, names):
        op = generate_active_clamp_forward_waveforms(
            input_voltage=vin,
            output_voltages=output_voltages,
            output_currents=output_currents,
            turns_ratios=turns_ratios,
            magnetizing_inductance=magnetizing_inductance,
            switching_frequency=switching_frequency,
            diode_voltage_drop=diode_voltage_drop,
            duty_cycle=duty_cycle,
            current_ripple_ratio=current_ripple_ratio,
            output_inductances=output_inductances,
            ambient_temperature=ambient_temperature,
            label=f"{name} input volt.",
        )
        results.append(op)
    return results


# ---------------------------------------------------------------------------
# Design requirements calculators
# ---------------------------------------------------------------------------

def compute_two_switch_forward_design(
    input_voltage_spec,
    output_voltages,
    output_currents,
    switching_frequency,
    diode_voltage_drop,
    duty_cycle=0.45,
    current_ripple_ratio=0.4,
    max_switch_current=None,
):
    """
    Compute turns ratios, magnetizing inductance, and output inductances
    for a Two-Switch Forward converter.

    Ported from TwoSwitchForward::process_design_requirements() and
    TwoSwitchForward::get_output_inductance().

    Returns
    -------
    dict with keys:
        turnsRatios : list[float]
        magnetizingInductance : float  (H)
        outputInductances : list[float]  (H, per secondary)
    """
    voltages, _ = _collect_input_voltages(input_voltage_spec)
    vin_min = min(voltages)
    vin_max = max(voltages)
    fsw = switching_frequency
    vd = diode_voltage_drop
    n_sec = len(output_voltages)

    # Turns ratios: Np/Ns = Vin_max * D / (Vout + Vd)
    turns_ratios = [0.0] * n_sec
    for si in range(n_sec):
        tr = vin_max * duty_cycle / (output_voltages[si] + vd)
        turns_ratios[si] = max(turns_ratios[si], tr)

    # Magnetizing inductance
    min_lm = 0.0
    for si in range(n_sec):
        total_reflected = 0.0
        for sj in range(n_sec):
            total_reflected += output_currents[sj] / turns_ratios[sj]
        lm = vin_min / (fsw * total_reflected)
        min_lm = max(min_lm, lm)

    if max_switch_current is not None:
        total_reflected = 0.0
        for sj in range(n_sec):
            total_reflected += output_currents[sj] / turns_ratios[sj] * (1.0 + current_ripple_ratio)
        lm = vin_max * duty_cycle / fsw / (max_switch_current - total_reflected)
        min_lm = max(min_lm, lm)

    # Output inductances
    output_inds = []
    for si in range(n_sec):
        max_lout = 0.0
        t_on = duty_cycle / fsw
        lout = (vin_max / turns_ratios[si] - vd - output_voltages[si]) * t_on / current_ripple_ratio
        max_lout = max(max_lout, lout)
        output_inds.append(max_lout)

    return {
        "turnsRatios": turns_ratios,
        "magnetizingInductance": min_lm,
        "outputInductances": output_inds,
    }


def compute_single_switch_forward_design(
    input_voltage_spec,
    output_voltages,
    output_currents,
    switching_frequency,
    diode_voltage_drop,
    duty_cycle=0.45,
    current_ripple_ratio=0.4,
    max_switch_current=None,
):
    """
    Compute turns ratios, magnetizing inductance, and output inductances
    for a Single-Switch Forward converter.

    Returns
    -------
    dict with keys:
        turnsRatios : list[float]
            Index 0 = demagnetization winding (always 1.0), rest = secondaries.
        magnetizingInductance : float (H)
        outputInductances : list[float] (H, per secondary)
    """
    voltages, _ = _collect_input_voltages(input_voltage_spec)
    vin_min = min(voltages)
    vin_max = max(voltages)
    fsw = switching_frequency
    vd = diode_voltage_drop
    n_out = len(output_voltages)

    # Turns ratios: [demag=1.0, Np/Ns_0, Np/Ns_1, ...]
    turns_ratios = [1.0] + [0.0] * n_out
    for si in range(n_out):
        tr = vin_max * duty_cycle / (output_voltages[si] + vd)
        turns_ratios[si + 1] = max(turns_ratios[si + 1], tr)

    # Magnetizing inductance
    min_lm = 0.0
    total_reflected = 0.0
    for sj in range(n_out):
        total_reflected += output_currents[sj] / turns_ratios[sj + 1]
    lm = vin_min / (fsw * total_reflected)
    min_lm = max(min_lm, lm)

    if max_switch_current is not None:
        total_reflected_with_ripple = 0.0
        for sj in range(n_out):
            total_reflected_with_ripple += output_currents[sj] / turns_ratios[sj + 1] * (1.0 + current_ripple_ratio)
        lm = vin_max * duty_cycle / fsw / (max_switch_current - total_reflected_with_ripple)
        min_lm = max(min_lm, lm)

    # Output inductances
    output_inds = []
    for si in range(n_out):
        t_on = duty_cycle / fsw
        lout = (vin_max / turns_ratios[si + 1] - vd - output_voltages[si]) * t_on / current_ripple_ratio
        output_inds.append(max(0.0, lout))

    return {
        "turnsRatios": turns_ratios,
        "magnetizingInductance": min_lm,
        "outputInductances": output_inds,
    }


def compute_active_clamp_forward_design(
    input_voltage_spec,
    output_voltages,
    output_currents,
    switching_frequency,
    diode_voltage_drop,
    duty_cycle=0.45,
    current_ripple_ratio=0.4,
    max_switch_current=None,
):
    """
    Compute turns ratios, magnetizing inductance, and output inductances
    for an Active Clamp Forward converter.

    Returns
    -------
    dict with keys:
        turnsRatios : list[float]
        magnetizingInductance : float (H)
        outputInductances : list[float] (H, per secondary)
    """
    voltages, _ = _collect_input_voltages(input_voltage_spec)
    vin_min = min(voltages)
    vin_max = max(voltages)
    fsw = switching_frequency
    vd = diode_voltage_drop
    n_sec = len(output_voltages)

    # Turns ratios (same formula as Two-Switch Forward)
    turns_ratios = [0.0] * n_sec
    for si in range(n_sec):
        tr = vin_max * duty_cycle / (output_voltages[si] + vd)
        turns_ratios[si] = max(turns_ratios[si], tr)

    # Magnetizing inductance
    min_lm = 0.0
    total_reflected = 0.0
    for sj in range(n_sec):
        total_reflected += output_currents[sj] / turns_ratios[sj]
    lm = vin_min / (fsw * total_reflected)
    min_lm = max(min_lm, lm)

    if max_switch_current is not None:
        total_reflected_with_ripple = 0.0
        for sj in range(n_sec):
            total_reflected_with_ripple += output_currents[sj] / turns_ratios[sj] * (1.0 + current_ripple_ratio)
        lm = vin_max * duty_cycle / fsw / (max_switch_current - total_reflected_with_ripple)
        min_lm = max(min_lm, lm)

    # Output inductances
    output_inds = []
    for si in range(n_sec):
        t_on = duty_cycle / fsw
        lout = (vin_max / turns_ratios[si] - vd - output_voltages[si]) * t_on / current_ripple_ratio
        output_inds.append(max(0.0, lout))

    return {
        "turnsRatios": turns_ratios,
        "magnetizingInductance": min_lm,
        "outputInductances": output_inds,
    }


# ---------------------------------------------------------------------------
# Self-test / demo
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import json

    print("=" * 72)
    print("  Forward-Family Waveform Generator Self-Test")
    print("=" * 72)

    # Common test parameters
    vin_spec = {"minimum": 36.0, "nominal": 48.0, "maximum": 75.0}
    vout = [3.3]
    iout = [10.0]
    fsw = 200e3
    vd = 0.5

    # ---- Two-Switch Forward ----
    print("\n--- Two-Switch Forward ---")
    des = compute_two_switch_forward_design(vin_spec, vout, iout, fsw, vd)
    print(f"  Turns ratios:          {des['turnsRatios']}")
    print(f"  Magnetizing inductance: {des['magnetizingInductance']*1e6:.2f} uH")
    print(f"  Output inductances:    {[f'{l*1e6:.2f} uH' for l in des['outputInductances']]}")

    ops = generate_all_two_switch_forward_operating_points(
        vin_spec, vout, iout,
        turns_ratios=des["turnsRatios"],
        magnetizing_inductance=des["magnetizingInductance"],
        switching_frequency=fsw,
        diode_voltage_drop=vd,
        output_inductances=des["outputInductances"],
    )
    for op in ops:
        print(f"  {op['label']}:")
        for exc in op["excitationsPerWinding"]:
            n_pts = len(exc["current"]["waveform"]["time"])
            print(f"    {exc['name']:20s}  {n_pts} current pts, "
                  f"{len(exc['voltage']['waveform']['time'])} voltage pts")

    # ---- Single-Switch Forward ----
    print("\n--- Single-Switch Forward ---")
    des = compute_single_switch_forward_design(vin_spec, vout, iout, fsw, vd)
    print(f"  Turns ratios:          {des['turnsRatios']}  (first = demag)")
    print(f"  Magnetizing inductance: {des['magnetizingInductance']*1e6:.2f} uH")

    ops = generate_all_single_switch_forward_operating_points(
        vin_spec, vout, iout,
        turns_ratios=des["turnsRatios"],
        magnetizing_inductance=des["magnetizingInductance"],
        switching_frequency=fsw,
        diode_voltage_drop=vd,
        output_inductances=des["outputInductances"],
    )
    for op in ops:
        print(f"  {op['label']}:")
        for exc in op["excitationsPerWinding"]:
            n_pts = len(exc["current"]["waveform"]["time"])
            print(f"    {exc['name']:25s}  {n_pts} current pts, "
                  f"{len(exc['voltage']['waveform']['time'])} voltage pts")

    # ---- Active Clamp Forward ----
    print("\n--- Active Clamp Forward ---")
    des = compute_active_clamp_forward_design(vin_spec, vout, iout, fsw, vd)
    print(f"  Turns ratios:          {des['turnsRatios']}")
    print(f"  Magnetizing inductance: {des['magnetizingInductance']*1e6:.2f} uH")

    ops = generate_all_active_clamp_forward_operating_points(
        vin_spec, vout, iout,
        turns_ratios=des["turnsRatios"],
        magnetizing_inductance=des["magnetizingInductance"],
        switching_frequency=fsw,
        diode_voltage_drop=vd,
        output_inductances=des["outputInductances"],
    )
    for op in ops:
        print(f"  {op['label']}:")
        for exc in op["excitationsPerWinding"]:
            n_pts = len(exc["current"]["waveform"]["time"])
            print(f"    {exc['name']:20s}  {n_pts} current pts, "
                  f"{len(exc['voltage']['waveform']['time'])} voltage pts")

    # ---- Multi-output Two-Switch Forward ----
    print("\n--- Two-Switch Forward (2 outputs) ---")
    vout2 = [3.3, 12.0]
    iout2 = [10.0, 2.0]
    des2 = compute_two_switch_forward_design(vin_spec, vout2, iout2, fsw, vd)
    print(f"  Turns ratios:          {des2['turnsRatios']}")

    ops2 = generate_all_two_switch_forward_operating_points(
        vin_spec, vout2, iout2,
        turns_ratios=des2["turnsRatios"],
        magnetizing_inductance=des2["magnetizingInductance"],
        switching_frequency=fsw,
        diode_voltage_drop=vd,
        output_inductances=des2["outputInductances"],
    )
    for op in ops2:
        print(f"  {op['label']}:")
        for exc in op["excitationsPerWinding"]:
            n_pts = len(exc["current"]["waveform"]["time"])
            print(f"    {exc['name']:20s}  {n_pts} current pts")

    # Dump first op point as JSON for inspection
    print("\n--- JSON sample (Two-Switch Forward, Nom. Vin, single output) ---")
    sample = ops[0]  # first single-output test
    print(json.dumps(sample, indent=2))
