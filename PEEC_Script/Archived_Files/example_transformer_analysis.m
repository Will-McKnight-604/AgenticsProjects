%example_transformer_analysis

%% ================== Transformer Loss Analysis Example ==================
clear; clc; close all;

%% ================== USER INPUTS ==================
% Discretization
Nx = 8;        % filaments per conductor (x)
Ny = 8;        % filaments per conductor (y)

% Conductor geometry
width  = 2e-3;       % m (conductor width)
height = 0.5e-3;     % m (conductor height)
gap_layer = 0.3e-3;  % m (gap between layers)
gap_turn  = 0.1e-3;  % m (gap between turns)

% Frequency
f = 100e3;  % Hz

% Material
sigma = 5.8e7;     % Copper conductivity (S/m)
mu0   = 4*pi*1e-7; % Permeability (H/m)

%% ================== DEFINE TRANSFORMER WINDINGS ==================
% winding_config format: {winding_id, N_turns, N_layers, I_rms, phase_deg}

% Example 1: Simple 1:2 transformer
% Primary: 10 turns in 2 layers, 10A
% Secondary: 20 turns in 4 layers, 5A, 180° phase shift
winding_config = {
    {1, 10, 2, 10.0, 0};      % Primary winding
    {2, 20, 4, 5.0, 180}      % Secondary winding
};

% Example 2: Multi-winding transformer (uncomment to try)
% winding_config = {
%     {1, 8, 2, 15.0, 0};       % Primary: 8 turns, 2 layers, 15A
%     {2, 16, 2, 7.5, 180};     % Secondary 1: 16 turns, 2 layers, 7.5A
%     {3, 24, 3, 5.0, 180}      % Secondary 2: 24 turns, 3 layers, 5A
% };

fprintf('\n=== TRANSFORMER CONFIGURATION ===\n');
for w = 1:length(winding_config)
    cfg = winding_config{w};
    fprintf('Winding %d: %d turns, %d layers, %.1f Arms @ %.0f°\n', ...
            cfg{1}, cfg{2}, cfg{3}, cfg{4}, cfg{5});
end

%% ================== BUILD GEOMETRY ==================
fprintf('\nBuilding transformer geometry...\n');

[conductors, winding_map] = build_transformer_geometry(...
    winding_config, width, height, gap_layer, gap_turn);

fprintf('  Total conductors (turns): %d\n', size(conductors,1));
fprintf('  Total windings: %d\n', length(unique(winding_map.winding_id)));

% Build PEEC geometry
geom = peec_build_geometry(conductors, winding_map, sigma, mu0, Nx, Ny);

fprintf('  Total filaments: %d\n', geom.Nf);

%% ================== SOLVE AND ANALYZE ==================
fprintf('\nSolving PEEC at %.1f kHz...\n', f/1e3);

results = peec_solve_frequency(geom, conductors, f, sigma, mu0);

% Display comprehensive results
display_transformer_losses(results, geom, f);

%% ================== VISUALIZE RESULTS ==================

% Plot 1: Current density distribution
figure('Name', 'Transformer Field Analysis', 'Position', [100 100 1400 500]);

subplot(1,3,1);
plot_current_density(geom, results);
title(sprintf('Current Density @ %.1f kHz', f/1e3));

% Add winding labels
hold on;
for w = 1:length(winding_config)
    cfg = winding_config{w};
    winding_id = cfg{1};

    % Find conductors for this winding
    cond_idx = find(winding_map.winding_id == winding_id);

    % Get y-position range
    y_positions = conductors(cond_idx, 2);
    y_center = mean(y_positions);

    text(-0.5e-3, y_center, sprintf('W%d', winding_id), ...
        'FontSize', 12, 'FontWeight', 'bold', 'Color', 'k');
end
hold off;

% Plot 2: Loss density
subplot(1,3,2);
plot_loss_density(geom, results);
title(sprintf('Loss Density (Total: %.2f W)', results.P_total));

% Plot 3: Per-winding comparison
subplot(1,3,3);
if ~isempty(results.winding)
    bar(results.winding.ids, results.winding.P, 'FaceColor', [0.8 0.3 0.3]);
    xlabel('Winding ID');
    ylabel('Power Loss [W]');
    title('Loss per Winding');
    grid on;

    % Add percentage labels
    for w = 1:length(results.winding.ids)
        pct = 100 * results.winding.P(w) / results.P_total;
        text(results.winding.ids(w), results.winding.P(w), ...
            sprintf('%.1f%%\n(%d turns)', pct, results.winding.N_turns(w)), ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', ...
            'FontSize', 9);
    end
end

%% ================== FREQUENCY SWEEP (Optional) ==================
fprintf('\n=== FREQUENCY SWEEP ===\n');
fprintf('Running frequency sweep...\n');

f_sweep = logspace(3, 6, 30);  % 1 kHz to 1 MHz
N_windings = length(winding_config);

P_vs_f = zeros(N_windings, length(f_sweep));
Fr_vs_f = zeros(N_windings, length(f_sweep));

for idx = 1:length(f_sweep)
    res = peec_solve_frequency(geom, conductors, f_sweep(idx), sigma, mu0);

    if ~isempty(res.winding)
        P_vs_f(:, idx) = res.winding.P;
        Fr_vs_f(:, idx) = res.winding.Fr;
    end

    if mod(idx, 5) == 0
        fprintf('  Progress: %d/%d\n', idx, length(f_sweep));
    end
end

% Plot frequency sweep results
figure('Name', 'Frequency Sweep Analysis', 'Position', [100 100 1200 400]);

subplot(1,2,1);
loglog(f_sweep/1e3, P_vs_f', 'LineWidth', 2);
xlabel('Frequency [kHz]');
ylabel('Power Loss [W]');
title('Winding Loss vs Frequency');
grid on;
legend_str = cell(N_windings, 1);
for w = 1:N_windings
    legend_str{w} = sprintf('Winding %d', winding_config{w}{1});
end
legend(legend_str, 'Location', 'northwest');

subplot(1,2,2);
semilogx(f_sweep/1e3, Fr_vs_f', 'LineWidth', 2);
xlabel('Frequency [kHz]');
ylabel('Proximity Factor (F_r)');
title('AC/DC Resistance Ratio vs Frequency');
grid on;
legend(legend_str, 'Location', 'northwest');

%% ================== TURN-BY-TURN ANALYSIS ==================
plot_turn_by_turn_analysis(results, geom, f);

fprintf('\nAnalysis complete!\n');
