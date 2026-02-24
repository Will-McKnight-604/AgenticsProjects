function report = evaluate_tuning_config(tune_cfg, options)
%EVALUATE_TUNING_CONFIG Constrained evaluation of one tuning configuration.
%
% Example:
%   cfg = struct('fast_direct_guard_nf_max', 1800, 'standard_direct_guard_nf_max', 2400);
%   rep = evaluate_tuning_config(cfg);

    ensure_local_paths();

    if nargin < 1 || ~isstruct(tune_cfg)
        tune_cfg = struct();
    end
    if nargin < 2 || ~isstruct(options)
        options = struct();
    end
    options = normalize_options(options);

    if ~exist(options.results_dir, 'dir')
        mkdir(options.results_dir);
    end

    cache_key = build_eval_cache_key(tune_cfg, options);
    if options.reuse_eval_cache
        [hit, rep_cached] = lookup_eval_cache(options.eval_cache_file, cache_key);
        if hit
            report = rep_cached;
            return;
        end
    end

    feat_opts = struct( ...
        'case_ids', {options.case_ids}, ...
        'case_indices', options.case_indices, ...
        'max_cases', options.max_cases, ...
        'save_results', false);
    feat_report = extract_case_features(options.case_dir, feat_opts);
    feats = feat_report.features;
    if isempty(feats)
        error('evaluate_tuning_config: no selected cases to evaluate');
    end

    ref_cache = ensure_reference_cache(feats, options);
    [entries, summary] = evaluate_cases(feats, tune_cfg, ref_cache, options);
    [pass_flags, score] = score_summary(summary, options);

    report = struct();
    report.generated_at = datestr(now, 30);
    report.config = tune_cfg;
    report.cache_key = cache_key;
    report.case_dir = options.case_dir;
    report.case_count = numel(entries);
    report.case_ids = {entries.case_id};
    report.options = sanitize_options_for_report(options);
    report.entries = entries;
    report.summary = summary;
    report.pass_flags = pass_flags;
    report.pass = pass_flags.standard_loss_ok && pass_flags.fast_outlier_ok && ...
        pass_flags.warning_ok && pass_flags.quality_ok;
    report.objective_score = score;

    if options.save_results
        out_latest = fullfile(options.results_dir, 'evaluate_tuning_config_latest.json');
        out_stamp = fullfile(options.results_dir, sprintf('evaluate_tuning_config_%s.json', report.generated_at));
        write_json(report, out_latest);
        write_json(report, out_stamp);
    end

    if options.reuse_eval_cache
        upsert_eval_cache(options.eval_cache_file, cache_key, report);
    end
end

function options = normalize_options(options)
    here = fileparts(mfilename('fullpath'));
    def = struct();
    def.case_dir = fullfile(here, 'mas_cases_real');
    def.case_ids = {};
    def.case_indices = [];
    def.max_cases = inf;
    def.results_dir = fullfile(here, 'results_hyperband');
    def.reference_cache_file = fullfile(def.results_dir, 'reference_high_cache.mat');
    def.eval_cache_file = fullfile(def.results_dir, 'eval_cache.mat');
    def.reuse_eval_cache = true;
    def.refresh_reference_cache = false;
    def.use_case_policy = true;
    def.repeat_count = 1;
    def.verbose = false;
    def.save_results = true;
    def.criteria = optimization_pass_criteria();
    def.objective_fast_weight = 1.0;
    def.objective_standard_weight = 0.35;
    def.stage_name = 'adhoc';

    f = fieldnames(def);
    for i = 1:numel(f)
        if ~isfield(options, f{i})
            options.(f{i}) = def.(f{i});
        end
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
    if ~isnumeric(options.max_cases) || ~isscalar(options.max_cases) || ~isfinite(options.max_cases) || options.max_cases <= 0
        options.max_cases = inf;
    end
    options.reuse_eval_cache = to_logical(options.reuse_eval_cache, true);
    options.refresh_reference_cache = to_logical(options.refresh_reference_cache, false);
    options.use_case_policy = to_logical(options.use_case_policy, true);
    options.verbose = to_logical(options.verbose, false);
    options.save_results = to_logical(options.save_results, true);
    options.repeat_count = max(1, round(get_struct_numeric(options, 'repeat_count', 1)));
    options.objective_fast_weight = max(0, get_struct_numeric(options, 'objective_fast_weight', 1.0));
    options.objective_standard_weight = max(0, get_struct_numeric(options, 'objective_standard_weight', 0.35));

    if ~isstruct(options.criteria)
        options.criteria = optimization_pass_criteria();
    else
        options.criteria = merge_structs(optimization_pass_criteria(), options.criteria);
    end
