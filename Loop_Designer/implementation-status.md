# PCMC Control Loop Analyzer — Implementation Status

## Current Version
**File:** `buck-cm-tool-7.jsx` (5,693 lines)
**Last Updated:** Session 7 (March 2026)

---

## Feature Status

### ✅ Complete & Validated

**Topologies**
- Buck (non-isolated) — validated against LTspice within 1%/1° on fc/PM
- Two-switch forward (isolated, buck-equivalent) — validated
- Flyback (isolated, Basso/Richtek closed-form) — physics validated against Richtek AN017 (<0.5% error on all pole/zero frequencies), SPICE export implemented, LTspice validation pending

**Plant Models**
- Standard decomposed: Fm·Gid·Gvi/(1+Ti) with He(s) sampling double-pole
- gm_ps integrated: gm_ps × Zout(s) × He(s) — validated against TI PSpice avg model (7% fc error after 9 bug fixes)
- Flyback CCM: Basso/Richtek closed-form with single output pole, ESR zero, RHPZ, He(s)
- Flyback DCM: single-pole with loss-free resistor
- Auto CCM/DCM detection with Io_crit

**Bode Analysis**
- Magnitude and phase plots with Plant, Comp, Loop traces
- Sub-blocks view: Ti, Gid, Gvi, He, Kcs, Ridley reference, Fm·Gvd (VM reference)
- EA finite bandwidth modeling (OTA and op-amp)
- CS delay modeling
- Phase tooltip shows degrees, magnitude tooltip shows dB
- Opto pole H(s) = H_dc / (1 + jf/fp_opto)

**Compensator**
- Type-II and Type-III with auto-placement
- Manual mode with direct fz/fp/fi entry
- Freeze-on-RECALCULATE (enables corner sweeping with fixed network)
- OTA: RCOMP/CCOMP/CHF decomposition
- Op-amp: R1/R2/C1/C2 (Type-II) or R1/R2/R3/C1/C2/C3 (Type-III)
- compGain scaling for ICs with internal COMP-to-comparator dividers

**IC Library (9 entries)**
- Custom, TPS7H4011-SP, UCC28C43, UCC28C44, UC3842/3, UC3844/5, UCC28780, ISL71043MBZ, ISL71041MBZ
- Per-IC: EA type/params, Vref, Dmax, LEB, CS delay, COMP clamps, slew current
- Signal conditioning: compDividerRatio, compDiodeDrop_V, csOffset_mV
- Topology compatibility filter on dropdown

**Isolated Feedback**
- Optocoupler mode: CTR, Rpullup, Rled, Copto → optoGain and fp_opto
- Primary-side mode: H_dc = Vref/Vout, no opto pole (ISL71041M/ISL71043M schematic topology)

**Current Sense**
- Simple resistor, shunt with amp BW + parasitic zero, CT with droop/reset analysis
- High-side / inductor placement
- Primary / secondary side for isolated
- Lm→Sn magnetizing ramp correction (Chen/Huang 2007)

**Output Cap Bank**
- Up to 3 groups in parallel, each with qty × (C, ESR, ESL)
- Per-type temperature derating (electrolytic, polymer, MLCC X7R/X5R)
- Impedance curve (Zcap tab) with anti-resonance detection
- CSV impedance import + curve fitting

**Transient Simulation**
- Averaged nonlinear state-space model (RK4)
- Topology-correct for buck, forward, and flyback
- EA slew rate limiting (source/sink)
- Output voltage: full recovery view (auto-sized to show return to 0)
- iL and VCOMP: auto-zoomed to fast dynamics
- Load step and line step stimuli

**Sweep Analysis**
- Vin sweep: PM, fc, GM across input range with frozen comp
- Iout sweep: PM, fc, GM across load range
- Subharmonic instability detection (correct for all topologies)

**Audio Susceptibility**
- Zout(f): open-loop and closed-loop output impedance
- Gvg(f): open-loop and closed-loop audio susceptibility
- PSRR(f) = -20·log₁₀|Gvg_cl|
- Feedforward kf for primary-side sensing

