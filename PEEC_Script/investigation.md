# Magnetic Adviser Algorithm Investigation

## Why This Document Exists

The PyOpenMagnetics magnetic adviser (`calculate_advised_magnetics`) is unreliable and slow — typical runs take 5-120 seconds, multi-winding topologies can exceed the 600-second subprocess timeout, and sometimes it returns no results at all. All databases are local (no network), so the bottleneck is purely computational. This document analyzes the algorithm from C++ source to identify exactly where time is spent and what can be done about it.

---

## Architecture Overview

```
topology_wizard.m  (MATLAB GUI)
    │
    ├── build_mas_structure.m        → MAS JSON (design requirements + operating points)
    ├── build_recommendation_config()→ config JSON (weights, max_results, filters)
    │
    ▼
call_pyopenmagnetics_api.py  (Python bridge)
    │
    ├── Python fallback chain: Octave 3.12 → py launcher → Python 3.11
    ├── 600-second subprocess timeout
    │
    ▼
generate_om_recommendations.py  (Python wrapper, ~1430 lines)
    │
    ├── pm.load_databases({})                    ~2s first call, cached after
    ├── pm.process_inputs(mas)                   ~50-200ms (validates, adds harmonics)
    ├── strip_nulls()                            ~10ms
    ├── pm.calculate_advised_magnetics(          ★ THE BOTTLENECK: 5-120+ seconds
    │       processed, max_results, "available cores")
    ├── Post-filter: local DB match, wire family, UI weight rerank
    │
    ▼
topology_wizard.m  (displays results)
```

---

## The Three-Stage C++ Pipeline

The C++ function `MagneticAdviser::get_advised_magnetic()` (MagneticAdviser.cpp:59) orchestrates three stages:

### Stage 1: Core Selection (CoreAdviser)

**Source**: `CoreAdviser.cpp:587` → `filter_available_cores_power_application()` at line 1347

**What it does**: Takes the full core database (~1271 cores) and progressively filters/scores them.

```
All 1271 cores
    │
    ├── create_magnetic_dataset()           Build Magnetic objects, skip:
    │     ├── Wrong material application      - suppression materials for power apps
    │     ├── Toroidal (if disabled)          - settings.get_use_toroidal_cores()
    │     ├── Concentric (if disabled)        - settings.get_use_concentric_cores()
    │     ├── Printed winding incompatible    - toroidal/2-column cores
    │     ├── Gap processing failure          - core.process_gap() returns false
    │     ├── Height exceeds max              - TWO_PIECE_SET only
    │     └── Distributed gaps (if disabled)  - gap count > column count
    │
    ├── AreaProduct filter (BINARY pass/fail, weight=1.0 fixed)
    │     Eliminates cores too small for AP = Aw × Ac requirement
    │     Uses MagneticFilterAreaProduct.evaluate_magnetic()
    │     Reference B_peak = 0.18T (hardcoded in MagneticFilter.h:40)
    │
    ├── Intermediate pruning (if enabled)
    │     Truncates to maximumMagneticsAfterFiltering (settings, default ~500)
    │     Keeps top-scoring cores from AreaProduct
    │
    ├── EnergyStored filter (BINARY pass/fail, weight=1.0 fixed)
    │     Validates L × I² / 2 capacity without saturation
    │     Assigns initial gap + turns via NumberTurns model
    │
    ├── add_initial_turns_by_inductance()
    │     Computes N = √(L × R_reluctance) for each surviving core
    │
    ├── Cost filter (SCORED, weight = user COST weight)
    │     MagneticFilterEstimatedCost: wire area × density × cost/kg + core cost
    │     Log normalization, inverted (cheaper = better)
    │
    ├── Dimensions filter (SCORED, weight = user DIMENSIONS weight)
    │     MagneticFilterDimensions: core volume
    │     LINEAR normalization (not log!), inverted (smaller = better)
    │
    └── Losses filter (SCORED, weight = user EFFICIENCY weight)
          MagneticFilterCoreAndDcLosses: Steinmetz core loss + DC winding loss
          Log normalization, inverted (lower = better)

    Result: Top N cores with composite score, trimmed to maximumNumberResults
    Unique core shapes enforced (cull_to_unique_core_shapes)
```

**Scoring formula** (CoreAdviser.h:43-44):
```
final_score = Σ (normalized_score_i × weight_i)   for i in {COST, EFFICIENCY, DIMENSIONS}
```

