# PEEC_Script Project Guide

## Architecture Overview

PEEC_Script is a cross-language electromagnetic design platform:

```
Octave GUI (topology_wizard.m, analysis_wizard.m)
    ↓ writes JSON config
    ↓ system('python script.py config.json')
Python scripts (generate_om_*.py, call_*.py)
    ↓ calls PyOpenMagnetics C++ bindings
PyOpenMagnetics / PyMKF (C++ via pybind11)
    ↓ returns dict/JSON
Python scripts
    ↓ writes JSON results
Octave GUI reads results
```

**Three-tier data flow:** Octave GUI → JSON → Python → C++ → JSON → Octave

### Key Scripts

| Script | Purpose | Called by |
|--------|---------|----------|
| `call_converter_api.py` | Converter → magnetic design (primary pipeline) | topology_wizard.m |
| `generate_om_topology.py` | Topology equations, MAS input builder | topology_wizard.m |
| `generate_om_recommendations.py` | Adviser API bridge, result formatting | topology_wizard.m |
| `generate_om_excitation.py` | Harmonic excitation for PEEC analysis | analysis_wizard.m |
| `generate_om_prescreen_losses.py` | Fast winding loss pre-screen | analysis_wizard.m |
| `generate_om_waveforms.py` | Analytical voltage/current waveforms | topology_wizard.m |
| `generate_om_visualization.py` | SVG cross-section rendering | topology_wizard.m |
| `export_openmagnetics_database.py` | DB export for Octave GUI | setup / manual |
| `export_wire_database.py` | Wire DB export | setup / manual |
| `call_pyopenmagnetics_api.py` | Legacy MAS-based adviser bridge | topology_wizard.m (legacy path) |

### Shared Module

`om_shared.py` provides common helpers used across all scripts:
- `as_float()`, `clamp()`, `as_list()` — safe type coercion
- `_log()` — stderr print safe for Octave subprocess
- `sanitize_local_key()` — MATLAB-compatible field name sanitizer
- `import_pyopenmagnetics()` — dual-path PyOM import

**Rule: New code must import from `om_shared` instead of defining local copies.**

---

## Critical Invariants

These rules, if violated, cause segfaults or silent failures in the C++ layer:

### 1. Volt-Second Balance (CRITICAL — caused the segfault)
Transformer primary voltage waveforms MUST satisfy ∫V·dt ≈ 0 over one switching period.
Violation causes unbounded flux growth → B field diverges → C++ `process_inputs()` segfaults.
**Fix:** Use `pm.process_converter()` instead of hand-crafting waveforms.

### 2. Array vs Scalar Types
- `outputVoltages`, `outputCurrents` → MUST be JSON arrays, never scalars
- `desiredTurnsRatios` → MUST be a list, not a scalar float
- `operatingPoints` → MUST be an array, not a single object
- Octave `jsonencode(scalar)` produces a number; use `jsonencode({scalar})` for arrays

### 3. Unit Conventions
- `magnetizingInductance.nominal` is in **Henries** (not microhenries)
- `dutyCycle` ∈ [0, 1] (not percentage)
- Waveform `time[]` starts at 0.0 and ends at T = 1/frequency

### 4. Null Safety
- No `null`/`None` values in dicts passed to C++ functions (use `strip_nulls()`)
- C++ pybind11 bindings crash on unexpected None values

### 5. Topology String Matching
MAS topology strings must be exact (case and spacing matter):
- `"Two Switch Forward Converter"` (not `"two-switch-forward"`)
- `"Flyback Converter"` (not `"flyback"`)
- `"Push Pull Converter"` (not `"push-pull"`)

### 6. Waveform Structure
- `turnsRatios` array length = number of secondaries
- Waveform `time[]` must be monotonically increasing
- `processed.dutyCycle` must be in (0, 1), not 0 or 1

---

## PyOpenMagnetics API Surface (v1.3.0)

### Core Functions Used

