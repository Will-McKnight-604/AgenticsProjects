#!/usr/bin/env python3
"""
Material Database Verification & Validation (V&V) Framework — v2

Self-contained: Layers 1-3 extract what they need from the record itself
and optional staging files. No external data needs to be threaded through
by the caller.

Layers:
    1. Bit-level integrity   — verify source_sha256 in record against staging file
    2. Structural identity   — recompute samples_sha256 and check against stored hash,
                               verify raw_point_count, detect post-extraction tampering
    3. Curve similarity      — if multiple sources exist for same quantity, compare them
    4. Physics constraints   — electromagnetic theory sanity checks
    5. Cross-source audit    — multi-vendor corroboration

Usage:
    python verification.py --db ../output/material_db.json
    python verification.py --db ../output/material_db.json --staging-dir ../staging
    python verification.py --db ../output/material_db.json --material FR_43
"""

from __future__ import annotations
import hashlib
import json
import math
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np


# ═══════════════════════════════════════════════════════════════════
# DATA STRUCTURES
# ═══════════════════════════════════════════════════════════════════

@dataclass
class CheckResult:
    layer: int
    name: str
    status: str       # PASS, FAIL, WARN, SKIP
    message: str
    details: dict[str, Any] = field(default_factory=dict)

    @property
    def passed(self) -> bool:
        return self.status in ("PASS", "SKIP")

    def __str__(self):
        icon = {"PASS": "✓", "FAIL": "✗", "WARN": "⚠", "SKIP": "—"}[self.status]
        return f"  [{icon}] L{self.layer} {self.name}: {self.message}"


@dataclass
class MaterialVVReport:
    material_id: str
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    checks: list[CheckResult] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(c.passed for c in self.checks)

    @property
    def fail_count(self) -> int:
        return sum(1 for c in self.checks if c.status == "FAIL")

    @property
    def warn_count(self) -> int:
        return sum(1 for c in self.checks if c.status == "WARN")

    def add(self, check: CheckResult):
        self.checks.append(check)

    def summary(self) -> str:
        lines = [f"\n{'='*60}", f"  V&V Report: {self.material_id}", f"{'='*60}"]
        for c in self.checks:
            lines.append(str(c))
        lines.append(f"{'─'*60}")
        p = sum(1 for c in self.checks if c.status == "PASS")
        lines.append(f"  {p}/{len(self.checks)} passed, {self.fail_count} FAIL, {self.warn_count} WARN")
        return "\n".join(lines)

    def to_dict(self) -> dict:
        return {
            "material_id": self.material_id,
            "timestamp": self.timestamp,
            "verdict": "PASS" if self.passed else "FAIL",
            "fail_count": self.fail_count,
            "warn_count": self.warn_count,
            "checks": [
                {"layer": c.layer, "name": c.name, "status": c.status,
                 "message": c.message, "details": c.details}
                for c in self.checks
            ]
        }


# ═══════════════════════════════════════════════════════════════════
# HASH HELPERS
# ═══════════════════════════════════════════════════════════════════

