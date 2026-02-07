% full_transformer_example.m
% Complete transformer analysis with frequency sweep
%{
clear; clc; close all;

fprintf('=== COMPLETE TRANSFORMER ANALYSIS ===\n\n');

%% Configuration
sigma = 5.8e7;      % Copper conductivity (S/m)
mu0 = 4*pi*1e-7;    % Permeability (H/m)

% Conductor geometry
width = 2e-3;       % 2 mm
height = 1e-3;      % 1 mm
gap = 0.2e-3;       % 0.2 mm between layers

% Transformer specification
fprintf('=== TRANSFORMER CONFIGURATION ===\n');

% Primary winding
N1_layers = 2;      % 2 layers
N1_turns_per_layer = 5;
N1 = N1_layers * N1_turns_per_layer;
I1 = 10;            % 10 Arms
phase1 = 0;         % 0 degrees

fprintf('Primary: %d turns (%d layers × %d turns/layer), %.1f Arms @ %.0f°\n', ...
    N1, N1_layers, N1_turns_per_layer, I1, phase1);

% Secondary winding
N2_layers = 4;      % 4 layers
N2_turns_per_layer = 5;
N2 = N2_layers * N2_turns_per_layer;
I2 = 5;             % 5 Arms (half primary current, double turns)
phase2 = 180;       % 180 degrees (buck converter)

fprintf('Secondary: %d turns (%d layers × %d turns/layer), %.1f Arms @ %.0f°\n', ...
    N2, N2_layers, N2_turns_per_layer, I2, phase2);

%% Build geometry
fprintf('\nBuilding transformer geometry...\n');

conductors = [];
winding_map = [];

% Primary winding conductors
x1 = 0;
for i = 1:N1
    y_pos = (i-1) * (height + gap);
    conductors = [conductors; x1, y_pos, width, height, I1, phase1];
    winding_map = [winding_map; 1];
end

% Secondary winding conductors (offset in x)
x2 = width + 1e-3;  % 1mm gap between windings
for i = 1:N2
    y_pos = (i-1) * (height + gap);
    conductors = [conductors; x2, y_pos, width, height, I2, phase2];
    winding_map = [winding_map; 2];
end

fprintf('  Total conductors: %d\n', size(conductors,1));
fprintf('  Primary conductors: %d\n', sum(winding_map == 1));
fprintf('  Secondary conductors: %d\n', sum(winding_map == 2));

%% Build PEEC geometry
Nx = 8;
Ny = 8;

fprintf('\nBuilding PEEC geometry (Nx=%d, Ny=%d)...\n', Nx, Ny);
geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny, winding_map);

fprintf('  Total filaments: %d\n', geom.Nf);
fprintf('  Filaments per conductor: %d\n', Nx*Ny);

%% Single frequency analysis
f_single = 100e3;  % 100 kHz

fprintf('\n=== SINGLE FREQUENCY ANALYSIS ===\n');
fprintf('Frequency: %.0f kHz\n', f_single/1e3);

results = peec_solve_frequency(geom, conductors, f_single, sigma, mu0);

% Calculate per-winding losses
fils_per_conductor = Nx * Ny;

loss_primary = 0;
for turn = 1:N1
    idx_start = (turn-1) * fils_per_conductor + 1;
    idx_end = turn * fils_per_conductor;
    loss_primary = loss_primary + sum(results.P_fil(idx_start:idx_end));
end

loss_secondary = 0;
for turn = 1:N2
    idx_start = N1*fils_per_conductor + (turn-1)*fils_per_conductor + 1;
    idx_end = N1*fils_per_conductor + turn*fils_per_conductor;
    loss_secondary = loss_secondary + sum(results.P_fil(idx_start:idx_end));
end

% Calculate DC losses for comparison
A = width * height;
Rdc_primary = N1 / (sigma * A);
Rdc_secondary = N2 / (sigma * A);
Pdc_primary = 0.5 * I1^2 * Rdc_primary;
Pdc_secondary = 0.5 * I2^2 * Rdc_secondary;

fprintf('\nPrimary Winding:\n');
fprintf('  DC Loss: %.6f W\n', Pdc_primary);
fprintf('  AC Loss: %.6f W\n', loss_primary);
fprintf('  Rac/Rdc: %.3f\n', loss_primary/Pdc_primary);

