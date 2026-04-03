# PCMC Control Loop Analyzer — Init / Handoff Guide

## What This Is
A React-based peak current-mode control (PCMC) loop analyzer for power electronics design. It computes Bode plots, transient response, stability margins, output impedance, and audio susceptibility for buck, two-switch forward, and flyback converter topologies. The tool runs as a single JSX artifact in Claude's artifact viewer or as a standalone HTML file.

The user is a power electronics engineer focused on space/radiation-tolerant designs (ISL71041M, ISL71043M). They value physics correctness over speed and prefer implementation plans reviewed before coding.

---

## Key Files

| File | Purpose |
|------|---------|
| `buck-cm-tool-7.jsx` | **The tool** — 5,693 lines, single React component + all physics inline |
| `session-7-changelog.md` | Detailed changelog of everything done in session 7 |
| `implementation-status.md` | Current feature status, what's done, what's planned, known patterns |

---

## Architecture

### File Structure (buck-cm-tool-7.jsx)
```
Lines 1–30:       Complex math helpers (C, cadd, cmul, cdiv, cmag, cphase, dB, etc.)
Lines 30–180:     Cap bank impedance functions (evalZcapSingle, evalZcapBank, etc.)
Lines 180–300:    Cap CSV import / curve fitting
Lines 300–700:    Plant models (getPlantInfo — routes to CCM/DCM/flyback/gm_ps)
Lines 700–900:    Transfer functions (evalPlant, evalGid, evalGvi, evalHe, evalTi, etc.)
Lines 900–1100:   Zout, Gvg, feedback, delay, sense chain functions
Lines 1100–1400:  Time-domain simulation (simTimeDomain — RK4 averaged nonlinear)
Lines 1400–1550:  Compensator auto-placement (autoPlace, autoPlaceType3, analyzeLoop)
Lines 1550–1800:  Validation, IC validation, step response
Lines 1800–2130:  SPICE netlist generator (generateSpiceNetlist)
Lines 2130–2390:  NGspice WASM netlist generator (generateNGspiceNetlist)
Lines 2390–2580:  IC_LIBRARY constant (9 ICs with full parameters)
Lines 2580–2900:  React component state (109 useState hooks), derived values, applyIC
Lines 2900–3200:  useMemo blocks (Bode data, sweep data, Zcap data, time-domain)
Lines 3200–3400:  useEffect blocks (logging, auto-calc)
Lines 3400–3700:  JSX: left panel (toggle bar, cards)
Lines 3700–4000:  JSX: left panel continued (sense, slope, EA, FB, comp, transient cards)
Lines 4000–4100:  JSX: right panel metrics bar
Lines 4100–4500:  JSX: Bode tab (magnitude, phase, info bar, SPICE export, advisor)
Lines 4500–4700:  JSX: Transient tab (output voltage, iL, vcomp/D)
Lines 4700–4900:  JSX: Sweep tab (Vin sweep, Iout sweep)
Lines 4900–5100:  JSX: Zcap, Audio tabs
Lines 5100–5400:  JSX: Diagnostics, Equations tabs
Lines 5400–5693:  JSX: Log panel, LoopBlockDiagram, PanelBox, EqnSection helpers
```

### Layout
Single-page side-by-side:
- **Left panel (300px):** Toggle bar `[TOPO][IC][XFMR][PWR][CAPS][SENSE][SLOPE][FB][EA][COMP]` + stacked parameter cards
- **Right panel:** Metrics bar (fc, PM, GM, D, Qp, RHPZ, Zout, EA φ) + tab bar + plots

### Plant Model Routing
`getPlantInfo(p)` is the central dispatcher:
- `p.plantMode === "gmps"` → `evalPlantGmps` (TPS7H4011 integrated converter)
- `p.topology === "flyback"` + CCM → `evalPlantFlybackCCM` (Basso/Richtek closed-form)
- `p.topology === "flyback"` + DCM → `evalPlantFlybackDCM` (single-pole, loss-free resistor)
- Otherwise CCM → `evalPlantCCM` (standard Fm·Gid·Gvi/(1+Ti) decomposition)
- Otherwise DCM → `evalPlantDCM`

### Loop Gain Assembly
T(s) = Gc(s) × Gvc(s) × compGain × H(s) × e^(-s·td)

Where:
- `Gc(s)` = compensator with EA finite bandwidth (`evalCompWithEA`)
- `Gvc(s)` = plant (`evalPlant`)
- `compGain` = 1/compDividerRatio (IC internal signal conditioning, e.g., 1/3 for UC384x)
- `H(s)` = feedback with opto pole (`evalOptoH`)
- `e^(-s·td)` = CS delay (`evalDelay`)

---

## Critical Physics Rules

