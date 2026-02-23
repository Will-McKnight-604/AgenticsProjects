function report = tune_solver_hyperband(options)
%TUNE_SOLVER_HYPERBAND Multi-fidelity constrained tuner for solver settings.
%
% Example:
%   rep = tune_solver_hyperband();
%   rep = tune_solver_hyperband(struct('initial_candidates', 20, 'stage_case_counts', [4 8 12]));

    ensure_local_paths();

    if nargin < 1 || ~isstruct(options)
        options = struct();
    end
    options = normalize_options(options);

    if ~exist(options.results_dir, 'dir')
        mkdir(options.results_dir);
    end

    if options.verbose
        fprintf('[HB] Extracting case features from %s\n', options.case_dir);
    end
    feat_opts = struct( ...
        'save_results', true, ...
        'results_dir', options.results_dir, ...
        'case_ids', {options.case_ids}, ...
        'case_indices', options.case_indices, ...
        'max_cases', options.max_cases);
    feat_report = extract_case_features(options.case_dir, feat_opts);
    feats_all = feat_report.features;
    if isempty(feats_all)
        error('tune_solver_hyperband: no cases available');
    end

    cand = build_candidate_pool(options);
    alive = 1:numel(cand);

    stages = repmat(struct(), numel(options.stage_case_counts), 1);
    for s = 1:numel(options.stage_case_counts)
        n_cases = min(options.stage_case_counts(s), numel(feats_all));
        case_ids = select_representative_case_ids(feats_all, n_cases);
        reps = options.stage_repeat_counts(min(s, numel(options.stage_repeat_counts)));

        if options.verbose
            fprintf('[HB] Stage %d/%d | candidates=%d | cases=%d | repeats=%d\n', ...
                s, numel(options.stage_case_counts), numel(alive), n_cases, reps);
        end

        rows = repmat(struct(), numel(alive), 1);
        for i = 1:numel(alive)
            ci = alive(i);
            ev_opts = struct();
            ev_opts.case_dir = options.case_dir;
            ev_opts.case_ids = case_ids;
            ev_opts.max_cases = inf;
            ev_opts.results_dir = options.results_dir;
            ev_opts.reference_cache_file = options.reference_cache_file;
            ev_opts.eval_cache_file = options.eval_cache_file;
            ev_opts.reuse_eval_cache = options.reuse_eval_cache;
            ev_opts.refresh_reference_cache = options.refresh_reference_cache && (s == 1 && i == 1);
            ev_opts.use_case_policy = options.use_case_policy;
            ev_opts.repeat_count = reps;
            ev_opts.criteria = options.criteria;
            ev_opts.save_results = false;
            ev_opts.verbose = false;
            ev_opts.stage_name = sprintf('stage_%02d', s);

            ev = evaluate_tuning_config(cand(ci).cfg, ev_opts);
            rows(i) = build_stage_row(ci, cand(ci), ev);

            if options.verbose
                fprintf('[HB]   cand %02d/%02d id=%s score=%.3f pass=%d fast=%.3fs std=%.3fs\n', ...
                    i, numel(alive), cand(ci).id, rows(i).objective_score, double(rows(i).pass), ...
                    rows(i).median_runtime_fast_s, rows(i).median_runtime_standard_s);
            end
        end

        [~, ord] = sort([rows.objective_score]);
        rows = rows(ord);

        stages(s).stage_index = s;
        stages(s).case_count = n_cases;
        stages(s).repeat_count = reps;
        stages(s).case_ids = case_ids;
        stages(s).rows = rows;
        stages(s).best_candidate_id = rows(1).candidate_id;
        stages(s).best_score = rows(1).objective_score;

        if s < numel(options.stage_case_counts)
            keep_n = max(2, ceil(options.keep_fraction(min(s, numel(options.keep_fraction))) * numel(rows)));
            keep_n = min(keep_n, numel(rows));
            keep_ids = {rows(1:keep_n).candidate_id};
            alive = find_candidate_indices(cand, keep_ids);
        else
            alive = find_candidate_indices(cand, {rows.candidate_id});
        end
    end

    final_rows = stages(end).rows;
    best_row = final_rows(1);
    best_idx = find_candidate_indices(cand, {best_row.candidate_id});
    best_idx = best_idx(1);

    report = struct();
    report.generated_at = datestr(now, 30);
    report.case_dir = options.case_dir;
    report.results_dir = options.results_dir;
    report.criteria = options.criteria;
    report.options = sanitize_options_for_report(options);
    report.candidate_count = numel(cand);
    report.candidates = cand;
    report.stages = stages;
    report.best_candidate_id = cand(best_idx).id;
    report.best_config = cand(best_idx).cfg;
    report.best_objective_score = best_row.objective_score;
    report.best_pass = best_row.pass;
    report.best_summary = best_row.summary;

    out_latest = fullfile(options.results_dir, 'hyperband_tuning_latest.json');
    out_stamp = fullfile(options.results_dir, sprintf('hyperband_tuning_%s.json', report.generated_at));
    write_json(report, out_latest);
    write_json(report, out_stamp);
    if options.verbose
        fprintf('[HB] Wrote: %s\n', out_latest);
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
    def.initial_candidates = 18;
    def.random_seed = 17;
    def.stage_case_counts = [4 8 12];
    def.stage_repeat_counts = [1 1 1];
    def.keep_fraction = [0.40 0.35];
    def.reuse_eval_cache = true;
    def.refresh_reference_cache = false;
    def.use_case_policy = true;
    def.verbose = true;
    def.criteria = optimization_pass_criteria();

    f = fieldnames(def);
    for i = 1:numel(f)
        if ~isfield(options, f{i})
            options.(f{i}) = def.(f{i});
        end
    end

    options.initial_candidates = max(4, round(options.initial_candidates));
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
    if ~isnumeric(options.stage_case_counts) || isempty(options.stage_case_counts)
        options.stage_case_counts = def.stage_case_counts;
    end
    options.stage_case_counts = max(1, round(options.stage_case_counts(:)'));

    if ~isnumeric(options.stage_repeat_counts) || isempty(options.stage_repeat_counts)
        options.stage_repeat_counts = def.stage_repeat_counts;
    end
    options.stage_repeat_counts = max(1, round(options.stage_repeat_counts(:)'));

    if ~isnumeric(options.keep_fraction) || isempty(options.keep_fraction)
        options.keep_fraction = def.keep_fraction;
    end
    options.keep_fraction = max(0.10, min(0.90, options.keep_fraction(:)'));

    options.reuse_eval_cache = to_logical(options.reuse_eval_cache, true);
    options.refresh_reference_cache = to_logical(options.refresh_reference_cache, false);
    options.use_case_policy = to_logical(options.use_case_policy, true);
    options.verbose = to_logical(options.verbose, true);

    if ~isstruct(options.criteria)
        options.criteria = optimization_pass_criteria();
    else
        options.criteria = merge_structs(optimization_pass_criteria(), options.criteria);
    end
end

function candidates = build_candidate_pool(options)
    seed_rng(options.random_seed);

    candidates = struct('id', {}, 'cfg', {}, 'origin', {});
    idx = 0;

    % Baseline from current defaults.
    std_opts = solver_option_profile('standard');
    base_cfg = struct();
    base_cfg.fast_direct_guard_nf_max = get_struct_numeric(std_opts, 'fast_direct_guard_nf_max', 2200);
    base_cfg.standard_direct_guard_nf_max = get_struct_numeric(std_opts, 'standard_direct_guard_nf_max', 2600);
    base_cfg.iter_min_size_for_use = get_struct_numeric(std_opts, 'iter_min_size_for_use', 2200);
    base_cfg.precond_drop_tol = get_struct_numeric(std_opts, 'precond_drop_tol', 1e-2);
    idx = idx + 1;
    candidates(idx) = make_candidate(idx, base_cfg, 'current_default');

    % Conservative direct-first seed.
    cfg_direct = base_cfg;
    cfg_direct.fast_direct_guard_nf_max = max(cfg_direct.fast_direct_guard_nf_max, 2600);
    cfg_direct.standard_direct_guard_nf_max = max(cfg_direct.standard_direct_guard_nf_max, 3200);
    cfg_direct.iter_min_size_for_use = max(cfg_direct.iter_min_size_for_use, 2600);
    idx = idx + 1;
    candidates(idx) = make_candidate(idx, cfg_direct, 'direct_first_seed');

    % Iterative-leaning seed.
    cfg_iter = base_cfg;
    cfg_iter.fast_direct_guard_nf_max = max(400, round(0.55 * cfg_iter.fast_direct_guard_nf_max));
    cfg_iter.standard_direct_guard_nf_max = max(800, round(0.65 * cfg_iter.standard_direct_guard_nf_max));
    cfg_iter.iter_min_size_for_use = max(700, round(0.60 * cfg_iter.iter_min_size_for_use));
    cfg_iter.precond_drop_tol = max(5e-4, min(2e-2, cfg_iter.precond_drop_tol * 0.5));
    idx = idx + 1;
    candidates(idx) = make_candidate(idx, cfg_iter, 'iterative_seed');

    while numel(candidates) < options.initial_candidates
        cfg = sample_random_cfg();
        if is_duplicate_cfg(candidates, cfg)
            continue;
        end
        idx = idx + 1;
        candidates(idx) = make_candidate(idx, cfg, 'random');
    end
end

function cfg = sample_random_cfg()
    cfg = struct();
    cfg.fast_direct_guard_nf_max = randi([400, 2800], 1, 1);
    cfg.standard_direct_guard_nf_max = randi([900, 3600], 1, 1);
    cfg.iter_min_size_for_use = randi([700, 3000], 1, 1);
    lo = log10(5e-4);
    hi = log10(3e-2);
    cfg.precond_drop_tol = 10 ^ (lo + rand() * (hi - lo));
end

function tf = is_duplicate_cfg(candidates, cfg)
    tf = false;
    for i = 1:numel(candidates)
        c = candidates(i).cfg;
        same_int = (round(c.fast_direct_guard_nf_max) == round(cfg.fast_direct_guard_nf_max)) && ...
                   (round(c.standard_direct_guard_nf_max) == round(cfg.standard_direct_guard_nf_max)) && ...
                   (round(c.iter_min_size_for_use) == round(cfg.iter_min_size_for_use));
        same_drop = abs(log10(max(c.precond_drop_tol, 1e-12)) - log10(max(cfg.precond_drop_tol, 1e-12))) < 1e-6;
        if same_int && same_drop
            tf = true;
            return;
        end
    end
end

function row = make_candidate(idx, cfg, origin)
    row = struct();
    row.id = sprintf('cfg_%03d', idx);
    row.cfg = cfg;
    row.origin = origin;
end

function ids = select_representative_case_ids(feats, n_keep)
    if n_keep >= numel(feats)
        ids = {feats.case_id};
        return;
    end
    scores = [feats.complexity_score];
    [~, ord] = sort(scores);
    pos = unique(round(linspace(1, numel(ord), n_keep)));
    pos = max(1, min(numel(ord), pos));
    ids = cell(1, numel(pos));
    for i = 1:numel(pos)
        ids{i} = feats(ord(pos(i))).case_id;
    end
end

function rows = build_stage_row(candidate_index, candidate, ev)
    rows = struct();
    rows.candidate_index = candidate_index;
    rows.candidate_id = candidate.id;
    rows.origin = candidate.origin;
    rows.config = candidate.cfg;
    rows.objective_score = ev.objective_score;
    rows.pass = ev.pass;
    rows.pass_flags = ev.pass_flags;
    rows.summary = ev.summary;
    rows.median_runtime_fast_s = get_struct_numeric(ev.summary, 'median_runtime_fast_s', NaN);
    rows.median_runtime_standard_s = get_struct_numeric(ev.summary, 'median_runtime_standard_s', NaN);
    rows.median_loss_error_standard_pct = get_struct_numeric(ev.summary, 'median_loss_error_standard_pct', NaN);
    rows.max_fast_loss_err_pct = get_struct_numeric(ev.summary, 'max_fast_loss_err_pct', NaN);
    rows.warning_fraction = get_struct_numeric(ev.summary, 'warning_fraction', NaN);
end

function idx = find_candidate_indices(candidates, ids)
    idx = [];
    for i = 1:numel(candidates)
        if any(strcmp(candidates(i).id, ids))
            idx(end+1) = i; %#ok<AGROW>
        end
    end
end

function out = sanitize_options_for_report(options)
    out = options;
end

function write_json(payload, out_file)
    fid = fopen(out_file, 'w');
    if fid == -1
        error('tune_solver_hyperband: cannot write %s', out_file);
    end
    fwrite(fid, jsonencode(payload));
    fclose(fid);
end

function seed_rng(seed)
    try
        rng(double(seed), 'twister');
    catch
        rand('seed', double(seed)); %#ok<RAND>
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
