#!/usr/bin/env python3
"""
Steinmetz coefficient fitting from core loss data.

Fits the generalized Steinmetz equation:
    P_v = k * f^alpha * B^beta

where P_v is volumetric power loss, f is frequency, and B is peak flux density.

Uses log-space linear regression:
    log(P_v) = log(k) + alpha*log(f) + beta*log(B)
"""

import math
import numpy as np
from typing import Any


def _validate_core_loss_data(
    data_points: list[tuple[float, float, float]],
) -> list[tuple[float, float, float]]:
    """
    Validate core loss data by checking per-frequency consistency.

    For each frequency, fit log(Pv) = a + beta*log(B). If the local beta
    is inconsistent with the majority, or the curve has too few points,
    exclude it. Also checks that higher frequency gives higher loss at
    matched B values.
    """
    from collections import defaultdict

    # Group by frequency
    freq_groups: dict[float, list[tuple[float, float]]] = defaultdict(list)
    for f, b, p in data_points:
        freq_groups[f].append((b, p))

    # Fit beta for each frequency independently
    freq_betas: dict[float, tuple[float, float]] = {}  # freq -> (beta, r2)
    for freq, points in freq_groups.items():
        if len(points) < 3:
            continue  # need at least 3 points for a reliable line
        log_b = np.log10([p[0] for p in points])
        log_p = np.log10([p[1] for p in points])
        A = np.column_stack([np.ones(len(points)), log_b])
        result, *_ = np.linalg.lstsq(A, log_p, rcond=None)
        local_beta = result[1]
        predicted = A @ result
        ss_res = np.sum((log_p - predicted) ** 2)
        ss_tot = np.sum((log_p - np.mean(log_p)) ** 2)
        r2 = 1.0 - ss_res / ss_tot if ss_tot > 0 else 0.0
        freq_betas[freq] = (local_beta, r2)

    if len(freq_betas) < 1:
        return data_points  # can't validate, return as-is

    # Median beta across frequencies
    betas = [b for b, r2 in freq_betas.values() if r2 > 0.9]
    if not betas:
        betas = [b for b, r2 in freq_betas.values()]
    if not betas:
        return data_points
    median_beta = float(np.median(betas))

    # Keep frequencies with beta within 30% of median and R² > 0.9
    valid_freqs = set()
    for freq, (beta, r2) in freq_betas.items():
        if r2 > 0.9 and abs(beta - median_beta) < median_beta * 0.3:
            valid_freqs.add(freq)

    # If too few valid frequencies, relax criteria
    if len(valid_freqs) < 2 and len(freq_betas) >= 2:
        valid_freqs = {f for f, (b, r2) in freq_betas.items() if r2 > 0.8}

    if not valid_freqs:
        return data_points  # can't filter, return as-is

    filtered = [(f, b, p) for f, b, p in data_points if f in valid_freqs]

    # Cross-frequency alpha consistency check:
    # For each pair of frequencies, compute alpha = delta_log_PL / delta_log_f
    # at a common B value. Reject frequencies that give inconsistent alphas.
    if len(valid_freqs) >= 3:
        freq_curves = {}
        for freq in valid_freqs:
            pts = [(b, p) for f, b, p in filtered if f == freq]
            if len(pts) >= 3:
                log_b = np.array([math.log10(p[0]) for p in pts])
                log_p = np.array([math.log10(p[1]) for p in pts])
                A = np.column_stack([np.ones(len(pts)), log_b])
                res, *_ = np.linalg.lstsq(A, log_p, rcond=None)
                freq_curves[freq] = res  # [intercept, slope]

        if len(freq_curves) >= 2:
            # Compute pairwise alpha at B=100 (log10(100)=2)
            freqs_sorted = sorted(freq_curves.keys())
            alphas = []
            for i in range(len(freqs_sorted)):
                for j in range(i + 1, len(freqs_sorted)):
                    f1, f2 = freqs_sorted[i], freqs_sorted[j]
                    r1, r2_coeff = freq_curves[f1], freq_curves[f2]
                    # PL at B=100mT for each frequency
                    pl1 = r1[0] + r1[1] * 2.0
                    pl2 = r2_coeff[0] + r2_coeff[1] * 2.0
                    alpha_pair = (pl2 - pl1) / math.log10(f2 / f1)
                    alphas.append((f1, f2, alpha_pair))

            if alphas:
                # Use the alpha from the two lowest frequencies as reference.
                # Lower-frequency curves have the best color separation in
                # core loss charts (they're rightmost, most isolated).
                ref_alpha = alphas[0][2]  # lowest pair (already sorted)

                # Keep frequencies consistent with the reference alpha
                consistent_freqs = set()
                for f1, f2, a in alphas:
                    if abs(a - ref_alpha) < max(abs(ref_alpha) * 0.3, 0.2):
                        consistent_freqs.add(f1)
                        consistent_freqs.add(f2)

                if len(consistent_freqs) >= 2:
                    filtered = [(f, b, p) for f, b, p in filtered
                                if f in consistent_freqs]

    return filtered


