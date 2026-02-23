function ov = build_mode_overrides_from_tune_cfg(cfg)
%BUILD_MODE_OVERRIDES_FROM_TUNE_CFG Convert tuner config to benchmark overrides.
%
% Example:
%   ov = build_mode_overrides_from_tune_cfg(hb.best_config);
%   ab = run_real_ab_benchmark(1, [], struct('tuned_mode_overrides', ov));

    if nargin < 1 || ~isstruct(cfg)
        cfg = struct();
    end

    ov = struct();
    ov.fast = struct();
    ov.standard = struct();

    if isfield(cfg, 'fast_direct_guard_nf_max')
        ov.fast.fast_direct_guard_nf_max = cfg.fast_direct_guard_nf_max;
    end
    if isfield(cfg, 'standard_direct_guard_nf_max')
        ov.standard.standard_direct_guard_nf_max = cfg.standard_direct_guard_nf_max;
    end
    if isfield(cfg, 'iter_min_size_for_use')
        ov.fast.iter_min_size_for_use = cfg.iter_min_size_for_use;
        ov.standard.iter_min_size_for_use = cfg.iter_min_size_for_use;
    end
    if isfield(cfg, 'precond_drop_tol')
        ov.fast.precond_drop_tol = cfg.precond_drop_tol;
        ov.standard.precond_drop_tol = cfg.precond_drop_tol;
    end

    % Keep rollout conservative in tuned profile evaluation.
    ov.fast.linear_solver = 'auto';
    ov.fast.iter_backend = 'auto';
    ov.fast.enable_external_krylov = false;
    ov.standard.linear_solver = 'auto';
    ov.standard.iter_backend = 'auto';
    ov.standard.enable_external_krylov = false;
end
