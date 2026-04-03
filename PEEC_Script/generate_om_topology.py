#!/usr/bin/env python3
"""
Converter topology calculator bridge for OpenMagnetics API.

Implements converter equations for 9 topologies and builds MAS-format inputs.
Called by topology_wizard.m via JSON I/O.

Modes:
  compute_topology - Calculate design requirements and build MAS inputs from converter specs

Usage:
    python generate_om_topology.py config.json

Input JSON (om_topology_config.json):
  {
    "mode": "compute_topology",
    "topology": "two_switch_forward",
    "design_mode": "auto",
    "converter": { ... },
    "advanced": { ... },
    "output_file": "om_topology_results.json"
  }

Output JSON (om_topology_results.json):
  {
    "status": "OK|ERROR",
    "topology": "two_switch_forward",
    "topology_display": "Two-Switch Forward Converter",
    "design_mode": "auto",
    "computed": { ... },
    "mas_inputs": { ... }
  }
"""

import json
import math
import os
import sys
import importlib.metadata

from om_shared import as_float, clamp, as_list, import_pyopenmagnetics

try:
    pm = import_pyopenmagnetics()
except Exception as exc:
    print(f"[TOPOLOGY] ImportError: {exc}", file=sys.stderr)
    sys.exit(1)


class TopologyCalculator:
    """Base class for converter topology calculators."""

    def __init__(self):
        self.topology_key = None
        self.topology_display = None
        self.n_windings_min = 1
        self.n_windings_max = 1

    def get_topology_display_name(self):
        """Return display name for the topology."""
        return self.topology_display or "Unknown"

    def get_n_windings(self):
        """Return number of windings (for MAS schema)."""
        return self.n_windings_min

    def compute_design_requirements(self, converter, advanced, n_outputs=1):
        """
        Compute design requirements from converter specifications.

        Args:
            converter: dict with inputVoltage, diodeVoltageDrop, efficiency, currentRippleRatio,
                      maximumSwitchCurrent, operatingPoints[]
            advanced: dict with desiredInductance, desiredDutyCycle, desiredTurnsRatios, etc.
            n_outputs: number of output voltages (for multi-output topologies)

        Returns:
            dict with Lm_uH, turnsRatios[], duty_nom, currents, etc.
        """
        raise NotImplementedError(f"{self.__class__.__name__}.compute_design_requirements")

    def _make_rectangular_excitation(self, name, freq, i_pp, i_offset, v_pp, v_offset, duty):
        """Build a MAS excitation dict with rectangular current and voltage waveforms.
        The processed waveform is what the PyOpenMagnetics adviser uses to compute losses
        and select cores. Without it the adviser receives zero-current excitations and
        produces topology-agnostic (often toroid-favouring) results.
        """
        return {
            "name": name,
            "frequency": freq,
            "current": {
                "processed": {
                    "label": "Rectangular",
                    "peakToPeak": float(abs(i_pp)),
                    "offset": float(i_offset),
                    "dutyCycle": float(clamp(duty, 0.01, 0.99)),
                }
            },
            "voltage": {
                "processed": {
                    "label": "Rectangular",
                    "peakToPeak": float(abs(v_pp)),
                    "offset": float(v_offset),
                    "dutyCycle": float(clamp(duty, 0.01, 0.99)),
                }
            },
        }

    def _make_triangular_excitation(self, name, freq, i_pp, i_offset, v_pp, v_offset, duty):
        """Build a MAS excitation dict with triangular current waveform (for Buck/Boost/IsolatedBuck)."""
        return {
            "name": name,
            "frequency": freq,
            "current": {
                "processed": {
                    "label": "Triangular",
                    "peakToPeak": float(abs(i_pp)),
                    "offset": float(i_offset),
                    "dutyCycle": float(clamp(duty, 0.01, 0.99)),
                }
            },
            "voltage": {
                "processed": {
                    "label": "Rectangular",
                    "peakToPeak": float(abs(v_pp)),
                    "offset": float(v_offset),
                    "dutyCycle": float(clamp(duty, 0.01, 0.99)),
                }
            },
        }

    def _make_forward_excitation(self, name, freq, duty, vin,
                                    i_load_reflected, i_mag_pp,
                                    v_sec=None, i_out=None, i_ripple_ratio=0.3,
                                    demag_ratio=1.0):
        """Build a MAS excitation with volt-second-balanced waveforms for forward converters.

        For primary: 3-phase waveform (on / demagnetize / dead time).
        For secondary: 2-phase waveform (on / off) with dead-time zero.

        Args:
            demag_ratio: ratio of demagnetization voltage to on-time voltage.
                         For two-switch forward: 1.0 (V_demag = Vin).
                         For single-switch forward: Vin/(Vclamp - Vin).
        """
        T = 1.0 / freq
        d = clamp(duty, 0.01, 0.49)  # forward converter D < 0.5
        d_demag = d * demag_ratio  # demagnetization duty cycle
        if d + d_demag > 0.99:
            d_demag = 0.99 - d

        is_primary = (v_sec is None)

        if is_primary:
            # Primary voltage: +Vin during on, -Vin*demag_ratio during demag, 0 during dead
            v_on = vin
            v_demag = -vin * demag_ratio
            v_time = [0.0, 0.0, d * T, d * T, (d + d_demag) * T, (d + d_demag) * T, T]
            v_data = [0.0, v_on, v_on, v_demag, v_demag, 0.0, 0.0]

            # Primary current: load+mag during on, mag during demag, 0 during dead
            i_on_start = i_load_reflected + i_mag_pp / 2
            i_on_end = i_load_reflected + i_mag_pp / 2  # simplified (no ramp)
            i_demag_start = i_mag_pp / 2
            i_time = [0.0, 0.0, d * T, d * T, (d + d_demag) * T, (d + d_demag) * T, T]
            i_data = [0.0, i_on_start, i_on_end, i_demag_start, 0.0, 0.0, 0.0]
        else:
            # Secondary voltage: +Vsec during on, 0 during off (with dead time)
            v_on = v_sec
            v_time = [0.0, 0.0, d * T, d * T, T]
            v_data = [0.0, v_on, v_on, 0.0, 0.0]

            # Secondary current: load current during on, 0 during off
            i_peak = i_out + i_out * i_ripple_ratio / 2
            i_valley = i_out - i_out * i_ripple_ratio / 2
            i_time = [0.0, 0.0, d * T, d * T, T]
            i_data = [0.0, i_peak, i_peak, 0.0, 0.0]

        return {
            "name": name,
            "frequency": freq,
            "current": {
                "waveform": {
                    "data": i_data,
                    "time": i_time,
                    "ancillaryLabel": "Custom",
                    "numberPeriods": None,
                },
            },
            "voltage": {
                "waveform": {
                    "data": v_data,
                    "time": v_time,
                    "ancillaryLabel": "Custom",
                    "numberPeriods": None,
                },
            },
        }

    def _create_rectangular_waveform(self, peak_to_peak, frequency, duty_cycle, offset):
        """Create rectangular waveform time/data arrays.

        Normalized time: [0, duty_cycle, duty_cycle, 1.0]
        Data:            [peak, peak, 0, 0]
        Physical time is computed from frequency.
        """
        if frequency <= 0:
            frequency = 200e3
        period = 1.0 / frequency

        # Normalized time points
        t_norm = [0.0, duty_cycle, duty_cycle, 1.0]

        # Voltage data: high during on-time, low during off-time
        data = [
            offset + peak_to_peak / 2,  # high at t=0
            offset + peak_to_peak / 2,  # high at t=D
            offset - peak_to_peak / 2,  # low at t=D+
            offset - peak_to_peak / 2,  # low at t=1
        ]

        # Convert to physical time
        time = [t * period for t in t_norm]

        return {"time": time, "data": data}

    def _create_triangular_waveform(self, peak_to_peak, frequency, duty_cycle, offset):
        """Create triangular waveform time/data arrays (symmetric ramp).

        Normalized time: [0, duty_cycle, 1.0]
        Data:            [min, max, min]
        """
        if frequency <= 0:
            frequency = 200e3
        period = 1.0 / frequency

        # Normalized time points
        t_norm = [0.0, duty_cycle, 1.0]

        # Triangular current: ramps from min to max during on-time, back to min during off-time
        data = [
            offset - peak_to_peak / 2,  # minimum
            offset + peak_to_peak / 2,  # maximum at end of on-time
            offset - peak_to_peak / 2,  # back to minimum at end of cycle
        ]

        # Convert to physical time
        time = [t * period for t in t_norm]

        return {"time": time, "data": data}

    def _create_flyback_primary_waveform(self, peak_to_peak, frequency, duty_cycle, offset):
        """Create flyback primary current waveform: ramps on, jumps down.

        During on-time (0 to D*T): current ramps linearly from low to high
        At turn-off (D*T): current jumps down discontinuously (ZVS transition)
        During off-time (D*T to T): freewheels at low level
        """
        if frequency <= 0:
            frequency = 200e3
        period = 1.0 / frequency

        # Normalized time points: include transition at end of on-time
        t_norm = [0.0, duty_cycle, duty_cycle, 1.0]

        # Current waveform
        data = [
            offset - peak_to_peak / 2,  # start at minimum (t=0)
            offset + peak_to_peak / 2,  # ramp to maximum (t=D)
            offset - peak_to_peak / 2,  # jump down at turn-off (t=D+)
            offset - peak_to_peak / 2,  # stay at minimum during off-time
        ]

        # Convert to physical time
        time = [t * period for t in t_norm]

        return {"time": time, "data": data}

    def _create_custom_waveform(self, time, data):
        """Pass-through for custom waveforms (used for IsolatedBuck secondaries)."""
        return {"time": time, "data": data}

    def build_waveform_preview(self, design_reqs, operating_point, fsw):
        """
        Build waveform preview time/data arrays for visualization.

        Override in subclasses to provide topology-specific waveforms.

        Args:
            design_reqs: dict from compute_design_requirements()
            operating_point: single operating point dict
            fsw: switching frequency in Hz

        Returns:
            list of dicts: [{"winding_name": str, "voltage": {...}, "current": {...}}, ...]
        """
        raise NotImplementedError(f"{self.__class__.__name__}.build_waveform_preview")

    def build_operating_points(self, converter, design_reqs):
        """
        Build MAS operatingPoints[] array from converter specs.

        Args:
            converter: dict with operatingPoints[]
            design_reqs: dict returned from compute_design_requirements()

        Returns:
            list of MAS operatingPoint dicts
        """
        raise NotImplementedError(f"{self.__class__.__name__}.build_operating_points")

    def build_mas_design_requirements(self, converter, design_reqs):
        """
        Build MAS designRequirements dict.

        Returns:
            dict with topology, magnetizingInductance, turnsRatios, etc.
        """
        raise NotImplementedError(f"{self.__class__.__name__}.build_mas_design_requirements")


