# Tuning Notes (Fast/Standard)

This note documents the practical tuning rollout for the 2D PEEC workflow.

## What Was Added
- Deterministic benchmark preset: `validation/tuning_benchmark_preset.m`
- Deterministic real-pack runner: `validation/run_real_tuning_benchmark.m`
- Baseline vs tuned repeated A/B harness: `validation/run_real_ab_benchmark.m`
- Case-level diagnostics extractor: `validation/extract_benchmark_diagnostics.m`
- Targeted regression suite: `validation/run_tuning_regression_suite.m`
- Optimization-day runner: `validation/run_optimization_day_pipeline.m`
- Pass-criteria object: `validation/optimization_pass_criteria.m`
- Baseline freeze helper: `validation/freeze_baseline_snapshot.m`
- FFT-specific case pack generator: `validation/generate_fft_eligible_cases.m`
- FFT routing/accuracy/speed benchmark: `validation/run_fft_backend_benchmark.m`
- Threshold sweep utility: `validation/sweep_solver_thresholds.m`
- Native backend build/check helpers:
  - `kernels/native/build_peec_native_backend.m`
  - `kernels/native/check_native_backend.m`

## Solver/Refinement Policy Changes
- `fast` and `standard` now default to `linear_solver='auto'`
- Fast direct guard: `fast_direct_guard_nf_max=700`
- Standard direct guard: `standard_direct_guard_nf_max=1200`
- Iterative acceptance thresholds:
  - fast: `iter_accept_relres_max_fast=1e-2`
  - standard: `iter_accept_relres_max_standard=5e-4`
- Iterative retry tolerance is capped by acceptance threshold
- ILU retry path increases drop tolerance before giving up
- Fast refine iterations reduced from 3 to 2
- Refinement stagnation stop:
  - `refine_stagnation_window=2`
  - `refine_stagnation_tol=0.05`
- Copper-loss jump guard reruns that refinement point with direct solve when jump exceeds `iter_quality_guard_loss_jump_pct`

## New Telemetry
- Iterative quality and warning fields:
  - `iter_quality_gate_passed`
  - `iter_rejected_reason`
  - `had_solver_warning`
  - `warning_kind`
- Refinement telemetry:
  - `mesh_refine_iterations`
- FFT telemetry:
  - `fft_eligible`
  - `fft_used`

## Recommended Workflow
1. Generate/refresh real pack if needed:
   - `generate_real_mas_cases();`
2. Generate FFT routing pack:
   - `generate_fft_eligible_cases();`
3. Build and smoke-check native backend:
   - `nb = check_native_backend(struct('auto_build', true));`
4. Run FFT benchmark:
   - `fr = run_fft_backend_benchmark();`
5. Sweep thresholds (optional before full A/B):
   - `sw = sweep_solver_thresholds();`
6. Run deterministic tuned benchmark:
   - `report = run_real_tuning_benchmark();`
7. Run repeated A/B against baseline direct profile:
   - `ab = run_real_ab_benchmark(3);`
8. Run targeted regressions:
   - `reg = run_tuning_regression_suite();`
9. One-command full pipeline:
   - `out = run_optimization_day_pipeline();`

## Acceptance Targets
- Fast median runtime <= 2.20 s on `mas_cases_real`
- Standard median runtime <= 2.50 s
- Standard-vs-high loss median error <= 0.01%
- No fast case > 30% loss error
- No iterative solve accepted above configured relres gate

## Deferred Methods (FMM/ACA)
- Native FMM/ACA are intentionally deferred in this cycle.
- Keep `interaction_backend='auto'` and do not force FMM globally.
- Revisit FMM/ACA only after both conditions are met:
  - External Krylov backend is stable and delivers pack-level win.
  - FFT path shows repeatable routing and speedup on eligible grids.

## Advanced Tuning (Multi-Fidelity)
- Added case-feature extraction:
  - `validation/extract_case_features.m`
- Added case-aware policy selector:
  - `validation/choose_solver_policy.m`
- Added constrained single-config evaluator with cache:
  - `validation/evaluate_tuning_config.m`
- Added Hyperband-style multi-fidelity tuner:
  - `validation/tune_solver_hyperband.m`
  - `validation/run_hyperband_tuning.m`

### Quick Hyperband Run
```octave
hb = run_hyperband_tuning(struct( ...
  'initial_candidates', 10, ...
  'stage_case_counts', [4 8], ...
  'stage_repeat_counts', [1 1], ...
  'max_cases', 8, ...
  'verbose', true));
```

### Full Hyperband Run
```octave
hb = run_hyperband_tuning(struct( ...
  'initial_candidates', 18, ...
  'stage_case_counts', [4 8 12], ...
  'stage_repeat_counts', [1 1 1], ...
  'verbose', true));
```

### A/B Check With Best Hyperband Config
```octave
ov = build_mode_overrides_from_tune_cfg(hb.best_config);
ab = run_real_ab_benchmark(1, [], struct( ...
  'max_cases', 8, ...
  'warmup_runs', 0, ...
  'refresh_cases', false, ...
  'tuned_mode_overrides', ov, ...
  'verbose', true));
```
