#!/usr/bin/env python3
"""
Converter topology waveform generators ported from MKF C++ source.

Faithful Python ports of the process_operating_points_for_input_voltage()
functions from:
  - MKF-main/src/converter_models/Buck.cpp
  - MKF-main/src/converter_models/Boost.cpp
  - MKF-main/src/converter_models/IsolatedBuck.cpp
  - MKF-main/src/converter_models/IsolatedBuckBoost.cpp

Each function produces waveform time/data arrays that exactly match the
C++ Inputs::create_waveform() helper with identical labels and parameters.

Usage:
    from generate_topology_waveforms import (
        generate_buck_waveforms,
        generate_boost_waveforms,
        generate_isolated_buck_waveforms,
        generate_isolated_buck_boost_waveforms,
    )
"""

import math


# ---------------------------------------------------------------------------
# Waveform construction helpers — exact ports of Inputs::create_waveform()
# from MKF-main/src/processors/Inputs.cpp lines 434-588
# ---------------------------------------------------------------------------

def _create_triangular(peak_to_peak, frequency, duty_cycle, offset):
    """TRIANGULAR waveform (C++ WaveformLabel::TRIANGULAR).

    time: [0, D*T, T]
    data: [min, max, min]

    where min = -pp/2 + offset, max = +pp/2 + offset.
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    w_max = peak_to_peak / 2.0 + offset
    w_min = -peak_to_peak / 2.0 + offset
    return {
        "time": [0.0, dc, period],
        "data": [w_min, w_max, w_min],
    }


def _create_triangular_with_deadtime(peak_to_peak, frequency, duty_cycle, offset, dead_time):
    """TRIANGULAR_WITH_DEADTIME waveform (C++ WaveformLabel::TRIANGULAR_WITH_DEADTIME).

    time: [0, D*T, T - deadTime, T]
    data: [min, max, min, 0]
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    w_max = peak_to_peak / 2.0 + offset
    w_min = -peak_to_peak / 2.0 + offset
    return {
        "time": [0.0, dc, period - dead_time, period],
        "data": [w_min, w_max, w_min, 0.0],
    }


def _create_rectangular(peak_to_peak, frequency, duty_cycle, offset):
    """RECTANGULAR waveform (C++ WaveformLabel::RECTANGULAR).

    time: [0, 0, D*T, D*T, T]
    data: [min, max, max, min, min]

    where max = pp*(1-D) + offset, min = -pp*D + offset.
    This gives a volt-second balanced rectangular pulse.
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    w_max = peak_to_peak * (1.0 - duty_cycle) + offset
    w_min = -peak_to_peak * duty_cycle + offset
    return {
        "time": [0.0, 0.0, dc, dc, period],
        "data": [w_min, w_max, w_max, w_min, w_min],
    }


def _create_rectangular_with_deadtime(peak_to_peak, frequency, duty_cycle, offset, dead_time):
    """RECTANGULAR_WITH_DEADTIME waveform (C++ WaveformLabel::RECTANGULAR_WITH_DEADTIME).

    time: [0, 0, D*T, D*T, T-dt, T-dt, T]
    data: [0, max, max, min, min, 0, 0]
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    w_max = peak_to_peak * (1.0 - duty_cycle) + offset
    w_min = -peak_to_peak * duty_cycle + offset
    return {
        "time": [0.0, 0.0, dc, dc, period - dead_time, period - dead_time, period],
        "data": [0.0, w_max, w_max, w_min, w_min, 0.0, 0.0],
    }


def _create_flyback_primary(peak_to_peak, frequency, duty_cycle, offset, skew=0.0):
    """FLYBACK_PRIMARY waveform (C++ WaveformLabel::FLYBACK_PRIMARY).

    Without skew:
        time: [0, 0, D*T, D*T, T]
        data: [0, min, max, 0, 0]
        where min = offset, max = pp + offset

    With skew > 0: the waveform is sampled, rotated right by skew time,
    then compressed back to piecewise-linear.  This is used by IsolatedBuckBoost
    secondary windings to shift the current pulse by tOn.
    """
    period = 1.0 / frequency
    dc = duty_cycle * period
    w_max = peak_to_peak + offset
    w_min = offset

    if skew <= 0.0:
        return {
            "time": [0.0, 0.0, dc, dc, period],
            "data": [0.0, w_min, w_max, 0.0, 0.0],
        }

    # When skew is nonzero, the C++ code:
    # 1. Samples the waveform at N uniform points (default 8192 in MKF)
    # 2. Rotates the sampled data right by round(skew / (T/N)) samples
    # 3. Compresses back to piecewise-linear via compress_waveform()
    #
    # We replicate this exactly: sample, rotate, compress.
    n_samples = 8192
    dt = period / n_samples

    # Build the un-skewed sampled waveform (linear interpolation)
    base_time = [0.0, 0.0, dc, dc, period]
    base_data = [0.0, w_min, w_max, 0.0, 0.0]

    sampled = _sample_waveform(base_time, base_data, n_samples)

    # Rotate right by skew
    steps = round(skew / dt)
    if steps > 0 and steps < n_samples:
        sampled = sampled[-steps:] + sampled[:-steps]

    # Compress back to piecewise-linear
    sampled_time = [i * dt for i in range(n_samples)]
    compressed_time, compressed_data = _compress_waveform(sampled_time, sampled)

    return {
        "time": compressed_time,
        "data": compressed_data,
    }