class TwoSwitchForwardCalc(TopologyCalculator):
    """Two-Switch Forward converter (isolated, 1 primary + N secondaries)."""

    def __init__(self):
        super().__init__()
        self.topology_key = "two_switch_forward"
        self.topology_display = "Two-Switch Forward Converter"
        self.n_windings_min = 2
        self.n_windings_max = 5

    def compute_design_requirements(self, converter, advanced, n_outputs=1):
        """Compute Two-Switch Forward requirements."""
        c = converter
        fsw = as_float(c.get("operatingPoints", [{}])[0].get("switchingFrequency", 200e3))
        eta = as_float(c.get("efficiency", 90)) / 100.0
        vd = as_float(c.get("diodeVoltageDrop", 0.7))

        vin_min = as_float(c.get("inputVoltage", {}).get("minimum", 100))
        vin_max = as_float(c.get("inputVoltage", {}).get("maximum", 190))
        vin_nom = as_float(c.get("inputVoltage", {}).get("nominal"))
        if vin_nom <= 0:
            vin_nom = (vin_min + vin_max) / 2

        # Get output specs (assume all outputs identical for auto mode)
        op = c.get("operatingPoints", [{}])[0]
        vout_list = as_list(op.get("outputVoltages", [5.0]))
        iout_list = as_list(op.get("outputCurrents", [5.0]))

        if not vout_list or not iout_list:
            vout_list = [5.0]
            iout_list = [5.0]

        # For multi-output, use first output for Lm calculation, but create turns ratios for each
        vout = vout_list[0] if vout_list else 5.0
        iout = iout_list[0] if iout_list else 5.0
        total_iout = sum(as_list(iout_list))  # total current for power calc

        # Output power (sum of each output's V*I)
        pout = sum(
            vout_list[i] * iout_list[i]
            for i in range(min(len(vout_list), len(iout_list)))
        )
        pin_nom = pout / max(eta, 0.01)

        # Turns ratio per secondary: Ns_i/Np = (Vout_i + Vd) / (Vin_min * D_target)
        # All outputs share the same duty cycle D (set by main output regulation).
        # Each secondary gets its own turns ratio to deliver its target voltage.
        d_target_max = 0.45
        ns_np_list = []
        np_ns_list = []
        for i in range(n_outputs):
            vout_i = vout_list[i] if i < len(vout_list) else vout_list[0]
            ns_np_i = (vout_i + vd) / (vin_min * d_target_max)
            ns_np_list.append(ns_np_i)
            np_ns_list.append(1.0 / ns_np_i)
        ns_np = ns_np_list[0]  # Main output ratio (for duty cycle calc)
        np_ns = np_ns_list[0]

        # Actual duty cycles (determined by main output)
        d_min_vin = (vout + vd) / (vin_min * ns_np)
        d_max_vin = (vout + vd) / (vin_max * ns_np)
        d_nom = (vout + vd) / (vin_nom * ns_np)

        d_min_vin = clamp(d_min_vin, 0.01, 0.49)
        d_max_vin = clamp(d_max_vin, 0.01, 0.49)
        d_nom = clamp(d_nom, 0.01, 0.49)

        # Output inductor per secondary (on-time equation, worst case at Vin_max)
        # Lout_i = (Vin_max * Ns_i/Np - Vd - Vout_i) * D_at_Vin_max / (ΔI_i * fsw)
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        lout_list = []
        for i in range(n_outputs):
            vout_i = vout_list[i] if i < len(vout_list) else vout_list[0]
            iout_i = iout_list[i] if i < len(iout_list) else iout_list[0]
            delta_i = ripple_frac * iout_i
            v_on = vin_max * ns_np_list[i] - vd - vout_i  # Per-secondary reflected voltage
            if delta_i > 0 and v_on > 0:
                lout_list.append(v_on * d_max_vin / (delta_i * fsw))
            else:
                lout_list.append(100e-6)
        lout = lout_list[0]

        # Magnetizing inductance (sum of all reflected secondary currents)
        # Size at worst case: Vin_min × D_max.  For a regulated forward converter
        # V_in × D = (Vout + Vd) × Np/Ns ≈ constant across the input range,
        # but use the worst-case expression for correct design practice.
        i_load_reflected = sum(
            iout_list[i] * ns_np_list[i] if i < len(iout_list) else 0
            for i in range(n_outputs)
        )
        i_mag_ripple_target = 0.10 * i_load_reflected
        if i_mag_ripple_target > 0:
            lm = vin_min * d_min_vin / (i_mag_ripple_target * fsw)
        else:
            lm = 500e-6

        # RMS currents — worst case at Vin_min (maximum duty cycle)
        i_pri_rms = i_load_reflected * math.sqrt(d_min_vin)
        i_sec_rms = [io * math.sqrt(d_min_vin) for io in as_list(iout_list)]

        # Peak magnetizing current — worst case at Vin_min × D_max
        i_mag_pp = vin_min * d_min_vin / (lm * fsw)
        i_mag_peak = i_mag_pp / 2

        # Per-secondary turns ratios (Np/Ns for each output)
        turns_ratios = np_ns_list

        return {
            "Lm_uH": lm * 1e6,
            "Lout_uH": lout * 1e6,
            "Lout_list_uH": [l * 1e6 for l in lout_list],
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
            "ns_np_list": ns_np_list,
            "np_ns": np_ns,
            "n_windings": 1 + n_outputs,
            "duty_nom": d_nom,
            "duty_min_vin": d_min_vin,
            "duty_max_vin": d_max_vin,
            "i_pri_rms": i_pri_rms,
            "i_sec_rms": i_sec_rms,
            "i_mag_peak": i_mag_peak,
            "i_mag_pp": i_mag_pp,
            "pin_nom": pin_nom,
            "pout_nom": pout,
            "vin_nom": vin_nom,
            "vin_min": vin_min,
            "vin_max": vin_max,
            "fsw_hz": fsw,
            "vout_list": vout_list,
            "iout_list": iout_list,
        }

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[] with volt-second-balanced waveforms.
        Two-switch forward primary: 3-phase (on / demagnetize / dead time).
        Secondary: 2-phase (on / off).
        demag_ratio = 1.0 for two-switch forward (V_demag = Vin).
        """
        op_list = []
        d = design_reqs.get("duty_nom", 0.45)
        i_mag_pp = design_reqs.get("i_mag_pp", 0.1)
        vin = design_reqs.get("vin_nom", 100.0)
        vout_list = design_reqs.get("vout_list", [5.0])
        iout_list = design_reqs.get("iout_list", [1.0])
        ns_np = design_reqs.get("ns_np", 0.05)

        # Per-secondary Ns/Np ratios for reflected current calculation
        ns_np_list = design_reqs.get("ns_np_list", [ns_np])
        if not isinstance(ns_np_list, list):
            ns_np_list = [ns_np]

        for op in converter.get("operatingPoints", []):
            freq = as_float(op.get("switchingFrequency", 200e3))

            # Total reflected load current on primary
            i_load_reflected = sum(
                iout_list[i] * ns_np_list[i] if i < len(ns_np_list) else iout_list[i] * ns_np
                for i in range(len(iout_list))
            )

            # Primary: volt-second-balanced 3-phase waveform
            exc = [self._make_forward_excitation(
                "Primary", freq, d, vin,
                i_load_reflected=i_load_reflected,
                i_mag_pp=i_mag_pp,
                demag_ratio=1.0)]  # two-switch: V_demag = Vin

            # Secondaries: 2-phase waveform (on / off)
            for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
                name = "Secondary" if j == 0 else f"Secondary {j + 1}"
                exc.append(self._make_forward_excitation(
                    name, freq, d, vin,
                    i_load_reflected=0,  # not used for secondary
                    i_mag_pp=0,          # not used for secondary
                    v_sec=vout_j,
                    i_out=iout_j,
                    i_ripple_ratio=0.3))

            op_list.append({
                "name": op.get("name", f"Operating Point {len(op_list)+1}"),
                "conditions": {"ambientTemperature": as_float(op.get("ambientTemperature", 25.0))},
                "excitationsPerWinding": exc,
            })

        return op_list

    def build_waveform_preview(self, design_reqs, operating_point, fsw):
        """Build waveform previews for two-switch forward.

        Primary: rectangular voltage and current with magnetizing ripple
        Secondaries: rectangular voltage and current during on-time only
        """
        windings = []
        d = design_reqs.get("duty_nom", 0.45)
        i_mag_pp = design_reqs.get("i_mag_pp", 0.1)
        iout_list = design_reqs.get("iout_list", [1.0])
        vout_list = design_reqs.get("vout_list", [5.0])
        vin = design_reqs.get("vin_nom", 100.0)
        ns_np = design_reqs.get("ns_np", 0.05)

        # Primary winding
        ns_np_list = design_reqs.get("ns_np_list", [ns_np])
        i_load_reflected = sum(
            iout_list[j] * (ns_np_list[j] if j < len(ns_np_list) else ns_np)
            for j in range(len(iout_list))
        )
        i_pri_pp = i_mag_pp + i_load_reflected
        i_pri_offset = i_pri_pp / 2
        v_pri_pp = vin
        v_pri_offset = vin * d / 2

        windings.append({
            "winding_name": "Primary",
            "voltage": {**self._create_rectangular_waveform(v_pri_pp, fsw, d, v_pri_offset), "label": "RECTANGULAR", "unit": "V"},
            "current": {**self._create_rectangular_waveform(i_pri_pp, fsw, d, i_pri_offset), "label": "RECTANGULAR", "unit": "A"},
        })

        # Secondary windings
        for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
            i_sec_pp = iout_j * 0.3
            i_sec_offset = iout_j
            v_sec_pp = vout_j
            v_sec_offset = vout_j * d / 2

            windings.append({
                "winding_name": "Secondary" if j == 0 else f"Secondary {j + 1}",
                "voltage": {**self._create_rectangular_waveform(v_sec_pp, fsw, d, v_sec_offset), "label": "SECONDARY_RECTANGULAR", "unit": "V"},
                "current": {**self._create_rectangular_waveform(i_sec_pp, fsw, d, i_sec_offset), "label": "RECTANGULAR", "unit": "A"},
            })

        return windings

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "Two Switch Forward Converter",
            "magnetizingInductance": {
                "nominal": design_reqs["Lm_uH"] * 1e-6
            },
            "turnsRatios": [{"nominal": tr} for tr in design_reqs["turns_ratios"]],
        }


class SingleSwitchForwardCalc(TopologyCalculator):
    """Single-Switch Forward converter (3 windings: primary + demagnetization + secondary)."""

    def __init__(self):
        super().__init__()
        self.topology_key = "single_switch_forward"
        self.topology_display = "Single-Switch Forward Converter"
        self.n_windings_min = 3
        self.n_windings_max = 6

    def compute_design_requirements(self, converter, advanced, n_outputs=1):
        """Compute Single-Switch Forward requirements."""
        # Similar to Two-Switch Forward but with demagnetization winding
        c = converter
        fsw = as_float(c.get("operatingPoints", [{}])[0].get("switchingFrequency", 200e3))
        eta = as_float(c.get("efficiency", 90)) / 100.0
        vd = as_float(c.get("diodeVoltageDrop", 0.7))

        vin_min = as_float(c.get("inputVoltage", {}).get("minimum", 100))
        vin_max = as_float(c.get("inputVoltage", {}).get("maximum", 190))
        vin_nom = as_float(c.get("inputVoltage", {}).get("nominal"))
        if vin_nom <= 0:
            vin_nom = (vin_min + vin_max) / 2

        op = c.get("operatingPoints", [{}])[0]
        vout_list = as_list(op.get("outputVoltages", [5.0]))
        iout_list = as_list(op.get("outputCurrents", [5.0]))

        vout = vout_list[0] if vout_list else 5.0
        total_iout = sum(as_list(iout_list))

        # Output power (sum of each output's V*I)
        pout = sum(
            vout_list[i] * iout_list[i]
            for i in range(min(len(vout_list), len(iout_list)))
        )
        pin_nom = pout / max(eta, 0.01)

        # Single-switch forward duty is typically 0.5, demagnetization winding carries reset
        # Per-secondary turns ratios: Ns_i/Np = (Vout_i + Vd) / (Vin_min * D_target)
        d_target_max = 0.5  # Single switch can reach 50%
        ns_np_list = []
        np_ns_list = []
        for i in range(n_outputs):
            vout_i = vout_list[i] if i < len(vout_list) else vout_list[0]
            ns_np_i = (vout_i + vd) / (vin_min * d_target_max)
            ns_np_list.append(ns_np_i)
            np_ns_list.append(1.0 / ns_np_i)
        ns_np = ns_np_list[0]
        np_ns = np_ns_list[0]

        # Actual duty cycles (determined by main output)
        d_min_vin = (vout + vd) / (vin_min * ns_np)
        d_max_vin = (vout + vd) / (vin_max * ns_np)
        d_nom = (vout + vd) / (vin_nom * ns_np)

        d_min_vin = clamp(d_min_vin, 0.01, 0.50)
        d_max_vin = clamp(d_max_vin, 0.01, 0.50)
        d_nom = clamp(d_nom, 0.01, 0.50)

        # Demagnetization winding turns ratio (typically equal to primary for simplicity)
        nd_np = 1.0

        # Output inductor per secondary (on-time equation, worst case at Vin_max)
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        lout_list = []
        for i in range(n_outputs):
            vout_i = vout_list[i] if i < len(vout_list) else vout_list[0]
            iout_i = iout_list[i] if i < len(iout_list) else iout_list[0]
            delta_i = ripple_frac * iout_i
            v_on = vin_max * ns_np_list[i] - vd - vout_i
            if delta_i > 0 and v_on > 0:
                lout_list.append(v_on * d_max_vin / (delta_i * fsw))
            else:
                lout_list.append(100e-6)
        lout = lout_list[0]

        # Magnetizing inductance — size at worst case (Vin_min × D_max)
        i_load_reflected = sum(
            iout_list[i] * ns_np_list[i] if i < len(iout_list) else 0
            for i in range(n_outputs)
        )
        i_mag_ripple_target = 0.10 * i_load_reflected
        if i_mag_ripple_target > 0:
            lm = vin_min * d_min_vin / (i_mag_ripple_target * fsw)
        else:
            lm = 500e-6

        # RMS currents — worst case at Vin_min (maximum duty cycle)
        i_pri_rms = i_load_reflected * math.sqrt(d_min_vin)
        i_demag_rms = i_load_reflected * nd_np * math.sqrt(d_min_vin)
        i_sec_rms = [io * math.sqrt(d_min_vin) for io in as_list(iout_list)]

        # Peak magnetizing current — worst case at Vin_min × D_max
        i_mag_pp = vin_min * d_min_vin / (lm * fsw)
        i_mag_peak = i_mag_pp / 2

        # Build turns ratios [per-secondary Np/Ns, then demagnetization]
        turns_ratios = np_ns_list + [nd_np]

        return {
            "Lm_uH": lm * 1e6,
            "Lout_uH": lout * 1e6,
            "Lout_list_uH": [l * 1e6 for l in lout_list],
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
            "ns_np_list": ns_np_list,
            "np_ns": np_ns,
            "nd_np": nd_np,
            "n_windings": 2 + n_outputs,  # primary + demagnetization + N secondaries
            "duty_nom": d_nom,
            "duty_min_vin": d_min_vin,
            "duty_max_vin": d_max_vin,
            "i_pri_rms": i_pri_rms,
            "i_demag_rms": i_demag_rms,
            "i_sec_rms": i_sec_rms,
            "i_mag_peak": i_mag_peak,
            "i_mag_pp": i_mag_pp,
            "pin_nom": pin_nom,
            "pout_nom": pout,
            "vin_nom": vin_nom,
            "vin_min": vin_min,
            "vin_max": vin_max,
            "fsw_hz": fsw,
            "vout_list": vout_list,
            "iout_list": iout_list,
        }

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[] with waveforms for single-switch forward.
        Same as two-switch forward but adds demagnetization winding.
        Demagnetization winding resets core during off-time; carries magnetizing current.
        """
        op_list = []
        d = design_reqs.get("duty_nom", 0.45)
        i_mag_pp = design_reqs.get("i_mag_pp", 0.1)
        ns_np = design_reqs.get("ns_np", 0.05)
        vin = design_reqs.get("vin_nom", 100.0)
        vout_list = design_reqs.get("vout_list", [5.0])
        iout_list = design_reqs.get("iout_list", [1.0])

        for op in converter.get("operatingPoints", []):
            freq = as_float(op.get("switchingFrequency", 200e3))

            # Primary
            ns_np_list = design_reqs.get("ns_np_list", [ns_np])
            i_load_reflected = sum(
                iout_list[j] * (ns_np_list[j] if j < len(ns_np_list) else ns_np)
                for j in range(len(iout_list))
            )
            i_pri_pp = i_mag_pp + i_load_reflected
            exc = [self._make_rectangular_excitation(
                "Primary", freq, i_pri_pp, i_pri_pp / 2, vin, vin * d / 2, d)]

            # Secondaries
            for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
                name = "Secondary" if j == 0 else f"Secondary {j + 1}"
                exc.append(self._make_rectangular_excitation(
                    name, freq, iout_j * 0.3, iout_j, vout_j, vout_j * d / 2, d))

            # Demagnetization winding: rectangular, conducts during off-time carrying reset current
            # Current = i_mag_pp reflected by turns ratio (nd_np = 1.0 typically)
            exc.append(self._make_rectangular_excitation(
                "Demagnetization", freq, i_mag_pp, i_mag_pp / 2, vin, vin * (1 - d) / 2, 1 - d))

            op_list.append({
                "name": op.get("name", f"Operating Point {len(op_list)+1}"),
                "conditions": {"ambientTemperature": as_float(op.get("ambientTemperature", 25.0))},
                "excitationsPerWinding": exc,
            })

        return op_list

    def build_waveform_preview(self, design_reqs, operating_point, fsw):
        """Build waveform previews for single-switch forward.

        Primary: rectangular voltage and current during on-time
        Secondaries: rectangular voltage and current during on-time
        Demagnetization: rectangular during off-time (reset current)
        """
        windings = []
        d = design_reqs.get("duty_nom", 0.45)
        i_mag_pp = design_reqs.get("i_mag_pp", 0.1)
        iout_list = design_reqs.get("iout_list", [1.0])
        vout_list = design_reqs.get("vout_list", [5.0])
        vin = design_reqs.get("vin_nom", 100.0)
        ns_np = design_reqs.get("ns_np", 0.05)

        # Primary winding
        ns_np_list = design_reqs.get("ns_np_list", [ns_np])
        i_load_reflected = sum(
            iout_list[j] * (ns_np_list[j] if j < len(ns_np_list) else ns_np)
            for j in range(len(iout_list))
        )
        i_pri_pp = i_mag_pp + i_load_reflected
        i_pri_offset = i_pri_pp / 2
        v_pri_pp = vin
        v_pri_offset = vin * d / 2

        windings.append({
            "winding_name": "Primary",
            "voltage": {**self._create_rectangular_waveform(v_pri_pp, fsw, d, v_pri_offset), "label": "RECTANGULAR", "unit": "V"},
            "current": {**self._create_rectangular_waveform(i_pri_pp, fsw, d, i_pri_offset), "label": "RECTANGULAR", "unit": "A"},
        })

        # Secondary windings
        for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
            i_sec_pp = iout_j * 0.3
            i_sec_offset = iout_j
            v_sec_pp = vout_j
            v_sec_offset = vout_j * d / 2

            windings.append({
                "winding_name": "Secondary" if j == 0 else f"Secondary {j + 1}",
                "voltage": {**self._create_rectangular_waveform(v_sec_pp, fsw, d, v_sec_offset), "label": "SECONDARY_RECTANGULAR", "unit": "V"},
                "current": {**self._create_rectangular_waveform(i_sec_pp, fsw, d, i_sec_offset), "label": "RECTANGULAR", "unit": "A"},
            })

        # Demagnetization winding (conducts during off-time)
        windings.append({
            "winding_name": "Demagnetization",
            "voltage": {**self._create_rectangular_waveform(vin, fsw, 1 - d, vin * (1 - d) / 2), "label": "RECTANGULAR", "unit": "V"},
            "current": {**self._create_rectangular_waveform(i_mag_pp, fsw, 1 - d, i_mag_pp / 2), "label": "RECTANGULAR", "unit": "A"},
        })

        return windings

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "Single Switch Forward Converter",
            "magnetizingInductance": {
                "nominal": design_reqs["Lm_uH"] * 1e-6
            },
            "turnsRatios": [{"nominal": tr} for tr in design_reqs["turns_ratios"]],
        }


