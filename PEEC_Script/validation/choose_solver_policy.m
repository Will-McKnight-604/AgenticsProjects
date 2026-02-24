function [overrides, meta] = choose_solver_policy(case_feature, mode, tune_cfg, base_opts)
%CHOOSE_SOLVER_POLICY Case-aware policy selection for PEEC solver options.
%
% Example:
%   [ov, meta] = choose_solver_policy(feat, 'fast', cfg);

    if nargin < 2 || ~is_text_like(mode)
        mode = 'standard';
    end
    if nargin < 3 || ~isstruct(tune_cfg)
        tune_cfg = struct();
    end
    if nargin < 4 || ~isstruct(base_opts)
        base_opts = solver_option_profile(char(mode));
    end

    mode = lower(strtrim(char(mode)));
    nf_est = max(1, round(get_struct_numeric(case_feature, 'mesh_cells_est', NaN)));
    winding_count = max(1, round(get_struct_numeric(case_feature, 'winding_count', 1)));
    complexity = get_struct_numeric(case_feature, 'complexity_score', NaN);
    fft_hint = get_struct_bool(case_feature, 'fft_eligible_hint', false);

    fast_guard = max(1, round(get_cfg_num(tune_cfg, 'fast_direct_guard_nf_max', get_struct_numeric(base_opts, 'fast_direct_guard_nf_max', 2200))));
    std_guard = max(1, round(get_cfg_num(tune_cfg, 'standard_direct_guard_nf_max', get_struct_numeric(base_opts, 'standard_direct_guard_nf_max', 2600))));
    iter_min = max(1, round(get_cfg_num(tune_cfg, 'iter_min_size_for_use', get_struct_numeric(base_opts, 'iter_min_size_for_use', 2200))));
    drop_tol = max(1e-4, get_cfg_num(tune_cfg, 'precond_drop_tol', get_struct_numeric(base_opts, 'precond_drop_tol', 1e-2)));

    if ~isfinite(complexity)
        complexity = nf_est;
    end

    overrides = struct();
    overrides.enable_external_krylov = false;
    overrides.iter_backend = 'octave';

    decision = 'default';
    reason = 'none';

    switch mode
        case 'fast'
            % Use the smaller of mode guard and iter threshold so candidate
            % sweeps can actually change solver routing behavior.
            direct_gate = max(200, min(fast_guard, iter_min));
            single_winding_fragile = (winding_count <= 1) && (nf_est < 1800);
            force_direct = (nf_est <= direct_gate) || single_winding_fragile;
            if force_direct
                overrides.linear_solver = 'direct';
                overrides.matrix_mode = 'dense';
                overrides.interaction_backend = 'dense';
                overrides.preconditioner = 'none';
                decision = 'direct';
                reason = 'small_or_fragile_case';
            else
                % Explicit iterative selection prevents solver auto-thresholds
                % from silently routing back to direct.
                overrides.linear_solver = 'bicgstab';
                overrides.matrix_mode = 'dense';
                overrides.interaction_backend = 'dense';
                overrides.preconditioner = 'ilu_sparse_drop';
                overrides.precond_drop_tol = drop_tol;
                decision = 'iterative_dense';
                reason = 'large_case';
            end
            overrides.max_refine_iters = min(get_struct_numeric(base_opts, 'max_refine_iters', 2), 2);

        case 'standard'
            direct_gate = max(400, min(std_guard, iter_min));
            single_winding_fragile = (winding_count <= 1) && (nf_est < 2200);
            force_direct = (nf_est <= direct_gate) || single_winding_fragile;
            if force_direct
                overrides.linear_solver = 'direct';
                overrides.matrix_mode = 'dense';
                overrides.interaction_backend = 'dense';
                overrides.preconditioner = 'none';
                decision = 'direct';
                reason = 'small_or_fragile_case';
            else
                overrides.linear_solver = 'bicgstab';
                overrides.matrix_mode = 'dense';
                overrides.interaction_backend = 'dense';
                overrides.preconditioner = 'ilu_sparse_drop';
                overrides.precond_drop_tol = max(1e-3, min(drop_tol, 2e-2));
                decision = 'iterative_dense';
                reason = 'large_case';
            end
            overrides.max_refine_iters = min(get_struct_numeric(base_opts, 'max_refine_iters', 5), 4);

        otherwise
            overrides.linear_solver = 'direct';
            overrides.matrix_mode = 'dense';
            overrides.interaction_backend = 'dense';
            overrides.preconditioner = 'none';
            decision = 'direct_reference';
            reason = 'reference_mode';
    end

    % Allow FFT auto-routing only for large and FFT-hint-eligible cases.
    if fft_hint && (nf_est >= max(3000, iter_min))
        overrides.matrix_mode = 'auto';
        overrides.interaction_backend = 'auto';
        reason = [reason '+fft_auto_candidate'];
    end

    meta = struct();
    meta.mode = mode;
    meta.nf_est = nf_est;
    meta.winding_count = winding_count;
    meta.complexity_score = complexity;
    meta.fft_hint = fft_hint;
    meta.fast_guard_nf = fast_guard;
    meta.standard_guard_nf = std_guard;
    meta.iter_min_size = iter_min;
    meta.precond_drop_tol = drop_tol;
    meta.decision = decision;
    meta.reason = reason;
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