end

function ref_cache = ensure_reference_cache(feats, options)
    ref_cache = load_reference_cache(options.reference_cache_file);
    for i = 1:numel(feats)
        cid = feats(i).case_id;
        idx = find_reference_entry(ref_cache.entries, cid);
        if options.refresh_reference_cache || (idx == 0)
            high_opts = solver_option_profile('high');
            high_opts.linear_solver = 'direct';
            high_opts.matrix_mode = 'dense';
            high_opts.interaction_backend = 'dense';
            high_opts.enable_external_krylov = false;
            high_opts.enable_solver_cache = true;

            if options.verbose
                fprintf('[EVAL] Building high reference: %s\n', cid);
            end
            res = execute_mas_case(feats(i).case_path, high_opts);
            e = struct();
            e.case_id = cid;
            e.case_file = feats(i).case_file;
            e.runtime_s = get_struct_numeric(res, 'runtime_s', NaN);
            e.total_copper_loss_w = get_struct_numeric(res, 'total_copper_loss_w', NaN);
            e.Lm_h = get_struct_numeric(res, 'Lm_h', NaN);
            e.Llk_pri_h = get_struct_numeric(res, 'Llk_pri_h', NaN);
            e.Llk_sec_h = get_struct_numeric(res, 'Llk_sec_h', NaN);
            e.generated_at = datestr(now, 30);

            if idx > 0
                ref_cache.entries(idx) = e;
            else
                ref_cache.entries(end+1) = e; %#ok<AGROW>
            end
        end
    end
    save_reference_cache(options.reference_cache_file, ref_cache);
end

function [entries, summary] = evaluate_cases(feats, tune_cfg, ref_cache, options)
    n = numel(feats);
    entries = repmat(empty_entry(), n, 1);

    for i = 1:n
        feat = feats(i);
        ref_idx = find_reference_entry(ref_cache.entries, feat.case_id);
        if ref_idx == 0
            error('evaluate_tuning_config: missing reference for case %s', feat.case_id);
        end
        ref = ref_cache.entries(ref_idx);

        [fast_res, fast_meta] = run_mode_case(feat, 'fast', tune_cfg, options);
        [std_res, std_meta] = run_mode_case(feat, 'standard', tune_cfg, options);

        e = empty_entry();
        e.case_id = feat.case_id;
        e.case_file = feat.case_file;
        e.feature = feat;
        e.reference = ref;
        e.fast = fast_res;
        e.standard = std_res;
        e.fast_policy = fast_meta;
        e.standard_policy = std_meta;
        e.error_fast = compute_error(fast_res, ref);
        e.error_standard = compute_error(std_res, ref);
        e.fast_runtime_delta_pct = 100 * safe_ratio(get_struct_numeric(fast_res, 'runtime_s', NaN), max(ref.runtime_s, 1e-9)) - 100;
        e.standard_runtime_delta_pct = 100 * safe_ratio(get_struct_numeric(std_res, 'runtime_s', NaN), max(ref.runtime_s, 1e-9)) - 100;
        entries(i) = e;
    end

    summary = summarize_entries(entries);
end

