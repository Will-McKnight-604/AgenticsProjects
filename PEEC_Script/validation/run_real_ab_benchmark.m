function report = run_real_ab_benchmark(repeats, results_root, bench_overrides)
%RUN_REAL_AB_BENCHMARK Repeated deterministic A/B between baseline and tuned defaults.
%
% Baseline profile forces direct dense solves for fast/standard to provide
% a stable comparison point. Tuned profile uses current defaults.

    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(repeats)
        repeats = 3;
    end
    repeats = max(1, round(repeats));

    if nargin < 2 || isempty(results_root)
        results_root = fullfile(here, 'results_real_ab');
    end
    if nargin < 3 || ~isstruct(bench_overrides)
        bench_overrides = struct();
    end
    if ~exist(results_root, 'dir')
        mkdir(results_root);
    end

    baseline_runs = repmat(struct(), repeats, 1);
    tuned_runs = repmat(struct(), repeats, 1);

    for r = 1:repeats
        base_dir = fullfile(results_root, sprintf('baseline_r%02d', r));
        tuned_dir = fullfile(results_root, sprintf('tuned_r%02d', r));
        if ~exist(base_dir, 'dir'), mkdir(base_dir); end
        if ~exist(tuned_dir, 'dir'), mkdir(tuned_dir); end

        bopts = tuning_benchmark_preset();
        bopts = merge_structs(bopts, bench_overrides);
        bopts.resume = false;
        if ~isfield(bench_overrides, 'verbose')
            bopts.verbose = true;
        end
        bopts.mode_overrides = build_baseline_overrides();
        if isfield(bench_overrides, 'baseline_mode_overrides') && isstruct(bench_overrides.baseline_mode_overrides)
            bopts.mode_overrides = bench_overrides.baseline_mode_overrides;
        end
        fprintf('[AB] Baseline run %d/%d\n', r, repeats);
        baseline_runs(r).report = run_real_accuracy_benchmarks(base_dir, bopts);

        topts = tuning_benchmark_preset();
        topts = merge_structs(topts, bench_overrides);
        topts.resume = false;
        if ~isfield(bench_overrides, 'verbose')
            topts.verbose = true;
        end
        if isfield(bench_overrides, 'tuned_mode_overrides') && isstruct(bench_overrides.tuned_mode_overrides)
            topts.mode_overrides = bench_overrides.tuned_mode_overrides;
        end
        fprintf('[AB] Tuned run %d/%d\n', r, repeats);
        tuned_runs(r).report = run_real_accuracy_benchmarks(tuned_dir, topts);
    end

    report = struct();
    report.generated_at = datestr(now, 30);
    report.repeats = repeats;
    report.results_root = results_root;
    report.baseline_runs = baseline_runs;
    report.tuned_runs = tuned_runs;
    report.summary = summarize_runs(baseline_runs, tuned_runs);

    baseline_last = fullfile(results_root, sprintf('baseline_r%02d', repeats), 'accuracy_benchmark_real_latest.json');
    tuned_last = fullfile(results_root, sprintf('tuned_r%02d', repeats), 'accuracy_benchmark_real_latest.json');
    csv_out = fullfile(results_root, 'ab_case_diagnostics.csv');
    report.case_diagnostics = extract_benchmark_diagnostics(baseline_last, tuned_last, csv_out);

    out_json = fullfile(results_root, 'ab_summary_latest.json');
    write_json(report, out_json);
    fprintf('[AB] Wrote summary: %s\n', out_json);
end

function ov = build_baseline_overrides()
    direct_cfg = struct( ...
        'linear_solver', 'direct', ...
        'matrix_mode', 'dense', ...
        'interaction_backend', 'dense', ...
        'enable_external_krylov', false, ...
        'enable_iterative_retry', false, ...
        'preconditioner', 'none');

    ov = struct();
    ov.fast = direct_cfg;
    ov.standard = direct_cfg;
end

function s = summarize_runs(base_runs, tuned_runs)
    s = struct();

    b_fast = extract_summary_series(base_runs, 'median_runtime_fast_s');
    t_fast = extract_summary_series(tuned_runs, 'median_runtime_fast_s');
    b_std = extract_summary_series(base_runs, 'median_runtime_standard_s');
    t_std = extract_summary_series(tuned_runs, 'median_runtime_standard_s');

    s.baseline_fast_runtime_median_of_runs_s = median_no_nan(b_fast);
    s.tuned_fast_runtime_median_of_runs_s = median_no_nan(t_fast);
    s.baseline_standard_runtime_median_of_runs_s = median_no_nan(b_std);
    s.tuned_standard_runtime_median_of_runs_s = median_no_nan(t_std);
    s.fast_speedup_vs_baseline = safe_ratio(s.baseline_fast_runtime_median_of_runs_s, s.tuned_fast_runtime_median_of_runs_s);
    s.standard_speedup_vs_baseline = safe_ratio(s.baseline_standard_runtime_median_of_runs_s, s.tuned_standard_runtime_median_of_runs_s);

    t_fast_err = extract_summary_series(tuned_runs, 'median_loss_error_fast_pct');
    t_std_err = extract_summary_series(tuned_runs, 'median_loss_error_standard_pct');
    s.tuned_fast_loss_error_median_pct = median_no_nan(t_fast_err);
    s.tuned_standard_loss_error_median_pct = median_no_nan(t_std_err);
end

function vals = extract_summary_series(run_struct, field_name)
    vals = NaN(1, numel(run_struct));
    for i = 1:numel(run_struct)
        rep = get_struct_field(run_struct(i), 'report', struct());
        sumry = get_struct_field(rep, 'summary', struct());
        vals(i) = get_struct_numeric(sumry, field_name, NaN);
    end
end

function write_json(payload, out_file)
    fid = fopen(out_file, 'w');
    if fid == -1
        error('run_real_ab_benchmark: cannot write %s', out_file);
    end
    fwrite(fid, jsonencode(payload));
    fclose(fid);
end

function m = median_no_nan(v)
    m = NaN;
    x = v(isfinite(v));
    if isempty(x)
        return;
    end
    m = median(x);
end

function r = safe_ratio(a, b)
    r = NaN;
    if ~isfinite(a) || ~isfinite(b) || b == 0
        return;
    end
    r = a / b;
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

function out = merge_structs(base, extra)
    out = base;
    if ~isstruct(extra)
        return;
    end
    f = fieldnames(extra);
    for i = 1:numel(f)
        out.(f{i}) = extra.(f{i});
    end
end

function out = get_struct_field(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        out = s.(field_name);
    end
end