def _sample_waveform(time_pts, data_pts, n_samples):
    """Uniformly sample a piecewise-linear waveform at n_samples points."""
    if not time_pts or not data_pts:
        return [0.0] * n_samples

    period = time_pts[-1]
    dt = period / n_samples
    result = []

    seg = 0
    n_seg = len(time_pts) - 1

    for i in range(n_samples):
        t = i * dt

        # Advance segment pointer
        while seg < n_seg - 1 and t >= time_pts[seg + 1]:
            seg += 1

        t0 = time_pts[seg]
        t1 = time_pts[seg + 1]
        d0 = data_pts[seg]
        d1 = data_pts[seg + 1]

        if abs(t1 - t0) < 1e-30:
            # Instantaneous step — use the destination value
            result.append(d1)
        else:
            frac = (t - t0) / (t1 - t0)
            frac = max(0.0, min(1.0, frac))
            result.append(d0 + frac * (d1 - d0))

    return result


def _compress_waveform(time_pts, data_pts, tol=1e-9):
    """Compress a sampled waveform back to piecewise-linear by removing
    collinear interior points.  This matches MKF's compress_waveform().
    """
    if len(data_pts) <= 2:
        return list(time_pts), list(data_pts)

    ct = [time_pts[0]]
    cd = [data_pts[0]]

    for i in range(1, len(data_pts) - 1):
        # Check if point i is collinear with previous kept point and next point
        dt_prev = time_pts[i] - ct[-1]
        dt_next = time_pts[i + 1] - ct[-1]

        if abs(dt_next) < 1e-30:
            ct.append(time_pts[i])
            cd.append(data_pts[i])
            continue

        slope_prev = (data_pts[i] - cd[-1]) / dt_prev if abs(dt_prev) > 1e-30 else float('inf')
        slope_next = (data_pts[i + 1] - cd[-1]) / dt_next

        if abs(slope_prev - slope_next) > tol:
            ct.append(time_pts[i])
            cd.append(data_pts[i])

    ct.append(time_pts[-1])
    cd.append(data_pts[-1])

    return ct, cd


# ---------------------------------------------------------------------------
# Buck converter waveforms — port of Buck.cpp lines 30-82
# ---------------------------------------------------------------------------

def generate_buck_waveforms(
    inputVoltage,
    outputVoltage,
    outputCurrent,
    inductance,
    switchingFrequency,
    diodeVoltageDrop=0.7,
    currentRippleRatio=None,
    efficiency=1.0,
    label="Nom. input volt.",
):
    """Generate Buck converter inductor waveforms for a single input voltage condition.

    Faithful port of Buck::process_operating_points_for_input_voltage() from
    MKF-main/src/converter_models/Buck.cpp.

    The Buck converter has a single inductor winding ("Primary" in MKF convention).
    During on-time: V_L = Vin - Vout (positive, current rises).
    During off-time: V_L = -(Vout + Vd) (negative, current falls through diode).

    Supports both CCM (continuous conduction mode) and DCM (discontinuous conduction
    mode with dead-time) depending on whether the minimum current goes negative.

    Args:
        inputVoltage: Input voltage for this operating condition (V)
        outputVoltage: Output voltage (V)
        outputCurrent: Output/load current (A)
        inductance: Inductor value (H)
        switchingFrequency: Switching frequency (Hz)
        diodeVoltageDrop: Diode forward voltage drop (V), default 0.7
        currentRippleRatio: Not used directly here (inductance is given)
        efficiency: Converter efficiency (0-1), default 1.0
        label: Label string for this operating point

    Returns:
        dict with keys:
            "label": str
            "conditions": {"inputVoltage": float}
            "excitationsPerWinding": [{"name", "frequency", "voltage", "current"}, ...]
    """
    # --- Duty cycle (C++ Buck::calculate_duty_cycle) ---
    # D = (Vout + Vd) / ((Vin + Vd) * eta)
    duty_cycle = (outputVoltage + diodeVoltageDrop) / ((inputVoltage + diodeVoltageDrop) * efficiency)
    if duty_cycle >= 1.0:
        raise ValueError(f"Buck duty cycle {duty_cycle:.4f} >= 1 (Vin={inputVoltage}, Vout={outputVoltage})")

    t_on = duty_cycle / switchingFrequency
    primary_current_pp = (inputVoltage - outputVoltage) * t_on / inductance
    minimum_current = outputCurrent - primary_current_pp / 2.0

    primary_voltage_minimum = -outputVoltage - diodeVoltageDrop
    primary_voltage_maximum = inputVoltage - outputVoltage
    primary_voltage_pp = primary_voltage_maximum - primary_voltage_minimum

    # --- Check CCM vs DCM ---
    if minimum_current < 0:
        # DCM: recalculate tOn and tOff, add dead-time
        # C++ Buck.cpp lines 57-64
        t_on = math.sqrt(
            2.0 * outputCurrent * inductance * (outputVoltage + diodeVoltageDrop)
            / (switchingFrequency * (inputVoltage - outputVoltage) * (inputVoltage + diodeVoltageDrop))
        )
        t_off = t_on * ((inputVoltage + diodeVoltageDrop) / (outputVoltage + diodeVoltageDrop) - 1.0)
        dead_time = 1.0 / switchingFrequency - t_on - t_off
        primary_current_pp = (inputVoltage - outputVoltage) * t_on / inductance
        # In DCM the average output current equals half the peak
        output_current_dcm = primary_current_pp / 2.0

        current_wf = _create_triangular_with_deadtime(
            primary_current_pp, switchingFrequency, duty_cycle, output_current_dcm, dead_time
        )
        voltage_wf = _create_rectangular_with_deadtime(
            primary_voltage_pp, switchingFrequency, duty_cycle, 0.0, dead_time
        )
    else:
        # CCM: standard triangular current + rectangular voltage
        # C++ Buck.cpp lines 68-69
        current_wf = _create_triangular(
            primary_current_pp, switchingFrequency, duty_cycle, outputCurrent
        )
        voltage_wf = _create_rectangular(
            primary_voltage_pp, switchingFrequency, duty_cycle, 0.0
        )

    return {
        "label": label,
        "conditions": {"inputVoltage": inputVoltage},
        "excitationsPerWinding": [
            {
                "name": "Primary",
                "frequency": switchingFrequency,
                "voltage": {"waveform": voltage_wf},
                "current": {"waveform": current_wf},
            }
        ],
    }


