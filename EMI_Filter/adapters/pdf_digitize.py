#!/usr/bin/env python3
"""
PDF chart digitization adapter using Claude's vision API.

Extracts numerical data from chart images in vendor datasheets by:
1. Rendering PDF pages to high-resolution images
2. Sending images to Claude API with structured extraction prompts
3. Parsing and validating the extracted data
4. Converting to unified material database schema

This is the Tier 2 extraction path — used when structured data (CSV, API)
is not available from the vendor.

Prerequisites:
    pip install anthropic pymupdf   # pymupdf is the 'fitz' library

Usage:
    python pdf_digitize.py --pdf path/to/N30_datasheet.pdf --material TDK_N30
    python pdf_digitize.py --url https://tdk.com/.../pdf-n30.pdf --material TDK_N30
    python pdf_digitize.py --batch-dir ./staging/pdfs/
"""

from __future__ import annotations
import base64
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# ── PDF rendering ──

def render_pdf_pages(pdf_path: str, dpi: int = 250, max_pages: int = 12) -> list[dict[str, Any]]:
    """
    Render each page of a PDF to a PNG image at high resolution.

    Returns list of {page_num, width, height, png_bytes, png_base64}.
    """
    try:
        import fitz  # pymupdf
    except ImportError:
        print("ERROR: pymupdf not installed. Run: pip install pymupdf")
        sys.exit(1)

    doc = fitz.open(pdf_path)
    pages = []

    for i in range(min(len(doc), max_pages)):
        page = doc[i]
        # High DPI for readable axis labels
        zoom = dpi / 72.0
        mat = fitz.Matrix(zoom, zoom)
        pix = page.get_pixmap(matrix=mat, alpha=False)
        png_bytes = pix.tobytes("png")
        png_b64 = base64.standard_b64encode(png_bytes).decode("ascii")

        pages.append({
            "page_num": i + 1,
            "width": pix.width,
            "height": pix.height,
            "png_bytes": png_bytes,
            "png_base64": png_b64,
        })

    doc.close()
    return pages


# ── Claude API interaction ──

CLASSIFY_PROMPT = """You are analyzing a page from a magnetic material datasheet.

Look at this image and determine:
1. Does this page contain any charts/graphs with plotted data curves?
2. If yes, for each chart identify:
   - What quantity is on the X-axis (e.g., frequency, temperature, flux density)
   - What quantity is on the Y-axis (e.g., complex permeability, power loss, impedance)
   - X-axis scale type (linear or logarithmic)
   - Y-axis scale type (linear or logarithmic)
   - X-axis range (min and max with units)
   - Y-axis range (min and max with units)
   - Number of distinct curves/traces
   - What each curve represents (e.g., "µ' at 25°C", "Pv at 100mT")

Respond ONLY with a JSON object, no markdown backticks or other text:
{
  "has_charts": true/false,
  "has_tables": true/false,
  "page_description": "brief text",
  "charts": [
    {
      "chart_type": "complex_permeability | power_loss | init_permeability | amplitude_permeability | dc_bias | impedance | other",
      "x_axis": {"quantity": "...", "unit": "...", "scale": "log|linear", "min": ..., "max": ...},
      "y_axis": {"quantity": "...", "unit": "...", "scale": "log|linear", "min": ..., "max": ...},
      "curves": [
        {"label": "...", "description": "..."}
      ]
    }
  ]
}"""

EXTRACT_PROMPT_TEMPLATE = """You are extracting numerical data from a chart in a magnetic material datasheet for {material_id}.

This chart shows: {chart_description}
X-axis: {x_axis_desc} ({x_scale})
Y-axis: {y_axis_desc} ({y_scale})

CAREFULLY read the axis scales, tick marks, and grid lines. Extract data points for EACH curve
visible in the chart. Aim for 20-50 points per curve, spaced roughly evenly in the axis scale
(evenly in log-space for logarithmic axes).

For each point, read the x-value from the horizontal position and the y-value from the vertical
position as precisely as you can from the grid lines and tick marks.

Respond ONLY with a JSON object, no markdown backticks:
{{
  "material": "{material_id}",
  "chart_type": "{chart_type}",
  "curves": [
    {{
      "label": "curve label",
      "x_unit": "{x_unit}",
      "y_unit": "{y_unit}",
      "points": [
        [x_value, y_value],
        [x_value, y_value],
        ...
      ]
    }}
  ],
  "extraction_confidence": "high|medium|low",
  "notes": "any issues or uncertainties"
}}"""


