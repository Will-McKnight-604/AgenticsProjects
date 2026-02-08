%compare_windings
%function compare_windings(geomA, condA, geomB, condB, f)
%{
function  compare_windings(geom_A, conductors_A, geom_B, conductors_B, f_single, sigma, mu0);

    resA = peec_solve_frequency(geom_A, conductors_A, f_single, sigma, mu0);
    resB = peec_solve_frequency(geom_B, conductors_B, f_single, sigma, mu0);





    figure('Name','Winding Comparison','Position',[100 100 1000 400]);

    subplot(2,2,1);
    plot_current_density(geom_A, resA);
    title('Layout A – Current');

    subplot(2,2,2);
    plot_current_density(geom_B, resB);
    title('Layout B – Current');

    subplot(2,2,3);
    plot_loss_density(geom_A, resA);
    title(sprintf('Layout A – Loss (%.1f W)',resA.P_total));

    subplot(2,2,4);
    plot_loss_density(geom_B, resB);
    title(sprintf('Layout B – Loss (%.1f W)',resB.P_total));
end

%}

%compare_windings
function compare_windings(geom_A, conductors_A, geom_B, conductors_B, f_single, sigma, mu0)

    resA = peec_solve_frequency(geom_A, conductors_A, f_single, sigma, mu0);
    resB = peec_solve_frequency(geom_B, conductors_B, f_single, sigma, mu0);

    figure('Name','Winding Comparison','Position',[100 100 1400 800]);

    % Top row: Current density plots
    subplot(3,2,1);
    plot_current_density(geom_A, resA);
    title('Layout A – Current');

    subplot(3,2,2);
    plot_current_density(geom_B, resB);
    title('Layout B – Current');

    % Middle row: Loss density plots
    subplot(3,2,3);
    plot_loss_density(geom_A, resA);
    title(sprintf('Layout A – Loss (%.1f W)',resA.P_total));

    subplot(3,2,4);
    plot_loss_density(geom_B, resB);
    title(sprintf('Layout B – Loss (%.1f W)',resB.P_total));

    % Bottom row: Per-winding comparison
    Nc = length(resA.P_winding);
    winding_num = 1:Nc;

    subplot(3,2,5);
    bar_width = 0.35;
    hold on;
    bar(winding_num - bar_width/2, resA.P_winding, bar_width, ...
        'FaceColor', [0.8 0.3 0.3], 'DisplayName', 'Layout A');
    bar(winding_num + bar_width/2, resB.P_winding, bar_width, ...
        'FaceColor', [0.3 0.6 0.9], 'DisplayName', 'Layout B');
    xlabel('Winding Number');
    ylabel('Power Loss [W]');
    title('Per-Winding Loss Comparison');
    legend('Location', 'best');
    grid on;
    hold off;

    subplot(3,2,6);
    hold on;
    bar(winding_num - bar_width/2, resA.Fr, bar_width, ...
        'FaceColor', [0.8 0.3 0.3], 'DisplayName', 'Layout A');
    bar(winding_num + bar_width/2, resB.Fr, bar_width, ...
        'FaceColor', [0.3 0.6 0.9], 'DisplayName', 'Layout B');
    plot([0.5 Nc+0.5], [1 1], 'k--', 'LineWidth', 1, 'DisplayName', 'DC baseline');
    xlabel('Winding Number');
    ylabel('F_r = R_{AC} / R_{DC}');
    title('Proximity Factor Comparison');
    legend('Location', 'best');
    grid on;
    hold off;
end