**SPICE Export**
- Separate .CIR files for Bode (.ac) and Transient (.tran)
- Buck/forward: averaged switch model with behavioral Fm
- Flyback: Laplace behavioral plant (.ac) or averaged nonlinear model (.tran)
- Middlebrook injection for loop gain measurement
- LTspice/Qspice/NGspice compatible

**Loop Design Advisor**
- Hybrid: Claude API (5s timeout) → local deterministic fallback
- Phase budget table at crossover, ranked by magnitude
- Top 3 phase killers identified
- 2–6 specific design recommendations with expected PM improvement

**Other**
- Snapshot/log system with clipboard copy
- Temperature corner sweeping (nominal/cold/hot)
- Input filter (Lin, Cin, Rd) with Middlebrook stability check
- Multi-winding transformer (forward: Ns+Lout+caps per winding, flyback: Ns+Vout+caps)

---

### 🔄 In Progress / Needs Validation

**Flyback SPICE Validation**
- .CIR export implemented for flyback
- NOT YET validated against LTspice — need to run .ac and compare Bode (crossover, PM, plant shape)
- Transient .tran also not yet compared

**Physics Engine Sync**
- `physics-engine-v7.js` (Node.js test copy) is significantly out of sync with the JSX
- All flyback fixes, compGain, error signal fix, Sn_total fix are only in the JSX
- 130-test suite needs re-extraction and update

---

### 📋 Planned / Not Started

**High Priority**
1. ~~IC signal conditioning model~~ ✅ Done
2. ~~IC-topology compatibility filter~~ ✅ Done
3. Flyback SPICE validation in LTspice (plant shape, crossover, PM comparison)
4. Test suite re-sync (extract physics from JSX, update 130 tests)

**Medium Priority**
5. Boost topology (RHPZ, non-isolated) — shares math with flyback
6. IC library expansion (more ICs with verified datasheet parameters)
7. Forward SPICE validation (separate from buck, verify Lm correction effect)

**Lower Priority**
8. Cap SPICE subcircuit parser (import manufacturer .lib files)
9. NGspice WASM integration (blocked by sandbox CSP; works standalone)
10. SPICE export: include IC signal conditioning (diode drops, divider) in netlist

---

## Key Learnings & Recurring Bug Patterns

### n² Reference Direction Errors (found 3× in session 6, more in session 7)
Always verify physical direction when implementing transformer-referred quantities:
- CT sense: `Ri = (Np/Ns) × Rb`, not `Ns/Np × Rb`
- Lm→Sn: slope in numerator (equivalent external slope), not denominator
- Referred magnetizing inductance: `Lm_sec = Lm × n²`, not `Lm / n²`

### Flyback ≠ Buck (found 8+ sites in session 7)
Every function that computes D, Sn, iL_ss, iC, or state equations must have an explicit flyback branch:
- D = Vout/(Vout+Vin_eff) NOT Vout/Vin_eff
- Sn = Vin_pri/Lm NOT (Vin-Vout)/L
- iL_ss = Iout/D' NOT Iout
- iC = iL×D' - Iout NOT iL - Iout

### Error Signal Equilibrium
For isolated converters with optoGain > 1: `vref - H×Vout ≠ 0` at steady state. Use `H × (Vout_nom - Vout)` instead.

### const Use-Before-Define
Unlike `var`, `const` throws ReferenceError if accessed before declaration. This causes blank screen crashes in React. Always verify derived `const` variables are placed AFTER their dependencies (especially after `useState` hooks).

---

## Architecture

- **Single file:** `buck-cm-tool-7.jsx` — React component + all physics inline
- **Layout:** Single-page, left panel (cards) + right panel (metrics + plots)
- **Physics functions:** Lines 1–2500 (standalone, no React dependencies)
- **React component:** Lines 2500–5693
- **IC Library:** Lines 2393–2580
- **Test copy:** `physics-engine-v7.js` (out of sync — needs re-extraction)