fprintf('\nSecondary Winding:\n');
fprintf('  DC Loss: %.6f W\n', Pdc_secondary);
fprintf('  AC Loss: %.6f W\n', loss_secondary);
fprintf('  Rac/Rdc: %.3f\n', loss_secondary/Pdc_secondary);

fprintf('\nTotal:\n');
fprintf('  DC Loss: %.6f W\n', Pdc_primary + Pdc_secondary);
fprintf('  AC Loss: %.6f W\n', results.P_total);
fprintf('  Rac/Rdc: %.3f\n', results.P_total/(Pdc_primary + Pdc_secondary));

% Skin depth
delta = 1/sqrt(pi*f_single*mu0*sigma);
fprintf('\nSkin depth: %.2f µm\n', delta*1e6);
fprintf('Height/skin depth: %.2f\n', height/delta);

%% Visualize single frequency
fprintf('\n=== CREATING VISUALIZATIONS ===\n');

figure('Name', 'Transformer Analysis', 'Position', [100 100 1600 900]);

% Add main title using annotation (Octave compatible)
annotation('textbox', [0 0.96 1 0.04], ...
    'String', sprintf('Transformer Analysis @ %.0f kHz', f_single/1e3), ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
    'FontSize', 14, 'FontWeight', 'bold');

% Current density
subplot(2,3,1);
plot_current_density(geom, results);
title('Current Density');
hold on;
% Mark winding boundaries
rectangle('Position', [x1-width/2-0.1e-3, -gap/2, width+0.2e-3, N1*(height+gap)], ...
    'EdgeColor', 'b', 'LineWidth', 2, 'LineStyle', '--');
rectangle('Position', [x2-width/2-0.1e-3, -gap/2, width+0.2e-3, N2*(height+gap)], ...
    'EdgeColor', 'r', 'LineWidth', 2, 'LineStyle', '--');
text(x1, N1*(height+gap)+0.3e-3, 'Primary', 'Color', 'b', 'FontWeight', 'bold');
text(x2, N2*(height+gap)+0.3e-3, 'Secondary', 'Color', 'r', 'FontWeight', 'bold');

% Loss density
subplot(2,3,2);
plot_loss_density(geom, results);
title('Loss Density');

% Loss per turn
subplot(2,3,3);
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
plot([N1+0.5, N1+0.5], ylim, 'k--', 'LineWidth', 2);
text(N1/2, max(loss_per_turn)*1e3*0.95, 'Pri', 'HorizontalAlignment', 'center');
text(N1 + N2/2, max(loss_per_turn)*1e3*0.95, 'Sec', 'HorizontalAlignment', 'center');

% Loss per layer
subplot(2,3,4);
loss_per_layer_pri = zeros(N1_layers, 1);
loss_per_layer_sec = zeros(N2_layers, 1);

for layer = 1:N1_layers
    for turn_in_layer = 1:N1_turns_per_layer
        turn = (layer-1)*N1_turns_per_layer + turn_in_layer;
        idx_start = (turn-1) * fils_per_conductor + 1;
        idx_end = turn * fils_per_conductor;
        loss_per_layer_pri(layer) = loss_per_layer_pri(layer) + sum(results.P_fil(idx_start:idx_end));
    end
end

for layer = 1:N2_layers
    for turn_in_layer = 1:N2_turns_per_layer
        turn = (layer-1)*N2_turns_per_layer + turn_in_layer;
        idx_start = N1*fils_per_conductor + (turn-1)*fils_per_conductor + 1;
        idx_end = N1*fils_per_conductor + turn*fils_per_conductor;
        loss_per_layer_sec(layer) = loss_per_layer_sec(layer) + sum(results.P_fil(idx_start:idx_end));
    end
end

bar([loss_per_layer_pri; loss_per_layer_sec]*1e3);
xlabel('Layer Number');
ylabel('Loss per Layer (mW)');
title('Loss Distribution by Layer');
grid on;
hold on;
plot([N1_layers+0.5, N1_layers+0.5], ylim, 'k--', 'LineWidth', 2);

%% Frequency sweep
fprintf('\n=== FREQUENCY SWEEP ===\n');

f_vec = logspace(3, 6, 30);  % 1 kHz to 1 MHz
Rac_Rdc_pri = zeros(size(f_vec));
Rac_Rdc_sec = zeros(size(f_vec));
Rac_Rdc_total = zeros(size(f_vec));

