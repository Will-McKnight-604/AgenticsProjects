#!/usr/bin/env python3
"""
Fair-Rite CSV adapter.

Downloads complex permeability CSV files from Fair-Rite material data sheet pages
and converts them to the unified material database schema.

Fair-Rite is the easiest vendor to ingest because they provide direct CSV downloads
on each material page with columns: Frequency, Permeability_Real, Permeability_Imaginary.

Usage:
    python fair_rite_csv.py                    # Process all known materials
    python fair_rite_csv.py --materials 43 61  # Process specific materials
    python fair_rite_csv.py --output ../output/vendor/fair_rite.json
"""

from __future__ import annotations
import argparse
import csv
import io
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# ── Known Fair-Rite materials with their CSV URLs and properties ──
# These are manually verified from the Fair-Rite website.
# Each material page has a "Click here to download Complex Permeability vs. Frequency (CSV)" link.

FAIR_RITE_CATALOG: list[dict[str, Any]] = [
    {
        "code": "15",
        "chemistry": "NiZn",
        "family": "EMI ferrite",
        "mu_i": 1500,
        "saturation_mT": 270,
        "curie_C": 105,
        "resistivity_ohm_cm": 1e8,
        "freq_range_MHz": [10, 250],
        "summary": "High-µ NiZn ferrite for suppression and broadband applications. Impedance extends down to 10 MHz.",
        "tags": ["EMI_suppression", "broadband", "high_permeability"],
        "page_url": "https://fair-rite.com/15-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2019/07/15-Material-Fair-Rite.csv"
    },
    {
        "code": "20",
        "chemistry": "NiZn",
        "family": "EMI ferrite",
        "mu_i": 2000,
        "saturation_mT": 330,
        "curie_C": 110,
        "resistivity_ohm_cm": 1e7,
        "freq_range_MHz": [1, 300],
        "summary": "High-µ NiZn ferrite for broadband and EMI suppression up to 300 MHz.",
        "tags": ["EMI_suppression", "broadband", "high_permeability"],
        "page_url": "https://fair-rite.com/20-material-data-sheet/",
        "csv_url": "https://fair-rite.com/wp-content/uploads/2024/10/20-Material-Fair-Rite-Preliminary-1.csv"
    },
    {
        "code": "31",
        "chemistry": "MnZn",
        "family": "EMI ferrite",
        "mu_i": 1500,
        "saturation_mT": 360,
        "curie_C": 130,
        "resistivity_ohm_cm": 3000,
        "freq_range_MHz": [1, 500],
        "summary": "MnZn ferrite for EMI suppression from 1 MHz to 500 MHz. No dimensional resonance limitations.",
        "tags": ["EMI_suppression", "broadband", "cable_cores"],
        "page_url": "https://fair-rite.com/31-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/03/31-Material-Fair-Rite.csv"
    },
    {
        "code": "43",
        "chemistry": "NiZn",
        "family": "EMI ferrite",
        "mu_i": 800,
        "saturation_mT": 300,
        "curie_C": 130,
        "resistivity_ohm_cm": 1e5,
        "freq_range_MHz": [25, 300],
        "summary": "NiZn ferrite for EMI suppression from 25 MHz to 300 MHz. Most popular suppression material.",
        "tags": ["EMI_suppression", "broadband", "beads", "cable_cores"],
        "page_url": "https://fair-rite.com/43-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2020/11/43-Material-publish.csv"
    },
    {
        "code": "44",
        "chemistry": "NiZn",
        "family": "EMI ferrite",
        "mu_i": 290,
        "saturation_mT": 200,
        "curie_C": 250,
        "resistivity_ohm_cm": 1e5,
        "freq_range_MHz": [50, 500],
        "summary": "NiZn ferrite for EMI suppression from 50 MHz to 500 MHz. Higher Curie temp than 43.",
        "tags": ["EMI_suppression", "high_temp", "beads"],
        "page_url": "https://fair-rite.com/44-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/44-Material-Fair-Rite.csv"
    },
    {
        "code": "46",
        "chemistry": "NiZn",
        "family": "EMI ferrite",
        "mu_i": 14,
        "saturation_mT": 350,
        "curie_C": 500,
        "resistivity_ohm_cm": 1e9,
        "freq_range_MHz": [500, 2000],
        "summary": "NiZn ferrite for EMI suppression above 500 MHz. Very low permeability, very high frequency.",
        "tags": ["EMI_suppression", "VHF", "UHF"],
        "page_url": "https://fair-rite.com/46-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/46-Material-Fair-Rite.csv"
    },
    {
        "code": "51",
        "chemistry": "NiZn",
        "family": "EMI ferrite",
        "mu_i": 170,
        "saturation_mT": 250,
        "curie_C": 200,
        "resistivity_ohm_cm": 1e9,
        "freq_range_MHz": [0.5, 5],
        "summary": "NiZn ferrite for low-loss inductive designs up to 5 MHz.",
        "tags": ["inductive", "low_loss", "transformers"],
        "page_url": "https://fair-rite.com/51-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/51-Material-Fair-Rite.csv"
    },
    {
        "code": "52",
        "chemistry": "NiZn",
        "family": "EMI ferrite",
        "mu_i": 250,
        "saturation_mT": 360,
        "curie_C": 270,
        "resistivity_ohm_cm": 1e9,
        "freq_range_MHz": [1, 200],
        "summary": "NiZn with high Bsat and high Curie temp. Good for broadband EMI.",
        "tags": ["EMI_suppression", "broadband", "high_Bsat"],
        "page_url": "https://fair-rite.com/52-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/52-Material-Fair-Rite.csv"
    },
    {
        "code": "61",
        "chemistry": "NiZn",
        "family": "EMI ferrite",
        "mu_i": 125,
        "saturation_mT": 250,
        "curie_C": 350,
        "resistivity_ohm_cm": 1e9,
        "freq_range_MHz": [200, 1000],
        "summary": "NiZn ferrite for EMI suppression 200 MHz to 1 GHz. Excellent for high-speed data lines.",
        "tags": ["EMI_suppression", "high_frequency", "data_line", "GHz"],
        "page_url": "https://fair-rite.com/61-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2021/11/61-Material-Fair-Rite.csv"
    },
    {
        "code": "67",
        "chemistry": "NiZn",
        "family": "EMI ferrite",
        "mu_i": 40,
        "saturation_mT": 350,
        "curie_C": 500,
        "resistivity_ohm_cm": 1e9,
        "freq_range_MHz": [300, 1000],
        "summary": "NiZn ferrite for VHF/UHF suppression 300 MHz–1 GHz.",
        "tags": ["EMI_suppression", "VHF", "UHF"],
        "page_url": "https://fair-rite.com/67-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2020/05/67-Material_publish.csv"
    },
    {
        "code": "68",
        "chemistry": "NiZn",
        "family": "EMI ferrite",
        "mu_i": 20,
        "saturation_mT": 350,
        "curie_C": 500,
        "resistivity_ohm_cm": 1e9,
        "freq_range_MHz": [500, 2000],
        "summary": "NiZn ferrite for GHz-range EMI suppression.",
        "tags": ["EMI_suppression", "GHz", "UHF"],
        "page_url": "https://fair-rite.com/68-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2020/05/68-Material_publish.csv"
    },
    {
        "code": "73",
        "chemistry": "MnZn",
        "family": "EMI ferrite",
        "mu_i": 2500,
        "saturation_mT": 375,
        "curie_C": 160,
        "resistivity_ohm_cm": 100,
        "freq_range_MHz": [0.01, 50],
        "summary": "MnZn ferrite for conducted EMI suppression below 50 MHz. Beads and multi-aperture cores.",
        "tags": ["EMI_suppression", "conducted", "beads", "low_frequency"],
        "page_url": "https://fair-rite.com/73-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/73-Material-Fair-Rite.csv"
    },
    {
        "code": "75",
        "chemistry": "MnZn",
        "family": "EMI ferrite",
        "mu_i": 5000,
        "saturation_mT": 400,
        "curie_C": 140,
        "resistivity_ohm_cm": 300,
        "freq_range_MHz": [0.001, 1],
        "summary": "High-µ MnZn for broadband/pulse transformers and common-mode inductors.",
        "tags": ["transformers", "common_mode", "high_permeability"],
        "page_url": "https://fair-rite.com/75-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/75-Material-Fair-Rite.csv"
    },
    {
        "code": "76",
        "chemistry": "MnZn",
        "family": "EMI ferrite",
        "mu_i": 10000,
        "saturation_mT": 400,
        "curie_C": 120,
        "resistivity_ohm_cm": 50,
        "freq_range_MHz": [0.001, 0.5],
        "summary": "Very high-µ MnZn for low-frequency CM suppression, broadband and pulse transformers.",
        "tags": ["common_mode", "high_permeability", "low_frequency"],
        "page_url": "https://fair-rite.com/76-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/76-Material-Fair-Rite.csv"
    },
    {
        "code": "77",
        "chemistry": "MnZn",
        "family": "EMI ferrite",
        "mu_i": 2000,
        "saturation_mT": 480,
        "curie_C": 200,
        "resistivity_ohm_cm": 100,
        "freq_range_MHz": [0.001, 0.1],
        "summary": "MnZn ferrite for inductive designs up to 100 kHz. High Bsat.",
        "tags": ["inductive", "power", "high_Bsat"],
        "page_url": "https://fair-rite.com/77-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/77-Material-Fair-Rite.csv"
    },
    {
        "code": "78",
        "chemistry": "MnZn",
        "family": "EMI ferrite",
        "mu_i": 2300,
        "saturation_mT": 480,
        "curie_C": 210,
        "resistivity_ohm_cm": 200,
        "freq_range_MHz": [0.001, 0.5],
        "summary": "MnZn power ferrite for up to 200 kHz and low-loss inductive to 500 kHz.",
        "tags": ["inductive", "power", "low_loss"],
        "page_url": "https://fair-rite.com/78-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/78-Material-Fair-Rite.csv"
    },
    {
        "code": "79",
        "chemistry": "MnZn",
        "family": "EMI ferrite",
        "mu_i": 225,
        "saturation_mT": 450,
        "curie_C": 250,
        "resistivity_ohm_cm": 500,
        "freq_range_MHz": [0.001, 0.75],
        "summary": "MnZn power ferrite for applications up to 750 kHz.",
        "tags": ["power", "high_frequency_power"],
        "page_url": "https://fair-rite.com/79-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/79-Material-Fair-Rite.csv"
    },
    {
        "code": "80",
        "chemistry": "MnZn",
        "family": "EMI ferrite",
        "mu_i": 900,
        "saturation_mT": 430,
        "curie_C": 250,
        "resistivity_ohm_cm": 400,
        "freq_range_MHz": [0.001, 0.3],
        "summary": "MnZn ferrite for low-loss power applications and wideband transformers to 300 kHz.",
        "tags": ["power", "transformers", "low_loss"],
        "page_url": "https://fair-rite.com/80-material-data-sheet/",
        "csv_url": "https://fair-rite.com/wp-content/uploads/2024/10/80-Material-Fair-Rite-1.csv"
    },
    {
        "code": "95",
        "chemistry": "MnZn",
        "family": "power ferrite",
        "mu_i": 3000,
        "saturation_mT": 500,
        "curie_C": 220,
        "resistivity_ohm_cm": 200,
        "freq_range_MHz": [0.001, 0.2],
        "summary": "Low-loss MnZn ferrite for power applications up to 200 kHz. Less power loss variation over temperature.",
        "tags": ["power", "low_loss", "temperature_stable"],
        "page_url": "https://fair-rite.com/95-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/95-Material-Fair-Rite.csv"
    },
    {
        "code": "96",
        "chemistry": "MnZn",
        "family": "power ferrite",
        "mu_i": 3300,
        "saturation_mT": 500,
        "curie_C": 215,
        "resistivity_ohm_cm": 200,
        "freq_range_MHz": [0.001, 0.5],
        "summary": "Low-loss MnZn ferrite for power applications up to 500 kHz. Minimal power loss over wide temperature range.",
        "tags": ["power", "low_loss", "temperature_stable", "high_frequency_power"],
        "page_url": "https://fair-rite.com/96-material-data-sheet/",
        "csv_url": "https://fair-rite.com/wp-content/uploads/2024/10/96-Material-Fair-Rite-Preliminary-1.csv"
    },
    {
        "code": "97",
        "chemistry": "MnZn",
        "family": "power ferrite",
        "mu_i": 2000,
        "saturation_mT": 500,
        "curie_C": 220,
        "resistivity_ohm_cm": 200,
        "freq_range_MHz": [0.001, 0.4],
        "summary": "Low-loss MnZn ferrite for power applications up to 400 kHz. Reduced power loss at 100C.",
        "tags": ["power", "low_loss", "high_frequency_power"],
        "page_url": "https://fair-rite.com/97-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/97-Material-Fair-Rite.csv"
    },
    {
        "code": "98",
        "chemistry": "MnZn",
        "family": "power ferrite",
        "mu_i": 2400,
        "saturation_mT": 500,
        "curie_C": 215,
        "resistivity_ohm_cm": 200,
        "freq_range_MHz": [0.001, 0.2],
        "summary": "Low-loss MnZn ferrite for power applications up to 200 kHz. Improved version of 78 material.",
        "tags": ["power", "low_loss"],
        "page_url": "https://fair-rite.com/98-material-data-sheet/",
        "csv_url": "https://www.fair-rite.com/wp-content/uploads/2015/04/98-Material-Fair-Rite.csv"
    },
]


