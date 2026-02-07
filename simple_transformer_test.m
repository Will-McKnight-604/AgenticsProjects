% simple_transformer_test.m
% Simple test for multi-winding transformer geometry

clear; clc; close all;

fprintf('=== SIMPLE TRANSFORMER TEST ===\n\n');

%% Configuration
sigma = 5.8e7;      % Copper conductivity
mu0 = 4*pi*1e-7;    % Permeability

% Conductor geometry
width = 2e-3;
height = 1e-3;
gap = 0.2e-3;

% Winding 1: 4 turns (2 layers × 2 turns/layer)
N1 = 4;
I1 = 10;  % Arms
phase1 = 0;

% Winding 2: 8 turns (2 layers × 4 turns/layer)
N2 = 8;
I2 = 5;  % Arms
phase2 = 180;

%% Build conductor array
fprintf('Building transformer geometry...\n');

conductors = [];
winding_map = [];

% Winding 1 conductors
for i = 1:N1
    y_pos = (i-1) * (height + gap);
    conductors = [conductors; 0, y_pos, width, height, I1, phase1];
    winding_map = [winding_map; 1];  % Belongs to winding 1
end

% Winding 2 conductors (offset in x)
x_offset = width + 1e-3;  % 1mm gap between windings
for i = 1:N2
    y_pos = (i-1) * (height + gap);
    conductors = [conductors; x_offset, y_pos, width, height, I2, phase2];
    winding_map = [winding_map; 2];  % Belongs to winding 2
end

fprintf('  Total conductors (turns): %d\n', size(conductors,1));
fprintf('  Winding 1: %d turns @ %.1f A, %.0f°\n', N1, I1, phase1);
fprintf('  Winding 2: %d turns @ %.1f A, %.0f°\n', N2, I2, phase2);

%% Build geometry with winding map
Nx = 6;
Ny = 6;

fprintf('\nBuilding PEEC geometry...\n');
geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny, winding_map);

fprintf('  Filaments per conductor: %d × %d = %d\n', Nx, Ny, Nx*Ny);
fprintf('  Total filaments: %d\n', geom.Nf);
fprintf('  Filament array columns: %d\n', size(geom.filaments, 2));

%% Solve at one frequency
f = 100e3;  % 100 kHz
fprintf('\nSolving at f = %.0f kHz...\n', f/1e3);

results = peec_solve_frequency(geom, conductors, f, sigma, mu0);

fprintf('  Total loss: %.6f W\n', results.P_total);

%% Calculate per-winding losses
fils_per_conductor = Nx * Ny;

% Winding 1 loss
loss_w1 = 0;
for turn = 1:N1
    idx_start = (turn-1) * fils_per_conductor + 1;
    idx_end = turn * fils_per_conductor;
    loss_w1 = loss_w1 + sum(results.P_fil(idx_start:idx_end));
end

% Winding 2 loss
loss_w2 = 0;
for turn = 1:N2
    idx_start = N1*fils_per_conductor + (turn-1)*fils_per_conductor + 1;
    idx_end = N1*fils_per_conductor + turn*fils_per_conductor;
    loss_w2 = loss_w2 + sum(results.P_fil(idx_start:idx_end));
end

fprintf('\nPer-winding losses:\n');
fprintf('  Winding 1: %.6f W (%.1f%%)\n', loss_w1, loss_w1/results.P_total*100);
fprintf('  Winding 2: %.6f W (%.1f%%)\n', loss_w2, loss_w2/results.P_total*100);

%% Visualize
fprintf('\nCreating visualizations...\n');

figure('Name', 'Transformer Analysis', 'Position', [100 100 1400 600]);

% Current density
subplot(1,3,1);
plot_current_density(geom, results);
title(sprintf('Current Density @ %.0f kHz', f/1e3));

% Add winding boundaries
hold on;
% Winding 1 boundary
rectangle('Position', [-width/2, -gap/2, width, N1*(height+gap)], ...
    'EdgeColor', 'b', 'LineWidth', 2, 'LineStyle', '--');
text(0, N1*(height+gap)/2, 'W1', 'Color', 'b', 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center');

% Winding 2 boundary
rectangle('Position', [x_offset-width/2, -gap/2, width, N2*(height+gap)], ...
    'EdgeColor', 'r', 'LineWidth', 2, 'LineStyle', '--');
text(x_offset, N2*(height+gap)/2, 'W2', 'Color', 'r', 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center');

% Loss density
subplot(1,3,2);
plot_loss_density(geom, results);
title('Loss Density');

% Loss per turn
subplot(1,3,3);
loss_per_turn = zeros(N1 + N2, 1);
for turn = 1:(N1+N2)
    idx_start = (turn-1) * fils_per_conductor + 1;
    idx_end = turn * fils_per_conductor;
    loss_per_turn(turn) = sum(results.P_fil(idx_start:idx_end));
end

bar(1:(N1+N2), loss_per_turn*1e3);
xlabel('Turn Number');
ylabel('Loss (mW)');
title('Loss per Turn');
grid on;
hold on;
% Mark winding boundary
plot([N1+0.5, N1+0.5], ylim, 'r--', 'LineWidth', 2);
text(N1/2, max(loss_per_turn)*1e3*0.9, 'Winding 1', ...
    'HorizontalAlignment', 'center', 'FontWeight', 'bold');
text(N1 + N2/2, max(loss_per_turn)*1e3*0.9, 'Winding 2', ...
    'HorizontalAlignment', 'center', 'FontWeight', 'bold');

fprintf('\n=== TEST COMPLETE ===\n');