def fit_steinmetz(
    data_points: list[tuple[float, float, float]],
    validate: bool = True,
) -> dict[str, Any] | None:
    """
    Fit Steinmetz parameters from (f_Hz, B_mT, Pv_kW_m3) data points.

    Args:
        data_points: List of (frequency_Hz, flux_density_mT, power_loss_kW_m3) tuples.
        validate: If True, filter out inconsistent frequency curves first.

    Returns:
        Dict with k, alpha, beta, r_squared, valid_range, or None if insufficient data.
    """
    # Filter out zero/negative values
    valid = [(f, b, p) for f, b, p in data_points if f > 0 and b > 0 and p > 0]

    if validate:
        valid = _validate_core_loss_data(valid)

    if len(valid) < 4:
        return None

    # Count distinct frequencies
    freqs = set(v[0] for v in valid)
    if len(freqs) < 2:
        return None  # need at least 2 frequencies for meaningful alpha

    f_arr = np.array([v[0] for v in valid])
    b_arr = np.array([v[1] for v in valid])
    p_arr = np.array([v[2] for v in valid])

    # Log-space regression: log(Pv) = log(k) + alpha*log(f) + beta*log(B)
    log_f = np.log10(f_arr)
    log_b = np.log10(b_arr)
    log_p = np.log10(p_arr)

    A = np.column_stack([np.ones(len(valid)), log_f, log_b])
    b_vec = log_p

    result, residuals, rank, sv = np.linalg.lstsq(A, b_vec, rcond=None)
    log_k, alpha, beta = result

    k = 10 ** log_k

    # Compute R^2
    ss_res = np.sum((log_p - A @ result) ** 2)
    ss_tot = np.sum((log_p - np.mean(log_p)) ** 2)
    r_squared = 1.0 - ss_res / ss_tot if ss_tot > 0 else 0.0

    # Max point error
    predicted = log_k + alpha * log_f + beta * log_b
    max_err_pct = float(np.max(np.abs(10 ** (log_p - predicted) - 1)) * 100)

    return {
        "equation": "Pv = k * f^alpha * B^beta",
        "k": float(k),
        "alpha": float(alpha),
        "beta": float(beta),
        "r_squared": float(r_squared),
        "max_error_pct": max_err_pct,
        "n_points": len(valid),
        "n_frequencies": len(freqs),
        "frequencies_used_Hz": sorted(freqs),
        "valid_range": {
            "f_Hz": [float(f_arr.min()), float(f_arr.max())],
            "B_mT": [float(b_arr.min()), float(b_arr.max())],
        },
        "units": {"Pv": "kW/m^3", "f": "Hz", "B": "mT"},
    }


# ── Unit conversion helpers ──

def gauss_to_mT(gauss: float) -> float:
    """Convert gauss to millitesla (1 G = 0.1 mT)."""
    return gauss * 0.1


def mW_cm3_to_kW_m3(mw_cm3: float) -> float:
    """Convert mW/cm^3 to kW/m^3 (1 mW/cm^3 = 1 kW/m^3)."""
    return mw_cm3  # they're the same!


