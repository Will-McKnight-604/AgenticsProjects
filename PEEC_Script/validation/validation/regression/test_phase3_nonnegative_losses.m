function ok = test_phase3_nonnegative_losses()
%TEST_PHASE3_NONNEGATIVE_LOSSES Ensure solver reports nonnegative losses.

    here = fileparts(mfilename('fullpath'));
    val_dir = fileparts(here);
    root = fileparts(val_dir);
    addpath(root);

    sigma = 5.8e7;
    mu0 = 4 * pi * 1e-7;
    conductors = [ ...
        0.0e-3, 0.0e-3, 0.6e-3, 0.2e-3, 2.0, 0.0; ...
        0.9e-3, 0.0e-3, 0.6e-3, 0.2e-3, 2.0, 180.0 ...
    ];
    opts = struct('enable_exact_rect_kernel', true, 'enable_surface_impedance_auto', true);
    geom = peec_build_geometry(conductors, sigma, mu0, 5, 5, [1; 2], {'round'; 'round'}, opts);
    res = peec_solve_frequency(geom, conductors, 250e3, sigma, mu0, opts);

    assert(all(real(res.P_fil) >= -1e-12), 'Negative filament losses found');
    assert(real(res.P_total) >= -1e-12, 'Negative total loss found');

    ok = true;
    fprintf('[PASS] test_phase3_nonnegative_losses\n');
end
