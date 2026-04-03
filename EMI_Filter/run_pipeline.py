#!/usr/bin/env python3
"""
Material database pipeline orchestrator with integrated V&V.

Flow: adapters → V&V per-vendor → merge → JS generation → final V&V → report

Usage:
    python run_pipeline.py \
        --seed-db /path/to/emi_material_db_seed.json \
        --tdk-seed /path/to/tdk_material_catalog_seed.json \
        --vv-report output/vv_report.json

    python run_pipeline.py --network       # download fresh CSVs
    python run_pipeline.py --mdt           # TDK MDT Playwright scrape
    python run_pipeline.py --validate-only output/material_db.json
"""

from __future__ import annotations
import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from adapters.fair_rite_csv import run_adapter as run_fair_rite
from adapters.tdk_catalog_seed import run_adapter as run_tdk_seed
from processing.merge_and_generate import merge_vendor_databases, generate_js_module
from processing.verification import run_vv_on_db, run_full_vv, MaterialVVReport


def print_vv(reports: list[MaterialVVReport]):
    """Print compact V&V results."""
    for r in reports:
        issues = [c for c in r.checks if c.status in ("FAIL", "WARN")]
        if issues:
            icon = "✗" if r.fail_count > 0 else "⚠"
            print(f"│   {icon} {r.material_id}")
            for c in issues:
                print(f"│       L{c.layer} {c.status}: {c.message}")
    clean = sum(1 for r in reports if not r.fail_count and not r.warn_count)
    if clean:
        print(f"│   ✓ {clean} material(s) fully clean")
    tf = sum(r.fail_count for r in reports)
    tw = sum(r.warn_count for r in reports)
    tp = sum(1 for r in reports for c in r.checks if c.status == "PASS")
    print(f"│   Totals: {tp} pass, {tw} warn, {tf} fail across {len(reports)} record(s)")


