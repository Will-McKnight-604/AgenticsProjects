% multifilar_comparison
.m
% Compare single, bi-filar, tri-filar, and quad-filar winding configurations

clear; clc; close all;

fprintf('=== MULTI-FILAR WINDING COMPARISON ===\n\n');

%% Common parameters
sigma = 5.8e7;      % Copper conductivity
mu0 = 4*pi*1e-7;    % Permeability

% Geometry
width = 1e-3;       % 1 mm conductor width
height = 1e-3;      % 1 mm conductor height
gap_layer = 0.2e-3; % 0.2 mm between layers
gap_filar = 0.1e-3; % 0.1 mm between filar conductors

% Winding specification
n_turns = 8;        % 8 turns total
I_total = 10;       % 10 A total current
phase = 0;          % 0 degrees

% Analysis
f = 100e3;          % 100 kHz
Nx = 6;
Ny = 6;

%% Configuration 1: Single conductor (standard)
fprintf('=== CONFIGURATION 1: SINGLE-FILAR ===\n');

config1.n_filar = 1;
config1.n_turns = n_turns;
config1.n_windings = 1;
config1.width = width;
config1.height = height;
config1.gap_layer = gap_layer;
config1.gap_filar = gap_filar;
config1.currents = I_total;
config1.phases = phase;
config1.x_offset = 0;

[conductors1, winding_map1] = build_multifilar_winding(config1);
geom1 = peec_build_geometry(conductors1, sigma, mu0, Nx, Ny, winding_map1);
results1 = peec_solve_frequency(geom1, conductors1, f, sigma, mu0);

fprintf('Total loss: %.6f W\n\n', results1.P_total);

%% Configuration 2: Bi-filar
fprintf('=== CONFIGURATION 2: BI-FILAR ===\n');

config2 = config1;
config2.n_filar = 2;

[conductors2, winding_map2] = build_multifilar_winding(config2);
geom2 = peec_build_geometry(conductors2, sigma, mu0, Nx, Ny, winding_map2);
results2 = peec_solve_frequency(geom2, conductors2, f, sigma, mu0);

fprintf('Total loss: %.6f W\n\n', results2.P_total);

%% Configuration 3: Tri-filar
fprintf('=== CONFIGURATION 3: TRI-FILAR ===\n');

config3 = config1;
config3.n_filar = 3;

[conductors3, winding_map3] = build_multifilar_winding(config3);
geom3 = peec_build_geometry(conductors3, sigma, mu0, Nx, Ny, winding_map3);
results3 = peec_solve_frequency(geom3, conductors3, f, sigma, mu0);

fprintf('Total loss: %.6f W\n\n', results3.P_total);

%% Configuration 4: Quad-filar
fprintf('=== CONFIGURATION 4: QUAD-FILAR ===\n');

config4 = config1;
config4.n_filar = 4;

[conductors4, winding_map4] = build_multifilar_winding(config4);
geom4 = peec_build_geometry(conductors4, sigma, mu0, Nx, Ny, winding_map4);
results4 = peec_solve_frequency(geom4, conductors4, f, sigma, mu0);

fprintf('Total loss: %.6f W\n\n', results4.P_total);

%% Visualize comparison
fprintf('Creating comparison visualizations...\n');

figure('Name', 'Multi-filar Comparison', 'Position', [50 50 1600 1000]);

% Add main title
annotation('textbox', [0 0.96 1 0.04], ...
    'String', sprintf('Multi-filar Winding Comparison @ %.0f kHz', f/1e3), ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
    'FontSize', 14, 'FontWeight', 'bold');

configs = {geom1, geom2, geom3, geom4};
results_all = {results1, results2, results3, results4};
titles = {'Single-filar', 'Bi-filar', 'Tri-filar', 'Quad-filar'};

for i = 1:4
    % Current density
    subplot(4, 3, (i-1)*3 + 1);
    plot_current_density(configs{i}, results_all{i});
    ylabel(titles{i}, 'FontWeight', 'bold');
    if i == 1
        title('Current Density');
    end

    % Loss density
    subplot(4, 3, (i-1)*3 + 2);
    plot_loss_density(configs{i}, results_all{i});
    if i == 1
        title('Loss Density');
    end

    % Loss per turn
    subplot(4, 3, (i-1)*3 + 3);
    n_filar = i;  % 1, 2, 3, 4
    fils_per_conductor = Nx * Ny;

    loss_per_turn = zeros(n_turns, 1);
    for turn = 1:n_turns
        % Each turn has n_filar conductors
        for filar = 1:n_filar
            cond_idx = (turn-1)*n_filar + filar;
            idx_start = (cond_idx-1) * fils_per_conductor + 1;
            idx_end = cond_idx * fils_per_conductor;
            loss_per_turn(turn) = loss_per_turn(turn) + sum(results_all{i}.P_fil(idx_start:idx_end));
        end
    end

    bar(1:n_turns, loss_per_turn*1e3);
    ylabel('Loss (mW)');
    grid on;

    if i == 1
        title('Loss per Turn');
    end
    if i == 4
        xlabel('Turn Number');
    end
end

%% Summary comparison
fprintf('\n=== SUMMARY ===\n');
fprintf('Configuration    Total Loss (W)    Reduction    Rac/Rdc\n');
fprintf('--------------------------------------------------------\n');

% Calculate DC loss for reference
A_total = width * height * n_turns;  % Total copper area (same for all)
Rdc = 1 / (sigma * A_total);
Pdc = 0.5 * I_total^2 * Rdc;

losses = [results1.P_total, results2.P_total, results3.P_total, results4.P_total];

for i = 1:4
    reduction = (1 - losses(i)/losses(1)) * 100;
    rac_rdc = losses(i) / Pdc;

    fprintf('%-16s %.6f W      %+5.1f%%      %.2f\n', ...
        titles{i}, losses(i), reduction, rac_rdc);
end

%% Create summary bar chart
figure('Name', 'Loss Comparison');

subplot(1,2,1);
bar(losses * 1e3);
set(gca, 'XTickLabel', titles);
ylabel('Total Loss (mW)');
title('Total Loss Comparison');
grid on;

subplot(1,2,2);
reduction_pct = (1 - losses/losses(1)) * 100;
bar(reduction_pct);
set(gca, 'XTickLabel', titles);
ylabel('Loss Reduction (%)');
title('Improvement vs Single-filar');
grid on;
ylim([min(reduction_pct)-5, max(reduction_pct)+5]);

fprintf('\n=== ANALYSIS COMPLETE ===\n');
