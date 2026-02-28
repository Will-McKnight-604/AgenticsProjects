#!/usr/bin/env python3
"""
Converter waveform models ported from MKF C++ source.

Provides cycle-accurate piecewise-linear waveforms for Flyback and Push-Pull
converters, matching the MKF C++ implementation in:
  - MKF-main/src/converter_models/Flyback.cpp
  - MKF-main/src/converter_models/PushPull.cpp
  - MKF-main/src/processors/Inputs.cpp (create_waveform helpers)

Each function takes scalar operating conditions for ONE input voltage and returns
a dict with excitationsPerWinding[] containing time/data waveform pairs for every
winding.

Usage:
    from converter_waveform_models import generate_flyback_waveforms, generate_push_pull_waveforms

    result = generate_flyback_waveforms(
        inputVoltage=100.0,
        outputVoltages=[5.0],
        outputCurrents=[10.0],
        turnsRatios=[20.0],         # Np/Ns per secondary
        magnetizingInductance=500e-6,
        switchingFrequency=100e3,
        diodeVoltageDrop=0.7,
        efficiency=0.9,
        currentRippleRatio=0.4,
        label="Min. input volt."
    )
"""

import math


# ---------------------------------------------------------------------------
# Helper: clamp
# ---------------------------------------------------------------------------
def _clamp(value, lo, hi):
    return max(lo, min(hi, value))


# ---------------------------------------------------------------------------
# Flyback waveform creation helpers (from Inputs.cpp create_waveform)
# ---------------------------------------------------------------------------

def _create_flyback_primary_waveform(peak_to_peak, frequency, duty_cycle, offset):
    """FLYBACK_PRIMARY waveform from Inputs.cpp line 535-541.

    data = {0, min, max, 0, 0}
    time = {0, 0, dc, dc, period}

    During on-time [0, D*T]: current ramps from offset to offset+peak_to_peak.
    At D*T: drops to zero. Stays zero during off-time.
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    max_val = peak_to_peak + offset
    min_val = offset

    time = [0.0, 0.0, dc, dc, period]
    data = [0.0, min_val, max_val, 0.0, 0.0]
    return {"time": time, "data": data}


def _create_flyback_secondary_waveform(peak_to_peak, frequency, duty_cycle, offset):
    """FLYBACK_SECONDARY waveform from Inputs.cpp line 543-549.

    data = {0, 0, max, min, 0}
    time = {0, dc, dc, period, period}

    Zero during on-time [0, D*T]. At D*T: jumps to max. Ramps down to min at T.
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    max_val = peak_to_peak + offset
    min_val = offset

    time = [0.0, dc, dc, period, period]
    data = [0.0, 0.0, max_val, min_val, 0.0]
    return {"time": time, "data": data}


def _create_flyback_secondary_with_deadtime_waveform(peak_to_peak, frequency, duty_cycle, offset, dead_time):
    """FLYBACK_SECONDARY_WITH_DEADTIME from Inputs.cpp line 551-557.

    data = {0, 0, max, min, 0, 0}
    time = {0, dc, dc, period-deadTime, period-deadTime, period}
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    max_val = peak_to_peak + offset
    min_val = offset

    time = [0.0, dc, dc, period - dead_time, period - dead_time, period]
    data = [0.0, 0.0, max_val, min_val, 0.0, 0.0]
    return {"time": time, "data": data}


def _create_rectangular_waveform(peak_to_peak, frequency, duty_cycle, offset):
    """RECTANGULAR waveform from Inputs.cpp line 465-471.

    data = {min, max, max, min, min}
    time = {0, 0, dc, dc, period}

    max = peakToPeak * (1 - dutyCycle) + offset
    min = -peakToPeak * dutyCycle + offset
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    max_val = peak_to_peak * (1 - duty_cycle) + offset
    min_val = -peak_to_peak * duty_cycle + offset

    time = [0.0, 0.0, dc, dc, period]
    data = [min_val, max_val, max_val, min_val, min_val]
    return {"time": time, "data": data}


def _create_rectangular_with_deadtime_waveform(peak_to_peak, frequency, duty_cycle, offset, dead_time):
    """RECTANGULAR_WITH_DEADTIME from Inputs.cpp line 473-479.

    data = {0, max, max, min, min, 0, 0}
    time = {0, 0, dc, dc, period-deadTime, period-deadTime, period}
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    max_val = peak_to_peak * (1 - duty_cycle) + offset
    min_val = -peak_to_peak * duty_cycle + offset

    time = [0.0, 0.0, dc, dc, period - dead_time, period - dead_time, period]
    data = [0.0, max_val, max_val, min_val, min_val, 0.0, 0.0]
    return {"time": time, "data": data}


def _create_secondary_rectangular_waveform(peak_to_peak, frequency, duty_cycle, offset):
    """SECONDARY_RECTANGULAR from Inputs.cpp line 481-487.

    data = {min, max, max, min, min}
    time = {0, 0, dc, dc, period}

    max = -peakToPeak * (1 - dutyCycle) + offset   (signs flipped vs RECTANGULAR)
    min = peakToPeak * dutyCycle + offset
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    max_val = -peak_to_peak * (1 - duty_cycle) + offset
    min_val = peak_to_peak * duty_cycle + offset

    time = [0.0, 0.0, dc, dc, period]
    data = [min_val, max_val, max_val, min_val, min_val]
    return {"time": time, "data": data}