# ---------------------------------------------------------------------------
# Boost converter waveforms — port of Boost.cpp lines 31-85
# ---------------------------------------------------------------------------

def generate_boost_waveforms(
    inputVoltage,
    outputVoltage,
    outputCurrent,
    inductance,
    switchingFrequency,
    diodeVoltageDrop=0.7,
    currentRippleRatio=None,
    efficiency=1.0,
    label="Nom. input volt.",
):
    """Generate Boost converter inductor waveforms for a single input voltage condition.

    Faithful port of Boost::process_operating_points_for_input_voltage() from
    MKF-main/src/converter_models/Boost.cpp.

    The Boost converter has a single inductor winding ("Primary" in MKF convention).
    During on-time: V_L = Vin (positive, current rises through inductor to ground).
    During off-time: V_L = Vin - Vout - Vd (negative, current flows through diode to output).

    The average inductor current equals the average input current, which is higher
    than the output current by the boost ratio: Iin = Iout * (Vout + Vd) / Vin.

    Args:
        inputVoltage: Input voltage for this operating condition (V)
        outputVoltage: Output voltage (V), must be > inputVoltage for boost
        outputCurrent: Output/load current (A)
        inductance: Inductor value (H)
        switchingFrequency: Switching frequency (Hz)
        diodeVoltageDrop: Diode forward voltage drop (V), default 0.7
        currentRippleRatio: Not used directly here (inductance is given)
        efficiency: Converter efficiency (0-1), default 1.0
        label: Label string for this operating point

    Returns:
        dict matching the standard return format (see generate_buck_waveforms).
    """
    # --- Duty cycle (C++ Boost::calculate_duty_cycle) ---
    # D = 1 - Vin * eta / (Vout + Vd)
    duty_cycle = 1.0 - inputVoltage * efficiency / (outputVoltage + diodeVoltageDrop)
    if duty_cycle >= 1.0:
        raise ValueError(f"Boost duty cycle {duty_cycle:.4f} >= 1 (Vin={inputVoltage}, Vout={outputVoltage})")

    t_on = duty_cycle / switchingFrequency
    primary_current_pp = inputVoltage * t_on / inductance

    # Average inductor (= input) current: Iin = Iout * (Vout + Vd) / Vin
    primary_current_average = outputCurrent * (outputVoltage + diodeVoltageDrop) / inputVoltage
    primary_current_minimum = primary_current_average - primary_current_pp / 2.0

    # Inductor voltage levels
    primary_voltage_minimum = inputVoltage - outputVoltage - diodeVoltageDrop  # off-time (negative)
    primary_voltage_maximum = inputVoltage                                      # on-time (positive)
    primary_voltage_pp = primary_voltage_maximum - primary_voltage_minimum

    # --- Check CCM vs DCM ---
    if primary_current_minimum < 0:
        # DCM: recalculate tOn, tOff, dead-time
        # C++ Boost.cpp lines 60-66
        t_on = math.sqrt(
            2.0 * outputCurrent * inductance * (outputVoltage + diodeVoltageDrop - inputVoltage)
            / (switchingFrequency * inputVoltage ** 2)
        )
        t_off = t_on * (
            (outputVoltage + diodeVoltageDrop) / (outputVoltage + diodeVoltageDrop - inputVoltage) - 1.0
        )
        dead_time = 1.0 / switchingFrequency - t_on - t_off
        # In DCM the average output current equals half the peak
        output_current_dcm = primary_current_pp / 2.0

        current_wf = _create_triangular_with_deadtime(
            primary_current_pp, switchingFrequency, duty_cycle, output_current_dcm, dead_time
        )
        voltage_wf = _create_rectangular_with_deadtime(
            primary_voltage_pp, switchingFrequency, duty_cycle, 0.0, dead_time
        )
    else:
        # CCM: standard triangular current + rectangular voltage
        # C++ Boost.cpp lines 71-72
        current_wf = _create_triangular(
            primary_current_pp, switchingFrequency, duty_cycle, primary_current_average
        )
        voltage_wf = _create_rectangular(
            primary_voltage_pp, switchingFrequency, duty_cycle, 0.0
        )

    return {
        "label": label,
        "conditions": {"inputVoltage": inputVoltage},
        "excitationsPerWinding": [
            {
                "name": "Primary",
                "frequency": switchingFrequency,
                "voltage": {"waveform": voltage_wf},
                "current": {"waveform": current_wf},
            }
        ],
    }


# ---------------------------------------------------------------------------
# Isolated Buck converter waveforms — port of IsolatedBuck.cpp lines 26-128
# ---------------------------------------------------------------------------