def main():
    # Ensure Unicode output works on Windows
    import os
    if os.name == 'nt':
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')

    ap = argparse.ArgumentParser(description="Material database pipeline + V&V")
    ap.add_argument("--network", action="store_true",
                    help="Download data from vendor websites")
    ap.add_argument("--fair-rite-only", action="store_true")
    ap.add_argument("--tdk-only", action="store_true")
    ap.add_argument("--mdt", action="store_true",
                    help="Run TDK MDT Playwright scraper (requires network)")
    ap.add_argument("--emi-only", action="store_true")
    ap.add_argument("--scrape-charts", action="store_true",
                    help="Scrape and digitize chart images from Fair-Rite")
    ap.add_argument("--skip-charts", action="store_true",
                    help="Skip chart digitization (CSV-only mode)")
    ap.add_argument("--steinmetz", action="store_true",
                    help="Fit Steinmetz coefficients from core loss data")
    ap.add_argument("--seed-db", default=None,
                    help="Path to emi_material_db_seed.json")
    ap.add_argument("--tdk-seed", default=None,
                    help="Path to tdk_material_catalog_seed.json")
    ap.add_argument("--output-dir", default="output",
                    help="Output directory (relative to pipeline root)")
    ap.add_argument("--validate-only", metavar="FILE",
                    help="Just run V&V on an existing database")
    ap.add_argument("--vv-report", metavar="FILE",
                    help="Save full V&V report as JSON")
    ap.add_argument("--skip-vv", action="store_true")
    args = ap.parse_args()

    base = Path(__file__).parent
    output_dir = base / args.output_dir
    vendor_dir = output_dir / "vendor"
    staging_dir = base / "staging"
    vendor_dir.mkdir(parents=True, exist_ok=True)
    staging_dir.mkdir(parents=True, exist_ok=True)

    # ── Validate-only mode ──
    if args.validate_only:
        db = json.loads(Path(args.validate_only).read_text())
        reports = run_vv_on_db(db, staging_dir=staging_dir)
        for r in reports:
            print(r.summary())
        tf = sum(r.fail_count for r in reports)
        sys.exit(1 if tf else 0)

    all_vv: list[MaterialVVReport] = []

    print("╔══════════════════════════════════════════════════╗")
    print("║  Material Database Pipeline + V&V               ║")
    print("╚══════════════════════════════════════════════════╝")

    # ═══════════════════════════════════════════════════════════
    # STEP 1: EXTRACTION
    # ═══════════════════════════════════════════════════════════
    print("\n┌─ Step 1: Extraction ─────────────────────────────")

    if not args.tdk_only:
        print("│\n│ Fair-Rite CSV adapter\n│ " + "─" * 40)
        run_fair_rite(
            seed_path=args.seed_db,
            output_path=str(vendor_dir / "fair_rite.json"),
            use_network=args.network,
            scrape_charts=args.scrape_charts,
        )

    if not args.fair_rite_only and args.tdk_seed and Path(args.tdk_seed).exists():
        print("│\n│ TDK catalog seed adapter\n│ " + "─" * 40)
        run_tdk_seed(
            input_path=args.tdk_seed,
            output_path=str(vendor_dir / "tdk.json"),
            emi_only=args.emi_only,
        )

    if args.mdt and not args.fair_rite_only:
        try:
            from adapters.tdk_mdt import run_adapter as run_mdt
            print("│\n│ TDK MDT scraper\n│ " + "─" * 40)
            existing = str(vendor_dir / "tdk.json") if (vendor_dir / "tdk.json").exists() else None
            run_mdt(
                existing_db_path=existing,
                output_path=str(vendor_dir / "tdk_mdt.json"),
                emi_only=True,
            )
        except Exception as e:
            print(f"│   MDT scraper failed: {e}")

    # ═══════════════════════════════════════════════════════════
    # STEP 1b: CHART DIGITIZATION
    # ═══════════════════════════════════════════════════════════
    fr_json = vendor_dir / "fair_rite.json"
    chart_staging = output_dir / "staging" / "fair_rite"

    if not args.skip_charts and not args.tdk_only and fr_json.exists() and chart_staging.exists():
        print("\n┌─ Step 1b: Chart Digitization ─────────────────────")
        try:
            from adapters.cv_digitize import process_chart_image, CHART_CONFIGS
            import glob

            def _is_grayscale(img_path: str) -> bool:
                """Check if image is grayscale (no chromatic content)."""
                import cv2 as _cv2
                img = _cv2.imread(img_path)
                if img is None:
                    return False
                hsv = _cv2.cvtColor(img, _cv2.COLOR_BGR2HSV)
                return float(hsv[:, :, 1].mean()) < 10

            fr_db = json.loads(fr_json.read_text())
            fr_materials = fr_db.get("materials", {})
            chart_count = 0
            curve_count = 0

            for mat_id in fr_materials:
                # Find chart images for this material
                chart_types = {
                    "perm_vs_temp": "perm_vs_temp",
                    "flux_vs_temp": "flux_vs_temp",
                    "core_loss_25C": "core_loss_colored",
                    "core_loss_100C": "core_loss_colored",
                    "core_loss_140C": "core_loss_colored",
                    "core_loss_vs_temp": "core_loss_vs_temp",
                    "bh_curve": "bh_curve",
                    "perm_vs_B": "perm_vs_B",
                    "perm_vs_H": "perm_vs_H",
                    "impedance_vs_H": "impedance_vs_H",
                    "impedance_vs_temp": "impedance_vs_temp",
                }
                for suffix, config_name in chart_types.items():
                    for ext in ("jpg", "png"):
                        img_path = chart_staging / f"{mat_id}_{suffix}.{ext}"
                        if img_path.exists():
                            # Fall back to black config for grayscale core loss
                            actual_config = config_name
                            if config_name == "core_loss_colored" and _is_grayscale(str(img_path)):
                                actual_config = "core_loss_black"

                            mu_i = fr_materials[mat_id].get("mu_i")
                            print(f"│   {mat_id} {suffix} ...", end=" ", flush=True)
                            try:
                                result = process_chart_image(
                                    image_path=str(img_path),
                                    material_id=mat_id,
                                    config_name=actual_config,
                                    mu_i=mu_i,
                                )
                            except Exception as e:
                                print(f"ERROR: {e}")
                                break
                            new_curves = result.get("curves", {})
                            nc = len(new_curves)
                            print(f"{nc} curve{'s' if nc != 1 else ''}")
                            if new_curves:
                                if "curves" not in fr_materials[mat_id]:
                                    fr_materials[mat_id]["curves"] = {}
                                fr_materials[mat_id]["curves"].update(new_curves)
                                curve_count += len(new_curves)
                                chart_count += 1
                            break  # found this suffix

            if chart_count:
                # Write updated database
                fr_json.write_text(json.dumps(fr_db, indent=2))
                print(f"│   Digitized {chart_count} charts, {curve_count} new curves")
            else:
                print("│   No chart images found in staging")
        except ImportError as e:
            print(f"│   Chart digitization skipped (missing dependency: {e})")

    # ═══════════════════════════════════════════════════════════
    # STEP 1c: STEINMETZ FITTING
    # ═══════════════════════════════════════════════════════════
    if args.steinmetz and not args.tdk_only and fr_json.exists():
        print("\n┌─ Step 1c: Steinmetz Coefficient Fitting ──────────")
        try:
            from processing.steinmetz_fit import fit_material_steinmetz

            fr_db = json.loads(fr_json.read_text())
            fr_materials = fr_db.get("materials", {})
            fit_count = 0

            for mat_id, record in fr_materials.items():
                cl_keys = [k for k in record.get("curves", {})
                           if k.startswith("core_loss_vs_B")]
                if not cl_keys:
                    continue

                fit = fit_material_steinmetz(record)
                if fit:
                    if "fitted_models" not in record:
                        record["fitted_models"] = {}
                    record["fitted_models"]["steinmetz"] = fit
                    fit_count += 1
                    status = "OK" if fit["r_squared"] > 0.95 else "WARN"
                    print(
                        f"│   {mat_id}: k={fit['k']:.2e} "
                        f"α={fit['alpha']:.2f} β={fit['beta']:.2f} "
                        f"R²={fit['r_squared']:.3f} [{status}]"
                    )

            if fit_count:
                fr_json.write_text(json.dumps(fr_db, indent=2))
                print(f"│   Fitted {fit_count} material(s)")
            else:
                print("│   No core loss data available for fitting")
        except Exception as e:
            print(f"│   Steinmetz fitting failed: {e}")

    # ═══════════════════════════════════════════════════════════
    # STEP 2: V&V PER VENDOR
    # ═══════════════════════════════════════════════════════════
    if not args.skip_vv:
        print("\n┌─ Step 2: Verification & Validation ──────────────")
        for fp in sorted(vendor_dir.glob("*.json")):
            vendor_name = fp.stem
            print(f"│\n│ V&V: {vendor_name}\n│ " + "─" * 40)
            db = json.loads(fp.read_text())
            reports = run_vv_on_db(db, staging_dir=staging_dir)
            all_vv.extend(reports)
            print_vv(reports)

    # ═══════════════════════════════════════════════════════════
    # STEP 3: MERGE
    # ═══════════════════════════════════════════════════════════
    print("\n┌─ Step 3: Merge ──────────────────────────────────")
    merged = merge_vendor_databases(str(vendor_dir))
    materials = merged.get("materials", {})

    # ═══════════════════════════════════════════════════════════
    # STEP 4: FINAL V&V ON MERGED DATABASE
    # ═══════════════════════════════════════════════════════════
    if not args.skip_vv:
        print("\n┌─ Step 4: Final V&V on merged database ───────────")
        final = run_vv_on_db(merged, staging_dir=staging_dir)
        all_vv.extend(final)
        print_vv(final)

    # ═══════════════════════════════════════════════════════════
    # STEP 5: APPLY V&V RESULTS TO RECORDS
    # ═══════════════════════════════════════════════════════════
    if not args.skip_vv and final:
        print("\n┌─ Step 5: Apply V&V results to records ───────────")
        vv_timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        promoted = 0
        flagged = 0

        for report in final:
            mat_id = report.material_id
            record = materials.get(mat_id)
            if not record:
                continue

            # Collect FAIL and WARN messages
            issues = [
                f"L{c.layer} {c.status}: {c.message}"
                for c in report.checks if c.status in ("FAIL", "WARN")
            ]

            # Write V&V results into the record
            record["vv_timestamp"] = vv_timestamp
            record["vv_issues"] = issues

            # Auto-promote: complete -> verified when all checks pass clean
            if record.get("record_status") == "complete" and report.fail_count == 0 and report.warn_count == 0:
                record["record_status"] = "verified"
                promoted += 1
            elif issues:
                flagged += 1

        print(f"│   {promoted} material(s) promoted to 'verified'")
        print(f"│   {flagged} material(s) flagged with issues")

    # ═══════════════════════════════════════════════════════════
    # STEP 6: WRITE OUTPUT FILES
    # ═══════════════════════════════════════════════════════════
    print("\n┌─ Step 6: Write output files ─────────────────────")

    # Recount statuses after V&V promotion
    status_counts = {}
    for m in materials.values():
        s = m.get("record_status", "?")
        status_counts[s] = status_counts.get(s, 0) + 1

    json_path = output_dir / "material_db.json"
    json_path.write_text(json.dumps(merged, indent=2))
    js_path = output_dir / "material_db.js"
    generate_js_module(merged, str(js_path))
    print(f"│   JSON: {json_path} ({json_path.stat().st_size / 1024:.1f} KB)")
    print(f"│   JS:   {js_path} ({js_path.stat().st_size / 1024:.1f} KB)")

    # ═══════════════════════════════════════════════════════════
    # WRITE V&V REPORT
    # ═══════════════════════════════════════════════════════════
    if args.vv_report:
        report_data = {
            "generated_utc": datetime.now(timezone.utc).isoformat(),
            "total_materials": len(all_vv),
            "total_pass": sum(1 for r in all_vv for c in r.checks if c.status == "PASS"),
            "total_warn": sum(1 for r in all_vv for c in r.checks if c.status == "WARN"),
            "total_fail": sum(1 for r in all_vv for c in r.checks if c.status == "FAIL"),
            "reports": [r.to_dict() for r in all_vv],
        }
        vvp = Path(args.vv_report)
        vvp.parent.mkdir(parents=True, exist_ok=True)
        vvp.write_text(json.dumps(report_data, indent=2))
        print(f"\n  V&V report -> {vvp} ({vvp.stat().st_size / 1024:.1f} KB)")

    # ═══════════════════════════════════════════════════════════
    # SUMMARY
    # ═══════════════════════════════════════════════════════════
    tf = sum(r.fail_count for r in all_vv)
    tw = sum(r.warn_count for r in all_vv)
    verdict = "PASS" if tf == 0 else f"FAIL ({tf})"

    print("\n╔══════════════════════════════════════════════════╗")
    print("║  Pipeline complete                              ║")
    print("╠══════════════════════════════════════════════════╣")
    print(f"║  Materials: {len(materials):>4}                               ║")
    for s in ["verified", "complete", "partial", "seed"]:
        c = status_counts.get(s, 0)
        if c:
            print(f"║    {s:>10}: {c:>4}                             ║")
    print(f"║  JSON: {json_path.stat().st_size / 1024:>7.1f} KB                              ║")
    print(f"║  JS:   {js_path.stat().st_size / 1024:>7.1f} KB                              ║")
    if not args.skip_vv:
        vl = f"V&V: {verdict}" + (f" ({tw} warn)" if tw else "")
        print(f"║  {vl:<48s}║")
    print("╠══════════════════════════════════════════════════╣")
    print("║  import { getMaterial } from './material_db.js'; ║")
    print("╚══════════════════════════════════════════════════╝")


if __name__ == "__main__":
    main()
