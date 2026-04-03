#!/usr/bin/env python3
"""
TDK Magnetic Design Tool (MDT) adapter.

Scrapes digitized material property data from TDK's online MDT web application
using Playwright browser automation. The MDT is a PHP + JavaScript app that
renders charts using the Highcharts library. The adapter intercepts the chart
data arrays from the JavaScript runtime.

Data available from MDT:
  - Complex permeability vs frequency (series and parallel representation)
  - Initial permeability vs temperature
  - Power loss vs frequency, flux density, temperature
  - Amplitude permeability vs B or H
  - DC bias curves (via core calculation pages)

Prerequisites:
    pip install playwright
    playwright install chromium

Usage:
    python tdk_mdt.py --materials N30 T35 K10       # Specific materials
    python tdk_mdt.py --emi-all                      # All 13 EMI-priority materials
    python tdk_mdt.py --output ../output/vendor/tdk_mdt.json

Network requirement: This adapter MUST reach tools.tdk-electronics.tdk.com.
"""

from __future__ import annotations
import asyncio
import hashlib
import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# EMI-priority materials to scrape first
EMI_PRIORITY = ["N30", "T35", "T36", "T37", "T65",
                "E11", "E12", "E13", "E14", "E16", "E19", "E21", "K10"]

MDT_BASE = "https://tools.tdk-electronics.tdk.com/mdt/index.php"

# MDT page routes for each data type
MDT_PAGES = {
    "complex_perm":  f"{MDT_BASE}/complexperm",
    "init_perm_vs_T": f"{MDT_BASE}/initperm",
    "power_loss_vs_f": f"{MDT_BASE}/pl_freq",
    "power_loss_vs_B": f"{MDT_BASE}/pl_flux_density",
    "power_loss_vs_T": f"{MDT_BASE}/pl_temp",
    "amplitude_perm_B": f"{MDT_BASE}/amplitpermb",
    "amplitude_perm_H": f"{MDT_BASE}/amplitpermh",
}

# ── Chart data extraction JavaScript ──
# Highcharts stores data in window.Highcharts.charts[n].series[m].data
# This JS snippet extracts all series data from the current page's chart.
EXTRACT_HIGHCHARTS_JS = """
() => {
    const results = [];
    if (typeof Highcharts === 'undefined') return JSON.stringify({error: 'no_highcharts'});
    const charts = Highcharts.charts.filter(c => c);
    for (let ci = 0; ci < charts.length; ci++) {
        const chart = charts[ci];
        const chartData = {
            chart_index: ci,
            title: chart.title?.textStr || '',
            xAxis: chart.xAxis?.[0]?.axisTitle?.textStr || '',
            yAxis: chart.yAxis?.[0]?.axisTitle?.textStr || '',
            xType: chart.xAxis?.[0]?.isLog ? 'log' : 'linear',
            yType: chart.yAxis?.[0]?.isLog ? 'log' : 'linear',
            series: []
        };
        for (let si = 0; si < chart.series.length; si++) {
            const s = chart.series[si];
            if (s.visible === false) continue;
            const points = s.data.map(p => ({
                x: p.x != null ? p.x : p.category,
                y: p.y
            })).filter(p => p.x != null && p.y != null);
            chartData.series.push({
                name: s.name || `series_${si}`,
                points: points,
                point_count: points.length
            });
        }
        results.push(chartData);
    }
    return JSON.stringify(results);
}
"""

# Alternative: some MDT pages use custom chart libs or inline data arrays.
# This fallback extracts any JSON-like arrays from script tags.
EXTRACT_INLINE_DATA_JS = """
() => {
    const scripts = document.querySelectorAll('script:not([src])');
    const arrays = [];
    for (const s of scripts) {
        const text = s.textContent;
        // Look for patterns like: data: [[x,y], [x,y], ...]
        const matches = text.matchAll(/data\s*:\s*(\[\s*\[[\d.e+\-,\s]+\][\s\S]*?\])/gi);
        for (const m of matches) {
            try {
                const parsed = JSON.parse(m[1]);
                if (Array.isArray(parsed) && parsed.length > 3) {
                    arrays.push({source: 'inline_script', data: parsed});
                }
            } catch(e) {}
        }
    }
    return JSON.stringify(arrays);
}
"""