fprintf('Running frequency sweep...\n');
for i = 1:length(f_vec)
    if mod(i, 5) == 0
        fprintf('  Progress: %d/%d\n', i, length(f_vec));
    end

    results_i = peec_solve_frequency(geom, conductors, f_vec(i), sigma, mu0);

    % Primary loss
    loss_pri_i = 0;
    for turn = 1:N1
        idx_start = (turn-1) * fils_per_conductor + 1;
        idx_end = turn * fils_per_conductor;
        loss_pri_i = loss_pri_i + sum(results_i.P_fil(idx_start:idx_end));
    end

    % Secondary loss
    loss_sec_i = 0;
    for turn = 1:N2
        idx_start = N1*fils_per_conductor + (turn-1)*fils_per_conductor + 1;
        idx_end = N1*fils_per_conductor + turn*fils_per_conductor;
        loss_sec_i = loss_sec_i + sum(results_i.P_fil(idx_start:idx_end));
    end

    Rac_Rdc_pri(i) = loss_pri_i / Pdc_primary;
    Rac_Rdc_sec(i) = loss_sec_i / Pdc_secondary;
    Rac_Rdc_total(i) = results_i.P_total / (Pdc_primary + Pdc_secondary);
end

% Plot frequency sweep
subplot(2,3,5);
loglog(f_vec/1e3, Rac_Rdc_pri, 'b-', 'LineWidth', 2);
hold on;
loglog(f_vec/1e3, Rac_Rdc_sec, 'r-', 'LineWidth', 2);
loglog(f_vec/1e3, Rac_Rdc_total, 'k--', 'LineWidth', 2);
grid on;
xlabel('Frequency (kHz)');
ylabel('R_{AC}/R_{DC}');
title('AC Resistance Factor vs Frequency');
legend('Primary', 'Secondary', 'Total', 'Location', 'northwest');

% Summary table
subplot(2,3,6);
axis off;

text(0.05, 0.95, 'Summary Statistics', 'FontSize', 12, 'FontWeight', 'bold');
text(0.05, 0.85, sprintf('Frequency: %.0f kHz', f_single/1e3), 'FontSize', 10);
text(0.05, 0.78, sprintf('Turns ratio: %d:%d', N1, N2), 'FontSize', 10);
text(0.05, 0.71, sprintf('Current ratio: %.1f:%.1f', I1, I2), 'FontSize', 10);

text(0.05, 0.60, 'Primary:', 'FontSize', 11, 'FontWeight', 'bold', 'Color', 'b');
text(0.05, 0.53, sprintf('  %d turns, %d layers', N1, N1_layers), 'FontSize', 9);
text(0.05, 0.47, sprintf('  Loss: %.3f W', loss_primary), 'FontSize', 9);
text(0.05, 0.41, sprintf('  Rac/Rdc: %.2f', loss_primary/Pdc_primary), 'FontSize', 9);

text(0.05, 0.30, 'Secondary:', 'FontSize', 11, 'FontWeight', 'bold', 'Color', 'r');
text(0.05, 0.23, sprintf('  %d turns, %d layers', N2, N2_layers), 'FontSize', 9);
text(0.05, 0.17, sprintf('  Loss: %.3f W', loss_secondary), 'FontSize', 9);
text(0.05, 0.11, sprintf('  Rac/Rdc: %.2f', loss_secondary/Pdc_secondary), 'FontSize', 9);

text(0.05, 0.00, sprintf('Total Loss: %.3f W', results.P_total), ...
    'FontSize', 11, 'FontWeight', 'bold');

fprintf('\n=== ANALYSIS COMPLETE ===\n');
fprintf('Results displayed in figure window\n');

%}

% full_transformer_example.m
% Complete transformer analysis with multi-filar winding support
% 2:1 transformer (primary:secondary turns ratio)

clear; clc; close all;

%% ========== USER INPUT: MULTI-FILAR CONFIGURATION ==========

fprintf('=== TRANSFORMER MULTI-FILAR CONFIGURATION ===\n\n');
fprintf('This is a 2:1 transformer (primary has 2× turns of secondary)\n');
fprintf('Configure the multi-filar winding for each winding:\n\n');

% Get primary winding filar configuration
fprintf('PRIMARY WINDING - Select filar configuration:\n');
fprintf('  1 = Single-filar (standard)\n');
fprintf('  2 = Bi-filar (two parallel conductors)\n');
fprintf('  3 = Tri-filar (three parallel conductors)\n');
fprintf('  4 = Quad-filar (four parallel conductors)\n');
primary_filar = input('Primary filar choice [1-4]: ');

