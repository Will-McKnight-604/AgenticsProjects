% minimal_test.m - Absolute minimal test case

clear; clc;

fprintf('=== MINIMAL TEST ===\n\n');

% Setup
sigma = 5.8e7;
mu0 = 4*pi*1e-7;

% Single conductor
conductors = [0, 0, 2e-3, 1e-3, 1, 0];

fprintf('Building geometry...\n');
geom = peec_build_geometry(conductors, sigma, mu0, 3, 3);

fprintf('Geometry OK: %d filaments\n', geom.Nf);
fprintf('Filament array: %d x %d\n', size(geom.filaments));

fprintf('\nCalling solver...\n');
fprintf('  Before solver call, geom is: %s\n', class(geom));

% The actual call
f = 100e3;
output = peec_solve_frequency(geom, conductors, f, sigma, mu0);

fprintf('  After solver call, output is: %s\n', class(output));

if isstruct(output)
    fprintf('  ✓ Output is a struct\n');
    fprintf('  Fields: %s\n', strjoin(fieldnames(output), ', '));

    if isfield(output, 'P_total')
        fprintf('  Loss = %.6f W\n', output.P_total);
        fprintf('\n✓ SUCCESS!\n');
    else
        fprintf('  ✗ No P_total field\n');
    end
else
    fprintf('  ✗ Output is NOT a struct: %s\n', class(output));
    fprintf('  Output value: ');
    disp(output);
end
