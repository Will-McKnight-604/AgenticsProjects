# Magnetic material ingestion pipeline — architecture

**For:** DM EMI Filter Design Tool (React/JSX)
**Date:** 2026-03-21
**Status:** Architecture design — ready for phased implementation

---

## 1. Problem statement

The EMI filter app currently has a seed database with six Fair-Rite suppression ferrites (with real complex-permeability curves from CSV) and catalog-level TDK entries (µ\_i and PDF links only — no fitted curves). To be production-useful, the app needs hundreds of material records with digitized µ′(f), µ″(f), core loss, DC bias, and temperature curves from multiple vendors.

Manufacturers publish this data in wildly different formats: Fair-Rite gives direct CSV downloads, TDK has a JavaScript web tool (MDT) with digitized data behind it, and most others ship only PDF datasheets with charts embedded as images. The pipeline must handle all three tiers gracefully.

---

## 2. Design principles

1. **Structured data first, PDF fallback second.** Any vendor that exposes numeric tables (CSV, API, or scrapeable web tool) takes priority over digitizing chart images. Chart digitization introduces ±3–8% error and should only be used when no better source exists, or for QA cross-checking.

2. **Provenance is non-negotiable.** Every data point in the database must trace back to its source: URL, page number, extraction method, extraction date, and a confidence tag. This is not bookkeeping — it is the only way to debug a curve that does not match measured impedance.

3. **Schema-first, adapter-second.** The unified JSON schema is defined before any extraction code is written. Every vendor adapter must produce records conforming to that schema. The app only talks to the schema.

4. **Claude-in-the-loop, not Claude-in-the-driver-seat.** The LLM assists with PDF table extraction, chart digitization guidance, and sanity checking — but a human must approve any record before it enters the production database.

5. **Incremental over monolithic.** Start with the 13 EMI-relevant TDK materials and the existing Fair-Rite set. Expand to Magnetics Inc powder cores, Würth, Micrometals, etc. once the core pipeline is validated.

---

## 3. Unified material record schema

This schema extends your existing `emi_material_db_seed.json` structure to cover all vendor types and curve families.