Normalization modes:
- COST: `invert=true, log=true` — logarithmic, cheaper is better
- EFFICIENCY: `invert=true, log=true` — logarithmic, lower losses is better
- DIMENSIONS: `invert=true, log=false` — LINEAR, smaller is better (2× larger scores 2× worse)

### Stage 2: Winding Optimization (CoilAdviser)

**Source**: `CoilAdviser.cpp:72` → `get_advised_coil()` → `get_advised_coil_for_pattern()` at line 297

**What it does**: For EACH surviving core from Stage 1 (up to 50 cores), finds optimal wire/winding configurations.

```
For each core:
    │
    ├── Generate patterns × repetitions
    │     patterns = Coil::get_patterns(inputs, coreType)     typically 1-3
    │     repetitions = Coil::get_repetitions(inputs, coreType) typically 1-2
    │     (interleaved vs non-interleaved, winding order permutations)
    │
    ├── For each (pattern, repetition):
    │     ├── Get insulation combos (margin tape vs wire-insulated)
    │     ├── wind_by_sections() — compute section proportions
    │     │
    │     ├── For each winding (1 to N):
    │     │     ├── WireAdviser.get_advised_wire() — searches ENTIRE wire DB
    │     │     │     Wire DB: ~4329 entries (round, litz, foil, rectangular, planar)
    │     │     │     Filtered by settings: include_planar, include_foil, etc.
    │     │     │     Filtered by wire standard (if set)
    │     │     │
    │     │     └── 4 wire configurations tried per winding:
    │     │           Config 1: default J_max, default parallels
    │     │           Config 2: default J_max, 2× parallels
    │     │           Config 3: 2× J_max,     default parallels
    │     │           Config 4: 2× J_max,     2× parallels
    │     │           (CoilAdviser.cpp:407-412)
    │     │
    │     └── Cartesian product of wire choices across windings:
    │           For 2 windings × 10 wire options each = 100 combinations
    │           For 3 windings × 10 wire options each = 1000 combinations
    │           Each combo: coil.wind() → physical layout + insulation clearance
    │           timeout = 1 - numberWindings (CoilAdviser.cpp:363) ← very tight!
    │
    └── Score all wound designs by:
          - MagnetomotiveForce (field quality)
          - EffectiveResistance (AC winding losses)
          - EffectiveCurrentDensity (heat generation)
          Sort, trim to maximumNumberResults per pattern
```

**This is the biggest bottleneck.** Each `wind()` call involves:
- Physical turn placement in bobbin window
- Insulation clearance calculation per IEC standards
- Wire dimension fitting (can fail → retry with different wire)

### Stage 3: Full Simulation (MagneticSimulator)

**Source**: `MagneticAdviser.cpp:185`

**What it does**: For each wound design from Stage 2, runs full electromagnetic simulation.

```
For each wound Mas:
    │
    ├── magneticSimulator.simulate(mas)
    │     ├── Core losses: Steinmetz/iGSE with temperature iteration
    │     ├── Winding losses: ohmic + skin effect + proximity effect (PEEC)
    │     ├── Inductance: Lm (reluctance model), Llk (PEEC)
    │     └── Thermal convergence: iterative loss↔temperature loop (3-5 iterations)
    │
    └── Early exit: processedCoils >= ceil(maximumNumberResults * 0.5)
          (MagneticAdviser.cpp:190)
```

### Top-Level Loop (MagneticAdviser)

**Source**: `MagneticAdviser.cpp:133`

```cpp
maxWhileIterations = 2;       // Max retry iterations
maxEvaluatedCores = 50;       // Hard cap on cores entering CoilAdviser
requestedCores increment = +20 per iteration (linear, not exponential)

while (coresWound < expectedWoundCores
       && whileIteration < 2
       && evaluatedCores < 50) {

    cores = CoreAdviser.get_advised_core(inputs, weights, requestedCores)

    for each core:
        skip if already evaluated (dedup by core name)
        coils = CoilAdviser.get_advised_coil(mas, ceil(max_results / cores.size()))
        if coils found: coresWound++

        for each coil:
            dedup by (numberSections, margin) combo
            simulate(mas)
            if processedCoils >= 50% of max_results: break

        if coresWound >= expectedWoundCores: break
}

// Retry without toroids if empty results and toroids were enabled
if (empty && toroidsWereEnabled) {
    disable toroids, clear state, repeat entire loop
}

score_magnetics(all_results, filterFlow)  // COST × LOSSES × DIMENSIONS
sort by score, trim to max_results
```

