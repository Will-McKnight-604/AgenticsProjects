function ok = test_phase3_kernel_symmetry()
%TEST_PHASE3_KERNEL_SYMMETRY Check rectangular kernel symmetry and L matrix symmetry.

    here = fileparts(mfilename('fullpath'));
    val_dir = fileparts(here);
    root = fileparts(val_dir);
    addpath(root);
    addpath(fullfile(root, 'kernels'));

    mu0 = 4 * pi * 1e-7;
    opts = struct('near_singular_floor_m', 1e-12);

    fi = [0.0, 0.0, 0.4e-3, 0.2e-3];
    fj = [0.5e-3, 0.3e-3, 0.5e-3, 0.3e-3];
    Lij = partial_inductance_rect(fi, fj, mu0, opts);
    Lji = partial_inductance_rect(fj, fi, mu0, opts);
    assert(abs(Lij - Lji) <= 1e-12 * max(1, abs(Lij)), 'Kernel is not symmetric');

    conductors = [ ...
        0.0e-3, 0.0e-3, 0.6e-3, 0.3e-3, 2.0, 0.0; ...
        1.0e-3, 0.0e-3, 0.6e-3, 0.3e-3, 2.0, 180.0 ...
    ];
    solve_opts = struct('enable_exact_rect_kernel', true);
    geom = peec_build_geometry(conductors, 5.8e7, mu0, 4, 4, [1; 2], {'round'; 'round'}, solve_opts);
    asym = norm(geom.L - geom.L.', 'fro');
    assert(asym <= 1e-10 * max(1, norm(geom.L, 'fro')), 'L matrix is not symmetric');

    ok = true;
    fprintf('[PASS] test_phase3_kernel_symmetry\n');
end