def classify_page(page_b64: str, api_key: str | None = None) -> dict[str, Any]:
    """Send a page image to Claude for chart classification."""
    try:
        import anthropic
    except ImportError:
        return {"error": "anthropic library not installed"}

    client = anthropic.Anthropic(api_key=api_key) if api_key else anthropic.Anthropic()

    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=2000,
        messages=[{
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {"type": "base64", "media_type": "image/png", "data": page_b64}
                },
                {"type": "text", "text": CLASSIFY_PROMPT}
            ]
        }]
    )

    text = message.content[0].text.strip()
    # Clean any markdown fencing
    text = re.sub(r'^```json\s*', '', text)
    text = re.sub(r'\s*```$', '', text)
    return json.loads(text)


def extract_chart_data(
    page_b64: str,
    material_id: str,
    chart_info: dict[str, Any],
    api_key: str | None = None
) -> dict[str, Any]:
    """Send a page image to Claude for detailed data extraction from a specific chart."""
    try:
        import anthropic
    except ImportError:
        return {"error": "anthropic library not installed"}

    client = anthropic.Anthropic(api_key=api_key) if api_key else anthropic.Anthropic()

    x_ax = chart_info.get("x_axis", {})
    y_ax = chart_info.get("y_axis", {})

    prompt = EXTRACT_PROMPT_TEMPLATE.format(
        material_id=material_id,
        chart_description=f"{chart_info.get('chart_type', 'unknown')} chart",
        x_axis_desc=f"{x_ax.get('quantity', '?')} in {x_ax.get('unit', '?')}",
        y_axis_desc=f"{y_ax.get('quantity', '?')} in {y_ax.get('unit', '?')}",
        x_scale=x_ax.get("scale", "linear"),
        y_scale=y_ax.get("scale", "linear"),
        chart_type=chart_info.get("chart_type", "unknown"),
        x_unit=x_ax.get("unit", ""),
        y_unit=y_ax.get("unit", ""),
    )

    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=8000,
        messages=[{
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {"type": "base64", "media_type": "image/png", "data": page_b64}
                },
                {"type": "text", "text": prompt}
            ]
        }]
    )

    text = message.content[0].text.strip()
    text = re.sub(r'^```json\s*', '', text)
    text = re.sub(r'\s*```$', '', text)
    return json.loads(text)


# ── Schema conversion ──

CHART_TYPE_TO_CURVE_NAME = {
    "complex_permeability": "complex_perm_vs_f",
    "power_loss": "core_loss_vs_f",
    "init_permeability": "mu_i_vs_temperature",
    "amplitude_permeability": "mu_a_vs_B",
    "dc_bias": "dc_bias_perm_drop",
    "impedance": "impedance_vs_f",
}

CHART_TYPE_TO_X_QUANTITY = {
    "complex_permeability": ("frequency", "Hz"),
    "power_loss": ("frequency", "Hz"),
    "init_permeability": ("temperature", "C"),
    "amplitude_permeability": ("flux_density", "mT"),
    "dc_bias": ("field_strength", "A/m"),
    "impedance": ("frequency", "Hz"),
}


