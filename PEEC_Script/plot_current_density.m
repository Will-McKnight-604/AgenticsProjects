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

    % ========== Draw core/bobbin shapes in background (from OM SVG) ==========
    % The SVG coordinates need to be mapped onto PEEC metre coordinates.
    % Mapping: compute bounding box of filaments, compare with SVG viewBox,
    % derive affine scale and offset, then draw polygons below conductors.

    has_core_shapes   = isfield(geom, 'core_polygons')   && ~isempty(geom.core_polygons)   && numel(geom.core_polygons)   > 1;
    has_bobbin_shapes = isfield(geom, 'bobbin_polygons') && ~isempty(geom.bobbin_polygons) && numel(geom.bobbin_polygons) > 1;

    if has_core_shapes || has_bobbin_shapes
        % First cell is the viewBox sentinel [x0 y0 w h]
        vb = [];
        if has_core_shapes
            vb_candidate = geom.core_polygons{1};
            if isnumeric(vb_candidate) && numel(vb_candidate) == 4
                vb = double(vb_candidate);
            end
        end
        if isempty(vb) && has_bobbin_shapes
            vb_candidate = geom.bobbin_polygons{1};
            if isnumeric(vb_candidate) && numel(vb_candidate) == 4
                vb = double(vb_candidate);
            end
        end

        % Build scale/offset from viewBox + filament bounding box
        % SVG viewBox: x0,y0 = origin, w,h = extent (all in SVG units).
        % PEEC filament coords: metres.
        % We map: SVG_x → fil_x, SVG_y (flipped) → fil_y
        if ~isempty(vb) && vb(3) > 0 && vb(4) > 0
            fil_xmin = min(fil(:,1) - fil(:,3)/2);
            fil_xmax = max(fil(:,1) + fil(:,3)/2);
            fil_ymin = min(fil(:,2) - fil(:,4)/2);
            fil_ymax = max(fil(:,2) + fil(:,4)/2);
            fil_w = fil_xmax - fil_xmin;
            fil_h = fil_ymax - fil_ymin;

            svg_x0 = vb(1); svg_y0 = vb(2);
            svg_w  = vb(3); svg_h  = vb(4);

            scale_x = fil_w / svg_w;
            scale_y = fil_h / svg_h;  % will be applied with y-flip

            % SVG helper: map SVG (x,y) → metres with y-flip
            function [mx, my] = svg_to_m(sx, sy)
                mx = fil_xmin + (sx - svg_x0) * scale_x;
                % SVG y increases downward; flip so top-SVG → top-filament
                my = fil_ymax - (sy - svg_y0) * scale_y;
            end

            ferrite_color = [0.486 0.486 0.490];  % #7b7c7d gray
            bobbin_color  = [0.325 0.592 0.588];  % #539796 teal

            if has_core_shapes
                for k = 2:numel(geom.core_polygons)
                    poly = geom.core_polygons{k};
                    if ~isnumeric(poly) || size(poly,2) < 2 || size(poly,1) < 3
                        continue;
                    end
                    [px, py] = svg_to_m(poly(:,1), poly(:,2));
                    try
                        patch(ax, px, py, ferrite_color, ...
                              'EdgeColor', ferrite_color * 0.8, 'LineWidth', 0.5, ...
                              'FaceAlpha', 0.45);
                    catch
                        patch(ax, px, py, ferrite_color, ...
                              'EdgeColor', ferrite_color * 0.8, 'LineWidth', 0.5);
                    end
                end
            end

            if has_bobbin_shapes
                for k = 2:numel(geom.bobbin_polygons)
                    poly = geom.bobbin_polygons{k};
                    if ~isnumeric(poly) || size(poly,2) < 2 || size(poly,1) < 3
                        continue;
                    end
                    [px, py] = svg_to_m(poly(:,1), poly(:,2));
                    try
                        patch(ax, px, py, bobbin_color, ...
                              'EdgeColor', bobbin_color * 0.8, 'LineWidth', 0.5, ...
                              'FaceAlpha', 0.4);
                    catch
                        patch(ax, px, py, bobbin_color, ...
                              'EdgeColor', bobbin_color * 0.8, 'LineWidth', 0.5);
                    end
                end
            end
        end
    end

    % ========== TIMING: Filament rendering (vectorized batch patch) ==========
    t_filament_start = tic;

    Nf = size(fil, 1);

    % Map each filament's J value to its RGB color from the colormap.
    % cidx proportional to Jmag: low J → index 1 (blue), high J → index 256 (red).
    cidx_all = max(1, min(256, round(255 * Jmag ./ Jmax) + 1));

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

    % ---- Winding zone backgrounds (semi-transparent colored regions) ----
    % Instead of thin colored outlines around each filament (which are invisible at small scales),
    % draw semi-transparent background zones that clearly separate windings spatially.
    % This preserves the current density colormap visibility while providing strong winding identity.
    if size(fil,2) >= 6 && ~isempty(winding_colors)
        winding_idx_col = round(fil(:,6));
        unique_windings = unique(winding_idx_col);

        % Compute bounding box for each winding and draw zone
        for w = unique_windings(:)'
            if w < 1 || w > numel(winding_colors), continue; end
            mask_w = (winding_idx_col == w);
            fil_w = fil(mask_w, :);

            % Get filament bounds (including their half-widths/heights as radii)
            x_min = min(fil_w(:,1) - fil_w(:,3)/2);
            x_max = max(fil_w(:,1) + fil_w(:,3)/2);
            y_min = min(fil_w(:,2) - fil_w(:,4)/2);
            y_max = max(fil_w(:,2) + fil_w(:,4)/2);

            % Add 10% margin to zone bounds for visual separation
            x_margin = 0.1 * (x_max - x_min);
            y_margin = 0.1 * (y_max - y_min);
            x_min = x_min - x_margin;
            x_max = x_max + x_margin;
            y_min = y_min - y_margin;
            y_max = y_max + y_margin;

            % Draw semi-transparent rectangular zone
            zone_color = winding_colors{w};
            try
                % Try to set FaceAlpha and EdgeAlpha (MATLAB R2014b+)
                zone_patch = patch(ax, ...
                    [x_min, x_max, x_max, x_min], ...
                    [y_min, y_min, y_max, y_max], ...
                    zone_color, ...
                    'FaceAlpha', 0.12, ...
                    'EdgeColor', zone_color, ...
                    'EdgeAlpha', 0.25, ...
                    'LineWidth', 1.5);
            catch
                % Fallback for older Octave without EdgeAlpha
                zone_patch = patch(ax, ...
                    [x_min, x_max, x_max, x_min], ...
                    [y_min, y_min, y_max, y_max], ...
                    zone_color, ...
                    'EdgeColor', zone_color, ...
                    'LineWidth', 1.5);
                try
                    set(zone_patch, 'FaceAlpha', 0.12);
                catch
                end
            end

            % Try to send zone to back (behind the filament patches drawn above)
            try
                uistack(zone_patch, 'bottom');
            catch
                % Octave may not support uistack; zones are still visible
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

    % Store legend handles for later (add AFTER colorbar to avoid resize conflict)
    leg_handles = [];
    leg_names = {};
    if ~isempty(winding_names) && ~isempty(winding_colors)
        n_w = min(numel(winding_names), numel(winding_colors));
        leg_handles = zeros(1, n_w);
        for w = 1:n_w
            leg_handles(w) = plot(ax, NaN, NaN, 's', 'MarkerFaceColor', winding_colors{w}, ...
                'MarkerEdgeColor', winding_colors{w}, 'MarkerSize', 8);
        end
        leg_names = winding_names(1:n_w);
    end

    % Set colormap for this axes
    colormap(ax, jet);

    % Add colorbar first (before legend to avoid resize conflicts in Octave)
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

    % Add legend after colorbar (avoid 'best' which fails in Octave with colorbar)
    if ~isempty(leg_handles) && ~isempty(leg_names)
        try
            legend(ax, leg_handles, leg_names, 'Location', 'northeast', 'FontSize', 7);
        catch
        end
    end

    t_decor_s = toc(t_decor_start);

    % ========== TIMING: Print summary ==========
    t_total_s = t_filament_s + t_decor_s;
    fprintf('[VIZ_CURR] filament_loop=%.3fs, decorations=%.3fs, total=%.3fs\n', ...
        t_filament_s, t_decor_s, t_total_s);

    hold(ax, 'off');
end