---

## Key Hardcoded Parameters

| Parameter | Value | Location | Impact |
|-----------|-------|----------|--------|
| `maxWhileIterations` | 2 | MagneticAdviser.cpp:131 | Limits core search retries |
| `maxEvaluatedCores` | 50 | MagneticAdviser.cpp:132 | Hard cap on cores entering CoilAdviser |
| `requestedCores` growth | +20/iteration | MagneticAdviser.cpp:135 | Linear growth rate |
| `maximumMagneticsAfterFiltering` | ~500 (settings) | CoreAdviser.cpp:590 | Pruning threshold between filters |
| Wire configurations | 4 per winding | CoilAdviser.cpp:407-412 | 2 J_max × 2 parallel limits |
| CoilAdviser timeout | `1 - numberWindings` | CoilAdviser.cpp:363 | Very tight for multi-winding! |
| `processedCoils` early exit | 50% of max_results | MagneticAdviser.cpp:190 | Limits simulation count |
| B_peak reference | 0.18 T | MagneticFilter.h:40 | AreaProduct pre-filter threshold |
| High voltage toroid cutoff | 600V | MagneticAdviser.cpp:80 | Auto-disables toroids |
| Subprocess timeout | 600 seconds | call_pyopenmagnetics_api.py:366 | Python wrapper kill timeout |
| Pool size (1-2 windings) | max(max_results×2, 10) | generate_om_recommendations.py:748 | Oversample for filtering |
| Pool size (3+ windings) | min(max_results, 3) | generate_om_recommendations.py:746 | Capped to avoid timeout |

---

## Database Sizes

| Database | Entries | File Size | Notes |
|----------|---------|-----------|-------|
| Cores | 1,271 | 846 KB | All manufacturers, all shapes |
| Materials | 409 | 194 KB | 94 have Steinmetz data |
| Wires | 4,329 | 2.5 MB | Round, litz, foil, rectangular, planar |
| Suppliers | 15 | 8.6 KB | Micrometals(93), Magnetics(69), ACME(56)... |

Core shapes by family: E, EFD, ETD, EI, EP, ER, PQ, PM, RM, Toroid, Planar, U, C, and more.

---

## Root Causes of Problems

### Why It's Slow

1. **No pre-filtering by user intent**: All 1271 cores enter the pipeline regardless of whether the user only wants E-cores from TDK. The AreaProduct filter is the first real elimination, but it still evaluates every core.

2. **CoilAdviser brute-force wire search**: For each surviving core, WireAdviser searches the entire 4329-wire database × 4 configurations. With multiple windings, the Cartesian product explodes: 2 windings × 10 wires each = 100 `wind()` calls; 3 windings = 1000.

3. **Single-threaded**: The entire C++ pipeline is sequential. No parallelism across cores or wire combinations.

4. **MagneticSimulator per design**: Full PEEC proximity loss + thermal convergence (~100-500ms per design) runs on every surviving wound design.

5. **Multi-winding exponential scaling**: The CoilAdviser timeout formula `1 - numberWindings` means 3+ windings have almost no search budget, yet the combinatorial space is largest.

### Why It's Unreliable

1. **C++ segfault with insulation + 3+ windings**: The MKF C++ code crashes (ACCESS_VIOLATION) when insulation data is present for multi-winding topologies. Current workaround: strip insulation before adviser call, restore after (generate_om_recommendations.py:752-762).

