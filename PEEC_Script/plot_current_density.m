% plot_current_density.m - Octave-compatible, works in subplots
function plot_current_density(geom, results)

    fil = geom.filaments;
    I   = results.I_fil;

    % Get current axes handle
    ax = gca;

    cla(ax);
    hold(ax, 'on');
    axis(ax, 'equal');
    box(ax, 'on');

    xlabel(ax, 'x (m)');
    ylabel(ax, 'y (m)');

    % Calculate current density magnitude in A/cm^2
    % fil areas are in m^2; 1 m^2 = 1e4 cm^2, so J(A/cm^2) = |I|/(area_m2 * 1e4)
    Jmag = abs(I) ./ (fil(:,3).*fil(:,4)) * 1e-4;
    Jmax = max(Jmag);

    if Jmax == 0
        Jmax = 1;  % Avoid division by zero
    end

    cmap = jet(256);

    % Get wire shape info if available
    use_shapes = isfield(geom, 'wire_shapes') && ~isempty(geom.wire_shapes);

    % Get winding color map (for conductor outlines by winding)
    winding_colors = {};
    if isfield(geom, 'winding_colors') && ~isempty(geom.winding_colors)
        winding_colors = geom.winding_colors;
    end
    winding_names = {};
    if isfield(geom, 'winding_names') && ~isempty(geom.winding_names)
        winding_names = geom.winding_names;
    end

    % Plot each filament
    for i = 1:length(Jmag)
        cidx = max(1, min(256, round(255 * Jmag(i) / Jmax) + 1));
        color = cmap(cidx,:);

        x_center = fil(i,1);
        y_center = fil(i,2);
        dx = fil(i,3);
        dy = fil(i,4);

        % Edge color by winding
        edge_color = 'none';
        if size(fil,2) >= 6 && ~isempty(winding_colors)
            widx = round(fil(i,6));
            if widx >= 1 && widx <= numel(winding_colors)
                edge_color = winding_colors{widx};
            end
        end

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
                    fill(ax, x_circle, y_circle, color, 'EdgeColor', edge_color, 'LineWidth', 0.5);
                else
                    % Draw as rectangle
                    rectangle('Parent', ax, 'Position', [x_center-dx/2, y_center-dy/2, dx, dy], ...
                             'FaceColor', color, 'EdgeColor', edge_color, 'LineWidth', 0.5);
                end
            else
                % Default to rectangle
                rectangle('Parent', ax, 'Position', [x_center-dx/2, y_center-dy/2, dx, dy], ...
                         'FaceColor', color, 'EdgeColor', edge_color, 'LineWidth', 0.5);
            end
        else
            % No shape info, use rectangles
            rectangle('Parent', ax, 'Position', [x_center-dx/2, y_center-dy/2, dx, dy], ...
                     'FaceColor', color, 'EdgeColor', 'none');
        end
    end

    % Draw winding window boundary if available
    if isfield(geom, 'window_meta') && isstruct(geom.window_meta)
        wm = geom.window_meta;
        if isfield(wm, 'local_bbox_m') && isstruct(wm.local_bbox_m)
            bb = wm.local_bbox_m;
            if isfield(bb, 'x_min') && isfield(bb, 'x_max') && isfield(bb, 'y_min') && isfield(bb, 'y_max')
                bx = [bb.x_min, bb.x_max, bb.x_max, bb.x_min, bb.x_min];
                by = [bb.y_min, bb.y_min, bb.y_max, bb.y_max, bb.y_min];
                plot(ax, bx, by, 'k--', 'LineWidth', 1.0);
            end
        end
    end

    % Draw winding legend entries (one marker per winding)
    if ~isempty(winding_names) && ~isempty(winding_colors)
        n_w = min(numel(winding_names), numel(winding_colors));
        leg_handles = zeros(1, n_w);
        for w = 1:n_w
            leg_handles(w) = plot(ax, NaN, NaN, 's', 'MarkerFaceColor', winding_colors{w}, ...
                'MarkerEdgeColor', winding_colors{w}, 'MarkerSize', 8);
        end
        try
            legend(ax, leg_handles, winding_names(1:n_w), 'Location', 'best', 'FontSize', 7);
        catch
        end
    end

    % Set colormap for this axes
    colormap(ax, jet);

    % Add colorbar - use try/catch for Octave compatibility
    try
        cb = colorbar(ax);
        ylabel(cb, 'J (A/cm^2)');
    catch
        colorbar;
    end

    % Set color axis limits
    try
        caxis(ax, [0 Jmax]);
    catch
        caxis([0 Jmax]);
    end

    hold(ax, 'off');
end
