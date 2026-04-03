# DM EMI Filter Design Tool — Technical Handoff Document

**For use by:** Claude Code CLI or any AI/developer continuing development
**Source file:** `emi-filter-v7.jsx` (single-file React/JSX artifact)
**Version:** 7.4 (as of March 2026)
**Lines:** ~2,791 | **State variables:** 74 | **Physics functions:** 52 | **Charts:** 5

---

## 1. Purpose & Scope

This is an interactive, browser-based differential-mode (DM) EMI filter design tool for power electronics engineers. It predicts whether a specific LC filter will pass conducted emissions standards for a given DC-DC converter topology.

**The complete signal chain modeled:**

```
Converter (DUT) → DM noise source spectrum → EMI filter (1 or 2 stage LC)
→ filtered emission at LISN → comparison against EMI standard limits
→ per-harmonic PASS/FAIL
```

**What makes it different from simple LC calculators:**
- Topology-specific Fourier source spectra (not flat noise assumption)
- Complex insertion loss with real parasitics (Cw, ESR, ESL)
- Toroid-corrected winding capacitance (calibrated against measured data)
- Per-harmonic compliance check across full frequency range
- Middlebrook stability as a simultaneous constraint
- Resonance diagnostics with damping recommendations
- SPICE time-domain import with browser-based FFT

---

## 2. Architecture

### 2.1 File Structure

Single file, no build system. Runs as a Claude.ai artifact (React/JSX rendered in iframe).

```
Lines 1–4:      Imports (React, Recharts)
Lines 5–170:    Data tables (materials, cores, wire, EMI limits)
Lines 170–688:  Physics functions (all pure, no side effects)
Lines 688–803:  Shared UI components (NI, IR, Tog, Sec, MC, W, etc.)
Lines 803–1076: EqPanel component (collapsible equations reference)
Lines 1077–2791: Main App component (state, computations, rendering)
```

### 2.2 Technology Stack

- **React** with hooks (useState, useMemo, useRef, useEffect)
- **Recharts** for all 5 charts (LineChart, ReferenceLine, ReferenceArea)
- **IBM Plex Mono** font throughout
- **Dark theme:** background #080808, text #ccc, accent colors per section
- **No external state management** — all state in useState hooks
- **No localStorage** — state resets on reload (known limitation)
- **SVG** for the circuit schematic (generated inline)

### 2.3 Color Coding Convention

| Color | Meaning |
|-------|---------|
| `#f0b44c` (gold) | Primary values, filter parameters, pass indicators |
| `#33cc55` (green) | Good/pass status, peak emission trace |
| `#ff4444` (red) | Fail status, limit lines |
| `#4488ff` (blue) | Wire/Cw section, frequency markers |
| `#cc88ff` (purple) | Damping networks, Middlebrook |
| `#ff8844` (orange) | DUT/source, EMI standard, warnings |
| `#44dddd` (cyan) | QP detector trace |

---

## 3. Data Tables

### 3.1 Material Database (`MAT`)

Three powder core families, each with:

```javascript
MAT = {
  MPP: {
    name, short, bsat_T,
    steinmetz: {k, alpha, beta},           // Simple Steinmetz: Pv = k·f^α·B^β
    csc: {60:{a,b,c,d}, 125:{...}, ...},   // CSC composite model per µ
    dcbias: {60:{a,b,c}, 125:{...}, ...},   // µ'(H) = 1/(a + b·H^c)
    fflat: {14:4000, 26:3000, ...},         // Flat frequency per µ (kHz)
    mus: [14, 26, 60, 125, 160, 200]        // Available permeabilities
  },
  KoolMu: {...},
  HighFlux: {...}
}
```

### 3.2 Core Presets (`CORES`)

Six presets + Custom. Each specifies: material, µ, AL (nH/N²), Ae (mm²), le (mm), Ve (cm³), OD/ID/HT (mm).

```
55350 (MPP 125µ), 55439 (MPP 60µ), 55059 (MPP 125µ lg),
77439 (KoolMu 60µ), 77083 (KoolMu 125µ), 58350 (HiFlux 125µ)
```