function [res_med, policy_meta] = run_mode_case(feat, mode_name, tune_cfg, options)
    opts = solver_option_profile(mode_name);
    opts = apply_config_to_mode_opts(opts, tune_cfg, mode_name);
    policy_meta = struct();
    if options.use_case_policy
        [ov, policy_meta] = choose_solver_policy(feat, mode_name, tune_cfg, opts);
        opts = merge_structs(opts, ov);
    end

    reps = max(1, options.repeat_count);
    runs = repmat(struct(), reps, 1);
    for r = 1:reps
        runs(r) = execute_mas_case(feat.case_path, opts);
    end
    idx = select_median_runtime_run(runs);
    res_med = runs(idx);
end

function idx = select_median_runtime_run(runs)
    idx = 1;
    if isempty(runs)
        return;
    end
    rt = arrayfun(@(x) get_struct_numeric(x, 'runtime_s', NaN), runs);
    good = find(isfinite(rt));
    if isempty(good)
        return;
    end
    [~, order] = sort(rt(good));
    mid = good(order(ceil(numel(order)/2)));
    idx = mid;
end

function opts = apply_config_to_mode_opts(opts, cfg, mode_name)
    opts.iter_min_size_for_use = get_cfg_num(cfg, 'iter_min_size_for_use', get_struct_numeric(opts, 'iter_min_size_for_use', 2200));
    opts.precond_drop_tol = get_cfg_num(cfg, 'precond_drop_tol', get_struct_numeric(opts, 'precond_drop_tol', 1e-2));
    if strcmp(mode_name, 'fast')
        opts.fast_direct_guard_nf_max = round(get_cfg_num(cfg, 'fast_direct_guard_nf_max', get_struct_numeric(opts, 'fast_direct_guard_nf_max', 2200)));
    elseif strcmp(mode_name, 'standard')
        opts.standard_direct_guard_nf_max = round(get_cfg_num(cfg, 'standard_direct_guard_nf_max', get_struct_numeric(opts, 'standard_direct_guard_nf_max', 2600)));
    end
end

function e = compute_error(candidate, reference)
    e = struct();
    e.loss_rel = relative_error(get_struct_numeric(candidate, 'total_copper_loss_w', NaN), reference.total_copper_loss_w);
    e.lm_rel = relative_error(get_struct_numeric(candidate, 'Lm_h', NaN), reference.Lm_h);
    e.llk_pri_rel = relative_error(get_struct_numeric(candidate, 'Llk_pri_h', NaN), reference.Llk_pri_h);
    e.llk_sec_rel = relative_error(get_struct_numeric(candidate, 'Llk_sec_h', NaN), reference.Llk_sec_h);
end

function s = summarize_entries(entries)
    s = struct();
    if isempty(entries)
        s.note = 'No entries';
        return;
    end
    fast_rt = arrayfun(@(e) get_struct_numeric(e.fast, 'runtime_s', NaN), entries);
    std_rt = arrayfun(@(e) get_struct_numeric(e.standard, 'runtime_s', NaN), entries);
    ref_rt = arrayfun(@(e) get_struct_numeric(e.reference, 'runtime_s', NaN), entries);
    fast_loss = arrayfun(@(e) get_struct_numeric(e.error_fast, 'loss_rel', NaN), entries);
    std_loss = arrayfun(@(e) get_struct_numeric(e.error_standard, 'loss_rel', NaN), entries);
    fast_warn = arrayfun(@(e) to_logical(get_struct_numeric(e.fast, 'had_solver_warning', 0), false), entries);
    std_warn = arrayfun(@(e) to_logical(get_struct_numeric(e.standard, 'had_solver_warning', 0), false), entries);
    fast_quality = arrayfun(@(e) to_logical(get_struct_numeric(e.fast, 'iter_quality_gate_passed', 1), true), entries);
    fft_used = arrayfun(@(e) to_logical(get_struct_numeric(e.fast, 'fft_used', 0), false), entries);

    s.case_count = numel(entries);
    s.median_runtime_fast_s = median_no_nan(fast_rt);
    s.median_runtime_standard_s = median_no_nan(std_rt);
    s.median_runtime_reference_s = median_no_nan(ref_rt);
    s.median_loss_error_fast_pct = 100 * median_no_nan(fast_loss);
    s.median_loss_error_standard_pct = 100 * median_no_nan(std_loss);
    s.max_fast_loss_err_pct = 100 * max_no_nan(fast_loss);
    s.fast_solver_warning_fraction = mean(double(fast_warn));
    s.standard_solver_warning_fraction = mean(double(std_warn));
    s.warning_fraction = mean(double(fast_warn | std_warn));
    s.fast_iter_quality_reject_fraction = mean(double(~fast_quality));
    s.fft_used_fraction = mean(double(fft_used));
