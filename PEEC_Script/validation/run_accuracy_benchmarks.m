function report = run_accuracy_benchmarks(case_dir, results_dir, options)
%RUN_ACCURACY_BENCHMARKS Run synthetic/internal benchmark sweep for phase 3.
%
% Default behavior (backward-compatible):
%   - runs all MAS cases in case_dir
%   - runs modes: high(reference), fast, standard
%   - writes latest + timestamped report JSON
%
% Optional options struct fields:
%   .modes            cellstr, e.g. {'fast','standard','high'}
%   .reference_mode   'high' (default) or one of .modes
%   .case_indices     numeric indices into sorted case file list
%   .case_ids         cellstr case ids (e.g. {'tsf_case_01'})
%   .max_cases        positive integer (default inf)
%   .resume           logical (default true)
%   .save_partial     logical (default true)
%   .verbose          logical (default true)
%   .mode_overrides   struct with per-mode option structs
%   .mode_order_policy 'fixed' (default) | 'random_per_case'
%   .clear_persistent_between_modes logical (default true)
%   .warmup_runs      integer >= 0 (default 0)
%   .record_timing_breakdown logical (default true)
%   .random_seed      integer seed for randomized mode ordering
%
% Example:
%   opts = struct('modes', {{'fast','standard'}}, ...
%                 'case_ids', {{'tsf_case_01','tsf_case_02'}}, ...
%                 'verbose', true);
%   report = run_accuracy_benchmarks([], [], opts);

    ensure_phase3_paths();

    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(case_dir)
        case_dir = fullfile(here, 'mas_cases');
    end
    if nargin < 2 || isempty(results_dir)
        results_dir = fullfile(here, 'results');
    end
    if nargin < 3 || ~isstruct(options)
        options = struct();
    end
    options = normalize_options(options);

    if ~exist(case_dir, 'dir')
        mkdir(case_dir);
    end
    if ~exist(results_dir, 'dir')
        mkdir(results_dir);
    end

    case_files = dir(fullfile(case_dir, '*.json'));
    if isempty(case_files)
        generate_default_mas_cases(case_dir);
        case_files = dir(fullfile(case_dir, '*.json'));
    end
    if isempty(case_files)
        error('run_accuracy_benchmarks: no MAS cases found in %s', case_dir);
    end

    case_names = sort({case_files.name});
    case_names = select_case_names(case_names, options);
    if isempty(case_names)
        error('run_accuracy_benchmarks: case selection is empty');
    end

    latest_file = fullfile(results_dir, 'accuracy_benchmark_latest.json');
    stamp_file = fullfile(results_dir, sprintf('accuracy_benchmark_%s.json', datestr(now, 'yyyymmdd_HHMMSS')));
    partial_file = fullfile(results_dir, 'accuracy_benchmark_partial.json');

    entries = init_entries(case_names);
    if options.resume && exist(partial_file, 'file') == 2
        try
            prev = load_json_file(partial_file);
            entries = merge_resume_entries(entries, prev);
        catch
        end
    end

    t_all = tic;
    total_cases = numel(entries);
    if options.verbose
        fprintf('[BENCH] Starting benchmark: %d cases | modes: %s | reference: %s | order: %s | clear_cache: %d | warmup: %d\n', ...
            total_cases, strjoin(options.modes, ', '), options.reference_mode, ...
            options.mode_order_policy, double(options.clear_persistent_between_modes), options.warmup_runs);
    end

    try
        for i = 1:total_cases
            if entries(i).completed
                if options.verbose
                    fprintf('[%d/%d] %s (resume: already complete)\n', i, total_cases, entries(i).case_id);
                end
                continue;
            end

            case_path = fullfile(case_dir, entries(i).case_file);
            if options.verbose
                fprintf('[%d/%d] %s\n', i, total_cases, entries(i).case_id);
            end

            mode_results = struct();
            mode_sequence = plan_mode_sequence(options.modes, options.mode_order_policy, options.random_seed, i);
            for mi = 1:numel(mode_sequence)
                mode_name = mode_sequence{mi};
                solve_opts = solver_option_profile(mode_name);
                solve_opts = apply_mode_overrides(solve_opts, mode_name, options);

                if options.clear_persistent_between_modes
                    clear_phase3_runtime_caches();
                end
                if options.warmup_runs > 0
                    for wi = 1:options.warmup_runs
                        execute_mas_case(case_path, solve_opts);
                    end
                end

                t_mode = tic;
                res_mode = execute_mas_case(case_path, solve_opts);
                mode_runtime = toc(t_mode);
                res_mode.wall_runtime_s = mode_runtime;
                res_mode.run_index = mi;
                res_mode.mode_order = mode_sequence;
                if options.record_timing_breakdown
                    res_mode.timing_breakdown = extract_timing_breakdown(res_mode);
                end
                mode_results.(mode_name) = res_mode;

                if options.verbose
                    fprintf('  - %s: %.2f s\n', upper(mode_name), mode_runtime);
                end
            end

            entries(i) = build_entry(entries(i), mode_results, options.reference_mode);

            if options.save_partial
                partial_report = build_report(entries, options, toc(t_all), 'partial');
                write_json(partial_report, partial_file);
                write_json(partial_report, latest_file);
            end
        end
    catch ME
        partial_report = build_report(entries, options, toc(t_all), 'partial');
        write_json(partial_report, partial_file);
        write_json(partial_report, latest_file);
        if options.verbose
            fprintf('[BENCH] Interrupted or failed; partial report saved to %s\n', partial_file);
        end
        rethrow(ME);
    end

    report = build_report(entries, options, toc(t_all), 'complete');
    write_json(report, latest_file);
    write_json(report, stamp_file);

    if exist(partial_file, 'file') == 2
        delete(partial_file);
    end

    if options.verbose
        fprintf('[BENCH] Complete: %d/%d cases | total %.1f s\n', ...
            report.completed_count, report.case_count, report.runtime_total_s);
        fprintf('[BENCH] Wrote: %s\n', latest_file);
        fprintf('[BENCH] Wrote: %s\n', stamp_file);
    end