while ~ismember(primary_filar, [1 2 3 4])
    fprintf('Invalid choice. Please enter 1, 2, 3, or 4.\n');
    primary_filar = input('Primary filar choice [1-4]: ');
end

% Get secondary winding filar configuration
fprintf('\nSECONDARY WINDING - Select filar configuration:\n');
fprintf('  1 = Single-filar (standard)\n');
fprintf('  2 = Bi-filar (two parallel conductors)\n');
fprintf('  3 = Tri-filar (three parallel conductors)\n');
fprintf('  4 = Quad-filar (four parallel conductors)\n');
secondary_filar = input('Secondary filar choice [1-4]: ');

while ~ismember(secondary_filar, [1 2 3 4])
    fprintf('Invalid choice. Please enter 1, 2, 3, or 4.\n');
    secondary_filar = input('Secondary filar choice [1-4]: ');
end

% Display configuration
filar_names = {'Single-filar', 'Bi-filar', 'Tri-filar', 'Quad-filar'};
fprintf('\n=== SELECTED CONFIGURATION ===\n');
fprintf('Primary:   %s (%d parallel conductor(s) per turn)\n', ...
    filar_names{primary_filar}, primary_filar);
fprintf('Secondary: %s (%d parallel conductor(s) per turn)\n', ...
    filar_names{secondary_filar}, secondary_filar);
fprintf('\n');

%% Configuration
sigma = 5.8e7;      % Copper conductivity (S/m)
mu0 = 4*pi*1e-7;    % Permeability (H/m)

% Conductor geometry
width = 2e-3;       % 2 mm
height = 1e-3;      % 1 mm
gap_layer = 0.2e-3; % 0.2 mm between layers
gap_filar = 0.15e-3; % 0.15 mm between filar conductors

% Transformer specification (2:1 turns ratio)
fprintf('=== TRANSFORMER SPECIFICATION ===\n');

% Primary winding (2× turns)
N1_layers = 2;
N1_turns_per_layer = 5;
N1 = N1_layers * N1_turns_per_layer;
I1 = 10;            % 10 Arms
phase1 = 0;         % 0 degrees

fprintf('Primary: %d turns (%d layers × %d turns/layer)\n', ...
    N1, N1_layers, N1_turns_per_layer);
fprintf('         %.1f Arms @ %.0f°, %s\n', I1, phase1, filar_names{primary_filar});

% Secondary winding (1× turns, 2× current for same power)
N2_layers = 4;
N2_turns_per_layer = 5;
N2 = N2_layers * N2_turns_per_layer / 2;  % Half the turns (2:1 ratio)
I2 = 5;             % 5 Arms (half primary current)
phase2 = 180;       % 180 degrees

fprintf('Secondary: %d turns (%d layers × %d turns/layer)\n', ...
    N2, N2_layers, N2_turns_per_layer/2);
fprintf('           %.1f Arms @ %.0f°, %s\n', I2, phase2, filar_names{secondary_filar});
fprintf('Turns ratio: %d:%d\n', N1, N2);

%% Build geometry using multi-filar configuration

fprintf('\nBuilding transformer geometry...\n');

% PRIMARY WINDING
config_pri.n_filar = primary_filar;
config_pri.n_turns = N1;
config_pri.n_windings = 1;
config_pri.width = width;
config_pri.height = height;
config_pri.gap_layer = gap_layer;
config_pri.gap_filar = gap_filar;
config_pri.currents = I1;
config_pri.phases = phase1;
config_pri.x_offset = 0;

[conductors_pri, winding_map_pri] = build_multifilar_winding(config_pri);

% Calculate primary total width for secondary offset
if primary_filar == 1
    primary_total_width = width;
else
    primary_total_width = primary_filar * width + (primary_filar - 1) * gap_filar;
end

% SECONDARY WINDING
config_sec.n_filar = secondary_filar;
config_sec.n_turns = N2;
config_sec.n_windings = 1;
config_sec.width = width;
config_sec.height = height;
config_sec.gap_layer = gap_layer;
config_sec.gap_filar = gap_filar;
config_sec.currents = I2;
config_sec.phases = phase2;

% Position secondary with appropriate gap
gap_between_windings = 1e-3;  % 1mm
if secondary_filar == 1
    secondary_total_width = width;