| Function | Input | Output | Notes |
|----------|-------|--------|-------|
| `pm.process_converter(topology, converter, use_ngspice)` | Underscore topology key (e.g. `"two_switch_forward"`), converter dict | MAS dict with operatingPoints + designRequirements | Generates volt-second-balanced waveforms. Uses underscore keys, NOT MAS formal names. Non-isolated topologies need `outputVoltage`/`outputCurrent` (singular). |
| `pm.calculate_advised_magnetics(mas, max_results, core_mode)` | Full MAS dict | `{"data": [...]}` list of recommendations | Main adviser entry point |
| `pm.design_magnetics_from_converter(topology, converter, max, mode, ngspice, weights)` | Individual args | `{"data": [...]}` | Legacy one-shot API |
| `pm.process_inputs(mas)` | MAS dict | Processed MAS with computed B fields | Computes B=∫V·dt/NAe |
| `pm.get_settings()` / `pm.set_settings(obj)` | None / settings dict | Settings dict / None | Global adviser settings |
| `pm.find_wire_by_name(name)` | Wire name string | Wire data dict | Wire database lookup |
| `pm.find_core_shape_by_name(name)` | Shape name string | Shape data dict | |
| `pm.find_core_material_by_name(name)` | Material name string | Material data dict | |
| `pm.get_wire_names()` | None | List of strings | |
| `pm.get_available_core_shapes()` | None | List of shapes | |

### Known Issues (v1.2.2, may be fixed in v1.3.0)
- **3-winding CoilAdviser crash:** Topologies with ≥3 windings (e.g., multi-output forward) can crash the CoilAdviser. Workaround: limit to 2 windings or catch and retry.
- **magnetizingCurrent inflation:** `process_inputs()` may compute inflated magnetizing current when converter specs have high turns ratios.
- **Settings persistence:** `set_settings()` modifies global state. Always use try/finally with `restore_settings()`.

---

## JSON File Contracts

| Config File | Producer | Consumer | Key Fields |
|-------------|----------|----------|------------|
| `om_topology_config.json` | Octave GUI | `generate_om_topology.py` | mode, topology, converter, advanced |
| `om_topology_results.json` | `generate_om_topology.py` | Octave GUI | status, computed, mas_inputs |
| `om_converter_api_config.json` | Octave GUI | `call_converter_api.py` | topology, converter, max_results, adviser_settings |
| `om_converter_api_results.json` | `call_converter_api.py` | Octave GUI | status, count, data[] |
| `om_waveform_config.json` | Octave GUI | `generate_om_waveforms.py` | topology, converter, topology_results |
| `om_waveform_results.json` | `generate_om_waveforms.py` | Octave GUI | status, waveforms[] |
| `om_excitation_config.json` | Octave GUI | `generate_om_excitation.py` | windings, harmonics, frequency |
| `om_excitation_profile.json` | `generate_om_excitation.py` | Octave GUI | operating_points[] |
| `om_viz_config.json` | Octave GUI | `generate_om_visualization.py` | core_shape, material, windings |
| `om_visualization.svg` | `generate_om_visualization.py` | Octave GUI | SVG image |

