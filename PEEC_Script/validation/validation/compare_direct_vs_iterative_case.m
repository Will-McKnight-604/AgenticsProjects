function report = compare_direct_vs_iterative_case(case_input, options)
%COMPARE_DIRECT_VS_ITERATIVE_CASE Fair A/B on one case: direct vs iterative.
%
% The comparison forces both runs through the same case path, disables LU cache,
% and clears persistent caches before every run.
%
% Example:
%   case_file = fullfile(pwd,'validation','mas_cases_real','real_case_03_tsf_case_03.json');
%   opts = struct('repeats', 3, 'mode', 'fast', 'iterative_solver', 'bicgstab');
%   report = compare_direct_vs_iterative_case(case_file, opts);

    ensure_local_paths();

    if nargin < 1 || isempty(case_input)
        case_input = fullfile(fileparts(mfilename('fullpath')), 'mas_cases_real', 'real_case_03_tsf_case_03.json');
    end
    if nargin < 2 || ~isstruct(options)
        options = struct();
    end

    options = normalize_options(options);
    case_path = resolve_case_path(case_input);

    direct_opts = build_direct_options(options);
    iter_opts = build_iterative_options(options);

    direct_runs = repmat(empty_run(), options.repeats, 1);
    iter_runs = repmat(empty_run(), options.repeats, 1);

    for k = 1:options.repeats
        clear_phase3_runtime_caches();
        d = execute_mas_case(case_path, direct_opts);
        direct_runs(k) = summarize_run(d);

        clear_phase3_runtime_caches();
        it = execute_mas_case(case_path, iter_opts);
        iter_runs(k) = summarize_run(it);
    end

    d_rt = [direct_runs.runtime_s];
    i_rt = [iter_runs.runtime_s];
    d_med = median_no_nan(d_rt);
    i_med = median_no_nan(i_rt);

    ref = pick_reference_run(direct_runs);
    cand = pick_reference_run(iter_runs);

    err = struct();
    err.loss_rel_pct = 100 * rel_err(cand.total_copper_loss_w, ref.total_copper_loss_w);
    err.lm_rel_pct = 100 * rel_err(cand.Lm_h, ref.Lm_h);
    err.llk_pri_rel_pct = 100 * rel_err(cand.Llk_pri_h, ref.Llk_pri_h);
    err.llk_sec_rel_pct = 100 * rel_err(cand.Llk_sec_h, ref.Llk_sec_h);

    report = struct();
    report.generated_at = datestr(now, 30);
    report.case_path = case_path;
    report.case_id = ref.case_id;
    report.repeats = options.repeats;
    report.direct_options = direct_opts;
    report.iterative_options = iter_opts;
    report.direct_runs = direct_runs;
    report.iterative_runs = iter_runs;
    report.summary = struct();
    report.summary.direct_runtime_median_s = d_med;
    report.summary.iterative_runtime_median_s = i_med;
    report.summary.iterative_over_direct_ratio = safe_ratio(i_med, d_med);
    report.summary.direct_over_iterative_speedup = safe_ratio(d_med, i_med);
    report.summary.iterative_faster = logical(i_med < d_med);
    report.summary.accuracy_vs_direct = err;

    print_summary(report);
end

function out = normalize_options(in)
    out = in;
    out.repeats = max(1, round(get_num(in, 'repeats', 3)));
    out.mode = lower(strtrim(get_str(in, 'mode', 'fast')));
    if isempty(out.mode)
        out.mode = 'fast';
    end

    out.iterative_solver = lower(strtrim(get_str(in, 'iterative_solver', 'bicgstab')));
    if ~any(strcmp(out.iterative_solver, {'gmres', 'bicgstab'}))
        out.iterative_solver = 'bicgstab';
    end
    out.matrix_mode = lower(strtrim(get_str(in, 'matrix_mode', 'dense')));
    if ~any(strcmp(out.matrix_mode, {'dense', 'matrix_free'}))
        out.matrix_mode = 'dense';
    end
    out.interaction_backend = lower(strtrim(get_str(in, 'interaction_backend', 'dense')));
    if ~any(strcmp(out.interaction_backend, {'dense', 'fft', 'fmm'}))
        out.interaction_backend = 'dense';
    end

    out.iter_tol = get_num(in, 'iter_tol', 1e-2);
    out.iter_maxit = max(1, round(get_num(in, 'iter_maxit', 300)));
    out.iter_restart = max(1, round(get_num(in, 'iter_restart', 40)));
    out.preconditioner = get_str(in, 'preconditioner', 'ilu_sparse_drop');
    out.precond_drop_tol = get_num(in, 'precond_drop_tol', 1e-2);
    out.iter_backend = lower(strtrim(get_str(in, 'iter_backend', 'auto')));
    if ~any(strcmp(out.iter_backend, {'auto', 'octave', 'external'}))
        out.iter_backend = 'auto';
    end
    out.enable_external_krylov = logical(get_num(in, 'enable_external_krylov', 0));
    out.external_backend_min_nf = max(1, round(get_num(in, 'external_backend_min_nf', 1800)));
    out.external_backend_allow_matrix_free = logical(get_num(in, 'external_backend_allow_matrix_free', 0));
    out.iter_external_solver_name = get_str(in, 'iter_external_solver_name', '');
end

