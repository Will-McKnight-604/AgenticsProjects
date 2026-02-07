%run_proximity_visualization
%{
%% ================== run_proximity_visualization.m ==================
clear; clc; close all;

%% ================== USER INPUTS ==================
% Discretization
Nx = 10;       % filaments per conductor (x)
Ny = 10;       % filaments per conductor (y)

% Conductor geometry
width  = 2e-3;       % m
height = 1e-3;     % m
gap    = 0.2e-3;     % m

% Number of layers
N_layers = 3;

% Frequencies
f_single = 200e3;                  % Hz (for static plots)
f_sweep  = logspace(3,6,40);       % Hz (for slider/animation)

% Material
sigma = 5.8e7;     % Copper conductivity
mu0   = 4*pi*1e-7; % Permeability

%% ================== BUILD WINDING LAYOUTS ==================
% Layout A: basic layered geometry
conductors_A = build_layered_geometry(N_layers, width, height, gap);

% Layout B: offset to simulate interleaving
conductors_B = build_layered_geometry(N_layers, width, height, gap);
conductors_B(:,1) = conductors_B(:,1) + width + 0.1e-3;  % small x offset

% Build filament geometry (once per layout)
geom_A = peec_build_geometry(conductors_A, sigma, mu0, Nx, Ny);
geom_B = peec_build_geometry(conductors_B, sigma, mu0, Nx, Ny);


%% ================== VISUALIZATION 1: FREQUENCY SLIDER ==================
% Only layout A for interactive frequency visualization
visualize_frequency_slider(conductors_A, geom_A, f_sweep, sigma, mu0);


%% ================== VISUALIZATION 2: SIDE-BY-SIDE LAYOUT COMPARISON ==================
compare_windings(geom_A, conductors_A, geom_B, conductors_B, f_single, sigma, mu0);

%% ================== VISUALIZATION 3: ANIMATE CURRENT CROWDING ==================
%animate_frequency(conductors_A, geom_A, f_sweep, sigma, mu0);

%% ================== VISUALIZATION 4: AUTO IDENTIFY HOTSPOTS ==================
% Solve for one frequency to identify top 5 hotspots
results = peec_solve_frequency(geom_A, conductors_A, f_single, sigma, mu0);


hotspots = identify_hotspots(geom_A, results, 5);

disp('Top 5 loss hotspots (x, y, power per filament [W]):');
for k = 1:length(hotspots)
    fprintf('Hotspot %d: x = %.4e, y = %.4e, P = %.4e W\n', ...
        k, hotspots(k).x, hotspots(k).y, hotspots(k).loss);
end

% Optional: overlay hotspots on loss density figure
figure(); hold on;
for k = 1:length(hotspots)
    plot(hotspots(k).x, hotspots(k).y, 'rx', 'MarkerSize',12, 'LineWidth',2);
end
hold off;
title('Copper Loss Density with Hotspots Highlighted');

%}

%run_proximity_visualization

%% ================== run_proximity_visualization.m ==================
clear; clc; close all;

%% ================== USER INPUTS ==================
% Discretization
Nx = 10;       % filaments per conductor (x)
Ny = 10;       % filaments per conductor (y)

% Conductor geometry
width  = 2e-3;       % m
height = 1e-3;       % m
gap    = 0.2e-3;     % m

% Number of layers
N_layers = 3;

% Frequencies
f_single = 200e3;                  % Hz (for static plots)
f_sweep  = logspace(3,6,40);       % Hz (for slider/animation)

% Material
sigma = 5.8e7;     % Copper conductivity (S/m)
mu0   = 4*pi*1e-7; % Permeability (H/m)

%% ================== BUILD WINDING LAYOUTS ==================
% Layout A: basic layered geometry
conductors_A = build_layered_geometry(N_layers, width, height, gap);

% Layout B: offset to simulate interleaving
conductors_B = build_layered_geometry(N_layers, width, height, gap);
conductors_B(:,1) = conductors_B(:,1) + width + 0.1e-3;  % small x offset

% Build filament geometry (once per layout)
geom_A = peec_build_geometry(conductors_A, sigma, mu0, Nx, Ny);
geom_B = peec_build_geometry(conductors_B, sigma, mu0, Nx, Ny);