# ── Chart image filename classification ──
# Fair-Rite uses inconsistent naming across materials.
# Regex patterns match case-insensitively against the filename.
import re as _re

# (regex_pattern, chart_type) — order matters: first match wins.
# Impedance patterns must precede permeability patterns to avoid Z→perm misclassification.
CHART_TYPE_PATTERNS: list[tuple[str, str]] = [
    # Power Loss vs Flux Density (at specific temp)
    (r"PowerLoss.*Flux", "core_loss"),
    (r"PL\w*v\w*(?:Flux|B|F)\d*", "core_loss"),  # PLvsFlux25, PLvB25, PLvF100
    (r"PLB\d+", "core_loss"),                      # 67PLB100
    (r"PL\d+", "core_loss"),                        # 95_PL25, 95pl100
    # Power Loss vs Temperature (must be before flux_vs_temp)
    (r"(?:PL|PowerLoss)\w*v\w*T(?:emp)?", "core_loss_vs_temp"),
    # Flux/B Density vs Temperature
    (r"(?:Flux|FluxDensity)\w*[Vv]\w*[Tt]", "flux_vs_temp"),
    (r"FL\w*[Vv]\w*T", "flux_vs_temp"),            # 78FLvT
    (r"FD\w*[Vv]\w*T", "flux_vs_temp"),            # 95FDvT
    (r"B[Vv]s?[TtYy]", "flux_vs_temp"),            # BvsT, bvst, BvsY (typo)
    # B-H hysteresis loop (Hysteresis sometimes misspelled as Hysterisis)
    (r"(?:_?BH|Hyster[ei])", "bh_curve"),
    # Complex permeability vs Frequency
    (r"(?:_?uuvsF|[Pp]erm\w*[Vv]\w*[Ff]req)", "complex_perm"),
    # Impedance vs Temperature (BEFORE perm_vs_temp to avoid Z→perm)
    (r"[Zz][Vv]s?[Tt]", "impedance_vs_temp"),
    (r"[Ii]mpedance\w*[Tt]emp", "impedance_vs_temp"),
    # Impedance vs Field Strength (BEFORE perm_vs_H to avoid Z→perm)
    (r"[Zz][Vv]s?[Hh]", "impedance_vs_H"),
    (r"[Ii]mpedance\w*[Ff]ield", "impedance_vs_H"),
    # Permeability vs Temperature
    (r"[Uu][Vv]s?[Tt]", "perm_vs_temp"),
    (r"[Pp]erm\w*[Vv]\w*[Tt]emp", "perm_vs_temp"),
    # Permeability vs Flux Density (B)
    (r"[Uu][Vv]s?B", "perm_vs_B"),
    # Permeability vs Field Strength (H) — only u-prefix, not Z-prefix
    (r"[Uu][Vv]s?H", "perm_vs_H"),
    (r"^\d+[-_]?vsH", "perm_vs_H"),               # 67vsH (bare, no u prefix)
    # Incremental / amplitude permeability
    (r"[Pp]erm(?:amp|\d+)", "perm_special"),
    (r"[Ii]ncremental[Pp]erm", "perm_special"),
    (r"[Aa]mp[Pp]erm", "perm_special"),
    (r"ipvsfs", "perm_special"),
    # DC characteristics
    (r"(?:\d|[-_])dc(?:$|[-_.])", "dc_characteristics"),
]


