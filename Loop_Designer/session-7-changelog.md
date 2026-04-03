# Session 7 Changelog — buck-cm-tool-7.jsx (5,693 lines)

## Summary
Major UI refactor to single-page layout, flyback topology fully debugged across all tabs, primary-side feedback mode added, IC signal conditioning model implemented, Loop Design Advisor built, and SPICE export extended for flyback.

---

## UI Refactor: Single-Page Layout
- **REMOVED** two-page Setup → Analyze navigation and "Analyze Control Loop →" button
- **NEW** single-page side-by-side layout:
  - Left panel (300px): toggle bar + stacked parameter cards + comp + load transient
  - Right panel: metrics bar + tab bar (Bode, Transient, Sweep, Zcap, Audio, Diagnostics, Equations) + plots
- Toggle bar buttons: `[TOPO] [IC] [XFMR] [PWR] [CAPS] [SENSE] [SLOPE] [FB] [EA] [COMP]`
- Cards hide/show via toggle; state preserved when hidden
- Card order: Topology → Controller IC → Operating Point → Transformer → Power Stage → Caps → Sense → Slope → FB → EA → Comp
- Compensator card (Type-II/III, Auto/Manual, RECALCULATE, component values) moved to left panel
- SPICE export buttons restored on Bode tab

## Flyback Physics Fixes (Critical)

### analyzeLoop (Sweep tab)
- **BUG:** Used buck D = Vout/Vin and Sn = (Vin-Vout)/L for ALL topologies
- **FIX:** Flyback uses D = Vout/(Vout+Vin_eff), Sn = Vin_pri/Lm × Ri
- **Impact:** Sweep tab was showing false subharmonic instability for flyback (D_buck=98% instead of correct D_fly=45%)

### simTimeDomain (Transient tab) — 5 bugs fixed
1. **D_ss:** Was Vout/Vin (buck). Fixed to Vout/(Vout+Vin) for flyback
2. **Sn_vs:** Was (Vin-Vout)/L×Ri. Fixed to Vin_pri/Lm × Ri for flyback
3. **iL initial condition:** Was `Iout`. Fixed to `Iout/D'` for flyback (secondary-referred magnetizing current)
4. **Error signal equilibrium:** `vref - H×Vout` gave -10V error at SS when optoGain≠1. Fixed to `H × (Vout_nom - Vout)` which gives 0 at operating point
5. **deriv() iC:** Was `iL - Iout` (buck) for all topologies before the flyback branch. Restructured: each branch computes its own iC and vout_sense
6. **Sn_total:** Was `Sn_vs × mc + se_vs` (double-counts Se). Fixed to `Sn_vs + se_vs`
7. **dvC in flyback branch:** Used constant `vout_nom` instead of actual `vC` from state. Fixed to use `vC + ESR × iC`
8. **iC in recording section:** Was `iL - Iout`. Fixed to `iL×D' - Iout` for flyback

### evalZout_open
- **BUG:** Used buck sub-blocks Gvi/(1+Ti) for flyback — gave wrong Ti(DC)
- **FIX:** Flyback uses Rload || Zcap(s) directly (same as gm_ps mode)
- Verified: Zout_open(DC) = 6.0Ω = Rload for flyback ✅

### Zout display
- Shows "N/A — loop unstable" when PM < 0° (was showing meaningless sub-mΩ values)
- Uses fmtSI() for proper prefix formatting

### Ti(0) warnings suppressed for flyback
- Ti(0) from buck sub-block decomposition not applicable to Basso/Richtek model
- Suppressed in: validation function, COMP card, bottom info bar, diagnostics tab
- Diagnostics tab shows explanation when flyback selected

## Multi-Winding Transformer
- XFMR card shows "SECONDARY WINDINGS" section for both topologies
- **Forward:** Each aux winding has Ns, Lout, Vout + per-winding caps (Qty, C, ESR)
- **Flyback:** Each aux winding has Ns, Vout + per-winding caps (no Lout)
- Up to 3 auxiliary windings
- Physics: all 3 aux slope calculation sites guarded with `topology !== "flyback"`
- Flyback note: "Aux windings are cross-regulated. They do not affect the control loop."