def generate_isolated_buck_waveforms(
    inputVoltage,
    outputVoltages,
    outputCurrents,
    turnsRatios,
    inductance,
    switchingFrequency,
    diodeVoltageDrop=0.7,
    currentRippleRatio=None,
    efficiency=1.0,
    label="Nom. input volt.",
):
    """Generate Isolated Buck (Flybuck) converter waveforms for a single input voltage.

    Faithful port of IsolatedBuck::processOperatingPointsForInputVoltage() from
    MKF-main/src/converter_models/IsolatedBuck.cpp.

    The Isolated Buck has:
      - A primary winding (buck inductor, coupled to secondaries)
      - One or more secondary windings (galvanically isolated outputs)

    Output voltages/currents convention from C++:
      outputVoltages[0] = primary output voltage (non-isolated buck output)
      outputVoltages[1..N] = secondary output voltages (isolated)
      outputCurrents[0] = primary output current
      outputCurrents[1..N] = secondary output currents
      turnsRatios[i] = Np/Ns for secondary i (ratio to outputVoltages[i+1])

    Primary winding:
      - Triangular current: magnetizing ripple + reflected load currents
      - Rectangular voltage: (Vin - Vpri_out) during on, (-Vpri_out) during off

    Secondary windings (custom waveforms):
      - Current: zero during on-time, ramps during off-time (freewheeling)
      - Voltage: reflects primary voltage scaled by turns ratio, offset by Vd

    Args:
        inputVoltage: Input voltage for this operating condition (V)
        outputVoltages: List of output voltages [Vpri_out, Vsec0, Vsec1, ...] (V)
        outputCurrents: List of output currents [Ipri_out, Isec0, Isec1, ...] (A)
        turnsRatios: List of Np/Ns ratios for each secondary [ratio0, ratio1, ...]
        inductance: Magnetizing inductance (H)
        switchingFrequency: Switching frequency (Hz)
        diodeVoltageDrop: Diode forward voltage drop (V), default 0.7
        currentRippleRatio: Not used directly here
        efficiency: Converter efficiency (0-1), default 1.0
        label: Label string for this operating point

    Returns:
        dict matching the standard return format.
    """
    primary_output_voltage = outputVoltages[0]
    primary_output_current = outputCurrents[0]

    # Total reflected secondary current on primary side
    total_reflected_secondary_current = 0.0
    for sec_idx in range(len(turnsRatios)):
        total_reflected_secondary_current += outputCurrents[sec_idx] / turnsRatios[sec_idx]

    # --- Duty cycle (C++ IsolatedBuck::calculate_duty_cycle) ---
    # D = Vout / (Vin * eta)   [note: no Vd in isolated buck duty cycle formula]
    duty_cycle = primary_output_voltage / inputVoltage * efficiency
    if duty_cycle >= 1.0:
        raise ValueError(
            f"IsolatedBuck duty cycle {duty_cycle:.4f} >= 1 "
            f"(Vin={inputVoltage}, Vout={primary_output_voltage})"
        )

    period = 1.0 / switchingFrequency
    t_on = duty_cycle * period

    # Magnetizing current ripple
    magnetizing_current_ripple = (inputVoltage - primary_output_voltage) * t_on / inductance

    # Primary current peak-to-peak (C++ lines 49-51)
    primary_current_maximum = (
        primary_output_current
        + total_reflected_secondary_current
        + magnetizing_current_ripple / 2.0
    )
    primary_current_minimum = (
        primary_output_current
        - total_reflected_secondary_current * (2.0 * duty_cycle) / (1.0 - duty_cycle)
        - magnetizing_current_ripple / 2.0
    )
    primary_current_pp = primary_current_maximum - primary_current_minimum

    # Primary voltage levels (C++ lines 53-55)
    primary_voltage_maximum = inputVoltage - primary_output_voltage
    primary_voltage_minimum = -primary_output_voltage
    primary_voltage_pp = primary_voltage_maximum - primary_voltage_minimum

    # --- Primary winding ---
    # C++ line 62-63: TRIANGULAR current, RECTANGULAR voltage (always CCM for isolated buck)
    primary_current_wf = _create_triangular(
        primary_current_pp, switchingFrequency, duty_cycle, primary_output_current
    )
    primary_voltage_wf = _create_rectangular(
        primary_voltage_pp, switchingFrequency, duty_cycle, 0.0
    )

    excitations = [
        {
            "name": "Primary",
            "frequency": switchingFrequency,
            "voltage": {"waveform": primary_voltage_wf},
            "current": {"waveform": primary_current_wf},
        }
    ]

    # --- Secondary windings (custom waveforms) ---
    # C++ IsolatedBuck.cpp lines 70-120
    for sec_idx in range(len(turnsRatios)):
        secondary_output_current = outputCurrents[sec_idx]

        # Secondary current bounds (C++ lines 75-76)
        secondary_current_maximum = (
            (1.0 + duty_cycle) / (1.0 - duty_cycle) * secondary_output_current
            - secondary_output_current
        )
        secondary_current_minimum = 0.0

        # Secondary voltage bounds (C++ lines 78-79)
        secondary_voltage_maximum = (
            (inputVoltage - primary_output_voltage) / turnsRatios[sec_idx]
            - diodeVoltageDrop
        )
        secondary_voltage_minimum = (
            -primary_output_voltage / turnsRatios[sec_idx]
            + diodeVoltageDrop
        )

        # Custom current waveform (C++ lines 82-98)
        # During on-time (0 to tOn): current is zero (secondary diode reverse-biased)
        # At tOn: current jumps to (Iout + Imin) and ramps to (Iout + Imax) during off-time
        sec_current_data = [
            0.0,
            0.0,
            secondary_output_current + secondary_current_minimum,
            secondary_output_current + secondary_current_maximum,
        ]
        sec_current_time = [0.0, t_on, t_on, period]

        # Custom voltage waveform (C++ lines 100-116)
        # During on-time: voltage is at minimum (reflected primary off-voltage)
        # During off-time: voltage is at maximum (reflected primary on-voltage)
        sec_voltage_data = [
            secondary_voltage_minimum,
            secondary_voltage_minimum,
            secondary_voltage_maximum,
            secondary_voltage_maximum,
        ]
        sec_voltage_time = [0.0, t_on, t_on, period]

        excitations.append({
            "name": f"Secondary {sec_idx}",
            "frequency": switchingFrequency,
            "voltage": {"waveform": {"time": sec_voltage_time, "data": sec_voltage_data}},
            "current": {"waveform": {"time": sec_current_time, "data": sec_current_data}},
        })

    return {
        "label": label,
        "conditions": {"inputVoltage": inputVoltage},
        "excitationsPerWinding": excitations,
    }


