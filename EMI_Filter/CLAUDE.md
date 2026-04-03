# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Interactive browser-based differential-mode (DM) EMI filter design tool for power electronics engineers. Predicts whether an LC filter will pass conducted emissions standards for a given DC-DC converter topology. Backed by a Python material ingestion pipeline that extracts vendor data into a unified database.

## Architecture

**Two major subsystems:**

1. **Frontend — `emi-filter-v7.jsx`** (~2,800 LOC single-file React/JSX artifact)
   - Runs in Claude.ai artifact sandbox or locally via Vite dev server (`my-app/`)
   - 74 useState hooks, 52 pure physics functions, 5 Recharts interactive charts
   - Layout: data tables (lines 5–170) → physics functions (170–688) → UI components (688–803) → EqPanel (803–1076) → main App (1077+)
   - Complex numbers as `[real, imaginary]` 2-element arrays throughout
   - All physics functions are pure (no side effects, no state access) — testable independently

2. **Backend — Python material pipeline**
   - `run_pipeline.py` — orchestrator (`python run_pipeline.py --help`)
   - `adapters/fair_rite_csv.py` — Fair-Rite CSV download adapter (16 materials, Tier 1 source)
   - `adapters/tdk_mdt.py` — Playwright browser automation for TDK MDT (13 EMI-priority materials)
   - `adapters/tdk_catalog_seed.py` — TDK catalog JSON to unified schema (seed records, no curves)
   - `adapters/pdf_digitize.py` — Claude vision API PDF chart extraction (Tier 2 fallback)
   - `adapters/cv_digitize.py` — OpenCV chart digitizer: extracts curves from chart images via color filtering, column scanning, and OCR axis calibration. Supports log-log, semilog, and linear charts. 9 chart configs for different Fair-Rite chart types. Key functions: `process_chart_image()`, `create_black_curve_mask()`, `auto_calibrate_axes()`, `column_scan_extract()`
   - `processing/steinmetz_fit.py` — Fits P_v = k * f^alpha * B^beta from core loss data. Includes per-frequency validation and cross-frequency alpha consistency checking
   - `processing/verification.py` — self-contained 5-layer V&V framework (L1 source hash, L2 samples hash, L3 curve similarity, L4 physics, L5 cross-source)
   - `processing/merge_and_generate.py` — merges vendor databases + generates JS module
   - Output: `output/material_db.json` + `output/material_db.js` (React-importable module)
   - Chart staging: `output/staging/fair_rite/` — 152 downloaded chart images (perm_vs_temp, flux_vs_temp, core_loss, bh_curve, etc.)
   - V&V hashes: adapters store `source_sha256` and `samples_sha256` in each curve's source block; verification recomputes and compares (sorted, 10 sig fig canonical form)

## Build & Run Commands

### Frontend (Vite React app in `my-app/`)
```bash
cd my-app && npm install      # first time
cd my-app && npm run dev       # dev server
cd my-app && npm run build     # production build
cd my-app && npx eslint .      # lint
```

### Material Pipeline
```bash
# Full pipeline with seed data (offline)
python run_pipeline.py --seed-db /path/to/seed.json --vv-report output/vv_report.json

# With live network downloads
python run_pipeline.py --network --seed-db /path/to/seed.json

# Full pipeline with chart digitization and Steinmetz fitting
python run_pipeline.py --network --fair-rite-only --steinmetz

# Scrape new chart images from Fair-Rite website (requires network)
python run_pipeline.py --network --scrape-charts --fair-rite-only --steinmetz

# Validate existing database only
python run_pipeline.py --validate-only output/material_db.json
```

### Python Dependencies (no requirements.txt — install manually)
```bash
pip install numpy similaritymeasures       # V&V framework
pip install opencv-python pytesseract      # CV digitizer (chart extraction)
pip install playwright && playwright install chromium  # TDK MDT scraper
pip install pymupdf anthropic              # PDF digitizer
```
Tesseract OCR must be installed separately: `C:\Program Files\Tesseract-OCR\tesseract.exe`

## Locked Design Decisions

Do not change without explicit discussion:
- SRF uses selectable L reference (unbias/bias/manual), not hardcoded
- Pass/fail is purely IL-driven; SRF/3 is advisory only
- Per-harmonic pass/fail across full spectrum determines overall PASS/FAIL
- Toroid Cw = Mag-Inc geometry + k factor (k=0.025 default, calibrated against measured 55350/57T/17AWG data)
- Two-stage IL uses cascaded voltage dividers (proper stage interaction), not dB sum
- Emission chart harmonic dots are primary, envelope is secondary — only dots determine pass/fail
- SPICE import uses filter parameter fsw for harmonic extraction, not auto-detected
- Middlebrook peak Z_out tracked above fc₁/5 to avoid source impedance plateau
- Damping recommendation: Rd = Z₀ = √(L/C), Cd = 4×C
- CISPR 25 voltage limits converted to dBµA via LISN impedance

## UI Patterns (for `emi-filter-v7.jsx`)

Use these existing shorthand components — do not introduce new patterns:
- `<IR lbl="Label" val={state} set={setState} unit="units" min={0} max={100} step={1}/>` — numeric input
- `<Tog lbl="Label" val={bool} set={setBool} detail="desc"/>` — toggle
- `<Sec title="TITLE" accent="#color">...</Sec>` — section container
- `<MC lbl="Label" val="formatted" status="pass|warn|fail"/>` — metric card
- `<W msg="message" col="#color"/>` — warning banner

Color convention: gold (#f0b44c) = primary/pass, green (#33cc55) = good, red (#ff4444) = fail, blue (#4488ff) = wire/Cw, purple (#cc88ff) = damping, orange (#ff8844) = DUT/source, cyan (#44dddd) = QP detector.

Dark theme: background #080808, chart bg #0c0c0c, text #ccc/#888/#444, borders #1a1a1a/#2a2a2a, font IBM Plex Mono.

## Key Technical Reference

- `emi-filter-handoff.md` — complete technical spec: all 52 physics functions, 74 state variables, data flow, known issues, and future roadmap
- `material_ingestion_pipeline.md` — unified schema spec, V&V framework details, phased implementation plan
- `README.md` — pipeline quick start and adapter descriptions

## Known Issues

- Dowell FR may overestimate for round wire in toroid (assumes infinite-width foil)
- Two separate damping networks (Middlebrook + EMI) should be consolidated into single per-stage control
- `dutyCy` and `spiceFswOvr` state variables are orphaned — safe to remove
- Core loss always uses analytical Ipp even when SPICE import is active