async def scrape_material_page(page, material_id: str, page_key: str, url: str) -> dict[str, Any]:
    """
    Navigate to an MDT page for a given material and extract chart data.

    Returns extracted chart data dict or error dict.
    """
    result = {
        "material": material_id,
        "page": page_key,
        "url": url,
        "status": "pending",
        "charts": [],
        "raw_data": [],
    }

    try:
        await page.goto(url, wait_until="networkidle", timeout=30000)

        # Select the material from the dropdown
        # MDT uses a <select> element with material names
        material_select = await page.query_selector('select[name="material"], select#material')
        if material_select:
            # Try to select by visible text or value
            options = await material_select.query_selector_all('option')
            found = False
            for opt in options:
                text = await opt.text_content()
                value = await opt.get_attribute('value')
                if material_id in (text or '') or material_id == (value or ''):
                    await material_select.select_option(value=value)
                    found = True
                    break

            if not found:
                result["status"] = "material_not_found"
                result["error"] = f"Material {material_id} not in dropdown"
                return result

            # Wait for chart to re-render after material selection
            await page.wait_for_timeout(2000)
            await page.wait_for_load_state("networkidle")
            await page.wait_for_timeout(1000)
        else:
            result["status"] = "no_material_selector"
            result["error"] = "Could not find material dropdown"

        # Extract chart data via Highcharts API
        chart_json = await page.evaluate(EXTRACT_HIGHCHARTS_JS)
        charts = json.loads(chart_json) if isinstance(chart_json, str) else chart_json

        if isinstance(charts, dict) and charts.get("error"):
            # Highcharts not found — try inline data extraction
            inline_json = await page.evaluate(EXTRACT_INLINE_DATA_JS)
            inline_data = json.loads(inline_json) if isinstance(inline_json, str) else inline_json
            result["raw_data"] = inline_data
            result["status"] = "fallback_inline"
        elif isinstance(charts, list) and len(charts) > 0:
            result["charts"] = charts
            result["status"] = "success"
        else:
            result["status"] = "no_data"

    except Exception as e:
        result["status"] = "error"
        result["error"] = str(e)

    return result


def convert_complex_perm_data(chart_data: dict[str, Any], material_id: str) -> dict[str, Any] | None:
    """
    Convert MDT complex permeability chart data to unified schema curve block.

    MDT typically shows two series: µ's (real) and µ''s (imaginary) for series representation.
    """
    series_list = chart_data.get("series", [])
    if len(series_list) < 2:
        return None

    # Identify which series is µ' and which is µ''
    mu_prime_series = None
    mu_double_prime_series = None

    for s in series_list:
        name_lower = s.get("name", "").lower()
        if "µ'" in name_lower or "mu'" in name_lower or "real" in name_lower or "µs'" in name_lower:
            mu_prime_series = s
        elif "µ''" in name_lower or 'mu"' in name_lower or "imag" in name_lower or "µs''" in name_lower:
            mu_double_prime_series = s

    # Fallback: first series = µ', second = µ''
    if not mu_prime_series and len(series_list) >= 1:
        mu_prime_series = series_list[0]
    if not mu_double_prime_series and len(series_list) >= 2:
        mu_double_prime_series = series_list[1]

    if not mu_prime_series or not mu_double_prime_series:
        return None

    # Build unified samples array
    # MDT may provide different x-points for each series; we need to merge
    prime_points = {p["x"]: p["y"] for p in mu_prime_series.get("points", [])}
    dprime_points = {p["x"]: p["y"] for p in mu_double_prime_series.get("points", [])}

    # Use intersection of x-values (frequencies both series cover)
    common_freqs = sorted(set(prime_points.keys()) & set(dprime_points.keys()))

    if not common_freqs:
        # Use the µ' frequencies and interpolate µ'' (or vice versa)
        common_freqs = sorted(prime_points.keys())

    samples = []
    for f in common_freqs:
        mp = prime_points.get(f)
        mpp = dprime_points.get(f)
        if mp is not None and mpp is not None:
            samples.append([float(f), float(mp), float(mpp)])

    if len(samples) < 3:
        return None

    # Compute hashes for V&V
    samples_canonical = json.dumps(
        [[float(f"{v:.10g}") for v in row] for row in samples],
        separators=(",", ":")
    )
    samples_hash = hashlib.sha256(samples_canonical.encode("utf-8")).hexdigest()

    return {
        "description": f"Complex permeability (series) vs frequency for TDK {material_id}",
        "x_quantity": "frequency",
        "x_unit": "Hz",
        "y_quantities": ["mu_prime", "mu_double_prime"],
        "y_units": ["1", "1"],
        "test_conditions": {
            "temperature_C": 25,
            "representation": "series",
            "core_shape": "MDT default test core"
        },
        "samples": samples,
        "source": {
            "method": "mdt_scrape",
            "url": MDT_PAGES["complex_perm"],
            "accessed_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            "confidence": "high",
            "notes": f"Extracted from TDK MDT Highcharts data for {material_id}",
            "samples_sha256": samples_hash,
            "raw_point_count": len(samples),
            "mu_prime_raw_count": len(prime_points),
            "mu_double_prime_raw_count": len(dprime_points),
        }
    }


