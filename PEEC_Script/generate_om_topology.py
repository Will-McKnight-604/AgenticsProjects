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

try:
    import PyOpenMagnetics as pm
except Exception as exc:
    print(f"[TOPOLOGY] ImportError: {exc}", file=sys.stderr)
    sys.exit(1)


def clamp(value, lo, hi):
    """Clamp value between lo and hi."""
    return max(lo, min(hi, value))


def as_float(value, default=0.0):
    """Convert to float, return default if fails."""
    try:
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, str):
            return float(value)
        return float(default)
    except Exception:
        return float(default)


def as_list(value):
    """Ensure value is a list. Wrap scalars."""
    if isinstance(value, list):
        return value
    if isinstance(value, (int, float)):
        return [value]
    if isinstance(value, str):
        try:
            return [float(value)]
        except Exception:
            return []
    return []


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

        # Output power
        pout = vout * total_iout
        pin_nom = pout / max(eta, 0.01)

        # Turns ratio: choose Ns/Np so D_max ~ 0.45 at Vin_min
        d_target_max = 0.45
        ns_np = (vout + vd) / (vin_min * d_target_max)
        np_ns = 1.0 / ns_np

        # Actual duty cycles
        d_min_vin = (vout + vd) / (vin_min * ns_np)
        d_max_vin = (vout + vd) / (vin_max * ns_np)
        d_nom = (vout + vd) / (vin_nom * ns_np)

        d_min_vin = clamp(d_min_vin, 0.01, 0.49)
        d_max_vin = clamp(d_max_vin, 0.01, 0.49)
        d_nom = clamp(d_nom, 0.01, 0.49)

        # Output inductor (for first output)
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        delta_i_max = ripple_frac * iout
        if delta_i_max > 0:
            lout = vout * (1 - d_max_vin) / (delta_i_max * fsw)
        else:
            lout = 100e-6

        # Magnetizing inductance
        i_load_reflected = total_iout * ns_np
        i_mag_ripple_target = 0.10 * i_load_reflected
        if i_mag_ripple_target > 0:
            lm = vin_nom * d_nom / (i_mag_ripple_target * fsw)
        else:
            lm = 500e-6

        # RMS currents
        i_pri_rms = total_iout * ns_np * math.sqrt(d_nom)
        i_sec_rms = [io * math.sqrt(d_nom) for io in as_list(iout_list)]

        # Peak magnetizing current
        i_mag_peak = vin_nom * d_nom / (2 * lm * fsw)
        i_mag_pp = vin_nom * d_nom / (lm * fsw)

        # Build turns ratios for each output (could differ in advanced mode)
        turns_ratios = [np_ns] * n_outputs

        return {
            "Lm_uH": lm * 1e6,
            "Lout_uH": lout * 1e6,
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
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

            # Primary excitation
            exc_per_winding.append({
                "name": "Primary",
                "frequency": as_float(op.get("switchingFrequency", 200e3)),
            })

            # Secondary excitations
            for j in range(len(design_reqs.get("iout_list", []))):
                exc_per_winding.append({
                    "name": f"Secondary {j + 1}" if j > 0 else "Secondary",
                    "frequency": as_float(op.get("switchingFrequency", 200e3)),
                })

            op_list.append({"excitationsPerWinding": exc_per_winding})

        return op_list

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "two-switch-forward",
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

        pout = vout * total_iout
        pin_nom = pout / max(eta, 0.01)

        # Single-switch forward duty is typically 0.5, demagnetization winding carries reset
        # Turns ratio for main output
        d_target_max = 0.5  # Single switch can reach 50%
        ns_np = (vout + vd) / (vin_min * d_target_max)
        np_ns = 1.0 / ns_np

        d_min_vin = (vout + vd) / (vin_min * ns_np)
        d_max_vin = (vout + vd) / (vin_max * ns_np)
        d_nom = (vout + vd) / (vin_nom * ns_np)

        d_min_vin = clamp(d_min_vin, 0.01, 0.50)
        d_max_vin = clamp(d_max_vin, 0.01, 0.50)
        d_nom = clamp(d_nom, 0.01, 0.50)

        # Demagnetization winding turns ratio (typically equal to primary for simplicity)
        nd_np = 1.0

        # Output inductor
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        delta_i_max = ripple_frac * vout_list[0] if vout_list else 1.0
        if delta_i_max > 0:
            lout = vout * (1 - d_max_vin) / (delta_i_max * fsw)
        else:
            lout = 100e-6

        # Magnetizing inductance
        i_load_reflected = total_iout * ns_np
        i_mag_ripple_target = 0.10 * i_load_reflected
        if i_mag_ripple_target > 0:
            lm = vin_nom * d_nom / (i_mag_ripple_target * fsw)
        else:
            lm = 500e-6

        # RMS currents
        i_pri_rms = total_iout * ns_np * math.sqrt(d_nom)
        i_demag_rms = total_iout * nd_np * math.sqrt(d_nom)
        i_sec_rms = [io * math.sqrt(d_nom) for io in as_list(iout_list)]

        i_mag_peak = vin_nom * d_nom / (2 * lm * fsw)
        i_mag_pp = vin_nom * d_nom / (lm * fsw)

        # Build turns ratios [primary to secondary outputs, primary to demagnetization]
        turns_ratios = [np_ns] * n_outputs + [nd_np]

        return {
            "Lm_uH": lm * 1e6,
            "Lout_uH": lout * 1e6,
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
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
            "fsw_hz": fsw,
            "vout_list": vout_list,
            "iout_list": iout_list,
        }

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[]."""
        op_list = []
        for i, op in enumerate(converter.get("operatingPoints", [])):
            exc_per_winding = []

            # Primary excitation
            exc_per_winding.append({
                "name": "Primary",
                "frequency": as_float(op.get("switchingFrequency", 200e3)),
            })

            # Secondary excitations
            for j in range(len(design_reqs.get("iout_list", []))):
                exc_per_winding.append({
                    "name": f"Secondary {j + 1}" if j > 0 else "Secondary",
                    "frequency": as_float(op.get("switchingFrequency", 200e3)),
                })

            # Demagnetization winding (last)
            exc_per_winding.append({
                "name": "Demagnetization",
                "frequency": as_float(op.get("switchingFrequency", 200e3)),
            })

            op_list.append({"excitationsPerWinding": exc_per_winding})

        return op_list

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "single-switch-forward",
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

        pout = vout * total_iout
        pin_nom = pout / max(eta, 0.01)

        # Similar turns ratio calculation
        d_target_max = 0.45
        ns_np = (vout + vd) / (vin_min * d_target_max)
        np_ns = 1.0 / ns_np

        d_min_vin = (vout + vd) / (vin_min * ns_np)
        d_max_vin = (vout + vd) / (vin_max * ns_np)
        d_nom = (vout + vd) / (vin_nom * ns_np)

        d_min_vin = clamp(d_min_vin, 0.01, 0.49)
        d_max_vin = clamp(d_max_vin, 0.01, 0.49)
        d_nom = clamp(d_nom, 0.01, 0.49)

        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        delta_i_max = ripple_frac * vout
        if delta_i_max > 0:
            lout = vout * (1 - d_max_vin) / (delta_i_max * fsw)
        else:
            lout = 100e-6

        i_load_reflected = total_iout * ns_np
        i_mag_ripple_target = 0.10 * i_load_reflected
        if i_mag_ripple_target > 0:
            lm = vin_nom * d_nom / (i_mag_ripple_target * fsw)
        else:
            lm = 500e-6

        i_pri_rms = total_iout * ns_np * math.sqrt(d_nom)
        i_sec_rms = [io * math.sqrt(d_nom) for io in as_list(iout_list)]

        i_mag_peak = vin_nom * d_nom / (2 * lm * fsw)
        i_mag_pp = vin_nom * d_nom / (lm * fsw)

        turns_ratios = [np_ns] * n_outputs

        return {
            "Lm_uH": lm * 1e6,
            "Lout_uH": lout * 1e6,
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
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
            op_list.append({"excitationsPerWinding": exc_per_winding})
        return op_list

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "active-clamp-forward",
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

        pout = vout * total_iout
        pin_nom = pout / max(eta, 0.01)

        # Flyback: D = N*Vout / (Vin + N*Vout), where N = Ns/Np
        # Lm stores energy during on-time, transfers during off-time
        # For auto mode, constrain max duty to ~0.5
        d_target_max = 0.50
        ns_np = (vin_min * d_target_max) / (vout + vd)  # inverted from forward
        np_ns = 1.0 / ns_np

        d_min_vin = (ns_np * vout) / (vin_min + ns_np * vout)
        d_max_vin = (ns_np * vout) / (vin_max + ns_np * vout)
        d_nom = (ns_np * vout) / (vin_nom + ns_np * vout)

        d_min_vin = clamp(d_min_vin, 0.01, 0.50)
        d_max_vin = clamp(d_max_vin, 0.01, 0.50)
        d_nom = clamp(d_nom, 0.01, 0.50)

        # For flyback, Lm stores all output energy
        # Lm = Vin^2 * D^2 / (2 * Pout * fsw * (1 + ripple))
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        if pin_nom > 0:
            lm = (vin_nom**2 * d_nom**2) / (2 * pin_nom * fsw * (1 + ripple_frac))
        else:
            lm = 500e-6

        # RMS currents (primary conducts during on-time)
        i_pri_rms = math.sqrt(pout / vin_nom * d_nom)  # approximate
        i_sec_rms = [io * math.sqrt(1 - d_nom) for io in as_list(iout_list)]  # conducts during off-time

        i_mag_peak = vin_nom * d_nom / (lm * fsw)
        i_mag_pp = vin_nom * d_nom / (lm * fsw)

        turns_ratios = [np_ns] * n_outputs

        return {
            "Lm_uH": lm * 1e6,
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
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
            op_list.append({"excitationsPerWinding": exc_per_winding})
        return op_list

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "flyback",
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

        pout = vout * total_iout
        pin_nom = pout / max(eta, 0.01)

        # Push-Pull: center-tapped primary, duty ~0.5 per switch
        # Voltage on secondary is 2 * Vin at full duty
        d_target_max = 0.45
        ns_np = (vout + vd) / (2 * vin_min * d_target_max)  # 2x multiplier
        np_ns = 1.0 / ns_np

        d_min_vin = (vout + vd) / (2 * vin_min * ns_np)
        d_max_vin = (vout + vd) / (2 * vin_max * ns_np)
        d_nom = (vout + vd) / (2 * vin_nom * ns_np)

        d_min_vin = clamp(d_min_vin, 0.01, 0.49)
        d_max_vin = clamp(d_max_vin, 0.01, 0.49)
        d_nom = clamp(d_nom, 0.01, 0.49)

        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        delta_i_max = ripple_frac * vout
        if delta_i_max > 0:
            lout = vout * (1 - d_max_vin) / (delta_i_max * fsw)
        else:
            lout = 100e-6

        i_load_reflected = total_iout * ns_np
        i_mag_ripple_target = 0.10 * i_load_reflected
        if i_mag_ripple_target > 0:
            lm = (2 * vin_nom) * d_nom / (i_mag_ripple_target * fsw)  # 2x for center tap
        else:
            lm = 500e-6

        i_pri_rms = total_iout * ns_np * math.sqrt(d_nom)
        i_sec_rms = [io * math.sqrt(d_nom) for io in as_list(iout_list)]

        i_mag_peak = (2 * vin_nom) * d_nom / (2 * lm * fsw)
        i_mag_pp = (2 * vin_nom) * d_nom / (lm * fsw)

        turns_ratios = [np_ns] * n_outputs

        return {
            "Lm_uH": lm * 1e6,
            "Lout_uH": lout * 1e6,
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
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
            op_list.append({"excitationsPerWinding": exc_per_winding})
        return op_list

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "push-pull",
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

        # Output inductor: L = Vout * (1 - D) / (delta_I * fsw)
        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        delta_i_max = ripple_frac * iout
        if delta_i_max > 0:
            l_out = vout * (1 - d_min_vin) / (delta_i_max * fsw)
        else:
            l_out = 10e-6

        return {
            "L_uH": l_out * 1e6,
            "turns_ratios": [],  # no transformer
            "n_windings": 1,
            "duty_nom": d_nom,
            "duty_min_vin": d_min_vin,
            "duty_max_vin": d_max_vin,
            "i_rms": iout * math.sqrt(d_nom),
            "pin_nom": pin_nom,
            "pout_nom": pout,
            "vin_nom": vin_nom,
            "vout": vout,
            "fsw_hz": fsw,
        }

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[]."""
        op_list = []
        for i, op in enumerate(converter.get("operatingPoints", [])):
            op_list.append({"excitationsPerWinding": [{"name": "Inductor", "frequency": as_float(op.get("switchingFrequency", 200e3))}]})
        return op_list

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements (no transformer, minimal MAS)."""
        return {
            "topology": "buck",
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

        # Boost: D = 1 - (Vin - Vd) / (Vout - Vd)
        d_nom = 1 - (vin_nom - vd) / (vout - vd)
        d_min_vin = 1 - (vin_min - vd) / (vout - vd)
        d_max_vin = 1 - (vin_max - vd) / (vout - vd)

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
            "i_rms": (pout / vin_nom) * math.sqrt(d_nom),
            "pin_nom": pin_nom,
            "pout_nom": pout,
            "vin_nom": vin_nom,
            "vout": vout,
            "fsw_hz": fsw,
        }

    def build_operating_points(self, converter, design_reqs):
        """Build MAS operatingPoints[]."""
        op_list = []
        for i, op in enumerate(converter.get("operatingPoints", [])):
            op_list.append({"excitationsPerWinding": [{"name": "Inductor", "frequency": as_float(op.get("switchingFrequency", 200e3))}]})
        return op_list

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements (no transformer)."""
        return {
            "topology": "boost",
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
        """Compute Isolated Buck requirements."""
        # Similar to regular buck but with transformer
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

        pout = vout * total_iout
        pin_nom = pout / max(eta, 0.01)

        # Turns ratio for isolation
        d_target = 0.45
        ns_np = (vout + vd) / (vin_min * d_target)
        np_ns = 1.0 / ns_np

        d_nom = (vout + vd) / (vin_nom * ns_np)
        d_min_vin = (vout + vd) / (vin_min * ns_np)
        d_max_vin = (vout + vd) / (vin_max * ns_np)

        d_nom = clamp(d_nom, 0.01, 0.99)
        d_min_vin = clamp(d_min_vin, 0.01, 0.99)
        d_max_vin = clamp(d_max_vin, 0.01, 0.99)

        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        delta_i_max = ripple_frac * vout
        if delta_i_max > 0:
            lout = vout * (1 - d_max_vin) / (delta_i_max * fsw)
        else:
            lout = 10e-6

        i_load_reflected = total_iout * ns_np
        i_mag_ripple_target = 0.10 * i_load_reflected
        if i_mag_ripple_target > 0:
            lm = vin_nom * d_nom / (i_mag_ripple_target * fsw)
        else:
            lm = 100e-6

        i_pri_rms = total_iout * ns_np * math.sqrt(d_nom)
        i_sec_rms = [io * math.sqrt(d_nom) for io in as_list(iout_list)]

        turns_ratios = [np_ns] * n_outputs

        return {
            "Lm_uH": lm * 1e6,
            "Lout_uH": lout * 1e6,
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
            "np_ns": np_ns,
            "n_windings": 1 + n_outputs,
            "duty_nom": d_nom,
            "duty_min_vin": d_min_vin,
            "duty_max_vin": d_max_vin,
            "i_pri_rms": i_pri_rms,
            "i_sec_rms": i_sec_rms,
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
            op_list.append({"excitationsPerWinding": exc_per_winding})
        return op_list

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "isolated-buck",
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
        """Compute Isolated Buck-Boost requirements."""
        # Similar to isolated buck
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

        pout = vout * total_iout
        pin_nom = pout / max(eta, 0.01)

        d_target = 0.45
        ns_np = (vout + vd) / (vin_min * d_target)
        np_ns = 1.0 / ns_np

        d_nom = (vout + vd) / (vin_nom * ns_np)
        d_min_vin = (vout + vd) / (vin_min * ns_np)
        d_max_vin = (vout + vd) / (vin_max * ns_np)

        d_nom = clamp(d_nom, 0.01, 0.99)
        d_min_vin = clamp(d_min_vin, 0.01, 0.99)
        d_max_vin = clamp(d_max_vin, 0.01, 0.99)

        ripple_frac = as_float(c.get("currentRippleRatio", 30)) / 100.0
        delta_i_max = ripple_frac * vout
        if delta_i_max > 0:
            lout = vout * (1 - d_max_vin) / (delta_i_max * fsw)
        else:
            lout = 10e-6

        i_load_reflected = total_iout * ns_np
        i_mag_ripple_target = 0.10 * i_load_reflected
        if i_mag_ripple_target > 0:
            lm = vin_nom * d_nom / (i_mag_ripple_target * fsw)
        else:
            lm = 100e-6

        i_pri_rms = total_iout * ns_np * math.sqrt(d_nom)
        i_sec_rms = [io * math.sqrt(d_nom) for io in as_list(iout_list)]

        turns_ratios = [np_ns] * n_outputs

        return {
            "Lm_uH": lm * 1e6,
            "Lout_uH": lout * 1e6,
            "turns_ratios": turns_ratios,
            "ns_np": ns_np,
            "np_ns": np_ns,
            "n_windings": 1 + n_outputs,
            "duty_nom": d_nom,
            "duty_min_vin": d_min_vin,
            "duty_max_vin": d_max_vin,
            "i_pri_rms": i_pri_rms,
            "i_sec_rms": i_sec_rms,
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
            op_list.append({"excitationsPerWinding": exc_per_winding})
        return op_list

    def build_mas_design_requirements(self, converter, design_reqs):
        """Build MAS designRequirements."""
        return {
            "topology": "isolated-buck-boost",
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

        # Determine number of outputs for isolated topologies
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