### Contract Rules
- Config files: `om_{purpose}_config.json`
- Result files: `om_{purpose}_results.json`
- All configs MUST be valid JSON (UTF-8, no BOM)
- Array fields must be arrays even for single values (see Invariant #2)
- Result `status` is always `"OK"` or `"ERROR"`

---

## Agent Definitions

These specialized sub-agents encode domain knowledge for automated review.

### contract-guardian
**Purpose:** Validates JSON crossing language boundaries — types, required fields, physics constraints.
**Tools:** Read, Grep, Glob, Bash (read-only Python for validation)
**Trigger:** Any `.py` file change, any `om_*_config.json` format change

**Checklist:**
1. `outputVoltages`, `outputCurrents` are JSON arrays, never scalars
2. `desiredTurnsRatios` is a list, not a scalar float
3. `operatingPoints` is an array, not a single object
4. Voltage waveforms on transformer primaries: ∫V·dt ≈ 0 over one period
5. `magnetizingInductance.nominal` is in Henries (not microhenries)
6. `processed.dutyCycle` ∈ (0, 1), not percentage
7. `turnsRatios` length = number of secondaries
8. No `null`/`None` values in dicts passed to C++ functions
9. Waveform `time[]` starts at 0.0 and ends at T = 1/frequency
10. `desiredDutyCycle` format matches `process_converter()` expectations

### topology-equations
**Purpose:** Audits 9 topology calculator classes for physics correctness.
**Tools:** Read, Grep, Glob
**Trigger:** Changes to `generate_om_topology.py`, new topology calculator class

**Checklist:**
1. Power balance: Pin = sum(Vout_i * Iout_i) / efficiency
2. Reflected current sums ALL secondaries, not just first
3. Duty cycle clamped to topology-valid range (two-switch forward: [0.01, 0.49])
4. Turns ratio convention (Np/Ns vs Ns/Np) consistent within each class
5. `build_waveform_preview()` values match `build_operating_points()` excitations
6. MAS topology string exact match (e.g., `"Two Switch Forward Converter"`)
7. Design requirements return dict has all required keys
8. No division by zero in duty cycle / inductance / current calculations

### pyom-interface
**Purpose:** Expert on PyOpenMagnetics black-box C++ API — signatures, return formats, error modes.
**Tools:** Read, Grep, Bash (Python introspection of pm.* signatures)
**Trigger:** Changes to `call_converter_api.py`, `call_pyopenmagnetics_api.py`, `generate_om_recommendations.py`

**Checklist:**
1. Every `pm.*` call wrapped in try/except with return-value type check
2. Return checked for both dict-with-`"error"` and string-containing-`"Exception:"`
3. `apply_adviser_settings()` / `restore_settings()` always in try/finally
4. 3-winding topologies: document CoilAdviser crash risk (v1.2.2)
5. `strip_nulls()` called on `process_inputs()` output before adviser
6. `magnetizingCurrent` inflation bug handled when using `process_inputs()` path

### octave-bridge
**Purpose:** Octave↔Python subprocess reliability — jsonencode quirks, MSYS2 paths, error propagation.
**Tools:** Read, Grep, Glob
**Trigger:** Changes to `.m` files in subprocess path

**Checklist:**
1. `jsonencode()` arrays use cell arrays `{...}` to produce JSON arrays (Octave differs from MATLAB)
2. `system()` Python path quoted for spaces in Windows paths
3. Python fallback chain consistent across all copies in topology_wizard.m
4. `sys.exit(1)` in Python → `error()` in Octave
5. Result file existence checked before `jsondecode(fileread(...))`
6. No raw MSYS2 paths (`/c/Users/...`) leak into JSON config files
7. `jsonencode(struct)` vs `jsonencode({struct})` — verify Octave produces correct array vs object
8. `pkg load` dependencies — verify no Octave packages beyond base are required
9. Python stderr capture — Octave's `system()` with `2>&1` redirect may close stderr pipe; verify `_log()` wrapper is used
10. Octave `fread`/`fclose` pattern — verify UTF-8 encoding parameter is supported

### codebase-hygiene
**Purpose:** Deduplication, debug file cleanup, shared module usage, type hints.
**Tools:** Read, Grep, Glob
**Trigger:** Any `.py` file change

**Checklist:**
1. No new copy-paste of `as_float`, `clamp`, `_log` — import from `om_shared`
2. No new `_debug_*` / `_test_*` / `tmp_*` files committed
3. New functions have parameter type hints
4. New JSON configs follow `om_{purpose}_config.json` naming convention

---

## Sequential Validation Workflow

```
Phase 1: Static Analysis (parallel agents)
  contract-guardian  →  Scan om_*_config.json / om_*_results.json
  topology-equations →  Verify equations in modified calculator classes
  codebase-hygiene   →  Check for new duplication / missing type hints

Phase 2: API Boundary (sequential, after Phase 1)
  pyom-interface     →  Verify pm.* call sites for error handling
  contract-guardian  →  Verify strip_nulls() on process_inputs() output

Phase 3: Integration (sequential, after Phase 2)
  octave-bridge      →  Verify jsonencode/jsondecode + system() patterns
  contract-guardian  →  End-to-end trace: Octave config write → result read

Phase 4: Regression (after Phase 3)
  Run: python call_converter_api.py om_converter_api_config.json (verify OK)
  Verify output JSON against contract-guardian rules
```

**Trigger rules:**
- `.py` file change → Phases 1-3
- `.m` file change in subprocess path → Phase 3
- `om_*_config.json` format change → Full Phases 1-4
- New topology calculator class → Full Phases 1-4
- PyOpenMagnetics version change → Full Phases 1-4

---

## Definition of Done

Before any PR is considered complete:

- [ ] All modified Python scripts import helpers from `om_shared` (no local duplicates)
- [ ] `contract-guardian` checklist passes on all JSON configs
- [ ] `python call_converter_api.py om_converter_api_config.json om_converter_api_results.json` returns `OK`
- [ ] `python generate_om_topology.py om_topology_config.json` returns `OK`
- [ ] No `_debug_*`, `_test_*`, or `tmp_*` files in the commit
- [ ] Volt-second balance maintained on all transformer voltage waveforms
- [ ] PyOpenMagnetics calls wrapped in try/except with proper error return
- [ ] Settings modified via `apply_adviser_settings()` are restored via try/finally