# ---------------------------------------------------------------------------
# Isolated Buck-Boost converter waveforms — port of IsolatedBuckBoost.cpp lines 30-97
# ---------------------------------------------------------------------------

def generate_isolated_buck_boost_waveforms(
    inputVoltage,
    outputVoltages,
    outputCurrents,
    turnsRatios,
    inductance,
    switchingFrequency,
    diodeVoltageDrop=0.7,
    currentRippleRatio=None,
    efficiency=1.0,
    label="Nom. input volt.",
):
    """Generate Isolated Buck-Boost converter waveforms for a single input voltage.

    Faithful port of IsolatedBuckBoost::processOperatingPointsForInputVoltage() from
    MKF-main/src/converter_models/IsolatedBuckBoost.cpp.

    The Isolated Buck-Boost operates like a flyback: the primary magnetizing
    inductance stores energy during the on-time and transfers it to the output
    during the off-time.  Unlike a standard flyback, the primary also has a
    direct (non-isolated) output through a diode.

    Output voltages/currents convention from C++:
      outputVoltages[0] = primary output voltage (non-isolated buck-boost output)
      outputVoltages[1..N] = secondary output voltages (isolated)
      outputCurrents[0] = primary output current
      outputCurrents[1..N] = secondary output currents
      turnsRatios[i] = Np/Ns for secondary i

    Primary winding:
      - Triangular current with offset = primaryOutputCurrent
      - Rectangular voltage: Vin during on-time, (Vout - Vd) during off-time

    Secondary windings:
      - FLYBACK_PRIMARY label with duty = (1-D) and skew = tOn
        (current ramps during off-time, zero during on-time)
      - RECTANGULAR voltage with duty = (1-D) and skew = tOn

    Args:
        inputVoltage: Input voltage for this operating condition (V)
        outputVoltages: List [Vpri_out, Vsec0, Vsec1, ...]
        outputCurrents: List [Ipri_out, Isec0, Isec1, ...]
        turnsRatios: List of Np/Ns ratios [ratio0, ratio1, ...]
        inductance: Magnetizing inductance (H)
        switchingFrequency: Switching frequency (Hz)
        diodeVoltageDrop: Diode forward voltage drop (V), default 0.7
        currentRippleRatio: Not used directly here
        efficiency: Converter efficiency (0-1), default 1.0
        label: Label string for this operating point

    Returns:
        dict matching the standard return format.
    """
    primary_output_voltage = outputVoltages[0]
    primary_output_current = outputCurrents[0]

    # Total reflected secondary current on primary side
    total_reflected_secondary_current = 0.0
    for sec_idx in range(len(turnsRatios)):
        total_reflected_secondary_current += outputCurrents[sec_idx] / turnsRatios[sec_idx]

    # --- Duty cycle (C++ IsolatedBuckBoost::calculate_duty_cycle) ---
    # D = Vout / (Vin + Vout) * eta
    duty_cycle = primary_output_voltage / (inputVoltage + primary_output_voltage) * efficiency
    if duty_cycle >= 1.0:
        raise ValueError(
            f"IsolatedBuckBoost duty cycle {duty_cycle:.4f} >= 1 "
            f"(Vin={inputVoltage}, Vout={primary_output_voltage})"
        )

    t_on = duty_cycle / switchingFrequency

    # Primary current peak-to-peak (C++ line 52)
    # This is the harmonic-mean formula: Vin*Vout / (Vin+Vout) / (fsw*L)
    primary_current_pp = (
        (inputVoltage * primary_output_voltage)
        / (inputVoltage + primary_output_voltage)
        / (switchingFrequency * inductance)
    )

    # Primary voltage levels (C++ lines 54-56, note typo "Voltave" in C++)
    primary_voltage_maximum = inputVoltage
    primary_voltage_minimum = primary_output_voltage - diodeVoltageDrop
    primary_voltage_pp = primary_voltage_maximum - primary_voltage_minimum

    # --- Primary winding ---
    # C++ lines 63-64: TRIANGULAR current, RECTANGULAR voltage
    primary_current_wf = _create_triangular(
        primary_current_pp, switchingFrequency, duty_cycle, primary_output_current
    )
    primary_voltage_wf = _create_rectangular(
        primary_voltage_pp, switchingFrequency, duty_cycle, 0.0
    )

    excitations = [
        {
            "name": "Primary",
            "frequency": switchingFrequency,
            "voltage": {"waveform": primary_voltage_wf},
            "current": {"waveform": primary_current_wf},
        }
    ]

    # --- Secondary windings ---
    # C++ IsolatedBuckBoost.cpp lines 71-89
    for sec_idx in range(len(turnsRatios)):
        secondary_output_current = outputCurrents[sec_idx]

        # Secondary current bounds (C++ lines 76-78)
        secondary_current_maximum = (
            (1.0 + duty_cycle) / (1.0 - duty_cycle) * secondary_output_current
            - secondary_output_current
        )
        secondary_current_minimum = 0.0
        secondary_current_pp = secondary_current_maximum - secondary_current_minimum

        # Secondary voltage bounds (C++ lines 80-82)
        secondary_voltage_maximum = inputVoltage / turnsRatios[sec_idx] - diodeVoltageDrop
        secondary_voltage_minimum = (
            (primary_output_voltage - diodeVoltageDrop) / turnsRatios[sec_idx]
            + diodeVoltageDrop
        )
        secondary_voltage_pp = secondary_voltage_maximum - secondary_voltage_minimum

        # C++ line 84: FLYBACK_PRIMARY label with duty = (1-D), offset = Iout, skew = tOn
        # The flyback primary waveform ramps from offset to (offset + pp) during
        # the secondary's conduction period (1-D), but is shifted in time by tOn
        # so that the ramp occurs during the primary off-time.
        sec_current_wf = _create_flyback_primary(
            secondary_current_pp,
            switchingFrequency,
            1.0 - duty_cycle,
            secondary_output_current,
            skew=t_on,
        )

        # C++ line 85: RECTANGULAR voltage with duty = (1-D), offset = 0, skew = tOn
        # Same time-shifting as the current: the secondary voltage pulse appears
        # during the off-time of the primary.
        sec_voltage_wf = _create_rectangular(
            secondary_voltage_pp, switchingFrequency, 1.0 - duty_cycle, 0.0
        )

        # Apply the same skew rotation to the voltage waveform
        if t_on > 0:
            period = 1.0 / switchingFrequency
            n_samples = 8192
            dt = period / n_samples

            # Sample the rectangular waveform
            v_sampled = _sample_waveform(
                sec_voltage_wf["time"], sec_voltage_wf["data"], n_samples
            )

            # Rotate right by tOn
            steps = round(t_on / dt)
            if 0 < steps < n_samples:
                v_sampled = v_sampled[-steps:] + v_sampled[:-steps]

            # Compress back
            v_time = [i * dt for i in range(n_samples)]
            ct, cd = _compress_waveform(v_time, v_sampled)
            sec_voltage_wf = {"time": ct, "data": cd}

        excitations.append({
            "name": f"Secondary {sec_idx}",
            "frequency": switchingFrequency,
            "voltage": {"waveform": sec_voltage_wf},
            "current": {"waveform": sec_current_wf},
        })

    return {
        "label": label,
        "conditions": {"inputVoltage": inputVoltage},
        "excitationsPerWinding": excitations,
    }