def convert_extraction_to_curve(
    extraction: dict[str, Any],
    material_id: str,
    pdf_url: str,
    page_num: int,
) -> dict[str, dict[str, Any]]:
    """
    Convert Claude's extraction output to unified schema curve blocks.

    Returns dict of {curve_name: curve_block}.
    """
    chart_type = extraction.get("chart_type", "unknown")
    curves_extracted = extraction.get("curves", [])
    confidence = extraction.get("extraction_confidence", "medium")

    if not curves_extracted:
        return {}

    result = {}
    curve_name = CHART_TYPE_TO_CURVE_NAME.get(chart_type, f"pdf_{chart_type}")
    x_info = CHART_TYPE_TO_X_QUANTITY.get(chart_type, ("frequency", "Hz"))

    if chart_type == "complex_permeability" and len(curves_extracted) >= 2:
        # Merge µ' and µ'' into single samples array
        mu_prime_curve = curves_extracted[0]
        mu_dprime_curve = curves_extracted[1] if len(curves_extracted) > 1 else None

        prime_pts = {p[0]: p[1] for p in mu_prime_curve.get("points", [])}
        dprime_pts = {p[0]: p[1] for p in (mu_dprime_curve.get("points", []) if mu_dprime_curve else [])}

        common_x = sorted(set(prime_pts.keys()) & set(dprime_pts.keys()))
        if not common_x:
            # Use µ' x-values and try to match closest µ'' points
            common_x = sorted(prime_pts.keys())

        samples = []
        for x in common_x:
            mp = prime_pts.get(x)
            mpp = dprime_pts.get(x)
            if mp is not None and mpp is not None:
                samples.append([float(x), float(mp), float(mpp)])

        if samples:
            result[curve_name] = {
                "description": f"Complex permeability vs frequency for {material_id} (PDF digitized)",
                "x_quantity": x_info[0],
                "x_unit": x_info[1],
                "y_quantities": ["mu_prime", "mu_double_prime"],
                "y_units": ["1", "1"],
                "test_conditions": {"temperature_C": 25, "representation": "series"},
                "samples": samples,
                "source": {
                    "method": "pdf_digitize_llm",
                    "url": pdf_url,
                    "page": page_num,
                    "accessed_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                    "confidence": confidence,
                    "notes": f"Digitized from PDF chart by Claude vision API. "
                             f"{extraction.get('notes', '')}",
                    "raw_point_count": len(samples),
                }
            }
    else:
        # Generic single-quantity curve
        for ci, curve_ext in enumerate(curves_extracted):
            points = curve_ext.get("points", [])
            if len(points) < 3:
                continue

            samples = [[float(p[0]), float(p[1])] for p in points]
            samples.sort(key=lambda s: s[0])

            suffix = f"_{ci}" if ci > 0 else ""
            result[f"{curve_name}{suffix}"] = {
                "description": f"{chart_type} for {material_id} ({curve_ext.get('label', 'curve')}) (PDF digitized)",
                "x_quantity": x_info[0],
                "x_unit": x_info[1],
                "y_quantities": [curve_ext.get("label", f"y_{ci}")],
                "y_units": [curve_ext.get("y_unit", "1")],
                "test_conditions": {},
                "samples": samples,
                "source": {
                    "method": "pdf_digitize_llm",
                    "url": pdf_url,
                    "page": page_num,
                    "accessed_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                    "confidence": confidence,
                    "notes": f"Digitized by Claude. {extraction.get('notes', '')}",
                    "raw_point_count": len(samples),
                }
            }

    return result


# ── Full PDF processing pipeline ──

def process_pdf(
    pdf_path: str,
    material_id: str,
    pdf_url: str = "",
    api_key: str | None = None,
    dpi: int = 250,
    staging_dir: str | None = None,
) -> dict[str, Any]:
    """
    Full PDF → data pipeline:
    1. Render pages to images
    2. Classify each page (find charts)
    3. Extract data from each chart
    4. Convert to schema format
    5. Return curves dict ready for merging

    Returns {curves: {...}, log: [...], source_hash: "..."}.
    """
    print(f"  Processing PDF: {Path(pdf_path).name}")

    # Hash the source PDF for V&V Layer 1
    with open(pdf_path, "rb") as f:
        source_hash = hashlib.sha256(f.read()).hexdigest()

    # Render pages
    print(f"    Rendering pages at {dpi} DPI...", end=" ")
    pages = render_pdf_pages(pdf_path, dpi=dpi)
    print(f"{len(pages)} pages")

    # Save rendered images if staging dir provided
    if staging_dir:
        img_dir = Path(staging_dir) / material_id
        img_dir.mkdir(parents=True, exist_ok=True)
        for pg in pages:
            (img_dir / f"page_{pg['page_num']:02d}.png").write_bytes(pg["png_bytes"])

    all_curves = {}
    log = []

    # Classify each page
    for pg in pages:
        page_num = pg["page_num"]
        print(f"    Page {page_num}: classifying...", end=" ")

        classification = classify_page(pg["png_base64"], api_key)
        log.append({"page": page_num, "classification": classification})

        if not classification.get("has_charts"):
            print("no charts")
            continue

        charts = classification.get("charts", [])
        print(f"{len(charts)} chart(s) found")

        # Extract data from each chart
        for ci, chart_info in enumerate(charts):
            chart_type = chart_info.get("chart_type", "unknown")
            print(f"      Chart {ci+1} ({chart_type}): extracting...", end=" ")

            extraction = extract_chart_data(
                pg["png_base64"], material_id, chart_info, api_key
            )
            log.append({"page": page_num, "chart": ci, "extraction": extraction})

            # Convert to schema
            curves = convert_extraction_to_curve(
                extraction, material_id, pdf_url or pdf_path, page_num
            )

            for name, block in curves.items():
                n_pts = len(block.get("samples", []))
                print(f"✓ {n_pts} points", end=" ")
                if name in all_curves:
                    # Keep the extraction with more points
                    if n_pts > len(all_curves[name].get("samples", [])):
                        all_curves[name] = block
                else:
                    all_curves[name] = block

            if not curves:
                print("✗ no usable data")
            else:
                print()

    return {
        "curves": all_curves,
        "log": log,
        "source_hash": source_hash,
        "pages_processed": len(pages),
    }


