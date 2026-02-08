%plot_turn_by_turn_analysis
%{
function plot_turn_by_turn_analysis(results, geom, f)
% Visualize loss distribution across turns and layers
%
% Inputs:
%   results - Results structure from peec_solve_frequency
%   geom    - Geometry structure (contains winding_map)
%   f       - Frequency [Hz]

    if ~isfield(geom, 'winding_map') || isempty(geom.winding_map)
        fprintf('No winding map available - cannot create turn-by-turn analysis\n');
        return;
    end

    winding_map = geom.winding_map;
    unique_windings = unique(winding_map.winding_id);
    N_windings = length(unique_windings);

    figure('Name', 'Turn-by-Turn Loss Analysis', ...
           'Position', [100 100, 400*N_windings, 800]);

    for w_idx = 1:N_windings
        winding_id = unique_windings(w_idx);

        % Find all conductors for this winding
        cond_indices = find(winding_map.winding_id == winding_id);

        % Extract data
        turn_nums = winding_map.turn_num(cond_indices);
        layer_nums = winding_map.layer_num(cond_indices);
        P_turns = results.conductor.P(cond_indices);
        Fr_turns = results.conductor.Fr(cond_indices);

        % Plot 1: Loss per turn
        subplot(3, N_windings, w_idx);
        bar(turn_nums, P_turns, 'FaceColor', [0.8 0.3 0.3]);
        xlabel('Turn Number');
        ylabel('Loss [W]');
        title(sprintf('Winding %d: Loss per Turn', winding_id));
        grid on;

        % Highlight which layer each turn is in with colors
        hold on;
        unique_layers = unique(layer_nums);
        colors = lines(length(unique_layers));
        for L = 1:length(unique_layers)
            layer_id = unique_layers(L);
            turns_in_layer = turn_nums(layer_nums == layer_id);
            P_in_layer = P_turns(layer_nums == layer_id);
            bar(turns_in_layer, P_in_layer, 'FaceColor', colors(L,:));
        end
        hold off;

        % Plot 2: Proximity factor per turn
        subplot(3, N_windings, N_windings + w_idx);
        bar(turn_nums, Fr_turns, 'FaceColor', [0.4 0.7 0.4]);
        xlabel('Turn Number');
        ylabel('F_r');
        title(sprintf('Winding %d: Proximity Factor', winding_id));
        grid on;
        hold on;
        plot([min(turn_nums)-0.5, max(turn_nums)+0.5], [1 1], 'r--', 'LineWidth', 1.5);
        hold off;

        % Plot 3: Loss distribution by layer
        subplot(3, N_windings, 2*N_windings + w_idx);
        P_by_layer = zeros(length(unique_layers), 1);
        for L = 1:length(unique_layers)
            layer_id = unique_layers(L);
            P_by_layer(L) = sum(P_turns(layer_nums == layer_id));
        end
        bar(unique_layers, P_by_layer, 'FaceColor', [0.3 0.6 0.9]);
        xlabel('Layer Number');
        ylabel('Total Loss [W]');
        title(sprintf('Winding %d: Loss per Layer', winding_id));
        grid on;

        % Add percentage labels
        for L = 1:length(unique_layers)
            pct = 100 * P_by_layer(L) / sum(P_by_layer);
            text(unique_layers(L), P_by_layer(L), sprintf('%.1f%%', pct), ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'bottom', ...
                'FontSize', 9);
        end
    end

    % Add overall title
    sgtitle(sprintf('Turn-by-Turn Analysis @ %.1f kHz', f/1e3), ...
            'FontSize', 14, 'FontWeight', 'bold');
end

%}