def convert_init_perm_data(chart_data: dict[str, Any], material_id: str) -> dict[str, Any] | None:
    """Convert MDT initial permeability vs temperature data to schema."""
    series_list = chart_data.get("series", [])
    if not series_list:
        return None

    points = series_list[0].get("points", [])
    if len(points) < 3:
        return None

    samples = [[float(p["x"]), float(p["y"])] for p in points
               if p.get("x") is not None and p.get("y") is not None]
    samples.sort(key=lambda s: s[0])

    return {
        "description": f"Initial permeability vs temperature for TDK {material_id}",
        "x_quantity": "temperature",
        "x_unit": "C",
        "y_quantities": ["mu_i"],
        "y_units": ["1"],
        "test_conditions": {"frequency_Hz": 10000, "flux_density_mT": 0.25},
        "samples": samples,
        "source": {
            "method": "mdt_scrape",
            "url": MDT_PAGES["init_perm_vs_T"],
            "accessed_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            "confidence": "high",
            "notes": f"MDT digitized data for {material_id}",
            "raw_point_count": len(samples),
        }
    }


def convert_power_loss_data(chart_data: dict[str, Any], material_id: str,
                            page_key: str) -> dict[str, Any] | None:
    """Convert MDT power loss chart data to schema."""
    series_list = chart_data.get("series", [])
    if not series_list:
        return None

    # Power loss charts often have multiple series (different temps or B levels)
    # For now, take all series as separate y-columns
    all_x = set()
    for s in series_list:
        for p in s.get("points", []):
            if p.get("x") is not None:
                all_x.add(float(p["x"]))

    x_sorted = sorted(all_x)
    if len(x_sorted) < 3:
        return None

    y_quantities = []
    y_units = []
    series_data = {}  # {series_name: {x: y}}

    for s in series_list:
        name = s.get("name", "series")
        y_quantities.append(f"Pv_{name}")
        y_units.append("kW/m3")
        series_data[name] = {float(p["x"]): float(p["y"])
                             for p in s.get("points", [])
                             if p.get("x") is not None and p.get("y") is not None}

    # Build samples where all series have data
    samples = []
    for x in x_sorted:
        row = [x]
        all_present = True
        for name in series_data:
            if x in series_data[name]:
                row.append(series_data[name][x])
            else:
                all_present = False
                break
        if all_present:
            samples.append(row)

    if len(samples) < 3:
        return None

    x_quantity = "frequency" if "freq" in page_key else ("flux_density" if "flux" in page_key else "temperature")
    x_unit = "Hz" if x_quantity == "frequency" else ("mT" if x_quantity == "flux_density" else "C")

    return {
        "description": f"Power loss for TDK {material_id} ({page_key})",
        "x_quantity": x_quantity,
        "x_unit": x_unit,
        "y_quantities": y_quantities,
        "y_units": y_units,
        "test_conditions": {"waveform": "sinusoidal"},
        "samples": samples,
        "source": {
            "method": "mdt_scrape",
            "url": MDT_PAGES.get(page_key, MDT_BASE),
            "accessed_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            "confidence": "high",
            "notes": f"MDT digitized data for {material_id}",
            "raw_point_count": len(samples),
        }
    }


async def scrape_material(browser, material_id: str,
                          pages_to_scrape: list[str] | None = None) -> dict[str, Any]:
    """
    Scrape all available data for one TDK material from MDT.

    Returns a dict with curves ready to merge into a material record.
    """
    if pages_to_scrape is None:
        pages_to_scrape = ["complex_perm", "init_perm_vs_T", "power_loss_vs_f"]

    context = await browser.new_context()
    page = await context.new_page()

    curves = {}
    scrape_log = []

    for page_key in pages_to_scrape:
        url = MDT_PAGES.get(page_key)
        if not url:
            continue

        print(f"    Scraping {page_key}...", end=" ")
        result = await scrape_material_page(page, material_id, page_key, url)
        scrape_log.append({"page": page_key, "status": result["status"]})

        if result["status"] == "success" and result["charts"]:
            chart = result["charts"][0]  # Primary chart

            if page_key == "complex_perm":
                curve_block = convert_complex_perm_data(chart, material_id)
                if curve_block:
                    curves["complex_perm_vs_f"] = curve_block
                    print(f"✓ {len(curve_block['samples'])} points")
                else:
                    print("✗ conversion failed")
            elif page_key == "init_perm_vs_T":
                curve_block = convert_init_perm_data(chart, material_id)
                if curve_block:
                    curves["mu_i_vs_temperature"] = curve_block
                    print(f"✓ {len(curve_block['samples'])} points")
                else:
                    print("✗ conversion failed")
            elif "power_loss" in page_key:
                curve_block = convert_power_loss_data(chart, material_id, page_key)
                if curve_block:
                    curves[page_key] = curve_block
                    print(f"✓ {len(curve_block['samples'])} points")
                else:
                    print("✗ conversion failed")
        else:
            print(f"✗ {result['status']}")

    await context.close()

    return {
        "curves": curves,
        "scrape_log": scrape_log,
    }


