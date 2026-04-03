# Material Ingestion Pipeline

Converts magnetic material data from vendor sources (CSVs, web tools, PDFs) into a unified JSON database and React-importable JS module for the EMI Filter Design App. Every record passes through a 5-layer verification and validation (V&V) framework before entering the database.

## Quick start

```bash
# Full pipeline using existing seed data (no network needed)
python run_pipeline.py \
  --seed-db /path/to/emi_material_db_seed.json \
  --tdk-seed /path/to/tdk_material_catalog_seed.json \
  --vv-report output/vv_report.json

# With live Fair-Rite CSV downloads
python run_pipeline.py --network --seed-db ...

# With TDK MDT scraping (requires: playwright install chromium)
python run_pipeline.py --mdt --tdk-seed ... --network

# Validate an existing database
python run_pipeline.py --validate-only output/material_db.json

# Just Fair-Rite, EMI-relevant TDK only
python run_pipeline.py --fair-rite-only --emi-only --seed-db ...
```

## Pipeline stages

```
  ┌──────────────────────────────────────────────┐
  │ Step 1: Extraction (per-vendor adapters)      │
  │   fair_rite_csv.py  → vendor/fair_rite.json   │
  │   tdk_catalog_seed.py → vendor/tdk.json       │
  │   tdk_mdt.py        → vendor/tdk_mdt.json     │
  │   pdf_digitize.py   → vendor/<material>.json   │
  ├──────────────────────────────────────────────┤
  │ Step 2: V&V per vendor (5-layer checks)       │
  │   L1 SHA-256 integrity                        │
  │   L2 Structural identity (point-by-point)     │
  │   L3 Curve similarity (Fréchet, DTW, area)    │
  │   L4 Physics (KK, Snoek, energy conservation) │
  │   L5 Cross-source corroboration               │
  ├──────────────────────────────────────────────┤
  │ Step 3: Merge + JS generation                 │
  │   → material_db.json + material_db.js         │
  ├──────────────────────────────────────────────┤
  │ Step 4: Final V&V on merged database          │
  │   → vv_report.json                            │
  └──────────────────────────────────────────────┘
```

## Adapters

### Fair-Rite CSV (`adapters/fair_rite_csv.py`)
Downloads complex permeability CSV files directly from Fair-Rite's material data sheet pages. This is the highest-quality source (vendor-provided digital data). Supports offline mode using seed database.

### TDK catalog seed (`adapters/tdk_catalog_seed.py`)
Converts the existing TDK catalog JSON into the unified schema as seed records (metadata only, no curves). Flags the 13 EMI-priority materials for ingestion.

### TDK MDT scraper (`adapters/tdk_mdt.py`)
Uses Playwright browser automation to scrape TDK's Magnetic Design Tool web application. Extracts digitized chart data from the Highcharts JavaScript objects rendered in the browser. Requires `playwright install chromium` before first use.

### PDF digitizer (`adapters/pdf_digitize.py`)
Renders PDF datasheet pages to high-resolution images and sends them to Claude's vision API for chart identification and data point extraction. This is the Tier 2 path used when structured data isn't available. Requires `pip install pymupdf` and an Anthropic API key.

```bash
# Digitize a specific PDF
python adapters/pdf_digitize.py --pdf N30_datasheet.pdf --material TDK_N30

# Discover PDFs from a catalog page
python adapters/pdf_digitize.py --discover "https://www.tdk-electronics.tdk.com/en/529404/..."

# Download and digitize from URL
python adapters/pdf_digitize.py --url https://tdk.com/.../pdf-n30.pdf --material TDK_N30
```

## V&V framework

The verification module (`processing/verification.py`) implements 5 layers of checks:

| Layer | Name | What it catches |
|-------|------|-----------------|
| L1 | Bit-level integrity | SHA-256 hash of raw source; detects file corruption |
| L2 | Structural identity | Point-by-point exact float match; detects dropped/swapped data |
| L3 | Curve similarity | Fréchet distance, DTW, area metrics; detects extraction drift |
| L4 | Physics constraints | Kramers-Kronig, Snoek's limit, energy conservation; detects bad data |
| L5 | Cross-source corroboration | Compares independent sources; detects wrong source assignment |

V&V runs automatically at two points: after each vendor extraction and on the final merged database. A JSON report is generated with every check result, enabling audit trails.

## React app integration

```jsx
import { getMaterial, getComplexPermeability, listMaterials,
         getChokeImpedance, getAvailableCurves } from './material_db.js';

// Get µ'(f) and µ''(f) at 1 MHz for Fair-Rite 43
const mu = getComplexPermeability("FR_43", 1e6);
// → { muPrime: 851.4, muDoublePrime: 48.0 }

// List all EMI materials with real curve data
const emiMats = listMaterials({ tag: "EMI_suppression", minStatus: "partial" });

// Compute choke impedance from complex permeability + core geometry
const Z = getChokeImpedance("FR_43", 1e6, 10, 13.1e-6, 27.9e-3);
// → { Z_mag, Z_phase_deg, L_H, R_core }

// Check what curves are available for a material
const curves = getAvailableCurves("FR_43");
// → ["complex_perm_vs_f"]
```

## Current database status

| Vendor | Materials | With curves | Source |
|--------|-----------|-------------|--------|
| Fair-Rite | 16 | 6 (31, 43, 52, 61, 79, 80) | Seed CSV data |
| TDK | 13 (EMI subset) | 0 | Catalog seed only |

## Dependencies

```bash
pip install numpy similaritymeasures       # V&V framework
pip install playwright && playwright install chromium  # TDK MDT scraper
pip install pymupdf anthropic              # PDF digitizer
```

## Architecture document

See `material_ingestion_pipeline.md` for the full design: unified schema specification, source tier strategy, phased implementation plan, and the "point at a page" workflow.
