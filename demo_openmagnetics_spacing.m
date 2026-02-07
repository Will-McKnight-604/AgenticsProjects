% demo_openmagnetics_spacing.m
% Demonstration of improved OpenMagnetics-compliant winding spacing
% Shows before/after comparison and integration with PEEC solver

clear; close all;

fprintf('===================================================================\n');
fprintf('   OpenMagnetics Winding Spacing Demonstration\n');
fprintf('===================================================================\n\n');

%% EXAMPLE 1: Spacing Calculation Comparison

fprintf('--- EXAMPLE 1: Spacing Calculator ---\n\n');

% Flyback transformer specification
config1 = struct();
config1.voltage_primary = 325;    % 230V RMS * sqrt(2)
config1.voltage_secondary = 48;   % 34V RMS * sqrt(2)
config1.n_turns = 40;
config1.width = 0.65e-3;          % AWG 22 equivalent
config1.height = 0.65e-3;
config1.insulation_class = 'basic';
config1.pollution_degree = 2;

% Calculate spacing
spacing_basic = calculate_winding_spacing(config1);

fprintf('Flyback Transformer (325V to 48V, basic insulation):\n');
fprintf('  Turn-to-turn gap:    %.3f mm\n', spacing_basic.gap_layer * 1e3);
fprintf('  Winding-to-winding:  %.3f mm\n', spacing_basic.gap_winding * 1e3);

% Now with reinforced insulation
config2 = config1;
config2.insulation_class = 'reinforced';
spacing_reinforced = calculate_winding_spacing(config2);

fprintf('\nSame transformer with reinforced insulation:\n');
fprintf('  Turn-to-turn gap:    %.3f mm\n', spacing_reinforced.gap_layer * 1e3);
fprintf('  Winding-to-winding:  %.3f mm (%.1fx increase)\n', ...
    spacing_reinforced.gap_winding * 1e3, ...
    spacing_reinforced.gap_winding / spacing_basic.gap_winding);

%% EXAMPLE 2: Build Transformer with Old vs New Method

fprintf('\n--- EXAMPLE 2: Transformer Geometry Comparison ---\n\n');

% Wire specifications
wire_width = 0.65e-3;   % 650 µm (approximately AWG 22)
wire_height = 0.65e-3;

% Transformer specification
% Primary: 40 turns, 2 layers, 2A, 0°, 325V peak
% Secondary: 10 turns, 1 layer, 8A, 180°, 48V peak

winding_old = {
    {1, 40, 2, 2.0, 0};      % Old format: no voltage info
    {2, 10, 1, 8.0, 180}
};

winding_new = {
    {1, 40, 2, 2.0, 0, 325};    % New format: includes voltage
    {2, 10, 1, 8.0, 180, 48}
};

% Old method (fixed spacing)
gap_layer_old = 0.1e-3;  % 100 µm
gap_turn_old = 0.05e-3;  % 50 µm

[cond_old, map_old] = build_transformer_geometry(winding_old, ...
    wire_width, wire_height, gap_layer_old, gap_turn_old);

fprintf('OLD METHOD (fixed spacing):\n');
height_old = max(cond_old(:,2)) - min(cond_old(:,2)) + wire_height;
fprintf('  Total height: %.3f mm\n', height_old * 1e3);

% New method (voltage-aware spacing)
insulation = struct();
insulation.insulation_class = 'reinforced';
insulation.pollution_degree = 2;

[cond_new, map_new] = build_transformer_geometry(winding_new, ...
    wire_width, wire_height, gap_layer_old, gap_turn_old, insulation);

fprintf('\nNEW METHOD (OpenMagnetics spacing):\n');
height_new = max(cond_new(:,2)) - min(cond_new(:,2)) + wire_height;
fprintf('  Total height: %.3f mm\n', height_new * 1e3);
fprintf('  Height increase: %.3f mm (%.1f%%)\n', ...
    (height_new - height_old) * 1e3, ...
    (height_new/height_old - 1) * 100);

