% compare_all_filar_configs.m
% Automatically compare different multi-filar configurations for 2:1 transformer
% No user input required - runs all combinations

clear; clc; close all;

fprintf('=== AUTOMATIC MULTI-FILAR COMPARISON ===\n');
fprintf('Testing all filar combinations for 2:1 transformer\n\n');

%% Configuration
sigma = 5.8e7;
mu0 = 4*pi*1e-7;
width = 2e-3;
height = 1e-3;
gap_layer = 0.2e-3;
gap_filar = 0.15e-3;

% Transformer spec
N1 = 10;  % Primary turns
N2 = 5;   % Secondary turns (2:1 ratio)
I1 = 10;  % Primary current
I2 = 5;   % Secondary current
f = 100e3; % 100 kHz

Nx = 6;
Ny = 6;

filar_names = {'Single', 'Bi', 'Tri', 'Quad'};

% Test configurations
configs_to_test = [
    1, 1;  % Single-Single
    2, 1;  % Bi-Single
    1, 2;  % Single-Bi
    2, 2;  % Bi-Bi
    3, 3;  % Tri-Tri
    2, 3;  % Bi-Tri
    3, 2;  % Tri-Bi
];

n_configs = size(configs_to_test, 1);
results_table = zeros(n_configs, 6);  % Store results

fprintf('Testing %d configurations...\n\n', n_configs);

%% Run all configurations
for cfg = 1:n_configs
    pri_filar = configs_to_test(cfg, 1);
    sec_filar = configs_to_test(cfg, 2);

    fprintf('[%d/%d] Testing: Primary=%s, Secondary=%s\n', ...
        cfg, n_configs, filar_names{pri_filar}, filar_names{sec_filar});

    % Build primary
    config_pri.n_filar = pri_filar;
    config_pri.n_turns = N1;
    config_pri.n_windings = 1;
    config_pri.width = width;
    config_pri.height = height;
    config_pri.gap_layer = gap_layer;
    config_pri.gap_filar = gap_filar;
    config_pri.currents = I1;
    config_pri.phases = 0;
    config_pri.x_offset = 0;

    [cond_pri, map_pri] = build_multifilar_winding(config_pri);

    % Calculate primary width
    if pri_filar == 1
        pri_width = width;
    else
        pri_width = pri_filar * width + (pri_filar - 1) * gap_filar;
    end

    % Build secondary
    config_sec.n_filar = sec_filar;
    config_sec.n_turns = N2;
    config_sec.n_windings = 1;
    config_sec.width = width;
    config_sec.height = height;
    config_sec.gap_layer = gap_layer;
    config_sec.gap_filar = gap_filar;
    config_sec.currents = I2;
    config_sec.phases = 180;

    if sec_filar == 1
        sec_width = width;
    else
        sec_width = sec_filar * width + (sec_filar - 1) * gap_filar;
    end

    config_sec.x_offset = pri_width/2 + 1e-3 + sec_width/2;

    [cond_sec, map_sec] = build_multifilar_winding(config_sec);

    % Combine
    conductors = [cond_pri; cond_sec];
    winding_map = [map_pri; map_sec + 1];

    % Build and solve
    geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny, winding_map);
    results = peec_solve_frequency(geom, conductors, f, sigma, mu0);

    % Calculate per-winding losses
    fils_per_cond = Nx * Ny;
    n_cond_pri = size(cond_pri, 1);
    n_cond_sec = size(cond_sec, 1);

    loss_pri = 0;
    for c = 1:n_cond_pri
        idx_start = (c-1) * fils_per_cond + 1;
        idx_end = c * fils_per_cond;
        loss_pri = loss_pri + sum(results.P_fil(idx_start:idx_end));
    end

    loss_sec = 0;
    for c = 1:n_cond_sec
        idx_start = n_cond_pri * fils_per_cond + (c-1) * fils_per_cond + 1;
        idx_end = n_cond_pri * fils_per_cond + c * fils_per_cond;
        loss_sec = loss_sec + sum(results.P_fil(idx_start:idx_end));
    end

    % DC losses
    A = width * height;
    Pdc_pri = 0.5 * I1^2 * (N1 / pri_filar) / (sigma * A);
    Pdc_sec = 0.5 * I2^2 * (N2 / sec_filar) / (sigma * A);

    % Store results
    results_table(cfg, 1) = loss_pri;
    results_table(cfg, 2) = loss_sec;
    results_table(cfg, 3) = results.P_total;
    results_table(cfg, 4) = loss_pri / Pdc_pri;
    results_table(cfg, 5) = loss_sec / Pdc_sec;
    results_table(cfg, 6) = results.P_total / (Pdc_pri + Pdc_sec);

    fprintf('      Loss: Primary=%.4f W, Secondary=%.4f W, Total=%.4f W\n', ...
        loss_pri, loss_sec, results.P_total);
end

%% Display results table
fprintf('\n=== RESULTS SUMMARY @ %.0f kHz ===\n\n', f/1e3);
fprintf('Config          Primary    Secondary   Total      Pri        Sec        Total\n');
fprintf('                Loss (W)   Loss (W)    Loss (W)   Rac/Rdc    Rac/Rdc    Rac/Rdc\n');
fprintf('-----------------------------------------------------------------------------------\n');