```jsonc
{
  "schema_version": "1.0.0",
  "materials": {
    "<material_id>": {
      // === Identity ===
      "material_id": "TDK_N30",          // vendor-prefixed unique key
      "vendor": "TDK Electronics",
      "vendor_material_code": "N30",      // as printed on datasheet
      "family": "EMI ferrite",            // one of: EMI ferrite, power ferrite,
                                          //   powder core, nanocrystalline
      "chemistry": "MnZn",               // MnZn, NiZn, MPP, Sendust, etc.
      "application_tags": [               // searchable tags for the app UI
        "current_compensated_choke",
        "EMI_filter",
        "data_line"
      ],
      "summary": "High-µ MnZn for CMC and EMI filter chokes, 4000 initial perm.",

      // === Scalar properties at reference conditions ===
      "properties_ref": {
        "mu_i": 4300,                     // initial permeability (dimensionless)
        "mu_i_tolerance_pct": 25,         // ±25%
        "saturation_flux_density_mT": 380,
        "residual_flux_density_mT": 200,
        "coercive_force_A_per_m": 12,
        "curie_temperature_C": 130,
        "resistivity_ohm_m": 1,
        "density_kg_per_m3": 4800,
        "reference_temperature_C": 25,
        "reference_frequency_Hz": 10000
      },

      // === Curve families ===
      // Each curve block is a named object with metadata + sample array.
      "curves": {
        "complex_perm_vs_f": {
          "description": "Complex permeability (series) vs frequency at 25°C",
          "x_quantity": "frequency",
          "x_unit": "Hz",
          "y_quantities": ["mu_prime", "mu_double_prime"],
          "y_units": ["1", "1"],
          "test_conditions": {
            "temperature_C": 25,
            "flux_density_mT": 0.25,
            "representation": "series",
            "core_shape": "R10 toroid"
          },
          "samples": [
            // [f_Hz, µ', µ'']
            [1e4, 4250, 15],
            [5e4, 4180, 85],
            [1e5, 4020, 210],
            [5e5, 2800, 1850],
            [1e6, 1600, 2900],
            [5e6, 180, 520],
            [1e7, 55, 160]
          ],
          "source": {
            "method": "csv_download",       // csv_download | mdt_scrape |
                                            //   pdf_digitize | manual
            "url": "https://fair-rite.com/43-material-data-sheet/",
            "accessed_date": "2026-03-21",
            "confidence": "high",           // high | medium | low
            "notes": "Direct CSV from Fair-Rite material page"
          }
        },

        "mu_i_vs_temperature": {
          "description": "Initial permeability vs temperature",
          "x_quantity": "temperature",
          "x_unit": "C",
          "y_quantities": ["mu_i"],
          "y_units": ["1"],
          "test_conditions": {
            "frequency_Hz": 10000,
            "flux_density_mT": 0.25
          },
          "samples": [
            // [T_C, µ_i]
            [-40, 2800],
            [0, 3600],
            [25, 4300],
            [60, 5200],
            [80, 5800],
            [100, 6500],
            [120, 3200],
            [130, 10]
          ],
          "source": {
            "method": "mdt_scrape",
            "url": "https://tools.tdk-electronics.tdk.com/mdt/index.php/initperm",
            "accessed_date": "2026-03-21",
            "confidence": "high",
            "notes": "Extracted from MDT chart data endpoint"
          }
        },

        "core_loss_vs_f": {
          "description": "Specific power loss vs frequency at 100mT, 25°C and 100°C",
          "x_quantity": "frequency",
          "x_unit": "Hz",
          "y_quantities": ["Pv_25C", "Pv_100C"],
          "y_units": ["kW/m3", "kW/m3"],
          "test_conditions": {
            "flux_density_mT": 100,
            "waveform": "sinusoidal"
          },
          "samples": [],
          "source": {
            "method": "pdf_digitize",
            "url": "https://www.tdk-electronics.tdk.com/download/...",
            "page": 3,
            "confidence": "medium",
            "notes": "Digitized from PDF chart, ~5% uncertainty on y-axis"
          }
        },

        "core_loss_vs_B": {
          "description": "Specific power loss vs flux density",
          "x_quantity": "flux_density",
          "x_unit": "mT",
          "y_quantities": ["Pv_25kHz", "Pv_100kHz", "Pv_500kHz"],
          "y_units": ["kW/m3", "kW/m3", "kW/m3"],
          "test_conditions": { "temperature_C": 100, "waveform": "sinusoidal" },
          "samples": [],
          "source": { "method": "pending", "confidence": "none" }
        },

        "dc_bias_perm_drop": {
          "description": "Relative permeability vs DC field strength",
          "x_quantity": "H_dc",
          "x_unit": "A/m",
          "y_quantities": ["mu_rev_relative"],
          "y_units": ["1"],
          "test_conditions": { "temperature_C": 25 },
          "samples": [],
          "source": { "method": "pending", "confidence": "none" }
        }
      },

      // === Fitted model parameters (computed from curves) ===
      "fitted_models": {
        "steinmetz_params": {
          "k": null,
          "alpha": null,
          "beta": null,
          "valid_f_range_Hz": [null, null],
          "valid_B_range_mT": [null, null],
          "valid_T_C": 100,
          "source_curve": "core_loss_vs_f",
          "fit_r_squared": null
        },
        "complex_perm_poles": {
          "description": "Rational-function fit for µ'(f) and µ''(f)",
          "model_type": "debye_relaxation",
          "poles": [],
          "fit_r_squared": null,
          "source_curve": "complex_perm_vs_f"
        }
      },

      // === Record metadata ===
      "record_status": "seed",            // seed | partial | complete | verified
      "last_updated": "2026-03-21T00:00:00Z",
      "pdf_url": "https://...",
      "mdt_url": "https://tools.tdk-electronics.tdk.com/mdt/index.php",
      "databook_revision": "2017",
      "review_notes": []
    }
  }
}
```