end

function [flags, score] = score_summary(summary, options)
    criteria = options.criteria;
    w_fast = max(0, get_struct_numeric(options, 'objective_fast_weight', 1.0));
    w_std = max(0, get_struct_numeric(options, 'objective_standard_weight', 0.35));
    fast_target = get_struct_numeric(criteria, 'fast_loss_error_target_pct', NaN);
    fast_hard_max = get_struct_numeric(criteria, 'max_fast_loss_err_pct_max', 15.0);
    if ~isfinite(fast_target)
        fast_target = fast_hard_max;
    end
    fast_target = min(fast_target, fast_hard_max);

    flags = struct();
    flags.standard_loss_ok = isfinite(summary.median_loss_error_standard_pct) && ...
        (summary.median_loss_error_standard_pct <= criteria.tuned_standard_loss_error_median_pct_max);
    flags.fast_target_ok = isfinite(summary.max_fast_loss_err_pct) && ...
        (summary.max_fast_loss_err_pct <= fast_target);
    flags.fast_outlier_ok = isfinite(summary.max_fast_loss_err_pct) && ...
        (summary.max_fast_loss_err_pct <= fast_hard_max);
    flags.warning_ok = isfinite(summary.warning_fraction) && ...
        (summary.warning_fraction <= criteria.warning_fraction_max);
    flags.quality_ok = isfinite(summary.fast_iter_quality_reject_fraction) && ...
        (summary.fast_iter_quality_reject_fraction <= 0);

    score = w_fast * summary.median_runtime_fast_s + w_std * summary.median_runtime_standard_s;
    if ~flags.standard_loss_ok
        score = score + 1000 + 50 * max(0, summary.median_loss_error_standard_pct - criteria.tuned_standard_loss_error_median_pct_max);
    end
    if ~flags.fast_target_ok
        score = score + 120 + 30 * max(0, summary.max_fast_loss_err_pct - fast_target);
    end
    if ~flags.fast_outlier_ok
        score = score + 1000 + 40 * max(0, summary.max_fast_loss_err_pct - fast_hard_max);
    end
    if ~flags.warning_ok
        score = score + 600 + 400 * max(0, summary.warning_fraction - criteria.warning_fraction_max);
    end
    if ~flags.quality_ok
        score = score + 800 + 400 * max(0, summary.fast_iter_quality_reject_fraction);
    end
end

function key = build_eval_cache_key(cfg, options)
    key_payload = struct();
    key_payload.eval_policy_version = 'eval_v3_fastcap_10_15';
    key_payload.cfg = cfg;
    key_payload.case_dir = options.case_dir;
    key_payload.case_ids = options.case_ids;
    key_payload.case_indices = options.case_indices;
    key_payload.max_cases = options.max_cases;
    key_payload.use_case_policy = options.use_case_policy;
    key_payload.repeat_count = options.repeat_count;
    key_payload.stage_name = options.stage_name;
    key_payload.criteria = options.criteria;
    key_payload.objective_fast_weight = get_struct_numeric(options, 'objective_fast_weight', 1.0);
    key_payload.objective_standard_weight = get_struct_numeric(options, 'objective_standard_weight', 0.35);
    txt = jsonencode(key_payload);
    key = simple_string_hash(txt);
end