class ActiveClampForwardCalc(TopologyCalculator):
    """Active Clamp Forward converter (2-4 windings)."""

    def __init__(self):
        super().__init__()
        self.topology_key = "active_clamp_forward"
        self.topology_display = "Active Clamp Forward Converter"
        self.n_windings_min = 2
        self.n_windings_max = 5

    def compute_design_requirements(self, converter, advanced, n_outputs=1):
        """Compute Active Clamp Forward requirements."""
        # Very similar to Two-Switch Forward, but with clamp diode instead of second switch
        c = converter
        fsw = as_float(c.get("operatingPoints", [{}])[0].get("switchingFrequency", 200e3))
        eta = as_float(c.get("efficiency", 90)) / 100.0
        vd = as_float(c.get("diodeVoltageDrop", 0.7))

        vin_min = as_float(c.get("inputVoltage", {}).get("minimum", 100))
        vin_max = as_float(c.get("inputVoltage", {}).get("maximum", 190))
        vin_nom = as_float(c.get("inputVoltage", {}).get("nominal"))
        if vin_nom <= 0:
            vin_nom = (vin_min + vin_max) / 2

        op = c.get("operatingPoints", [{}])[0]
        vout_list = as_list(op.get("outputVoltages", [5.0]))
        iout_list = as_list(op.get("outputCurrents", [5.0]))

        vout = vout_list[0] if vout_list else 5.0
        total_iout = sum(as_list(iout_list))

        # Output power (sum of each output's V*I)
        pout = sum(
            vout_list[i] * iout_list[i]
            for i in range(min(len(vout_list), len(iout_list)))
        )
        pin_nom = pout / max(eta, 0.01)

        # Per-secondary turns ratios
        d_target_max = 0.45
        ns_np_list = []
        np_ns_list = []
        for i in range(n_outputs):
            vout_i = vout_list[i] if i < len(vout_list) else vout_list[0]
            ns_np_i = (vout_i + vd) / (vin_min * d_target_max)
            ns_np_list.append(ns_np_i)
            np_ns_list.append(1.0 / ns_np_i)
        ns_np = ns_np_list[0]
        np_ns = np_ns_list[0]

        # Actual duty cycles (determined by main output)
        d_min_vin = (vout + vd) / (vin_min * ns_np)
        d_max_vin = (vout + vd) / (vin_max * ns_np)
        d_nom = (vout + vd) / (vin_nom * ns_np)

        d_min_vin = clamp(d_min_vin, 0.01, 0.49)
        d_max_vin = clamp(d_max_vin, 0.01, 0.49)
        d_nom = clamp(d_nom, 0.01, 0.49)

        # Output inductor per secondary (on-time equation, worst case at Vin_max)
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        lout_list = []
        for i in range(n_outputs):
            vout_i = vout_list[i] if i < len(vout_list) else vout_list[0]
            iout_i = iout_list[i] if i < len(iout_list) else iout_list[0]
            delta_i = ripple_frac * iout_i
            v_on = vin_max * ns_np_list[i] - vd - vout_i
            if delta_i > 0 and v_on > 0:
                lout_list.append(v_on * d_max_vin / (delta_i * fsw))
            else:
                lout_list.append(100e-6)
        lout = lout_list[0]

        # Magnetizing inductance — size at worst case (Vin_min × D_max)
        i_load_reflected = sum(
            iout_list[i] * ns_np_list[i] if i < len(iout_list) else 0
            for i in range(n_outputs)
        )
        i_mag_ripple_target = 0.10 * i_load_reflected
        if i_mag_ripple_target > 0:
            lm = vin_min * d_min_vin / (i_mag_ripple_target * fsw)
        else:
            lm = 500e-6

        # RMS currents — worst case at Vin_min (maximum duty cycle)
        i_pri_rms = i_load_reflected * math.sqrt(d_min_vin)
        i_sec_rms = [io * math.sqrt(d_min_vin) for io in as_list(iout_list)]

        # Peak magnetizing current — worst case at Vin_min × D_max
        i_mag_pp = vin_min * d_min_vin / (lm * fsw)
        i_mag_peak = i_mag_pp / 2

        turns_ratios = np_ns_list

        return {
            "Lm_uH": lm * 1e6,
            "Lout_uH": lout * 1e6,
            "Lout_list_uH": [l * 1e6 for l in lout_list],
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
            "ns_np_list": ns_np_list,
            "np_ns": np_ns,
            "n_windings": 1 + n_outputs,
            "duty_nom": d_nom,
            "duty_min_vin": d_min_vin,
            "duty_max_vin": d_max_vin,
            "i_pri_rms": i_pri_rms,
            "i_sec_rms": i_sec_rms,
            "i_mag_peak": i_mag_peak,
            "i_mag_pp": i_mag_pp,
            "pin_nom": pin_nom,
            "pout_nom": pout,
            "vin_nom": vin_nom,
            "vin_min": vin_min,
            "vin_max": vin_max,
            "fsw_hz": fsw,
            "vout_list": vout_list,
            "iout_list": iout_list,
        }

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[] for active clamp forward.
        Same waveform structure as two-switch forward. The active clamp circuit reduces
        secondary voltage stress but doesn't change the fundamental waveform shapes.
        """
        op_list = []
        d = design_reqs.get("duty_nom", 0.45)
        i_mag_pp = design_reqs.get("i_mag_pp", 0.1)
        ns_np = design_reqs.get("ns_np", 0.05)
        vin = design_reqs.get("vin_nom", 100.0)
        vout_list = design_reqs.get("vout_list", [5.0])
        iout_list = design_reqs.get("iout_list", [1.0])

        for op in converter.get("operatingPoints", []):
            freq = as_float(op.get("switchingFrequency", 200e3))
            ns_np_list = design_reqs.get("ns_np_list", [ns_np])
            i_load_reflected = sum(
                iout_list[j] * (ns_np_list[j] if j < len(ns_np_list) else ns_np)
                for j in range(len(iout_list))
            )
            i_pri_pp = i_mag_pp + i_load_reflected
            exc = [self._make_rectangular_excitation(
                "Primary", freq, i_pri_pp, i_pri_pp / 2, vin, vin * d / 2, d)]
            for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
                name = "Secondary" if j == 0 else f"Secondary {j + 1}"
                exc.append(self._make_rectangular_excitation(
                    name, freq, iout_j * 0.3, iout_j, vout_j, vout_j * d / 2, d))
            op_list.append({
                "name": op.get("name", f"Operating Point {len(op_list)+1}"),
                "conditions": {"ambientTemperature": as_float(op.get("ambientTemperature", 25.0))},
                "excitationsPerWinding": exc,
            })
        return op_list

    def build_waveform_preview(self, design_reqs, operating_point, fsw):
        """Build waveform previews for active clamp forward.

        Same structure as two-switch forward: rectangular primary and secondaries.
        """
        windings = []
        d = design_reqs.get("duty_nom", 0.45)
        i_mag_pp = design_reqs.get("i_mag_pp", 0.1)
        iout_list = design_reqs.get("iout_list", [1.0])
        vout_list = design_reqs.get("vout_list", [5.0])
        vin = design_reqs.get("vin_nom", 100.0)
        ns_np = design_reqs.get("ns_np", 0.05)

        # Primary winding
        ns_np_list = design_reqs.get("ns_np_list", [ns_np])
        i_load_reflected = sum(
            iout_list[j] * (ns_np_list[j] if j < len(ns_np_list) else ns_np)
            for j in range(len(iout_list))
        )
        i_pri_pp = i_mag_pp + i_load_reflected
        i_pri_offset = i_pri_pp / 2
        v_pri_pp = vin
        v_pri_offset = vin * d / 2

        windings.append({
            "winding_name": "Primary",
            "voltage": {**self._create_rectangular_waveform(v_pri_pp, fsw, d, v_pri_offset), "label": "RECTANGULAR", "unit": "V"},
            "current": {**self._create_rectangular_waveform(i_pri_pp, fsw, d, i_pri_offset), "label": "RECTANGULAR", "unit": "A"},
        })

        # Secondary windings
        for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
            i_sec_pp = iout_j * 0.3
            i_sec_offset = iout_j
            v_sec_pp = vout_j
            v_sec_offset = vout_j * d / 2

            windings.append({
                "winding_name": "Secondary" if j == 0 else f"Secondary {j + 1}",
                "voltage": {**self._create_rectangular_waveform(v_sec_pp, fsw, d, v_sec_offset), "label": "SECONDARY_RECTANGULAR", "unit": "V"},
                "current": {**self._create_rectangular_waveform(i_sec_pp, fsw, d, i_sec_offset), "label": "RECTANGULAR", "unit": "A"},
            })

        return windings

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "Active Clamp Forward Converter",
            "magnetizingInductance": {"nominal": design_reqs["Lm_uH"] * 1e-6},
            "turnsRatios": [{"nominal": tr} for tr in design_reqs["turns_ratios"]],
        }


class FlybackCalc(TopologyCalculator):
    """Flyback converter (isolated, primary + N secondaries, Lm stores energy)."""

    def __init__(self):
        super().__init__()
        self.topology_key = "flyback"
        self.topology_display = "Flyback Converter"
        self.n_windings_min = 2
        self.n_windings_max = 5

    def compute_design_requirements(self, converter, advanced, n_outputs=1):
        """Compute Flyback requirements."""
        c = converter
        fsw = as_float(c.get("operatingPoints", [{}])[0].get("switchingFrequency", 200e3))
        eta = as_float(c.get("efficiency", 90)) / 100.0
        vd = as_float(c.get("diodeVoltageDrop", 0.7))

        vin_min = as_float(c.get("inputVoltage", {}).get("minimum", 100))
        vin_max = as_float(c.get("inputVoltage", {}).get("maximum", 190))
        vin_nom = as_float(c.get("inputVoltage", {}).get("nominal"))
        if vin_nom <= 0:
            vin_nom = (vin_min + vin_max) / 2

        op = c.get("operatingPoints", [{}])[0]
        vout_list = as_list(op.get("outputVoltages", [5.0]))
        iout_list = as_list(op.get("outputCurrents", [5.0]))

        vout = vout_list[0] if vout_list else 5.0
        total_iout = sum(as_list(iout_list))

        # Output power (sum of each output's V*I)
        pout = sum(
            vout_list[i] * iout_list[i]
            for i in range(min(len(vout_list), len(iout_list)))
        )
        pin_nom = pout / max(eta, 0.01)

        # Flyback: D = N*(Vout+Vd) / (Vin + N*(Vout+Vd)), where N = Ns/Np
        # Lm stores energy during on-time, transfers during off-time
        # Choose Ns/Np so that D = 0.5 at Vin_min:
        #   0.5 = N*(Vout+Vd) / (Vin_min + N*(Vout+Vd)) => Vin_min = N*(Vout+Vd)
        ns_np = vin_min / (vout + vd)
        np_ns = 1.0 / ns_np

        d_min_vin = (ns_np * (vout + vd)) / (vin_min + ns_np * (vout + vd))
        d_max_vin = (ns_np * (vout + vd)) / (vin_max + ns_np * (vout + vd))
        d_nom = (ns_np * (vout + vd)) / (vin_nom + ns_np * (vout + vd))

        d_min_vin = clamp(d_min_vin, 0.01, 0.50)
        d_max_vin = clamp(d_max_vin, 0.01, 0.50)
        d_nom = clamp(d_nom, 0.01, 0.50)

        # For flyback, Lm stores all output energy
        # Lm = Vin^2 * D^2 / (2 * Pout * fsw * (1 + ripple))
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        if pout > 0:
            lm = (vin_nom**2 * d_nom**2) / (2 * pout * fsw * (1 + ripple_frac))
        else:
            lm = 500e-6

        # RMS currents: flyback primary is triangular, I_pk = Vin*D/(Lm*fsw)
        i_pk = vin_nom * d_nom / (lm * fsw) if lm > 0 and fsw > 0 else pout / vin_nom
        i_pri_rms = i_pk * math.sqrt(d_nom / 3)
        i_sec_rms = [io * math.sqrt(1 - d_nom) for io in as_list(iout_list)]  # conducts during off-time

        i_mag_peak = vin_nom * d_nom / (lm * fsw)
        i_mag_pp = vin_nom * d_nom / (lm * fsw)

        turns_ratios = [np_ns] * n_outputs
        ns_np_list = [ns_np] * n_outputs

        return {
            "Lm_uH": lm * 1e6,
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
            "ns_np_list": ns_np_list,
            "np_ns": np_ns,
            "n_windings": 1 + n_outputs,
            "duty_nom": d_nom,
            "duty_min_vin": d_min_vin,
            "duty_max_vin": d_max_vin,
            "i_pri_rms": i_pri_rms,
            "i_sec_rms": i_sec_rms,
            "i_mag_peak": i_mag_peak,
            "i_mag_pp": i_mag_pp,
            "pin_nom": pin_nom,
            "pout_nom": pout,
            "vin_nom": vin_nom,
            "fsw_hz": fsw,
            "vout_list": vout_list,
            "iout_list": iout_list,
        }

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[]."""
        op_list = []
        for i, op in enumerate(converter.get("operatingPoints", [])):
            exc_per_winding = []
            exc_per_winding.append({"name": "Primary", "frequency": as_float(op.get("switchingFrequency", 200e3))})
            for j in range(len(design_reqs.get("iout_list", []))):
                exc_per_winding.append({
                    "name": f"Secondary {j + 1}" if j > 0 else "Secondary",
                    "frequency": as_float(op.get("switchingFrequency", 200e3))
                })
            op_list.append({
                "name": op.get("name", f"Operating Point {len(op_list)+1}"),
                "conditions": {"ambientTemperature": as_float(op.get("ambientTemperature", 25.0))},
                "excitationsPerWinding": exc_per_winding,
            })
        return op_list

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[] with flyback-specific triangular waveforms.
        Flyback primary: triangular rising current during on-time (energy stored in Lm).
        Flyback secondary: triangular falling current during off-time (energy transferred).
        """
        op_list = []
        d = design_reqs.get("duty_nom", 0.45)
        i_mag_pp = design_reqs.get("i_mag_pp", 1.0)
        i_mag_peak = design_reqs.get("i_mag_peak", i_mag_pp)
        ns_np = design_reqs.get("ns_np", 0.05)
        vin = design_reqs.get("vin_nom", 100.0)
        vout_list = design_reqs.get("vout_list", [5.0])
        iout_list = design_reqs.get("iout_list", [1.0])

        for op in converter.get("operatingPoints", []):
            freq = as_float(op.get("switchingFrequency", 200e3))

            # Primary: triangular during on-time (energy storage), starts near zero
            # The magnetizing current ramps from I_pk - Ipp/2 to I_pk + Ipp/2
            i_pri_offset = i_mag_peak - i_mag_pp / 2  # lower peak value as DC offset
            v_pri_pp = vin
            v_pri_offset = vin * d / 2

            exc = [self._make_triangular_excitation(
                "Primary", freq, i_mag_pp, i_pri_offset, v_pri_pp, v_pri_offset, d)]

            # Secondaries: triangular during off-time (energy transfer)
            # Secondary current = primary current * Np/Ns (reflected)
            for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
                name = "Secondary" if j == 0 else f"Secondary {j + 1}"
                i_sec_pp = i_mag_pp / ns_np  # reflected magnetizing current
                i_sec_offset = iout_j  # average at DC load level
                v_sec_pp = vout_j
                v_sec_offset = vout_j * (1 - d) / 2
                # Secondary conducts during (1-D), so invert duty for secondary
                exc.append(self._make_triangular_excitation(
                    name, freq, i_sec_pp, i_sec_offset, v_sec_pp, v_sec_offset, 1 - d))

            op_list.append({
                "name": op.get("name", f"Operating Point {len(op_list)+1}"),
                "conditions": {"ambientTemperature": as_float(op.get("ambientTemperature", 25.0))},
                "excitationsPerWinding": exc,
            })

        return op_list

    def build_waveform_preview(self, design_reqs, operating_point, fsw):
        """Build waveform previews for flyback.

        Primary: rectangular voltage, triangular rising current during on-time
        Secondaries: rectangular voltage, triangular falling current during off-time
        """
        windings = []
        d = design_reqs.get("duty_nom", 0.45)
        i_mag_pp = design_reqs.get("i_mag_pp", 1.0)
        i_mag_peak = design_reqs.get("i_mag_peak", i_mag_pp)
        iout_list = design_reqs.get("iout_list", [1.0])
        vout_list = design_reqs.get("vout_list", [5.0])
        vin = design_reqs.get("vin_nom", 100.0)
        ns_np = design_reqs.get("ns_np", 0.05)

        # Primary winding: triangular rising current during on-time
        i_pri_offset = i_mag_peak - i_mag_pp / 2
        v_pri_pp = vin
        v_pri_offset = vin * d / 2

        windings.append({
            "winding_name": "Primary",
            "voltage": {**self._create_rectangular_waveform(v_pri_pp, fsw, d, v_pri_offset), "label": "RECTANGULAR", "unit": "V"},
            "current": {**self._create_triangular_waveform(i_mag_pp, fsw, d, i_pri_offset), "label": "FLYBACK_PRIMARY", "unit": "A"},
        })

        # Secondary windings: triangular falling current during off-time
        for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
            i_sec_pp = i_mag_pp / ns_np
            i_sec_offset = iout_j
            v_sec_pp = vout_j
            v_sec_offset = vout_j * (1 - d) / 2

            windings.append({
                "winding_name": "Secondary" if j == 0 else f"Secondary {j + 1}",
                "voltage": {**self._create_rectangular_waveform(v_sec_pp, fsw, 1 - d, v_sec_offset), "label": "SECONDARY_RECTANGULAR", "unit": "V"},
                "current": {**self._create_triangular_waveform(i_sec_pp, fsw, 1 - d, i_sec_offset), "label": "FLYBACK_SECONDARY", "unit": "A"},
            })

        return windings

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "Flyback Converter",
            "magnetizingInductance": {"nominal": design_reqs["Lm_uH"] * 1e-6},
            "turnsRatios": [{"nominal": tr} for tr in design_reqs["turns_ratios"]],
        }


class PushPullCalc(TopologyCalculator):
    """Push-Pull converter (isolated, primary + N secondaries, balanced drive)."""

    def __init__(self):
        super().__init__()
        self.topology_key = "push_pull"
        self.topology_display = "Push-Pull Converter"
        self.n_windings_min = 2
        self.n_windings_max = 5

    def compute_design_requirements(self, converter, advanced, n_outputs=1):
        """Compute Push-Pull requirements."""
        c = converter
        fsw = as_float(c.get("operatingPoints", [{}])[0].get("switchingFrequency", 200e3))
        eta = as_float(c.get("efficiency", 90)) / 100.0
        vd = as_float(c.get("diodeVoltageDrop", 0.7))

        vin_min = as_float(c.get("inputVoltage", {}).get("minimum", 100))
        vin_max = as_float(c.get("inputVoltage", {}).get("maximum", 190))
        vin_nom = as_float(c.get("inputVoltage", {}).get("nominal"))
        if vin_nom <= 0:
            vin_nom = (vin_min + vin_max) / 2

        op = c.get("operatingPoints", [{}])[0]
        vout_list = as_list(op.get("outputVoltages", [5.0]))
        iout_list = as_list(op.get("outputCurrents", [5.0]))

        vout = vout_list[0] if vout_list else 5.0
        total_iout = sum(as_list(iout_list))

        # Output power (sum of each output's V*I)
        pout = sum(
            vout_list[i] * iout_list[i]
            for i in range(min(len(vout_list), len(iout_list)))
        )
        pin_nom = pout / max(eta, 0.01)

        # Push-Pull: center-tapped primary, duty ~0.5 per switch
        # Voltage on secondary is 2 * Vin at full duty
        # Per-secondary turns ratios
        d_target_max = 0.45
        ns_np_list = []
        np_ns_list = []
        for i in range(n_outputs):
            vout_i = vout_list[i] if i < len(vout_list) else vout_list[0]
            ns_np_i = (vout_i + vd) / (2 * vin_min * d_target_max)  # 2x multiplier
            ns_np_list.append(ns_np_i)
            np_ns_list.append(1.0 / ns_np_i)
        ns_np = ns_np_list[0]
        np_ns = np_ns_list[0]

        # Actual duty cycles (determined by main output)
        d_min_vin = (vout + vd) / (2 * vin_min * ns_np)
        d_max_vin = (vout + vd) / (2 * vin_max * ns_np)
        d_nom = (vout + vd) / (2 * vin_nom * ns_np)

        d_min_vin = clamp(d_min_vin, 0.01, 0.49)
        d_max_vin = clamp(d_max_vin, 0.01, 0.49)
        d_nom = clamp(d_nom, 0.01, 0.49)

        # Output inductor per secondary (on-time equation, worst case at Vin_max)
        # Push-pull has 2× Vin reflected to secondary
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        lout_list = []
        for i in range(n_outputs):
            vout_i = vout_list[i] if i < len(vout_list) else vout_list[0]
            iout_i = iout_list[i] if i < len(iout_list) else iout_list[0]
            delta_i = ripple_frac * iout_i
            v_on = 2 * vin_max * ns_np_list[i] - vd - vout_i  # 2× for center-tapped primary
            if delta_i > 0 and v_on > 0:
                lout_list.append(v_on * d_max_vin / (delta_i * fsw))
            else:
                lout_list.append(100e-6)
        lout = lout_list[0]

        # Magnetizing inductance — size at worst case (2 × Vin_min × D_max)
        i_load_reflected = sum(
            iout_list[i] * ns_np_list[i] if i < len(iout_list) else 0
            for i in range(n_outputs)
        )
        i_mag_ripple_target = 0.10 * i_load_reflected
        if i_mag_ripple_target > 0:
            lm = (2 * vin_min) * d_min_vin / (i_mag_ripple_target * fsw)  # 2x for center tap
        else:
            lm = 500e-6

        # RMS currents — worst case at Vin_min (maximum duty cycle)
        i_pri_rms = i_load_reflected * math.sqrt(d_min_vin)
        i_sec_rms = [io * math.sqrt(d_min_vin) for io in as_list(iout_list)]

        # Peak magnetizing current — worst case at 2 × Vin_min × D_max
        i_mag_pp = (2 * vin_min) * d_min_vin / (lm * fsw)
        i_mag_peak = i_mag_pp / 2

        turns_ratios = np_ns_list

        return {
            "Lm_uH": lm * 1e6,
            "Lout_uH": lout * 1e6,
            "Lout_list_uH": [l * 1e6 for l in lout_list],
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
            "ns_np_list": ns_np_list,
            "np_ns": np_ns,
            "n_windings": 1 + n_outputs,
            "duty_nom": d_nom,
            "duty_min_vin": d_min_vin,
            "duty_max_vin": d_max_vin,
            "i_pri_rms": i_pri_rms,
            "i_sec_rms": i_sec_rms,
            "i_mag_peak": i_mag_peak,
            "i_mag_pp": i_mag_pp,
            "pin_nom": pin_nom,
            "pout_nom": pout,
            "vin_nom": vin_nom,
            "vin_min": vin_min,
            "vin_max": vin_max,
            "fsw_hz": fsw,
            "vout_list": vout_list,
            "iout_list": iout_list,
        }

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[] for push-pull.
        Push-pull sees 2x Vin across primary (center-tap reflected), each half conducts
        alternately for D of the full period. Effective input voltage swing = 2*Vin.
        """
        op_list = []
        d = design_reqs.get("duty_nom", 0.45)
        i_mag_pp = design_reqs.get("i_mag_pp", 0.1)
        ns_np = design_reqs.get("ns_np", 0.05)
        vin = design_reqs.get("vin_nom", 100.0)
        vout_list = design_reqs.get("vout_list", [5.0])
        iout_list = design_reqs.get("iout_list", [1.0])

        for op in converter.get("operatingPoints", []):
            freq = as_float(op.get("switchingFrequency", 200e3))
            # Push-pull: effective voltage is 2*Vin across full primary
            ns_np_list = design_reqs.get("ns_np_list", [ns_np])
            i_load_reflected = sum(
                iout_list[j] * (ns_np_list[j] if j < len(ns_np_list) else ns_np)
                for j in range(len(iout_list))
            )
            i_pri_pp = i_mag_pp + i_load_reflected
            exc = [self._make_rectangular_excitation(
                "Primary", freq, i_pri_pp, i_pri_pp / 2, 2 * vin, vin * d, d)]
            for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
                name = "Secondary" if j == 0 else f"Secondary {j + 1}"
                exc.append(self._make_rectangular_excitation(
                    name, freq, iout_j * 0.3, iout_j, vout_j, vout_j * d / 2, d))
            op_list.append({
                "name": op.get("name", f"Operating Point {len(op_list)+1}"),
                "conditions": {"ambientTemperature": as_float(op.get("ambientTemperature", 25.0))},
                "excitationsPerWinding": exc,
            })
        return op_list

    def build_waveform_preview(self, design_reqs, operating_point, fsw):
        """Build waveform previews for push-pull.

        Primary: rectangular voltage (2x Vin effective), rectangular current
        Secondaries: rectangular voltage and current
        """
        windings = []
        d = design_reqs.get("duty_nom", 0.45)
        i_mag_pp = design_reqs.get("i_mag_pp", 0.1)
        iout_list = design_reqs.get("iout_list", [1.0])
        vout_list = design_reqs.get("vout_list", [5.0])
        vin = design_reqs.get("vin_nom", 100.0)
        ns_np = design_reqs.get("ns_np", 0.05)

        # Primary winding: sees 2x Vin effective across center tap
        ns_np_list = design_reqs.get("ns_np_list", [ns_np])
        i_load_reflected = sum(
            iout_list[j] * (ns_np_list[j] if j < len(ns_np_list) else ns_np)
            for j in range(len(iout_list))
        )
        i_pri_pp = i_mag_pp + i_load_reflected
        i_pri_offset = i_pri_pp / 2
        v_pri_pp = 2 * vin
        v_pri_offset = vin * d

        windings.append({
            "winding_name": "Primary",
            "voltage": {**self._create_rectangular_waveform(v_pri_pp, fsw, d, v_pri_offset), "label": "RECTANGULAR", "unit": "V"},
            "current": {**self._create_rectangular_waveform(i_pri_pp, fsw, d, i_pri_offset), "label": "RECTANGULAR", "unit": "A"},
        })

        # Secondary windings
        for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
            i_sec_pp = iout_j * 0.3
            i_sec_offset = iout_j
            v_sec_pp = vout_j
            v_sec_offset = vout_j * d / 2

            windings.append({
                "winding_name": "Secondary" if j == 0 else f"Secondary {j + 1}",
                "voltage": {**self._create_rectangular_waveform(v_sec_pp, fsw, d, v_sec_offset), "label": "SECONDARY_RECTANGULAR", "unit": "V"},
                "current": {**self._create_rectangular_waveform(i_sec_pp, fsw, d, i_sec_offset), "label": "RECTANGULAR", "unit": "A"},
            })

        return windings

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "Push Pull Converter",
            "magnetizingInductance": {"nominal": design_reqs["Lm_uH"] * 1e-6},
            "turnsRatios": [{"nominal": tr} for tr in design_reqs["turns_ratios"]],
        }