else
    secondary_total_width = secondary_filar * width + (secondary_filar - 1) * gap_filar;
end

config_sec.x_offset = primary_total_width/2 + gap_between_windings + secondary_total_width/2;

[conductors_sec, winding_map_sec] = build_multifilar_winding(config_sec);

% Combine windings
conductors = [conductors_pri; conductors_sec];
winding_map = [winding_map_pri; winding_map_sec + 1];  % Secondary is winding 2

fprintf('  Total conductors: %d (Primary: %d, Secondary: %d)\n', ...
    size(conductors,1), size(conductors_pri,1), size(conductors_sec,1));

%% Build PEEC geometry
Nx = 8;
Ny = 8;

fprintf('\nBuilding PEEC geometry (Nx=%d, Ny=%d)...\n', Nx, Ny);
geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny, winding_map);

fprintf('  Total filaments: %d\n', geom.Nf);
fprintf('  Filaments per conductor: %d\n', Nx*Ny);

%% Single frequency analysis
f_single = 100e3;  % 100 kHz

fprintf('\n=== SINGLE FREQUENCY ANALYSIS ===\n');
fprintf('Frequency: %.0f kHz\n', f_single/1e3);

results = peec_solve_frequency(geom, conductors, f_single, sigma, mu0);

% Calculate per-winding losses
fils_per_conductor = Nx * Ny;
n_cond_pri = size(conductors_pri, 1);
n_cond_sec = size(conductors_sec, 1);

loss_primary = 0;
for cond = 1:n_cond_pri
    idx_start = (cond-1) * fils_per_conductor + 1;
    idx_end = cond * fils_per_conductor;
    loss_primary = loss_primary + sum(results.P_fil(idx_start:idx_end));
end

loss_secondary = 0;
for cond = 1:n_cond_sec
    idx_start = n_cond_pri * fils_per_conductor + (cond-1) * fils_per_conductor + 1;
    idx_end = n_cond_pri * fils_per_conductor + cond * fils_per_conductor;
    loss_secondary = loss_secondary + sum(results.P_fil(idx_start:idx_end));
end

% Calculate DC losses for comparison
A = width * height;
Rdc_primary = (N1 / primary_filar) / (sigma * A);
Rdc_secondary = (N2 / secondary_filar) / (sigma * A);
Pdc_primary = 0.5 * I1^2 * Rdc_primary;
Pdc_secondary = 0.5 * I2^2 * Rdc_secondary;

fprintf('\nPrimary Winding (%s):\n', filar_names{primary_filar});
fprintf('  DC Loss: %.6f W\n', Pdc_primary);
fprintf('  AC Loss: %.6f W\n', loss_primary);
fprintf('  Rac/Rdc: %.3f\n', loss_primary/Pdc_primary);
if primary_filar > 1
    fprintf('  Current per filar: %.2f A\n', I1/primary_filar);
end

fprintf('\nSecondary Winding (%s):\n', filar_names{secondary_filar});
fprintf('  DC Loss: %.6f W\n', Pdc_secondary);
fprintf('  AC Loss: %.6f W\n', loss_secondary);
fprintf('  Rac/Rdc: %.3f\n', loss_secondary/Pdc_secondary);
if secondary_filar > 1
    fprintf('  Current per filar: %.2f A\n', I2/secondary_filar);
end

fprintf('\nTotal:\n');
fprintf('  DC Loss: %.6f W\n', Pdc_primary + Pdc_secondary);
fprintf('  AC Loss: %.6f W\n', results.P_total);
fprintf('  Rac/Rdc: %.3f\n', results.P_total/(Pdc_primary + Pdc_secondary));

% Skin depth
delta = 1/sqrt(pi*f_single*mu0*sigma);
fprintf('\nSkin depth: %.2f µm\n', delta*1e6);
fprintf('Height/skin depth: %.2f\n', height/delta);

%% Visualize single frequency
fprintf('\n=== CREATING VISUALIZATIONS ===\n');

figure('Name', 'Transformer Analysis', 'Position', [100 100 1600 900]);

% Add main title using annotation
title_str = sprintf('2:1 Transformer: Primary=%s, Secondary=%s @ %.0f kHz', ...
    filar_names{primary_filar}, filar_names{secondary_filar}, f_single/1e3);
annotation('textbox', [0 0.96 1 0.04], ...
    'String', title_str, ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
    'FontSize', 14, 'FontWeight', 'bold');