### 3.3 Wire Table (`AWG_TABLE`)

14–26 AWG, each with `dc` (bare diameter mm) and `dw` (insulated diameter mm).

### 3.4 Insulation (`INS`)

Four types: `std` (Standard), `heavy` (Heavy Build), `ptfe` (PTFE Wrap), `triple` (Triple Insulated). Each has `er` (relative permittivity), `tex` (extra thickness mm), `lb` (label).

### 3.5 EMI Limit Tables

**CISPR 25 Voltage method:** `C25V_AVG`, `C25V_PK`, `C25V_QP` — 6 bands (LW through Band 5), Class 5 base + inter-class step. Units: dBµV, converted to dBµA via `dBµA = dBµV − 20·log₁₀(Zs)`.

**CISPR 25 Current probe:** `C25I_PK`, `C25I_QP`, `C25I_AVG` — Edition 1 basis, dBµA directly.

**CISPR 32:** `C32` table with Class A/B, QP and AVG. Log-linear interpolation in sloped 150k–500k band.

**MIL-STD-461:** `CE102_VADJ` voltage adjustment table {28:0, 115:12, 220:18, 270:20, 440:24}. CE101 limits hardcoded in `evalLimit()`.

---

## 4. Physics Models (Functions)

All physics functions are pure (no side effects, no state access). They live outside the App component.

### 4.1 Core & Magnetics

| Function | Purpose |
|----------|---------|
| `pMuFn(mat, mu, H)` | DC bias permeability rolloff: µ'(H) = 1/(a + b·H^c) |
| `muFf(f, mat, mu)` | Frequency-dependent permeability: 1/√(1 + (f/(ff·7.5))²) |
| `calcIGSE(mat, dB, fk, D)` | Improved Generalized Steinmetz with duty cycle |
| `calcDowell(dc, dw, N, nL, lt, Idc, Ipp, fk)` | Dowell proximity/skin effect FR factor |

### 4.2 Winding Capacitance

| Function | Purpose |
|----------|---------|
| `calcCwPhysics(dc, dw, er, tex, N, OD, ID, HT, kTor)` | Full Cw pipeline |

**Pipeline:** Magnetics Inc wound dimensions → M-K parallel-plate base → toroid coupling correction (k factor).

**Returns:** M-K bobbin values, toroid-corrected values, Mag-Inc geometry (OD_wound, HT_wound, ID_eff, angularL2), window fill.

**Key parameter:** `kTor` (default 0.025) — empirical toroid coupling factor, calibrated against measured impedance data from 55350/57T/17AWG inductor. Adjustable via slider.

### 4.3 Complex Impedance Algebra

```javascript
cmul([r1,i1], [r2,i2])  // complex multiply
cdiv([r1,i1], [r2,i2])  // complex divide
cadd([r1,i1], [r2,i2])  // complex add
cmag([r,i])              // complex magnitude
cpara(Z1, Z2)            // parallel impedance
```

All complex numbers represented as `[real, imaginary]` 2-element arrays.

### 4.4 Filter Transfer Functions

| Function | Purpose |
|----------|---------|
| `chokeZc(w, L, rL, Cw_pF, mat, mu)` | Choke impedance with Cw parallel resonance + µ'(f) |
| `capZc(w, C_nF, esr, esl_nH)` | Cap impedance with ESR + ESL |
| `capZcDamped(w, C_nF, esr, esl_nH, Rd, Cd_nF)` | Cap + Rd+Cd damping network |
| `calcIL1(f, L, C, Zs, rL, Cw, esr, esl, mat, mu)` | 1-stage insertion loss (dB) |
| `calcIL2(f, L1, C1, L2, C2, Zs, ...)` | 2-stage insertion loss with stage interaction |
| `calcIL1_d(f, ..., Rd, Cd)` | 1-stage IL with damping |
| `calcIL2_d(f, ..., Rd1, Cd1, Rd2, Cd2)` | 2-stage IL with per-stage damping |
| `calcZout1(f, ...)` | 1-stage filter output impedance |
| `calcZout2(f, ...)` | 2-stage filter output impedance |

