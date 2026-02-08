% plot_loss_density.m - Octave-compatible, works in subplots
function plot_loss_density(geom, results)

    fil = geom.filaments;
    P   = results.P_fil;

    % Get current axes handle
    ax = gca;

    cla(ax);
    hold(ax, 'on');
    axis(ax, 'equal');
    box(ax, 'on');

    xlabel(ax, 'x (m)');
    ylabel(ax, 'y (m)');

    % Calculate power density
    % fil columns: [x, y, dx, dy, conductor_idx, winding_idx, I_complex]
    pdens = P ./ (fil(:,3) .* fil(:,4));
    pmax  = max(pdens);

    if pmax == 0
        pmax = 1;  % Avoid division by zero
    end

    cmap = hot(256);

    % Get wire shape info if available
    use_shapes = isfield(geom, 'wire_shapes') && ~isempty(geom.wire_shapes);

    % Plot each filament
    for i = 1:length(pdens)
        cidx = max(1, min(256, round(255 * pdens(i) / pmax) + 1));
        color = cmap(cidx,:);

        x_center = fil(i,1);
        y_center = fil(i,2);
        dx = fil(i,3);
        dy = fil(i,4);

        % Determine wire shape from conductor index
        if use_shapes && size(fil,2) >= 5
            conductor_idx = fil(i,5);

            if conductor_idx <= length(geom.wire_shapes)
                wire_shape = geom.wire_shapes{conductor_idx};

                if strcmp(wire_shape, 'round')
                    % Draw as circle
                    radius = sqrt(dx * dy) / 2;
                    theta = linspace(0, 2*pi, 20);
                    x_circle = x_center + radius * cos(theta);
                    y_circle = y_center + radius * sin(theta);
                    fill(ax, x_circle, y_circle, color, 'EdgeColor', 'none');
                else
                    % Draw as rectangle
                    rectangle('Parent', ax, 'Position', [x_center-dx/2, y_center-dy/2, dx, dy], ...
                             'FaceColor', color, 'EdgeColor', 'none');
                end
            else
                % Default to rectangle
                rectangle('Parent', ax, 'Position', [x_center-dx/2, y_center-dy/2, dx, dy], ...
                         'FaceColor', color, 'EdgeColor', 'none');
            end
        else
            % No shape info, use rectangles
            rectangle('Parent', ax, 'Position', [x_center-dx/2, y_center-dy/2, dx, dy], ...
                     'FaceColor', color, 'EdgeColor', 'none');
        end
    end

    % Set colormap for this axes
    colormap(ax, hot);

    % Add colorbar - use try/catch for Octave compatibility
    try
        cb = colorbar(ax);
        ylabel(cb, 'P (W/m^2)');
    catch
        colorbar;
    end

    % Set color axis limits
    try
        caxis(ax, [0 pmax]);
    catch
        caxis([0 pmax]);
    end

    % Overlay hotspots
    try
        hs = identify_hotspots(geom, results, 5);
        for k = 1:length(hs)
            plot(ax, hs(k).x, hs(k).y, 'cx', 'MarkerSize', 12, 'LineWidth', 2);
        end
    catch
        % identify_hotspots not available, skip
    end

    hold(ax, 'off');
end
