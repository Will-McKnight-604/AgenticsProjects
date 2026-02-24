# AI Agent Handoff (2026-02-22)

## Scope + Environment
- Repository/worktree: `C:\Users\Will\proximity_loss\codex-cli-feature-work\PEEC_Script`
- Branch: `optimization`
- Continued from: `AGENT_HANDOFF_2026-02-21.md`

---

## What Was Completed This Session

### Priority 1: Vectorized L-matrix in peec_build_geometry.m (prior session)
The O(N²) scalar nested-loop inductance matrix computation was replaced with vectorized
`bsxfun` operations. This is the dominant bottleneck in the adaptive mesh refinement loop,
which calls `peec_build_geometry` up to 5 times per run.

Files changed:
- `peec_build_geometry.m` — L-matrix now uses vectorized distance computation + GMD/GMR corrections

### Priority 2: Wire solve_options into peec_solve_frequency.m
Root-cause bug: both `adaptive_refine.m` and `interactive_winding_designer.m` called
`peec_solve_frequency(geom, conductors, f, sigma, mu0, solve_options)` with 6 arguments,
but the function signature only declared 5. This caused a hard crash:

```
error: peec_solve_frequency: function called with too many inputs
```

All solver infrastructure (BiCGSTAB tuning, interaction backend, quality presets) that the
prior agent had built was completely dead code because the 6th argument was never received.

**Fix applied** — four edits to `peec_solve_frequency.m`:
1. Function signature changed to accept `solve_options` as 6th optional parameter
2. `nargin < 6` guard added with fallback to empty struct
3. Solve-options parsing block added (11 parameters extracted)
4. Solver selection logic implemented with fallback from iterative → direct
5. Power loss vectorized: `P_fil = 0.5 * R_diag .* abs(I_fil).^2` replacing scalar loop
6. Six `psf_`-prefixed local helper functions added (iterative solve, preconditioner, type-safe option getters)

Files changed:
- `peec_solve_frequency.m` (lines 624–869)

### Priority 3: Disable automatic BiCGSTAB
A 214-conductor run had to be manually stopped due to timeout. Investigation showed:
- 214 conductors at Nx=Ny=8 → N_sys = 13,910 DOF
- BiCGSTAB was auto-triggering (threshold was 2200)
- Dense complex saddle-point systems are a poor fit for BiCGSTAB without sparse structure
- LAPACK direct solve (`A\b`) is highly optimized for these sizes

**Fix applied** — raised all iterative-trigger thresholds from 2200–2600 to `1e10`,
effectively disabling auto-BiCGSTAB. Iterative solvers remain available via explicit
`solve_options.linear_solver = 'bicgstab'` or `'gmres'`.

Files changed:
- `validation/solver_option_profile.m` — `iter_min_size_for_use`, `fast_direct_guard_nf_max`,
  `standard_direct_guard_nf_max` all set to `1e10`

### Priority 4: Remove 18-point operating-point prescreen
The previous workflow generated an 18-point grid (3 line scales × 3 load scales × CCM+DCM),
ran OpenMagnetics to score them all, then selected the worst 6 for PEEC refinement.
This entire prescreen layer has been removed. The new operating points are:

| OP | Vin | Iload | Mode |
|----|-----|-------|------|
| 1  | Vin_min (0.90×) | Imax | CCM |
| 2  | Vin_min (0.90×) | Imax | DCM |
| 3  | Vin_max (1.10×) | Imax | CCM |
| 4  | Vin_max (1.10×) | Imax | DCM |

All 4 points run through PEEC directly — no prescreen ranking step.

**Changes made:**

`om_excitation_config.json`:
- `line_scales`: `[0.9, 1, 1.1]` → `[0.9, 1.1]`
- `load_scales`: `[0.5, 0.75, 1.0]` → `[1.0]`
- `conduction_mode`: unchanged (`ccm+dcm`)

`interactive_winding_designer.m`:
- Removed `use_prescreen` execution block (~30 lines)
- Removed `run_om_prescreen_for_profile()` function (~175 lines)
- Removed `peec_refine_top_n`, `prescreen_waveform_samples`, `prescreen_temperature_c`
  from defaults, `resolve_excitation_config()`, and `apply_excitation_quality_preset()`
- Removed prescreen metadata fields from `analysis_meta` initialization
- Updated default `line_scales = [0.90, 1.10]`, `load_scales = [1.00]`

---

## Current State

The PEEC analysis pipeline is now:

```
topology_wizard → interactive_winding_designer
    → generate_om_excitation.py  (4 operating points)
    → run_peec_with_excitation_profile()  (PEEC all 4 directly)
    → display results
```

No prescreen Python subprocess is invoked. The pipeline is simpler and more deterministic.