2. **Empty results from bad waveforms**: If operating point excitations have zero amplitude (a common bug when topology calculators don't populate `current.processed`), the AreaProduct and EnergyStored filters eliminate ALL cores. The adviser returns empty.

3. **Toroid retry doubles execution time**: If toroids are enabled and the first pass fails, the entire pipeline re-runs with toroids disabled (MagneticAdviser.cpp:213-283). This doubles wall time for a common failure mode.

4. **Python fallback chain fragility**: Octave 10.3.0 bundles Python 3.12.8 which lacks PyOpenMagnetics. The fallback chain (try `py -3.11`, `where python`, etc.) adds startup latency and can fail on non-standard installations.

---

## Time Breakdown (Estimated)

For a typical 2-winding Two-Switch Forward design requesting 5 results:

| Stage | Time | % of Total | Notes |
|-------|------|-----------|-------|
| Python startup + DB load | 2-3s | 5% | Cached after first call |
| `process_inputs()` | 0.1-0.2s | <1% | Fast validation |
| CoreAdviser (all filters) | 3-15s | 15-25% | 1271 cores through 5 filters |
| CoilAdviser (per core, ~10-20 cores) | 15-60s | 50-70% | Wire search + wind() attempts |
| MagneticSimulator (per design) | 5-20s | 15-25% | PEEC + thermal per wound design |
| Post-processing + JSON I/O | 0.5-1s | <2% | Negligible |
| **Total** | **25-100s** | | Typical range for 2-winding |

For 3+ windings: multiply CoilAdviser time by 3-10× due to combinatorial explosion.

---

## Optimization Approaches

### Approach A: Pre-Filtering Knobs (Python-side, no C++ changes)

**Concept**: Add user-facing GUI controls in topology_wizard.m that filter the core/wire databases BEFORE calling the C++ adviser. Pass only matching cores to the adviser.

**New controls**:
- Core shape family multi-select (E, ETD, EFD, PQ, RM, Toroid, Planar, etc.)
- Manufacturer filter (TDK, Ferroxcube, Fair-Rite, Magnetics, etc.)
- Material type (Ferrite only, Powder only, Both)
- Max core dimensions (width × height × depth) — partially exists already
- Wire type filter — already exists (`wire_family_mode`)

**How it works**: In `generate_om_recommendations.py`, before calling `calculate_advised_magnetics()`:
1. Load core database, filter by user's shape/manufacturer/material selections
2. Either: (a) modify the loaded `coreDatabase` global before the adviser runs, or (b) use the `custom cores` CoreAdviser mode to pass a pre-filtered list

**Pros**:
- Fastest to implement — Python-only changes, no C++ recompilation
- Biggest bang-for-buck: selecting "ETD + E cores, TDK only" reduces 1271 → ~50 cores
- User gets exactly the design space they're interested in
- Composable with all other approaches
- Reduces CoilAdviser work proportionally (fewer cores = fewer wind() calls)

**Cons**:
- User must know what they want (wrong filter = missed good options)
- Need sensible defaults for users who don't know core families
- Filtering happens outside the C++ scoring — might miss cores that would score well
- Still slow if user selects "all cores" (no filter)

**Effort**: Low-medium. ~1-2 days for GUI controls + Python filtering logic.

**Impact**: 5-20× speedup depending on filter aggressiveness.

---

### Approach B: Two-Pass Fast-Then-Detailed Strategy

**Concept**: Split the adviser into two phases:
1. **Quick pass** (~1-5s): Run only CoreAdviser (Stage 1) to get top ~10-20 core candidates with estimated scores. Show these to user.
2. **Detailed pass** (~10-30s): Run CoilAdviser + MagneticSimulator only on the 1-3 cores the user selects.

**How it works**:
1. New mode in `generate_om_recommendations.py`: `mode: "core_only"` that calls `CoreAdviser.get_advised_core()` directly
2. Returns core shape, material, estimated losses, volume, cost score — no winding details
3. User sees a quick preview table, picks their preferred core(s)
4. Second call with `mode: "full"` runs the complete pipeline on just those cores

**Pros**:
- Fast interactive feedback — user sees core options in 1-5 seconds
- User agency: they choose the core, not the algorithm
- Detailed optimization focused on user's choice — higher quality results
- Natural workflow: browse cores → pick → optimize windings
- Avoids wasting time optimizing windings for cores the user would reject

**Cons**:
- Two API calls instead of one — more complex GUI flow
- User needs enough knowledge to pick a reasonable core
- CoreAdviser scores (no winding info) may not accurately predict final ranking
- Requires new GUI elements (preview table, selection, "optimize" button)
- The CoreAdviser stage is still somewhat slow for large databases (~3-15s)

**Effort**: Medium. ~2-3 days for new API mode + GUI flow.

**Impact**: 2-10× perceived speedup (fast feedback), total computation similar if user picks 1 core.

---

### Approach C: Custom Python Scorer (Bypass MKF Adviser)

**Concept**: Build a lightweight scoring system in Python that replaces the C++ adviser entirely for core selection. Use the local JSON databases directly.

**Algorithm**:
1. Load `openmagnetics_core_database.json` (1271 cores with pre-computed Ae, le, Aw, volume)
2. For each core, compute:
   - Area Product check: AP = Aw × Ae ≥ required AP (from Lm, Ipeak, Bmax, J, kw)
   - Energy check: ½ L I² ≤ ½ Bsat² Ae le / μ₀μᵣ
   - Estimated core loss: Steinmetz P = k × f^α × B^β × Ve (from material database)
   - Estimated cost: proportional to core volume × material density
   - Dimension score: Euclidean distance from target size
3. Rank by weighted score (same COST/LOSSES/DIMENSIONS weights)
4. Return top N cores — no winding optimization
5. User picks a core → proceeds to `interactive_winding_designer.m` where our PEEC solver does detailed design

**Pros**:
- Extremely fast: pure Python math on pre-loaded JSON, ~0.1-0.5 seconds
- Full control: we own the algorithm, can debug and tune freely
- No C++ crashes, segfaults, or DLL issues
- Simpler architecture: remove PyOpenMagnetics adviser dependency for core selection
- Can add custom scoring criteria (e.g., prefer cores we have physical samples of)
- Works even when PyOpenMagnetics is not installed

**Cons**:
- Re-implements what MKF already does (Area Product, Energy, Steinmetz)
- No winding optimization — user must design windings manually in interactive_winding_designer
- Loses CoilAdviser intelligence (wire selection, interleaving, insulation coordination)
- Steinmetz estimation without temperature iteration is less accurate
- Maintenance burden: must keep formulas in sync with MKF if models improve
- Doesn't compute inductance verification (no gap/reluctance calculation)

**Effort**: Medium. ~2-3 days for Python scorer + integration.

**Impact**: 100-1000× speedup for core selection. But loses winding optimization entirely.

---

### Approach D: PyOpenMagnetics Settings Tuning (Quick Win)

**Concept**: Expose existing MKF C++ settings that are currently hidden/hardcoded, and tune them for faster execution.

**Available settings** (from `pm.get_settings()` / `pm.set_settings()`):
- `useToroidalCores` (bool) — already partially exposed
- `useOnlyCoresInStock` (bool) — limits to "in stock" cores
- `useConcenticCores` (bool) — exclude piece-and-plate types
- `coreAdviserMaximumMagneticsAfterFiltering` (int, default ~500) — **reduce to 50-100**
- `wireAdviserIncludeRound` / `IncludeLitz` / `IncludeFoil` / `IncludeRectangular` / `IncludePlanar` (bools)
- `coilAdviserMaximumNumberWires` (int) — limit wire search per winding
- `coreAdviserIncludeStacks` (bool) — disable stacked core combinations
- `coreAdviserIncludeDistributedGaps` (bool) — disable distributed gap variants
- `coilMaximumLayersPlanar` (int) — limit planar winding layers

**Key tuning**:
1. Set `coreAdviserMaximumMagneticsAfterFiltering = 100` (from ~500) — 5× fewer cores survive to expensive filters
2. Disable `coreAdviserIncludeStacks` — eliminates stacked core variants
3. Disable wire types the user doesn't want — reduces WireAdviser search space
4. Set `coilAdviserMaximumNumberWires = 10` (from default) — limits wire combos per winding

**Pros**:
- Zero code changes for basic tuning — just `pm.set_settings()` calls
- Immediate impact: reducing intermediate pruning threshold from 500 to 100 = 5× less work
- Wire type filtering is already supported in C++
- Can be done alongside any other approach

**Cons**:
- Limited knobs: can't filter by manufacturer/shape family via settings
- Reducing pruning threshold risks missing good candidates (quality-speed tradeoff)
- Some settings may not be exposed through PyOpenMagnetics Python bindings
- Still fundamentally the same brute-force algorithm

**Effort**: Very low. ~0.5-1 day.

**Impact**: 2-5× speedup from settings alone.

---

### Approach E: Hybrid (A + B + D)

**Concept**: Combine pre-filtering, two-pass strategy, and settings tuning for maximum impact.

**Implementation order**:
1. **Phase 1** (Quick Win): Settings tuning (Approach D) — immediate 2-5× speedup
2. **Phase 2** (Medium Win): Pre-filtering knobs (Approach A) — additional 5-20× for filtered searches
3. **Phase 3** (UX Win): Two-pass strategy (Approach B) — fast interactive feedback

**Expected total impact**: 10-100× speedup for typical use cases.

**Pros**:
- Incremental delivery: each phase adds value independently
- Covers all scenarios: constrained search (A), interactive browsing (B), default tuning (D)
- No C++ changes needed
- Preserves MKF winding optimization quality

**Cons**:
- Most implementation effort (~4-6 days total)
- More GUI complexity (filter controls + preview table + optimize button)
- Must handle all combinations of options cleanly

---

### Approach F: Alternative — Precomputed Core Index

**Concept**: Pre-compute and cache a core scoring index offline. At query time, just look up scores instead of computing them.

**How it works**:
1. Offline: For each core in database, pre-compute AreaProduct range, volume, estimated cost
2. Store as `core_index.json` with pre-sorted lists by AP, volume, cost
3. At query time: binary search for cores matching AP requirement, intersect with volume/cost constraints
4. Return matches in ~10ms

**Pros**:
- Near-instant core lookup (<100ms)
- One-time computation cost
- Can include richer pre-computed data (multiple Bmax scenarios, multiple frequencies)

**Cons**:
- Must regenerate index when database changes
- Pre-computed scores are frequency/current-independent (generic)
- Doesn't replace winding optimization
- Additional file to maintain and version

**Effort**: Low-medium. ~1-2 days.

**Impact**: Core selection becomes instant. Still need CoilAdviser for winding design.

---

## Summary Comparison

| Approach | Speedup | Effort | Quality Impact | C++ Changes |
|----------|---------|--------|---------------|-------------|
| A: Pre-filter knobs | 5-20× | Low-Med | None (user filters) | None |
| B: Two-pass strategy | 2-10× perceived | Medium | Slight (user picks core) | None |
| C: Custom Python scorer | 100-1000× | Medium | Moderate (no winding opt) | None |
| D: Settings tuning | 2-5× | Very Low | Slight (fewer candidates) | None |
| E: Hybrid A+B+D | 10-100× | Med-High | Minimal | None |
| F: Precomputed index | 1000×+ lookup | Low-Med | Moderate (generic scores) | None |

---

## Key Source File References

| File | Lines | What's There |
|------|-------|-------------|
| `MKF-main/src/advisers/MagneticAdviser.cpp` | 59-199 | Main adviser loop, 50-core cap, retry logic |
| `MKF-main/src/advisers/MagneticAdviser.h` | 107-199 | Class definition, filter flow defaults, weight guidelines |
| `MKF-main/src/advisers/CoreAdviser.cpp` | 587-619 | Core search entry point, stack expansion retry |
| `MKF-main/src/advisers/CoreAdviser.cpp` | 633-727 | `create_magnetic_dataset()` — builds candidate list with exclusion filters |
| `MKF-main/src/advisers/CoreAdviser.cpp` | 1347-1413 | `filter_available_cores_power_application()` — 5-filter cascade |
| `MKF-main/src/advisers/CoreAdviser.h` | 97-338 | CoreAdviser class, filter configuration, normalization modes |
| `MKF-main/src/advisers/CoilAdviser.cpp` | 72-185 | `get_advised_coil()` — pattern/repetition loop |
| `MKF-main/src/advisers/CoilAdviser.cpp` | 297-496 | `get_advised_coil_for_pattern()` — wire search + wind() loop |
| `MKF-main/src/advisers/MagneticFilter.h` | 22-370 | All 25+ filter classes |
| `PEEC_Script/generate_om_recommendations.py` | 627-900 | Python wrapper: pool sizing, insulation workaround, post-filtering |
| `PEEC_Script/call_pyopenmagnetics_api.py` | 262-467 | Python bridge, subprocess timeout, fallback chain |
| `PEEC_Script/topology_wizard.m` | 2962-3258 | GUI recommendation flow + config building |

---

## Open Questions for Future Investigation

1. **Can we call `CoreAdviser.get_advised_core()` directly from Python?** If yes, Approach B becomes trivial. Need to check if PyOpenMagnetics exposes this as a separate function.

2. **What does `coreAdviserMaximumMagneticsAfterFiltering` default to?** The C++ reads it from `settings` — need to check the default value in the Settings class.

3. **Can we pass a pre-filtered core list to `calculate_advised_magnetics()`?** The C++ has a `CUSTOM_CORES` mode but it's unclear if PyOpenMagnetics Python bindings expose it.

4. **Is the CoilAdviser timeout formula correct?** `timeout = 1 - numberWindings` seems like it would be 0 for a single winding and -1 for 2 windings. Need to trace how `timeout` is incremented by successful wire finds (line 431: `timeout += wiresWithScoring.size()`).

5. **Why does the insulation + multi-winding combination crash?** The C++ segfault (ACCESS_VIOLATION) suggests a null pointer or buffer overflow in InsulationCoordinator when processing 3+ windings with full insulation data. This is a bug in MKF, not our code.