# ---------------------------------------------------------------------------
# Multi-voltage convenience wrappers (matching C++ process_operating_points)
# ---------------------------------------------------------------------------

def generate_buck_waveforms_all_voltages(
    inputVoltage_min,
    inputVoltage_nom,
    inputVoltage_max,
    outputVoltage,
    outputCurrent,
    inductance,
    switchingFrequency,
    diodeVoltageDrop=0.7,
    efficiency=1.0,
):
    """Generate Buck waveforms for min/nom/max input voltages.

    Mirrors C++ Buck::process_operating_points() which iterates over
    collect_input_voltages() to produce one OperatingPoint per voltage.
    """
    results = []
    voltages = [
        (inputVoltage_nom, "Nom. input volt."),
        (inputVoltage_min, "Min. input volt."),
        (inputVoltage_max, "Max. input volt."),
    ]
    for vin, lbl in voltages:
        if vin is not None and vin > 0:
            results.append(generate_buck_waveforms(
                inputVoltage=vin,
                outputVoltage=outputVoltage,
                outputCurrent=outputCurrent,
                inductance=inductance,
                switchingFrequency=switchingFrequency,
                diodeVoltageDrop=diodeVoltageDrop,
                efficiency=efficiency,
                label=lbl,
            ))
    return results


def generate_boost_waveforms_all_voltages(
    inputVoltage_min,
    inputVoltage_nom,
    inputVoltage_max,
    outputVoltage,
    outputCurrent,
    inductance,
    switchingFrequency,
    diodeVoltageDrop=0.7,
    efficiency=1.0,
):
    """Generate Boost waveforms for min/nom/max input voltages."""
    results = []
    voltages = [
        (inputVoltage_nom, "Nom. input volt."),
        (inputVoltage_min, "Min. input volt."),
        (inputVoltage_max, "Max. input volt."),
    ]
    for vin, lbl in voltages:
        if vin is not None and vin > 0:
            results.append(generate_boost_waveforms(
                inputVoltage=vin,
                outputVoltage=outputVoltage,
                outputCurrent=outputCurrent,
                inductance=inductance,
                switchingFrequency=switchingFrequency,
                diodeVoltageDrop=diodeVoltageDrop,
                efficiency=efficiency,
                label=lbl,
            ))
    return results


