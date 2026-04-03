#!/usr/bin/env python3
"""Test CV digitizer accuracy across all Fair-Rite materials.

Uses OCR-based y-axis calibration and CSV-derived x-axis range.
Generates comparison plots for materials that fail accuracy checks,
highlighting regions where input data resolution is insufficient.
"""

import sys, math
import numpy as np
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from adapters.cv_digitize import process_chart_image
from adapters.fair_rite_csv import FAIR_RITE_CATALOG, parse_fair_rite_csv

staging = Path("output/staging/fair_rite")
output = Path("output")
review_dir = output / "review"
review_dir.mkdir(parents=True, exist_ok=True)

ERROR_THRESHOLD = 10  # percent median error


def generate_review_plot(mat_id, mu_i, truth_f, truth_mp, truth_mpp,
                         dig_f, dig_mp, dig_mpp, log_f_pts,
                         mp_point_errors, mpp_point_errors):
    """Generate a comparison plot highlighting high-error regions."""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return None

    fig, axes = plt.subplots(2, 1, figsize=(12, 8), sharex=True)
    fig.suptitle(f"{mat_id}  (mu_i={mu_i})  —  Manual Review Required",
                 fontsize=13, fontweight="bold")

    for ax, label, truth_y, dig_y, point_errors in [
        (axes[0], "mu' (real)", truth_mp, dig_mp, mp_point_errors),
        (axes[1], "mu'' (imaginary)", truth_mpp, dig_mpp, mpp_point_errors),
    ]:
        ax.semilogx(truth_f, truth_y, "k-", linewidth=1.5, label="CSV ground truth", zorder=3)
        ax.semilogx(dig_f, dig_y, "--", color="#2080ff", linewidth=1.5, label="Digitized", zorder=3)

        # Highlight high-error frequency regions
        for lf, err in point_errors:
            f_val = 10 ** lf
            if err > ERROR_THRESHOLD:
                ax.axvspan(f_val * 0.7, f_val * 1.4, alpha=0.15, color="red", zorder=1)

        # Mark individual comparison points with error-coded color
        for lf, err in point_errors:
            f_val = 10 ** lf
            t_val = float(np.interp(lf, np.log10(truth_f), truth_y))
            color = "#22cc44" if err < ERROR_THRESHOLD else "#ff4444"
            ax.plot(f_val, t_val, "o", color=color, markersize=5, zorder=4)

        ax.set_ylabel(label)
        ax.legend(loc="best", fontsize=9)
        ax.grid(True, alpha=0.3)

    axes[1].set_xlabel("Frequency (Hz)")

    # Add data quality note
    fig.text(0.5, 0.01,
             "Red shading = error > 10%.  Source chart resolution may be insufficient in these regions.\n"
             "Review required: approve digitized data or provide higher-resolution source.",
             ha="center", fontsize=9, style="italic", color="#666666")

    plot_path = review_dir / f"{mat_id}_review.png"
    fig.savefig(str(plot_path), dpi=150, bbox_inches="tight")
    plt.close(fig)
    return plot_path


results = []
review_materials = []

