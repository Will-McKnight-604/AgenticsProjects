function report = sweep_solver_thresholds(case_dir, results_root, grid, bench_overrides)
%SWEEP_SOLVER_THRESHOLDS Sweep key fast/standard threshold knobs.
%
% Example:
%   report = sweep_solver_thresholds();
%   report = sweep_solver_thresholds([], [], [], struct('max_cases', 4, 'warmup_runs', 0));

    ensure_local_paths();
    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(case_dir)
        case_dir = fullfile(here, 'mas_cases_real');
    end
    if nargin < 2 || isempty(results_root)
        results_root = fullfile(here, 'results_threshold_sweep');
    end
    if ~exist(results_root, 'dir')
        mkdir(results_root);
    end
    if nargin < 3 || ~isstruct(grid)
        grid = default_grid();
    end
    if nargin < 4 || ~isstruct(bench_overrides)
        bench_overrides = struct();
    end

    cfgs = expand_grid(grid);
    rows = repmat(struct(), numel(cfgs), 1);
    crit = optimization_pass_criteria();

    sample_opts = tuning_benchmark_preset();
    sample_opts = merge_structs(sample_opts, bench_overrides);
    case_count = count_cases(case_dir, sample_opts);
    modes_count = numel(sample_opts.modes);
    runs_per_mode = 1 + max(0, round(get_struct_numeric(sample_opts, 'warmup_runs', 0)));
    total_exec = numel(cfgs) * case_count * modes_count * runs_per_mode;

    fprintf('[SWEEP] Running %d threshold configurations (cases=%d, modes=%d, warmup=%d, total executes~%d)\n', ...
        numel(cfgs), case_count, modes_count, max(0, round(get_struct_numeric(sample_opts, 'warmup_runs', 0))), total_exec);

    for i = 1:numel(cfgs)
        cfg = cfgs(i);
        out_dir = fullfile(results_root, sprintf('cfg_%02d', i));
        if ~exist(out_dir, 'dir')
            mkdir(out_dir);
        end

        opts = tuning_benchmark_preset();
        opts = merge_structs(opts, bench_overrides);
        if ~isfield(bench_overrides, 'verbose')
            opts.verbose = false;
        end
        opts.resume = false;
        opts.mode_overrides = build_mode_overrides(cfg);
        t_cfg = tic;
        r = run_accuracy_benchmarks(case_dir, out_dir, opts);

        rows(i) = summarize_cfg(cfg, r, crit);
        fprintf('[SWEEP] cfg %02d/%02d fast_rt=%.3fs std_rt=%.3fs pass=%d elapsed=%.1fs\n', ...
            i, numel(cfgs), rows(i).median_runtime_fast_s, rows(i).median_runtime_standard_s, ...
            double(rows(i).pass), toc(t_cfg));
    end

    report = struct();
    report.generated_at = datestr(now, 30);
    report.case_dir = case_dir;
    report.results_root = results_root;
    report.criteria = crit;
    report.config_rows = rows;
    report.best = select_best(rows);

    out_json = fullfile(results_root, 'threshold_sweep_latest.json');
    write_json(report, out_json);
    write_csv(rows, fullfile(results_root, 'threshold_sweep_latest.csv'));
    fprintf('[SWEEP] Wrote: %s\n', out_json);
end

function grid = default_grid()
    grid = struct();
    grid.fast_direct_guard_nf_max = [500, 700, 900];
    grid.standard_direct_guard_nf_max = [1000, 1200, 1500];
    grid.iter_min_size_for_use = [900, 1200];
    grid.precond_drop_tol = [1e-2, 5e-3];
end