class BuckCalc(TopologyCalculator):
    """Buck converter (non-isolated, single inductor winding)."""

    def __init__(self):
        super().__init__()
        self.topology_key = "buck"
        self.topology_display = "Buck Converter"
        self.n_windings_min = 1
        self.n_windings_max = 1

    def compute_design_requirements(self, converter, advanced, n_outputs=1):
        """Compute Buck requirements."""
        c = converter
        fsw = as_float(c.get("operatingPoints", [{}])[0].get("switchingFrequency", 200e3))
        eta = as_float(c.get("efficiency", 90)) / 100.0
        vd = as_float(c.get("diodeVoltageDrop", 0.7))

        vin_min = as_float(c.get("inputVoltage", {}).get("minimum", 100))
        vin_max = as_float(c.get("inputVoltage", {}).get("maximum", 190))
        vin_nom = as_float(c.get("inputVoltage", {}).get("nominal"))
        if vin_nom <= 0:
            vin_nom = (vin_min + vin_max) / 2

        op = c.get("operatingPoints", [{}])[0]
        vout = as_float(op.get("outputVoltages", [5.0])[0] if op.get("outputVoltages") else 5.0)
        iout = as_float(op.get("outputCurrents", [5.0])[0] if op.get("outputCurrents") else 5.0)

        pout = vout * iout
        pin_nom = pout / max(eta, 0.01)

        # Buck: D = (Vout + Vd) / (Vin + Vd)
        d_nom = (vout + vd) / (vin_nom + vd)
        d_min_vin = (vout + vd) / (vin_min + vd)
        d_max_vin = (vout + vd) / (vin_max + vd)

        d_nom = clamp(d_nom, 0.01, 0.99)
        d_min_vin = clamp(d_min_vin, 0.01, 0.99)
        d_max_vin = clamp(d_max_vin, 0.01, 0.99)

        # Output inductor: L = (Vout + Vd) * (1 - D) / (delta_I * fsw)
        # Worst-case ripple at Vin_max (min D, max V_on across inductor)
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        delta_i_max = ripple_frac * iout
        if delta_i_max > 0:
            l_out = (vout + vd) * (1 - d_max_vin) / (delta_i_max * fsw)
        else:
            l_out = 10e-6

        return {
            "L_uH": l_out * 1e6,
            "turns_ratios": [],  # no transformer
            "n_windings": 1,
            "duty_nom": d_nom,
            "duty_min_vin": d_min_vin,
            "duty_max_vin": d_max_vin,
            "i_rms": iout,  # buck inductor carries continuous output current
            "pin_nom": pin_nom,
            "pout_nom": pout,
            "vin_nom": vin_nom,
            "vout": vout,
            "fsw_hz": fsw,
        }

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[] for buck with triangular inductor current.
        Buck inductor sees: (Vin - Vout) during on-time, (-Vout) during off-time.
        """
        op_list = []
        d = design_reqs.get("duty_nom", 0.5)
        l_uh = design_reqs.get("L_uH", 10.0)
        vin = design_reqs.get("vin_nom", 100.0)
        vout = design_reqs.get("vout", 5.0)
        pout = design_reqs.get("pout_nom", 25.0)
        iout = pout / max(vout, 0.1)

        for op in converter.get("operatingPoints", []):
            freq = as_float(op.get("switchingFrequency", 200e3))
            l = l_uh * 1e-6
            i_ripple = (vin - vout) * d / (l * freq) if l > 0 and freq > 0 else iout * 0.3
            v_pp = vin - vout
            exc = [self._make_triangular_excitation(
                "Inductor", freq, i_ripple, iout, v_pp, (vin - vout) * d / 2, d)]
            op_list.append({
                "name": op.get("name", f"Operating Point {len(op_list)+1}"),
                "conditions": {"ambientTemperature": as_float(op.get("ambientTemperature", 25.0))},
                "excitationsPerWinding": exc,
            })
        return op_list

    def build_waveform_preview(self, design_reqs, operating_point, fsw):
        """Build waveform previews for buck (non-isolated).

        Single inductor winding with triangular current ripple.
        """
        d = design_reqs.get("duty_nom", 0.5)
        l_uh = design_reqs.get("L_uH", 10.0)
        vin = design_reqs.get("vin_nom", 100.0)
        vout = design_reqs.get("vout", 5.0)
        pout = design_reqs.get("pout_nom", 25.0)
        iout = pout / max(vout, 0.1)

        l = l_uh * 1e-6
        i_ripple = (vin - vout) * d / (l * fsw) if l > 0 and fsw > 0 else iout * 0.3
        v_pp = vin - vout

        return [{
            "winding_name": "Inductor",
            "voltage": {**self._create_rectangular_waveform(v_pp, fsw, d, (vin - vout) * d / 2), "label": "RECTANGULAR", "unit": "V"},
            "current": {**self._create_triangular_waveform(i_ripple, fsw, d, iout), "label": "TRIANGULAR", "unit": "A"},
        }]

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements (no transformer, minimal MAS)."""
        return {
            "topology": "Buck Converter",
        }