% plot_turn_by_turn_analysis.m - Compatible with older MATLAB/Octave
function plot_turn_by_turn_analysis(geom, results, N_turns, f)

    % Get number of filaments (robust method)
    if isfield(geom, 'Nf') && ~isempty(geom.Nf)
        Nf = geom.Nf;
    elseif isfield(geom, 'filaments') && ~isempty(geom.filaments)
        Nf = size(geom.filaments, 1);
    else
        error('Cannot determine number of filaments from geometry structure');
    end

    % Calculate loss per turn
    fils_per_turn = Nf / N_turns;
    loss_per_turn = zeros(N_turns, 1);

    for k = 1:N_turns
        idx_start = round((k-1)*fils_per_turn + 1);
        idx_end = round(k*fils_per_turn);
        loss_per_turn(k) = sum(results.P_fil(idx_start:idx_end));
    end

    % Create figure
    fig = figure('Name', sprintf('Turn-by-Turn Analysis @ %.0f kHz', f/1e3), ...
                 'Position', [100 100 1400 900]);

    % Main title using annotation (compatible alternative to sgtitle)
    annotation('textbox', [0 0.96 1 0.04], ...
               'String', sprintf('Turn-by-Turn Loss Analysis @ %.0f kHz', f/1e3), ...
               'EdgeColor', 'none', ...
               'HorizontalAlignment', 'center', ...
               'FontSize', 14, ...
               'FontWeight', 'bold');

    % Plot 1: Current density
    subplot(2,3,1);
    plot_current_density(geom, results);
    title('Current Density Distribution');

    % Plot 2: Loss density
    subplot(2,3,2);
    plot_loss_density(geom, results);
    title('Loss Density Distribution');

    % Plot 3: Loss per turn (bar chart)
    subplot(2,3,3);
    bar(1:N_turns, loss_per_turn*1e3, 'FaceColor', [0.2 0.6 0.8]);
    xlabel('Turn Number');
    ylabel('Loss (mW)');
    title('Loss per Turn');
    grid on;

    % Plot 4: Cumulative loss
    subplot(2,3,4);
    cumulative_loss = cumsum(loss_per_turn);
    plot(1:N_turns, cumulative_loss*1e3, 'LineWidth', 2, 'Color', [0.8 0.2 0.2]);
    hold on;
    plot(1:N_turns, cumulative_loss*1e3, 'o', 'MarkerSize', 6, ...
         'MarkerFaceColor', [0.8 0.2 0.2], 'MarkerEdgeColor', 'k');
    xlabel('Turn Number');
    ylabel('Cumulative Loss (mW)');
    title('Cumulative Loss Distribution');
    grid on;

    % Plot 5: Loss ratio (normalized to minimum)
    subplot(2,3,5);
    min_loss = min(loss_per_turn);
    loss_ratio = loss_per_turn / min_loss;
    bar(1:N_turns, loss_ratio, 'FaceColor', [0.9 0.5 0.1]);
    xlabel('Turn Number');
    ylabel('Normalized Loss');
    title('Relative Loss per Turn (normalized to minimum)');
    grid on;
    ylim([0 max(loss_ratio)*1.1]);

    % Plot 6: Statistics table
    subplot(2,3,6);
    axis off;

    % Calculate statistics
    total_loss = sum(loss_per_turn);
    avg_loss = mean(loss_per_turn);
    max_loss = max(loss_per_turn);
    min_loss_val = min(loss_per_turn);
    std_loss = std(loss_per_turn);

    [~, max_idx] = max(loss_per_turn);
    [~, min_idx] = min(loss_per_turn);

    % Create text summary
    y_pos = 0.9;
    dy = 0.08;

    text(0.05, y_pos, 'Loss Statistics:', 'FontSize', 12, 'FontWeight', 'bold');
    y_pos = y_pos - dy;

    text(0.05, y_pos, sprintf('Total Loss: %.4f mW', total_loss*1e3), 'FontSize', 10);
    y_pos = y_pos - dy;

    text(0.05, y_pos, sprintf('Average Loss: %.4f mW', avg_loss*1e3), 'FontSize', 10);
    y_pos = y_pos - dy;

    text(0.05, y_pos, sprintf('Maximum Loss: %.4f mW (Turn %d)', max_loss*1e3, max_idx), 'FontSize', 10);
    y_pos = y_pos - dy;

    text(0.05, y_pos, sprintf('Minimum Loss: %.4f mW (Turn %d)', min_loss_val*1e3, min_idx), 'FontSize', 10);
    y_pos = y_pos - dy;

    text(0.05, y_pos, sprintf('Std Deviation: %.4f mW', std_loss*1e3), 'FontSize', 10);
    y_pos = y_pos - dy;

    text(0.05, y_pos, sprintf('Max/Min Ratio: %.2f', max_loss/min_loss_val), 'FontSize', 10);
    y_pos = y_pos - dy*1.5;

    % Identify which turns have highest losses
    text(0.05, y_pos, 'Hotspot Turns:', 'FontSize', 11, 'FontWeight', 'bold');
    y_pos = y_pos - dy;

    [sorted_loss, sorted_idx] = sort(loss_per_turn, 'descend');
    n_show = min(5, N_turns);

    for k = 1:n_show
        turn_num = sorted_idx(k);
        text(0.05, y_pos, sprintf('  Turn %d: %.4f mW (%.1f%%)', ...
             turn_num, sorted_loss(k)*1e3, sorted_loss(k)/total_loss*100), ...
             'FontSize', 9);
        y_pos = y_pos - dy*0.8;
    end

end