%% EXAMPLE 3: Multi-filar Winding with Voltage-Aware Spacing

fprintf('\n--- EXAMPLE 3: Multi-filar Winding ---\n\n');

% Bifilar winding configuration
config_bifilar = struct();
config_bifilar.n_filar = 2;        % Bifilar (2 parallel strands)
config_bifilar.n_turns = 20;
config_bifilar.n_windings = 2;
config_bifilar.width = wire_width;
config_bifilar.height = wire_height;
config_bifilar.gap_layer = 0.1e-3;
config_bifilar.currents = [2.0; 8.0];
config_bifilar.phases = [0; 180];

% Add voltage information for proper spacing
config_bifilar.voltages = [325; 48];
config_bifilar.insulation_class = 'reinforced';
config_bifilar.pollution_degree = 2;

% Build with new method
[cond_bifilar, map_bifilar, shapes_bifilar] = ...
    build_multifilar_winding_improved(config_bifilar);

fprintf('Bifilar winding built with OpenMagnetics spacing\n');
height_bifilar = max(cond_bifilar(:,2)) - min(cond_bifilar(:,2)) + wire_height;
fprintf('Total height: %.3f mm\n', height_bifilar * 1e3);

%% EXAMPLE 4: Visualization Comparison

fprintf('\n--- EXAMPLE 4: Visual Comparison ---\n\n');

% Create figure with side-by-side comparison
fig1 = figure('Name', 'Spacing Comparison', 'Position', [100 100 1400 600]);

% Plot old method
subplot(1, 2, 1);
plot_transformer_cross_section(cond_old, map_old, wire_width, wire_height);
title('OLD: Fixed Spacing (Not IEC Compliant)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Height (mm)');
xlabel('Width (mm)');