**Insertion loss model:** Complex voltage-divider transfer function. IL = 20·log₁₀(|H_without_filter / H_with_filter|). Includes: source impedance Zs, choke (L + Cw parallel + µ'(f) rolloff + R_dc), cap (C + ESR + ESL), load impedance.

### 4.5 EMI Limits

| Function | Purpose |
|----------|---------|
| `evalLimit(f, stdKey, cls, det, Vnom, Zs, c32cls)` | Returns limit in dBµA at frequency f |
| `buildLimitCurve(stdKey, cls, det, Vnom, Zs, srcDB, margin, c32cls)` | 301-point limit + required attenuation array |
| `getBandName(f, stdKey, det)` | Band label for display |
| `c32eval(f, c32cls, det)` | CISPR 32 specific evaluator with sloped band |

### 4.6 Detector Correction (CISPR 16-1-1)

```javascript
detCorr(f, fsw_Hz) → {pk2qp, pk2avg}
```

Analytical charge-balance QP model + broadband average formula. For fixed-frequency CCM SMPS with fsw >> RBW: pk2qp ≈ 0, pk2avg ≈ 0 (narrowband, all detectors read the same).

### 4.7 Source Spectrum Engine

**Topology definitions (`TOPOS`):**

Each topology has: `name`, `hasIso` (isolated?), `duty(Vi, Vo, NsNp)`, `ipp(Vi, Vo, D, L, fsw)`, `In(n, D, Iout, tr, fsw, ...)` (nth harmonic), `envA(...)` (envelope amplitude), `desc`.

| Key | Topology | Waveform | Dominant DM Source |
|-----|----------|----------|-------------------|
| `buck` | Buck CCM | Rectangular pulse | Full load current chopped at D |
| `boost` | Boost CCM | Triangular ripple | Inductor ripple only (quiet) |
| `flyCCM` | Flyback CCM | Trapezoidal pulse | Rect(Imin) + Ramp(ΔI) |
| `flyDCM` | Flyback DCM | Triangular pulse + dead time | Ramp(0→Ipeak) then instant drop |
| `fwd2sw` | 2-Switch Forward | Bipolar (on + reset) | Reflected load IL + magnetizing ΔIm |

**Key functions:**

```javascript
computeHarmonics(topo, params, maxF) → [{n, f, In, dBuA}]
envAmplitude(f, topo, params) → amplitude in Amps (for continuous envelope)
sincSafe(x) → sin(x)/x with x=0 handling
riseCorr(n, tr, fsw) → |sinc(n·π·tr·fsw)| rise-time rolloff
```

### 4.8 SPICE Import / FFT

| Function | Purpose |
|----------|---------|
| `parseSpiceFile(text)` | Parse CSV/tab-delimited → {time[], amp[], points} |
| `resampleUniform(time, amp, nPts)` | Variable → uniform timestep (linear interp) |
| `fftRadix2(re, im)` | In-place Cooley-Tukey radix-2 FFT |
| `autoDetectFsw(magSpectrum, df)` | Find dominant peak above DC |
| `trimToIntegerCycles(time, amp, fswHz)` | Trim to clean cycle boundary |
| `processSpiceImport(text, sigType, Zs, fswOverride)` | Full pipeline: parse → resample → DC remove → Hanning → FFT → harmonics |
| `getStdRequirements(stdKey)` | Compute min duration, RBW, freq range for selected standard |

**FFT pipeline:**
1. Parse CSV/txt → time[], amp[]
2. Resample to uniform grid (next power of 2, max 65536)
3. Remove DC offset
4. Apply Hanning window
5. Radix-2 FFT
6. Magnitude spectrum → dBµA (with voltage/current conversion if needed)
7. Peak search at each n×fsw ±2 bins
8. Return harmonics array (same format as analytical)

---

## 5. State Variables (74 total)

### 5.1 Core/Winding

| Variable | Default | Purpose |
|----------|---------|---------|
| `coreName` | "55350 (MPP 125µ)" | Selected core preset |
| `cMat/cMu/cAL/cAe/cLe/cVe` | MPP/125/105/38.8/58.8/2.28 | Core parameters |
| `cOD/cID/cHT` | 23.57/14.40/8.89 | Core dimensions (mm) |
| `N` | 57 | Turns count |
| `Idc` | 2.8 | DC load current (A) |
| `awg` | 17 | Wire gauge |
| `insType` | "heavy" | Insulation type |

### 5.2 Winding Capacitance

| Variable | Default | Purpose |
|----------|---------|---------|
| `cwMode` | "toroid" | Cw model: "mk", "toroid", "manual" |
| `cwManual` | 10 | Manual Cw override (pF) |
| `kTor` | 0.025 | Toroid coupling factor |
| `wS/wP/wO/wF/wSp` | all false | Winding technique toggles |

### 5.3 SRF

| Variable | Default | Purpose |
|----------|---------|---------|
| `srfLmode` | "unbias" | SRF L reference: "unbias", "bias", "manual" |
| `srfLman` | 330 | Manual L for SRF (µH) |

### 5.4 Core Loss

| Variable | Default | Purpose |
|----------|---------|---------|
| `lmod` | "igse" | Loss model: "simple", "csc", "igse" |
| `dutyCy` | 0.5 | Duty cycle (now auto-synced from topology) |

### 5.5 Filter Parameters

| Variable | Default | Purpose |
|----------|---------|---------|
| `autoL` | true | Auto L from AL×N²×pMu or manual |
| `Lman` | 240 | Manual L (µH) |
| `Cnf` | 10 | Filter capacitance (nF) |
| `fsw` | 221 | Switching frequency (kHz) |
| `capEsr/capEsl` | 10/1.0 | Cap parasitic ESR (mΩ) / ESL (nH) |

### 5.6 DUT / Source Spectrum

| Variable | Default | Purpose |
|----------|---------|---------|
| `topoKey` | "buck" | Converter topology selector |
| `autoIpp` | true | Auto or manual ΔI_pp |
| `Vin/Vout/Iout` | 28/5/3 | Converter operating point |
| `tr` | 20 | Rise/fall time (ns) |
| `NsNp/Lm` | 0.5/500 | Turns ratio, magnetizing L (for isolated) |

### 5.7 SPICE Import

| Variable | Default | Purpose |
|----------|---------|---------|
| `useSpice` | false | SPICE import mode active |
| `spiceSigType` | "current" | "current" or "voltage" |
| `spiceResult` | null | Processed FFT result object |
| `spiceFileName` | "" | Uploaded filename |

### 5.8 EMI Standard

| Variable | Default | Purpose |
|----------|---------|---------|
| `stdKey` | "cispr25v" | Selected standard |
| `emiCls` | 5 | CISPR 25 class (1–5) |
| `emiDet` | "avg" | Detector: "avg", "qp", "pk" |
| `emiVnom` | 28 | Nominal bus voltage (for CE102) |
| `c32Cls` | "B" | CISPR 32 class (A/B) |
| `limMan` | 20 | Manual limit (dB, custom mode) |
| `Zs` | 50 | LISN impedance (Ω) |
| `desMgn` | 6 | Design margin (dB) |

### 5.9 2nd Filter Stage

| Variable | Default | Purpose |
|----------|---------|---------|
| `st2` | false | 2nd stage enabled |
| `L2/C2` | 50/47 | Stage 2 L (µH) / C (nF) |
| `capEsr2/capEsl2` | 10/1.0 | Stage 2 ESR/ESL |

### 5.10 Damping

| Variable | Default | Purpose |
|----------|---------|---------|
| `useDamping` | false | Middlebrook damping active |
| `dampAuto` | true | Auto or manual Middlebrook Rd/Cd |
| `RdMan/CdMan` | 5/40 | Manual Middlebrook values |
| `Vbus/Pout/etaMB` | 28/100/0.90 | Middlebrook Z_in computation |
| `emiDamp` | false | EMI resonance damping active |
| `emiDampAuto` | true | Auto or manual EMI Rd/Cd |
| `emiRd/emiCd` | 5/40 | Manual EMI damping values |
| `emiDampStage` | 1 | Which stage to damp (1 or 2) |

### 5.11 UI Toggles

| Variable | Default | Purpose |
|----------|---------|---------|
| `showEq` | false | Equations panel visibility |
| `showSchem` | false | Circuit schematic visibility |

---

## 6. Computed Values (useMemo)

| Memo | Depends On | Produces |
|------|-----------|----------|
| `cwP` | Wire, core dims, N, kTor | Cw decomposition, fill %, wound geometry |
| `CwEff_pF` | cwP, cwMode, techniques | Effective Cw after mode + techniques |
| `SRF` | srfL, CwEff_pF | Self-resonant frequency (Hz) |
| `srcParams` | topD, Iout, tr, fsw, Ipp_eff, NsNp | Parameter bundle for harmonic engine |
| `harmonicsAnalytical` | topo, srcParams | [{n, f, In, dBuA}] analytical spectrum |
| `srcEnvPts` | topo, srcParams, spiceEnvAtF | 301-point source envelope for chart |
| `limAtFsw` | fsw, std params | Limit value at switching frequency |
| `limCurve` | std params, srcDB | 301-point limit + required attenuation |
| `zoutPts` | L, C, Zs, damping, st2 | Z_out spectrum, peak, Middlebrook pass |
| `specPts` | L, C, Zs, parasitics, limCurve, src | 301-point: IL, emission, Z, µ for all charts |
| `biasCurve` | mat, mu | 101-point µ'(H) curve |
| `resonances` | fc1, fc2, SRF, damping, limits | Resonance scanner results |
| `dampedPts` | EMI damping params, L, C | 301-point damped emission |
| `specPtsFinal` | specPts, dampedPts | Final chart data with damped overlays |
| `harmDots` | harmonics, IL, limits, damping | Per-harmonic filtered emission + pass/fail |
| `chartData` | specPtsFinal, harmDots | Final emission chart data with dot markers |
| `worstHarmonic` | harmonics, IL, limits, damping | Worst-case harmonic margin |
| `cu` | wire, N, Idc, Ipp_eff, fsw | Dowell copper loss |

**Data flow:**

```
Core params → Lbias/Lunbias → Luh (auto or manual)
                             ↓
Wire/Core dims + kTor → cwP → CwEff_pF → SRF
                                         ↓
Topology → srcParams → harmonics ──────→ specPts → specPtsFinal → chartData
                                    ↓      ↑
EMI standard → limCurve ──────────→┘      │
                                           │
Damping → dampedPts ──────────────────────→┘
                                           ↓
                              Charts (IL, Emission, Z_out, |Z|, µ)
```

---

## 7. Charts

### Chart 1: Insertion Loss vs Frequency
- **X:** log frequency 100 Hz – 10 MHz
- **Y:** IL in dB (0–120)
- **Traces:** a1 (1-stage), a2 (2-stage), needA (required from standard), a1_before (undamped reference)
- **Markers:** fc₁, fc₂, fsw, SRF/3, harmonic lines (2×, 3×, 5×)
- **Shading:** red below needA, green above

### Chart 2: Emission Spectrum — Test Perspective
- **X:** log frequency 100 Hz – 10 MHz
- **Y:** dBµA (-20 to 140)
- **Traces:** srcEnv (source envelope, dim), emPk/emQP/emAvg (filtered, dim), limA (limit, red dashed), harmEm (harmonic dots, green/red)
- **Dots:** Green = pass, Red = fail, labeled H1–H8
- **Key insight:** Only dots matter for pass/fail; envelope between dots has no real energy

### Chart 3: Filter Output Impedance Z_out(f)
- **Traces:** Z1_und, Z1_dmp, Z2_und, Z2_dmp
- **Reference:** Z_in converter (horizontal line)
- **Pass/fail:** Peak Z_out < Z_in at all frequencies

### Chart 4: Choke |Z| + µ'(f)
- **Dual axis:** |Z| in dBΩ (left), µ'(f) as % (right, scaled)
- **Shows:** SRF peak, permeability rolloff

### Chart 5: Permeability vs DC Bias
- **X:** H (Oersteds), **Y:** µ'(H) %
- **Color bands:** Green (>70%), Yellow (40–70%), Red (<40%)

---

## 8. UI Sections (Left Column)

1. **CORE MATERIAL** — Preset selector, turns, DC current, computed H/µ/L/B
2. **WIRE — Cw MODEL** — AWG, insulation, window fill (Magnetics Inc), Cw mode selector (M-K/Toroid/Manual), k-factor slider, decomposition pipeline, SRF L-reference selector
3. **CORE LOSS + COPPER (DOWELL)** — Loss model selector, ΔB, Pv, FR factor
4. **FILTER PARAMETERS** — L (auto/manual), C, fsw, ESR, ESL
5. **DUT — SOURCE SPECTRUM** — Topology/SPICE toggle, converter params, DM current breakdown, operating point
6. **EMI STANDARD & SOURCE** — Standard selector, class, detector, limit display, design margin
7. **SRF — WINDING TECHNIQUES** — Technique toggles with divider factors
8. **2ND FILTER STAGE** — Enable toggle, L₂, C₂, ESR₂, ESL₂
9. **MIDDLEBROOK STABILITY** — Bus voltage, P_out, η, damping on/off, auto/manual Rd/Cd, EMI benefit display
10. **RESONANCE DIAGNOSTIC** — Resonance scan table, EMI damping controls

### Collapsible Panels (Bottom)
- **CIRCUIT SCHEMATIC** — Live SVG with all components
- **EQUATIONS & CRITERIA** — 10 equation sections

---

## 9. Known Issues & Technical Debt

### 9.1 Bugs / Inaccuracies

1. **Dowell FR = 20.68× for 17AWG at 221 kHz** — seems high. May need verification against FEA. The Dowell model assumes infinite-width foil conductors which overestimates proximity effect for round wire in a toroid. Consider implementing the Ferreira correction.

2. **Boost CCM envelope approximation** — `envAmplitude()` uses a simplified -20 dB/dec slope for the boost, but the actual harmonic computation (`In()`) correctly uses the 1/n² triangular formula. Only the continuous envelope display line is approximate; the harmonic dots are correct.

3. **Two separate damping networks** — Middlebrook and EMI damping are independent UI controls but physically they'd be one Rd+Cd per stage. When both are active on stage 1, the code takes the larger Rd, which isn't physically correct (parallel networks would give lower combined impedance). Should consolidate into single per-stage damping with dual-criterion display.

4. **`dutyCy` state variable is orphaned** — was the manual duty cycle input for iGSE. Now the duty cycle comes from `topD` (topology computation). The state variable still exists but is never set by user (display is read-only from topD). Safe to remove the state and just use topD directly.

5. **Brace count mismatch** — Simple `{`/`}` counting shows -1 imbalance due to JSX string literals in equations panel like `{"))]}"}`. Not a real syntax error — JSX handles this correctly. But tooling that does naive brace counting will flag it.

6. **`spiceFswOvr` state variable unused** — was for fsw override in SPICE mode, replaced by always using filter parameter fsw. State declaration remains at line 1113 but is never read. Safe to remove.

7. **Core loss uses `Ipp_eff` which is the analytical ripple** — when SPICE import is active, core loss should ideally use the RMS ripple from the imported waveform, not the analytical Ipp. Currently it always uses the topology-computed or manual Ipp.

### 9.2 Performance Considerations

- **301-point specPts** recomputes on every parameter change. With complex IL models and 2-stage, this is ~600 `calcIL` calls. Currently imperceptible (<5ms) but could be optimized with Web Workers if more computation is added.
- **LC Sizing Advisor binary search** runs ~90 `calcIL` evaluations × 500 harmonics = 45,000 IL calls per render when failing. This may cause perceptible lag on mobile. Consider debouncing or running in a requestAnimationFrame callback.
- **SPICE FFT** up to 65536-point runs in ~1ms. Not a concern.

### 9.3 Mobile Layout

- Works but charts are cramped on screens < 380px wide
- Some text overlaps in metric cards on narrow screens
- Range slider for kTor is hard to use on touch screens (thin target)

---

## 10. Features Not Yet Implemented

### 10.1 SPICE Import Enhancements (partially built)

The FFT engine and processing pipeline are complete and tested. The UI for upload/validation is built. **What's missing:**

- Waveform preview chart (small time-domain plot showing last 5 cycles)
- Option to re-process with different parameters without re-uploading
- NGspice `.raw` binary format parser (currently only CSV/txt)
- Multi-signal file handling (LTspice can export multiple probes)

### 10.2 Damping Consolidation

Merge Middlebrook and EMI damping into single per-stage control:
- One Rd/Cd per stage
- Dual-criterion display: "MB: PASS (peak Z_out = X Ω < Z_in)" + "EMI: reduces resonance by Y dB"
- Remove redundant EMI damping section
- Schematic shows single network per stage (currently shows two)

### 10.3 State Persistence

No state is saved between sessions. Options:
- URL hash encoding (compact, shareable)
- localStorage (simple, non-shareable)
- Export/import JSON config file

---

## 11. High-Impact Future Features

### Tier 1 — Immediate Value

**Common-Mode (CM) Filter Path**
- CM choke with mutual inductance model
- Y-caps (cap to chassis ground)
- CM + DM combined prediction
- Most real EMI failures are CM — this would roughly double the tool's coverage

**Component Library / Database**
- Real capacitor entries: MLCC part numbers with C(V) derating, ESR(f), ESL
- Off-the-shelf inductor catalog (Coilcraft, Würth, TDK)
- Dropdown selection → auto-populate all parasitic values

**SPICE Netlist Export**
- Generate .asc (LTspice) or .cir (NGspice/Qspice) of the designed filter
- Include pulsed current source matching topology waveform
- User verifies tool predictions in their own simulator

**BOM Output**
- Summary: L₁ spec (core + wire + turns), C₁ (value + voltage + ESR), Rd, Cd
- CSV export or copy-to-clipboard
- Rough cost/size estimate

### Tier 2 — Significant Expansion

**Spread Spectrum Frequency Modulation (SSFM)**
- Input: ±X% dither, modulation frequency
- Per-harmonic energy spreading: bandwidth = 2n·Δf
- This is where QP and AVG detectors genuinely diverge
- 5–20 dB reduction depending on parameters

**Multi-Objective Optimization**
- Sweep L/C/N space automatically
- Constraints: fill < 40%, SRF/3 > fsw, Middlebrook pass, loss < budget
- Pareto front: minimum size/weight vs maximum margin

**Temperature Derating**
- µ(T), R_dc(T), ESR(T) models
- Worst-case operating point at max ambient
- MLCC DC bias derating (X5R, X7R)

**Impedance Analyzer Data Import**
- Upload measured |Z|(f) CSV
- Overlay on choke |Z| chart
- Auto-fit Cw and loss parameters to match measurement

### Tier 3 — Advanced

- PCB parasitic estimator (trace L, via L, coupling)
- Near-field coupling between filter stages
- Radiated emissions rough estimate
- Power loss thermal budget
- Aging/reliability assessment

---

## 12. Locked Design Decisions

These decisions were made during development with engineering justification. Don't change without good reason:

1. **SRF uses selectable L reference** (unbias/bias/manual) — not hardcoded to unbiased
2. **Attenuation pass/fail is purely IL-driven** — SRF/3 is advisory, not a gate
3. **Per-harmonic pass/fail** — worst harmonic across full spectrum determines PASS/FAIL
4. **Toroid Cw correction = Mag-Inc geometry + k factor** — not raw M-K
5. **k = 0.025 default** — calibrated against measured 55350/57T/17AWG data
6. **Window fill uses Magnetics Inc formula** — N×Aw / (π/4 × ID²)
7. **Middlebrook peak Z_out tracked above fc₁/5** — avoids source impedance plateau
8. **Damping recommendation: Rd = Z₀ = √(L/C), Cd = 4×C**
9. **CISPR 25 voltage limits converted to dBµA** via LISN impedance
10. **Two-stage IL uses cascaded voltage dividers** — proper stage interaction, not dB sum
11. **Emission chart: harmonic dots are primary, envelope is secondary** — only dots determine pass/fail
12. **SPICE import uses filter parameter fsw** for harmonic extraction, not auto-detected value

---

## 13. Testing Notes

### SPICE Import Test Results

Eight test files validated against the JS FFT pipeline (run via Node.js):

| Test | Description | H1 Accuracy | Status |
|------|-------------|-------------|--------|
| test1 | Uniform dt, clean buck | -1.4 dB | ✓ |
| test2 | Variable dt (SPICE-like) | -1.4 dB | ✓ |
| test3 | Too short (10 µs) | Wrong harmonics | ⚠ Warns |
| test4 | Voltage mode (/50Ω) | -1.4 dB | ✓ |
| test5 | LTspice tab format | -0.3 dB | ✓ |
| test6 | 10 points only | Error thrown | ✓ |
| test7 | 1.31A DC offset | -1.4 dB | ✓ |
| test8 | With 50 MHz ringing | H1 correct, H5 +62 dB | ✓ |

The systematic -1.4 dB offset is from the Hanning window amplitude correction (expected).

### Winding Capacitance Validation

Measured inductor: 55350 core, 57 turns, 17 AWG heavy build.
Measured impedance at 2 MHz: 9822 Ω → implied SRF ≈ 2.66 MHz, Cw ≈ 10.5 pF.

| Model | Cw (pF) | SRF (MHz) | Error |
|-------|---------|-----------|-------|
| M-K bobbin | 657 | 0.34 | 8× low SRF |
| Toroid k=0.025 + Mag-Inc | ~10 | ~2.7 | Close ✓ |
| Manual (measured) | 10.5 | 2.66 | Reference |

---

## 14. Development Workflow

### Running Locally

The file is a single React/JSX component. To run:

1. In Claude.ai: paste as artifact, renders immediately
2. In Claude Code: serve via a React dev server with Recharts dependency
3. Standalone: wrap in HTML with React + Recharts CDN imports

### Making Changes

1. **Physics changes:** Edit functions in lines 170–688. All pure functions, testable independently.
2. **UI changes:** Edit within the main App component (lines 1077+). Follow existing section patterns.
3. **New data:** Add to tables in lines 5–170.
4. **New chart:** Add ResponsiveContainer + LineChart following existing patterns. Add dataKeys to specPts computation.

### Key Patterns

- **Input component:** `<IR lbl="Label" val={stateVar} set={setStateVar} unit="units" min={0} max={100} step={1}/>`
- **Toggle:** `<Tog lbl="Label" val={boolState} set={setBoolState} detail="description"/>`
- **Section:** `<Sec title="TITLE" accent="#color">...content...</Sec>`
- **Metric card:** `<MC lbl="Label" val="formatted" status="pass|warn|fail"/>`
- **Warning:** `<W msg="message text" col="#color"/>`

### Color/Style Conventions

- All backgrounds: `#080808` (app), `#0c0c0c` (charts), `#0a0a0a` (sub-panels)
- Borders: `#1a1a1a` (default), `#2a2a2a` (interactive), section accent color (active)
- Text: `#ccc` (primary), `#888` (secondary), `#444` (dim), `#333` (very dim)
- Font: IBM Plex Mono throughout, sizes 7–16px
- Spacing: 4–14px padding/gaps, consistent with existing sections