class BoostCalc(TopologyCalculator):
    """Boost converter (non-isolated, single inductor winding)."""

    def __init__(self):
        super().__init__()
        self.topology_key = "boost"
        self.topology_display = "Boost Converter"
        self.n_windings_min = 1
        self.n_windings_max = 1

    def compute_design_requirements(self, converter, advanced, n_outputs=1):
        """Compute Boost requirements."""
        c = converter
        fsw = as_float(c.get("operatingPoints", [{}])[0].get("switchingFrequency", 200e3))
        eta = as_float(c.get("efficiency", 90)) / 100.0
        vd = as_float(c.get("diodeVoltageDrop", 0.7))

        vin_min = as_float(c.get("inputVoltage", {}).get("minimum", 100))
        vin_max = as_float(c.get("inputVoltage", {}).get("maximum", 190))
        vin_nom = as_float(c.get("inputVoltage", {}).get("nominal"))
        if vin_nom <= 0:
            vin_nom = (vin_min + vin_max) / 2

        op = c.get("operatingPoints", [{}])[0]
        vout = as_float(op.get("outputVoltages", [5.0])[0] if op.get("outputVoltages") else 5.0)
        iout = as_float(op.get("outputCurrents", [5.0])[0] if op.get("outputCurrents") else 5.0)

        pout = vout * iout
        pin_nom = pout / max(eta, 0.01)

        # Boost: D = 1 - Vin / (Vout + Vd)  [Erickson Eq.2.14 with diode drop]
        d_nom = 1 - vin_nom / (vout + vd)
        d_min_vin = 1 - vin_min / (vout + vd)
        d_max_vin = 1 - vin_max / (vout + vd)

        d_nom = clamp(d_nom, 0.01, 0.99)
        d_min_vin = clamp(d_min_vin, 0.01, 0.99)
        d_max_vin = clamp(d_max_vin, 0.01, 0.99)

        # Input inductor: L = Vin * D / (delta_I * fsw)
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        delta_i_max = ripple_frac * (pout / vin_nom)  # input current
        if delta_i_max > 0:
            l_in = vin_nom * d_nom / (delta_i_max * fsw)
        else:
            l_in = 10e-6

        return {
            "L_uH": l_in * 1e6,
            "turns_ratios": [],
            "n_windings": 1,
            "duty_nom": d_nom,
            "duty_min_vin": d_min_vin,
            "duty_max_vin": d_max_vin,
            "i_rms": pout / max(vin_nom, 0.1),  # boost inductor carries continuous input current
            "pin_nom": pin_nom,
            "pout_nom": pout,
            "vin_nom": vin_nom,
            "vout": vout,
            "fsw_hz": fsw,
        }

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[] for boost with triangular inductor current.
        Boost inductor sees: Vin during on-time (current rises), -(Vout - Vin) during off-time.
        """
        op_list = []
        d = design_reqs.get("duty_nom", 0.5)
        l_uh = design_reqs.get("L_uH", 10.0)
        vin = design_reqs.get("vin_nom", 100.0)
        vout = design_reqs.get("vout", 150.0)
        pout = design_reqs.get("pout_nom", 100.0)
        iin = pout / max(vin, 0.1)  # average input current

        for op in converter.get("operatingPoints", []):
            freq = as_float(op.get("switchingFrequency", 200e3))
            l = l_uh * 1e-6
            i_ripple = vin * d / (l * freq) if l > 0 and freq > 0 else iin * 0.3
            # Boost inductor current ripple around average input current
            exc = [self._make_triangular_excitation(
                "Inductor", freq, i_ripple, iin, vin, vin * d / 2, d)]
            op_list.append({
                "name": op.get("name", f"Operating Point {len(op_list)+1}"),
                "conditions": {"ambientTemperature": as_float(op.get("ambientTemperature", 25.0))},
                "excitationsPerWinding": exc,
            })
        return op_list

    def build_waveform_preview(self, design_reqs, operating_point, fsw):
        """Build waveform previews for boost (non-isolated).

        Single inductor winding with triangular current ripple.
        """
        d = design_reqs.get("duty_nom", 0.5)
        l_uh = design_reqs.get("L_uH", 10.0)
        vin = design_reqs.get("vin_nom", 100.0)
        vout = design_reqs.get("vout", 150.0)
        pout = design_reqs.get("pout_nom", 100.0)
        iin = pout / max(vin, 0.1)

        l = l_uh * 1e-6
        i_ripple = vin * d / (l * fsw) if l > 0 and fsw > 0 else iin * 0.3

        return [{
            "winding_name": "Inductor",
            "voltage": {**self._create_rectangular_waveform(vin, fsw, d, vin * d / 2), "label": "RECTANGULAR", "unit": "V"},
            "current": {**self._create_triangular_waveform(i_ripple, fsw, d, iin), "label": "TRIANGULAR", "unit": "A"},
        }]

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements (no transformer)."""
        return {
            "topology": "Boost Converter",
        }


