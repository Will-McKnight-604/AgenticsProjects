# AI Agent Handoff (2026-02-21)

## Scope + Environment
- Repository/worktree: `C:\Users\Will\proximity_loss\codex-cli-feature-work\PEEC_Script`
- Branch: `optimization`
- User requirement: all work for this topic must stay in this worktree/branch.

## What Was Completed

### 1) Fast-loss cap policy update (tuning constraints)
Updated tuning criteria to enforce tighter fast-mode error limits:
- `validation/optimization_pass_criteria.m`
  - Added `fast_loss_error_target_pct = 10.0`
  - Changed `max_fast_loss_err_pct_max` from `30.0` to `15.0`

### 2) Tuning objective/scoring updated to use target+hard cap
Updated tuning evaluation to:
- penalize configs above target (10%)
- hard-gate outliers above 15%
- avoid stale cached results after scoring/policy changes

File changed:
- `validation/evaluate_tuning_config.m`
  - Added `flags.fast_target_ok`
  - Added score penalties above target and stronger penalties above hard max
  - Versioned cache key via `eval_policy_version = 'eval_v3_fastcap_10_15'`
  - Included criteria/objective weights in cache key payload

### 3) Fixed a major reason iterative policy was collapsing to direct
When case policy chose iterative, it still set `linear_solver='auto'`, so lower-level auto guards often re-routed to direct.

File changed:
- `validation/choose_solver_policy.m`
  - In iterative branches (fast/standard), switched from:
    - `linear_solver = 'auto'`
    - to `linear_solver = 'bicgstab'`
  - This forces iterative when policy explicitly chooses iterative.

## Current Investigation (In Progress)

User-reported failures while running `topology_wizard`:
1. Core-loss schema error:
   - `Core loss calc failed: Input JSON does not conform to CoreLossesModels schema: "iGSE"`
2. iGSE/Steinmetz parameters not passed into interactive GUI behavior as expected.
3. OM visualization warning:
   - `wind_by_layers failed (Exception: Input JSON does not conform to schema!), falling back to pm.wind()`

### Root-cause findings so far

#### A) Core-loss schema failure is reproducibly sourced to this code path:
- `generate_om_recommendations.py` in `compute_losses_for_recommendation(...)`
  - currently calls:
    - `models = {"coreLosses": "iGSE", "reluctance": "Zhang"}`
    - `pm.calculate_core_losses(core, coil, inputs_data, models)`
  - error indicates this explicit model JSON is invalid for current PyOpenMagnetics schema/runtime.

Likely fix direction:
- stop forcing model enum strings for this call and use default model selection (empty models struct) or accepted schema object shape.

#### B) Wizard -> GUI iGSE/Steinmetz propagation gap
- `topology_wizard.m` builds `spec.recommendation` from advisor output but does not pass explicit core-loss method/Steinmetz fields in design spec.
- `interactive_winding_designer.m` initializes:
  - `data.core_loss_method = 'iGSE'`
  - `data.steinmetz.*` from material DB lookup (`get_steinmetz_coefficients`)
- If material DB lacks steinmetz ranges for selected material/frequency, analysis logs:
  - `Core loss (N/A (no Steinmetz data))`

Potential mismatch also found:
- MKF reference attachment currently expects:
  - `rec.core_loss_W`, `rec.winding_loss_W`
- but recommendation generator writes:
  - `core_losses_w`, `winding_losses_w`
- This means MKF reference values can be dropped silently in analysis display.

#### C) Additional schema/winding warning in visualization
- `generate_om_visualization.py` tries:
  - `wind_by_sections -> wind_by_layers -> wind_by_turns`
- for some configs, `wind_by_layers` fails schema validation and falls back to `pm.wind()`.
- This is handled gracefully but indicates config shape drift or unsupported combination.

## Files Inspected During Current Debug
- `generate_om_recommendations.py`
- `topology_wizard.m`
- `interactive_winding_designer.m`
- `openmagnetics_api_interface.m`
- `generate_om_visualization.py`

## Work Remaining (Priority Order)

### Priority 1: Fix core-loss schema failure in recommendations
Implement in `generate_om_recommendations.py`:
- In `compute_losses_for_recommendation(...)`
  - replace explicit invalid models payload with schema-safe/default call
  - keep backward-compatible retry strategy:
    1. default models (`{}`)
    2. optional legacy attempt only if needed
  - preserve detailed error logging per attempt

Validation:
- run `topology_wizard` -> `Get Recommendations`
- confirm repeated `[LOSS] Core loss calc failed ... CoreLossesModels schema` messages disappear.

### Priority 2: Fix recommendation->GUI field mapping for loss refs
Implement in `interactive_winding_designer.m` (around analysis MKF reference attach):
- support both field names:
  - `core_loss_W` and `core_losses_w`
  - `winding_loss_W` and `winding_losses_w`