def generate_isolated_buck_waveforms_all_voltages(
    inputVoltage_min,
    inputVoltage_nom,
    inputVoltage_max,
    outputVoltages,
    outputCurrents,
    turnsRatios,
    inductance,
    switchingFrequency,
    diodeVoltageDrop=0.7,
    efficiency=1.0,
):
    """Generate Isolated Buck waveforms for min/nom/max input voltages."""
    results = []
    voltages = [
        (inputVoltage_nom, "Nom. input volt."),
        (inputVoltage_min, "Min. input volt."),
        (inputVoltage_max, "Max. input volt."),
    ]
    for vin, lbl in voltages:
        if vin is not None and vin > 0:
            results.append(generate_isolated_buck_waveforms(
                inputVoltage=vin,
                outputVoltages=outputVoltages,
                outputCurrents=outputCurrents,
                turnsRatios=turnsRatios,
                inductance=inductance,
                switchingFrequency=switchingFrequency,
                diodeVoltageDrop=diodeVoltageDrop,
                efficiency=efficiency,
                label=lbl,
            ))
    return results


def generate_isolated_buck_boost_waveforms_all_voltages(
    inputVoltage_min,
    inputVoltage_nom,
    inputVoltage_max,
    outputVoltages,
    outputCurrents,
    turnsRatios,
    inductance,
    switchingFrequency,
    diodeVoltageDrop=0.7,
    efficiency=1.0,
):
    """Generate Isolated Buck-Boost waveforms for min/nom/max input voltages."""
    results = []
    voltages = [
        (inputVoltage_nom, "Nom. input volt."),
        (inputVoltage_min, "Min. input volt."),
        (inputVoltage_max, "Max. input volt."),
    ]
    for vin, lbl in voltages:
        if vin is not None and vin > 0:
            results.append(generate_isolated_buck_boost_waveforms(
                inputVoltage=vin,
                outputVoltages=outputVoltages,
                outputCurrents=outputCurrents,
                turnsRatios=turnsRatios,
                inductance=inductance,
                switchingFrequency=switchingFrequency,
                diodeVoltageDrop=diodeVoltageDrop,
                efficiency=efficiency,
                label=lbl,
            ))
    return results


# ---------------------------------------------------------------------------
# Self-test / CLI
# ---------------------------------------------------------------------------