function opts = build_direct_options(options)
    opts = solver_option_profile(options.mode);
    opts.enable_solver_cache = false;
    opts.enable_iter_precond_cache = false;
    opts.enable_adaptive_meshing = false;
    opts.max_refine_iters = 1;
    opts.linear_solver = 'direct';
    opts.matrix_mode = 'dense';
    opts.interaction_backend = 'dense';
end

function opts = build_iterative_options(options)
    opts = solver_option_profile(options.mode);
    opts.enable_solver_cache = false;
    opts.enable_iter_precond_cache = false;
    opts.enable_adaptive_meshing = false;
    opts.max_refine_iters = 1;
    opts.linear_solver = options.iterative_solver;
    opts.matrix_mode = options.matrix_mode;
    opts.interaction_backend = options.interaction_backend;
    opts.iter_tol = options.iter_tol;
    opts.iter_maxit = options.iter_maxit;
    opts.iter_restart = options.iter_restart;
    opts.preconditioner = options.preconditioner;
    opts.precond_drop_tol = options.precond_drop_tol;
    opts.iter_backend = options.iter_backend;
    opts.enable_external_krylov = options.enable_external_krylov;
    opts.external_backend_min_nf = options.external_backend_min_nf;
    opts.external_backend_allow_matrix_free = options.external_backend_allow_matrix_free;
    opts.iter_external_solver_name = options.iter_external_solver_name;
end

function p = resolve_case_path(case_input)
    if ischar(case_input)
        p = case_input;
    elseif (exist('isstring', 'builtin') || exist('isstring', 'file')) && isstring(case_input)
        p = char(case_input);
    else
        error('compare_direct_vs_iterative_case: case_input must be a case file path');
    end
    if exist(p, 'file') ~= 2
        error('compare_direct_vs_iterative_case: case file not found: %s', p);
    end
end

function r = summarize_run(raw)
    r = empty_run();
    r.case_id = get_str(raw, 'case_id', 'unknown_case');
    r.runtime_s = get_num(raw, 'runtime_s', NaN);
    r.total_copper_loss_w = get_num(raw, 'total_copper_loss_w', NaN);
    r.Lm_h = get_num(raw, 'Lm_h', NaN);
    r.Llk_pri_h = get_num(raw, 'Llk_pri_h', NaN);
    r.Llk_sec_h = get_num(raw, 'Llk_sec_h', NaN);
    r.linear_solver_used = get_str(raw, 'linear_solver_used', 'unknown');
    r.preconditioner_used = get_str(raw, 'preconditioner_used', 'none');
    r.matrix_mode_used = get_str(raw, 'matrix_mode_used', 'unknown');
    r.interaction_backend_used = get_str(raw, 'interaction_backend_used', 'unknown');
    r.iter_count = get_num(raw, 'iter_count', NaN);
    r.iter_relres = get_num(raw, 'iter_relres', NaN);
    if isfield(raw, 'solve_meta') && isstruct(raw.solve_meta)
        r.stop_reason = get_str(raw.solve_meta, 'stop_reason', 'unknown');
        r.fallback_to_direct = logical(get_num(raw.solve_meta, 'fallback_to_direct', 0));
    end
end

function r = empty_run()
    r = struct();
    r.case_id = '';
    r.runtime_s = NaN;
    r.total_copper_loss_w = NaN;
    r.Lm_h = NaN;
    r.Llk_pri_h = NaN;
    r.Llk_sec_h = NaN;
    r.linear_solver_used = 'unknown';
    r.preconditioner_used = 'none';
    r.matrix_mode_used = 'unknown';
    r.interaction_backend_used = 'unknown';
    r.iter_count = NaN;
    r.iter_relres = NaN;
    r.stop_reason = 'unknown';
    r.fallback_to_direct = false;
end

function r = pick_reference_run(runs)
    r = runs(1);
    rt = [runs.runtime_s];
    [~, idx] = min(abs(rt - median_no_nan(rt)));
    if ~isempty(idx) && idx >= 1 && idx <= numel(runs)
        r = runs(idx);
    end
end

function e = rel_err(v, ref)
    e = NaN;
    if ~isfinite(v) || ~isfinite(ref)
        return;
    end
    e = abs(v - ref) / max(abs(ref), 1e-12);
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

function print_summary(report)
    s = report.summary;
    a = s.accuracy_vs_direct;
    fprintf('[AB] Case: %s\n', report.case_id);
    fprintf('[AB] Median runtime direct: %.4f s | iterative: %.4f s | direct/iterative speedup: %.3fx\n', ...
        s.direct_runtime_median_s, s.iterative_runtime_median_s, s.direct_over_iterative_speedup);
    fprintf('[AB] Accuracy vs direct (%%): loss=%.4f | Lm=%.4f | Llk_pri=%.4f | Llk_sec=%.4f\n', ...
        a.loss_rel_pct, a.lm_rel_pct, a.llk_pri_rel_pct, a.llk_sec_rel_pct);
end

function out = get_num(s, field_name, default_val)
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

function out = get_str(s, field_name, default_val)
    out = default_val;
    if ~isstruct(s) || ~isfield(s, field_name)
        return;
    end
    v = s.(field_name);
    if ischar(v)
        out = char(v);
        return;
    end
    if (exist('isstring', 'builtin') || exist('isstring', 'file')) && isstring(v)
        out = char(v);
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