for entry in FAIR_RITE_CATALOG:
    code = entry["code"]
    mu_i = entry["mu_i"]
    mat_id = f"FR_{code}"

    csv_path = staging / f"{mat_id}_raw.csv"
    img_path = output / f"{mat_id}_permeability.png"

    if not csv_path.exists() or not img_path.exists():
        continue

    # Ground truth from CSV
    csv_text = csv_path.read_text()
    truth = parse_fair_rite_csv(csv_text)
    if len(truth) < 5:
        continue
    truth_f = np.array([r[0] for r in truth])
    truth_mp = np.array([r[1] for r in truth])
    truth_mpp = np.array([r[2] for r in truth])

    # Compute x_range from CSV data (round to nearest decade)
    f_min_decade = 10 ** math.floor(math.log10(max(truth_f[0], 1)))
    f_max_decade = 10 ** math.ceil(math.log10(max(truth_f[-1], 1)))
    x_range = (f_min_decade, f_max_decade)

    # Digitize with OCR y-axis calibration + mu_i anchor fallback
    result = process_chart_image(
        image_path=str(img_path),
        material_id=mat_id,
        config_name="matplotlib_stacked",
        x_range=x_range,
        mu_i=mu_i,
    )

    samples = result.get("curves", {}).get("complex_perm_vs_f", {}).get("samples", [])
    if not samples:
        results.append((mat_id, mu_i, None, None, "NO DATA", None))
        continue

    dig_f = np.array([s[0] for s in samples])
    dig_mp = np.array([s[1] for s in samples])
    dig_mpp = np.array([s[2] for s in samples])

    # Compare at overlapping frequencies
    f_min = max(truth_f[0], dig_f[0])
    f_max = min(truth_f[-1], dig_f[-1])

    if f_min >= f_max:
        results.append((mat_id, mu_i, None, None, "NO OVERLAP", None))
        continue

    log_f_pts = np.linspace(math.log10(f_min), math.log10(f_max), 20)

    mp_errors = []
    mpp_errors = []
    mp_point_errors = []
    mpp_point_errors = []

    for lf in log_f_pts:
        t_mp = float(np.interp(lf, np.log10(truth_f), truth_mp))
        t_mpp = float(np.interp(lf, np.log10(truth_f), truth_mpp))
        d_mp = float(np.interp(lf, np.log10(dig_f), dig_mp))
        d_mpp = float(np.interp(lf, np.log10(dig_f), dig_mpp))

        if t_mp > 1:
            err = abs(d_mp - t_mp) / t_mp * 100
            mp_errors.append(err)
            mp_point_errors.append((lf, err))
        if t_mpp > 1:
            err = abs(d_mpp - t_mpp) / t_mpp * 100
            mpp_errors.append(err)
            mpp_point_errors.append((lf, err))

    med_mp = float(np.median(mp_errors)) if mp_errors else None
    med_mpp = float(np.median(mpp_errors)) if mpp_errors else None

    ok = med_mp is not None and med_mpp is not None and med_mp < ERROR_THRESHOLD and med_mpp < ERROR_THRESHOLD

    if ok:
        tag = "OK"
        note = None
    else:
        # Diagnose root cause
        y_range = max(truth_mp.max(), truth_mpp.max())
        low_f_mpp = truth_mpp[0] if len(truth_mpp) > 0 else 0
        pixel_resolution = y_range / 450  # approximate value-per-pixel

        if med_mpp is not None and med_mpp >= ERROR_THRESHOLD and low_f_mpp < pixel_resolution * 5:
            tag = "REVIEW"
            note = (f"Source chart resolution insufficient: mu'' values at low frequency "
                    f"({low_f_mpp:.1f}) are below pixel resolution threshold "
                    f"({pixel_resolution * 5:.1f}).  Higher-resolution source data recommended.")
        else:
            tag = "REVIEW"
            note = f"Median error exceeds {ERROR_THRESHOLD}% threshold. Manual review required."

        # Generate review plot
        plot_path = generate_review_plot(
            mat_id, mu_i, truth_f, truth_mp, truth_mpp,
            dig_f, dig_mp, dig_mpp, log_f_pts,
            mp_point_errors, mpp_point_errors,
        )
        if plot_path:
            review_materials.append((mat_id, note, str(plot_path)))

    results.append((mat_id, mu_i, med_mp, med_mpp, tag, note))


# ── Print results ──
header = f"{'Mat':8s}  {'mu_i':>6s}  {'mu_p_err':>8s}  {'mu_pp_err':>9s}  Status"
print(header)
print("-" * len(header))
ok_count = 0
review_count = 0
for mat_id, mu_i, mp_err, mpp_err, tag, note in results:
    mp_s = f"{mp_err:5.1f}%" if mp_err is not None else "  N/A"
    mpp_s = f"{mpp_err:5.1f}%" if mpp_err is not None else "  N/A"
    print(f"{mat_id:8s}  mu_i={mu_i:>5}  mu_p={mp_s}  mu_pp={mpp_s}  [{tag}]")
    if tag == "OK":
        ok_count += 1
    elif tag == "REVIEW":
        review_count += 1

print(f"\n{ok_count}/{len(results)} materials OK (<{ERROR_THRESHOLD}% median error)")
if review_count:
    print(f"{review_count}/{len(results)} materials flagged for REVIEW")

if review_materials:
    print(f"\n--- Materials Requiring Manual Review ---")
    for mat_id, note, plot_path in review_materials:
        print(f"\n  {mat_id}:")
        print(f"    {note}")
        print(f"    Review plot: {plot_path}")
    print(f"\nAction: Inspect review plots in {review_dir}/")
    print("  - Approve: accept digitized data as-is (sufficient for application)")
    print("  - Reject:  provide higher-resolution source chart or tabular data")
