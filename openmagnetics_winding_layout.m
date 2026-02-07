% openmagnetics_winding_layout.m
% Winding layout calculator using OpenMagnetics MAS-style architecture
%
% MAS hierarchy: Bobbin Window -> Margins -> Sections -> Layers -> Turns
%
% Key features:
%   - Section-based winding allocation (like OpenMagnetics CoilWrapper)
%   - IEC 60664-1 / IEC 61558 insulation gap calculation
%   - Bobbin margin handling
%   - Tight-pack section sizing (each winding gets only what it needs)
%   - Wire-shape-aware packing: round, litz, rectangular, foil
%   - Multi-winding support with proper inter-section insulation

classdef openmagnetics_winding_layout < handle

    properties
        api  % OpenMagnetics API interface
    end

    methods

        function obj = openmagnetics_winding_layout(api_interface)
            obj.api = api_interface;
        end

        % ==============================================================
        % SINGLE WINDING LAYOUT (backward-compatible)
        % ==============================================================
        function layout = calculate_winding_layout(obj, core_name, wire_type, n_turns, pattern)
            % Calculate layout for a single winding in the full bobbin.
            % Kept for backward compatibility; prefer calculate_multi_winding_layout.

            if nargin < 5; pattern = 'layered'; end

            core = obj.api.core_database.(core_name);
            bobbin = obj.get_bobbin_dimensions(core);
            wire = obj.api.wire_database.(wire_type);
            [wire_shape, wire_od, wire_w, wire_h] = obj.get_wire_packing_dims(wire);

            fprintf('=== WINDING LAYOUT ===\n');
            fprintf('Core: %s | Wire: %s (OD=%.3fmm) | Turns: %d | %s\n', ...
                core_name, wire_type, wire_od*1e3, n_turns, pattern);

            switch pattern
                case 'orthocyclic'
                    layout = obj.pack_round_orthocyclic(bobbin, wire_od, n_turns);
                case 'layered'
                    if strcmp(wire_shape, 'rectangular') || strcmp(wire_shape, 'foil')
                        layout = obj.pack_rectangular(bobbin, wire_w, wire_h, n_turns, pattern);
                    else
                        layout = obj.pack_round_layered(bobbin, wire_od, n_turns);
                    end
                case 'random'
                    layout = obj.pack_round_random(bobbin, wire_od, n_turns);
                otherwise
                    error('Unknown pattern: %s', pattern);
            end

            layout.bobbin = bobbin;
            layout.wire_od = wire_od;
            layout.wire_type = wire_type;
            layout.wire_shape = wire_shape;
            layout.core_name = core_name;

            if ~isfield(layout, 'turn_sizes')
                layout.turn_sizes = repmat([wire_od, wire_od], size(layout.turn_positions, 1), 1);
            end
        end


        % ==============================================================
        % MULTI-WINDING LAYOUT (MAS section-based)
        % ==============================================================
        function layouts = calculate_multi_winding_layout(obj, core_name, winding_defs, pattern, strategy)
            % Calculate section-based layout for multiple windings.
            %
            % This follows the OpenMagnetics MAS architecture:
            %   Bobbin Window -> Margins -> Sections -> Layers -> Turns
            %
            % Inputs:
            %   core_name    - Core identifier (e.g. 'ETD_29_16_10')
            %   winding_defs - Cell array of structs, each with fields:
            %                    .wire_type  - e.g. 'AWG_22'
            %                    .n_turns    - total turns (including filar)
            %                    .name       - e.g. 'Primary'
            %                    .voltage    - (optional) winding voltage [V]
            %                    .insulation - (optional) 'functional'|'basic'|
            %                                  'supplementary'|'reinforced'
            %   pattern      - 'layered', 'orthocyclic', or 'random'
            %   strategy     - 'wind_by_consecutive_turns' (default)
            %
            % Output:
            %   layouts      - Cell array of layout structs, one per winding.
            %                  Each has: turn_positions, turn_sizes, wire_od,
            %                  section_x_offset, section_width, bobbin, ...

            if nargin < 4 || isempty(pattern);  pattern  = 'layered'; end
            if nargin < 5 || isempty(strategy); strategy = 'wind_by_consecutive_turns'; end

            % --- Normalize input: accept struct array OR cell array ---
            if isstruct(winding_defs)
                % Convert struct array to cell array of structs
                tmp = cell(length(winding_defs), 1);
                for i = 1:length(winding_defs)
                    tmp{i} = winding_defs(i);
                end
                winding_defs = tmp;
            end

            n_windings = length(winding_defs);

            % --- Get core and bobbin ---
            core   = obj.api.core_database.(core_name);
            bobbin = obj.get_bobbin_dimensions(core);

            % --- Bobbin margins (MAS: bobbin wall thickness) ---
            margin = obj.get_bobbin_margins(bobbin);
            usable_width  = bobbin.width  - margin.left - margin.right;
            usable_height = bobbin.height - margin.top  - margin.bottom;

            fprintf('=== MULTI-WINDING LAYOUT (%s) ===\n', strategy);
            fprintf('Core: %s  Bobbin: %.2f x %.2f mm\n', ...
                core_name, bobbin.width*1e3, bobbin.height*1e3);
            fprintf('Usable window: %.2f x %.2f mm (margins: L=%.1f R=%.1f T=%.1f B=%.1f mm)\n', ...
                usable_width*1e3, usable_height*1e3, ...
                margin.left*1e3, margin.right*1e3, margin.top*1e3, margin.bottom*1e3);

            % --- Calculate wire dimensions for each winding ---
            wire_info = cell(n_windings, 1);
            for w = 1:n_windings
                def = winding_defs{w};
                wire = obj.api.wire_database.(def.wire_type);
                [ws, od, ww, wh] = obj.get_wire_packing_dims(wire);
                wire_info{w}.shape = ws;
                wire_info{w}.od    = od;
                wire_info{w}.w     = ww;
                wire_info{w}.h     = wh;
            end

            % --- Calculate insulation gaps between sections (IEC-based) ---
            insulation_gaps = zeros(n_windings - 1, 1);
            for g = 1:n_windings - 1
                def_a = winding_defs{g};
                def_b = winding_defs{g + 1};
                insulation_gaps(g) = obj.calculate_insulation_gap(def_a, def_b);
            end

            % --- Calculate each winding's required width (tight-pack) ---
            section_sub_bobbin.height = usable_height;  % full usable height
            winding_widths = zeros(n_windings, 1);

            for w = 1:n_windings
                def = winding_defs{w};
                wi  = wire_info{w};

                % Defensive: ensure required fields exist
                if ~isfield(def, 'name');    def.name = sprintf('Winding_%d', w); winding_defs{w} = def; end
                if ~isfield(def, 'n_turns'); def.n_turns = 1; winding_defs{w} = def; end

                % Calculate turns per layer and number of layers
                if strcmp(wi.shape, 'rectangular') || strcmp(wi.shape, 'foil')
                    turn_gap = 50e-6;  % 50um between rectangular turns
                    tpl = floor(usable_height / (wi.h + turn_gap));
                    if tpl < 1; tpl = 1; end
                    n_layers = ceil(def.n_turns / tpl);
                    layer_gap = 50e-6;
                    winding_widths(w) = n_layers * wi.w + max(0, n_layers - 1) * layer_gap;
                else
                    tpl = floor(usable_height / wi.od);
                    if tpl < 1; tpl = 1; end
                    n_layers = ceil(def.n_turns / tpl);
                    winding_widths(w) = n_layers * wi.od;
                end

                fprintf('  Winding %d (%s): %d turns, %d layers, need %.2f mm width\n', ...
                    w, def.name, def.n_turns, n_layers, winding_widths(w)*1e3);
            end

            % --- Total width needed (tight-pack) ---
            total_insulation = sum(insulation_gaps);
            total_winding_width = sum(winding_widths);
            total_needed = total_winding_width + total_insulation;

            fprintf('  Insulation gaps: ');
            for g = 1:length(insulation_gaps)
                fprintf('%.2f mm  ', insulation_gaps(g)*1e3);
            end
            fprintf('\n');
            fprintf('  Total needed: %.2f mm (available: %.2f mm)\n', ...
                total_needed*1e3, usable_width*1e3);

            all_fit = (total_needed <= usable_width * 1.001);  % 0.1% tolerance

            % --- Assign section offsets (tight-pack from left margin) ---
            x_cursor = margin.left;

            layouts = cell(n_windings, 1);
            for w = 1:n_windings
                def = winding_defs{w};
                wi  = wire_info{w};

                % This section's x offset and width
                section_x = x_cursor;
                section_w = winding_widths(w);

                % Create a sub-bobbin for this section
                sub_bobbin.width  = section_w;
                sub_bobbin.height = usable_height;

                % Pack winding within this section
                switch pattern
                    case 'orthocyclic'
                        lay = obj.pack_round_orthocyclic(sub_bobbin, wi.od, def.n_turns);
                    case 'layered'
                        if strcmp(wi.shape, 'rectangular') || strcmp(wi.shape, 'foil')
                            lay = obj.pack_rectangular(sub_bobbin, wi.w, wi.h, def.n_turns, pattern);
                        else
                            lay = obj.pack_round_layered(sub_bobbin, wi.od, def.n_turns);
                        end
                    case 'random'
                        lay = obj.pack_round_random(sub_bobbin, wi.od, def.n_turns);
                    otherwise
                        error('Unknown pattern: %s', pattern);
                end

                % Offset turn positions by section origin + bottom margin
                lay.turn_positions(:,1) = lay.turn_positions(:,1) + section_x;
                lay.turn_positions(:,2) = lay.turn_positions(:,2) + margin.bottom;

                % Store metadata
                lay.bobbin           = bobbin;
                lay.wire_od          = wi.od;
                lay.wire_type        = def.wire_type;
                lay.wire_shape       = wi.shape;
                lay.core_name        = core_name;
                lay.section_x_offset = section_x;
                lay.section_width    = section_w;
                lay.winding_name     = def.name;
                lay.all_fit          = all_fit;

                if ~isfield(lay, 'turn_sizes')
                    lay.turn_sizes = repmat([wi.od, wi.od], size(lay.turn_positions, 1), 1);
                end

                layouts{w} = lay;

                % Advance cursor past this winding + insulation gap
                x_cursor = x_cursor + section_w;
                if w < n_windings
                    x_cursor = x_cursor + insulation_gaps(w);
                end
            end

            if all_fit
                fprintf('[OK] All windings FIT in core window\n');
            else
                fprintf('[WARN] Windings DO NOT FIT - need %.2f mm, have %.2f mm\n', ...
                    total_needed*1e3, usable_width*1e3);
            end
        end


        % ==============================================================
        % BOBBIN DIMENSIONS
        % ==============================================================
        function bobbin = get_bobbin_dimensions(obj, core)
            % Extract bobbin window from core data.
            % For E-cores the winding window is typically TALL and NARROW:
            %   width  = gap between center leg and outer leg (radial)
            %   height = height of the winding window (axial)

            if isfield(core, 'bobbin')
                bobbin = core.bobbin;
            elseif isfield(core, 'dimensions')
                dims = core.dimensions;
                % E-core: window_width is the slot, window_height is the depth
                if isfield(dims, 'window_width') && isfield(dims, 'window_height')
                    bobbin.width  = dims.window_width;
                    bobbin.height = dims.window_height;
                elseif isfield(dims, 'E') && isfield(dims, 'D')
                    % MAS E-core: E = window width, D = window height
                    bobbin.width  = dims.E;
                    bobbin.height = dims.D;
                elseif isfield(dims, 'A') && isfield(dims, 'C') && isfield(dims, 'D')
                    % Older format: compute from outer dims
                    % A = total width, C = center leg width, D = window height
                    bobbin.width  = (dims.A - dims.C) / 2;
                    bobbin.height = dims.D;
                else
                    % Fallback for E-cores
                    bobbin.width  = 0.4 * dims.A;
                    bobbin.height = 0.8 * dims.A;
                end
            else
                bobbin.width  = 10e-3;
                bobbin.height = 20e-3;
            end

            % Sanity check: E-core windows are typically taller than wide
            % If width > 2 * height, they're likely swapped
            if bobbin.width > 2 * bobbin.height
                fprintf('  [NOTE] Bobbin width > 2x height -- swapping (E-core convention)\n');
                tmp = bobbin.width;
                bobbin.width  = bobbin.height;
                bobbin.height = tmp;
            end

            fprintf('  Bobbin window: %.2f x %.2f mm (W x H)\n', ...
                bobbin.width*1e3, bobbin.height*1e3);
        end


        % ==============================================================
        % BOBBIN MARGINS
        % ==============================================================
        function margin = get_bobbin_margins(obj, bobbin)
            % Bobbin wall thickness / tape margins.
            % OpenMagnetics uses real bobbin data; we estimate.
            % Typical bobbin wall: 0.5-1.5mm per side.

            % Use 5% of dimension or 0.5mm minimum, 1.5mm maximum
            m_w = max(0.5e-3, min(1.5e-3, 0.05 * bobbin.width));
            m_h = max(0.5e-3, min(1.5e-3, 0.05 * bobbin.height));

            margin.left   = m_w;
            margin.right  = m_w;
            margin.top    = m_h;
            margin.bottom = m_h;
        end


        % ==============================================================
        % IEC INSULATION GAP CALCULATION
        % ==============================================================
        function gap = calculate_insulation_gap(obj, def_a, def_b)
            % Calculate minimum insulation gap between two winding sections
            % per IEC 60664-1 / IEC 61558.
            %
            % OpenMagnetics implements the full standard with pollution degree,
            % material group, altitude factors, etc. We implement the key lookup.

            % Get voltage difference
            V_a = 0; V_b = 0;
            if isfield(def_a, 'voltage'); V_a = abs(def_a.voltage); end
            if isfield(def_b, 'voltage'); V_b = abs(def_b.voltage); end
            V_diff = abs(V_a - V_b);

            % Get insulation type (default = basic for different windings)
            ins_type = 'basic';
            if isfield(def_a, 'insulation'); ins_type = def_a.insulation; end
            if isfield(def_b, 'insulation'); ins_type = def_b.insulation; end

            % Calculate creepage distance (IEC 60664-1, PD2, Material Group III)
            % These are lookup tables from the standard
            creepage = obj.iec_creepage_distance(V_diff, ins_type);

            % Calculate clearance distance
            clearance = obj.iec_clearance_distance(V_diff, ins_type);

            % Gap is the maximum of creepage and clearance
            gap = max(creepage, clearance);

            % Minimum practical gap (manufacturing tolerance)
            gap = max(gap, 0.3e-3);

            fprintf('    Insulation %s<->%s: V_diff=%.0fV, %s, gap=%.2fmm (creepage=%.2f, clearance=%.2f)\n', ...
                obj.safe_name(def_a), obj.safe_name(def_b), V_diff, ins_type, gap*1e3, creepage*1e3, clearance*1e3);
        end

        function d = iec_creepage_distance(obj, voltage, ins_type)
            % IEC 60664-1 Table F.4 creepage distance
            % Pollution Degree 2, Material Group III (typical PCB/bobbin)
            %
            % Voltage [V] | Functional | Basic | Reinforced
            %     0-50    |   0.6mm    | 1.0mm |   2.0mm
            %    50-100   |   0.7mm    | 1.0mm |   2.0mm
            %   100-150   |   0.8mm    | 1.3mm |   2.5mm
            %   150-300   |   1.0mm    | 1.6mm |   3.2mm
            %   300-600   |   1.5mm    | 2.5mm |   5.0mm
            %   600-1000  |   2.5mm    | 4.0mm |   8.0mm

            % Voltage breakpoints and corresponding distances (mm)
            V_bp = [0, 50, 100, 150, 300, 600, 1000];

            switch ins_type
                case 'functional'
                    d_bp = [0.3, 0.6, 0.7, 0.8, 1.0, 1.5, 2.5];
                case 'basic'
                    d_bp = [0.5, 1.0, 1.0, 1.3, 1.6, 2.5, 4.0];
                case 'supplementary'
                    d_bp = [0.5, 1.0, 1.0, 1.3, 1.6, 2.5, 4.0];
                case 'reinforced'
                    d_bp = [1.0, 2.0, 2.0, 2.5, 3.2, 5.0, 8.0];
                otherwise
                    d_bp = [0.5, 1.0, 1.0, 1.3, 1.6, 2.5, 4.0];
            end

            % Interpolate
            d = interp1(V_bp, d_bp * 1e-3, min(voltage, 1000), 'linear', d_bp(end) * 1e-3);
        end

        function d = iec_clearance_distance(obj, voltage, ins_type)
            % IEC 60664-1 Table F.2 clearance distance
            % Pollution Degree 2, Overvoltage Category II
            %
            % Voltage [V] | Functional | Basic | Reinforced
            %     0-50    |   0.2mm    | 0.5mm |   1.0mm
            %    50-100   |   0.3mm    | 0.5mm |   1.0mm
            %   100-150   |   0.5mm    | 0.5mm |   1.0mm
            %   150-300   |   0.5mm    | 1.5mm |   3.0mm
            %   300-600   |   1.0mm    | 3.0mm |   6.0mm
            %   600-1000  |   1.5mm    | 5.5mm |  11.0mm

            V_bp = [0, 50, 100, 150, 300, 600, 1000];

            switch ins_type
                case 'functional'
                    d_bp = [0.1, 0.2, 0.3, 0.5, 0.5, 1.0, 1.5];
                case 'basic'
                    d_bp = [0.2, 0.5, 0.5, 0.5, 1.5, 3.0, 5.5];
                case 'supplementary'
                    d_bp = [0.2, 0.5, 0.5, 0.5, 1.5, 3.0, 5.5];
                case 'reinforced'
                    d_bp = [0.4, 1.0, 1.0, 1.0, 3.0, 6.0, 11.0];
                otherwise
                    d_bp = [0.2, 0.5, 0.5, 0.5, 1.5, 3.0, 5.5];
            end

            d = interp1(V_bp, d_bp * 1e-3, min(voltage, 1000), 'linear', d_bp(end) * 1e-3);
        end


        function n = safe_name(obj, def)
            % Return name field or fallback string
            if isfield(def, 'name')
                n = def.name;
            else
                n = '?';
            end
        end


        % ==============================================================
        % WIRE DIMENSION HELPERS
        % ==============================================================
        function [wire_shape, wire_od, wire_w, wire_h] = get_wire_packing_dims(obj, wire)
            % Get wire packing dimensions for any wire type.
            %
            % Returns:
            %   wire_shape - 'round', 'litz', 'rectangular', 'foil'
            %   wire_od    - outer diameter (for round/litz) or max(w,h)
            %   wire_w     - packing width (radial, into bobbin wall)
            %   wire_h     - packing height (axial, along bobbin window)

            insulation_factor = 1.12;
            wire_shape = 'round';

            if isfield(wire, 'type')
                wire_shape = lower(wire.type);
            elseif isfield(wire, 'shape')
                wire_shape = lower(wire.shape);
            end

            switch wire_shape
                case 'round'
                    if isfield(wire, 'outer_diameter')
                        wire_od = wire.outer_diameter;
                    elseif isfield(wire, 'diameter')
                        wire_od = wire.diameter * insulation_factor;
                    else
                        wire_od = 0.65e-3;
                    end
                    wire_w = wire_od;
                    wire_h = wire_od;

                case 'litz'
                    if isfield(wire, 'outer_diameter')
                        wire_od = wire.outer_diameter;
                    elseif isfield(wire, 'diameter')
                        wire_od = wire.diameter;
                    else
                        wire_od = 2e-3;
                    end
                    wire_w = wire_od;
                    wire_h = wire_od;

                case {'rectangular', 'rect'}
                    wire_shape = 'rectangular';
                    wire_w = 0.5e-3; wire_h = 2e-3;
                    if isfield(wire, 'width');  wire_w = wire.width;  end
                    if isfield(wire, 'height'); wire_h = wire.height; end
                    wire_od = max(wire_w, wire_h);

                case 'foil'
                    wire_w = 0.1e-3; wire_h = 10e-3;
                    if isfield(wire, 'thickness');  wire_w = wire.thickness;  end
                    if isfield(wire, 'foil_width'); wire_h = wire.foil_width; end
                    wire_od = max(wire_w, wire_h);

                otherwise
                    if isfield(wire, 'outer_diameter')
                        wire_od = wire.outer_diameter;
                    elseif isfield(wire, 'diameter')
                        wire_od = wire.diameter * insulation_factor;
                    else
                        wire_od = 0.65e-3;
                    end
                    wire_shape = 'round';
                    wire_w = wire_od;
                    wire_h = wire_od;
            end
        end

        function od = get_wire_outer_diameter(obj, wire)
            % Legacy wrapper for backward compatibility.
            [~, od, ~, ~] = obj.get_wire_packing_dims(wire);
        end


        % ==============================================================
        % PACKING ALGORITHMS
        % ==============================================================

        function layout = pack_round_layered(obj, bobbin, wire_od, n_turns)
            % Layered (rectangular grid) packing for round wire.
            % Fill factor ~78.5% (pi/4).

            tpl = floor(bobbin.height / wire_od);
            if tpl < 1; tpl = 1; end
            n_layers = ceil(n_turns / tpl);
            total_width = n_layers * wire_od;

            positions = zeros(n_turns, 2);
            sizes     = repmat([wire_od, wire_od], n_turns, 1);
            idx = 1;
            for layer = 1:n_layers
                x = (layer - 0.5) * wire_od;
                for t = 1:tpl
                    if idx > n_turns; break; end
                    y = (t - 0.5) * wire_od;
                    positions(idx, :) = [x, y];
                    idx = idx + 1;
                end
            end

            layout.fits            = (total_width <= bobbin.width * 1.001);
            layout.n_layers        = n_layers;
            layout.turns_per_layer = tpl;
            layout.required_width  = total_width;
            layout.width_util      = total_width / bobbin.width;
            layout.height_util     = min(1, (tpl * wire_od) / bobbin.height);
            layout.fill_factor     = 0.785 * layout.width_util * layout.height_util;
            layout.pattern         = 'layered';
            layout.wire_shape      = 'round';
            layout.turn_positions  = positions;
            layout.turn_sizes      = sizes;
        end

        function layout = pack_round_orthocyclic(obj, bobbin, wire_od, n_turns)
            % Orthocyclic (hexagonal close-pack) for round wire.
            % Fill factor ~90.7%.

            tpl_odd  = floor(bobbin.height / wire_od);
            tpl_even = floor((bobbin.height - wire_od/2) / wire_od);
            if tpl_odd  < 1; tpl_odd  = 1; end
            if tpl_even < 1; tpl_even = 1; end

            % Count layers needed
            placed = 0; n_layers = 0;
            while placed < n_turns
                n_layers = n_layers + 1;
                if mod(n_layers, 2) == 1
                    placed = placed + tpl_odd;
                else
                    placed = placed + tpl_even;
                end
            end

            layer_pitch = wire_od * 0.866;  % cos(30deg)
            total_width = n_layers * layer_pitch;

            positions = zeros(n_turns, 2);
            sizes     = repmat([wire_od, wire_od], n_turns, 1);
            idx = 1;
            for layer = 1:n_layers
                x = (layer - 0.5) * layer_pitch;
                if mod(layer, 2) == 1
                    tpl = tpl_odd;
                    y_off = 0;
                else
                    tpl = tpl_even;
                    y_off = wire_od / 2;
                end
                for t = 1:tpl
                    if idx > n_turns; break; end
                    y = y_off + (t - 0.5) * wire_od;
                    positions(idx, :) = [x, y];
                    idx = idx + 1;
                end
            end

            layout.fits            = (total_width <= bobbin.width * 1.001);
            layout.n_layers        = n_layers;
            layout.turns_per_layer = tpl_odd;
            layout.required_width  = total_width;
            layout.width_util      = total_width / bobbin.width;
            layout.height_util     = min(1, (tpl_odd * wire_od) / bobbin.height);
            layout.fill_factor     = 0.907 * layout.width_util * layout.height_util;
            layout.pattern         = 'orthocyclic';
            layout.wire_shape      = 'round';
            layout.turn_positions  = positions;
            layout.turn_sizes      = sizes;
        end

        function layout = pack_round_random(obj, bobbin, wire_od, n_turns)
            % Random (hand-wound) packing. Fill factor ~55%.

            eff_d = wire_od / sqrt(0.55);
            tpl = floor(bobbin.height / eff_d);
            if tpl < 1; tpl = 1; end
            n_layers = ceil(n_turns / tpl);
            total_width = n_layers * eff_d;

            positions = zeros(n_turns, 2);
            sizes     = repmat([wire_od, wire_od], n_turns, 1);
            idx = 1;
            for layer = 1:n_layers
                x = (layer - 0.5) * eff_d;
                for t = 1:tpl
                    if idx > n_turns; break; end
                    y = (t - 0.5) * eff_d;
                    positions(idx, :) = [x, y];
                    idx = idx + 1;
                end
            end

            layout.fits            = (total_width <= bobbin.width * 1.001);
            layout.n_layers        = n_layers;
            layout.turns_per_layer = tpl;
            layout.required_width  = total_width;
            layout.width_util      = total_width / bobbin.width;
            layout.height_util     = min(1, (tpl * eff_d) / bobbin.height);
            layout.fill_factor     = 0.55 * layout.width_util * layout.height_util;
            layout.pattern         = 'random';
            layout.wire_shape      = 'round';
            layout.turn_positions  = positions;
            layout.turn_sizes      = sizes;
        end

        function layout = pack_rectangular(obj, bobbin, wire_w, wire_h, n_turns, pattern)
            % Rectangular wire packing (grid with gaps).

            if nargin < 6; pattern = 'layered'; end

            turn_gap  = 50e-6;   % 50um between turns
            layer_gap = 50e-6;   % 50um between layers

            tpl = floor(bobbin.height / (wire_h + turn_gap));
            if tpl < 1; tpl = 1; end
            n_layers = ceil(n_turns / tpl);
            total_width = n_layers * wire_w + max(0, n_layers - 1) * layer_gap;

            positions = zeros(n_turns, 2);
            sizes     = repmat([wire_w, wire_h], n_turns, 1);
            idx = 1;
            for layer = 1:n_layers
                x = (layer - 1) * (wire_w + layer_gap) + wire_w / 2;
                for t = 1:tpl
                    if idx > n_turns; break; end
                    y = (t - 1) * (wire_h + turn_gap) + wire_h / 2;
                    positions(idx, :) = [x, y];
                    idx = idx + 1;
                end
            end

            layout.fits            = (total_width <= bobbin.width * 1.001);
            layout.n_layers        = n_layers;
            layout.turns_per_layer = tpl;
            layout.required_width  = total_width;
            layout.width_util      = total_width / bobbin.width;
            layout.height_util     = min(1, (tpl * (wire_h + turn_gap)) / bobbin.height);
            layout.fill_factor     = (wire_w * wire_h) / ((wire_w + layer_gap) * (wire_h + turn_gap));
            layout.pattern         = pattern;
            layout.wire_shape      = 'rectangular';
            layout.turn_positions  = positions;
            layout.turn_sizes      = sizes;
        end

        function layout = pack_foil(obj, bobbin, foil_thick, foil_width, n_turns)
            % Foil winding: one turn per layer, full bobbin height.

            insulation = 25e-6;  % 25um interlayer insulation
            layer_pitch = foil_thick + insulation;
            total_width = n_turns * layer_pitch;

            positions = zeros(n_turns, 2);
            sizes     = repmat([foil_thick, foil_width], n_turns, 1);
            for t = 1:n_turns
                x = (t - 0.5) * layer_pitch;
                y = bobbin.height / 2;
                positions(t, :) = [x, y];
            end

            layout.fits            = (total_width <= bobbin.width * 1.001);
            layout.n_layers        = n_turns;
            layout.turns_per_layer = 1;
            layout.required_width  = total_width;
            layout.width_util      = total_width / bobbin.width;
            layout.height_util     = min(1, foil_width / bobbin.height);
            layout.fill_factor     = foil_thick / layer_pitch;
            layout.pattern         = 'foil';
            layout.wire_shape      = 'foil';
            layout.turn_positions  = positions;
            layout.turn_sizes      = sizes;
        end


        % ==============================================================
        % VISUALIZATION
        % ==============================================================
        function visualize_layout(obj, layout, ax_handle)
            % Draw a single winding layout in the given axes.

            if nargin < 3 || isempty(ax_handle)
                figure('Name', 'Winding Layout', 'Position', [100 100 800 600]);
                ax_handle = gca;
            end

            axes(ax_handle);
            cla(ax_handle);
            hold(ax_handle, 'on');
            axis(ax_handle, 'equal');

            % Bobbin outline
            rectangle('Position', [0, 0, layout.bobbin.width, layout.bobbin.height], ...
                'EdgeColor', 'k', 'LineWidth', 2, 'LineStyle', '--', 'Parent', ax_handle);

            % Draw turns
            n = size(layout.turn_positions, 1);
            for i = 1:n
                x = layout.turn_positions(i, 1);
                y = layout.turn_positions(i, 2);

                if isfield(layout, 'wire_shape') && ...
                        (strcmp(layout.wire_shape, 'rectangular') || strcmp(layout.wire_shape, 'foil'))
                    w = layout.turn_sizes(i, 1);
                    h = layout.turn_sizes(i, 2);
                    rectangle('Position', [x - w/2, y - h/2, w, h], ...
                        'FaceColor', [0.6 0.8 1.0], 'EdgeColor', 'b', ...
                        'LineWidth', 0.5, 'Parent', ax_handle);
                else
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

        function visualize_multi_layout(obj, layouts, ax_handle, winding_colors)
            % Draw multiple winding layouts in a single bobbin view.
            % This is the proper Core Window Fit visualization.

            if nargin < 3 || isempty(ax_handle)
                figure('Name', 'Multi-Winding Layout', 'Position', [100 100 900 600]);
                ax_handle = gca;
            end
            if nargin < 4 || isempty(winding_colors)
                winding_colors = {[0.2 0.4 0.8], [0.8 0.2 0.2], [0.2 0.7 0.3], [0.7 0.5 0.1]};
            end

            axes(ax_handle);
            cla(ax_handle);
            hold(ax_handle, 'on');
            axis(ax_handle, 'equal');

            bobbin = layouts{1}.bobbin;

            % Bobbin outline
            rectangle('Position', [0, 0, bobbin.width, bobbin.height], ...
                'EdgeColor', 'k', 'LineWidth', 2, 'LineStyle', '--', 'Parent', ax_handle);
            text(bobbin.width/2, bobbin.height + 0.001, 'Bobbin Window', ...
                'Parent', ax_handle, 'HorizontalAlignment', 'center', ...
                'FontSize', 9, 'FontWeight', 'bold');

            % Draw each winding
            for w = 1:length(layouts)
                lay = layouts{w};
                c_idx = mod(w-1, length(winding_colors)) + 1;
                col = winding_colors{c_idx};

                n = size(lay.turn_positions, 1);
                for i = 1:n
                    x = lay.turn_positions(i, 1);
                    y = lay.turn_positions(i, 2);

                    if strcmp(lay.wire_shape, 'rectangular') || strcmp(lay.wire_shape, 'foil')
                        tw = lay.turn_sizes(i, 1);
                        th = lay.turn_sizes(i, 2);
                        rectangle('Position', [x - tw/2, y - th/2, tw, th], ...
                            'FaceColor', col, 'EdgeColor', 'k', ...
                            'LineWidth', 0.3, 'Parent', ax_handle);
                    else
                        r = lay.wire_od / 2;
                        theta = linspace(0, 2*pi, 30);
                        fill(ax_handle, x + r*cos(theta), y + r*sin(theta), col, ...
                            'EdgeColor', 'k', 'LineWidth', 0.3);
                    end
                end

                % Label
                label_x = lay.section_x_offset + lay.section_width / 2;
                if isfield(lay, 'winding_name')
                    text(label_x, -0.0005, lay.winding_name, ...
                        'Parent', ax_handle, 'HorizontalAlignment', 'center', ...
                        'FontSize', 8, 'Color', col, 'FontWeight', 'bold');
                end

                % Draw section boundary (light gray dashed)
                sx = lay.section_x_offset;
                sw = lay.section_width;
                rectangle('Position', [sx, 0, sw, bobbin.height], ...
                    'EdgeColor', [0.7 0.7 0.7], 'LineWidth', 0.5, ...
                    'LineStyle', ':', 'Parent', ax_handle);
            end

            xlim(ax_handle, [-0.001, bobbin.width + 0.001]);
            ylim(ax_handle, [-0.002, bobbin.height + 0.002]);
            xlabel(ax_handle, 'Width (m)');
            ylabel(ax_handle, 'Height (m)');

            hold(ax_handle, 'off');
        end

    end  % methods
end  % classdef