% Plot new method
subplot(1, 2, 2);
plot_transformer_cross_section(cond_new, map_new, wire_width, wire_height);
title('NEW: OpenMagnetics IEC-Compliant Spacing', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Height (mm)');
xlabel('Width (mm)');

%% EXAMPLE 5: Integration with PEEC Solver

fprintf('\n--- EXAMPLE 5: PEEC Analysis with New Spacing ---\n\n');

% Physical parameters
sigma = 5.8e7;  % Copper conductivity [S/m]
mu0 = 4*pi*1e-7;  % Permeability [H/m]
f = 100e3;  % 100 kHz
Nx = 4;  % Filaments in X
Ny = 4;  % Filaments in Y

% Build geometry using new spacing
fprintf('Building PEEC geometry with OpenMagnetics spacing...\n');
geom_new = peec_build_geometry(cond_new, sigma, mu0, Nx, Ny, map_new.winding_id);

% Solve at frequency
fprintf('Solving at f = %.1f kHz...\n', f/1e3);
results_new = peec_solve_frequency(geom_new, cond_new, f, sigma, mu0);

fprintf('Results:\n');
fprintf('  Total loss: %.3f W\n', results_new.P_total);
fprintf('  Primary loss: %.3f W\n', sum(results_new.P_fil(map_new.winding_id == 1)));
fprintf('  Secondary loss: %.3f W\n', sum(results_new.P_fil(map_new.winding_id == 2)));

%% EXAMPLE 6: Voltage Sweep for Different Insulation Classes

fprintf('\n--- EXAMPLE 6: Insulation Class Comparison ---\n\n');

voltage_levels = [50, 100, 250, 500, 1000];  % Voltage differences [V]
insulation_classes = {'basic', 'supplementary', 'reinforced'};

% Create comparison matrix
gap_matrix = zeros(length(voltage_levels), length(insulation_classes));

for i = 1:length(voltage_levels)
    for j = 1:length(insulation_classes)
        cfg = struct();
        cfg.voltage_primary = voltage_levels(i);
        cfg.voltage_secondary = 48;
        cfg.width = wire_width;
        cfg.height = wire_height;
        cfg.insulation_class = insulation_classes{j};
        cfg.pollution_degree = 2;

        sp = calculate_winding_spacing(cfg);
        gap_matrix(i, j) = sp.gap_winding;
    end
end

% Plot comparison
fig2 = figure('Name', 'Insulation Requirements', 'Position', [150 150 800 500]);
plot(voltage_levels, gap_matrix(:,1) * 1e3, 'b-o', 'LineWidth', 2, 'DisplayName', 'Basic');
hold on;
plot(voltage_levels, gap_matrix(:,2) * 1e3, 'g-s', 'LineWidth', 2, 'DisplayName', 'Supplementary');
plot(voltage_levels, gap_matrix(:,3) * 1e3, 'r-^', 'LineWidth', 2, 'DisplayName', 'Reinforced');
grid on;
xlabel('Voltage Difference (V)', 'FontSize', 11);
ylabel('Inter-winding Gap (mm)', 'FontSize', 11);
title('OpenMagnetics Spacing vs Voltage & Insulation Class', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'northwest');

fprintf('Comparison table:\n');
fprintf('V_diff (V) | Basic | Suppl | Reinf\n');
fprintf('-----------|-------|-------|-------\n');
for i = 1:length(voltage_levels)
    fprintf('%10d | %5.2f | %5.2f | %5.2f mm\n', voltage_levels(i), ...
        gap_matrix(i,1)*1e3, gap_matrix(i,2)*1e3, gap_matrix(i,3)*1e3);
end

fprintf('\n===================================================================\n');
fprintf('   Demonstration Complete\n');
fprintf('===================================================================\n');

%% Helper Function: Plot Transformer Cross-Section

function plot_transformer_cross_section(conductors, winding_map, width, height)
    % Plot transformer cross-section

    hold on;
    axis equal;

    % Colors for different windings
    colors = [0.3 0.5 0.9;   % Blue for primary
             0.9 0.3 0.3];   % Red for secondary

    % Draw each conductor
    for i = 1:size(conductors, 1)
        x = conductors(i, 1);
        y = conductors(i, 2);
        w = conductors(i, 3);
        h = conductors(i, 4);

        winding_id = winding_map.winding_id(i);
        color = colors(min(winding_id, size(colors, 1)), :);

        % Draw rectangle
        rectangle('Position', [x-w/2, y-h/2, w, h]*1e3, ...
            'FaceColor', color, 'EdgeColor', color*0.6, 'LineWidth', 0.5);
    end

    % Add winding labels
    unique_windings = unique(winding_map.winding_id);
    for w = unique_windings'
        idx = find(winding_map.winding_id == w);
        y_mid = mean(conductors(idx, 2)) * 1e3;

        winding_name = sprintf('W%d', w);
        text(2, y_mid, winding_name, 'FontSize', 10, 'FontWeight', 'bold');
    end

    % Measure and annotate inter-winding gap
    if length(unique_windings) > 1
        for w = 1:(length(unique_windings)-1)
            idx1 = find(winding_map.winding_id == unique_windings(w));
            idx2 = find(winding_map.winding_id == unique_windings(w+1));

            y_top_1 = max(conductors(idx1, 2) + height/2) * 1e3;
            y_bot_2 = min(conductors(idx2, 2) - height/2) * 1e3;

            gap = y_bot_2 - y_top_1;

            % Draw gap measurement
            x_arrow = -1.5;
            plot([x_arrow x_arrow], [y_top_1 y_bot_2], 'k-', 'LineWidth', 1);
            text(x_arrow - 0.5, (y_top_1 + y_bot_2)/2, ...
                sprintf('%.2f mm', gap), ...
                'FontSize', 8, 'HorizontalAlignment', 'right');
        end
    end

    grid on;
    xlim([-3, 4]);
end
