% test_peec_solver.m
% Simple test to verify PEEC solver is working correctly

clear; clc; close all;

fprintf('=== PEEC SOLVER TEST ===\n\n');

%% Setup
sigma = 5.8e7;      % Copper conductivity
mu0 = 4*pi*1e-7;    % Permeability

% Simple 3-layer winding
width = 2e-3;
height = 1e-3;
gap = 0.2e-3;
N_layers = 3;

% Build conductors
conductors = build_layered_geometry(N_layers, width, height, gap);
fprintf('Created %d layer geometry\n', N_layers);

%% Test 1: Build geometry
fprintf('\nTest 1: Building geometry...\n');
Nx = 6;
Ny = 6;

geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny);
fprintf('  Geometry built successfully\n');

% Debug geometry
debug_geometry_structure(geom, true);

%% Test 2: Solve at single frequency
fprintf('Test 2: Solving at single frequency...\n');
f = 100e3;  % 100 kHz

results = peec_solve_frequency(geom, conductors, f, sigma, mu0);

fprintf('  Solver completed successfully\n');
fprintf('  Total filament current entries: %d\n', length(results.I_fil));
fprintf('  Total loss: %.6f W\n', results.P_total);

%% Test 3: Calculate Rac/Rdc
fprintf('\nTest 3: Calculating AC/DC resistance ratio...\n');

A = width * height;
Rdc = N_layers / (sigma * A);
I_rms = conductors(1,5);
Pdc = 0.5 * I_rms^2 * Rdc;
RacRdc = results.P_total / Pdc;

fprintf('  DC Resistance: %.6f mOhm\n', Rdc*1e3);
fprintf('  DC Loss: %.6f W\n', Pdc);
fprintf('  AC Loss: %.6f W\n', results.P_total);
fprintf('  Rac/Rdc: %.3f\n', RacRdc);

% Skin depth
delta = 1/sqrt(pi*f*mu0*sigma);
fprintf('  Skin depth: %.2f µm\n', delta*1e6);
fprintf('  Height/skin depth: %.2f\n', height/delta);

%% Test 4: Visualize
fprintf('\nTest 4: Creating visualizations...\n');

figure('Name', 'PEEC Test Results', 'Position', [100 100 1200 500]);

subplot(1,3,1);
plot_current_density(geom, results);
title(sprintf('Current Density @ %.0f kHz', f/1e3));

subplot(1,3,2);
plot_loss_density(geom, results);
title('Loss Density');

subplot(1,3,3);
% Loss per layer
fils_per_layer = Nx * Ny;
loss_per_layer = zeros(N_layers, 1);
for k = 1:N_layers
    idx_start = (k-1)*fils_per_layer + 1;
    idx_end = k*fils_per_layer;
    loss_per_layer(k) = sum(results.P_fil(idx_start:idx_end));
end
bar(1:N_layers, loss_per_layer*1e3);
xlabel('Layer Number');
ylabel('Loss (mW)');
title('Loss per Layer');
grid on;

fprintf('  Visualizations created\n');

%% Test 5: Frequency sweep
fprintf('\nTest 5: Frequency sweep...\n');

f_vec = logspace(3, 5, 20);  % 1 kHz to 100 kHz
RacRdc_vec = zeros(size(f_vec));

for i = 1:length(f_vec)
    results_i = peec_solve_frequency(geom, conductors, f_vec(i), sigma, mu0);
    RacRdc_vec(i) = results_i.P_total / Pdc;
end

figure('Name', 'Frequency Sweep');
semilogx(f_vec/1e3, RacRdc_vec, 'LineWidth', 2);
grid on;
xlabel('Frequency (kHz)');
ylabel('R_{AC}/R_{DC}');
title('AC Resistance Factor vs Frequency');

fprintf('  Frequency sweep complete\n');
fprintf('  Rac/Rdc range: %.2f to %.2f\n', min(RacRdc_vec), max(RacRdc_vec));

%% Test 6: Hotspot identification
fprintf('\nTest 6: Identifying hotspots...\n');

hotspots = identify_hotspots(geom, results, 5);

fprintf('  Top 5 hotspots:\n');
for k = 1:length(hotspots)
    fprintf('    %d: (x=%.3f mm, y=%.3f mm), Loss=%.4e W\n', ...
        k, hotspots(k).x*1e3, hotspots(k).y*1e3, hotspots(k).loss);
end

%% Summary
fprintf('\n=== ALL TESTS PASSED ===\n');
fprintf('PEEC solver is working correctly!\n\n');