def classify_chart_image(url: str) -> str | None:
    """Classify a chart image URL by matching against known filename patterns."""
    filename = url.rsplit("/", 1)[-1]
    # Strip material code prefix and extension for cleaner matching
    name_part = filename.rsplit(".", 1)[0]
    for pattern, chart_type in CHART_TYPE_PATTERNS:
        if _re.search(pattern, name_part, _re.IGNORECASE):
            return chart_type
    return None


def scrape_material_charts(
    page_url: str,
    material_code: str,
    staging_dir: Path,
) -> list[dict[str, str]]:
    """
    Scrape a Fair-Rite material data sheet page for chart images.

    Returns list of dicts: [{"chart_type": ..., "url": ..., "local_path": ...}, ...]
    """
    import re
    import urllib.request

    mat_id = f"FR_{material_code}"
    results = []

    try:
        req = urllib.request.Request(page_url, headers={"User-Agent": "MaterialPipeline/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            html = resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"    chart scrape failed for {mat_id}: {e}")
        return []

    # Find all image URLs in the page
    img_urls = re.findall(r'<img[^>]+src=["\']([^"\']+)["\']', html, re.IGNORECASE)

    # Filter to chart images (must contain material code number in filename)
    chart_urls = []
    for url in img_urls:
        filename = url.rsplit("/", 1)[-1]
        # Chart images contain the material number and are in wp-content/uploads
        if material_code not in filename:
            continue
        if "wp-content/uploads" not in url:
            continue
        chart_type = classify_chart_image(url)
        if chart_type:
            # Normalize URL
            if url.startswith("//"):
                url = "https:" + url
            elif not url.startswith("http"):
                url = "https://fair-rite.com" + url
            chart_urls.append((chart_type, url))

    # Also find unclassified chart images (for discovery)
    for url in img_urls:
        filename = url.rsplit("/", 1)[-1]
        if material_code not in filename and material_code.lower() not in filename.lower():
            continue
        if "wp-content/uploads" not in url:
            continue
        if classify_chart_image(url) is None:
            # Check if it's a chart (JPG/PNG, not too small based on filename)
            ext = filename.rsplit(".", 1)[-1].lower()
            if ext in ("jpg", "jpeg", "png"):
                if url.startswith("//"):
                    url = "https:" + url
                elif not url.startswith("http"):
                    url = "https://fair-rite.com" + url
                # Skip if already classified
                if not any(u == url for _, u in chart_urls):
                    chart_urls.append(("unknown", url))

    # Download each chart image
    staging_dir.mkdir(parents=True, exist_ok=True)
    for chart_type, url in chart_urls:
        ext = url.rsplit(".", 1)[-1].split("?")[0].lower()
        if ext not in ("jpg", "jpeg", "png"):
            ext = "jpg"

        # Include temperature suffix for core loss charts
        suffix = ""
        filename = url.rsplit("/", 1)[-1]
        if chart_type == "core_loss":
            # Extract temperature from filename variants:
            # PLvsFlux25, PLvB25, PLvF25, _PL25, PLB100, PowerLossVsFluxDensity25C, etc.
            temp_match = re.search(r'(\d+)\s*C?\.(?:jpg|png)', filename, re.IGNORECASE)
            if not temp_match:
                temp_match = re.search(r'(?:Flux|vB|vF|PL|PLB)(\d+)', filename, re.IGNORECASE)
            if temp_match:
                suffix = f"_{temp_match.group(1)}C"

        local_name = f"{mat_id}_{chart_type}{suffix}.{ext}"
        local_path = staging_dir / local_name

        try:
            req = urllib.request.Request(url, headers={"User-Agent": "MaterialPipeline/1.0"})
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = resp.read()
            local_path.write_bytes(data)
            results.append({
                "chart_type": chart_type,
                "url": url,
                "local_path": str(local_path),
                "filename": local_name,
            })
        except Exception as e:
            print(f"    failed to download {chart_type} chart: {e}")

    return results


def scrape_material_properties(page_url: str, material_code: str) -> dict[str, Any]:
    """
    Scrape the HTML properties table from a Fair-Rite material data sheet page.

    Returns dict of property_name -> value (with units).
    """
    import re
    import urllib.request

    try:
        req = urllib.request.Request(page_url, headers={"User-Agent": "MaterialPipeline/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            html = resp.read().decode("utf-8", errors="replace")
    except Exception:
        return {}

    # Find table rows — Fair-Rite uses <td> with Property | Unit | Symbol | Value
    properties = {}
    rows = re.findall(r'<tr[^>]*>(.*?)</tr>', html, re.DOTALL | re.IGNORECASE)
    for row_html in rows:
        cells = re.findall(r'<td[^>]*>(.*?)</td>', row_html, re.DOTALL | re.IGNORECASE)
        if len(cells) >= 4:
            prop_name = re.sub(r'<[^>]+>', '', cells[0]).strip()
            unit = re.sub(r'<[^>]+>', '', cells[1]).strip()
            value_str = re.sub(r'<[^>]+>', '', cells[3]).strip()
            if prop_name and value_str:
                try:
                    value = float(value_str.replace(",", ""))
                    properties[prop_name] = {"value": value, "unit": unit}
                except ValueError:
                    properties[prop_name] = {"value": value_str, "unit": unit}

    return properties


def discover_csv_url(page_url: str) -> str | None:
    """
    Scrape a Fair-Rite material data sheet page to find the CSV download URL.
    Used as a fallback when hardcoded csv_url fails (Fair-Rite changes URLs periodically).
    """
    import re
    import urllib.request
    try:
        req = urllib.request.Request(page_url, headers={"User-Agent": "MaterialPipeline/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            html = resp.read().decode("utf-8", errors="replace")
        # Look for .csv links in the HTML
        csv_links = re.findall(r'href=["\']([^"\']*\.csv)["\']', html, re.IGNORECASE)
        # Prefer the complex permeability CSV (usually the first or only one)
        for link in csv_links:
            if "permeability" in link.lower() or "material" in link.lower():
                return link
        # Fall back to the first CSV link found
        return csv_links[0] if csv_links else None
    except Exception:
        return None


def parse_fair_rite_csv(csv_text: str) -> list[list[float]]:
    """
    Parse a Fair-Rite complex permeability CSV.

    Handles multiple Fair-Rite CSV formats:
      Format A (most materials): Frequency,mu',mu''  with bare \\r line endings
      Format B (67, 68, etc.):   ,Frequency,mu',mu''  with leading comma and extra columns

    Returns list of [f_Hz, mu_prime, mu_double_prime] arrays.
    """
    # Normalize line endings (some CSVs use bare \r)
    csv_text = csv_text.replace("\r\n", "\n").replace("\r", "\n")

    reader = csv.reader(io.StringIO(csv_text))
    samples = []

    for row in reader:
        # Strip empty trailing cells
        while row and row[-1].strip() == "":
            row.pop()
        # Strip empty leading cells
        while row and row[0].strip() == "":
            row.pop(0)

        if not row or len(row) < 3:
            continue

        # Try to parse as [frequency, mu', mu'']
        try:
            f = float(row[0].strip())
            mu_p = float(row[1].strip())
            mu_pp = float(row[2].strip())
        except ValueError:
            continue

        samples.append([f, mu_p, mu_pp])

    # Sort by frequency ascending
    samples.sort(key=lambda s: s[0])
    return samples


def build_material_record(
    entry: dict[str, Any],
    samples: list[list[float]] | None,
    accessed_date: str,
    raw_csv_text: str | None = None,
) -> dict[str, Any]:
    """
    Build a unified schema material record from a Fair-Rite catalog entry
    and its parsed CSV data.
    """
    import hashlib

    material_id = f"FR_{entry['code']}"

    # Determine record status based on data availability
    if samples and len(samples) >= 10:
        status = "complete"
    elif samples and len(samples) > 0:
        status = "partial"
    else:
        status = "seed"

    # Build curves dict
    curves: dict[str, Any] = {}

    if samples:
        # Compute source hash for V&V Layer 1
        source_hash = None
        if raw_csv_text:
            source_hash = hashlib.sha256(raw_csv_text.encode("utf-8")).hexdigest()

        # Compute samples hash for V&V Layer 2
        # MUST sort by frequency before hashing to match verification.py's _canonical_samples_hash
        import json as _json
        sorted_samples = sorted(samples, key=lambda r: r[0])
        samples_canonical = _json.dumps(
            [[float(f"{v:.10g}") for v in row] for row in sorted_samples],
            separators=(",", ":")
        )
        samples_hash = hashlib.sha256(samples_canonical.encode("utf-8")).hexdigest()

        curves["complex_perm_vs_f"] = {
            "description": f"Complex permeability (series) vs frequency for Fair-Rite {entry['code']} at 25°C",
            "x_quantity": "frequency",
            "x_unit": "Hz",
            "y_quantities": ["mu_prime", "mu_double_prime"],
            "y_units": ["1", "1"],
            "test_conditions": {
                "temperature_C": 25,
                "core_shape": "standard toroid 18/10/6 mm",
                "representation": "series"
            },
            "samples": samples,
            "source": {
                "method": "csv_download" if raw_csv_text else "seed_database",
                "url": entry["csv_url"],
                "accessed_date": accessed_date,
                "confidence": "high" if raw_csv_text else "medium",
                "notes": ("Direct CSV download from Fair-Rite material data sheet page"
                          if raw_csv_text else
                          "Loaded from seed database — re-run with --network to verify against vendor"),
                "source_sha256": source_hash,
                "samples_sha256": samples_hash,
                "raw_point_count": len(samples),
            }
        }

    # Scalar properties
    properties_ref: dict[str, Any] = {
        "mu_i": entry["mu_i"],
        "reference_temperature_C": 25,
        "reference_frequency_Hz": 10000,
    }
    if entry.get("saturation_mT"):
        properties_ref["saturation_flux_density_mT"] = entry["saturation_mT"]
    if entry.get("curie_C"):
        properties_ref["curie_temperature_C"] = entry["curie_C"]
    if entry.get("resistivity_ohm_cm"):
        # Convert ohm·cm to ohm·m (÷ 100)
        properties_ref["resistivity_ohm_m"] = entry["resistivity_ohm_cm"] / 100

    record = {
        "material_id": material_id,
        "vendor": "Fair-Rite",
        "vendor_material_code": entry["code"],
        "family": entry.get("family", "EMI ferrite"),
        "chemistry": entry["chemistry"],
        "application_tags": entry.get("tags", []),
        "summary": entry.get("summary", ""),
        "properties_ref": properties_ref,
        "curves": curves,
        "fitted_models": {},
        "record_status": status,
        "last_updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "pdf_url": entry["page_url"],
        "review_notes": []
    }

    return record


def load_existing_csv_from_seed(seed_path: str, material_code: str) -> list[list[float]] | None:
    """
    Load complex permeability data from the existing seed database JSON
    (for offline / no-network mode).
    """
    try:
        seed = json.loads(Path(seed_path).read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return None

    key = f"fair_rite_{material_code}"
    mat = seed.get("materials", {}).get(key)
    if not mat:
        return None

    curve = mat.get("complex_permeability_curve")
    if not curve:
        return None

    samples = []
    for pt in curve:
        f = pt.get("f_Hz")
        mp = pt.get("mu_prime")
        mpp = pt.get("mu_double_prime")
        if f is not None and mp is not None and mpp is not None:
            samples.append([float(f), float(mp), float(mpp)])

    samples.sort(key=lambda s: s[0])
    return samples if samples else None


def run_adapter(
    materials: list[str] | None = None,
    seed_path: str | None = None,
    output_path: str | None = None,
    use_network: bool = False,
    scrape_charts: bool = False,
) -> dict[str, Any]:
    """
    Main adapter entry point.

    Args:
        materials: List of material codes to process (None = all).
        seed_path: Path to existing emi_material_db_seed.json for offline mode.
        output_path: Where to write the output JSON.
        use_network: If True, attempt to download CSVs from Fair-Rite website.
        scrape_charts: If True, scrape chart images from material pages.

    Returns:
        The complete vendor database dict.
    """
    accessed_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    entries = FAIR_RITE_CATALOG

    if materials:
        entries = [e for e in entries if e["code"] in materials]

    results: dict[str, Any] = {}
    stats = {"total": 0, "complete": 0, "partial": 0, "seed": 0, "errors": []}

    for entry in entries:
        stats["total"] += 1
        code = entry["code"]
        material_id = f"FR_{code}"

        print(f"  Processing Fair-Rite {code}...", end=" ")

        samples = None
        raw_csv_text = None  # Preserved for V&V Layer 1-2

        # Try network download first if enabled
        if use_network:
            import urllib.request

            csv_url = entry["csv_url"]
            for attempt in range(2):
                try:
                    req = urllib.request.Request(
                        csv_url,
                        headers={"User-Agent": "MaterialPipeline/1.0"}
                    )
                    with urllib.request.urlopen(req, timeout=15) as resp:
                        content_type = resp.headers.get("Content-Type", "")
                        raw_bytes = resp.read()
                        # Fair-Rite CSVs use latin-1 encoding (µ = 0xB5)
                        try:
                            raw_csv_text = raw_bytes.decode("utf-8-sig")
                        except UnicodeDecodeError:
                            raw_csv_text = raw_bytes.decode("latin-1")

                    # Detect if we got HTML instead of CSV (stale URL redirect)
                    if "text/html" in content_type or raw_csv_text.strip().startswith("<!"):
                        if attempt == 0:
                            print("got HTML (stale URL), discovering...", end=" ")
                            discovered = discover_csv_url(entry["page_url"])
                            if discovered:
                                csv_url = discovered
                                raw_csv_text = None
                                continue
                        print("CSV URL not found on page, trying seed...", end=" ")
                        raw_csv_text = None
                        break

                    samples = parse_fair_rite_csv(raw_csv_text)
                    if samples:
                        print(f"downloaded {len(samples)} points", end=" ")
                        # Save raw source to staging for V&V audit trail
                        staging_dir = Path(output_path).parent.parent / "staging" / "fair_rite"
                        staging_dir.mkdir(parents=True, exist_ok=True)
                        raw_path = staging_dir / f"FR_{code}_raw.csv"
                        raw_path.write_text(raw_csv_text, encoding="utf-8")
                    else:
                        print("CSV parsed to 0 rows, trying seed...", end=" ")
                        raw_csv_text = None
                    break

                except Exception as e:
                    if attempt == 0:
                        # Try discovering the real URL from the data sheet page
                        print(f"download failed, discovering...", end=" ")
                        discovered = discover_csv_url(entry["page_url"])
                        if discovered:
                            csv_url = discovered
                            continue
                    print(f"download failed ({e}), trying seed...", end=" ")
                    break

        # Fall back to seed database
        if not samples and seed_path:
            samples = load_existing_csv_from_seed(seed_path, code)
            if samples:
                print(f"loaded {len(samples)} points from seed", end=" ")

        if not samples:
            print("no data available", end=" ")

        record = build_material_record(entry, samples, accessed_date, raw_csv_text)

        # Chart scraping (requires network)
        if scrape_charts and use_network:
            staging_dir = Path(output_path).parent.parent / "staging" / "fair_rite"
            charts = scrape_material_charts(entry["page_url"], code, staging_dir)
            if charts:
                record.setdefault("chart_images", [])
                for chart_info in charts:
                    record["chart_images"].append({
                        "chart_type": chart_info["chart_type"],
                        "source_url": chart_info["url"],
                        "local_path": chart_info["local_path"],
                    })
                print(f"  scraped {len(charts)} chart(s)", end=" ")

        results[material_id] = record
        stats[record["record_status"]] += 1
        print(f"-> {record['record_status']}")

    # Build output
    db = {
        "schema_version": "1.0.0",
        "generated_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "vendor": "Fair-Rite",
        "stats": stats,
        "materials": results,
    }

    if output_path:
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        Path(output_path).write_text(json.dumps(db, indent=2), encoding="utf-8")
        print(f"\nWrote {output_path}")
        print(f"  {stats['complete']} complete, {stats['partial']} partial, "
              f"{stats['seed']} seed-only, {len(stats['errors'])} errors")

    return db


def main():
    parser = argparse.ArgumentParser(description="Fair-Rite CSV adapter")
    parser.add_argument("--materials", nargs="*",
                        help="Material codes to process (default: all)")
    parser.add_argument("--seed", default=None,
                        help="Path to emi_material_db_seed.json for offline mode")
    parser.add_argument("--output", default="output/vendor/fair_rite.json",
                        help="Output JSON path")
    parser.add_argument("--network", action="store_true",
                        help="Attempt to download CSVs from Fair-Rite website")
    parser.add_argument("--scrape-charts", action="store_true",
                        help="Scrape chart images from material data sheet pages (requires --network)")
    args = parser.parse_args()

    print("Fair-Rite CSV adapter")
    print("=" * 40)
    run_adapter(
        materials=args.materials,
        seed_path=args.seed,
        output_path=args.output,
        use_network=args.network,
        scrape_charts=args.scrape_charts,
    )


if __name__ == "__main__":
    main()