### Key schema decisions

**Why `samples` is a 2D array, not objects:** At 50–200 points per curve, object-per-point (`{f_Hz: ..., mu_prime: ...}`) bloats the JSON 3–4× compared to `[f, µ', µ'']`. The column definitions in `y_quantities` tell you what each column means. Your React app interpolates these arrays with a simple binary search — no object key lookups.

**Why vendor-prefixed IDs:** `TDK_N30` vs `FR_43` avoids collisions when two vendors have overlapping codes (e.g., "N30" exists in both TDK and some Chinese manufacturers).

**Why `record_status`:** The app UI can show a badge (seed / partial / complete / verified) so the engineer knows what level of trust to place in the data. A `seed` record has no curves yet — just catalog metadata. A `verified` record has been cross-checked against measurement or a second source.

---

## 4. Source tier architecture

### Tier 1 — Structured data (highest quality, lowest effort)

| Source | Vendor(s) | Format | Extraction method |
|--------|-----------|--------|-------------------|
| Fair-Rite material pages | Fair-Rite | CSV download links on each material page | HTTP GET → parse CSV → map to schema |
| TDK MDT web app | TDK (EPCOS) | JavaScript SPA with internal data endpoints | Puppeteer/Playwright → intercept XHR/fetch responses → extract JSON arrays |
| Würth REDEXPERT API | Würth | REST-ish endpoints behind their web tool | Similar browser automation approach |

**Fair-Rite CSV adapter** (simplest, build first):

```
1. Scrape material list page → get list of material codes (31, 43, 52, 61, 73, 75, 76, 77, 78, etc.)
2. For each material:
   a. Fetch the material data sheet page
   b. Find the CSV download link (every Fair-Rite material page has one)
   c. Download CSV: columns are f_Hz, mu_prime, mu_double_prime
   d. Parse scalar properties from the HTML table on the page
   e. Map to unified schema
   f. Set source.method = "csv_download", confidence = "high"
```

**TDK MDT adapter** (medium effort, high payoff):

The MDT is a PHP-backed JavaScript app. When you select a material and navigate to "Complex permeability vs. f", it renders a chart using internal data. The approach:

```
1. Use Playwright (headless browser) to load MDT
2. Navigate to complex permeability page
3. Select material from dropdown (N30, T35, etc.)
4. Intercept the network request that fetches chart data
   (likely an XHR to a PHP endpoint returning JSON or CSV)
5. If no clean endpoint exists, extract data from the
   chart's JavaScript data arrays (inspect the chart library's
   internal state — MDT likely uses Highcharts or similar)
6. Map extracted arrays to schema
7. Repeat for each chart type: µ_i vs T, power loss vs f, etc.
```

If the MDT desktop version stores local SQLite or XML data files, those can be parsed directly without browser automation — check the install directory structure.

### Tier 2 — PDF extraction (medium quality, higher effort)

For vendors that only publish PDFs (Magnetics Inc, Micrometals, many TDK materials as fallback).

**Two sub-paths within PDF extraction:**

**2a. Table extraction** — for PDFs where data is in actual text tables (not chart images). Use `pdfplumber` or `camelot` in Python:

```
1. Open PDF
2. Detect tables on each page
3. Extract rows → validate column headers match expected quantities
4. Convert units (some vendors use Oe instead of A/m, gauss instead of mT)
5. Map to schema with source.method = "pdf_table_extract"
6. confidence = "medium" (OCR can misread digits)
```

**2b. Chart digitization** — for PDFs where the data only exists as plotted curves. This is the hardest path:

```
1. Render PDF page to high-res image (300+ DPI)
2. Crop to the chart region
3. Detect axes: identify axis labels, tick marks, scale (linear vs log)
4. Use Claude's vision capability to:
   a. Identify the chart type and what quantities are plotted
   b. Read axis ranges and scale type
   c. Trace each curve and extract approximate (x, y) pairs
5. Alternatively, use WebPlotDigitizer or similar tool
   (open-source, can be scripted)
6. Post-process: remove duplicates, sort by x, smooth if noisy
7. Map to schema with source.method = "pdf_digitize"
8. confidence = "medium" to "low" depending on chart resolution
```

**Claude-assisted PDF digitization workflow:**

This is the "AI enrichment" layer. For each PDF:

```
1. Convert PDF pages to images
2. Send images to Claude API with a structured prompt:
   "This is page N of the {vendor} {material} datasheet.
    Extract all data from charts and tables.
    For each chart, identify:
    - x-axis quantity, unit, scale (linear/log), range
    - y-axis quantity, unit, scale (linear/log), range
    - Number of curves and what each represents
    - Approximate data points (aim for 20-50 per curve)
    Return as JSON matching this schema: ..."
3. Parse Claude's response
4. Validate: are values physically reasonable?
   (µ' should decrease with frequency, not increase)
5. Cross-reference against any scalar data from the same PDF
6. Store with source.method = "pdf_digitize_llm"
```

### Tier 3 — Manual entry / user upload

For measured data, proprietary data, or corrections:

```
1. User provides CSV or JSON with column headers
2. Schema mapper validates structure and units
3. Interactive review: plot the curves, compare against
   any existing data for the same material
4. User approves → merge into database
```

---

## 5. Pipeline stages in detail

### Stage 1: Discovery

Input: A vendor catalog URL or a folder of PDFs.

```
discover(source) → [
  { material_id: "N30", source_type: "mdt", url: "...", priority: 1 },
  { material_id: "N30", source_type: "pdf", url: "...", priority: 2 },
  { material_id: "T35", source_type: "pdf", url: "...", priority: 2 },
  ...
]
```

For the "point at a page with PDFs" use case: the discovery stage scrapes the page for PDF links, downloads them, and uses Claude to classify each PDF (is this a material datasheet? which material? which curves does it contain?).

### Stage 2: Extraction

Each source type has a dedicated adapter. All adapters output the same intermediate format:

```typescript
interface RawExtraction {
  material_id: string;
  vendor: string;
  curves: {
    [curve_name: string]: {
      x_values: number[];
      y_columns: { [name: string]: number[] };
      x_unit: string;
      y_unit: string;
      test_conditions: Record<string, any>;
    }
  };
  scalars: Record<string, number>;
  source: SourceTrace;
}
```

### Stage 3: Normalization

Converts raw extractions to the canonical schema:

- **Unit conversion:** Oe → A/m, gauss → mT, etc.
- **Frequency axis:** Ensure all frequency data is in Hz (some sources use kHz or MHz).
- **Representation:** Complex permeability can be series or parallel — normalize to series with conversion formulas if needed.
- **Deduplication:** If the same curve exists from two sources, keep both with different provenance, flag for human review.
- **Sorting:** All sample arrays sorted by x-axis ascending.

### Stage 4: Validation

Automated physics-based sanity checks:

```
✓ µ'(f) is monotonically decreasing (or at least non-increasing) above f_flat
✓ µ''(f) has exactly one peak (for simple ferrites)
✓ µ'(0) ≈ µ_i (within tolerance)
✓ Curie temperature is above max operating temperature
✓ Core loss increases with frequency and flux density
✓ DC bias: µ_rev decreases with increasing H_dc
✓ No negative values for µ', µ'', Pv
✓ Sample count ≥ 10 per curve (enough for interpolation)
```

Failed checks do not reject the record — they flag it for review with a specific warning message.

### Stage 5: Model fitting

For records with sufficient curve data, fit analytical models:

