function out = run_optimization_day_pipeline(options)
%RUN_OPTIMIZATION_DAY_PIPELINE Single runner for optimization-day validation.
%
% This runner keeps command drift low by executing the same validation flow:
%   1) freeze baseline artifact snapshot
%   2) verify/build native backend
%   3) run FFT routing benchmark
%   4) run deterministic tuned benchmark
%   5) run deterministic 3x A/B
%   6) run targeted regression suite
%
% Example:
%   out = run_optimization_day_pipeline();

    ensure_local_paths();

    if nargin < 1 || ~isstruct(options)
        options = struct();
    end
    run_ab = get_opt_bool(options, 'run_ab', true);
    run_tuned = get_opt_bool(options, 'run_tuned', true);
    run_fft = get_opt_bool(options, 'run_fft', true);
    run_sweep = get_opt_bool(options, 'run_sweep', true);
    run_reg = get_opt_bool(options, 'run_regression', true);
    run_native = get_opt_bool(options, 'run_native_check', true);
    repeats = max(1, round(get_opt_num(options, 'ab_repeats', 3)));

    out = struct();
    out.generated_at = datestr(now, 30);
    out.criteria = optimization_pass_criteria();
    out.baseline_snapshot = freeze_baseline_snapshot();

    if run_native
        out.native = check_native_backend(struct('auto_build', true, 'verbose', true));
    else
        out.native = struct('skipped', true);
    end

    if run_fft
        out.fft_cases = generate_fft_eligible_cases();
        out.fft = run_fft_backend_benchmark();
    else
        out.fft_cases = {};
        out.fft = struct('skipped', true);
    end

    if run_tuned
        out.tuned = run_real_tuning_benchmark();
    else
        out.tuned = struct('skipped', true);
    end

    if run_sweep
        out.sweep = sweep_solver_thresholds();
    else
        out.sweep = struct('skipped', true);
    end

    if run_ab
        out.ab = run_real_ab_benchmark(repeats);
    else
        out.ab = struct('skipped', true);
    end

    if run_reg
        out.regression = run_tuning_regression_suite();
    else
        out.regression = struct('skipped', true);
    end

    out.acceptance = evaluate_acceptance(out);

    here = fileparts(mfilename('fullpath'));
    out_file = fullfile(here, 'results_real_ab', 'optimization_day_pipeline_latest.json');
    write_json(out, out_file);
    fprintf('[PIPE] Wrote: %s\n', out_file);
    fprintf('[PIPE] Acceptance pass: %d\n', double(get_struct_bool(out.acceptance, 'pass', false)));
end