### Flyback ≠ Buck
Every function that touches D, Sn, iL, or iC must have an explicit flyback branch:
```javascript
// Duty cycle
D_flyback = Vout / (Vout + Vin_eff)       // NOT Vout / Vin_eff
// Current slope
Sn_flyback = (Vin_pri / Lm) × Ri          // NOT (Vin-Vout)/L × Ri
// Steady-state inductor current
iL_ss_flyback = Iout / D'                  // NOT Iout
// Capacitor current
iC_flyback = iL × D' - Iout               // NOT iL - Iout
```

Sites that need flyback handling: `getPlantInfo`, `analyzeLoop`, `simTimeDomain`, `generateSpiceNetlist`, `evalZout_open`.

### n² Reference Direction
Recurring bug pattern — always verify physical direction:
- `Lm_sec = Lm × n²` (NOT Lm / n²)
- CT sense: `Ri = (Np/Ns) × Rb` (NOT Ns/Np)
- Sn_mag goes in numerator of mc (equivalent external slope)

### He(s) Always Uses Real Slope Comp
Even when SC correction toggle is "off" for gm_ps, He(s) must use the actual physical mc. Decoupling He mc from the SC toggle gives wrong Qp.

### Comp Freeze Behavior
Compensator values (fz, fp, fi, component values) only update on explicit RECALCULATE click. This enables sweeping Vin/Iout/temp corners with a frozen network. Do NOT add auto-recalculate useEffects.

### Ti(0) Not Applicable to Flyback
Ti(0) metric comes from buck decomposed model. Flyback uses Basso/Richtek closed-form which doesn't have Ti decomposition. Suppress Ti(0) warnings when `topology === "flyback"`.

### Error Signal in Time-Domain Sim
For isolated converters: `error = H × (Vout_nom - Vout)`, NOT `Vref - H × Vout`. The latter has wrong equilibrium when optoGain ≠ 1.

---

## Working With This Code

### Before Making Changes
1. Read the relevant physics function(s) thoroughly
2. Check if the change affects flyback, buck, AND forward — most functions need all three paths
3. Run Babel parse check: `parser.parse(code, {sourceType:'module', plugins:['jsx']})`
4. Check balance: count `()`, `{}`, `[]` — all must be 0
5. Verify no `const` use-before-define (causes blank screen crash in React)

### After Making Changes
1. Babel parse check (mandatory)
2. Buck regression: mc=1.230, Qp=0.812, Zout=0.1082Ω at reference operating point
3. Flyback regression: fp1=121Hz, fz_esr=79.58kHz, RHPZ=340.95kHz at Richtek AN017 reference
4. Forward regression: mc=1.707, Qp=0.469

### Extracting Physics for Testing
```javascript
// Read JSX, find "function NumInput(" to split physics from React
const lines = code.split('\n');
let physicsEnd = lines.findIndex(l => l.includes('function NumInput('));
const physics = lines.slice(5, physicsEnd).join('\n');
// Add module.exports with needed functions
```

### Common Gotchas
- The JSX uses `<sub>` tags in descriptions — these are valid JSX but not valid in plain strings
- Unicode characters (µ, Ω, °, ×, etc.) must be actual UTF-8 bytes, not escape sequences
- `fmtSI()` handles SI prefix formatting — use it instead of manual mΩ/kΩ/µF formatting
- `sf(value, digits)` is the safe formatter — handles null/NaN/Infinity gracefully
- Cap bank derating is per-type per-temperature — don't assume uniform derating

---

## User Preferences
- Prefers implementation plans reviewed before coding
- Wants hand-calculation validation before fixes are applied
- Provides SPICE screenshots and numerical log dumps for debugging
- Pushes back on incomplete explanations and approximations
- Maintains synchronized copies between JSX artifact and Node.js test file
- Session documentation updated at end of major sessions

---

## Reference Validation Points

### Buck (non-isolated)
- Vin=12V, Vout=3.3V, Iout=5A, fsw=300kHz, L=10µH, Cout=220µF/20mΩ, Ri=50mΩ, Se=10mV/µs
- Expected: mc=1.230, Qp=0.812, Ti0=5.10, Zout_open(DC)=0.1082Ω

### Flyback (Richtek AN017 reference)
- Vin_eff=14.625V (117V primary, n=1/8), Vout=12V, Iout=2A, fsw=256kHz, Lm=120µH
- Np=8, Ns=1, Cout=400µF/5mΩ, Ri=0.35V/A
- Expected: fp1=120.7Hz, fz_esr=79,577Hz, RHPZ=340,950Hz (all <0.5% of AN017 reference)

### Forward (2SW)
- Same Vin range as flyback but buck-equivalent with Dmax≤50%
- Expected: mc=1.707, Qp=0.469 (at Se=0, Lm correction active)