% Current density
subplot(2,3,1);
plot_current_density(geom, results);
title('Current Density Distribution');
hold on;
% Mark winding boundaries
x1 = 0;
x2 = config_sec.x_offset;
max_y_pri = max(conductors_pri(:,2)) + height;
max_y_sec = max(conductors_sec(:,2)) + height;
rectangle('Position', [x1-primary_total_width/2-0.1e-3, -gap_layer/2, ...
    primary_total_width+0.2e-3, max_y_pri+gap_layer], ...
    'EdgeColor', 'b', 'LineWidth', 2, 'LineStyle', '--');
rectangle('Position', [x2-secondary_total_width/2-0.1e-3, -gap_layer/2, ...
    secondary_total_width+0.2e-3, max_y_sec+gap_layer], ...
    'EdgeColor', 'r', 'LineWidth', 2, 'LineStyle', '--');
text(x1, max(max_y_pri,max_y_sec)+0.5e-3, 'Primary', 'Color', 'b', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
text(x2, max(max_y_pri,max_y_sec)+0.5e-3, 'Secondary', 'Color', 'r', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

% Loss density
subplot(2,3,2);
plot_loss_density(geom, results);
title('Loss Density Distribution');

% Loss per turn
subplot(2,3,3);
loss_per_turn_pri = zeros(N1, 1);
for turn = 1:N1
    for filar = 1:primary_filar
        cond = (turn-1)*primary_filar + filar;
        idx_start = (cond-1) * fils_per_conductor + 1;
        idx_end = cond * fils_per_conductor;
        loss_per_turn_pri(turn) = loss_per_turn_pri(turn) + sum(results.P_fil(idx_start:idx_end));
    end
end

loss_per_turn_sec = zeros(N2, 1);
for turn = 1:N2
    for filar = 1:secondary_filar
        cond = n_cond_pri + (turn-1)*secondary_filar + filar;
        idx_start = (cond-1) * fils_per_conductor + 1;
        idx_end = cond * fils_per_conductor;
        loss_per_turn_sec(turn) = loss_per_turn_sec(turn) + sum(results.P_fil(idx_start:idx_end));
    end
end

bar([loss_per_turn_pri; loss_per_turn_sec]*1e3);
xlabel('Turn Number');
ylabel('Loss (mW)');
title('Loss per Turn');
grid on;
hold on;
plot([N1+0.5, N1+0.5], ylim, 'k--', 'LineWidth', 2);
text(N1/2, max([loss_per_turn_pri; loss_per_turn_sec])*1e3*0.95, 'Pri', 'HorizontalAlignment', 'center');
text(N1 + N2/2, max([loss_per_turn_pri; loss_per_turn_sec])*1e3*0.95, 'Sec', 'HorizontalAlignment', 'center');

% Loss per layer
subplot(2,3,4);
loss_per_layer_pri = zeros(N1_layers, 1);
loss_per_layer_sec = zeros(N2_layers, 1);

for layer = 1:N1_layers
    for turn_in_layer = 1:N1_turns_per_layer
        turn = (layer-1)*N1_turns_per_layer + turn_in_layer;
        for filar = 1:primary_filar
            cond = (turn-1)*primary_filar + filar;
            idx_start = (cond-1) * fils_per_conductor + 1;
            idx_end = cond * fils_per_conductor;
            loss_per_layer_pri(layer) = loss_per_layer_pri(layer) + sum(results.P_fil(idx_start:idx_end));
        end
    end
end

for layer = 1:N2_layers
    for turn_in_layer = 1:(N2_turns_per_layer/2)
        turn = (layer-1)*(N2_turns_per_layer/2) + turn_in_layer;
        for filar = 1:secondary_filar
            cond = n_cond_pri + (turn-1)*secondary_filar + filar;
            idx_start = (cond-1) * fils_per_conductor + 1;
            idx_end = cond * fils_per_conductor;
            loss_per_layer_sec(layer) = loss_per_layer_sec(layer) + sum(results.P_fil(idx_start:idx_end));
        end
    end
end

bar([loss_per_layer_pri; loss_per_layer_sec]*1e3);
xlabel('Layer Number');
ylabel('Loss per Layer (mW)');
title('Loss Distribution by Layer');
grid on;
hold on;
plot([N1_layers+0.5, N1_layers+0.5], ylim, 'k--', 'LineWidth', 2);

%% Frequency sweep
fprintf('\n=== FREQUENCY SWEEP ===\n');

f_vec = logspace(3, 6, 30);  % 1 kHz to 1 MHz
Rac_Rdc_pri = zeros(size(f_vec));
Rac_Rdc_sec = zeros(size(f_vec));
Rac_Rdc_total = zeros(size(f_vec));

fprintf('Running frequency sweep...\n');
for i = 1:length(f_vec)
    if mod(i, 5) == 0
        fprintf('  Progress: %d/%d\n', i, length(f_vec));
    end

    results_i = peec_solve_frequency(geom, conductors, f_vec(i), sigma, mu0);

    % Primary loss
    loss_pri_i = 0;
    for cond = 1:n_cond_pri
        idx_start = (cond-1) * fils_per_conductor + 1;
        idx_end = cond * fils_per_conductor;
        loss_pri_i = loss_pri_i + sum(results_i.P_fil(idx_start:idx_end));
    end

    % Secondary loss
    loss_sec_i = 0;
    for cond = 1:n_cond_sec
        idx_start = n_cond_pri * fils_per_conductor + (cond-1) * fils_per_conductor + 1;
        idx_end = n_cond_pri * fils_per_conductor + cond * fils_per_conductor;
        loss_sec_i = loss_sec_i + sum(results_i.P_fil(idx_start:idx_end));
    end

    Rac_Rdc_pri(i) = loss_pri_i / Pdc_primary;
    Rac_Rdc_sec(i) = loss_sec_i / Pdc_secondary;
    Rac_Rdc_total(i) = results_i.P_total / (Pdc_primary + Pdc_secondary);
end

% Plot frequency sweep
subplot(2,3,5);
loglog(f_vec/1e3, Rac_Rdc_pri, 'b-', 'LineWidth', 2);
hold on;
loglog(f_vec/1e3, Rac_Rdc_sec, 'r-', 'LineWidth', 2);
loglog(f_vec/1e3, Rac_Rdc_total, 'k--', 'LineWidth', 2);
grid on;
xlabel('Frequency (kHz)');
ylabel('R_{AC}/R_{DC}');
title('AC Resistance Factor vs Frequency');
legend('Primary', 'Secondary', 'Total', 'Location', 'northwest');

% Summary table
subplot(2,3,6);
axis off;

text(0.05, 0.95, 'Configuration Summary', 'FontSize', 12, 'FontWeight', 'bold');
text(0.05, 0.85, sprintf('Frequency: %.0f kHz', f_single/1e3), 'FontSize', 10);
text(0.05, 0.78, sprintf('Turns ratio: %d:%d', N1, N2), 'FontSize', 10);
text(0.05, 0.71, sprintf('Current ratio: %.1f:%.1f', I1, I2), 'FontSize', 10);

text(0.05, 0.60, sprintf('Primary (%s):', filar_names{primary_filar}), ...
    'FontSize', 11, 'FontWeight', 'bold', 'Color', 'b');
text(0.05, 0.53, sprintf('  %d turns, %d layers', N1, N1_layers), 'FontSize', 9);
text(0.05, 0.47, sprintf('  %d conductors', n_cond_pri), 'FontSize', 9);
text(0.05, 0.41, sprintf('  Loss: %.3f W', loss_primary), 'FontSize', 9);
text(0.05, 0.35, sprintf('  Rac/Rdc: %.2f', loss_primary/Pdc_primary), 'FontSize', 9);

text(0.05, 0.24, sprintf('Secondary (%s):', filar_names{secondary_filar}), ...
    'FontSize', 11, 'FontWeight', 'bold', 'Color', 'r');
text(0.05, 0.17, sprintf('  %d turns, %d layers', N2, N2_layers), 'FontSize', 9);
text(0.05, 0.11, sprintf('  %d conductors', n_cond_sec), 'FontSize', 9);
text(0.05, 0.05, sprintf('  Loss: %.3f W', loss_secondary), 'FontSize', 9);
text(0.05, -0.01, sprintf('  Rac/Rdc: %.2f', loss_secondary/Pdc_secondary), 'FontSize', 9);

text(0.05, -0.12, sprintf('Total Loss: %.3f W', results.P_total), ...
    'FontSize', 11, 'FontWeight', 'bold');

fprintf('\n=== ANALYSIS COMPLETE ===\n');
fprintf('Results displayed in figure window\n');