# ── Batch URL scraper ("point at a page") ──

def discover_pdfs_from_url(catalog_url: str) -> list[dict[str, str]]:
    """
    Scrape a vendor catalog page for PDF download links.

    Returns list of {url, filename, material_guess}.
    """
    import urllib.request
    from html.parser import HTMLParser

    class PDFLinkParser(HTMLParser):
        def __init__(self):
            super().__init__()
            self.links = []

        def handle_starttag(self, tag, attrs):
            if tag == "a":
                href = dict(attrs).get("href", "")
                if href.lower().endswith(".pdf"):
                    self.links.append(href)

    req = urllib.request.Request(catalog_url, headers={"User-Agent": "MaterialPipeline/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        html = resp.read().decode("utf-8", errors="replace")

    parser = PDFLinkParser()
    parser.feed(html)

    results = []
    for link in parser.links:
        # Make absolute URL
        if link.startswith("/"):
            from urllib.parse import urlparse
            parsed = urlparse(catalog_url)
            link = f"{parsed.scheme}://{parsed.netloc}{link}"
        elif not link.startswith("http"):
            link = catalog_url.rstrip("/") + "/" + link

        filename = link.split("/")[-1]

        # Try to guess material from filename (e.g., "pdf-n30.pdf" → "N30")
        mat_match = re.search(r'(?:pdf[_-]?)([a-zA-Z]\d+)', filename, re.IGNORECASE)
        material_guess = mat_match.group(1).upper() if mat_match else None

        results.append({
            "url": link,
            "filename": filename,
            "material_guess": material_guess,
        })

    return results


# ── CLI ──

def main():
    import argparse
    parser = argparse.ArgumentParser(description="PDF chart digitizer")
    parser.add_argument("--pdf", help="Path to a single PDF datasheet")
    parser.add_argument("--url", help="URL to download a PDF from")
    parser.add_argument("--material", required=True, help="Material ID (e.g., TDK_N30)")
    parser.add_argument("--api-key", help="Anthropic API key (or set ANTHROPIC_API_KEY env var)")
    parser.add_argument("--dpi", type=int, default=250, help="Rendering DPI")
    parser.add_argument("--staging-dir", default="staging/pdf_pages")
    parser.add_argument("--output", help="Output JSON path")
    parser.add_argument("--discover", help="URL to scrape for PDF links (batch mode)")
    args = parser.parse_args()

    if args.discover:
        print(f"Discovering PDFs from {args.discover}...")
        pdfs = discover_pdfs_from_url(args.discover)
        for p in pdfs:
            print(f"  {p['filename']:40s} → material: {p.get('material_guess', '?')}")
        print(f"\n{len(pdfs)} PDFs found")
        return

    if not args.pdf and not args.url:
        parser.error("Either --pdf or --url is required")

    pdf_path = args.pdf
    pdf_url = args.url or ""

    if args.url and not args.pdf:
        # Download PDF
        import urllib.request
        import tempfile
        print(f"Downloading {args.url}...")
        pdf_path = Path(args.staging_dir) / f"{args.material}.pdf"
        pdf_path.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(args.url, str(pdf_path))
        print(f"  Saved to {pdf_path}")

    result = process_pdf(
        pdf_path=str(pdf_path),
        material_id=args.material,
        pdf_url=pdf_url,
        api_key=args.api_key,
        dpi=args.dpi,
        staging_dir=args.staging_dir,
    )

    print(f"\n  Extracted {len(result['curves'])} curve families")
    for name, block in result["curves"].items():
        print(f"    {name}: {len(block['samples'])} points "
              f"({block['source']['confidence']} confidence)")

    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(json.dumps(result, indent=2, default=str))
        print(f"\n  Wrote {args.output}")


if __name__ == "__main__":
    main()