function cfgs = expand_grid(grid)
    a = grid.fast_direct_guard_nf_max(:);
    b = grid.standard_direct_guard_nf_max(:);
    c = grid.iter_min_size_for_use(:);
    d = grid.precond_drop_tol(:);

    idx = 0;
    cfgs = repmat(struct(), numel(a) * numel(b) * numel(c) * numel(d), 1);
    for i = 1:numel(a)
        for j = 1:numel(b)
            for k = 1:numel(c)
                for m = 1:numel(d)
                    idx = idx + 1;
                    cfgs(idx).fast_direct_guard_nf_max = a(i);
                    cfgs(idx).standard_direct_guard_nf_max = b(j);
                    cfgs(idx).iter_min_size_for_use = c(k);
                    cfgs(idx).precond_drop_tol = d(m);
                end
            end
        end
    end
end

function ov = build_mode_overrides(cfg)
    ov = struct();
    ov.fast = struct( ...
        'fast_direct_guard_nf_max', cfg.fast_direct_guard_nf_max, ...
        'iter_min_size_for_use', cfg.iter_min_size_for_use, ...
        'precond_drop_tol', cfg.precond_drop_tol, ...
        'linear_solver', 'auto', ...
        'iter_backend', 'auto', ...
        'enable_external_krylov', false);
    ov.standard = struct( ...
        'standard_direct_guard_nf_max', cfg.standard_direct_guard_nf_max, ...
        'iter_min_size_for_use', cfg.iter_min_size_for_use, ...
        'precond_drop_tol', cfg.precond_drop_tol, ...
        'linear_solver', 'auto', ...
        'iter_backend', 'auto', ...
        'enable_external_krylov', false);
end

function row = summarize_cfg(cfg, report, crit)
    s = get_struct_field(report, 'summary', struct());
    entries = get_struct_field(report, 'entries', struct([]));
    max_fast_loss = compute_max_fast_loss_pct(entries);

    row = struct();
    row.fast_direct_guard_nf_max = cfg.fast_direct_guard_nf_max;
    row.standard_direct_guard_nf_max = cfg.standard_direct_guard_nf_max;
    row.iter_min_size_for_use = cfg.iter_min_size_for_use;
    row.precond_drop_tol = cfg.precond_drop_tol;
    row.median_runtime_fast_s = get_struct_numeric(s, 'median_runtime_fast_s', NaN);
    row.median_runtime_standard_s = get_struct_numeric(s, 'median_runtime_standard_s', NaN);
    row.median_loss_error_fast_pct = get_struct_numeric(s, 'median_loss_error_fast_pct', NaN);
    row.median_loss_error_standard_pct = get_struct_numeric(s, 'median_loss_error_standard_pct', NaN);
    row.fast_solver_warning_fraction = get_struct_numeric(s, 'fast_solver_warning_fraction', NaN);
    row.fast_iter_quality_reject_fraction = get_struct_numeric(s, 'fast_iter_quality_reject_fraction', NaN);
    row.max_fast_loss_err_pct = max_fast_loss;

    pass_std_acc = isfinite(row.median_loss_error_standard_pct) && ...
        (row.median_loss_error_standard_pct <= crit.tuned_standard_loss_error_median_pct_max);
    pass_fast_loss = isfinite(row.max_fast_loss_err_pct) && ...
        (row.max_fast_loss_err_pct <= crit.max_fast_loss_err_pct_max);
    pass_warn = isfinite(row.fast_solver_warning_fraction) && ...
        (row.fast_solver_warning_fraction <= crit.warning_fraction_max);
    pass_quality = isfinite(row.fast_iter_quality_reject_fraction) && ...
        (row.fast_iter_quality_reject_fraction <= 0);
    row.pass = pass_std_acc && pass_fast_loss && pass_warn && pass_quality;

    penalty = 0;
    if ~pass_std_acc, penalty = penalty + 1000; end
    if ~pass_fast_loss, penalty = penalty + 1000; end
    if ~pass_warn, penalty = penalty + 1000; end
    if ~pass_quality, penalty = penalty + 1000; end
    row.score = row.median_runtime_fast_s + penalty;
end