async def run_mdt_scraper(
    materials: list[str],
    existing_db_path: str | None = None,
    output_path: str | None = None,
    pages: list[str] | None = None,
) -> dict[str, Any]:
    """
    Main entry point: scrape MDT for a list of TDK materials.

    Merges scraped curve data into existing TDK records if available.
    """
    from playwright.async_api import async_playwright

    print("TDK MDT Scraper")
    print("=" * 50)
    print(f"  Materials: {', '.join(materials)}")
    print(f"  Target: {MDT_BASE}")
    print()

    # Load existing TDK records if available
    existing_records = {}
    if existing_db_path and Path(existing_db_path).exists():
        db = json.loads(Path(existing_db_path).read_text(encoding="utf-8"))
        existing_records = db.get("materials", {})

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)

        results = {}
        for mat_id in materials:
            print(f"  [{mat_id}]")
            scrape_result = await scrape_material(browser, mat_id, pages)

            # Merge into existing record or create new one
            record_key = f"TDK_{mat_id}"
            if record_key in existing_records:
                record = existing_records[record_key].copy()
                # Merge new curves into existing record
                for curve_name, curve_data in scrape_result["curves"].items():
                    record["curves"][curve_name] = curve_data
                # Update status
                if record["curves"]:
                    record["record_status"] = "complete" if len(record["curves"]) >= 2 else "partial"
                record["last_updated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                record["review_notes"].append(f"MDT scrape: {len(scrape_result['curves'])} curves added")
            else:
                record = {
                    "material_id": record_key,
                    "vendor": "TDK Electronics",
                    "vendor_material_code": mat_id,
                    "family": "EMI ferrite",
                    "chemistry": "NiZn" if mat_id.startswith(("K", "E")) else "MnZn",
                    "application_tags": ["EMI_filter"],
                    "summary": f"TDK {mat_id} (data from MDT)",
                    "properties_ref": {},
                    "curves": scrape_result["curves"],
                    "fitted_models": {},
                    "record_status": "partial" if scrape_result["curves"] else "seed",
                    "last_updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "mdt_url": MDT_BASE,
                    "review_notes": [f"MDT scrape: {len(scrape_result['curves'])} curves"],
                }

            results[record_key] = record

        await browser.close()

    # Write output
    db_out = {
        "schema_version": "1.0.0",
        "generated_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "vendor": "TDK Electronics",
        "source": "MDT scrape",
        "materials": results,
    }

    if output_path:
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        Path(output_path).write_text(json.dumps(db_out, indent=2), encoding="utf-8")
        print(f"\nWrote {output_path}")

    return db_out


def run_adapter(
    materials: list[str] | None = None,
    existing_db_path: str | None = None,
    output_path: str | None = None,
    emi_only: bool = True,
) -> dict[str, Any]:
    """Synchronous wrapper for the async scraper."""
    if materials is None:
        materials = EMI_PRIORITY if emi_only else EMI_PRIORITY

    return asyncio.run(run_mdt_scraper(
        materials=materials,
        existing_db_path=existing_db_path,
        output_path=output_path,
    ))


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="TDK MDT scraper")
    parser.add_argument("--materials", nargs="*", help="Material codes to scrape")
    parser.add_argument("--emi-all", action="store_true", help="Scrape all 13 EMI-priority materials")
    parser.add_argument("--existing-db", help="Existing TDK vendor JSON to merge into")
    parser.add_argument("--output", default="output/vendor/tdk_mdt.json")
    args = parser.parse_args()

    mats = args.materials or (EMI_PRIORITY if args.emi_all else ["N30"])
    run_adapter(materials=mats, existing_db_path=args.existing_db, output_path=args.output)