- **Steinmetz parameters** (k, α, β) from core loss vs f and B data
- **Debye relaxation poles** from complex permeability curves
- **DC bias rational fit** (CSC-style) from µ vs H data
- **Single-pole frequency rolloff** for µ'(f) approximation

Each fit stores its R² value and valid range. The app can use fitted models for interpolation/extrapolation and fall back to raw lookup tables when fits are poor.

### Stage 6: Storage

The final validated, normalized records are written to:

1. **`material_db.json`** — the full database, used by build tooling
2. **`material_db.js`** — ES module export for direct React import
3. **Per-vendor JSON files** — for incremental updates

The JS module exposes helper functions matching your existing API:

```javascript
export function getMaterial(id) { ... }
export function getMaterialsByTag(tag) { ... }
export function interpolateCurve(materialId, curveName, xValue) { ... }
export function getComplexPermeability(materialId, fHz) { ... }
export function getCoreLoss(materialId, fHz, BmT, TC) { ... }
```

---

## 6. Implementation plan — phased

### Phase 1: Schema + Fair-Rite (week 1)

- Finalize the unified schema (above)
- Build Fair-Rite CSV adapter (simplest path, proves the pipeline)
- Ingest all Fair-Rite materials that offer CSV downloads
  (31, 43, 44, 46, 51, 52, 61, 67, 68, 73, 75, 76, 77, 78, 79, 80)
- Generate `material_db.js` with helpers
- Integrate into the React app, replacing the current seed data

**Deliverable:** Working app with ~16 Fair-Rite materials, each with real µ'(f) and µ''(f) curves.

### Phase 2: TDK EMI subset via MDT (week 2–3)

- Build Playwright-based MDT adapter
- Target the 13 EMI-relevant TDK materials:
  N30, T35, T36, T37, T65, E11, E12, E13, E14, E16, E19, E21, K10
- Extract: complex permeability, µ_i vs T, power loss families
- Cross-check against PDF datasheets for the same materials
- Fit Steinmetz parameters and Debye relaxation models

**Deliverable:** 13 TDK materials with full curve sets, fitted models, and QA provenance.

### Phase 3: PDF digitization pipeline (week 3–4)

- Build PDF extraction adapter using `pdfplumber` + Claude vision
- Create the "point at a page" workflow:
  1. User provides a URL (e.g., TDK ferrite materials catalog page)
  2. Pipeline scrapes all PDF links
  3. Downloads and classifies each PDF
  4. Extracts what it can automatically
  5. Queues uncertain extractions for human review
- Target: remaining TDK power ferrites (N27, N41, N51, N87, N88, N95, N96, N97, T38, T46, T57, T58, T66)

**Deliverable:** PDF pipeline working end-to-end, ~15 additional TDK materials.

### Phase 4: Powder cores + expansion (week 5+)

- Add Magnetics Inc powder core families (MPP, Kool Mµ, High Flux, XFlux)
  using their published graphs and the CSC µ(H) model you already have
- Add Micrometals families (MS, HF, FS)
- Add Würth REDEXPERT data if their web tool is scrapeable
- Community contribution path: JSON schema validator so users can submit materials

**Deliverable:** Database covering major ferrite and powder-core families used in EMI filter design.

---

## 7. Technology choices

| Component | Tool | Why |
|-----------|------|-----|
| PDF text/table extraction | `pdfplumber` (Python) | Best table detection, handles multi-column layouts |
| PDF chart digitization | Claude API (vision) + `WebPlotDigitizer` CLI | Claude handles chart interpretation; WPD handles precise point extraction |
| Browser automation | Playwright (Python) | Better than Puppeteer for intercepting network traffic; works headless |
| Data validation | Custom Python (NumPy/SciPy) | Physics-based checks and curve fitting |
| Model fitting | SciPy `curve_fit` | Steinmetz, Debye, rational fits |
| Database format | JSON + JS module | Matches your existing architecture; no server needed |
| Orchestration | Python CLI scripts | Simple, debuggable, no framework overhead |
| LLM assist | Anthropic Claude API | PDF interpretation, QA review, data classification |