def _create_secondary_rectangular_with_deadtime_waveform(peak_to_peak, frequency, duty_cycle, offset, dead_time):
    """SECONDARY_RECTANGULAR_WITH_DEADTIME from Inputs.cpp line 489-495.

    data = {0, max, max, min, min, 0, 0}
    time = {0, 0, dc, dc, period-deadTime, period-deadTime, period}
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    max_val = -peak_to_peak * (1 - duty_cycle) + offset
    min_val = peak_to_peak * duty_cycle + offset

    time = [0.0, 0.0, dc, dc, period - dead_time, period - dead_time, period]
    data = [0.0, max_val, max_val, min_val, min_val, 0.0, 0.0]
    return {"time": time, "data": data}


# ---------------------------------------------------------------------------
# generate_flyback_waveforms()
# ---------------------------------------------------------------------------

def generate_flyback_waveforms(
    inputVoltage,
    outputVoltages,
    outputCurrents,
    turnsRatios,
    magnetizingInductance,
    switchingFrequency,
    diodeVoltageDrop=0.7,
    efficiency=1.0,
    currentRippleRatio=None,
    dutyCycle=None,
    deadTime=0.0,
    label="Input volt.",
):
    """Generate Flyback converter waveforms for a single input voltage condition.

    Faithfully ports Flyback::process_operating_points_for_input_voltage() from
    MKF-main/src/converter_models/Flyback.cpp.

    Args:
        inputVoltage: DC input voltage for this operating condition (V).
        outputVoltages: List of output voltages, one per secondary (V).
        outputCurrents: List of output currents, one per secondary (A).
        turnsRatios: List of Np/Ns ratios, one per secondary.
                     turnsRatios[i] = Np/Ns for secondary i.
        magnetizingInductance: Primary magnetizing inductance (H).
        switchingFrequency: Switching frequency (Hz).
        diodeVoltageDrop: Forward voltage drop of output diodes (V).
        efficiency: Converter efficiency (0-1). Default 1.0.
        currentRippleRatio: Primary current ripple ratio (delta_I / I_avg).
                            If None, computed from V*D/(fsw*Lm)/I_center.
        dutyCycle: Override duty cycle. If None, computed from power balance.
        deadTime: Dead time in seconds (for DCM/QRM modes). Default 0.
        label: Label string for this operating condition.

    Returns:
        dict with:
          - "label": str
          - "conditions": {"inputVoltage": float}
          - "excitationsPerWinding": list of excitation dicts
    """
    n_secondaries = len(turnsRatios)

    # --- Reflected output voltage (for primary voltage swing) ---
    # C++ Flyback.cpp line 130-133
    maximum_reflected_output_voltage = 0.0
    for sec_idx in range(n_secondaries):
        v_out_plus_vd = outputVoltages[sec_idx] + diodeVoltageDrop
        reflected = v_out_plus_vd * turnsRatios[sec_idx]
        maximum_reflected_output_voltage = max(maximum_reflected_output_voltage, reflected)

    # Primary voltage peak-to-peak (C++ line 135)
    primary_voltage_peak_to_peak = inputVoltage + maximum_reflected_output_voltage

    # --- Power calculations (C++ lines 137-141) ---
    # get_total_input_power with efficiency=1 => total output power (sum of Vout*Iout)
    total_output_power = sum(
        outputCurrents[i] * outputVoltages[i] for i in range(n_secondaries)
    )
    # Maximum effective load current reflected to primary through first secondary
    maximum_effective_load_current = total_output_power / outputVoltages[0]
    maximum_effective_load_current_reflected = maximum_effective_load_current / turnsRatios[0]

    # Total input power (accounting for efficiency)
    # get_total_input_power with efficiency => sum(Vout*Iout) / eta
    total_input_power = total_output_power / max(efficiency, 1e-9)
    average_input_current = total_input_power / inputVoltage

    # --- Duty cycle (C++ lines 143-149) ---
    if dutyCycle is not None:
        d = dutyCycle
    else:
        # C++ line 148: dutyCycle = averageInputCurrent / (averageInputCurrent + maximumEffectiveLoadCurrentReflected)
        d = average_input_current / (average_input_current + maximum_effective_load_current_reflected)

    if d > 1.0:
        raise ValueError(f"dutyCycle cannot be larger than one: {d}")

    # --- Center current ramp (C++ lines 151-153) ---
    # centerSecondaryCurrentRampLumped = maximumEffectiveLoadCurrent / (1 - dutyCycle)
    center_secondary_current_ramp_lumped = maximum_effective_load_current / (1.0 - d)
    # centerPrimaryCurrentRamp = centerSecondaryCurrentRampLumped / turnsRatios[0]
    center_primary_current_ramp = center_secondary_current_ramp_lumped / turnsRatios[0]

    # --- Current ripple ratio (C++ lines 164-171) ---
    primary_current_average = center_primary_current_ramp
    if currentRippleRatio is None:
        # C++ line 166: primaryCurrentPeakToPeak = inputVoltage * dutyCycle / switchingFrequency / inductance
        primary_current_peak_to_peak_auto = inputVoltage * d / switchingFrequency / magnetizingInductance
        crr = primary_current_peak_to_peak_auto / center_primary_current_ramp if center_primary_current_ramp > 0 else 0.4
    else:
        crr = currentRippleRatio

    # C++ line 172: primaryCurrentPeakToPeak = centerPrimaryCurrentRamp * currentRippleRatio * 2
    primary_current_peak_to_peak = center_primary_current_ramp * crr * 2.0
    # C++ line 173: primaryCurrentOffset = primaryCurrentAverage - primaryCurrentPeakToPeak / 2
    primary_current_offset = primary_current_average - primary_current_peak_to_peak / 2.0
    # C++ line 174: primaryCurrentOffset = max(0.0, primaryCurrentOffset)
    primary_current_offset = max(0.0, primary_current_offset)

    # --- Mode detection (C++ lines 176-187) ---
    # CCM if offset > 0 (current never touches zero), else DCM
    if primary_current_offset > 0:
        mode = "CCM"
    else:
        mode = "DCM"

    excitations = []

    # ======================================================================
    # PRIMARY winding (C++ lines 189-211)
    # ======================================================================
    # Current: FLYBACK_PRIMARY waveform
    # Voltage: RECTANGULAR (CCM) or RECTANGULAR_WITH_DEADTIME (DCM)
    primary_current_wf = _create_flyback_primary_waveform(
        primary_current_peak_to_peak, switchingFrequency, d, primary_current_offset
    )

    if mode == "CCM":
        # C++ line 198: RECTANGULAR
        primary_voltage_wf = _create_rectangular_waveform(
            primary_voltage_peak_to_peak, switchingFrequency, d, 0.0
        )
    else:
        # C++ line 204: RECTANGULAR_WITH_DEADTIME
        primary_voltage_wf = _create_rectangular_with_deadtime_waveform(
            primary_voltage_peak_to_peak, switchingFrequency, d, 0.0, deadTime
        )

    excitations.append({
        "name": "Primary",
        "frequency": switchingFrequency,
        "voltage": {"waveform": primary_voltage_wf},
        "current": {"waveform": primary_current_wf},
    })

    # ======================================================================
    # SECONDARY windings (C++ lines 213-246)
    # ======================================================================
    for sec_idx in range(n_secondaries):
        # C++ line 219: secondaryPower = Iout[i] * Vout[i]
        secondary_power = outputCurrents[sec_idx] * outputVoltages[sec_idx]
        # C++ line 220: powerDivider = secondaryPower / totalOutputPower
        power_divider = secondary_power / total_output_power if total_output_power > 0 else 1.0 / n_secondaries

        # C++ line 222: minimumSecondaryVoltage = -inputVoltage / turnsRatios[secondaryIndex]
        min_sec_voltage = -inputVoltage / turnsRatios[sec_idx]
        # C++ line 223: maximumSecondaryVoltage = outputVoltages[secondaryIndex] + diodeVoltageDrop
        max_sec_voltage = outputVoltages[sec_idx] + diodeVoltageDrop
        # C++ line 224: secondaryVoltagePeaktoPeak = max - min
        sec_voltage_pp = max_sec_voltage - min_sec_voltage
        # C++ line 225: secondaryCurrentAverage = centerPrimaryCurrentRamp * turnsRatios[secondaryIndex] * powerDivider
        sec_current_average = center_primary_current_ramp * turnsRatios[sec_idx] * power_divider
        # C++ line 226: secondaryCurrentPeaktoPeak = secondaryCurrentAverage * currentRippleRatio * 2
        sec_current_pp = sec_current_average * crr * 2.0
        # C++ line 227: secondaryCurrentOffset = max(0.0, secondaryCurrentAverage - secondaryCurrentPeaktoPeak / 2)
        sec_current_offset = max(0.0, sec_current_average - sec_current_pp / 2.0)

        if mode == "CCM":
            # C++ lines 230-233: SECONDARY_RECTANGULAR voltage, FLYBACK_SECONDARY current
            sec_voltage_wf = _create_secondary_rectangular_waveform(
                sec_voltage_pp, switchingFrequency, d, 0.0
            )
            sec_current_wf = _create_flyback_secondary_waveform(
                sec_current_pp, switchingFrequency, d, sec_current_offset
            )
        else:
            # C++ lines 237-239: SECONDARY_RECTANGULAR_WITH_DEADTIME, FLYBACK_SECONDARY_WITH_DEADTIME
            sec_voltage_wf = _create_secondary_rectangular_with_deadtime_waveform(
                sec_voltage_pp, switchingFrequency, d, 0.0, deadTime
            )
            sec_current_wf = _create_flyback_secondary_with_deadtime_waveform(
                sec_current_pp, switchingFrequency, d, sec_current_offset, deadTime
            )

        # C++ line 244: name = "Secondary " + to_string(secondaryIndex)
        name = f"Secondary {sec_idx}"
        excitations.append({
            "name": name,
            "frequency": switchingFrequency,
            "voltage": {"waveform": sec_voltage_wf},
            "current": {"waveform": sec_current_wf},
        })

    return {
        "label": label,
        "conditions": {"inputVoltage": inputVoltage},
        "mode": mode,
        "dutyCycle": d,
        "currentRippleRatio": crr,
        "excitationsPerWinding": excitations,
    }


# ---------------------------------------------------------------------------
# generate_push_pull_waveforms()
# ---------------------------------------------------------------------------

def generate_push_pull_waveforms(
    inputVoltage,
    outputVoltages,
    outputCurrents,
    turnsRatios,
    magnetizingInductance,
    switchingFrequency,
    diodeVoltageDrop=0.7,
    currentRippleRatio=0.3,
    outputInductance=None,
    label="Input volt.",
):
    """Generate Push-Pull converter waveforms for a single input voltage condition.

    Faithfully ports PushPull::process_operating_points_for_input_voltage() from
    MKF-main/src/converter_models/PushPull.cpp.

    The Push-Pull has a center-tapped primary with two primary half-windings.
    Each switch drives one half for time t1 per half-period, alternating.
    The transformer sees +/-Vin across the full primary.

    C++ turnsRatios layout for PushPull:
      [0] = second primary ratio (always 1.0, center-tap mirror)
      [1] = main secondary Np/Ns (first secondary half)
      [2] = main secondary Np/Ns (second secondary half, same as [1])
      [3..] = auxiliary secondary ratios

    This function accepts a SIMPLIFIED turnsRatios:
      turnsRatios[0] = main secondary Np/Ns
      turnsRatios[1..] = auxiliary secondary Np/Ns

    and internally expands to the C++ layout.

    Args:
        inputVoltage: DC input voltage for this operating condition (V).
        outputVoltages: List of output voltages, one per secondary output (V).
                        outputVoltages[0] = main output.
        outputCurrents: List of output currents, one per secondary output (A).
        turnsRatios: Simplified list of Np/Ns ratios.
                     turnsRatios[0] = main secondary Np/Ns.
                     turnsRatios[1..] = auxiliary secondary Np/Ns.
        magnetizingInductance: Primary magnetizing inductance (H).
        switchingFrequency: Switching frequency (Hz).
        diodeVoltageDrop: Forward voltage drop of output diodes (V).
        currentRippleRatio: Output inductor current ripple ratio (delta_I / I_avg).
        outputInductance: Output filter inductance (H). If None, estimated internally.
        label: Label string for this operating condition.

    Returns:
        dict with:
          - "label": str
          - "conditions": {"inputVoltage": float}
          - "excitationsPerWinding": list of excitation dicts
            Winding order: [First Primary, Second Primary, First Main Secondary,
                           Second Main Secondary, Auxiliary 1, ...]
    """
    n_outputs = len(outputVoltages)

    # --- Expand turnsRatios to C++ internal layout ---
    # C++ convert_turns_ratios() (PushPull.cpp lines 23-43):
    #   [0] = 1 (second primary)
    #   [1] = turnsRatios[0] (first secondary half)
    #   [2] = turnsRatios[0] (second secondary half)
    #   [3..] = turnsRatios[1..] (auxiliary secondaries)
    tr_internal = [1.0]                      # [0] second primary
    tr_internal.append(turnsRatios[0])       # [1] first main secondary
    tr_internal.append(turnsRatios[0])       # [2] second main secondary
    for aux_idx in range(1, len(turnsRatios)):
        tr_internal.append(turnsRatios[aux_idx])

    # --- Basic parameters (C++ lines 66-74) ---
    period = 1.0 / switchingFrequency
    main_output_voltage = outputVoltages[0]
    main_output_current = outputCurrents[0]
    main_secondary_turns_ratio = tr_internal[1]  # Np/Ns for main secondary

    inductor_current_ripple = currentRippleRatio * main_output_current

    # --- t1: on-time per half-cycle (C++ line 75) ---
    # t1 = (T/2) * (Vout + Vd) / (Vin / Ns_Np)
    #    = (T/2) * (Vout + Vd) * (Ns/Np) / Vin
    # Note: mainSecondaryTurnsRatio in C++ is Np/Ns, so Vin/ratio = Vin*Ns/Np
    t1 = (period / 2.0) * (main_output_voltage + diodeVoltageDrop) / (inputVoltage / main_secondary_turns_ratio)
    if t1 > period / 2.0:
        raise ValueError(
            f"T1 ({t1*1e6:.1f} us) cannot be larger than period/2 ({period/2*1e6:.1f} us), "
            "wrong topology configuration"
        )

    # --- Magnetization current (C++ line 80) ---
    magnetization_current = inputVoltage * t1 / magnetizingInductance

    # --- Output filter inductor ripple (C++ lines 81-82) ---
    min_secondary_current = main_output_current - inductor_current_ripple / 2.0
    max_secondary_current = main_output_current + inductor_current_ripple / 2.0

    # --- Primary current (reflected secondary + magnetization) (C++ lines 83-84) ---
    min_primary_current = min_secondary_current / main_secondary_turns_ratio - magnetization_current / 2.0
    max_primary_current = min_secondary_current / main_secondary_turns_ratio + magnetization_current / 2.0
    # Note: C++ uses minimumSecondaryCurrent for BOTH min and max primary (magnetization adds symmetrically)

    # --- Add auxiliary secondary reflected currents (C++ lines 86-94) ---
    for aux_idx in range(1, n_outputs):
        aux_ripple = currentRippleRatio * outputCurrents[aux_idx]
        min_aux_sec = outputCurrents[aux_idx] - aux_ripple / 2.0
        max_aux_sec = outputCurrents[aux_idx] + aux_ripple / 2.0
        tr_aux_idx = 2 + aux_idx  # C++ line 91: turnsRatioAuxiliarySecondaryIndex = 2 + auxiliarySecondaryIndex
        min_primary_current += min_aux_sec / tr_internal[tr_aux_idx]
        max_primary_current += max_aux_sec / tr_internal[tr_aux_idx]

    excitations = []

    # ======================================================================
    # CCM vs DCM branch (C++ line 97)
    # ======================================================================
    if min_primary_current > 0:
        # ==================================================================
        # CCM (Continuous Conduction Mode)
        # ==================================================================

        # --- Primary-side transformer currents and voltages (C++ lines 98-110) ---
        min_pri_xfmr_i = min_primary_current
        max_pri_xfmr_i = max_primary_current
        min_pri_xfmr_v = -inputVoltage
        max_pri_xfmr_v = inputVoltage

        min_sec_xfmr_i_t1_of_fet = min_secondary_current
        max_sec_xfmr_i_t1_of_fet = max_secondary_current
        # C++ lines 105-106: during T2 (off-time of the FET that was conducting)
        min_sec_xfmr_i_t2_other_fet = (
            (min_secondary_current / main_secondary_turns_ratio + magnetization_current / 2.0)
            / 2.0 * main_secondary_turns_ratio - inductor_current_ripple / 2.0
        )
        max_sec_xfmr_i_t2_other_fet = (
            (min_secondary_current / main_secondary_turns_ratio + magnetization_current / 2.0)
            / 2.0 * main_secondary_turns_ratio
        )
        # C++ lines 107-108: T2 for the FET's own secondary
        min_sec_xfmr_i_t2_of_fet = min_secondary_current - min_sec_xfmr_i_t2_other_fet
        max_sec_xfmr_i_t2_of_fet = max_secondary_current - max_sec_xfmr_i_t2_other_fet

        min_sec_xfmr_v = -inputVoltage / main_secondary_turns_ratio
        max_sec_xfmr_v = inputVoltage / main_secondary_turns_ratio

        # ------------------------------------------------------------------
        # First Primary (C++ lines 112-162)
        # ------------------------------------------------------------------
        # Current: ramps from min to max during [0, t1], then zero during [t1, T]
        fp_i_data = [min_pri_xfmr_i, max_pri_xfmr_i, 0.0, 0.0]
        fp_i_time = [0.0, t1, t1, period]

        # Voltage: +Vin during [0, t1], 0 during [t1, T/2], -Vin during [T/2, T/2+t1], 0 during rest
        fp_v_data = [
            max_pri_xfmr_v, max_pri_xfmr_v,
            0.0, 0.0,
            min_pri_xfmr_v, min_pri_xfmr_v,
            0.0, 0.0,
        ]
        fp_v_time = [
            0.0, t1,
            t1, period / 2.0,
            period / 2.0, period / 2.0 + t1,
            period / 2.0 + t1, period,
        ]

        excitations.append({
            "name": "First primary",
            "frequency": switchingFrequency,
            "voltage": {"waveform": {"time": fp_v_time, "data": fp_v_data}},
            "current": {"waveform": {"time": fp_i_time, "data": fp_i_data}},
        })

        # ------------------------------------------------------------------
        # Second Primary (C++ lines 164-218)
        # ------------------------------------------------------------------
        # Current: zero during [0, T/2], ramps from min to max during [T/2, T/2+t1], zero rest
        sp_i_data = [0.0, 0.0, min_pri_xfmr_i, max_pri_xfmr_i, 0.0, 0.0]
        sp_i_time = [0.0, period / 2.0, period / 2.0, period / 2.0 + t1, period / 2.0 + t1, period]

        # Voltage: -Vin during [0, t1], 0 during [t1, T/2], +Vin during [T/2, T/2+t1], 0 rest
        sp_v_data = [
            min_pri_xfmr_v, min_pri_xfmr_v,
            0.0, 0.0,
            max_pri_xfmr_v, max_pri_xfmr_v,
            0.0, 0.0,
        ]
        sp_v_time = [
            0.0, t1,
            t1, period / 2.0,
            period / 2.0, period / 2.0 + t1,
            period / 2.0 + t1, period,
        ]

        excitations.append({
            "name": "Second primary",
            "frequency": switchingFrequency,
            "voltage": {"waveform": {"time": sp_v_time, "data": sp_v_data}},
            "current": {"waveform": {"time": sp_i_time, "data": sp_i_data}},
        })

        # ------------------------------------------------------------------
        # First Main Secondary (C++ lines 221-280)
        # ------------------------------------------------------------------
        # Current: 8 segments (C++ lines 227-246)
        fs_i_data = [
            0.0,
            0.0,
            max_sec_xfmr_i_t2_other_fet,
            min_sec_xfmr_i_t2_other_fet,
            min_sec_xfmr_i_t1_of_fet,
            max_sec_xfmr_i_t1_of_fet,
            max_sec_xfmr_i_t2_of_fet,
            min_sec_xfmr_i_t2_of_fet,
        ]
        fs_i_time = [
            0.0, t1,
            t1, period / 2.0,
            period / 2.0, period / 2.0 + t1,
            period / 2.0 + t1, period,
        ]

        # Voltage: 8 segments (C++ lines 253-276)
        fs_v_data = [
            min_sec_xfmr_v, min_sec_xfmr_v,
            0.0, 0.0,
            max_sec_xfmr_v, max_sec_xfmr_v,
            0.0, 0.0,
        ]
        fs_v_time = [
            0.0, t1,
            t1, period / 2.0,
            period / 2.0, period / 2.0 + t1,
            period / 2.0 + t1, period,
        ]

        excitations.append({
            "name": "First secondary",
            "frequency": switchingFrequency,
            "voltage": {"waveform": {"time": fs_v_time, "data": fs_v_data}},
            "current": {"waveform": {"time": fs_i_time, "data": fs_i_data}},
        })

        # ------------------------------------------------------------------
        # Second Main Secondary (C++ lines 282-341)
        # ------------------------------------------------------------------
        # Current: 8 segments (C++ lines 288-310)
        ss_i_data = [
            min_sec_xfmr_i_t1_of_fet,
            max_sec_xfmr_i_t1_of_fet,
            max_sec_xfmr_i_t2_of_fet,
            min_sec_xfmr_i_t2_of_fet,
            0.0,
            0.0,
            max_sec_xfmr_i_t2_other_fet,
            min_sec_xfmr_i_t2_other_fet,
        ]
        ss_i_time = [
            0.0, t1,
            t1, period / 2.0,
            period / 2.0, period / 2.0 + t1,
            period / 2.0 + t1, period,
        ]

        # Voltage: 8 segments (C++ lines 314-337)
        ss_v_data = [
            max_sec_xfmr_v, max_sec_xfmr_v,
            0.0, 0.0,
            min_sec_xfmr_v, min_sec_xfmr_v,
            0.0, 0.0,
        ]
        ss_v_time = [
            0.0, t1,
            t1, period / 2.0,
            period / 2.0, period / 2.0 + t1,
            period / 2.0 + t1, period,
        ]

        excitations.append({
            "name": "Second secondary",
            "frequency": switchingFrequency,
            "voltage": {"waveform": {"time": ss_v_time, "data": ss_v_data}},
            "current": {"waveform": {"time": ss_i_time, "data": ss_i_data}},
        })

        # ------------------------------------------------------------------
        # Auxiliary Secondaries (C++ lines 343-420)
        # ------------------------------------------------------------------
        for aux_idx in range(1, n_outputs):
            aux_ripple = currentRippleRatio * outputCurrents[aux_idx]
            min_aux_sec = outputCurrents[aux_idx] - aux_ripple / 2.0
            max_aux_sec = outputCurrents[aux_idx] + aux_ripple / 2.0
            tr_aux_sec_idx = 2 + aux_idx
            tr_aux = tr_internal[tr_aux_sec_idx]

            # C++ lines 355-358
            min_aux_t1_of_fet = min_aux_sec
            max_aux_t1_of_fet = max_aux_sec
            min_aux_t2_other_fet = (
                (min_aux_sec / tr_aux + magnetization_current / 2.0) / 2.0 * tr_aux
                - inductor_current_ripple / 2.0
            )
            max_aux_t2_other_fet = (
                (min_aux_sec / tr_aux + magnetization_current / 2.0) / 2.0 * tr_aux
            )
            min_aux_t2_of_fet = min_aux_sec - min_aux_t2_other_fet
            max_aux_t2_of_fet = max_aux_sec - max_aux_t2_other_fet
            min_aux_v = -inputVoltage / tr_aux
            max_aux_v = inputVoltage / tr_aux

            # Current: 8 segments (same shape as second main secondary)
            # C++ lines 366-388
            aux_i_data = [
                min_aux_t1_of_fet,
                max_aux_t1_of_fet,
                max_aux_t2_of_fet,
                min_aux_t2_of_fet,
                0.0,
                0.0,
                max_aux_t2_other_fet,
                min_aux_t2_other_fet,
            ]
            aux_i_time = [
                0.0, t1,
                t1, period / 2.0,
                period / 2.0, period / 2.0 + t1,
                period / 2.0 + t1, period,
            ]

            # Voltage: 8 segments
            # C++ lines 392-415
            aux_v_data = [
                max_aux_v, max_aux_v,
                0.0, 0.0,
                min_aux_v, min_aux_v,
                0.0, 0.0,
            ]
            aux_v_time = [
                0.0, t1,
                t1, period / 2.0,
                period / 2.0, period / 2.0 + t1,
                period / 2.0 + t1, period,
            ]

            excitations.append({
                "name": f"Auxiliary {aux_idx}",
                "frequency": switchingFrequency,
                "voltage": {"waveform": {"time": aux_v_time, "data": aux_v_data}},
                "current": {"waveform": {"time": aux_i_time, "data": aux_i_data}},
            })

    else:
        # ==================================================================
        # DCM (Discontinuous Conduction Mode) - C++ lines 423-825
        # ==================================================================

        # --- Estimate output inductance if not provided ---
        if outputInductance is None:
            # Use the same formula as PushPull::get_output_inductance (C++ lines 956-998)
            v_secondary = inputVoltage / main_secondary_turns_ratio
            v_l_out = v_secondary - main_output_voltage
            if v_l_out > 0 and inductor_current_ripple > 0:
                outputInductance = v_l_out * t1 / inductor_current_ripple
            else:
                outputInductance = 10e-6  # 10 uH default

        # C++ line 424: t1_dcm calculation
        # t1 = sqrt(2 * Iout * Lout * (Vout + Vd) / (2 * fsw * (Vin/N - Vd - Vout) * (Vin/N)))
        vin_over_n = inputVoltage / main_secondary_turns_ratio
        numerator = 2.0 * main_output_current * outputInductance * (main_output_voltage + diodeVoltageDrop)
        denominator = 2.0 * switchingFrequency * (vin_over_n - diodeVoltageDrop - main_output_voltage) * vin_over_n
        if denominator <= 0:
            raise ValueError("Invalid DCM parameters: denominator <= 0 in t1 calculation")
        t1_dcm = math.sqrt(numerator / denominator)

        # C++ line 425: t2 = t1 * (Vin/N) / (Vout + Vd) - t1
        t2_dcm = t1_dcm * vin_over_n / (main_output_voltage + diodeVoltageDrop) - t1_dcm
        if t1_dcm + t2_dcm > period / 2.0:
            raise ValueError(
                f"T1+T2 ({(t1_dcm+t2_dcm)*1e6:.1f} us) cannot be larger than period/2 "
                f"({period/2*1e6:.1f} us), wrong topology configuration"
            )

        # C++ lines 430-433
        min_sec_current_dcm = 0.0
        max_sec_current_dcm = inductor_current_ripple
        min_pri_current_dcm = 0.0
        max_pri_current_dcm = inductor_current_ripple / main_secondary_turns_ratio + magnetization_current / 2.0

        # Add auxiliary secondaries (C++ lines 435-439)
        for aux_idx in range(1, n_outputs):
            aux_ripple = currentRippleRatio * outputCurrents[aux_idx]
            tr_aux_sec_idx = 2 + aux_idx
            max_pri_current_dcm += aux_ripple / tr_internal[tr_aux_sec_idx] + magnetization_current / 2.0

        # --- Derived quantities (C++ lines 441-459) ---
        min_pri_xfmr_i_dcm = min_pri_current_dcm
        max_pri_xfmr_i_dcm = max_pri_current_dcm
        min_pri_xfmr_v_dcm = -inputVoltage
        max_pri_xfmr_v_dcm = inputVoltage

        max_sec_xfmr_i_t1_of_fet_dcm = max_sec_current_dcm
        min_sec_xfmr_i_t2_other_fet_dcm = (
            (min_sec_current_dcm / main_secondary_turns_ratio + magnetization_current / 2.0)
            / 2.0 * main_secondary_turns_ratio - inductor_current_ripple / 2.0
        )
        max_sec_xfmr_i_t2_other_fet_dcm = (
            (min_sec_current_dcm / main_secondary_turns_ratio + magnetization_current / 2.0)
            / 2.0 * main_secondary_turns_ratio
        )
        min_sec_xfmr_i_t2_of_fet_dcm = 0.0
        max_sec_xfmr_i_t2_of_fet_dcm = max_sec_current_dcm - max_sec_xfmr_i_t2_other_fet_dcm
        min_sec_xfmr_v_dcm = -inputVoltage / main_secondary_turns_ratio
        max_sec_xfmr_v_dcm = inputVoltage / main_secondary_turns_ratio

        # T3 quantities (C++ lines 454-459)
        min_pri_xfmr_v_t3 = -(main_output_voltage + diodeVoltageDrop) * main_secondary_turns_ratio
        max_pri_xfmr_v_t3 = (main_output_voltage + diodeVoltageDrop) * main_secondary_turns_ratio
        min_sec_xfmr_i_t3 = 0.0
        max_sec_xfmr_i_t3 = max_sec_xfmr_i_t2_other_fet_dcm - max_sec_xfmr_i_t2_of_fet_dcm
        min_sec_xfmr_v_t3 = -main_output_voltage - diodeVoltageDrop
        max_sec_xfmr_v_t3 = main_output_voltage + diodeVoltageDrop

        # ------------------------------------------------------------------
        # First Primary DCM (C++ lines 461-520)
        # ------------------------------------------------------------------
        fp_i_data_dcm = [min_pri_xfmr_i_dcm, max_pri_xfmr_i_dcm, 0.0, 0.0]
        fp_i_time_dcm = [0.0, t1_dcm, t1_dcm, period]

        # Voltage: 12 segments (C++ lines 485-515)
        fp_v_data_dcm = [
            max_pri_xfmr_v_dcm, max_pri_xfmr_v_dcm,
            0.0, 0.0,
            min_pri_xfmr_v_t3, min_pri_xfmr_v_t3,
            min_pri_xfmr_v_dcm, min_pri_xfmr_v_dcm,
            0.0, 0.0,
            max_pri_xfmr_v_t3, max_pri_xfmr_v_t3,
        ]
        fp_v_time_dcm = [
            0.0, t1_dcm,
            t1_dcm, t1_dcm + t2_dcm,
            t1_dcm + t2_dcm, period / 2.0,
            period / 2.0, period / 2.0 + t1_dcm,
            period / 2.0 + t1_dcm, period / 2.0 + t1_dcm + t2_dcm,
            period / 2.0 + t1_dcm + t2_dcm, period,
        ]

        excitations.append({
            "name": "First primary",
            "frequency": switchingFrequency,
            "voltage": {"waveform": {"time": fp_v_time_dcm, "data": fp_v_data_dcm}},
            "current": {"waveform": {"time": fp_i_time_dcm, "data": fp_i_data_dcm}},
        })

        # ------------------------------------------------------------------
        # Second Primary DCM (C++ lines 522-583)
        # ------------------------------------------------------------------
        sp_i_data_dcm = [0.0, min_pri_xfmr_i_dcm, max_pri_xfmr_i_dcm, 0.0, 0.0]
        sp_i_time_dcm = [0.0, period / 2.0, period / 2.0 + t1_dcm, period / 2.0 + t1_dcm, period]

        # Voltage: 12 segments (C++ lines 548-575)
        sp_v_data_dcm = [
            min_pri_xfmr_v_dcm, min_pri_xfmr_v_dcm,
            0.0, 0.0,
            max_pri_xfmr_v_t3, max_pri_xfmr_v_t3,
            max_pri_xfmr_v_dcm, max_pri_xfmr_v_dcm,
            0.0, 0.0,
            min_pri_xfmr_v_t3, min_pri_xfmr_v_t3,
        ]
        sp_v_time_dcm = [
            0.0, t1_dcm,
            t1_dcm, t1_dcm + t2_dcm,
            t1_dcm + t2_dcm, period / 2.0,
            period / 2.0, period / 2.0 + t1_dcm,
            period / 2.0 + t1_dcm, period / 2.0 + t1_dcm + t2_dcm,
            period / 2.0 + t1_dcm + t2_dcm, period,
        ]

        excitations.append({
            "name": "Second primary",
            "frequency": switchingFrequency,
            "voltage": {"waveform": {"time": sp_v_time_dcm, "data": sp_v_data_dcm}},
            "current": {"waveform": {"time": sp_i_time_dcm, "data": sp_i_data_dcm}},
        })

        # ------------------------------------------------------------------
        # First Main Secondary DCM (C++ lines 585-656)
        # ------------------------------------------------------------------
        # Current: 10 segments (C++ lines 591-614)
        fs_i_data_dcm = [
            0.0,
            0.0,
            max_sec_xfmr_i_t2_other_fet_dcm,
            min_sec_xfmr_i_t2_other_fet_dcm,
            max_sec_xfmr_i_t3,
            min_sec_xfmr_i_t3,
            max_sec_xfmr_i_t1_of_fet_dcm,
            max_sec_xfmr_i_t2_of_fet_dcm,
            min_sec_xfmr_i_t2_of_fet_dcm,
            0.0,
        ]
        fs_i_time_dcm = [
            0.0, t1_dcm,
            t1_dcm, t1_dcm + t2_dcm,
            t1_dcm + t2_dcm, period / 2.0,
            period / 2.0 + t1_dcm, period / 2.0 + t1_dcm,
            period / 2.0 + t1_dcm + t2_dcm, period,
        ]
        # Note: C++ has 10 data points but only 10 time points
        # The time layout from C++ (lines 603-613):
        # {0, t1, t1, t1+t2, t1+t2, T/2, T/2+t1, T/2+t1, T/2+t1+t2, T}

        # Voltage: 12 segments (C++ lines 621-652)
        fs_v_data_dcm = [
            min_sec_xfmr_v_dcm, min_sec_xfmr_v_dcm,
            0.0, 0.0,
            max_sec_xfmr_v_t3, max_sec_xfmr_v_t3,
            max_sec_xfmr_v_dcm, max_sec_xfmr_v_dcm,
            0.0, 0.0,
            min_sec_xfmr_v_t3, min_sec_xfmr_v_t3,
        ]
        fs_v_time_dcm = [
            0.0, t1_dcm,
            t1_dcm, t1_dcm + t2_dcm,
            t1_dcm + t2_dcm, period / 2.0,
            period / 2.0, period / 2.0 + t1_dcm,
            period / 2.0 + t1_dcm, period / 2.0 + t1_dcm + t2_dcm,
            period / 2.0 + t1_dcm + t2_dcm, period,
        ]

        excitations.append({
            "name": "First secondary",
            "frequency": switchingFrequency,
            "voltage": {"waveform": {"time": fs_v_time_dcm, "data": fs_v_data_dcm}},
            "current": {"waveform": {"time": fs_i_time_dcm, "data": fs_i_data_dcm}},
        })

        # ------------------------------------------------------------------
        # Second Main Secondary DCM (C++ lines 658-727)
        # ------------------------------------------------------------------
        # Current: 9 segments (C++ lines 664-684)
        ss_i_data_dcm = [
            0.0,
            max_sec_xfmr_i_t1_of_fet_dcm,
            max_sec_xfmr_i_t2_of_fet_dcm,
            min_sec_xfmr_i_t2_of_fet_dcm,
            0.0,
            max_sec_xfmr_i_t2_other_fet_dcm,
            min_sec_xfmr_i_t2_other_fet_dcm,
            max_sec_xfmr_i_t3,
            min_sec_xfmr_i_t3,
        ]
        ss_i_time_dcm = [
            0.0,
            t1_dcm,
            t1_dcm,
            t1_dcm + t2_dcm,
            period / 2.0 + t1_dcm,
            period / 2.0 + t1_dcm,
            period / 2.0 + t1_dcm + t2_dcm,
            period / 2.0 + t1_dcm + t2_dcm,
            period,
        ]

        # Voltage: 12 segments (C++ lines 692-718)
        ss_v_data_dcm = [
            max_sec_xfmr_v_dcm, max_sec_xfmr_v_dcm,
            0.0, 0.0,
            min_sec_xfmr_v_t3, min_sec_xfmr_v_t3,
            min_sec_xfmr_v_dcm, min_sec_xfmr_v_dcm,
            0.0, 0.0,
            max_sec_xfmr_v_t3, max_sec_xfmr_v_t3,
        ]
        ss_v_time_dcm = [
            0.0, t1_dcm,
            t1_dcm, t1_dcm + t2_dcm,
            t1_dcm + t2_dcm, period / 2.0,
            period / 2.0, period / 2.0 + t1_dcm,
            period / 2.0 + t1_dcm, period / 2.0 + t1_dcm + t2_dcm,
            period / 2.0 + t1_dcm + t2_dcm, period,
        ]

        excitations.append({
            "name": "Second secondary",
            "frequency": switchingFrequency,
            "voltage": {"waveform": {"time": ss_v_time_dcm, "data": ss_v_data_dcm}},
            "current": {"waveform": {"time": ss_i_time_dcm, "data": ss_i_data_dcm}},
        })

        # ------------------------------------------------------------------
        # Auxiliary Secondaries DCM (C++ lines 729-823)
        # ------------------------------------------------------------------
        for aux_idx in range(1, n_outputs):
            aux_ripple = currentRippleRatio * outputCurrents[aux_idx]
            aux_output_voltage = outputVoltages[aux_idx]
            min_aux_sec_dcm = outputCurrents[aux_idx] - aux_ripple / 2.0
            max_aux_sec_dcm = outputCurrents[aux_idx] + aux_ripple / 2.0
            tr_aux_sec_idx = 2 + aux_idx
            tr_aux_dcm = tr_internal[tr_aux_sec_idx]

            # C++ lines 740-751
            max_aux_t1_of_fet_dcm = max_aux_sec_dcm
            min_aux_t2_other_fet_dcm = (
                (min_aux_sec_dcm / tr_aux_dcm + magnetization_current / 2.0)
                / 2.0 * tr_aux_dcm - inductor_current_ripple / 2.0
            )
            max_aux_t2_other_fet_dcm = (
                (min_aux_sec_dcm / tr_aux_dcm + magnetization_current / 2.0)
                / 2.0 * tr_aux_dcm
            )
            min_aux_t2_of_fet_dcm = 0.0
            max_aux_t2_of_fet_dcm = max_aux_sec_dcm - max_aux_t2_other_fet_dcm
            min_aux_v_dcm = -inputVoltage / tr_aux_dcm
            max_aux_v_dcm = inputVoltage / tr_aux_dcm

            min_aux_i_t3_dcm = 0.0
            max_aux_i_t3_dcm = max_aux_t2_other_fet_dcm - max_aux_t2_of_fet_dcm
            min_aux_v_t3_dcm = -aux_output_voltage - diodeVoltageDrop
            max_aux_v_t3_dcm = aux_output_voltage + diodeVoltageDrop

            # Current: 10 segments (C++ lines 757-780)
            aux_i_data_dcm = [
                0.0,
                0.0,
                max_aux_t2_other_fet_dcm,
                min_aux_t2_other_fet_dcm,
                max_aux_i_t3_dcm,
                min_aux_i_t3_dcm,
                max_aux_t1_of_fet_dcm,
                max_aux_t2_of_fet_dcm,
                min_aux_t2_of_fet_dcm,
                0.0,
            ]
            aux_i_time_dcm = [
                0.0, t1_dcm,
                t1_dcm, t1_dcm + t2_dcm,
                t1_dcm + t2_dcm, period / 2.0,
                period / 2.0 + t1_dcm, period / 2.0 + t1_dcm,
                period / 2.0 + t1_dcm + t2_dcm, period,
            ]

            # Voltage: 12 segments (C++ lines 787-814)
            aux_v_data_dcm = [
                min_aux_v_dcm, min_aux_v_dcm,
                0.0, 0.0,
                max_aux_v_t3_dcm, max_aux_v_t3_dcm,
                max_aux_v_dcm, max_aux_v_dcm,
                0.0, 0.0,
                min_aux_v_t3_dcm, min_aux_v_t3_dcm,
            ]
            aux_v_time_dcm = [
                0.0, t1_dcm,
                t1_dcm, t1_dcm + t2_dcm,
                t1_dcm + t2_dcm, period / 2.0,
                period / 2.0, period / 2.0 + t1_dcm,
                period / 2.0 + t1_dcm, period / 2.0 + t1_dcm + t2_dcm,
                period / 2.0 + t1_dcm + t2_dcm, period,
            ]

            excitations.append({
                "name": f"Auxiliary {aux_idx}",
                "frequency": switchingFrequency,
                "voltage": {"waveform": {"time": aux_v_time_dcm, "data": aux_v_data_dcm}},
                "current": {"waveform": {"time": aux_i_time_dcm, "data": aux_i_data_dcm}},
            })

    return {
        "label": label,
        "conditions": {"inputVoltage": inputVoltage},
        "mode": "CCM" if min_primary_current > 0 else "DCM",
        "t1": t1 if min_primary_current > 0 else t1_dcm,
        "excitationsPerWinding": excitations,
    }


# ---------------------------------------------------------------------------
# Convenience wrappers
# ---------------------------------------------------------------------------

def generate_flyback_multi_voltage(
    inputVoltageMin,
    inputVoltageNom,
    inputVoltageMax,
    outputVoltages,
    outputCurrents,
    turnsRatios,
    magnetizingInductance,
    switchingFrequency,
    diodeVoltageDrop=0.7,
    efficiency=1.0,
    currentRippleRatio=None,
    dutyCycle=None,
    deadTime=0.0,
):
    """Run generate_flyback_waveforms for min/nom/max input voltages.

    Returns a list of 1-3 result dicts, matching the C++ collect_input_voltages
    pattern (nom, min, max order).
    """
    results = []
    voltages = []
    labels = []
    if inputVoltageNom is not None and inputVoltageNom > 0:
        voltages.append(inputVoltageNom)
        labels.append("Nom. input volt.")
    if inputVoltageMin is not None and inputVoltageMin > 0:
        voltages.append(inputVoltageMin)
        labels.append("Min. input volt.")
    if inputVoltageMax is not None and inputVoltageMax > 0:
        voltages.append(inputVoltageMax)
        labels.append("Max. input volt.")

    for vin, lbl in zip(voltages, labels):
        results.append(generate_flyback_waveforms(
            inputVoltage=vin,
            outputVoltages=outputVoltages,
            outputCurrents=outputCurrents,
            turnsRatios=turnsRatios,
            magnetizingInductance=magnetizingInductance,
            switchingFrequency=switchingFrequency,
            diodeVoltageDrop=diodeVoltageDrop,
            efficiency=efficiency,
            currentRippleRatio=currentRippleRatio,
            dutyCycle=dutyCycle,
            deadTime=deadTime,
            label=lbl,
        ))
    return results


def generate_push_pull_multi_voltage(
    inputVoltageMin,
    inputVoltageNom,
    inputVoltageMax,
    outputVoltages,
    outputCurrents,
    turnsRatios,
    magnetizingInductance,
    switchingFrequency,
    diodeVoltageDrop=0.7,
    currentRippleRatio=0.3,
    outputInductance=None,
):
    """Run generate_push_pull_waveforms for min/nom/max input voltages.

    Returns a list of 1-3 result dicts, matching the C++ collect_input_voltages
    pattern (nom, min, max order).
    """
    results = []
    voltages = []
    labels = []
    if inputVoltageNom is not None and inputVoltageNom > 0:
        voltages.append(inputVoltageNom)
        labels.append("Nom. input volt.")
    if inputVoltageMin is not None and inputVoltageMin > 0:
        voltages.append(inputVoltageMin)
        labels.append("Min. input volt.")
    if inputVoltageMax is not None and inputVoltageMax > 0:
        voltages.append(inputVoltageMax)
        labels.append("Max. input volt.")

    for vin, lbl in zip(voltages, labels):
        results.append(generate_push_pull_waveforms(
            inputVoltage=vin,
            outputVoltages=outputVoltages,
            outputCurrents=outputCurrents,
            turnsRatios=turnsRatios,
            magnetizingInductance=magnetizingInductance,
            switchingFrequency=switchingFrequency,
            diodeVoltageDrop=diodeVoltageDrop,
            currentRippleRatio=currentRippleRatio,
            outputInductance=outputInductance,
            label=lbl,
        ))
    return results


# ---------------------------------------------------------------------------
# Self-test / demo
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import json

    print("=" * 72)
    print("FLYBACK CONVERTER WAVEFORM TEST")
    print("=" * 72)
    fb_result = generate_flyback_waveforms(
        inputVoltage=100.0,
        outputVoltages=[5.0, 12.0],
        outputCurrents=[10.0, 2.0],
        turnsRatios=[20.0, 8.33],
        magnetizingInductance=500e-6,
        switchingFrequency=100e3,
        diodeVoltageDrop=0.7,
        efficiency=0.9,
        currentRippleRatio=0.4,
        label="Nom. input volt.",
    )
    print(f"Label: {fb_result['label']}")
    print(f"Mode:  {fb_result['mode']}")
    print(f"Duty:  {fb_result['dutyCycle']:.4f}")
    print(f"CRR:   {fb_result['currentRippleRatio']:.4f}")
    print(f"Number of windings: {len(fb_result['excitationsPerWinding'])}")
    for exc in fb_result["excitationsPerWinding"]:
        print(f"  {exc['name']}: freq={exc['frequency']/1e3:.0f} kHz")
        v_wf = exc["voltage"]["waveform"]
        i_wf = exc["current"]["waveform"]
        print(f"    Voltage: {len(v_wf['time'])} points, "
              f"range [{min(v_wf['data']):.2f}, {max(v_wf['data']):.2f}] V")
        print(f"    Current: {len(i_wf['time'])} points, "
              f"range [{min(i_wf['data']):.2f}, {max(i_wf['data']):.2f}] A")

    print()
    print("=" * 72)
    print("PUSH-PULL CONVERTER WAVEFORM TEST (CCM)")
    print("=" * 72)
    pp_result = generate_push_pull_waveforms(
        inputVoltage=48.0,
        outputVoltages=[5.0],
        outputCurrents=[20.0],
        turnsRatios=[4.8],          # Np/Ns = 4.8
        magnetizingInductance=2e-3,
        switchingFrequency=100e3,
        diodeVoltageDrop=0.7,
        currentRippleRatio=0.3,
        label="Nom. input volt.",
    )
    print(f"Label: {pp_result['label']}")
    print(f"Mode:  {pp_result['mode']}")
    print(f"t1:    {pp_result['t1']*1e6:.2f} us")
    print(f"Number of windings: {len(pp_result['excitationsPerWinding'])}")
    for exc in pp_result["excitationsPerWinding"]:
        print(f"  {exc['name']}: freq={exc['frequency']/1e3:.0f} kHz")
        v_wf = exc["voltage"]["waveform"]
        i_wf = exc["current"]["waveform"]
        print(f"    Voltage: {len(v_wf['time'])} points, "
              f"range [{min(v_wf['data']):.2f}, {max(v_wf['data']):.2f}] V")
        print(f"    Current: {len(i_wf['time'])} points, "
              f"range [{min(i_wf['data']):.2f}, {max(i_wf['data']):.2f}] A")

    print()
    print("=" * 72)
    print("PUSH-PULL MULTI-OUTPUT TEST (CCM)")
    print("=" * 72)
    pp2_result = generate_push_pull_waveforms(
        inputVoltage=48.0,
        outputVoltages=[5.0, 12.0],
        outputCurrents=[20.0, 5.0],
        turnsRatios=[4.8, 2.0],
        magnetizingInductance=2e-3,
        switchingFrequency=100e3,
        diodeVoltageDrop=0.7,
        currentRippleRatio=0.3,
        label="Nom. input volt.",
    )
    print(f"Label: {pp2_result['label']}")
    print(f"Mode:  {pp2_result['mode']}")
    print(f"Number of windings: {len(pp2_result['excitationsPerWinding'])}")
    for exc in pp2_result["excitationsPerWinding"]:
        print(f"  {exc['name']}: freq={exc['frequency']/1e3:.0f} kHz")
        v_wf = exc["voltage"]["waveform"]
        i_wf = exc["current"]["waveform"]
        print(f"    Voltage: {len(v_wf['time'])} points, "
              f"range [{min(v_wf['data']):.2f}, {max(v_wf['data']):.2f}] V")
        print(f"    Current: {len(i_wf['time'])} points, "
              f"range [{min(i_wf['data']):.2f}, {max(i_wf['data']):.2f}] A")

    print()
    print("JSON output of flyback result:")
    print(json.dumps(fb_result, indent=2))