**Expected runtime for 214-conductor case (post-fixes):**
- Geometry build (vectorized L): substantially faster than scalar loop
- Solver: direct LAPACK — deterministic, no timeout risk
- 4 operating points × adaptive refinement ≈ minutes, not hours
- Actual timing needs a live run to benchmark

---

## What Remains / Improvements for Next Session

### High Priority

#### A) Benchmark the 214-conductor case
Run `topology_wizard` end-to-end with the 214-conductor design and measure:
- Total wall-clock time
- Per-operating-point solve time
- Whether adaptive mesh converges (check `mesh_meta.converged` and `stop_reason`)
- Whether results are physically sensible (check P_total vs. expected copper loss)

This will confirm whether Priority 1–3 fixes have the expected impact.

#### B) L-matrix reuse across adaptive refinement iterations (Priority 3 from prior plan)
`adaptive_refine.m` calls `peec_build_geometry` up to 5 times with increasing Nx/Ny.
Each call recomputes the full L-matrix from scratch. Between consecutive refinement levels
(e.g., Nx=6→7), ~60–70% of the filament pairs are new but many geometry relationships
overlap. A warm-start approach could:
- Cache the coarse-mesh L and index map
- Only compute new cross-terms when Nx/Ny increases
- Estimated saving: 30–50% of L-matrix build time per refinement step

This is the highest-impact remaining optimization.

#### C) Vectorize R_diag loop in peec_solve_frequency.m
The resistance matrix is still computed with a scalar loop:
```matlab
for i = 1:Nf
    A_fil = filaments(i,3) * filaments(i,4);
    R_diag(i) = 1 / (sigma * A_fil);
end
```
Trivially vectorizable:
```matlab
R_diag = 1 ./ (sigma * filaments(:,3) .* filaments(:,4));
```
Low risk, minor gain, but worth doing for consistency with the rest of the codebase.

### Medium Priority

#### D) Issues from AGENT_HANDOFF_2026-02-21 (not yet addressed)
The schema/wizard issues identified previously are still open:

1. **Core-loss schema failure** (`generate_om_recommendations.py`): iGSE model enum string
   is invalid for current PyOpenMagnetics schema. Fix: use default models `{}` and retry.
2. **Recommendation → GUI field mapping**: `core_loss_W` vs `core_losses_w` mismatch causes
   silent zero in analysis comparison display (`interactive_winding_designer.m`).
3. **design_spec core-loss pass-through**: `topology_wizard.m` doesn't forward core-loss
   method/Steinmetz fields into `interactive_winding_designer.m`.
4. **`wind_by_layers` schema fallback**: non-critical but generates noise in logs.

#### E) FFT/FMM interaction backend wiring
`build_peec_interaction_backend.m` and `kernels/` subdirectory implement FFT convolution
and FMM backends for O(N log N) matvec, but these are not yet wired into
`peec_solve_frequency.m`. The matrix-vector product in the solver currently uses the
full dense L matrix. Connecting the FFT backend would benefit large uniform-grid cases.

### Low Priority

#### F) Cache invalidation for excitation profile
The `use_cache = true` default in `om_excitation_config.json` means changing `line_scales`
or `load_scales` may serve stale cached waveforms. Consider adding the operating-point
configuration to the cache key hash in `generate_om_excitation.py`.

#### G) Prescreen orphan files
The following files are now unused but harmless:
- `generate_om_prescreen_losses.py`
- `om_prescreen_config.json`
- `om_excitation_profile_for_prescreen.json`
- `om_prescreen_losses.json`
- `om_viz_config_prescreen.json`

Can be deleted when convenient to reduce clutter.

---

## Files Modified This Session

| File | Change |
|------|--------|
| `peec_build_geometry.m` | Vectorized L-matrix (prior session) |
| `peec_solve_frequency.m` | Added solve_options param + iterative solver + vectorized P_fil |
| `validation/solver_option_profile.m` | BiCGSTAB auto-trigger thresholds → 1e10 |
| `om_excitation_config.json` | line_scales=[0.9,1.1], load_scales=[1.0] |
| `interactive_winding_designer.m` | Removed prescreen block + function + stale defaults |

---

## Repro / Test Command

```octave
cd('C:/Users/Will/proximity_loss/codex-cli-feature-work/PEEC_Script');
addpath(pwd); rehash;
topology_wizard
```

Monitor for:
- No crash at `peec_solve_frequency` (was: "too many inputs")
- `[ANALYSIS]` log lines showing 4 operating points processed (not 18 or 6)
- Mesh convergence reported in console
- Sensible P_total values (order of milliwatts to watts depending on design)

---

## Notes
- No destructive git operations were performed.
- `optimization` branch is ahead of `main` — push only when user requests.
- The `peec_refine_top_n` field has been fully removed; any caller setting it will be silently ignored (struct copy loop in `resolve_excitation_config` will not copy unknown fields into ex_cfg).
