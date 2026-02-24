function ok = test_phase3_cap_behavior()
%TEST_PHASE3_CAP_BEHAVIOR Verify runtime-cap stop path in adaptive meshing.

    here = fileparts(mfilename('fullpath'));
    val_dir = fileparts(here);
    root = fileparts(val_dir);
    addpath(root);
    addpath(fullfile(root, 'mesh'));
    addpath(val_dir);

    data = struct();
    data.sigma = 5.8e7;
    data.mu0 = 4 * pi * 1e-7;
    data.f = 300e3;
    data.Nx = 4;
    data.Ny = 4;

    conductors = [ ...
        0.0e-3, 0.0e-3, 0.5e-3, 0.2e-3, 3.0, 0.0; ...
        0.9e-3, 0.0e-3, 0.5e-3, 0.2e-3, 3.0, 180.0 ...
    ];
    winding_map = [1; 2];
    wire_shapes = {'round'; 'round'};

    opts = solver_option_profile('standard');
    opts.runtime_cap_s = 1e-4;
    opts.max_refine_iters = 8;
    opts.max_mesh_Nx = 20;
    opts.max_mesh_Ny = 20;
    opts.enable_adaptive_meshing = true;

    [geom, meta] = adaptive_refine(data, conductors, winding_map, wire_shapes, opts); %#ok<ASGLU>

    assert(isfield(meta, 'stop_reason'), 'Meta missing stop_reason');
    assert(~isempty(meta.stop_reason), 'stop_reason empty');
    assert(isfield(meta, 'converged'), 'Meta missing converged');
    assert(isfield(meta, 'uncertainty_pct'), 'Meta missing uncertainty_pct');

    ok = true;
    fprintf('[PASS] test_phase3_cap_behavior (stop_reason=%s)\n', meta.stop_reason);
end