class IsolatedBuckCalc(TopologyCalculator):
    """Isolated Buck converter (isolated dc-dc, transformer + sync rect)."""

    def __init__(self):
        super().__init__()
        self.topology_key = "isolated_buck"
        self.topology_display = "Isolated Buck Converter"
        self.n_windings_min = 2
        self.n_windings_max = 5

    def compute_design_requirements(self, converter, advanced, n_outputs=1):
        """Compute Isolated Buck requirements.

        Isolated buck: transformer provides galvanic isolation while the topology
        operates like a regular buck. Duty cycle D = Vout / (Vin * Ns/Np * eta).
        The primary magnetizing inductance is sized for triangular ripple current.
        """
        c = converter
        fsw = as_float(c.get("operatingPoints", [{}])[0].get("switchingFrequency", 200e3))
        eta = as_float(c.get("efficiency", 90)) / 100.0
        vd = as_float(c.get("diodeVoltageDrop", 0.7))

        vin_min = as_float(c.get("inputVoltage", {}).get("minimum", 100))
        vin_max = as_float(c.get("inputVoltage", {}).get("maximum", 190))
        vin_nom = as_float(c.get("inputVoltage", {}).get("nominal"))
        if vin_nom <= 0:
            vin_nom = (vin_min + vin_max) / 2

        op = c.get("operatingPoints", [{}])[0]
        vout_list = as_list(op.get("outputVoltages", [5.0]))
        iout_list = as_list(op.get("outputCurrents", [5.0]))

        vout = vout_list[0] if vout_list else 5.0
        total_iout = sum(as_list(iout_list))

        # Output power (sum of each output's V*I)
        pout = sum(
            vout_list[i] * iout_list[i]
            for i in range(min(len(vout_list), len(iout_list)))
        )
        pin_nom = pout / max(eta, 0.01)

        # Isolated Buck duty cycle: D = (Vout + Vd) / (Vin * Ns/Np)
        # Unlike forward converters, isolated buck can use full 0-1 duty range.
        # Choose Ns/Np so D_nom ~ 0.5 at Vin_nom for maximum volt-second headroom.
        d_target_nom = 0.50
        ns_np = (vout + vd) / (vin_nom * d_target_nom)
        np_ns = 1.0 / ns_np
        ns_np_list = [ns_np] * n_outputs

        d_nom = (vout + vd) / (vin_nom * ns_np)
        d_min_vin = (vout + vd) / (vin_min * ns_np)
        d_max_vin = (vout + vd) / (vin_max * ns_np)

        d_nom = clamp(d_nom, 0.01, 0.99)
        d_min_vin = clamp(d_min_vin, 0.01, 0.99)
        d_max_vin = clamp(d_max_vin, 0.01, 0.99)

        # Output filter inductor: L = (Vin_max*Ns/Np - Vout) * (1-D) / (delta_I * fsw)
        # This is the secondary-side filter inductor for the isolated buck.
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        delta_i = ripple_frac * total_iout
        vin_sec_max = vin_max * ns_np  # max voltage reflected to secondary
        if delta_i > 0 and fsw > 0:
            lout = (vin_sec_max - vout) * d_max_vin / (delta_i * fsw)
        else:
            lout = 10e-6

        # Magnetizing inductance: sized from (Vin - Vout/ns_np) * D / (delta_Im * fsw)
        # where delta_Im = 10% of reflected load current (primary side triangular ripple)
        # Worst case ripple at Vin_max (largest V_Lm = Vin - Vout_reflected)
        i_load_reflected = total_iout * ns_np
        delta_im = 0.10 * i_load_reflected
        if delta_im > 0 and fsw > 0:
            lm = (vin_max - vout / ns_np) * d_max_vin / (delta_im * fsw)
            lm = max(lm, 10e-6)
        else:
            lm = 100e-6

        # Currents — worst case at Vin_min (maximum duty cycle)
        i_pri_rms = total_iout * ns_np * math.sqrt(d_min_vin)
        i_sec_rms = [io * math.sqrt(d_min_vin) for io in as_list(iout_list)]
        # Magnetizing current ripple — worst case at Vin_max
        i_mag_pp = (vin_max - vout * np_ns) * d_max_vin / (lm * fsw)
        i_mag_peak = i_mag_pp / 2 + i_load_reflected

        turns_ratios = [np_ns] * n_outputs

        return {
            "Lm_uH": lm * 1e6,
            "Lout_uH": lout * 1e6,
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
            "ns_np_list": ns_np_list,
            "np_ns": np_ns,
            "n_windings": 1 + n_outputs,
            "duty_nom": d_nom,
            "duty_min_vin": d_min_vin,
            "duty_max_vin": d_max_vin,
            "i_pri_rms": i_pri_rms,
            "i_sec_rms": i_sec_rms,
            "i_mag_peak": i_mag_peak,
            "i_mag_pp": i_mag_pp,
            "pin_nom": pin_nom,
            "pout_nom": pout,
            "vin_nom": vin_nom,
            "vin_min": vin_min,
            "vin_max": vin_max,
            "fsw_hz": fsw,
            "vout_list": vout_list,
            "iout_list": iout_list,
        }

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[] for isolated buck with triangular primary current.
        Primary sees triangular current during on-time (like a buck inductor reflected through xfmr).
        Secondary sees triangular filtered current.
        """
        op_list = []
        d = design_reqs.get("duty_nom", 0.5)
        i_mag_pp = design_reqs.get("i_mag_pp", 0.1)
        i_mag_peak = design_reqs.get("i_mag_peak", i_mag_pp)
        ns_np = design_reqs.get("ns_np", 0.05)
        vin = design_reqs.get("vin_nom", 100.0)
        vout_list = design_reqs.get("vout_list", [5.0])
        iout_list = design_reqs.get("iout_list", [1.0])

        for op in converter.get("operatingPoints", []):
            freq = as_float(op.get("switchingFrequency", 200e3))
            # Primary: triangular current (reflected buck inductor current)
            i_pri_offset = i_mag_peak - i_mag_pp / 2
            v_pri_pp = vin
            exc = [self._make_triangular_excitation(
                "Primary", freq, i_mag_pp, i_pri_offset, v_pri_pp, vin * d / 2, d)]
            # Secondaries: triangular filtered current
            for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
                name = "Secondary" if j == 0 else f"Secondary {j + 1}"
                i_sec_ripple = iout_j * 0.3
                exc.append(self._make_triangular_excitation(
                    name, freq, i_sec_ripple, iout_j, vout_j, vout_j * d / 2, d))
            op_list.append({
                "name": op.get("name", f"Operating Point {len(op_list)+1}"),
                "conditions": {"ambientTemperature": as_float(op.get("ambientTemperature", 25.0))},
                "excitationsPerWinding": exc,
            })
        return op_list

    def build_waveform_preview(self, design_reqs, operating_point, fsw):
        """Build waveform previews for isolated buck.

        Primary: rectangular voltage, triangular current during on-time
        Secondaries: rectangular voltage, triangular filtered current
        """
        windings = []
        d = design_reqs.get("duty_nom", 0.5)
        i_mag_pp = design_reqs.get("i_mag_pp", 0.1)
        i_mag_peak = design_reqs.get("i_mag_peak", i_mag_pp)
        iout_list = design_reqs.get("iout_list", [1.0])
        vout_list = design_reqs.get("vout_list", [5.0])
        vin = design_reqs.get("vin_nom", 100.0)

        # Primary winding: triangular current during on-time
        i_pri_offset = i_mag_peak - i_mag_pp / 2
        v_pri_pp = vin

        windings.append({
            "winding_name": "Primary",
            "voltage": {**self._create_rectangular_waveform(v_pri_pp, fsw, d, vin * d / 2), "label": "RECTANGULAR", "unit": "V"},
            "current": {**self._create_triangular_waveform(i_mag_pp, fsw, d, i_pri_offset), "label": "TRIANGULAR", "unit": "A"},
        })

        # Secondary windings: triangular filtered current
        for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
            i_sec_ripple = iout_j * 0.3

            windings.append({
                "winding_name": "Secondary" if j == 0 else f"Secondary {j + 1}",
                "voltage": {**self._create_rectangular_waveform(vout_j, fsw, d, vout_j * d / 2), "label": "RECTANGULAR", "unit": "V"},
                "current": {**self._create_triangular_waveform(i_sec_ripple, fsw, d, iout_j), "label": "TRIANGULAR", "unit": "A"},
            })

        return windings

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "Isolated Buck Converter",
            "magnetizingInductance": {"nominal": design_reqs["Lm_uH"] * 1e-6},
            "turnsRatios": [{"nominal": tr} for tr in design_reqs["turns_ratios"]],
        }


class IsolatedBuckBoostCalc(TopologyCalculator):
    """Isolated Buck-Boost converter (transformer + sync rect, bidirectional)."""

    def __init__(self):
        super().__init__()
        self.topology_key = "isolated_buck_boost"
        self.topology_display = "Isolated Buck-Boost Converter"
        self.n_windings_min = 2
        self.n_windings_max = 5

    def compute_design_requirements(self, converter, advanced, n_outputs=1):
        """Compute Isolated Buck-Boost requirements.

        Isolated buck-boost: allows Vout > Vin or Vout < Vin (both step-up and step-down).
        Duty cycle: D = Vout / (Vin + Vout) * eta  (classic buck-boost relation).
        Lm stores all energy during on-time and transfers during off-time.
        The harmonic mean Vin*Vout/(Vin+Vout) is the effective voltage for inductance sizing.
        """
        c = converter
        fsw = as_float(c.get("operatingPoints", [{}])[0].get("switchingFrequency", 200e3))
        eta = as_float(c.get("efficiency", 90)) / 100.0
        vd = as_float(c.get("diodeVoltageDrop", 0.7))

        vin_min = as_float(c.get("inputVoltage", {}).get("minimum", 100))
        vin_max = as_float(c.get("inputVoltage", {}).get("maximum", 190))
        vin_nom = as_float(c.get("inputVoltage", {}).get("nominal"))
        if vin_nom <= 0:
            vin_nom = (vin_min + vin_max) / 2

        op = c.get("operatingPoints", [{}])[0]
        vout_list = as_list(op.get("outputVoltages", [5.0]))
        iout_list = as_list(op.get("outputCurrents", [5.0]))

        vout = vout_list[0] if vout_list else 5.0
        total_iout = sum(as_list(iout_list))

        # Output power (sum of each output's V*I)
        pout = sum(
            vout_list[i] * iout_list[i]
            for i in range(min(len(vout_list), len(iout_list)))
        )
        pin_nom = pout / max(eta, 0.01)

        # Buck-boost duty cycle: D = Vout / (Vin + Vout) (ignoring Vd for turns ratio calc)
        # Rearranged for turns ratio: choose Ns/Np so that at Vin_nom D_nom = 0.5
        # D = ns_np * Vout / (Vin + ns_np * Vout)  → at D=0.5: Vin = ns_np * Vout
        ns_np = vin_nom / (vout + vd)  # balanced point (D=0.5 at Vin_nom)
        np_ns = 1.0 / ns_np

        # Duty cycles across input range
        d_nom = (ns_np * (vout + vd)) / (vin_nom + ns_np * (vout + vd))
        d_min_vin = (ns_np * (vout + vd)) / (vin_min + ns_np * (vout + vd))
        d_max_vin = (ns_np * (vout + vd)) / (vin_max + ns_np * (vout + vd))

        d_nom = clamp(d_nom, 0.01, 0.99)
        d_min_vin = clamp(d_min_vin, 0.01, 0.99)
        d_max_vin = clamp(d_max_vin, 0.01, 0.99)

        # Magnetizing inductance: Lm = Vin*Vout / ((Vin+Vout) * 2*delta_Im * fsw)
        # The harmonic mean Vin*Vout/(Vin+Vout) is the effective volt-second product
        # Factor of 2 because both on-time and off-time contribute equally to current swing
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        i_load_reflected = total_iout * ns_np
        delta_im = ripple_frac * i_load_reflected if i_load_reflected > 0 else 0.1
        v_harmonic = (vin_nom * vout * np_ns) / (vin_nom + vout * np_ns)  # effective voltage
        if delta_im > 0 and fsw > 0:
            lm = v_harmonic / (2 * delta_im * fsw)
            lm = max(lm, 10e-6)
        else:
            lm = 100e-6

        # Current waveforms: symmetric triangular (on-time and off-time equal swing)
        i_mag_pp = v_harmonic / (lm * fsw) if lm > 0 and fsw > 0 else delta_im * 2
        i_mag_peak = i_load_reflected + i_mag_pp / 2

        # RMS currents: primary conducts on-time, secondary conducts off-time
        i_pri_rms = math.sqrt((i_mag_peak**2 - i_mag_peak * i_mag_pp + i_mag_pp**2 / 3) * d_nom)
        i_sec_rms = [io * math.sqrt(1 - d_nom) for io in as_list(iout_list)]

        # No separate output inductor — Lm stores and transfers all energy
        turns_ratios = [np_ns] * n_outputs
        ns_np_list = [ns_np] * n_outputs

        return {
            "Lm_uH": lm * 1e6,
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
            "ns_np_list": ns_np_list,
            "np_ns": np_ns,
            "n_windings": 1 + n_outputs,
            "duty_nom": d_nom,
            "duty_min_vin": d_min_vin,
            "duty_max_vin": d_max_vin,
            "i_pri_rms": i_pri_rms,
            "i_sec_rms": i_sec_rms,
            "i_mag_peak": i_mag_peak,
            "i_mag_pp": i_mag_pp,
            "pin_nom": pin_nom,
            "pout_nom": pout,
            "vin_nom": vin_nom,
            "fsw_hz": fsw,
            "vout_list": vout_list,
            "iout_list": iout_list,
        }

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[] for isolated buck-boost.
        Like flyback: primary stores energy (triangular rising) during on-time,
        secondary releases energy (triangular falling) during off-time.
        Symmetric current swing due to harmonic mean voltage.
        """
        op_list = []
        d = design_reqs.get("duty_nom", 0.5)
        i_mag_pp = design_reqs.get("i_mag_pp", 1.0)
        i_mag_peak = design_reqs.get("i_mag_peak", i_mag_pp)
        ns_np = design_reqs.get("ns_np", 0.05)
        vin = design_reqs.get("vin_nom", 100.0)
        vout_list = design_reqs.get("vout_list", [5.0])
        iout_list = design_reqs.get("iout_list", [1.0])

        for op in converter.get("operatingPoints", []):
            freq = as_float(op.get("switchingFrequency", 200e3))
            # Primary: triangular rising current during on-time (energy storage, like flyback)
            i_pri_offset = i_mag_peak - i_mag_pp / 2
            exc = [self._make_triangular_excitation(
                "Primary", freq, i_mag_pp, i_pri_offset, vin, vin * d / 2, d)]
            # Secondaries: triangular falling current during off-time (energy transfer)
            for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
                name = "Secondary" if j == 0 else f"Secondary {j + 1}"
                i_sec_pp = i_mag_pp / ns_np  # reflected magnetizing swing
                i_sec_offset = iout_j
                exc.append(self._make_triangular_excitation(
                    name, freq, i_sec_pp, i_sec_offset, vout_j, vout_j * (1 - d) / 2, 1 - d))
            op_list.append({
                "name": op.get("name", f"Operating Point {len(op_list)+1}"),
                "conditions": {"ambientTemperature": as_float(op.get("ambientTemperature", 25.0))},
                "excitationsPerWinding": exc,
            })
        return op_list

    def build_waveform_preview(self, design_reqs, operating_point, fsw):
        """Build waveform previews for isolated buck-boost.

        Primary: rectangular voltage, triangular current during on-time (energy storage)
        Secondaries: rectangular voltage, triangular current during off-time (energy transfer)
        """
        windings = []
        d = design_reqs.get("duty_nom", 0.5)
        i_mag_pp = design_reqs.get("i_mag_pp", 1.0)
        i_mag_peak = design_reqs.get("i_mag_peak", i_mag_pp)
        iout_list = design_reqs.get("iout_list", [1.0])
        vout_list = design_reqs.get("vout_list", [5.0])
        vin = design_reqs.get("vin_nom", 100.0)
        ns_np = design_reqs.get("ns_np", 0.05)

        # Primary winding: triangular rising current during on-time (energy storage)
        i_pri_offset = i_mag_peak - i_mag_pp / 2

        windings.append({
            "winding_name": "Primary",
            "voltage": {**self._create_rectangular_waveform(vin, fsw, d, vin * d / 2), "label": "RECTANGULAR", "unit": "V"},
            "current": {**self._create_triangular_waveform(i_mag_pp, fsw, d, i_pri_offset), "label": "TRIANGULAR", "unit": "A"},
        })

        # Secondary windings: triangular falling current during off-time (energy transfer)
        for j, (iout_j, vout_j) in enumerate(zip(as_list(iout_list), as_list(vout_list))):
            i_sec_pp = i_mag_pp / ns_np
            i_sec_offset = iout_j

            windings.append({
                "winding_name": "Secondary" if j == 0 else f"Secondary {j + 1}",
                "voltage": {**self._create_rectangular_waveform(vout_j, fsw, 1 - d, vout_j * (1 - d) / 2), "label": "RECTANGULAR", "unit": "V"},
                "current": {**self._create_triangular_waveform(i_sec_pp, fsw, 1 - d, i_sec_offset), "label": "TRIANGULAR", "unit": "A"},
            })

        return windings

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "Isolated Buck Boost Converter",
            "magnetizingInductance": {"nominal": design_reqs["Lm_uH"] * 1e-6},
            "turnsRatios": [{"nominal": tr} for tr in design_reqs["turns_ratios"]],
        }