for cfg = 1:n_configs
    config_name = sprintf('%s-%s', ...
        filar_names{configs_to_test(cfg,1)}, ...
        filar_names{configs_to_test(cfg,2)});

    fprintf('%-15s %.6f   %.6f    %.6f   %.3f      %.3f      %.3f\n', ...
        config_name, ...
        results_table(cfg, 1), ...
        results_table(cfg, 2), ...
        results_table(cfg, 3), ...
        results_table(cfg, 4), ...
        results_table(cfg, 5), ...
        results_table(cfg, 6));
end

%% Find best configurations
[~, idx_min_total] = min(results_table(:,3));
[~, idx_min_pri] = min(results_table(:,1));
[~, idx_min_sec] = min(results_table(:,2));

fprintf('\n=== BEST CONFIGURATIONS ===\n');
fprintf('Lowest total loss:     %s-%s (%.6f W)\n', ...
    filar_names{configs_to_test(idx_min_total,1)}, ...
    filar_names{configs_to_test(idx_min_total,2)}, ...
    results_table(idx_min_total,3));

fprintf('Lowest primary loss:   %s-%s (%.6f W)\n', ...
    filar_names{configs_to_test(idx_min_pri,1)}, ...
    filar_names{configs_to_test(idx_min_pri,2)}, ...
    results_table(idx_min_pri,1));

fprintf('Lowest secondary loss: %s-%s (%.6f W)\n', ...
    filar_names{configs_to_test(idx_min_sec,1)}, ...
    filar_names{configs_to_test(idx_min_sec,2)}, ...
    results_table(idx_min_sec,2));

%% Visualize comparison
figure('Name', 'Multi-filar Configuration Comparison', 'Position', [50 50 1400 800]);

annotation('textbox', [0 0.96 1 0.04], ...
    'String', 'Multi-filar Configuration Comparison @ 100 kHz', ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
    'FontSize', 14, 'FontWeight', 'bold');

% Total loss comparison
subplot(2,3,1);
bar(results_table(:,3)*1e3);
set(gca, 'XTickLabel', arrayfun(@(i) sprintf('%s-%s', ...
    filar_names{configs_to_test(i,1)}, ...
    filar_names{configs_to_test(i,2)}), 1:n_configs, 'UniformOutput', false));
xtickangle(45);
ylabel('Total Loss (mW)');
title('Total Loss by Configuration');
grid on;

% Primary vs Secondary loss
subplot(2,3,2);
bar([results_table(:,1), results_table(:,2)]*1e3);
set(gca, 'XTickLabel', arrayfun(@(i) sprintf('%s-%s', ...
    filar_names{configs_to_test(i,1)}, ...
    filar_names{configs_to_test(i,2)}), 1:n_configs, 'UniformOutput', false));
xtickangle(45);
ylabel('Loss (mW)');
legend('Primary', 'Secondary', 'Location', 'best');
title('Primary vs Secondary Loss');
grid on;

% Rac/Rdc comparison
subplot(2,3,3);
bar(results_table(:,6));
set(gca, 'XTickLabel', arrayfun(@(i) sprintf('%s-%s', ...
    filar_names{configs_to_test(i,1)}, ...
    filar_names{configs_to_test(i,2)}), 1:n_configs, 'UniformOutput', false));
xtickangle(45);
ylabel('R_{AC}/R_{DC}');
title('Total Rac/Rdc Factor');
grid on;

% Loss reduction vs Single-Single
subplot(2,3,4);
baseline_loss = results_table(1,3);  % Single-Single
reduction = (1 - results_table(:,3)/baseline_loss) * 100;
bar(reduction);
set(gca, 'XTickLabel', arrayfun(@(i) sprintf('%s-%s', ...
    filar_names{configs_to_test(i,1)}, ...
    filar_names{configs_to_test(i,2)}), 1:n_configs, 'UniformOutput', false));
xtickangle(45);
ylabel('Loss Reduction (%)');
title('Improvement vs Single-Single');
grid on;

% Scatter: Primary filar vs loss
subplot(2,3,5);
scatter(configs_to_test(:,1), results_table(:,1)*1e3, 100, 'filled');
xlabel('Primary Filar Number');
ylabel('Primary Loss (mW)');
title('Primary Loss vs Filar Count');
grid on;
xlim([0.5 4.5]);
set(gca, 'XTick', 1:4, 'XTickLabel', {'1', '2', '3', '4'});

% Scatter: Secondary filar vs loss
subplot(2,3,6);
scatter(configs_to_test(:,2), results_table(:,2)*1e3, 100, 'filled', 'MarkerFaceColor', 'r');
xlabel('Secondary Filar Number');
ylabel('Secondary Loss (mW)');
title('Secondary Loss vs Filar Count');
grid on;
xlim([0.5 4.5]);
set(gca, 'XTick', 1:4, 'XTickLabel', {'1', '2', '3', '4'});

fprintf('\n=== COMPARISON COMPLETE ===\n');
