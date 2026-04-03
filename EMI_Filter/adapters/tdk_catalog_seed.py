#!/usr/bin/env python3
"""
TDK catalog seed adapter.

Converts the existing TDK catalog seed JSON into the unified material schema.
These are seed-only records (no curve data yet) — the MDT scraper or PDF
digitization pipeline fills in the curves later.

Also flags which materials are EMI-relevant (priority for ingestion).

Usage:
    python tdk_catalog_seed.py --input ../../tdk_material_catalog_seed.json
    python tdk_catalog_seed.py --emi-only  # Only EMI-relevant materials
"""

from __future__ import annotations
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# EMI-relevant TDK materials — these get ingested first
EMI_PRIORITY_MATERIALS = {
    "N30", "T35", "T36", "T37", "T65",
    "E11", "E12", "E13", "E14", "E16", "E19", "E21",
    "K10",
}

# Map TDK catalog categories to unified schema families and tags
CATEGORY_MAP: dict[str, dict[str, Any]] = {
    "Power/Transformer": {
        "family": "power ferrite",
        "tags": ["power", "transformer"],
    },
    "Power/Transformer; Output choke": {
        "family": "power ferrite",
        "tags": ["power", "transformer", "output_choke"],
    },
    "EMI suppression (NiZn)": {
        "family": "EMI ferrite",
        "tags": ["EMI_suppression", "NiZn"],
    },
    "Current-compensated choke / EMI filter": {
        "family": "EMI ferrite",
        "tags": ["current_compensated_choke", "EMI_filter", "common_mode"],
    },
    "Current-compensated choke / EMI filter; Data-line filter": {
        "family": "EMI ferrite",
        "tags": ["current_compensated_choke", "EMI_filter", "data_line"],
    },
    "Filter choke": {
        "family": "EMI ferrite",
        "tags": ["filter_choke", "EMI_filter"],
    },
    "Data-line filter": {
        "family": "EMI ferrite",
        "tags": ["data_line", "EMI_filter"],
    },
    "LAN / Data-line": {
        "family": "EMI ferrite",
        "tags": ["data_line", "LAN"],
    },
}


def guess_chemistry(material_id: str, category: str) -> str:
    """Infer chemistry from material ID prefix and category."""
    if material_id.startswith("K") or material_id.startswith("E"):
        return "NiZn"
    if "NiZn" in category:
        return "NiZn"
    # Default TDK power and EMI ferrites are MnZn
    return "MnZn"


def convert_seed_entry(entry: dict[str, Any]) -> dict[str, Any]:
    """Convert a TDK catalog seed entry to unified schema format."""
    mat_id = entry["id"]
    material_id = f"TDK_{mat_id}"
    category = entry.get("category", "")
    cat_info = CATEGORY_MAP.get(category, {"family": "power ferrite", "tags": []})

    is_emi = mat_id in EMI_PRIORITY_MATERIALS
    tags = list(cat_info["tags"])
    if is_emi and "EMI_filter" not in tags:
        tags.append("EMI_filter")

    properties_ref: dict[str, Any] = {
        "reference_temperature_C": 25,
    }
    if entry.get("mu_i"):
        properties_ref["mu_i"] = entry["mu_i"]

    record = {
        "material_id": material_id,
        "vendor": "TDK Electronics",
        "vendor_material_code": mat_id,
        "family": cat_info["family"],
        "chemistry": guess_chemistry(mat_id, category),
        "application_tags": tags,
        "summary": entry.get("note", ""),
        "properties_ref": properties_ref,
        "curves": {},
        "fitted_models": {},
        "record_status": "seed",
        "last_updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "pdf_url": entry.get("pdf_url", ""),
        "mdt_url": "https://tools.tdk-electronics.tdk.com/mdt/index.php",
        "review_notes": [
            "Catalog seed only — no curve data yet.",
            f"Priority: {'EMI-relevant, ingest first' if is_emi else 'standard'}",
            f"Original category: {category}",
        ],
    }

    return record


def run_adapter(
    input_path: str,
    output_path: str | None = None,
    emi_only: bool = False,
) -> dict[str, Any]:
    """
    Main adapter entry point.
    """
    seed_data = json.loads(Path(input_path).read_text(encoding="utf-8"))
    materials_list = seed_data.get("materials", [])

    results: dict[str, Any] = {}
    stats = {"total": 0, "emi_priority": 0, "skipped": 0}

    for entry in materials_list:
        mat_id = entry.get("id", "")
        is_emi = mat_id in EMI_PRIORITY_MATERIALS

        if emi_only and not is_emi:
            stats["skipped"] += 1
            continue

        record = convert_seed_entry(entry)
        material_key = record["material_id"]
        results[material_key] = record

        stats["total"] += 1
        if is_emi:
            stats["emi_priority"] += 1

        print(f"  {'★' if is_emi else ' '} {material_key:12s} µ_i={entry.get('mu_i', '?'):>6}  "
              f"{record['family']:16s}  {', '.join(record['application_tags'][:3])}")

    db = {
        "schema_version": "1.0.0",
        "generated_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "vendor": "TDK Electronics",
        "stats": stats,
        "materials": results,
    }

    if output_path:
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        Path(output_path).write_text(json.dumps(db, indent=2), encoding="utf-8")
        print(f"\nWrote {output_path}")
        print(f"  {stats['total']} materials ({stats['emi_priority']} EMI-priority), "
              f"{stats['skipped']} skipped")

    return db


def main():
    parser = argparse.ArgumentParser(description="TDK catalog seed adapter")
    parser.add_argument("--input", required=True,
                        help="Path to tdk_material_catalog_seed.json")
    parser.add_argument("--output", default="output/vendor/tdk.json",
                        help="Output JSON path")
    parser.add_argument("--emi-only", action="store_true",
                        help="Only include EMI-relevant materials")
    args = parser.parse_args()

    print("TDK catalog seed adapter")
    print("=" * 40)
    run_adapter(args.input, args.output, args.emi_only)


if __name__ == "__main__":
    main()