%% ================== SINGLE FREQUENCY ANALYSIS ==================
fprintf('\n=== ANALYZING WINDING LOSSES ===\n');

% Solve for Layout A
results_A = peec_solve_frequency(geom_A, conductors_A, f_single, sigma, mu0);

% Display per-winding loss summary
display_winding_losses(results_A, conductors_A, f_single);

% Plot winding analysis
plot_winding_analysis(results_A, f_single);


%% ================== FREQUENCY SWEEP: WINDING LOSS vs FREQUENCY ==================
fprintf('Running frequency sweep for per-winding loss analysis...\n');

Nf_sweep = length(f_sweep);
P_winding_vs_f = zeros(N_layers, Nf_sweep);
Fr_vs_f = zeros(N_layers, Nf_sweep);

for idx = 1:Nf_sweep
    res = peec_solve_frequency(geom_A, conductors_A, f_sweep(idx), sigma, mu0);
    P_winding_vs_f(:, idx) = res.P_winding;
    Fr_vs_f(:, idx) = res.Fr;

    if mod(idx, 10) == 0
        fprintf('  Progress: %d/%d frequencies\n', idx, Nf_sweep);
    end
end

% Plot winding loss vs frequency
figure('Name', 'Winding Loss vs Frequency', 'Position', [100 100 1200 400]);

subplot(1,2,1);
semilogx(f_sweep/1e3, P_winding_vs_f', 'LineWidth', 2);
xlabel('Frequency [kHz]');
ylabel('Power Loss [W]');
title('Per-Winding Loss vs Frequency');
grid on;
legend_str = cell(N_layers, 1);
for k = 1:N_layers
    legend_str{k} = sprintf('Winding %d', k);
end
legend(legend_str, 'Location', 'best');

subplot(1,2,2);
semilogx(f_sweep/1e3, Fr_vs_f', 'LineWidth', 2);
xlabel('Frequency [kHz]');
ylabel('F_r = R_{AC} / R_{DC}');
title('Proximity Factor vs Frequency');
grid on;
legend(legend_str, 'Location', 'best');


%% ================== VISUALIZATION 1: FREQUENCY SLIDER ==================
% Only layout A for interactive frequency visualization
visualize_frequency_slider(conductors_A, geom_A, f_sweep, sigma, mu0);


%% ================== VISUALIZATION 2: SIDE-BY-SIDE LAYOUT COMPARISON ==================
compare_windings(geom_A, conductors_A, geom_B, conductors_B, f_single, sigma, mu0);

% Compare winding losses between layouts
fprintf('\n=== LAYOUT COMPARISON ===\n');
results_B = peec_solve_frequency(geom_B, conductors_B, f_single, sigma, mu0);

fprintf('\nLayout A vs Layout B @ %.1f kHz:\n', f_single/1e3);
fprintf('%-10s %12s %12s %12s\n', 'Winding', 'P_A [W]', 'P_B [W]', 'Reduction');
fprintf('%-10s %12s %12s %12s\n', '-------', '-------', '-------', '---------');
for k = 1:N_layers
    reduction = 100 * (results_A.P_winding(k) - results_B.P_winding(k)) / results_A.P_winding(k);
    fprintf('%-10d %12.4f %12.4f %11.1f%%\n', ...
            k, results_A.P_winding(k), results_B.P_winding(k), reduction);
end
fprintf('%-10s %12.4f %12.4f %11.1f%%\n', ...
        'TOTAL', results_A.P_total, results_B.P_total, ...
        100*(results_A.P_total - results_B.P_total)/results_A.P_total);


%% ================== VISUALIZATION 4: AUTO IDENTIFY HOTSPOTS ==================
hotspots = identify_hotspots(geom_A, results_A, 5);

fprintf('\nTop 5 loss hotspots (x, y, power per filament [W]):\n');
for k = 1:length(hotspots)
    fprintf('Hotspot %d: x = %.4e m, y = %.4e m, P = %.4e W (Winding %d)\n', ...
        k, hotspots(k).x, hotspots(k).y, hotspots(k).loss, hotspots(k).conductor);
end
