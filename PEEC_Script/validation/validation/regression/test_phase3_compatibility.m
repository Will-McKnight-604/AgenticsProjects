function ok = test_phase3_compatibility()
%TEST_PHASE3_COMPATIBILITY Verify legacy call paths still execute.

    here = fileparts(mfilename('fullpath'));
    val_dir = fileparts(here);
    root = fileparts(val_dir);
    addpath(root);

    sigma = 5.8e7;
    mu0 = 4 * pi * 1e-7;
    conductors = [ ...
        0.0e-3, 0.0e-3, 0.5e-3, 0.2e-3, 2.5, 0.0; ...
        0.8e-3, 0.0e-3, 0.5e-3, 0.2e-3, 2.5, 180.0 ...
    ];

    % Legacy peec_build_geometry signature without solve options.
    geom = peec_build_geometry(conductors, sigma, mu0, 4, 4);
    assert(isfield(geom, 'L') && isfield(geom, 'R') && isfield(geom, 'C'), ...
        'Geometry missing expected legacy fields');

    % Legacy peec_solve_frequency signature without solve options.
    res = peec_solve_frequency(geom, conductors, 100e3, sigma, mu0);
    assert(isfield(res, 'P_total') && isfield(res, 'P_fil'), ...
        'Solver result missing expected legacy fields');

    core_params = struct('Ae', 50e-6, 'le', 60e-3, 'Ve', 3e-6, ...
                         'bobbin_w', 10e-3, 'bobbin_h', 8e-3);
    mp = compute_winding_inductance_matrix(geom, 75e-3, core_params, 2200, {});
    assert(isfield(mp, 'Lm') && isfield(mp, 'Llk_pri') && isfield(mp, 'Llk_sec'), ...
        'Magnetic extraction missing expected fields');

    ok = true;
    fprintf('[PASS] test_phase3_compatibility\n');
end