def _run_self_test():
    """Run quick validation tests for all 4 topologies."""
    import json as _json

    print("=" * 72)
    print("Self-test: generate_topology_waveforms.py")
    print("=" * 72)

    # ---- Buck ----
    print("\n--- Buck Converter (CCM) ---")
    buck = generate_buck_waveforms(
        inputVoltage=48.0,
        outputVoltage=12.0,
        outputCurrent=5.0,
        inductance=100e-6,
        switchingFrequency=200e3,
        diodeVoltageDrop=0.7,
    )
    exc = buck["excitationsPerWinding"][0]
    print(f"  Label:     {buck['label']}")
    print(f"  Winding:   {exc['name']}")
    print(f"  Frequency: {exc['frequency'] / 1e3:.0f} kHz")
    print(f"  Current time pts:  {len(exc['current']['waveform']['time'])}")
    print(f"  Current data:      {[f'{v:.4f}' for v in exc['current']['waveform']['data']]}")
    print(f"  Voltage time pts:  {len(exc['voltage']['waveform']['time'])}")
    print(f"  Voltage data:      {[f'{v:.4f}' for v in exc['voltage']['waveform']['data']]}")

    # Verify duty cycle: D = (12 + 0.7) / ((48 + 0.7) * 1) = 0.2609
    d_expected = (12.0 + 0.7) / (48.0 + 0.7)
    t_on_expected = d_expected / 200e3
    i_pp_expected = (48.0 - 12.0) * t_on_expected / 100e-6
    print(f"  Expected D = {d_expected:.4f}")
    print(f"  Expected i_pp = {i_pp_expected:.4f} A")
    i_data = exc['current']['waveform']['data']
    i_pp_actual = max(i_data) - min(i_data)
    print(f"  Actual i_pp   = {i_pp_actual:.4f} A")
    assert abs(i_pp_actual - i_pp_expected) < 1e-6, "Buck CCM i_pp mismatch!"

    # ---- Buck DCM ----
    print("\n--- Buck Converter (DCM, low current) ---")
    buck_dcm = generate_buck_waveforms(
        inputVoltage=48.0,
        outputVoltage=12.0,
        outputCurrent=0.1,  # very light load -> DCM
        inductance=100e-6,
        switchingFrequency=200e3,
        diodeVoltageDrop=0.7,
    )
    exc_dcm = buck_dcm["excitationsPerWinding"][0]
    print(f"  Current time pts:  {len(exc_dcm['current']['waveform']['time'])}")
    print(f"  Current data:      {[f'{v:.4f}' for v in exc_dcm['current']['waveform']['data']]}")
    print(f"  Voltage data:      {[f'{v:.4f}' for v in exc_dcm['voltage']['waveform']['data']]}")
    # DCM should have 4 time points for current (triangular with deadtime)
    assert len(exc_dcm['current']['waveform']['time']) == 4, "Buck DCM should have 4 time points"

    # ---- Boost ----
    print("\n--- Boost Converter (CCM) ---")
    boost = generate_boost_waveforms(
        inputVoltage=12.0,
        outputVoltage=48.0,
        outputCurrent=2.0,
        inductance=50e-6,
        switchingFrequency=200e3,
        diodeVoltageDrop=0.7,
    )
    exc = boost["excitationsPerWinding"][0]
    print(f"  Label:     {boost['label']}")
    print(f"  Winding:   {exc['name']}")
    print(f"  Current data:      {[f'{v:.4f}' for v in exc['current']['waveform']['data']]}")
    print(f"  Voltage data:      {[f'{v:.4f}' for v in exc['voltage']['waveform']['data']]}")

    # Verify duty cycle: D = 1 - 12 / (48 + 0.7) = 0.7536
    d_boost = 1.0 - 12.0 / (48.0 + 0.7)
    i_avg = 2.0 * (48.0 + 0.7) / 12.0
    print(f"  Expected D = {d_boost:.4f}")
    print(f"  Expected Iin_avg = {i_avg:.4f} A")

    # ---- Isolated Buck ----
    print("\n--- Isolated Buck Converter ---")
    iso_buck = generate_isolated_buck_waveforms(
        inputVoltage=48.0,
        outputVoltages=[24.0, 5.0],      # primary out + 1 secondary
        outputCurrents=[2.0, 3.0],        # primary current + secondary current
        turnsRatios=[4.8],                 # Np/Ns for secondary 0
        inductance=200e-6,
        switchingFrequency=200e3,
        diodeVoltageDrop=0.7,
    )
    print(f"  Label:     {iso_buck['label']}")
    print(f"  Num windings: {len(iso_buck['excitationsPerWinding'])}")
    for i, exc in enumerate(iso_buck["excitationsPerWinding"]):
        print(f"  [{i}] {exc['name']}:")
        print(f"      Current data: {[f'{v:.4f}' for v in exc['current']['waveform']['data']]}")
        print(f"      Voltage data: {[f'{v:.4f}' for v in exc['voltage']['waveform']['data']]}")

    # ---- Isolated Buck-Boost ----
    print("\n--- Isolated Buck-Boost Converter ---")
    iso_bb = generate_isolated_buck_boost_waveforms(
        inputVoltage=48.0,
        outputVoltages=[24.0, 12.0],      # primary out + 1 secondary
        outputCurrents=[1.0, 2.0],        # primary + secondary
        turnsRatios=[2.0],                 # Np/Ns
        inductance=100e-6,
        switchingFrequency=200e3,
        diodeVoltageDrop=0.7,
    )
    print(f"  Label:     {iso_bb['label']}")
    print(f"  Num windings: {len(iso_bb['excitationsPerWinding'])}")
    for i, exc in enumerate(iso_bb["excitationsPerWinding"]):
        n_pts = len(exc['current']['waveform']['time'])
        print(f"  [{i}] {exc['name']}: {n_pts} time points")
        if n_pts <= 10:
            print(f"      Current data: {[f'{v:.4f}' for v in exc['current']['waveform']['data']]}")
            print(f"      Voltage data: {[f'{v:.4f}' for v in exc['voltage']['waveform']['data']]}")
        else:
            print(f"      (skew-rotated sampled waveform with {n_pts} points)")

    # ---- Multi-voltage convenience ----
    print("\n--- Multi-voltage Buck ---")
    multi = generate_buck_waveforms_all_voltages(
        inputVoltage_min=36.0,
        inputVoltage_nom=48.0,
        inputVoltage_max=60.0,
        outputVoltage=12.0,
        outputCurrent=5.0,
        inductance=100e-6,
        switchingFrequency=200e3,
    )
    print(f"  Generated {len(multi)} operating points:")
    for op in multi:
        print(f"    {op['label']} (Vin={op['conditions']['inputVoltage']}V)")

    print("\n" + "=" * 72)
    print("All self-tests PASSED.")
    print("=" * 72)


if __name__ == "__main__":
    import sys as _sys
    if len(_sys.argv) > 1 and _sys.argv[1] == "--test":
        _run_self_test()
    elif len(_sys.argv) > 1:
        # JSON config mode: read config, generate waveforms, write results
        import json as _json
        config_path = _sys.argv[1]
        with open(config_path, 'r') as f:
            config = _json.load(f)

        topology = config.get("topology", "buck")
        vin = config.get("inputVoltage", 48.0)
        vout = config.get("outputVoltage", 12.0)
        iout = config.get("outputCurrent", 5.0)
        inductance = config.get("inductance", 100e-6)
        fsw = config.get("switchingFrequency", 200e3)
        vd = config.get("diodeVoltageDrop", 0.7)
        eta = config.get("efficiency", 1.0)

        # For isolated topologies
        vout_list = config.get("outputVoltages", [vout])
        iout_list = config.get("outputCurrents", [iout])
        turns_ratios = config.get("turnsRatios", [1.0])

        if topology == "buck":
            result = generate_buck_waveforms(vin, vout, iout, inductance, fsw, vd, efficiency=eta)
        elif topology == "boost":
            result = generate_boost_waveforms(vin, vout, iout, inductance, fsw, vd, efficiency=eta)
        elif topology == "isolated_buck":
            result = generate_isolated_buck_waveforms(
                vin, vout_list, iout_list, turns_ratios, inductance, fsw, vd, efficiency=eta
            )
        elif topology == "isolated_buck_boost":
            result = generate_isolated_buck_boost_waveforms(
                vin, vout_list, iout_list, turns_ratios, inductance, fsw, vd, efficiency=eta
            )
        else:
            result = {"error": f"Unknown topology: {topology}"}

        output_file = config.get("output_file", "topology_waveform_results.json")
        with open(output_file, 'w') as f:
            _json.dump(result, f, indent=2)
        print(f"[WAVEFORMS] Written to {output_file}")
    else:
        print("Usage:")
        print("  python generate_topology_waveforms.py --test")
        print("  python generate_topology_waveforms.py config.json")
