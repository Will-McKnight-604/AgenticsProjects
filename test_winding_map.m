% test_winding_map.m
% Test if winding_map causes issues

clear; clc;

fprintf('=== TESTING WINDING MAP ===\n\n');

sigma = 5.8e7;
mu0 = 4*pi*1e-7;
Nx = 4;
Ny = 4;
f = 100e3;

%% Test 1: Single winding (no winding_map)
fprintf('Test 1: Single winding (no winding_map argument)\n');

conductors1 = [
    0, 0,      2e-3, 1e-3, 1, 0;
    0, 1.2e-3, 2e-3, 1e-3, 1, 0;
];

geom1 = peec_build_geometry(conductors1, sigma, mu0, Nx, Ny);
fprintf('  Geometry: %d filaments, array size %dx%d\n', ...
    geom1.Nf, size(geom1.filaments,1), size(geom1.filaments,2));

results1 = peec_solve_frequency(geom1, conductors1, f, sigma, mu0);
fprintf('  Results type: %s\n', class(results1));
fprintf('  Loss: %.6f W\n', results1.P_total);
fprintf('  ✓ Test 1 passed\n\n');

%% Test 2: With explicit winding_map (single winding)
fprintf('Test 2: With winding_map = [1; 1]\n');

winding_map2 = [1; 1];

geom2 = peec_build_geometry(conductors1, sigma, mu0, Nx, Ny, winding_map2);
fprintf('  Geometry: %d filaments, array size %dx%d\n', ...
    geom2.Nf, size(geom2.filaments,1), size(geom2.filaments,2));

results2 = peec_solve_frequency(geom2, conductors1, f, sigma, mu0);
fprintf('  Results type: %s\n', class(results2));
fprintf('  Loss: %.6f W\n', results2.P_total);
fprintf('  ✓ Test 2 passed\n\n');

%% Test 3: Two windings
fprintf('Test 3: Two windings with winding_map = [1; 1; 2; 2]\n');

conductors3 = [
    0,    0,      2e-3, 1e-3, 10, 0;
    0,    1.2e-3, 2e-3, 1e-3, 10, 0;
    3e-3, 0,      2e-3, 1e-3, 5,  180;
    3e-3, 1.2e-3, 2e-3, 1e-3, 5,  180;
];

winding_map3 = [1; 1; 2; 2];

geom3 = peec_build_geometry(conductors3, sigma, mu0, Nx, Ny, winding_map3);
fprintf('  Geometry: %d filaments, array size %dx%d\n', ...
    geom3.Nf, size(geom3.filaments,1), size(geom3.filaments,2));

fprintf('  Calling solver...\n');
results3 = peec_solve_frequency(geom3, conductors3, f, sigma, mu0);
fprintf('  Results type: %s\n', class(results3));

if isstruct(results3)
    fprintf('  Loss: %.6f W\n', results3.P_total);
    fprintf('  ✓ Test 3 passed\n\n');
else
    fprintf('  ✗ Results is not a struct!\n');
    fprintf('  Results = ');
    disp(results3);
end

fprintf('=== ALL TESTS PASSED ===\n');
