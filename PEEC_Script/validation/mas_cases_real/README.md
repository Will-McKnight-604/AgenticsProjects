# mas_cases_real

Curated real-use benchmark pack for the 2D PEEC validation flow.

This pack complements `validation/mas_cases`:
- `mas_cases`: synthetic sweep-friendly cases
- `mas_cases_real`: practical operating-point stress cases

## Included scenarios

1. `real_case_01_tsf_nominal` - two-switch-forward nominal
2. `real_case_02_tsf_lowline_full` - two-switch-forward low-line/full-load
3. `real_case_03_tsf_highline_light` - two-switch-forward high-line/light-load
4. `real_case_04_llc_midband` - half-bridge LLC near resonance
5. `real_case_05_llc_highfreq_litz` - LLC high-frequency litz stress
6. `real_case_06_flyback_ccm_gap` - flyback CCM with large gap
7. `real_case_07_flyback_qr` - flyback quasi-resonant tendency
8. `real_case_08_interleaved_forward` - interleaved forward high current
9. `real_case_09_pfc_coupled` - interleaved PFC coupled winding
10. `real_case_10_planar_rect_500k` - planar rectangular conductors at 500 kHz
11. `real_case_11_aux_bias_highfreq` - low-power high-frequency auxiliary bias
12. `real_case_12_dab_highcurrent` - dual-active-bridge high-current symmetry

## Generate and run

```octave
cd('C:/Users/Will/proximity_loss/Claude/PEEC_Script');
addpath(pwd);
addpath(fullfile(pwd, 'validation'));
addpath(fullfile(pwd, 'mesh'));
addpath(fullfile(pwd, 'physics'));
addpath(fullfile(pwd, 'corrections'));
addpath(fullfile(pwd, 'kernels'));
addpath(fullfile(pwd, 'litz'));
rehash;

generate_real_mas_cases();

opts = struct( ...
  'modes', {{'fast','standard','high'}}, ...
  'reference_mode', 'high', ...
  'resume', true, ...
  'verbose', true);

report = run_real_accuracy_benchmarks([], opts);
```

## Output location

- Case files: `validation/mas_cases_real/*.json`
- Results: `validation/results_real/accuracy_benchmark_latest.json`
- Runner alias: `validation/results_real/accuracy_benchmark_real_latest.json`