Validation:
- recommendation list shows OM losses
- analysis comparison section reads the same recommendation loss values (no silent zeros).

### Priority 3: Pass explicit core-loss preferences through design_spec
Implement in `topology_wizard.m` + `interactive_winding_designer.m`:
- include optional `spec.core_loss` struct from wizard/recommendation payload:
  - method (`iGSE`/`i2GSE`)
  - coefficients if available (`k`, `alpha`, `beta`)
- in `apply_design_spec(...)`, apply these before GUI render.

Validation:
- on launch from wizard, GUI controls for core-loss method and Steinmetz fields reflect passed values.

### Priority 4: Investigate/contain `wind_by_layers` schema fallback
Implement targeted normalization in `generate_om_visualization.py` for fields sent to `wind_by_layers`:
- verify allowed enum values/field names before call
- continue graceful fallback but reduce fallback frequency

Validation:
- run same wizard case and check python output:
  - fallback warning frequency reduced or eliminated for normal cases.

## Suggested Next-Agent Execution Plan
1. Patch `generate_om_recommendations.py` core-loss model call + retries.
2. Patch `interactive_winding_designer.m` recommendation loss field aliases.
3. Patch design_spec core-loss pass-through (`topology_wizard.m` + `interactive_winding_designer.m`).
4. Re-run wizard end-to-end and capture logs:
   - recommendation generation
   - design-spec handoff
   - analysis core-loss message
5. Only then tune visualization schema normalization path.

## Useful Repro Commands (User Side / Octave)
```octave
cd('C:/Users/Will/proximity_loss/codex-cli-feature-work/PEEC_Script');
addpath(pwd); rehash;
topology_wizard
```

## Meshing Findings (Google AI Guidance Cross-Check)

The following findings came from cross-checking Google AI meshing guidance against current Octave implementation.

### Guidance 1: Hard vectorization for mesh generation/topology mapping

Status: Partially implemented, with important conflicts still present.

- Conflict: Filament coordinate generation still uses nested loops and dynamic growth.
  - `peec_build_geometry.m` uses `filaments = []` then appends with `filaments = [filaments; ...]` inside nested loops over conductors and `Nx,Ny`.
- Conflict: Conductor-to-filament connectivity (`C`) is built in scalar nested loops.
  - `peec_build_geometry.m` fills `C(k,idx)` one entry at a time.
- Conflict: Case-to-conductor build path also uses dynamic `end+1` growth.
  - `validation/execute_mas_case.m` appends to `conductors`, `winding_map`, and `wire_shapes` in loops.
- Alignment: Partial inductance matrix assembly is already vectorized.
  - `peec_build_geometry.m` uses pairwise `bsxfun`-based operations for L matrix assembly.
  - `mesh/adaptive_refine.m` includes a vectorized local L builder for indicator calculations.

### Guidance 2: Parallel meshing with Octave parallel package

Status: Not implemented.

- No `pkg load parallel`, `pararrayfun`, or `parcellfun` usage found in core meshing paths.
- No conductor-level parallel mesh generation path currently exists.

### Guidance 3: Measurement clarity (identify true bottleneck)

Status: Current timing labels can misclassify work.

- `validation/execute_mas_case.m` records `time_mesh_build_s` around `adaptive_refine(...)`.
- Inside `mesh/adaptive_refine.m`, each refinement iteration runs both:
  - `peec_build_geometry(...)`
  - `peec_solve_frequency(...)`
- Result: reported mesh time includes iterative solve work during refinement, not just geometry/topology generation.

### Practical interpretation

- If reports show "mesh is 90%+ runtime", part of that bucket is repeated solve activity inside adaptive refinement.
- Pure geometry/topology build is still a significant candidate for improvement, but current telemetry should be split before drawing hard conclusions.

### Recommended next meshing actions

1. Replace dynamic filament growth with preallocated arrays in `peec_build_geometry.m`.
2. Vectorize conductor cell center generation (`ndgrid`/`meshgrid`) per conductor.
3. Vectorize or sparse-construct connectivity mapping (`C`) instead of scalar per-entry writes.
4. Preallocate conductor assembly in `validation/execute_mas_case.m` to remove `end+1` growth.
5. Add timing split inside `adaptive_refine.m`:
   - geometry build time
   - refinement solve time
   - indicator/evaluation time
6. Add optional conductor-parallel meshing path using Octave `parallel` package for independent conductor discretization.

### Validation checkpoints for meshing-focused improvements

- Wall-clock reduction in pure geometry+connectivity phase with solves disabled.
- Reduced `adaptive_refine` runtime after timing split confirms where gains land.
- Numerical invariance checks:
  - same `geom.Nf`, `geom.C` structure, and L symmetry
  - no regression in benchmark loss/inductance outputs beyond configured tolerances

## Notes
- No destructive git operations were performed.
- This handoff includes both completed tuning-policy work and the currently active wizard/schema debug stream.
