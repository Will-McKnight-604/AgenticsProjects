% diagnose_solver_issue.m
% Diagnose what's wrong with peec_solve_frequency

clear; clc;

fprintf('=== DIAGNOSING SOLVER ISSUE ===\n\n');

%% Step 1: Build simple geometry
fprintf('Step 1: Building geometry...\n');

sigma = 5.8e7;
mu0 = 4*pi*1e-7;

conductors = [
    0, 0,      2e-3, 1e-3, 1, 0;
    0, 1.2e-3, 2e-3, 1e-3, 1, 0;
];

winding_map = [1; 1];

try
    geom = peec_build_geometry(conductors, sigma, mu0, 4, 4, winding_map);
    fprintf('  ✓ Geometry built successfully\n');
    fprintf('  Filaments: %d\n', geom.Nf);
    fprintf('  Conductors: %d\n', geom.Nc);
    fprintf('  Filament array size: %d x %d\n', size(geom.filaments,1), size(geom.filaments,2));
catch err
    fprintf('  ✗ ERROR building geometry:\n');
    fprintf('    %s\n', err.message);
    return;
end

%% Step 2: Check geometry structure
fprintf('\nStep 2: Checking geometry structure...\n');

required_fields = {'filaments', 'Nf', 'Nc', 'R', 'L', 'C'};
all_ok = true;

for i = 1:length(required_fields)
    if isfield(geom, required_fields{i})
        fprintf('  ✓ %s exists\n', required_fields{i});
    else
        fprintf('  ✗ %s MISSING!\n', required_fields{i});
        all_ok = false;
    end
end

if ~all_ok
    fprintf('\n✗ Geometry structure incomplete. Cannot proceed.\n');
    return;
end

%% Step 3: Try to call solver
fprintf('\nStep 3: Calling solver...\n');
f = 100e3;

fprintf('  Function call: peec_solve_frequency(geom, conductors, %.0f, %.2e, %.2e)\n', ...
    f, sigma, mu0);

try
    % Check if function exists
    if ~exist('peec_solve_frequency', 'file')
        error('peec_solve_frequency.m not found in path');
    end

    fprintf('  Executing...\n');
    results = peec_solve_frequency(geom, conductors, f, sigma, mu0);

    fprintf('  ✓ Solver executed\n');

catch err
    fprintf('  ✗ ERROR in solver:\n');
    fprintf('    Message: %s\n', err.message);
    fprintf('    Line: %s\n', err.stack(1).name);
    if length(err.stack) > 0
        fprintf('    File: %s, Line %d\n', err.stack(1).file, err.stack(1).line);
    end

    % Try to identify the issue
    fprintf('\n  Debugging info:\n');
    fprintf('    geom is a: %s\n', class(geom));
    fprintf('    conductors is a: %s\n', class(conductors));
    fprintf('    f is a: %s\n', class(f));
    fprintf('    sigma is a: %s\n', class(sigma));
    fprintf('    mu0 is a: %s\n', class(mu0));

    return;
end

%% Step 4: Check results structure
fprintf('\nStep 4: Checking results...\n');

fprintf('  results is a: %s\n', class(results));

if isstruct(results)
    fprintf('  ✓ Results is a structure\n');

    result_fields = fieldnames(results);
    fprintf('  Fields in results:\n');
    for i = 1:length(result_fields)
        fprintf('    - %s\n', result_fields{i});
    end

    % Check critical fields
    if isfield(results, 'P_total')
        fprintf('  Total loss: %.6f W\n', results.P_total);
    else
        fprintf('  ✗ P_total field missing!\n');
    end

else
    fprintf('  ✗ Results is NOT a structure!\n');
    fprintf('  This is the problem - solver should return a struct\n');
    return;
end

%% Step 5: Try to access results.P_total
fprintf('\nStep 5: Accessing results.P_total...\n');

try
    loss = results.P_total;
    fprintf('  ✓ Successfully accessed: %.6f W\n', loss);
catch err
    fprintf('  ✗ ERROR accessing results.P_total:\n');
    fprintf('    %s\n', err.message);
    return;
end

fprintf('\n=== ALL CHECKS PASSED ===\n');
fprintf('The solver is working correctly!\n');
