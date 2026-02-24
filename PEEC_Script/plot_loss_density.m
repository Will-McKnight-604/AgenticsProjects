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

    % Calculate power density in W/mm^2
    % fil areas are in m^2; 1 m^2 = 1e6 mm^2, so P(W/mm^2) = P/(area_m2 * 1e6)
    pdens = P ./ (fil(:,3) .* fil(:,4)) * 1e-6;
    pmax  = max(pdens);

    if pmax == 0
        pmax = 1;  % Avoid division by zero
    end

    cmap = hot(256);

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

    % ========== TIMING: Filament rendering (vectorized batch patch) ==========
    t_filament_start = tic;

    Nf = size(fil, 1);

    % Map each filament's power density to its RGB color from the colormap.
    % cidx proportional to pdens: low P → index 1 (dark/black), high P → index 256 (bright).
    cidx_all = max(1, min(256, round(255 * pdens ./ pmax) + 1));

    % Classify each filament as round or rect
    is_round = false(Nf, 1);
    if use_shapes && size(fil,2) >= 5
        for i = 1:Nf
            cidx_c = round(fil(i,5));
            if cidx_c >= 1 && cidx_c <= numel(geom.wire_shapes)
                is_round(i) = strcmp(geom.wire_shapes{cidx_c}, 'round');
            end
        end
    end

    Nv = 20;  % vertices per circle polygon
    theta = linspace(0, 2*pi, Nv+1);
    theta(end) = [];  % 1 × Nv

    % ---- Batch render round filaments via Faces/Vertices patch (one call) ----
    % Each face (row of Faces) gets its own RGB from FaceVertexCData with FaceColor flat.
    idx_round = find(is_round);
    if ~isempty(idx_round)
        Nr    = numel(idx_round);
        R_all = sqrt(fil(idx_round,3) .* fil(idx_round,4)) / 2;  % Nr×1
        % vx/vy: Nr×Nv — row i = vertex coords of circle i
        vx = bsxfun(@plus, fil(idx_round,1), bsxfun(@times, R_all, cos(theta)));
        vy = bsxfun(@plus, fil(idx_round,2), bsxfun(@times, R_all, sin(theta)));
        % Row-major flatten: vertex (i-1)*Nv+k belongs to face i
        verts_r   = [reshape(vx', [], 1), reshape(vy', [], 1)];  % (Nr*Nv)×2
        faces_r   = reshape(1:Nr*Nv, Nv, Nr)';                   % Nr×Nv
        fcolors_r = cmap(cidx_all(idx_round), :);                 % Nr×3 RGB per face
        patch(ax, 'Faces', faces_r, 'Vertices', verts_r, ...
              'FaceVertexCData', fcolors_r, ...
              'FaceColor', 'flat', 'EdgeColor', 'none');
    end

    % ---- Batch render rectangular filaments via Faces/Vertices patch (one call) ----
    idx_rect = find(~is_round);
    if ~isempty(idx_rect)
        Nrect  = numel(idx_rect);
        hx_all = fil(idx_rect,3) / 2;
        hy_all = fil(idx_rect,4) / 2;
        cx_all = fil(idx_rect,1);
        cy_all = fil(idx_rect,2);
        % 4 vertices per rect (BL BR TR TL): Nrect×4
        vx_q = [cx_all-hx_all, cx_all+hx_all, cx_all+hx_all, cx_all-hx_all];
        vy_q = [cy_all-hy_all, cy_all-hy_all, cy_all+hy_all, cy_all+hy_all];
        verts_q   = [reshape(vx_q', [], 1), reshape(vy_q', [], 1)];  % (Nrect*4)×2
        faces_q   = reshape(1:Nrect*4, 4, Nrect)';                   % Nrect×4
        fcolors_q = cmap(cidx_all(idx_rect), :);                      % Nrect×3 RGB per face
        patch(ax, 'Faces', faces_q, 'Vertices', verts_q, ...
              'FaceVertexCData', fcolors_q, ...
              'FaceColor', 'flat', 'EdgeColor', 'none');
    end

    % ---- Winding outline overlays (one patch per winding, not per filament) ----
    if size(fil,2) >= 6 && ~isempty(winding_colors)
        winding_idx_col = round(fil(:,6));
        unique_windings = unique(winding_idx_col);
        for w = unique_windings(:)'
            if w < 1 || w > numel(winding_colors), continue; end
            ec         = winding_colors{w};
            mask_w     = (winding_idx_col == w);
            fil_w      = fil(mask_w, :);
            is_round_w = is_round(mask_w);
            idx_r_w    = find(is_round_w);
            idx_q_w    = find(~is_round_w);
            % Round outlines
            if ~isempty(idx_r_w)
                Nr_w  = numel(idx_r_w);
                R_w   = sqrt(fil_w(idx_r_w,3) .* fil_w(idx_r_w,4)) / 2;
                vx_w  = bsxfun(@plus, fil_w(idx_r_w,1), bsxfun(@times, R_w, cos(theta)));
                vy_w  = bsxfun(@plus, fil_w(idx_r_w,2), bsxfun(@times, R_w, sin(theta)));
                vts_w = [reshape(vx_w', [], 1), reshape(vy_w', [], 1)];
                fcs_w = reshape(1:Nr_w*Nv, Nv, Nr_w)';
                patch(ax, 'Faces', fcs_w, 'Vertices', vts_w, ...
                      'FaceColor', 'none', 'EdgeColor', ec, 'LineWidth', 0.5);
            end
            % Rect outlines
            if ~isempty(idx_q_w)
                Nq_w  = numel(idx_q_w);
                hx_w  = fil_w(idx_q_w,3) / 2;
                hy_w  = fil_w(idx_q_w,4) / 2;
                cx_w  = fil_w(idx_q_w,1);
                cy_w  = fil_w(idx_q_w,2);
                vx_w  = [cx_w-hx_w, cx_w+hx_w, cx_w+hx_w, cx_w-hx_w];
                vy_w  = [cy_w-hy_w, cy_w-hy_w, cy_w+hy_w, cy_w+hy_w];
                vts_w = [reshape(vx_w', [], 1), reshape(vy_w', [], 1)];
                fcs_w = reshape(1:Nq_w*4, 4, Nq_w)';
                patch(ax, 'Faces', fcs_w, 'Vertices', vts_w, ...
                      'FaceColor', 'none', 'EdgeColor', ec, 'LineWidth', 0.5);
            end
        end
    end

    t_filament_s = toc(t_filament_start);

    % ========== TIMING: Boundary, legend, colorbar ==========
    t_decor_start = tic;

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
    colormap(ax, hot);

    % Add colorbar - use try/catch for Octave compatibility
    try
        cb = colorbar(ax);
        ylabel(cb, 'P (W/mm^2)');
    catch
        colorbar;
    end

    % Set color axis limits
    try
        caxis(ax, [0 pmax]);
    catch
        caxis([0 pmax]);
    end

    t_decor_s = toc(t_decor_start);

    % ========== TIMING: Hotspot overlay ==========
    t_hotspot_start = tic;

    % Overlay hotspots
    try
        hs = identify_hotspots(geom, results, 5);
        for k = 1:length(hs)
            plot(ax, hs(k).x, hs(k).y, 'cx', 'MarkerSize', 12, 'LineWidth', 2);
        end
    catch
        % identify_hotspots not available, skip
    end

    t_hotspot_s = toc(t_hotspot_start);

    hold(ax, 'off');

    % ========== TIMING: Print summary ==========
    t_total_s = t_filament_s + t_decor_s + t_hotspot_s;
    fprintf('[VIZ_LOSS] filament_loop=%.3fs, decorations=%.3fs, hotspot=%.3fs, total=%.3fs\n', ...
        t_filament_s, t_decor_s, t_hotspot_s, t_total_s);
end