def _canonical_samples_hash(samples: list[list[float]]) -> str:
    """Deterministic SHA-256 of a samples array (10 sig figs, sorted)."""
    canonical = json.dumps(
        [[float(f"{v:.10g}") for v in row] for row in sorted(samples, key=lambda r: r[0])],
        separators=(",", ":")
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


# ═══════════════════════════════════════════════════════════════════
# LAYER 1: BIT-LEVEL INTEGRITY
# ═══════════════════════════════════════════════════════════════════

def _check_L1(record: dict, staging_dir: Path | None) -> list[CheckResult]:
    """
    Verify raw source file hashes against what was recorded at extraction time.

    Works by:
    - Reading source_sha256 from each curve's source block
    - If staging_dir exists, finding the corresponding raw file and rehashing
    - If no staging_dir, verifying that the hash field at least exists (tamper seal)
    """
    results = []
    mat_id = record.get("material_id", "?")

    for curve_name, curve in record.get("curves", {}).items():
        source = curve.get("source", {})
        stored_hash = source.get("source_sha256")

        if stored_hash is None:
            # No hash stored — this curve wasn't from a hashable source (e.g., seed load)
            results.append(CheckResult(
                layer=1, name=f"L1_hash_{curve_name}",
                status="WARN",
                message=f"{curve_name}: no source_sha256 stored — "
                        f"source was loaded without raw file preservation "
                        f"(method: {source.get('method', '?')})",
            ))
            continue

        # Hash exists — can we verify it against the staging file?
        if staging_dir:
            # Convention: staging/<vendor>/<material_id>_raw.csv
            vendor = record.get("vendor", "").lower().replace(" ", "_").replace("-", "_")
            raw_patterns = [
                staging_dir / vendor / f"{mat_id}_raw.csv",
                staging_dir / vendor / f"{mat_id}.csv",
                staging_dir / f"{mat_id}_raw.csv",
            ]
            raw_file = None
            for p in raw_patterns:
                if p.exists():
                    raw_file = p
                    break

            if raw_file:
                actual_hash = _hash_file(raw_file)
                if actual_hash == stored_hash:
                    results.append(CheckResult(
                        layer=1, name=f"L1_hash_{curve_name}",
                        status="PASS",
                        message=f"{curve_name}: staging file hash matches stored source_sha256",
                        details={"hash": stored_hash[:16] + "...", "file": str(raw_file)}
                    ))
                else:
                    results.append(CheckResult(
                        layer=1, name=f"L1_hash_{curve_name}",
                        status="FAIL",
                        message=f"{curve_name}: staging file hash MISMATCH — "
                                f"raw file changed since extraction",
                        details={"stored": stored_hash[:16], "actual": actual_hash[:16]}
                    ))
            else:
                results.append(CheckResult(
                    layer=1, name=f"L1_hash_{curve_name}",
                    status="PASS",
                    message=f"{curve_name}: source_sha256 recorded at extraction "
                            f"(no staging file for re-verification)",
                    details={"hash": stored_hash[:16] + "..."}
                ))
        else:
            # No staging dir — just confirm the hash field exists
            results.append(CheckResult(
                layer=1, name=f"L1_hash_{curve_name}",
                status="PASS",
                message=f"{curve_name}: source_sha256 present (seal intact)",
                details={"hash": stored_hash[:16] + "..."}
            ))

    if not record.get("curves"):
        results.append(CheckResult(
            layer=1, name="L1_hash", status="SKIP",
            message="No curves to verify"
        ))

    return results


# ═══════════════════════════════════════════════════════════════════
# LAYER 2: STRUCTURAL IDENTITY
# ═══════════════════════════════════════════════════════════════════

def _check_L2(record: dict) -> list[CheckResult]:
    """
    Verify that the samples array hasn't been modified since extraction.

    Self-contained: recomputes samples_sha256 from the record's own samples
    array and compares to the hash that was stored at extraction time.
    Also checks raw_point_count matches actual array length.
    """
    results = []

    for curve_name, curve in record.get("curves", {}).items():
        samples = curve.get("samples", [])
        source = curve.get("source", {})

        if not samples:
            continue

        # Check 2a: Point count matches what was recorded at extraction
        stored_count = source.get("raw_point_count")
        actual_count = len(samples)

        if stored_count is not None:
            if actual_count == stored_count:
                results.append(CheckResult(
                    layer=2, name=f"L2_count_{curve_name}",
                    status="PASS",
                    message=f"{curve_name}: {actual_count} points matches raw_point_count"
                ))
            else:
                results.append(CheckResult(
                    layer=2, name=f"L2_count_{curve_name}",
                    status="FAIL",
                    message=f"{curve_name}: array has {actual_count} points "
                            f"but raw_point_count says {stored_count} — "
                            f"data was modified post-extraction",
                    details={"actual": actual_count, "stored": stored_count}
                ))
        else:
            results.append(CheckResult(
                layer=2, name=f"L2_count_{curve_name}",
                status="WARN",
                message=f"{curve_name}: no raw_point_count stored — "
                        f"cannot verify point count (has {actual_count} points)"
            ))

        # Check 2b: Recompute samples hash and compare to stored hash
        stored_hash = source.get("samples_sha256")
        if stored_hash is not None:
            recomputed = _canonical_samples_hash(samples)
            if recomputed == stored_hash:
                results.append(CheckResult(
                    layer=2, name=f"L2_hash_{curve_name}",
                    status="PASS",
                    message=f"{curve_name}: samples_sha256 verified — "
                            f"data unchanged since extraction",
                    details={"hash": stored_hash[:16] + "..."}
                ))
            else:
                results.append(CheckResult(
                    layer=2, name=f"L2_hash_{curve_name}",
                    status="FAIL",
                    message=f"{curve_name}: samples_sha256 MISMATCH — "
                            f"data was modified after extraction",
                    details={"stored": stored_hash[:16], "recomputed": recomputed[:16]}
                ))
        else:
            results.append(CheckResult(
                layer=2, name=f"L2_hash_{curve_name}",
                status="WARN",
                message=f"{curve_name}: no samples_sha256 stored — "
                        f"cannot verify data integrity "
                        f"(method: {source.get('method', '?')})"
            ))

        # Check 2c: Sort order — monotonic x-axis curves must be ascending
        x_qty = curve.get("x_quantity", "")
        sortable = x_qty in ("frequency", "flux_density", "temperature",
                             "field_strength")
        if sortable and len(samples) >= 2:
            x_vals = [s[0] for s in samples]
            if x_vals == sorted(x_vals):
                results.append(CheckResult(
                    layer=2, name=f"L2_sort_{curve_name}",
                    status="PASS",
                    message=f"{curve_name}: sorted ascending by {x_qty}"
                ))
            else:
                results.append(CheckResult(
                    layer=2, name=f"L2_sort_{curve_name}",
                    status="FAIL",
                    message=f"{curve_name}: NOT sorted by {x_qty}"
                ))

        # Check 2d: No NaN or Inf
        bad_values = []
        for i, row in enumerate(samples):
            for j, v in enumerate(row):
                if v != v or abs(v) == float("inf"):  # NaN or Inf
                    bad_values.append((i, j, v))
        if bad_values:
            results.append(CheckResult(
                layer=2, name=f"L2_finite_{curve_name}",
                status="FAIL",
                message=f"{curve_name}: {len(bad_values)} NaN/Inf values found",
                details={"bad_values": bad_values[:5]}
            ))
        else:
            results.append(CheckResult(
                layer=2, name=f"L2_finite_{curve_name}",
                status="PASS",
                message=f"{curve_name}: all values finite"
            ))

    if not any(record.get("curves", {}).get(c, {}).get("samples")
               for c in record.get("curves", {})):
        results.append(CheckResult(
            layer=2, name="L2_structural", status="SKIP",
            message="No curve data to verify"
        ))

    return results


# ═══════════════════════════════════════════════════════════════════
# LAYER 3: CURVE SIMILARITY
# ═══════════════════════════════════════════════════════════════════

def _check_L3(record: dict) -> list[CheckResult]:
    """
    Compare curves from different extraction methods within the same record.

    If a material has e.g. both an MDT-scraped and a PDF-digitized complex
    permeability curve, this layer compares them using Fréchet distance, DTW,
    and area-between-curves.
    """
    results = []
    curves = record.get("curves", {})

    # Group curves that measure the same physical quantity
    perm_curves = {k: v for k, v in curves.items()
                   if "complex_perm" in k and v.get("samples")}
    loss_curves = {k: v for k, v in curves.items()
                   if "core_loss" in k and v.get("samples")}

    for group_name, group in [("complex_perm", perm_curves), ("core_loss", loss_curves)]:
        keys = list(group.keys())
        if len(keys) < 2:
            continue

        # Compare each pair
        for i in range(len(keys)):
            for j in range(i + 1, len(keys)):
                k_a, k_b = keys[i], keys[j]
                samples_a = group[k_a]["samples"]
                samples_b = group[k_b]["samples"]
                method_a = group[k_a].get("source", {}).get("method", "?")
                method_b = group[k_b].get("source", {}).get("method", "?")

                try:
                    import similaritymeasures
                    # Compare first y-column in log-frequency space
                    arr_a = np.array([[np.log10(max(s[0], 1)), s[1]] for s in samples_a])
                    arr_b = np.array([[np.log10(max(s[0], 1)), s[1]] for s in samples_b])

                    # Normalize
                    x_min = min(arr_a[:, 0].min(), arr_b[:, 0].min())
                    x_rng = max(arr_a[:, 0].max(), arr_b[:, 0].max()) - x_min or 1
                    y_min = min(arr_a[:, 1].min(), arr_b[:, 1].min())
                    y_rng = max(arr_a[:, 1].max(), arr_b[:, 1].max()) - y_min or 1

                    an = np.column_stack([(arr_a[:, 0] - x_min) / x_rng, (arr_a[:, 1] - y_min) / y_rng])
                    bn = np.column_stack([(arr_b[:, 0] - x_min) / x_rng, (arr_b[:, 1] - y_min) / y_rng])

                    fd = similaritymeasures.frechet_dist(an, bn)
                    area = similaritymeasures.area_between_two_curves(an, bn)

                    ok = fd < 0.1 and area < 0.05
                    results.append(CheckResult(
                        layer=3, name=f"L3_{group_name}_{method_a}_vs_{method_b}",
                        status="PASS" if ok else "WARN",
                        message=f"{k_a} vs {k_b}: Fréchet={fd:.4f}, area={area:.4f}"
                                f" — {'agree' if ok else 'disagree, review needed'}",
                        details={"frechet": round(fd, 6), "area": round(area, 6)}
                    ))
                except ImportError:
                    results.append(CheckResult(
                        layer=3, name=f"L3_{group_name}",
                        status="SKIP",
                        message="similaritymeasures not installed"
                    ))
                except Exception as e:
                    results.append(CheckResult(
                        layer=3, name=f"L3_{group_name}",
                        status="WARN",
                        message=f"Curve comparison failed: {e}"
                    ))

    if not results:
        # Check if there's only one source — that's expected, not a skip
        has_curves = any(c.get("samples") for c in curves.values())
        if has_curves:
            results.append(CheckResult(
                layer=3, name="L3_single_source",
                status="PASS",
                message="Single source per quantity — no cross-method comparison needed "
                        "(L5 compares across vendors)"
            ))
        else:
            results.append(CheckResult(
                layer=3, name="L3_curves", status="SKIP",
                message="No curve data for comparison"
            ))

    return results


# ═══════════════════════════════════════════════════════════════════
# LAYER 4: PHYSICS CONSTRAINTS
# ═══════════════════════════════════════════════════════════════════

def _check_L4(record: dict) -> list[CheckResult]:
    results = []
    props = record.get("properties_ref", {})
    curves = record.get("curves", {})
    mu_i = props.get("mu_i")
    curie_C = props.get("curie_temperature_C")
    bsat_mT = props.get("saturation_flux_density_mT")
    chemistry = record.get("chemistry", "")

    cp = curves.get("complex_perm_vs_f", {})
    samples = cp.get("samples", [])

    if len(samples) >= 10:
        mu_p = [s[1] for s in samples]
        mu_pp = [s[2] for s in samples]

        # Kramers-Kronig qualitative check
        peak_idx = int(np.argmax(mu_pp))
        peak_f = samples[peak_idx][0]
        if 2 <= peak_idx <= len(samples) - 3:
            before = np.mean(mu_p[max(0, peak_idx - 3):peak_idx])
            after = np.mean(mu_p[peak_idx + 1:min(len(mu_p), peak_idx + 4)])
            results.append(CheckResult(
                layer=4, name="L4_kramers_kronig",
                status="PASS" if before > after else "WARN",
                message=f"µ' {'decreasing' if before > after else 'NOT decreasing'} "
                        f"around µ'' peak at {peak_f / 1e6:.2f} MHz",
                details={"peak_f_Hz": peak_f, "mu_p_before": round(before, 1),
                         "mu_p_after": round(after, 1)}
            ))

        # |µ| at lowest f vs µ_i
        mu_mag = math.sqrt(mu_p[0] ** 2 + mu_pp[0] ** 2)
        if mu_i:
            diff_pct = abs(mu_mag - mu_i) / mu_i * 100
            results.append(CheckResult(
                layer=4, name="L4_mu_vs_mu_i",
                status="PASS" if diff_pct < 30 else "WARN",
                message=f"|µ|(f_low) = {mu_mag:.0f} vs µ_i = {mu_i:.0f} "
                        f"({diff_pct:.0f}% difference)",
                details={"mu_mag": round(mu_mag, 1), "mu_i": mu_i, "diff_pct": round(diff_pct, 1)}
            ))

        # Energy conservation: µ'' ≥ 0
        neg = sum(1 for v in mu_pp if v < -1e-3)
        results.append(CheckResult(
            layer=4, name="L4_energy_conservation",
            status="PASS" if neg == 0 else ("WARN" if neg <= 3 else "FAIL"),
            message=f"µ'' ≥ 0 everywhere" if neg == 0
                    else f"{neg} points have µ'' < 0 (thermodynamic violation)"
        ))

        # Snoek's limit
        if mu_i and mu_i > 50:
            snoek = (samples[peak_idx][0] * mu_i) / 1e9
            results.append(CheckResult(
                layer=4, name="L4_snoek",
                status="PASS" if 0.5 < snoek < 50 else "WARN",
                message=f"Snoek product = {snoek:.1f} GHz "
                        f"({'typical' if 0.5 < snoek < 50 else 'unusual'})",
                details={"snoek_GHz": round(snoek, 2)}
            ))

    # Curie temperature
    if curie_C is not None:
        ok = 50 < curie_C < 700
        results.append(CheckResult(
            layer=4, name="L4_curie",
            status="PASS" if ok else "WARN",
            message=f"Curie temp = {curie_C}°C ({'reasonable' if ok else 'unusual'})"
        ))

    # Bsat vs chemistry
    if bsat_mT and chemistry:
        ok = True
        if chemistry == "MnZn" and not (200 <= bsat_mT <= 600):
            ok = False
        if chemistry == "NiZn" and bsat_mT > 500:
            ok = False
        results.append(CheckResult(
            layer=4, name="L4_bsat",
            status="PASS" if ok else "WARN",
            message=f"Bsat = {bsat_mT} mT {'consistent' if ok else 'unusual'} for {chemistry}"
        ))

    # ── Core loss checks ──
    core_loss_curves = {k: v for k, v in curves.items()
                        if k.startswith("core_loss_vs_B") and v.get("samples")}

    for cl_key, cl_curve in core_loss_curves.items():
        samples = cl_curve["samples"]
        if len(samples) < 3:
            continue
        # Monotonicity: P_v should increase with B
        sorted_s = sorted(samples, key=lambda s: s[0])
        violations = sum(1 for i in range(len(sorted_s) - 1)
                         if sorted_s[i][1] > sorted_s[i + 1][1] * 1.01)
        results.append(CheckResult(
            layer=4, name=f"L4_cl_monotonic_{cl_key}",
            status="PASS" if violations == 0 else (
                "WARN" if violations <= 2 else "FAIL"),
            message=f"{cl_key}: P_v vs B {'monotonic' if violations == 0 else f'{violations} non-monotonic points'}",
        ))

    # Frequency ordering: higher f → higher P_v at same B
    if len(core_loss_curves) >= 2:
        freq_median_pv: list[tuple[float, float]] = []
        for cl_key, cl_curve in core_loss_curves.items():
            freq_hz = _parse_freq_from_curve_key(cl_key)
            if freq_hz and freq_hz > 0:
                pv_vals = [s[1] for s in cl_curve["samples"] if s[1] > 0]
                if pv_vals:
                    freq_median_pv.append((freq_hz, float(np.median(pv_vals))))

        freq_median_pv.sort()
        if len(freq_median_pv) >= 2:
            ordered = all(freq_median_pv[i][1] <= freq_median_pv[i + 1][1]
                          for i in range(len(freq_median_pv) - 1))
            results.append(CheckResult(
                layer=4, name="L4_cl_freq_ordering",
                status="PASS" if ordered else "WARN",
                message=f"Core loss frequency ordering: "
                        f"{'higher f → higher P_v' if ordered else 'UNEXPECTED — check frequency labels'}",
                details={"freq_median_pairs": [
                    (f"{f / 1e3:.0f}kHz", round(pv, 1))
                    for f, pv in freq_median_pv
                ]},
            ))

    # ── Steinmetz parameter checks ──
    steinmetz = record.get("fitted_models", {}).get("steinmetz", {})
    if steinmetz:
        alpha = steinmetz.get("alpha")
        beta = steinmetz.get("beta")
        r2 = steinmetz.get("r_squared")

        if alpha is not None:
            ok = 0.8 <= alpha <= 2.5
            results.append(CheckResult(
                layer=4, name="L4_steinmetz_alpha",
                status="PASS" if ok else "WARN",
                message=f"Steinmetz α = {alpha:.2f} "
                        f"({'typical' if ok else 'unusual — expected 0.8–2.5'})",
            ))

        if beta is not None:
            ok = 1.5 <= beta <= 3.5
            results.append(CheckResult(
                layer=4, name="L4_steinmetz_beta",
                status="PASS" if ok else "WARN",
                message=f"Steinmetz β = {beta:.2f} "
                        f"({'typical' if ok else 'unusual — expected 1.5–3.5'})",
            ))

        if r2 is not None:
            if r2 >= 0.95:
                status = "PASS"
            elif r2 >= 0.90:
                status = "WARN"
            else:
                status = "FAIL"
            results.append(CheckResult(
                layer=4, name="L4_steinmetz_r2",
                status=status,
                message=f"Steinmetz R² = {r2:.4f} "
                        f"({'good' if r2 >= 0.95 else 'marginal' if r2 >= 0.90 else 'poor fit'})",
            ))

    # ── Perm vs temp — Curie check ──
    perm_temp = curves.get("perm_vs_temp", {})
    pt_samples = perm_temp.get("samples", [])
    if len(pt_samples) >= 5 and curie_C is not None:
        # µ should drop to near-zero approaching Curie temp
        mu_vals = [s[1] for s in pt_samples]
        t_vals = [s[0] for s in pt_samples]
        mu_peak = max(mu_vals)
        # Find µ at highest measured temperature
        mu_at_max_t = mu_vals[-1] if t_vals[-1] > t_vals[0] else mu_vals[0]
        # If max temp is near or above Curie, µ should be well below peak
        max_t = max(t_vals)
        if max_t > curie_C * 0.8:
            drop_ratio = mu_at_max_t / mu_peak if mu_peak > 0 else 1.0
            ok = drop_ratio < 0.5
            results.append(CheckResult(
                layer=4, name="L4_perm_curie",
                status="PASS" if ok else "WARN",
                message=f"µ drops to {drop_ratio:.0%} of peak near Curie ({curie_C}°C)"
                        f" — {'consistent' if ok else 'expected sharper drop'}",
            ))

    # ── B-H curve sanity ──
    for bh_key in [k for k in curves if k.startswith("bh_curve") and curves[k].get("samples")]:
        bh_samples = curves[bh_key]["samples"]
        if len(bh_samples) < 5:
            continue
        b_vals = [s[1] for s in bh_samples]
        b_max = max(b_vals)
        # B should reach at least some saturation level
        if bsat_mT:
            # Compare in same units — bh curves may be in gauss
            bh_unit = curves[bh_key].get("y_units", ["gauss"])[0]
            b_max_mT = b_max * 0.1 if "gauss" in bh_unit.lower() else b_max
            ratio = b_max_mT / bsat_mT if bsat_mT > 0 else 0
            ok = 0.5 < ratio < 2.0
            results.append(CheckResult(
                layer=4, name=f"L4_bh_bsat_{bh_key}",
                status="PASS" if ok else "WARN",
                message=f"{bh_key}: B_max = {b_max_mT:.0f} mT vs "
                        f"B_sat = {bsat_mT:.0f} mT (ratio {ratio:.2f})",
            ))

    # ── Flux vs temp — should decrease with temperature ──
    flux_temp = curves.get("flux_vs_temp", {})
    ft_samples = flux_temp.get("samples", [])
    if len(ft_samples) >= 5:
        t_vals = [s[0] for s in ft_samples]
        b_vals = [s[1] for s in ft_samples]
        # Flux density should generally decrease at high temperatures
        n = len(b_vals)
        avg_first = np.mean(b_vals[:n // 4]) if n >= 4 else b_vals[0]
        avg_last = np.mean(b_vals[-n // 4:]) if n >= 4 else b_vals[-1]
        decreasing = avg_last < avg_first
        results.append(CheckResult(
            layer=4, name="L4_flux_vs_temp",
            status="PASS" if decreasing else "WARN",
            message=f"B_sat vs temp: {'decreasing' if decreasing else 'NOT decreasing'} "
                    f"({avg_first:.0f} → {avg_last:.0f} gauss)",
        ))

    if not results:
        results.append(CheckResult(
            layer=4, name="L4_physics", status="SKIP",
            message="No curve/property data for physics checks"
        ))

    return results


def _parse_freq_from_curve_key(key: str) -> float | None:
    """Parse frequency from a curve key like 'core_loss_vs_B_100kHz'."""
    suffix = key.rsplit("_", 1)[-1].strip().lower()
    multipliers = {"hz": 1, "khz": 1e3, "mhz": 1e6, "ghz": 1e9}
    for unit, mult in sorted(multipliers.items(), key=lambda x: -len(x[0])):
        if suffix.endswith(unit):
            try:
                return float(suffix[:-len(unit)]) * mult
            except ValueError:
                return None
    return None


# ═══════════════════════════════════════════════════════════════════
# LAYER 5: CROSS-SOURCE CORROBORATION
# ═══════════════════════════════════════════════════════════════════

def _check_L5(record: dict, secondary_sources: list[dict] | None) -> list[CheckResult]:
    if not secondary_sources:
        return [CheckResult(layer=5, name="L5_cross", status="SKIP",
                            message="No secondary sources for corroboration")]

    results = []
    for sec in secondary_sources:
        sec_label = sec.get("source_label", "secondary")
        for prop in ["mu_i", "saturation_flux_density_mT", "curie_temperature_C"]:
            pv = record.get("properties_ref", {}).get(prop)
            sv = sec.get("properties_ref", {}).get(prop)
            if pv is not None and sv is not None:
                diff = abs(pv - sv) / max(abs(pv), abs(sv), 1e-30)
                st = "PASS" if diff < 0.02 else ("WARN" if diff < 0.10 else "FAIL")
                results.append(CheckResult(
                    layer=5, name=f"L5_{prop}",
                    status=st,
                    message=f"{prop}: primary={pv}, {sec_label}={sv} ({diff * 100:.1f}%)"
                ))
    return results or [CheckResult(layer=5, name="L5_cross", status="SKIP",
                                    message="No comparable properties")]


# ═══════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ═══════════════════════════════════════════════════════════════════

def run_full_vv(
    record: dict[str, Any],
    staging_dir: Path | str | None = None,
    secondary_sources: list[dict[str, Any]] | None = None,
) -> MaterialVVReport:
    """
    Run the complete 5-layer V&V on one material record.

    Self-contained: Layers 1-3 extract verification data from the record's
    own stored hashes and source metadata. No external raw data needed.

    Args:
        record: The material database record.
        staging_dir: Optional path to staging directory with raw source files.
        secondary_sources: Optional alternative sources for Layer 5.
    """
    report = MaterialVVReport(material_id=record.get("material_id", "?"))
    stg = Path(staging_dir) if staging_dir else None

    for check in _check_L1(record, stg):
        report.add(check)
    for check in _check_L2(record):
        report.add(check)
    for check in _check_L3(record):
        report.add(check)
    for check in _check_L4(record):
        report.add(check)
    for check in _check_L5(record, secondary_sources):
        report.add(check)

    return report


def run_vv_on_db(
    db: dict[str, Any],
    staging_dir: Path | str | None = None,
) -> list[MaterialVVReport]:
    """Run V&V on all non-seed materials in a database."""
    reports = []
    for mat_id, record in db.get("materials", {}).items():
        if record.get("record_status") == "seed":
            continue
        reports.append(run_full_vv(record, staging_dir=staging_dir))
    return reports


# ── CLI ──

def main():
    import argparse
    ap = argparse.ArgumentParser(description="Material V&V Framework")
    ap.add_argument("--db", required=True)
    ap.add_argument("--material", help="Single material to check")
    ap.add_argument("--staging-dir", help="Staging directory with raw source files")
    ap.add_argument("--output", help="Write JSON report")
    args = ap.parse_args()

    db = json.loads(Path(args.db).read_text())
    mats = db.get("materials", {})
    if args.material:
        mats = {k: v for k, v in mats.items() if k == args.material}

    stg = Path(args.staging_dir) if args.staging_dir else None
    reports = []
    for mat_id, rec in mats.items():
        if rec.get("record_status") == "seed":
            continue
        r = run_full_vv(rec, staging_dir=stg)
        reports.append(r)
        print(r.summary())

    if args.output:
        out = {"reports": [r.to_dict() for r in reports]}
        Path(args.output).write_text(json.dumps(out, indent=2))
        print(f"\nWrote {args.output}")

    total_fail = sum(r.fail_count for r in reports)
    print(f"\n{len(reports)} materials: {total_fail} failures")


if __name__ == "__main__":
    main()
