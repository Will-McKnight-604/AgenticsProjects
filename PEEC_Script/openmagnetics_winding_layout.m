% openmagnetics_winding_layout.m
% Advanced winding layout calculator using OpenMagnetics concepts
% Supports: round, litz, foil, and rectangular wire packing

classdef openmagnetics_winding_layout < handle

    properties
        api  % OpenMagnetics API interface
    end

    methods

        function obj = openmagnetics_winding_layout(api_interface)
            obj.api = api_interface;
        end

        function layout = calculate_winding_layout(obj, core_name, wire_type, n_turns, pattern, n_filar, edge_margin)
            % Calculate optimal winding layout for given core and wire
            if nargin < 5
                pattern = 'layered';
            end
            if nargin < 6 || isempty(n_filar)
                n_filar = 1;
            end
            if nargin < 7 || isempty(edge_margin)
                edge_margin = 0;
            end

            % Get core data
            core = obj.api.core_database.(core_name);
            bobbin = obj.get_bobbin_dimensions(core);
            bobbin_eff = bobbin;
            if edge_margin > 0
                bobbin_eff.width = max(1e-6, bobbin.width - 2*edge_margin);
                bobbin_eff.height = max(1e-6, bobbin.height - 2*edge_margin);
            end

            % Get wire data and shape info
            wire = obj.api.get_wire_info(wire_type);
            if isfield(wire, 'conductor_shape')
                wire_shape = wire.conductor_shape;
            else
                wire_shape = 'round';
            end

            % Get visual dimensions for layout
            [vis_w, vis_h] = obj.api.get_wire_visual_dims(wire_type);

            % For foil wires: width is NOT a wire property - it's the core window height
            % OpenMagnetics foil wires only specify thickness (conductingWidth)
            % The width (conductingHeight) is null because foil is cut to match the core
            if strcmp(wire_shape, 'rectangular')
                wire_type_field = '';
                if isfield(wire, 'type')
                    wire_type_field = wire.type;
                    if iscell(wire_type_field); wire_type_field = wire_type_field{1}; end
                end
                if strcmpi(wire_type_field, 'foil') || (vis_w > 10 * vis_h)
                    % Foil wire: set width = bobbin height (foil fills the window)
                    vis_w = bobbin_eff.height;
                    fprintf('  Foil wire: setting width to bobbin height = %.3f mm\n', vis_w*1e3);
                end
            end

            wire_od = max(vis_w, vis_h);  % For round, this is OD

            fprintf('=== WINDING LAYOUT ===\n');
            fprintf('Core: %s | Wire: %s (OD=%.3fmm) | Turns: %d x %d | %s\n', ...
                core_name, wire_type, wire_od*1e3, n_turns, n_filar, pattern);

            % Route to appropriate packing algorithm
            if strcmp(wire_shape, 'rectangular')
                % Foil/Rect wire: use rectangular packing
                layout = obj.rectangular_wire_packing(bobbin_eff, vis_w, vis_h, n_turns, n_filar);
            else
                % Round/Litz wire
                effective_turns = n_turns * max(1, n_filar);
                switch pattern
                    case 'orthocyclic'
                        layout = obj.orthocyclic_packing(bobbin_eff, wire_od, effective_turns);
                    case 'layered'
                        layout = obj.layered_packing(bobbin_eff, wire_od, effective_turns);
                    case 'random'
                        layout = obj.random_packing(bobbin_eff, wire_od, effective_turns);
                    otherwise
                        layout = obj.layered_packing(bobbin_eff, wire_od, effective_turns);
                end
            end

            % Store geometry and shape info for visualization
            layout.bobbin = bobbin;
            layout.bobbin_eff = bobbin_eff;
            layout.wire_od = wire_od;
            layout.wire_type = wire_type;
            layout.core_name = core_name;
            layout.wire_shape = wire_shape;
            layout.wire_vis_w = vis_w;
            layout.wire_vis_h = vis_h;
            layout.edge_margin = edge_margin;
            if strcmp(wire_shape, 'rectangular')
                if isfield(layout, 'is_foil') && layout.is_foil
                    layout.draw_w = vis_h;
                    layout.draw_h = vis_w;
                else
                    layout.draw_w = vis_w;
                    layout.draw_h = vis_h;
                end
            else
                layout.draw_w = wire_od;
                layout.draw_h = wire_od;
            end
        end

        function bobbin = get_bobbin_dimensions(obj, core)
            if isfield(core, 'bobbin')
                bobbin = core.bobbin;
            else
                if isfield(core, 'dimensions')
                    bobbin.width = 0.4 * core.dimensions.A;
                    bobbin.height = 0.6 * core.dimensions.C;
                else
                    bobbin.width = 25e-3;
                    bobbin.height = 15e-3;
                end
            end
            fprintf('  Bobbin window: %.2f x %.2f mm (W x H)\n', ...
                bobbin.width*1e3, bobbin.height*1e3);
        end

        % ============ ROUND/LITZ PACKING ============

        function layout = layered_packing(obj, bobbin, wire_od, n_turns)
            turns_per_layer = floor(bobbin.height / wire_od);
            if turns_per_layer < 1; turns_per_layer = 1; end
            n_layers = ceil(n_turns / turns_per_layer);
            total_width = n_layers * wire_od;

            layout.fits = (total_width <= bobbin.width);
            layout.n_layers = n_layers;
            layout.turns_per_layer = turns_per_layer;
            layout.required_width = total_width;
            layout.width_util = total_width / bobbin.width;
            layout.height_util = min(1, (turns_per_layer * wire_od) / bobbin.height);
            layout.fill_factor = 0.785 * layout.width_util * layout.height_util;
            layout.pattern = 'layered';
            layout.turn_positions = obj.generate_layered_positions(n_turns, turns_per_layer, wire_od);
        end

        function layout = orthocyclic_packing(obj, bobbin, wire_od, n_turns)
            turns_layer_1 = floor(bobbin.height / wire_od);
            if turns_layer_1 < 1; turns_layer_1 = 1; end
            h_layer_2 = bobbin.height - wire_od/2;
            turns_layer_2 = max(1, floor(h_layer_2 / wire_od));

            turns_so_far = 0;
            n_layers = 0;
            while turns_so_far < n_turns
                n_layers = n_layers + 1;
                if mod(n_layers, 2) == 1
                    turns_so_far = turns_so_far + turns_layer_1;
                else
                    turns_so_far = turns_so_far + turns_layer_2;
                end
            end

            layer_width = wire_od * 0.866;
            total_width = n_layers * layer_width;

            layout.fits = (total_width <= bobbin.width);
            layout.n_layers = n_layers;
            layout.turns_per_layer = turns_layer_1;
            layout.required_width = total_width;
            layout.width_util = total_width / bobbin.width;
            layout.height_util = min(1, (turns_layer_1 * wire_od) / bobbin.height);
            layout.fill_factor = 0.907 * layout.width_util * layout.height_util;
            layout.pattern = 'orthocyclic';
            layout.turn_positions = obj.generate_orthocyclic_positions(n_turns, ...
                turns_layer_1, turns_layer_2, wire_od);
        end

        function layout = random_packing(obj, bobbin, wire_od, n_turns)
            eff_diameter = wire_od / sqrt(0.55);
            turns_per_layer = max(1, floor(bobbin.height / eff_diameter));
            n_layers = ceil(n_turns / turns_per_layer);
            total_width = n_layers * eff_diameter;

            layout.fits = (total_width <= bobbin.width);
            layout.n_layers = n_layers;
            layout.turns_per_layer = turns_per_layer;
            layout.required_width = total_width;
            layout.width_util = total_width / bobbin.width;
            layout.height_util = min(1, (turns_per_layer * eff_diameter) / bobbin.height);
            layout.fill_factor = 0.55 * layout.width_util * layout.height_util;
            layout.pattern = 'random';
            layout.turn_positions = obj.generate_layered_positions(n_turns, turns_per_layer, eff_diameter);
        end

        % ============ RECTANGULAR/FOIL PACKING ============

        function layout = rectangular_wire_packing(obj, bobbin, wire_w, wire_h, n_turns, n_filar)
            % For foil: each turn is one layer; wire fills bobbin height
            % For rect: layered, but with actual rect dimensions
            % Convention: wire_w = conductor width (across bobbin width)
            %             wire_h = conductor height (fills bobbin height or stacks)
            if nargin < 6 || isempty(n_filar)
                n_filar = 1;
            end

            % If foil (width >> height, and width > bobbin height/2),
            % assume foil wraps: each turn = one layer,
            % foil width fills bobbin height, foil thickness = layer width
            is_foil = (wire_w > 5 * wire_h) && (wire_w > bobbin.height * 0.3);
            layout.is_foil = is_foil;

            if is_foil
                % FOIL WINDING: each turn = one layer
                % Foil width fills the bobbin height
                % Foil thickness stacks in the width direction
                gap_filar = 0.05e-3;
                layer_thickness = wire_h + 0.05e-3;  % thickness + insulation
                total_width = n_turns * layer_thickness;

                turns_per_layer = 1;
                n_layers = n_turns;
                total_height = n_filar * wire_w + (n_filar - 1) * gap_filar;

                layout.fits = (total_width <= bobbin.width) && (total_height <= bobbin.height);
                layout.n_layers = n_layers;
                layout.turns_per_layer = max(1, n_filar);
                layout.required_width = total_width;
                layout.width_util = total_width / bobbin.width;
                layout.height_util = min(1, total_height / bobbin.height);
                layout.fill_factor = layout.width_util * layout.height_util;
                layout.pattern = 'foil';

                % Generate foil turn positions: each turn at center of layer
                % x = layer center, y = centered stack of parallels
                positions = zeros(n_turns * n_filar, 2);
                if total_height <= bobbin.height
                    y_start = (bobbin.height - total_height) / 2 + wire_w / 2;
                else
                    y_start = wire_w / 2;
                end

                idx = 1;
                for t = 1:n_turns
                    x = (t - 0.5) * layer_thickness;
                    for p = 1:n_filar
                        y = y_start + (p - 1) * (wire_w + gap_filar);
                        positions(idx, :) = [x, y];
                        idx = idx + 1;
                    end
                end
                layout.turn_positions = positions;
            else
                % RECTANGULAR WIRE: layered like round but with rect dims
                % Stack height = wire_h, layer width = wire_w
                % Turns stack vertically in each layer
                n_turns_eff = n_turns * max(1, n_filar);
                turns_per_layer = max(1, floor(bobbin.height / (wire_h + 0.05e-3)));
                n_layers = ceil(n_turns_eff / turns_per_layer);
                layer_width = wire_w + 0.05e-3;
                total_width = n_layers * layer_width;

                layout.fits = (total_width <= bobbin.width);
                layout.n_layers = n_layers;
                layout.turns_per_layer = turns_per_layer;
                layout.required_width = total_width;
                layout.width_util = total_width / bobbin.width;
                layout.height_util = min(1, (turns_per_layer * wire_h) / bobbin.height);
                layout.fill_factor = layout.width_util * layout.height_util;
                layout.pattern = 'rectangular';

                % Generate positions
                positions = zeros(n_turns_eff, 2);
                turn_idx = 1;
                for layer = 1:n_layers
                    for t = 1:turns_per_layer
                        if turn_idx > n_turns_eff; break; end
                        x = (layer - 0.5) * layer_width;
                        y = (t - 0.5) * (wire_h + 0.05e-3);
                        positions(turn_idx, :) = [x, y];
                        turn_idx = turn_idx + 1;
                    end
                end
                layout.turn_positions = positions;
            end
        end

        % ============ POSITION GENERATORS ============

        function positions = generate_layered_positions(obj, n_turns, turns_per_layer, wire_od)
            positions = zeros(n_turns, 2);
            turn_idx = 1;
            layer = 0;

            while turn_idx <= n_turns
                layer = layer + 1;
                x = (layer - 0.5) * wire_od;
                for t = 1:turns_per_layer
                    if turn_idx > n_turns; break; end
                    y = (t - 0.5) * wire_od;
                    positions(turn_idx, :) = [x, y];
                    turn_idx = turn_idx + 1;
                end
            end
        end

        function positions = generate_orthocyclic_positions(obj, n_turns, tpl_odd, tpl_even, wire_od)
            positions = zeros(n_turns, 2);
            turn_idx = 1;
            layer = 0;

            while turn_idx <= n_turns
                layer = layer + 1;
                x = (layer - 1) * wire_od * 0.866;

                if mod(layer, 2) == 1
                    tpl = tpl_odd;
                    y_offset = 0;
                else
                    tpl = tpl_even;
                    y_offset = wire_od / 2;
                end

                for t = 1:tpl
                    if turn_idx > n_turns; break; end
                    y = y_offset + (t - 0.5) * wire_od;
                    positions(turn_idx, :) = [x, y];
                    turn_idx = turn_idx + 1;
                end
            end
        end

        % ============ VISUALIZATION ============

        function visualize_layout(obj, layout, ax_handle)
            if nargin < 3 || isempty(ax_handle)
                figure('Name', 'Winding Layout', 'Position', [100 100 800 600]);
                ax_handle = gca;
            end

            axes(ax_handle);
            cla(ax_handle);
            hold(ax_handle, 'on');
            axis(ax_handle, 'equal');

            % Draw bobbin window
            rectangle('Position', [0, 0, layout.bobbin.width, layout.bobbin.height], ...
                'EdgeColor', 'k', 'LineWidth', 2, 'LineStyle', '--', 'Parent', ax_handle);
            if isfield(layout, 'edge_margin') && layout.edge_margin > 0
                rectangle('Position', [layout.edge_margin, layout.edge_margin, ...
                    max(1e-6, layout.bobbin.width - 2*layout.edge_margin), ...
                    max(1e-6, layout.bobbin.height - 2*layout.edge_margin)], ...
                    'EdgeColor', [0.5 0.5 0.5], 'LineStyle', ':', 'LineWidth', 1, ...
                    'Parent', ax_handle);
            end

            % Determine wire shape
            is_rect = isfield(layout, 'wire_shape') && strcmp(layout.wire_shape, 'rectangular');

            for i = 1:size(layout.turn_positions, 1)
                x = layout.turn_positions(i, 1);
                y = layout.turn_positions(i, 2);
                if isfield(layout, 'edge_margin') && layout.edge_margin > 0
                    x = x + layout.edge_margin;
                    y = y + layout.edge_margin;
                end

                if is_rect
                    % Draw rectangle
                    if isfield(layout, 'draw_w')
                        w = layout.draw_w;
                        h = layout.draw_h;
                    else
                        w = layout.wire_vis_w;
                        h = layout.wire_vis_h;
                    end
                    rectangle('Parent', ax_handle, ...
                        'Position', [x - w/2, y - h/2, w, h], ...
                        'FaceColor', [0.6 0.8 1.0], ...
                        'EdgeColor', 'b', 'LineWidth', 0.5);
                else
                    % Draw circle
                    r = layout.wire_od / 2;
                    theta = linspace(0, 2*pi, 50);
                    fill(ax_handle, x + r*cos(theta), y + r*sin(theta), [0.6 0.8 1.0], ...
                        'EdgeColor', 'b', 'LineWidth', 0.5);
                end

                if i <= 20
                    text(x, y, sprintf('%d', i), 'FontSize', 6, ...
                        'HorizontalAlignment', 'center', 'Parent', ax_handle);
                end
            end

            xlabel(ax_handle, 'Width (m)');
            ylabel(ax_handle, 'Height (m)');
            title(ax_handle, sprintf('%s: %d layers, %.1f%% fill', ...
                layout.pattern, layout.n_layers, layout.fill_factor*100));

            hold(ax_handle, 'off');
        end

    end % methods
end