## Primary-Side Feedback Mode
- New toggle on FB card: `[OPTOCOUPLER]` vs `[PRIMARY-SIDE]`
- **Optocoupler:** Existing behavior — CTR, Rpullup, Rled, Copto
- **Primary-side:** optoGain=1, fp_opto=0 (no pole), H_dc = Vref/Vout
- Eliminates opto pole phase loss entirely
- Cross-regulation warning displayed
- Snapshot, log, and advisor all updated

## IC Signal Conditioning Model
New per-IC fields:
- `compDividerRatio` — internal divider (e.g., 3 for UC384x, ISL7104x)
- `compDiodeDrop_V` — diode drop (e.g., 1.4V for UC384x, 1.15V for ISL7104x)
- `csOffset_mV` — CS comparator offset (e.g., 100mV for ISL7104x)

Derived `compGain = 1/dividerRatio` scales the plant in loop gain T(s) at ALL sites:
- Main Bode computation
- evalZout_closed
- evalGvg_closed
- analyzeLoop (sweep)
- autoPlace (Type-II)
- autoPlaceType3

Verified: compGain=1/3 reduces |T| by exactly 9.5dB = 20·log₁₀(3) ✅
Autoplacer compensates by boosting fi proportionally.

Purple "Signal Conditioning" info box shows on IC card when divider/diodes are present.

## IC Topology Compatibility Filter
Each IC has `supportedTopologies` array. Dropdown only shows compatible ICs:

| IC | Buck | 2SW Fwd | Flyback |
|---|---|---|---|
| TPS7H4011 | ✅ | | |
| UCC28C43 | ✅ | ✅ | ✅ |
| UCC28C44 | ✅ | ✅ | |
| UC3842/3 | ✅ | ✅ | ✅ |
| UC3844/5 | ✅ | ✅ | |
| UCC28780 | | | ✅ |
| ISL71043M | ✅ | ✅ | ✅ |
| ISL71041M | ✅ | ✅ | |

Removed: LM3478, NCP1200, LT3748 (unverified parameters)

## Loop Design Advisor
- Hybrid: tries Claude API (5s timeout via Promise.race), falls back to local analyzer
- Local analyzer computes exact phase budget at crossover:
  - Phase table: each contributor ranked by magnitude
  - Top 3 phase killers identified
  - Status assessment (stable / marginal / unstable)
  - 2–6 design options with specific parameter changes and expected improvement
- Shows `[AI Advisor]` or `[Local Analysis]` header
- Located at bottom of Bode tab

## Phase Tooltip Fix
- Separate `TT_ph` tooltip for phase chart showing degrees (°) not dB
- Magnitude chart keeps `TT` with dB

## Transient Tab Improvements
- Rise time input widened to 70px (4 sig figs visible)
- Output voltage chart: full recovery view (auto-sized based on plant pole, up to 10ms)
- iL and VCOMP/D charts: auto-zoomed to fast dynamics (8τ of crossover)
- Slew limiting explanation text when SOURCE/SINK LIMITED

## Flyback SPICE Export
- New flyback averaged plant model in .CIR generator:
  - **.ac:** Laplace behavioral source with Basso/Richtek transfer function including RHPZ and He(s)
  - **.tran:** Averaged nonlinear model with behavioral D, Lm_sec inductor, and D'-scaled output current
- Correct D, Sn, mc, Fm, initial conditions for flyback
- EXPORT .CIR buttons restored on Bode tab for all topologies

## Comp Freeze Behavior Restored
- Removed auto-recalculate effect that was recomputing comp on every parameter change
- Comp values only update on explicit RECALCULATE click or compType change
- Enables corner sweeping with frozen network

## Bug Fixes
- `const isFlyback` used before declaration in SPICE generator → moved before first use
- `selICobj`, `compDividerRatio`, `compGain` defined before `selectedIC` was available → moved after useState hooks
