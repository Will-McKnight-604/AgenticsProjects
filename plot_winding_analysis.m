%plot_winding_analysis
function plot_winding_analysis(results, f)
% Create comprehensive winding loss analysis plots
%
% Inputs:
%   results - Results structure from peec_solve_frequency
%   f       - Frequency [Hz]

    Nc = length(results.P_winding);
    winding_num = 1:Nc;

    figure('Name', 'Winding Loss Analysis', 'Position', [100 100 1200 400]);

    % Plot 1: Power loss per winding
    subplot(1,3,1);
    bar(winding_num, results.P_winding, 'FaceColor', [0.8 0.3 0.3]);
    xlabel('Winding Number');
    ylabel('Power Loss [W]');
    title(sprintf('Loss per Winding @ %.1f kHz', f/1e3));
    grid on;

    % Add percentage labels on bars
    for k = 1:Nc
        pct = 100 * results.P_winding(k) / results.P_total;
        text(k, results.P_winding(k), sprintf('%.1f%%', pct), ...
             'HorizontalAlignment', 'center', ...
             'VerticalAlignment', 'bottom', ...
             'FontSize', 9);
    end

    % Plot 2: AC vs DC resistance
    subplot(1,3,2);
    hold on;
    bar_width = 0.35;
    bar(winding_num - bar_width/2, results.R_dc_winding*1e3, bar_width, ...
        'FaceColor', [0.3 0.6 0.9], 'DisplayName', 'R_{DC}');
    bar(winding_num + bar_width/2, results.R_ac_winding*1e3, bar_width, ...
        'FaceColor', [0.9 0.5 0.2], 'DisplayName', 'R_{AC}');
    xlabel('Winding Number');
    ylabel('Resistance [mΩ]');
    title('AC vs DC Resistance');
    legend('Location', 'best');
    grid on;
    hold off;

    % Plot 3: Proximity factor (Fr)
    subplot(1,3,3);
    bar(winding_num, results.Fr, 'FaceColor', [0.4 0.7 0.4]);
    xlabel('Winding Number');
    ylabel('F_r = R_{AC} / R_{DC}');
    title('Proximity/Skin Effect Factor');
    grid on;

    % Add reference line at Fr = 1
    hold on;
    plot([0.5 Nc+0.5], [1 1], 'r--', 'LineWidth', 1.5);
    text(Nc*0.98, 1.1, 'DC baseline', ...
         'HorizontalAlignment', 'right', 'Color', 'r');
    hold off;

    % Add value labels
    for k = 1:Nc
        text(k, results.Fr(k), sprintf('%.2f', results.Fr(k)), ...
             'HorizontalAlignment', 'center', ...
             'VerticalAlignment', 'bottom', ...
             'FontSize', 9);
    end
end