function a = evaluate_acceptance(out)
    c = out.criteria;
    a = struct();
    a.pass = true;
    a.gates = struct();

    if isstruct(out.ab) && isfield(out.ab, 'summary')
        sumry = out.ab.summary;
        a.gates.fast_speedup_vs_baseline = get_struct_numeric(sumry, 'fast_speedup_vs_baseline', NaN);
        a.gates.standard_speedup_vs_baseline = get_struct_numeric(sumry, 'standard_speedup_vs_baseline', NaN);
        a.gates.tuned_standard_loss_error_median_pct = get_struct_numeric(sumry, 'tuned_standard_loss_error_median_pct', NaN);
    else
        a.gates.fast_speedup_vs_baseline = NaN;
        a.gates.standard_speedup_vs_baseline = NaN;
        a.gates.tuned_standard_loss_error_median_pct = NaN;
    end

    diag_sum = struct();
    if isstruct(out.ab) && isfield(out.ab, 'case_diagnostics') && isstruct(out.ab.case_diagnostics) && ...
            isfield(out.ab.case_diagnostics, 'summary')
        diag_sum = out.ab.case_diagnostics.summary;
    end
    a.gates.max_fast_loss_err_pct = get_struct_numeric(diag_sum, 'max_fast_loss_err_pct', NaN);
    a.gates.warning_fraction = get_struct_numeric(diag_sum, 'warning_fraction', NaN);
    a.gates.quality_reject_fraction = get_struct_numeric(diag_sum, 'quality_reject_fraction', NaN);

    fft_sum = struct();
    if isstruct(out.fft) && isfield(out.fft, 'summary')
        fft_sum = out.fft.summary;
    end
    a.gates.uniform_fft_used = get_struct_bool(fft_sum, 'uniform_fft_used', false);
    a.gates.uniform_interaction_rel_error = get_struct_numeric(fft_sum, 'uniform_interaction_rel_error', NaN);
    a.gates.uniform_fft_speedup_vs_dense = get_struct_numeric(fft_sum, 'uniform_fft_speedup_vs_dense', NaN);

    pass_vec = [];
    pass_vec(end+1) = isfinite(a.gates.fast_speedup_vs_baseline) && ...
        (a.gates.fast_speedup_vs_baseline >= c.fast_speedup_vs_baseline_min); %#ok<AGROW>
    pass_vec(end+1) = isfinite(a.gates.standard_speedup_vs_baseline) && ...
        (a.gates.standard_speedup_vs_baseline >= c.standard_speedup_vs_baseline_min); %#ok<AGROW>
    pass_vec(end+1) = isfinite(a.gates.tuned_standard_loss_error_median_pct) && ...
        (a.gates.tuned_standard_loss_error_median_pct <= c.tuned_standard_loss_error_median_pct_max); %#ok<AGROW>
    pass_vec(end+1) = isfinite(a.gates.max_fast_loss_err_pct) && ...
        (a.gates.max_fast_loss_err_pct <= c.max_fast_loss_err_pct_max); %#ok<AGROW>
    pass_vec(end+1) = isfinite(a.gates.warning_fraction) && ...
        (a.gates.warning_fraction <= c.warning_fraction_max); %#ok<AGROW>
    if c.require_no_iter_quality_reject
        pass_vec(end+1) = isfinite(a.gates.quality_reject_fraction) && ...
            (a.gates.quality_reject_fraction <= 0); %#ok<AGROW>
    end
    if c.require_fft_routed_on_uniform_case
        pass_vec(end+1) = a.gates.uniform_fft_used; %#ok<AGROW>
    end
    pass_vec(end+1) = isfinite(a.gates.uniform_interaction_rel_error) && ...
        (a.gates.uniform_interaction_rel_error <= c.fft_interaction_rel_error_max); %#ok<AGROW>
    pass_vec(end+1) = isfinite(a.gates.uniform_fft_speedup_vs_dense) && ...
        (a.gates.uniform_fft_speedup_vs_dense >= c.fft_speedup_min); %#ok<AGROW>

    a.pass = all(pass_vec);
end

function ensure_local_paths()
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(root);
    addpath(here);
    addpath(fullfile(root, 'mesh'));
    addpath(fullfile(root, 'physics'));
    addpath(fullfile(root, 'corrections'));
    addpath(fullfile(root, 'kernels'));
    addpath(fullfile(root, 'kernels', 'native'));
    addpath(fullfile(root, 'litz'));
end

function write_json(payload, out_file)
    fid = fopen(out_file, 'w');
    if fid == -1
        error('run_optimization_day_pipeline: cannot write %s', out_file);
    end
    fwrite(fid, jsonencode(payload));
    fclose(fid);
end

function out = get_opt_bool(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if islogical(v) && isscalar(v)
            out = v;
        elseif isnumeric(v) && isscalar(v)
            out = (v ~= 0);
        end
    end
end

function out = get_opt_num(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if isnumeric(v) && isscalar(v) && isfinite(v)
            out = double(v);
        end
    end
end

function out = get_struct_numeric(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if isnumeric(v) && isscalar(v) && isfinite(v)
            out = double(v);
        elseif islogical(v) && isscalar(v)
            out = double(v);
        end
    end
end

function out = get_struct_bool(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if islogical(v) && isscalar(v)
            out = v;
        elseif isnumeric(v) && isscalar(v)
            out = (v ~= 0);
        end
    end
end