# Global registry of topology calculators
TOPOLOGY_CALCULATORS = {
    "two_switch_forward": TwoSwitchForwardCalc,
    "single_switch_forward": SingleSwitchForwardCalc,
    "active_clamp_forward": ActiveClampForwardCalc,
    "flyback": FlybackCalc,
    "push_pull": PushPullCalc,
    "buck": BuckCalc,
    "boost": BoostCalc,
    "isolated_buck": IsolatedBuckCalc,
    "isolated_buck_boost": IsolatedBuckBoostCalc,
}


def compute_topology(config):
    """
    Main entry point for compute_topology mode.

    Args:
        config: dict with mode, topology, design_mode, converter, advanced, output_file

    Returns:
        dict with status, computed values, and mas_inputs
    """
    try:
        topology_key = config.get("topology", "two_switch_forward").strip().lower()
        if topology_key not in TOPOLOGY_CALCULATORS:
            return {"status": "ERROR", "error": f"Unknown topology: {topology_key}"}

        calc_class = TOPOLOGY_CALCULATORS[topology_key]
        calc = calc_class()

        design_mode = config.get("design_mode", "auto").lower()
        converter = config.get("converter", {})
        advanced = config.get("advanced", {})

        # Normalize flat MATLAB keys to MAS-nested format expected by all
        # topology calculators.  MATLAB topology_wizard.m sends vin_min/vin_max
        # etc., but compute_design_requirements() reads inputVoltage.minimum.
        if "vin_min" in converter and "inputVoltage" not in converter:
            vin_nom_raw = converter.get("vin_nom")
            # MATLAB jsonencode([]) → [] in JSON; treat as missing
            if isinstance(vin_nom_raw, list) or vin_nom_raw is None:
                vin_nom_val = None
            else:
                vin_nom_val = as_float(vin_nom_raw)
                if vin_nom_val <= 0:
                    vin_nom_val = None
            iv = {
                "minimum": as_float(converter.get("vin_min", 100)),
                "maximum": as_float(converter.get("vin_max", 190)),
            }
            if vin_nom_val is not None:
                iv["nominal"] = vin_nom_val
            converter["inputVoltage"] = iv
        if "vd" in converter and "diodeVoltageDrop" not in converter:
            converter["diodeVoltageDrop"] = as_float(converter.get("vd", 0.7))
        if "max_ripple" in converter and "currentRippleRatio" not in converter:
            converter["currentRippleRatio"] = as_float(converter.get("max_ripple", 30))

        # Determine number of outputs for isolated topologies
        # Prefer explicit n_outputs from config (set by GUI spinner) over inferring
        # from outputVoltages array length, because MATLAB may send a scalar even
        # when the user selected multiple outputs.
        explicit_n = config.get("n_outputs", None)
        if explicit_n is not None and isinstance(explicit_n, (int, float)) and explicit_n >= 1:
            n_outputs = int(explicit_n)
        else:
            op = converter.get("operatingPoints", [{}])[0]
            vout_list = op.get("outputVoltages", [5.0])
            if isinstance(vout_list, list):
                n_outputs = len(vout_list)
            else:
                n_outputs = 1

        # Ensure n_outputs is within range
        n_outputs = max(1, min(n_outputs, calc.n_windings_max - (2 if "single_switch" in topology_key else 1)))

        # Compute design requirements
        design_reqs = calc.compute_design_requirements(converter, advanced, n_outputs)

        # Build MAS structures
        mas_design_requirements = calc.build_mas_design_requirements(converter, design_reqs)
        mas_operating_points = calc.build_operating_points(converter, design_reqs)

        # Build waveform previews for each operating point
        waveforms_preview = []
        fsw = design_reqs.get("fsw_hz", 200e3)
        for op in converter.get("operatingPoints", []):
            op_fsw = as_float(op.get("switchingFrequency", fsw))
            waveforms_preview.append(calc.build_waveform_preview(design_reqs, op, op_fsw))

        # Build result dict
        result = {
            "status": "OK",
            "topology": topology_key,
            "topology_display": calc.get_topology_display_name(),
            "design_mode": design_mode,
            "computed": {
                k: v for k, v in design_reqs.items()
                if k not in ["vout_list", "iout_list"]  # Don't duplicate in output
            },
            "mas_inputs": {
                "designRequirements": mas_design_requirements,
                "operatingPoints": mas_operating_points,
            },
            "waveforms_preview": waveforms_preview,
        }

        return result

    except Exception as e:
        print(f"[TOPOLOGY] Exception: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        return {"status": "ERROR", "error": str(e)}


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print("[TOPOLOGY] Usage: python generate_om_topology.py <config.json>", file=sys.stderr)
        sys.exit(1)

    config_file = sys.argv[1]
    try:
        with open(config_file, "r", encoding="utf-8") as fh:
            config = json.load(fh)
    except Exception as e:
        print(f"[TOPOLOGY] Failed to load config: {e}", file=sys.stderr)
        sys.exit(1)

    mode = config.get("mode", "compute_topology").lower()
    if mode == "compute_topology":
        result = compute_topology(config)
    else:
        result = {"status": "ERROR", "error": f"Unknown mode: {mode}"}

    # Write result
    output_file = config.get("output_file", "om_topology_results.json")
    try:
        with open(output_file, "w", encoding="utf-8") as fh:
            json.dump(result, fh, indent=2)
        if result.get("status") == "OK":
            print(f"[TOPOLOGY] OK: {result.get('topology_display')}", file=sys.stderr)
        else:
            print(f"[TOPOLOGY] ERROR: {result.get('error')}", file=sys.stderr)
            sys.exit(1)
    except Exception as e:
        print(f"[TOPOLOGY] Failed to write output: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
