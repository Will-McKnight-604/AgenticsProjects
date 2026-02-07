% visualize_core_window_PATCH.m
%
% UPDATED visualize_core_window function for interactive_winding_designer.m
%
% Replace BOTH copies of visualize_core_window() in interactive_winding_designer.m
% (around lines ~758 and ~1779) with this version.
%
% KEY CHANGES:
%   1. Uses calculate_multi_winding_layout() for proper section-based allocation
%   2. IEC 60664-1 insulation gap calculation (not hardcoded 1mm)
%   3. Bobbin margins (not winding from x=0)
%   4. Tight-pack sections (no proportional window division)
%   5. Section boundaries shown as dotted gray lines
%   6. Bobbin width/height swap protection for E-cores

function visualize_core_window(data, ax)
    % Show how windings fit in selected core's bobbin window
    % Uses MAS-style section-based layout from OpenMagnetics

    if strcmp(data.selected_core, 'None')
        text(ax, 0.5, 0.5, 'No core selected', ...
            'HorizontalAlignment', 'center', 'FontSize', 12);
        return;
    end

    % Get packing pattern from GUI
    packing_ctrl = findobj(data.fig_gui, 'Tag', 'packing_pattern');
    packing_idx = get(packing_ctrl, 'Value');
    patterns = {'layered', 'orthocyclic', 'random'};
    pattern = patterns{packing_idx};

    % --- Build winding_defs for multi-winding layout ---
    winding_defs = cell(data.n_windings, 1);
    for w = 1:data.n_windings
        def = struct();
        def.wire_type  = data.windings(w).wire_type;
        def.n_turns    = data.windings(w).n_turns * data.windings(w).n_filar;
        def.name       = data.windings(w).name;

        % Voltage and insulation (if available in data)
        if isfield(data.windings(w), 'voltage')
            def.voltage = data.windings(w).voltage;
        else
            def.voltage = 0;  % unknown -> minimal gap
        end

        if isfield(data.windings(w), 'insulation')
            def.insulation = data.windings(w).insulation;
        else
            if w == 1
                def.insulation = 'basic';  % primary-to-secondary default
            else
                def.insulation = 'basic';
            end
        end

        winding_defs{w} = def;
    end

    % --- Calculate multi-winding layout with proper sections ---
    layouts = data.layout_calc.calculate_multi_winding_layout(...
        data.selected_core, winding_defs, pattern);

    % --- Draw using the layout calculator's visualization ---
    hold(ax, 'on');
    axis(ax, 'equal');

    bobbin = layouts{1}.bobbin;

    % Bobbin outline
    rectangle('Parent', ax, 'Position', [0, 0, bobbin.width, bobbin.height], ...
        'EdgeColor', 'k', 'LineWidth', 2, 'LineStyle', '--');
    text(bobbin.width/2, bobbin.height + 0.001, 'Bobbin Window', ...
        'Parent', ax, 'HorizontalAlignment', 'center', ...
        'FontSize', 9, 'FontWeight', 'bold');

    % Draw each winding's turns
    total_fits = true;
    for w = 1:length(layouts)
        lay = layouts{w};
        col = data.winding_colors{mod(w-1, length(data.winding_colors)) + 1};

        if isfield(lay, 'all_fit') && ~lay.all_fit
            total_fits = false;
        end
        if isfield(lay, 'fits') && ~lay.fits
            total_fits = false;
        end

        % Draw turns
        for i = 1:size(lay.turn_positions, 1)
            x = lay.turn_positions(i, 1);
            y = lay.turn_positions(i, 2);

            if isfield(lay, 'wire_shape') && ...
                    (strcmp(lay.wire_shape, 'rectangular') || strcmp(lay.wire_shape, 'foil'))
                tw = lay.turn_sizes(i, 1);
                th = lay.turn_sizes(i, 2);
                rectangle('Parent', ax, ...
                    'Position', [x - tw/2, y - th/2, tw, th], ...
                    'FaceColor', col, 'EdgeColor', 'k', 'LineWidth', 0.3);
            else
                r = lay.wire_od / 2;
                theta = linspace(0, 2*pi, 30);
                fill(ax, x + r*cos(theta), y + r*sin(theta), col, ...
                    'EdgeColor', 'k', 'LineWidth', 0.3);
            end
        end

        % Section boundary (dotted gray)
        if isfield(lay, 'section_x_offset') && isfield(lay, 'section_width')
            sx = lay.section_x_offset;
            sw = lay.section_width;
            rectangle('Parent', ax, 'Position', [sx, 0, sw, bobbin.height], ...
                'EdgeColor', [0.6 0.6 0.6], 'LineWidth', 0.5, 'LineStyle', ':');
        end

        % Winding label
        if isfield(lay, 'section_x_offset') && isfield(lay, 'section_width')
            label_x = lay.section_x_offset + lay.section_width / 2;
        else
            label_x = mean(lay.turn_positions(:,1));
        end
        text(label_x, -0.0005, lay.winding_name, ...
            'Parent', ax, 'HorizontalAlignment', 'center', 'FontSize', 8, ...
            'Color', col, 'FontWeight', 'bold');
    end

    xlim(ax, [-0.001, bobbin.width + 0.001]);
    ylim(ax, [-0.002, bobbin.height + 0.002]);
    xlabel(ax, 'Width (m)');
    ylabel(ax, 'Height (m)');
    title(ax, sprintf('%s packing in %s', pattern, data.selected_core));
    hold(ax, 'off');

    % Update info text
    if total_fits
        info_str = sprintf('[OK] All windings FIT in core\nPattern: %s', pattern);
        color = [0.8 1.0 0.8];
    else
        info_str = sprintf('[WARN] Windings DO NOT FIT\nTry smaller wire or fewer turns');
        color = [1.0 0.8 0.8];
    end

    info_ctrl = findobj(data.fig_gui, 'Tag', 'vis_info');
    if ~isempty(info_ctrl)
        set(info_ctrl, 'String', info_str, 'BackgroundColor', color);
    end
end
