function ok = test_phase3_solver_options()
%TEST_PHASE3_SOLVER_OPTIONS Verify mode presets and required fields.

    here = fileparts(mfilename('fullpath'));
    val_dir = fileparts(here);
    addpath(val_dir);

    req_fields = { ...
        'mode', 'target_rel_error_loss', 'target_rel_error_llk', ...
        'runtime_cap_s', 'max_refine_iters', 'cap_behavior', ...
        'enable_surface_impedance_auto', 'enable_exact_rect_kernel', ...
        'enable_end_turn_correction' ...
    };

    modes = {'fast', 'standard', 'high', 'compatibility'};
    for i = 1:numel(modes)
        opts = solver_option_profile(modes{i});
        for k = 1:numel(req_fields)
            assert(isfield(opts, req_fields{k}), ...
                'Missing required solve option field: %s', req_fields{k});
        end
    end

    fast = solver_option_profile('fast');
    std = solver_option_profile('standard');
    high = solver_option_profile('high');

    assert(fast.runtime_cap_s <= std.runtime_cap_s, 'Fast runtime cap should be <= standard');
    assert(high.runtime_cap_s >= std.runtime_cap_s, 'High runtime cap should be >= standard');
    assert(fast.target_rel_error_loss >= std.target_rel_error_loss, 'Fast target error should be >= standard');
    assert(high.target_rel_error_loss <= std.target_rel_error_loss, 'High target error should be <= standard');
    compat = solver_option_profile('compatibility');
    assert(~compat.enable_adaptive_meshing, 'Compatibility mode should disable adaptive meshing');
    assert(~compat.enable_exact_rect_kernel, 'Compatibility mode should disable exact kernel');
    assert(~compat.enable_end_turn_correction, 'Compatibility mode should disable end-turn correction');

    ok = true;
    fprintf('[PASS] test_phase3_solver_options\n');
end
