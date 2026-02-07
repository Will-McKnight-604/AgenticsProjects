% demo_winding_layout_calculator.m
% Demonstrate winding layout calculation using OpenMagnetics approach

clear; clc; close all;

fprintf('=== WINDING LAYOUT CALCULATOR DEMO ===\n\n');

% Initialize API
api = openmagnetics_api_interface();
api.get_wires();
api.get_cores();

% Create layout calculator
calculator = openmagnetics_winding_layout(api);

%% Example 1: Layered winding (your current approach)
fprintf('\n--- Example 1: LAYERED WINDING ---\n');
layout1 = calculator.calculate_winding_layout('E_65_32_27', 'AWG_22', 50, 'layered');

%% Example 2: Orthocyclic winding (best packing)
fprintf('\n--- Example 2: ORTHOCYCLIC WINDING ---\n');
layout2 = calculator.calculate_winding_layout('E_65_32_27', 'AWG_22', 50, 'orthocyclic');

%% Example 3: Random winding (worst case)
fprintf('\n--- Example 3: RANDOM WINDING ---\n');
layout3 = calculator.calculate_winding_layout('E_65_32_27', 'AWG_22', 50, 'random');

%% Comparison
fprintf('\n=== COMPARISON ===\n');
fprintf('Pattern         Layers  Fill Factor  Width Used  Fits?\n');
fprintf('--------------------------------------------------------\n');

fits1 = 'Yes'; if ~layout1.fits, fits1 = 'No'; end
fits2 = 'Yes'; if ~layout2.fits, fits2 = 'No'; end
fits3 = 'Yes'; if ~layout3.fits, fits3 = 'No'; end

fprintf('Layered         %5d    %5.1f%%      %5.1f mm    %s\n', ...
    layout1.n_layers, layout1.fill_factor*100, layout1.required_width*1e3, fits1);
fprintf('Orthocyclic     %5d    %5.1f%%      %5.1f mm    %s\n', ...
    layout2.n_layers, layout2.fill_factor*100, layout2.required_width*1e3, fits2);
fprintf('Random          %5d    %5.1f%%      %5.1f mm    %s\n', ...
    layout3.n_layers, layout3.fill_factor*100, layout3.required_width*1e3, fits3);

%% Visualize all three
fprintf('\nGenerating visualizations...\n');

figure('Name', 'Winding Pattern Comparison', 'Position', [50 50 1400 400]);

ax1 = subplot(1,3,1);
calculator.visualize_layout(layout1, ax1);

ax2 = subplot(1,3,2);
calculator.visualize_layout(layout2, ax2);

ax3 = subplot(1,3,3);
calculator.visualize_layout(layout3, ax3);

%% Test with Litz wire
fprintf('\n--- Example 4: LITZ WIRE ---\n');
layout4 = calculator.calculate_winding_layout('E_65_32_27', 'Litz_100_38', 30, 'layered');

fprintf('\n=== DEMO COMPLETE ===\n');
fprintf('Key Insights:\n');
fprintf('  - Orthocyclic packing gives ~16%% more turns in same space\n');
fprintf('  - Layered is easier to manufacture\n');
fprintf('  - Random has 30%% worse utilization\n');
fprintf('  - Litz wire has larger OD, fewer turns fit\n');