def extract_core_loss_data(
    material_record: dict,
    frequency_map: dict[str, float] | None = None,
) -> list[tuple[float, float, float]]:
    """
    Extract (f_Hz, B_mT, Pv_kW_m3) data points from a material record's curves.

    Looks for curve keys matching 'core_loss_vs_B_*' pattern.
    Each curve contains [B_gauss, PL_mW_cm3] samples at a specific frequency.

    Args:
        material_record: Material record dict with 'curves' block.
        frequency_map: Optional mapping from curve suffix (e.g. "10kHz") to Hz.
                       If not provided, parses frequency from the suffix.

    Returns:
        List of (f_Hz, B_mT, Pv_kW_m3) tuples.
    """
    curves = material_record.get("curves", {})
    data_points = []

    for key, curve_block in curves.items():
        if not key.startswith("core_loss_vs_B_"):
            continue

        suffix = key.replace("core_loss_vs_B_", "")
        # Parse frequency from suffix
        if frequency_map and suffix in frequency_map:
            freq_hz = frequency_map[suffix]
        else:
            freq_hz = _parse_frequency_suffix(suffix)

        if freq_hz is None or freq_hz <= 0:
            continue

        samples = curve_block.get("samples", [])
        x_unit = curve_block.get("x_unit", "gauss")
        y_unit = curve_block.get("y_units", ["mW/cm3"])[0] if "y_units" in curve_block else "mW/cm3"

        for sample in samples:
            b_val, pl_val = sample[0], sample[1]
            # Convert to SI
            if "gauss" in x_unit.lower():
                b_mT = gauss_to_mT(b_val)
            elif "mt" in x_unit.lower():
                b_mT = b_val
            else:
                b_mT = b_val  # assume mT

            if "mw" in y_unit.lower() and "cm" in y_unit.lower():
                pv_kw = mW_cm3_to_kW_m3(pl_val)
            elif "kw" in y_unit.lower():
                pv_kw = pl_val
            else:
                pv_kw = pl_val  # assume kW/m^3

            if b_mT > 0 and pv_kw > 0:
                data_points.append((freq_hz, b_mT, pv_kw))

    return data_points


def _parse_frequency_suffix(suffix: str) -> float | None:
    """Parse a frequency string like '10kHz', '2MHz', '500Hz' into Hz."""
    suffix = suffix.strip().lower()
    multipliers = {"hz": 1, "khz": 1e3, "mhz": 1e6, "ghz": 1e9}

    for unit, mult in sorted(multipliers.items(), key=lambda x: -len(x[0])):
        if suffix.endswith(unit):
            try:
                return float(suffix[: -len(unit)]) * mult
            except ValueError:
                return None
    # Try plain number (assume Hz)
    try:
        return float(suffix)
    except ValueError:
        return None


def fit_material_steinmetz(
    material_record: dict,
    frequency_map: dict[str, float] | None = None,
) -> dict[str, Any] | None:
    """
    Fit Steinmetz parameters for a single material.

    Args:
        material_record: Full material record dict.
        frequency_map: Optional curve suffix → Hz mapping.

    Returns:
        Steinmetz fit result dict, or None if fitting failed.
    """
    data = extract_core_loss_data(material_record, frequency_map)
    if len(data) < 4:
        return None
    return fit_steinmetz(data)


def fit_all_materials(
    material_db: dict,
    frequency_maps: dict[str, dict[str, float]] | None = None,
) -> dict[str, dict[str, Any]]:
    """
    Fit Steinmetz parameters for all materials in the database.

    Args:
        material_db: Full material database dict with 'materials' key.
        frequency_maps: Per-material frequency maps (material_id -> {suffix -> Hz}).

    Returns:
        Dict mapping material_id -> steinmetz fit result.
    """
    results = {}
    materials = material_db.get("materials", {})

    for mat_id, record in materials.items():
        freq_map = (frequency_maps or {}).get(mat_id)
        fit = fit_material_steinmetz(record, freq_map)
        if fit is not None:
            results[mat_id] = fit
            status = "OK" if fit["r_squared"] > 0.95 else "WARN"
            print(
                f"  {mat_id}: k={fit['k']:.3e}, alpha={fit['alpha']:.2f}, "
                f"beta={fit['beta']:.2f}, R²={fit['r_squared']:.4f} [{status}]"
            )
        else:
            curves = record.get("curves", {})
            cl_keys = [k for k in curves if k.startswith("core_loss_vs_B")]
            if cl_keys:
                print(f"  {mat_id}: insufficient data ({len(cl_keys)} curves)")

    return results