end

function options = normalize_options(options)
    def = struct();
    def.modes = {'fast', 'standard', 'high'};
    def.reference_mode = 'high';
    def.case_indices = [];
    def.case_ids = {};
    def.max_cases = inf;
    def.resume = true;
    def.save_partial = true;
    def.verbose = true;
    def.mode_overrides = struct();
    def.mode_order_policy = 'fixed';
    def.clear_persistent_between_modes = true;
    def.warmup_runs = 0;
    def.record_timing_breakdown = true;
    def.random_seed = 17;

    f = fieldnames(def);
    for i = 1:numel(f)
        if ~isfield(options, f{i})
            options.(f{i}) = def.(f{i});
        end
    end

    options.modes = normalize_mode_list(options.modes);
    if isempty(options.modes)
        options.modes = def.modes;
    end

    if ~is_text_like(options.reference_mode)
        options.reference_mode = def.reference_mode;
    end
    options.reference_mode = lower(strtrim(char(options.reference_mode)));
    if ~any(strcmp(options.reference_mode, options.modes))
        options.reference_mode = options.modes{1};
    end

    if ~iscell(options.case_ids)
        if is_text_like(options.case_ids)
            options.case_ids = {char(options.case_ids)};
        else
            options.case_ids = {};
        end
    end

    if ~isnumeric(options.case_indices)
        options.case_indices = [];
    end
    if ~isnumeric(options.max_cases) || ~isfinite(options.max_cases) || options.max_cases <= 0
        options.max_cases = inf;
    else
        options.max_cases = floor(options.max_cases);
    end

    options.resume = to_logical(options.resume, true);
    options.save_partial = to_logical(options.save_partial, true);
    options.verbose = to_logical(options.verbose, true);
    if ~isstruct(options.mode_overrides)
        options.mode_overrides = struct();
    end
    options.mode_order_policy = normalize_mode_order_policy(options.mode_order_policy, def.mode_order_policy);
    options.clear_persistent_between_modes = to_logical(options.clear_persistent_between_modes, def.clear_persistent_between_modes);
    if ~isnumeric(options.warmup_runs) || ~isscalar(options.warmup_runs) || ~isfinite(options.warmup_runs)
        options.warmup_runs = def.warmup_runs;
    end
    options.warmup_runs = max(0, floor(double(options.warmup_runs)));
    options.record_timing_breakdown = to_logical(options.record_timing_breakdown, def.record_timing_breakdown);
    if ~isnumeric(options.random_seed) || ~isscalar(options.random_seed) || ~isfinite(options.random_seed)
        options.random_seed = def.random_seed;
    end
    options.random_seed = floor(double(options.random_seed));