### Why not a "real" database?

Your app is a single-file React artifact running in Claude.ai. It has no backend, no server, no database connection. The material data ships as a JS module imported directly into the component. A traditional database (SQLite, Postgres) would add deployment complexity for zero benefit at this scale. If the dataset grows past ~10 MB (unlikely — 200 materials with full curves is ~2–3 MB), consider splitting into lazy-loaded vendor chunks.

---

## 8. The "point at a page" workflow

This is the dream: you give the pipeline a URL like `https://www.tdk-electronics.tdk.com/en/529404/.../ferrite-materials`, and it:

1. **Scrapes the page** for all PDF download links
2. **Downloads each PDF** to a local staging directory
3. **Classifies each PDF** using Claude:
   "Is this a ferrite material datasheet? If so, which material?"
4. **Checks the existing database** — skip materials we already have at `complete` status
5. **For each new material:**
   a. Extracts tables (pdfplumber)
   b. Extracts charts (Claude vision → data points)
   c. Extracts scalar properties (Claude text extraction)
   d. Normalizes and validates
   e. Generates a review report with plots
6. **Outputs a staged batch** ready for human approval

This is entirely viable with current tooling. The main constraint is Claude API cost for vision calls — a typical material datasheet is 4–8 pages, each needing one vision call. At ~13 EMI materials, that is roughly 50–100 API calls, which is very manageable.

For non-TDK vendors, the same workflow applies — the discovery stage just needs to know how to find PDF links on a given vendor's page structure. Each vendor gets a small `discover_*.py` adapter.

---

## 9. React app integration

The app consumes the database through a thin API layer:

```javascript
// material_db.js (auto-generated by pipeline)
import { MATERIAL_DB } from './material_db_data.js';

// Lookup
export const getMaterial = (id) => MATERIAL_DB.materials[id];
export const listMaterials = (filter) => {
  return Object.values(MATERIAL_DB.materials).filter(m => {
    if (filter.vendor && m.vendor !== filter.vendor) return false;
    if (filter.family && m.family !== filter.family) return false;
    if (filter.tag && !m.application_tags.includes(filter.tag)) return false;
    if (filter.minStatus) {
      const order = ['seed','partial','complete','verified'];
      if (order.indexOf(m.record_status) < order.indexOf(filter.minStatus)) return false;
    }
    return true;
  });
};

// Interpolation (log-scale for frequency curves)
export const interpolateCurve = (materialId, curveName, xTarget) => {
  const curve = MATERIAL_DB.materials[materialId]?.curves?.[curveName];
  if (!curve?.samples?.length) return null;

  const samples = curve.samples;
  const isLogX = ['frequency'].includes(curve.x_quantity);

  // Binary search + linear interpolation (log-space if frequency)
  const xArr = samples.map(s => isLogX ? Math.log10(s[0]) : s[0]);
  const xT = isLogX ? Math.log10(xTarget) : xTarget;

  if (xT <= xArr[0]) return samples[0].slice(1);
  if (xT >= xArr[xArr.length-1]) return samples[samples.length-1].slice(1);

  let lo = 0, hi = xArr.length - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (xArr[mid] <= xT) lo = mid; else hi = mid;
  }
  const t = (xT - xArr[lo]) / (xArr[hi] - xArr[lo]);
  return samples[lo].slice(1).map((v, i) =>
    v + t * (samples[hi][i+1] - v)
  );
};

// Convenience: get µ'(f) and µ''(f)
export const getComplexPermeability = (materialId, fHz) => {
  const vals = interpolateCurve(materialId, 'complex_perm_vs_f', fHz);
  if (!vals) return null;
  return { muPrime: vals[0], muDoublePrime: vals[1] };
};
```

### Material selector component changes

The app's material dropdown currently has hardcoded entries. With the new database:

```jsx
// Replace hardcoded material list with dynamic query
const materialOptions = listMaterials({
  tag: filterMode === 'emi' ? 'EMI_filter' : undefined,
  minStatus: 'partial'  // hide seed-only records from selector
});

// Show provenance badge next to material name
<option value={m.material_id}>
  {m.vendor} {m.vendor_material_code}
  {m.record_status === 'verified' ? ' ✓' : ''}
</option>
```

---

## 10. Priority materials — EMI-relevant first cut

These are the materials that matter most for DC-DC input filter design:

| Vendor | Material | µ\_i | Type | Use case |
|--------|----------|------|------|----------|
| TDK | N30 | 4300 | MnZn | CMC, EMI filter chokes |
| TDK | T35 | 6000 | MnZn | Current-compensated chokes |
| TDK | T36 | 7700 | MnZn | CMC, data line filters |
| TDK | T37 | 6500 | MnZn | CMC, EMI filter |
| TDK | T65 | 6500 | MnZn | Filter chokes, high perm |
| TDK | K10 | 700 | NiZn | Data line suppression |
| TDK | E11–E21 | 100–1000 | NiZn | Broadband EMI suppression |
| Fair-Rite | 31 | 1500 | MnZn | Broadband EMI 1–500 MHz |
| Fair-Rite | 43 | 800 | NiZn | EMI suppression 25–300 MHz |
| Fair-Rite | 61 | 125 | NiZn | EMI suppression 200 MHz–1 GHz |
| Fair-Rite | 73 | 2500 | MnZn | EMI beads < 50 MHz |
| Magnetics | MPP (various µ) | 14–550 | MPP | DM filter inductors |
| Magnetics | Kool Mµ (various µ) | 26–125 | Sendust | DM filter inductors |
| Magnetics | High Flux (various µ) | 14–160 | NiFe | DM filter, high DC bias |

---

## 11. File structure

```
material_pipeline/
├── README.md
├── schema/
│   └── material_schema.json          # JSON Schema for validation
├── adapters/
│   ├── fair_rite_csv.py              # Fair-Rite CSV downloader + parser
│   ├── tdk_mdt.py                    # TDK MDT browser scraper
│   ├── pdf_extractor.py              # Generic PDF table + chart extraction
│   ├── manual_csv_import.py          # User-uploaded CSV mapper
│   └── discover_catalog.py           # "Point at a page" URL scraper
├── processing/
│   ├── normalizer.py                 # Unit conversion, axis normalization
│   ├── validator.py                  # Physics sanity checks
│   ├── model_fitter.py               # Steinmetz, Debye, rational fits
│   └── llm_assist.py                 # Claude API calls for PDF interpretation
├── output/
│   ├── material_db.json              # Full database
│   ├── material_db.js                # ES module for React import
│   └── vendor/                       # Per-vendor JSON splits
│       ├── fair_rite.json
│       ├── tdk.json
│       └── magnetics_inc.json
├── staging/                          # Downloaded PDFs, intermediate files
├── reviews/                          # Human review queue
└── tests/
    ├── test_normalizer.py
    ├── test_validator.py
    └── test_interpolation.py
```

---

## 12. Open questions for your decision

1. **MDT desktop vs web:** The TDK MDT desktop version (Windows) may store material data in local files that are easier to parse than scraping the web app. If you have access to a Windows machine, it is worth installing and checking the file structure. Would you like to investigate this path?

2. **Data licensing:** Fair-Rite and TDK publish this data freely for engineering use, but redistribution in an app may have terms. For a personal tool this is fine; if you plan to distribute the app publicly, check each vendor's terms of use.

3. **Update frequency:** Vendor data changes rarely (maybe once per databook revision, every few years). Do you want the pipeline to re-run periodically, or is a one-time build with manual updates sufficient?

4. **Powder core priority:** Your existing app already models MPP, Kool Mµ, and High Flux with CSC rational fits. Do you want the pipeline to replace those hardcoded models, or augment them with additional curve data?