function h = simple_string_hash(txt)
    bytes = uint8(txt);
    v = uint64(1469598103934665603);
    p = uint64(1099511628211);
    for i = 1:numel(bytes)
        v = bitxor(v, uint64(bytes(i)));
        v = v * p;
    end
    h = sprintf('%016x', v);
end

function [hit, report] = lookup_eval_cache(cache_file, key)
    hit = false;
    report = struct();
    if ~exist(cache_file, 'file')
        return;
    end
    try
        s = load(cache_file, 'entries');
    catch
        return;
    end
    if ~isstruct(s) || ~isfield(s, 'entries')
        return;
    end
    entries = s.entries;
    if isempty(entries)
        return;
    end
    for i = 1:numel(entries)
        if isfield(entries(i), 'key') && strcmp(entries(i).key, key)
            hit = true;
            report = entries(i).report;
            return;
        end
    end
end

function upsert_eval_cache(cache_file, key, report)
    entries = struct('key', {}, 'report', {});
    if exist(cache_file, 'file')
        try
            s = load(cache_file, 'entries');
            if isstruct(s) && isfield(s, 'entries')
                entries = s.entries;
            end
        catch
        end
    end
    idx = 0;
    for i = 1:numel(entries)
        if isfield(entries(i), 'key') && strcmp(entries(i).key, key)
            idx = i;
            break;
        end
    end
    row = struct('key', key, 'report', report);
    if idx > 0
        entries(idx) = row;
    else
        entries(end+1) = row; %#ok<AGROW>
    end
    try
        save(cache_file, 'entries');
    catch
    end
end

function cache = load_reference_cache(cache_file)
    cache = struct();
    cache.entries = struct('case_id', {}, 'case_file', {}, 'runtime_s', {}, ...
        'total_copper_loss_w', {}, 'Lm_h', {}, 'Llk_pri_h', {}, 'Llk_sec_h', {}, 'generated_at', {});
    if ~exist(cache_file, 'file')
        return;
    end
    try
        s = load(cache_file, 'cache');
        if isstruct(s) && isfield(s, 'cache') && isstruct(s.cache) && isfield(s.cache, 'entries')
            cache = s.cache;
        end
    catch
    end
end

function save_reference_cache(cache_file, cache)
    try
        save(cache_file, 'cache');
    catch
    end
end

function idx = find_reference_entry(entries, case_id)
    idx = 0;
    for i = 1:numel(entries)
        if isfield(entries(i), 'case_id') && strcmp(entries(i).case_id, case_id)
            idx = i;
            return;
        end
    end
end

function e = empty_entry()
    e = struct();
    e.case_id = '';
    e.case_file = '';
    e.feature = struct();
    e.reference = struct();
    e.fast = struct();
    e.standard = struct();
    e.fast_policy = struct();
    e.standard_policy = struct();
    e.error_fast = struct();
    e.error_standard = struct();
    e.fast_runtime_delta_pct = NaN;
    e.standard_runtime_delta_pct = NaN;
end

function out = sanitize_options_for_report(options)
    out = options;
    if isfield(out, 'criteria') && isstruct(out.criteria)
        out.criteria = out.criteria;
    end
end

function write_json(payload, out_file)
    fid = fopen(out_file, 'w');
    if fid == -1
        error('evaluate_tuning_config: cannot write %s', out_file);
    end
    fwrite(fid, jsonencode(payload));
    fclose(fid);
end

function m = median_no_nan(v)
    m = NaN;
    x = v(isfinite(v));
    if ~isempty(x)
        m = median(x);
    end
end

function m = max_no_nan(v)
    m = NaN;
    x = v(isfinite(v));
    if ~isempty(x)
        m = max(x);
    end
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

function out = get_cfg_num(cfg, field_name, default_val)
    out = default_val;
    if isstruct(cfg) && isfield(cfg, field_name)
        v = cfg.(field_name);
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

function tf = to_logical(v, default_val)
    tf = default_val;
    if islogical(v) && isscalar(v)
        tf = v;
    elseif isnumeric(v) && isscalar(v)
        tf = (v ~= 0);
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