end

function modes = normalize_mode_list(modes_in)
    valid = {'fast', 'standard', 'high', 'compatibility'};
    modes = {};
    if is_text_like(modes_in)
        modes_in = {char(modes_in)};
    end
    if ~iscell(modes_in)
        return;
    end
    for i = 1:numel(modes_in)
        if ~is_text_like(modes_in{i})
            continue;
        end
        m = lower(strtrim(char(modes_in{i})));
        if any(strcmp(m, valid)) && ~any(strcmp(m, modes))
            modes{end+1} = m; %#ok<AGROW>
        end
    end
end

function policy = normalize_mode_order_policy(policy_in, default_val)
    policy = default_val;
    if ~is_text_like(policy_in)
        return;
    end
    cand = lower(strtrim(char(policy_in)));
    if any(strcmp(cand, {'fixed', 'random_per_case'}))
        policy = cand;
    end
end

function selected = select_case_names(case_names, options)
    selected = case_names;

    if ~isempty(options.case_indices)
        idx = unique(max(1, min(numel(case_names), round(options.case_indices(:)'))));
        selected = case_names(idx);
    end

    if ~isempty(options.case_ids)
        wanted = cell(1, numel(options.case_ids));
        for i = 1:numel(options.case_ids)
            wanted{i} = lower(strip_json_suffix(char(options.case_ids{i})));
        end
        keep = false(1, numel(selected));
        for i = 1:numel(selected)
            cid = lower(strip_json_suffix(selected{i}));
            keep(i) = any(strcmp(cid, wanted));
        end
        selected = selected(keep);
    end

    if isfinite(options.max_cases)
        selected = selected(1:min(numel(selected), options.max_cases));
    end
end

function s = strip_json_suffix(name_in)
    s = char(name_in);
    if numel(s) > 5 && strcmpi(s(end-4:end), '.json')
        s = s(1:end-5);
    end
end

function entries = init_entries(case_names)
    entries = repmat(empty_entry_template(), 1, numel(case_names));
    for i = 1:numel(case_names)
        entries(i).case_file = case_names{i};
        entries(i).case_id = strip_json_suffix(case_names{i});
    end
end

function entry = empty_entry_template()
    entry = struct();
    entry.case_id = '';
    entry.case_file = '';
    entry.frequency_hz = NaN;
    entry.completed = false;
    entry.reference = struct();
    entry.fast = struct();
    entry.standard = struct();
    entry.high = struct();
    entry.error_fast = struct();
    entry.error_standard = struct();
    entry.error_high = struct();
    entry.runtime_ratio_std_vs_fast = NaN;
    entry.runtime_ratio_high_vs_standard = NaN;
    entry.timestamp = '';
end

function entries = merge_resume_entries(entries, prev_report)
    if ~isstruct(prev_report) || ~isfield(prev_report, 'entries') || ~isstruct(prev_report.entries)
        return;
    end
    prev_entries = prev_report.entries;
    for i = 1:numel(entries)
        idx = find_entry_idx(prev_entries, entries(i).case_id);
        if idx > 0
            cand = prev_entries(idx);
            if isfield(cand, 'completed') && to_logical(cand.completed, false)
                entries(i) = merge_entry_fields(entries(i), cand);
                entries(i).completed = true;
            end
        end
    end
end

function idx = find_entry_idx(entries, case_id)
    idx = 0;
    for i = 1:numel(entries)
        if isfield(entries(i), 'case_id')
            if strcmp(char(entries(i).case_id), char(case_id))
                idx = i;
                return;
            end
        end
    end
end

function dst = merge_entry_fields(dst, src)
    fs = fieldnames(dst);
    for i = 1:numel(fs)
        k = fs{i};
        if isfield(src, k)
            dst.(k) = src.(k);
        end
    end
end

function solve_opts = apply_mode_overrides(solve_opts, mode_name, options)
    if ~isfield(options, 'mode_overrides') || ~isstruct(options.mode_overrides)
        return;
    end
    if ~isfield(options.mode_overrides, mode_name)
        return;
    end
    ov = options.mode_overrides.(mode_name);
    if ~isstruct(ov)
        ov = struct();
    end

    f = fieldnames(ov);
    for i = 1:numel(f)
        solve_opts.(f{i}) = ov.(f{i});
    end

    if strcmp(mode_name, 'standard')
        lock_targets = to_logical(get_struct_numeric(solve_opts, 'lock_standard_targets', 1), true);
        if lock_targets
            solve_opts.target_rel_error_loss = 0.025;
            solve_opts.target_rel_error_llk = 0.025;
        end
    end
end

function mode_sequence = plan_mode_sequence(modes, mode_order_policy, random_seed, case_idx)
    mode_sequence = modes;
    if ~strcmp(mode_order_policy, 'random_per_case') || numel(modes) <= 1
        return;
    end
    try
        rng(double(random_seed + case_idx), 'twister');
    catch
        rand('seed', double(random_seed + case_idx)); %#ok<RAND>
    end
    mode_sequence = modes(randperm(numel(modes)));
end

function t = extract_timing_breakdown(res_mode)
    t = struct();
    t.mesh_build_s = get_struct_numeric(res_mode, 'time_mesh_build_s', NaN);
    t.linear_solve_s = get_struct_numeric(res_mode, 'time_linear_solve_s', NaN);
    t.magnetic_extract_s = get_struct_numeric(res_mode, 'time_magnetic_extract_s', NaN);
    t.total_case_s = get_struct_numeric(res_mode, 'time_total_s', NaN);
end

function entry = build_entry(entry, mode_results, reference_mode)
    ref_res = pick_mode_result(mode_results, reference_mode);
    fast_res = pick_mode_result(mode_results, 'fast');
    std_res = pick_mode_result(mode_results, 'standard');
    high_res = pick_mode_result(mode_results, 'high');

    entry.completed = true;
    if isfield(ref_res, 'case_id')
        entry.case_id = ref_res.case_id;
    end
    if isfield(ref_res, 'frequency_hz')
        entry.frequency_hz = ref_res.frequency_hz;
    end
    entry.reference = summarize_result(ref_res);
    entry.fast = summarize_result(fast_res);
    entry.standard = summarize_result(std_res);
    entry.high = summarize_result(high_res);
    entry.error_fast = compute_error_metrics(fast_res, ref_res);
    entry.error_standard = compute_error_metrics(std_res, ref_res);
    entry.error_high = compute_error_metrics(high_res, ref_res);
    entry.runtime_ratio_std_vs_fast = safe_ratio( ...
        get_struct_numeric(std_res, 'runtime_s', NaN), ...
        max(get_struct_numeric(fast_res, 'runtime_s', NaN), 1e-9));
    entry.runtime_ratio_high_vs_standard = safe_ratio( ...
        get_struct_numeric(high_res, 'runtime_s', NaN), ...
        max(get_struct_numeric(std_res, 'runtime_s', NaN), 1e-9));
    entry.timestamp = datestr(now, 30);
end

function out = pick_mode_result(mode_results, mode_name)
    out = struct();
    if isstruct(mode_results) && isfield(mode_results, mode_name)
        out = mode_results.(mode_name);
    end
end

function report = build_report(entries, options, runtime_total_s, status_str)
    if nargin < 4 || isempty(status_str)
        status_str = 'complete';
    end
    done_mask = arrayfun(@(e) to_logical(get_struct_numeric(e, 'completed', 0), false), entries);
    completed_entries = entries(done_mask);
    pending_entries = entries(~done_mask);
    pending_ids = cell(1, numel(pending_entries));
    for i = 1:numel(pending_entries)
        pending_ids{i} = pending_entries(i).case_id;
    end

    report = struct();
    report.generated_at = datestr(now, 30);
    report.status = status_str;
    report.case_count = numel(entries);
    report.completed_count = numel(completed_entries);
    report.pending_case_ids = pending_ids;
    report.scope = 'two_switch_forward';
    report.reference_mode = options.reference_mode;
    report.modes = options.modes;
    report.mode_order_policy = options.mode_order_policy;
    report.clear_persistent_between_modes = options.clear_persistent_between_modes;
    report.warmup_runs = options.warmup_runs;
    report.record_timing_breakdown = options.record_timing_breakdown;
    report.runtime_total_s = runtime_total_s;
    report.entries = completed_entries;
    report.summary = summarize_entries(completed_entries);
end

function out = summarize_result(r)
    out = struct();
    out.mode = get_struct_string(r, 'mode', 'unknown');
    out.total_copper_loss_w = get_struct_numeric(r, 'total_copper_loss_w', NaN);
    out.Lm_h = get_struct_numeric(r, 'Lm_h', NaN);
    out.Llk_pri_h = get_struct_numeric(r, 'Llk_pri_h', NaN);
    out.Llk_sec_h = get_struct_numeric(r, 'Llk_sec_h', NaN);
    out.runtime_s = get_struct_numeric(r, 'runtime_s', NaN);
    out.mesh_cells = get_struct_numeric(r, 'mesh_cells', NaN);
    out.uncertainty_pct = get_struct_numeric(r, 'uncertainty_pct', NaN);
    out.converged = to_logical(get_struct_numeric(r, 'converged', 0), false);
    out.stop_reason = get_struct_string(r, 'stop_reason', 'unknown');
    out.linear_solver_used = get_struct_string(r, 'linear_solver_used', 'unknown');
    out.preconditioner_used = get_struct_string(r, 'preconditioner_used', 'none');
    out.iter_backend_used = get_struct_string(r, 'iter_backend_used', 'octave');
    out.matrix_mode_used = get_struct_string(r, 'matrix_mode_used', 'unknown');
    out.interaction_backend_used = get_struct_string(r, 'interaction_backend_used', 'unknown');
    out.iter_relres = get_struct_numeric(r, 'iter_relres', NaN);
    out.iter_count = get_struct_numeric(r, 'iter_count', NaN);
    out.fallback_to_direct = to_logical(get_struct_numeric(r, 'fallback_to_direct', 0), false);
    out.iterative_attempts = get_struct_numeric(r, 'iterative_attempts', NaN);
    out.iterative_retry_used = to_logical(get_struct_numeric(r, 'iterative_retry_used', 0), false);
    out.iter_quality_gate_passed = to_logical(get_struct_numeric(r, 'iter_quality_gate_passed', 1), true);
    out.iter_rejected_reason = get_struct_string(r, 'iter_rejected_reason', '');
    out.had_solver_warning = to_logical(get_struct_numeric(r, 'had_solver_warning', 0), false);
    out.warning_kind = get_struct_string(r, 'warning_kind', '');
    out.mesh_refine_iterations = get_struct_numeric(r, 'mesh_refine_iterations', NaN);
    out.fft_eligible = to_logical(get_struct_numeric(r, 'fft_eligible', 0), false);
    out.fft_used = to_logical(get_struct_numeric(r, 'fft_used', 0), false);
    out.mode_order = get_struct_field(r, 'mode_order', {});
    out.timing_breakdown = get_struct_field(r, 'timing_breakdown', struct());
end

function err = compute_error_metrics(candidate, reference)
    err = struct();
    err.loss_rel = relative_error( ...
        get_struct_numeric(candidate, 'total_copper_loss_w', NaN), ...
        get_struct_numeric(reference, 'total_copper_loss_w', NaN));
    err.llk_pri_rel = relative_error( ...
        get_struct_numeric(candidate, 'Llk_pri_h', NaN), ...
        get_struct_numeric(reference, 'Llk_pri_h', NaN));
    err.llk_sec_rel = relative_error( ...
        get_struct_numeric(candidate, 'Llk_sec_h', NaN), ...
        get_struct_numeric(reference, 'Llk_sec_h', NaN));
    err.lm_rel = relative_error( ...
        get_struct_numeric(candidate, 'Lm_h', NaN), ...
        get_struct_numeric(reference, 'Lm_h', NaN));
end

function s = summarize_entries(entries)
    s = struct();
    if isempty(entries)
        s.note = 'No completed entries';
        return;
    end

    fast_loss_err = arrayfun(@(e) get_struct_numeric(get_struct_field(e, 'error_fast', struct()), 'loss_rel', NaN), entries);
    std_loss_err = arrayfun(@(e) get_struct_numeric(get_struct_field(e, 'error_standard', struct()), 'loss_rel', NaN), entries);
    fast_llk_err = arrayfun(@(e) get_struct_numeric(get_struct_field(e, 'error_fast', struct()), 'llk_pri_rel', NaN), entries);
    std_llk_err = arrayfun(@(e) get_struct_numeric(get_struct_field(e, 'error_standard', struct()), 'llk_pri_rel', NaN), entries);
    fast_rt = arrayfun(@(e) get_struct_numeric(get_struct_field(e, 'fast', struct()), 'runtime_s', NaN), entries);
    std_rt = arrayfun(@(e) get_struct_numeric(get_struct_field(e, 'standard', struct()), 'runtime_s', NaN), entries);
    ref_rt = arrayfun(@(e) get_struct_numeric(get_struct_field(e, 'reference', struct()), 'runtime_s', NaN), entries);
    mesh_build_fast = arrayfun(@(e) get_timing_field(e, 'fast', 'mesh_build_s'), entries);
    linear_solve_fast = arrayfun(@(e) get_timing_field(e, 'fast', 'linear_solve_s'), entries);
    mesh_build_std = arrayfun(@(e) get_timing_field(e, 'standard', 'mesh_build_s'), entries);
    linear_solve_std = arrayfun(@(e) get_timing_field(e, 'standard', 'linear_solve_s'), entries);
    fast_iter_used = arrayfun(@(e) ~strcmpi(get_struct_string(get_struct_field(e, 'fast', struct()), 'linear_solver_used', 'direct'), 'direct'), entries);
    fast_fallback = arrayfun(@(e) to_logical(get_struct_numeric(get_struct_field(e, 'fast', struct()), 'fallback_to_direct', 0), false), entries);
    fast_retry = arrayfun(@(e) to_logical(get_struct_numeric(get_struct_field(e, 'fast', struct()), 'iterative_retry_used', 0), false), entries);
    fast_quality_pass = arrayfun(@(e) to_logical(get_struct_numeric(get_struct_field(e, 'fast', struct()), 'iter_quality_gate_passed', 1), true), entries);
    fast_warning = arrayfun(@(e) to_logical(get_struct_numeric(get_struct_field(e, 'fast', struct()), 'had_solver_warning', 0), false), entries);
    fast_iter_backend_external = arrayfun(@(e) strcmpi(get_struct_string(get_struct_field(e, 'fast', struct()), 'iter_backend_used', 'octave'), 'external'), entries);
    fast_fft_eligible = arrayfun(@(e) to_logical(get_struct_numeric(get_struct_field(e, 'fast', struct()), 'fft_eligible', 0), false), entries);
    fast_fft_used = arrayfun(@(e) to_logical(get_struct_numeric(get_struct_field(e, 'fast', struct()), 'fft_used', 0), false), entries);

    s.completed_entries = numel(entries);
    s.median_loss_error_fast_pct = 100 * median_no_nan(fast_loss_err);
    s.median_loss_error_standard_pct = 100 * median_no_nan(std_loss_err);
    s.median_llk_error_fast_pct = 100 * median_no_nan(fast_llk_err);
    s.median_llk_error_standard_pct = 100 * median_no_nan(std_llk_err);
    s.median_runtime_fast_s = median_no_nan(fast_rt);
    s.median_runtime_standard_s = median_no_nan(std_rt);
    s.median_runtime_reference_s = median_no_nan(ref_rt);
    s.standard_vs_fast_runtime_ratio = safe_ratio(s.median_runtime_standard_s, max(s.median_runtime_fast_s, 1e-9));
    s.median_mesh_build_fast_s = median_no_nan(mesh_build_fast);
    s.median_linear_solve_fast_s = median_no_nan(linear_solve_fast);
    s.median_mesh_build_standard_s = median_no_nan(mesh_build_std);
    s.median_linear_solve_standard_s = median_no_nan(linear_solve_std);
    s.fast_iterative_usage_fraction = mean(double(fast_iter_used));
    s.fast_fallback_to_direct_fraction = mean(double(fast_fallback));
    s.fast_retry_used_fraction = mean(double(fast_retry));
    s.fast_iter_quality_reject_fraction = mean(double(~fast_quality_pass));
    s.fast_solver_warning_fraction = mean(double(fast_warning));
    s.fast_external_iter_backend_fraction = mean(double(fast_iter_backend_external));
    s.fft_eligible_fraction = mean(double(fast_fft_eligible));
    s.fft_used_fraction = mean(double(fast_fft_used));
    s.standard_vs_fast_loss_error_gain_pct = ...
        s.median_loss_error_fast_pct - s.median_loss_error_standard_pct;
    s.standard_vs_fast_llk_error_gain_pct = ...
        s.median_llk_error_fast_pct - s.median_llk_error_standard_pct;
end

function v = get_timing_field(entry, mode_name, timing_field)
    v = NaN;
    mode_obj = get_struct_field(entry, mode_name, struct());
    t_obj = get_struct_field(mode_obj, 'timing_breakdown', struct());
    v = get_struct_numeric(t_obj, timing_field, NaN);
end

function m = median_no_nan(v)
    m = NaN;
    if isempty(v)
        return;
    end
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

function e = relative_error(v, ref)
    e = NaN;
    if ~isfinite(v) || ~isfinite(ref)
        return;
    end
    e = abs(v - ref) / max(abs(ref), 1e-12);
end

function obj = load_json_file(in_file)
    fid = fopen(in_file, 'r');
    if fid == -1
        error('run_accuracy_benchmarks: cannot open %s', in_file);
    end
    raw = fread(fid, '*char')';
    fclose(fid);
    raw = sanitize_json_text(raw);
    obj = jsondecode(raw);
end

function txt = sanitize_json_text(txt)
    if isempty(txt)
        return;
    end
    if double(txt(1)) == 65279
        txt = txt(2:end);
    end
    txt = strtrim(txt);
end

function write_json(payload, out_file)
    fid = fopen(out_file, 'w');
    if fid == -1
        error('run_accuracy_benchmarks: cannot write %s', out_file);
    end
    fwrite(fid, jsonencode(payload));
    fclose(fid);
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

function out = get_struct_string(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if is_text_like(v)
            out = char(v);
        end
    end
end

function out = get_struct_field(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        out = s.(field_name);
    end
end

function tf = to_logical(v, default_val)
    if nargin < 2
        default_val = false;
    end
    tf = default_val;
    if islogical(v) && isscalar(v)
        tf = v;
    elseif isnumeric(v) && isscalar(v)
        tf = (v ~= 0);
    end
end

function tf = is_text_like(v)
    tf = ischar(v);
    if tf
        return;
    end
    if exist('isstring', 'builtin') || exist('isstring', 'file')
        tf = isstring(v);
    else
        tf = false;
    end
end

function ensure_phase3_paths()
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(root);
    addpath(here);
    subdirs = {'mesh', 'corrections', 'physics', 'kernels', 'litz'};
    for i = 1:numel(subdirs)
        p = fullfile(root, subdirs{i});
        if exist(p, 'dir')
            addpath(p);
        end
    end
end