function best = select_best(rows)
    best = struct();
    if isempty(rows)
        return;
    end
    pass_idx = find(arrayfun(@(r) get_struct_bool(r, 'pass', false), rows));
    if ~isempty(pass_idx)
        [~, k] = min(arrayfun(@(r) r.score, rows(pass_idx)));
        best = rows(pass_idx(k));
    else
        [~, k] = min(arrayfun(@(r) r.score, rows));
        best = rows(k);
    end
end

function max_err = compute_max_fast_loss_pct(entries)
    max_err = NaN;
    if isempty(entries)
        return;
    end
    vals = NaN(1, numel(entries));
    for i = 1:numel(entries)
        ef = get_struct_field(entries(i), 'error_fast', struct());
        v = get_struct_numeric(ef, 'loss_rel', NaN);
        if isfinite(v)
            vals(i) = 100 * v;
        end
    end
    x = vals(isfinite(vals));
    if ~isempty(x)
        max_err = max(x);
    end
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
        error('sweep_solver_thresholds: cannot write %s', out_file);
    end
    fwrite(fid, jsonencode(payload));
    fclose(fid);
end

function write_csv(rows, out_file)
    fid = fopen(out_file, 'w');
    if fid == -1
        error('sweep_solver_thresholds: cannot write %s', out_file);
    end
    hdr = ['fast_direct_guard_nf_max,standard_direct_guard_nf_max,iter_min_size_for_use,precond_drop_tol,' ...
           'median_runtime_fast_s,median_runtime_standard_s,median_loss_error_fast_pct,' ...
           'median_loss_error_standard_pct,fast_solver_warning_fraction,fast_iter_quality_reject_fraction,' ...
           'max_fast_loss_err_pct,pass,score'];
    fprintf(fid, '%s\n', hdr);
    for i = 1:numel(rows)
        r = rows(i);
        fprintf(fid, '%g,%g,%g,%.6g,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%.6f\n', ...
            r.fast_direct_guard_nf_max, r.standard_direct_guard_nf_max, r.iter_min_size_for_use, ...
            r.precond_drop_tol, r.median_runtime_fast_s, r.median_runtime_standard_s, ...
            r.median_loss_error_fast_pct, r.median_loss_error_standard_pct, ...
            r.fast_solver_warning_fraction, r.fast_iter_quality_reject_fraction, ...
            r.max_fast_loss_err_pct, double(r.pass), r.score);
    end
    fclose(fid);
end

function out = get_struct_field(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        out = s.(field_name);
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

function n = count_cases(case_dir, opts)
    n = 0;
    if ~exist(case_dir, 'dir')
        return;
    end
    files = dir(fullfile(case_dir, '*.json'));
    names = sort({files.name});
    if isempty(names)
        return;
    end
    if isfield(opts, 'case_indices') && isnumeric(opts.case_indices) && ~isempty(opts.case_indices)
        idx = unique(max(1, min(numel(names), round(opts.case_indices(:)'))));
        names = names(idx);
    end
    if isfield(opts, 'case_ids') && iscell(opts.case_ids) && ~isempty(opts.case_ids)
        wanted = cell(1, numel(opts.case_ids));
        for wi = 1:numel(opts.case_ids)
            if ischar(opts.case_ids{wi})
                wanted{wi} = lower(strip_json_suffix_local(strtrim(opts.case_ids{wi})));
            else
                wanted{wi} = '';
            end
        end
        keep = false(1, numel(names));
        for i = 1:numel(names)
            cid = lower(strip_json_suffix_local(names{i}));
            keep(i) = any(strcmp(cid, wanted));
        end
        names = names(keep);
    end
    if isfield(opts, 'max_cases') && isnumeric(opts.max_cases) && isfinite(opts.max_cases) && opts.max_cases > 0
        names = names(1:min(numel(names), floor(opts.max_cases)));
    end
    n = numel(names);
end

function s = strip_json_suffix_local(name_in)
    s = char(name_in);
    if numel(s) > 5 && strcmpi(s(end-4:end), '.json')
        s = s(1:end-5);
    end
end
