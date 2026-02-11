% interactive_winding_designer.m
% Interactive GUI for designing multi-filar transformer windings
% Layout: Core (left) | Windings (center) | Visualization (right)
% Fixes: Layout-matched analysis, rect wire viz, OM wire info, supplier cascade

function interactive_winding_designer()

    close all;

    % Initialize global data structure
    data = struct();

    % Initialize OpenMagnetics API
    data.api = openmagnetics_api_interface();
    data.data_mode = 'offline';
    data.online_url = 'http://localhost:8484';

    % Initialize layout calculator
    data.layout_calc = openmagnetics_winding_layout(data.api);

    % Load databases
    data.wires = data.api.get_wires();
    data.cores = data.api.get_cores();
    data.materials = data.api.get_materials();
    data.suppliers = data.api.get_suppliers();
    data.wire_options = build_wire_option_lists(data.wires);

    % Default transformer configuration
    data.n_windings = 2;
    data.winding_names = {'Primary', 'Secondary'};
    data.winding_colors = {[0.2 0.4 0.8], [0.8 0.2 0.2]};
    data.section_order = '12';

    % Default winding parameters
    data.windings(1).name = 'Primary';
    data.windings(1).n_turns = 10;
    data.windings(1).n_filar = 1;
    data.windings(1).current = 10;
    data.windings(1).phase = 0;
    data.windings(1).wire_type = 'AWG_22';
    data.windings(1).wire_shape = 'round';
    data.windings(1).voltage = 0;
    data.windings(1).wire_insulation = 'standard';

    data.windings(2).name = 'Secondary';
    data.windings(2).n_turns = 5;
    data.windings(2).n_filar = 1;
    data.windings(2).current = 5;
    data.windings(2).phase = 180;
    data.windings(2).wire_type = 'AWG_22';
    data.windings(2).wire_shape = 'round';
    data.windings(2).voltage = 0;
    data.windings(2).wire_insulation = 'standard';

    % Default supplier & core selection
    if ~isempty(data.suppliers)
        data.selected_supplier = data.suppliers{1};
    else
        data.selected_supplier = 'TDK';
    end

    % Get cores for default supplier
    supplier_cores = data.api.get_cores_by_supplier(data.selected_supplier);
    if ~isempty(supplier_cores)
        data.selected_core = supplier_cores{1};
    else
        core_list = fieldnames(data.cores);
        if ~isempty(core_list)
            data.selected_core = core_list{1};
        else
            data.selected_core = 'None';
        end
    end

    % Default material for this supplier
    supplier_mats = data.api.get_materials_by_supplier(data.selected_supplier);
    if ~isempty(supplier_mats)
        data.selected_material = supplier_mats{1};
    else
        mat_list = fieldnames(data.materials);
        if ~isempty(mat_list)
            data.selected_material = mat_list{1};
        else
            data.selected_material = 'N87';
        end
    end

    % Geometry parameters
    [w, h, shape] = data.api.wire_to_conductor_dims(data.windings(1).wire_type);
    data.width = w;
    data.height = h;
    data.windings(1).wire_shape = shape;
    data.windings(2).wire_shape = shape;
    data.gap_layer = 0.2e-3;
    data.gap_filar = 0.05e-3;
    data.gap_winding = 0.0e-3;

    % Core air gap parameters
    data.core_gap_type = 'Ungapped';   % Ungapped, Ground, Spacer, Distributed
    data.core_gap_length = 0;          % Gap length in meters (0 = ungapped)
    data.core_num_gaps = 1;            % Number of gaps
    data.insulation_class = 'basic';
    data.insulation_standard = 'IEC 60664-1';
    data.overvoltage_category = 'OVC-II';
    data.pollution_degree = 2;
    data.cti_group = 'Group II';
    data.altitude_m = 0;
    data.wiring_technology = 'Wound';
    data.allow_margin_tape = true;
    data.allow_insulated_wire = true;
    data.tape_thickness = 0.05e-3;
    data.tape_layers = 1;
    data.tape_kv_per_mm = 120;  % user-adjustable estimate
    data.edge_margin = 0.0e-3;
    data.tiw_kv = 3.0;

    % Analysis parameters
    data.sigma = 5.8e7;
    data.mu0 = 4*pi*1e-7;
    data.f = 100e3;
    data.Nx = 6;
    data.Ny = 6;

    % Create main GUI figure
    scr = get(0, 'ScreenSize');
    fig_w = min(1800, max(1200, scr(3) - 100));
    fig_h = min(900, max(700, scr(4) - 120));
    fig_w = min(fig_w, max(900, scr(3) - 40));
    fig_h = min(fig_h, max(650, scr(4) - 80));
    fig_x = max(20, floor((scr(3) - fig_w) / 2));
    fig_y = max(20, floor((scr(4) - fig_h) / 2));
    data.fig_gui = figure('Name', 'Interactive Transformer Design Tool [Offline Mode]', ...
                          'Position', [fig_x fig_y fig_w fig_h], ...
                          'NumberTitle', 'off', ...
                          'MenuBar', 'none', ...
                          'Resize', 'on');

    data.fig_results = [];

    % Build GUI layout
    build_gui(data);

    % Initial visualization
    update_visualization(data);
end

% ===============================================================
% BUILD GUI
% ===============================================================

function build_gui(data)

    fig = data.fig_gui;

    % Main title
    uicontrol('Parent', fig, 'Style', 'text', ...
              'String', 'Interactive Transformer Design Tool [Offline Mode]', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.94 0.96 0.045], ...
              'FontSize', 17, 'FontWeight', 'bold', ...
              'HorizontalAlignment', 'center', ...
              'Tag', 'main_title');

    % Data mode controls (top bar)
    uicontrol('Parent', fig, 'Style', 'text', ...
              'String', 'Data Mode:', ...
              'Position', [560 35 80 18], ...
              'FontWeight', 'bold', 'HorizontalAlignment', 'left');

    uicontrol('Parent', fig, 'Style', 'popupmenu', ...
              'String', {'Offline', 'Online (OM Server)'}, ...
              'Position', [650 32 200 25], ...
              'Tag', 'data_mode', ...
              'Callback', @update_data_mode);

    uicontrol('Parent', fig, 'Style', 'text', ...
              'String', 'Server URL:', ...
              'Position', [560 8 80 18], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', fig, 'Style', 'edit', ...
              'String', data.online_url, ...
              'Position', [650 5 240 25], ...
              'Tag', 'server_url', ...
              'Callback', @update_server_url);

    uicontrol('Parent', fig, 'Style', 'text', ...
              'String', 'Status: Offline', ...
              'Position', [900 8 300 18], ...
              'HorizontalAlignment', 'left', ...
              'Tag', 'data_mode_status');

    % ========== LEFT PANEL: CORE SELECTION (with supplier cascade) ==========
    core_panel = uipanel('Parent', fig, ...
                        'Position', [0.02 0.16 0.29 0.76], ...
                        'Title', 'Core Selection (OpenMagnetics)', ...
                        'FontSize', 11, 'FontWeight', 'bold');

    % --- Supplier dropdown ---
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Supplier:', ...
              'Position', [20 530 120 20], ...
              'FontWeight', 'bold', 'HorizontalAlignment', 'left');

    supplier_list = data.suppliers;
    if isempty(supplier_list); supplier_list = {'TDK'}; end

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', supplier_list, ...
              'Position', [20 508 380 25], ...
              'Tag', 'supplier_dropdown', ...
              'Callback', @select_supplier);

    % --- Core Shape dropdown (filtered by supplier) ---
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Core Shape:', ...
              'Position', [20 480 120 20], ...
              'HorizontalAlignment', 'left');

    supplier_cores = data.api.get_cores_by_supplier(data.selected_supplier);
    if isempty(supplier_cores); supplier_cores = fieldnames(data.cores); end

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', supplier_cores, ...
              'Position', [20 458 380 25], ...
              'Tag', 'core_dropdown', ...
              'Callback', @select_core);

    % Core information display
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Core Information:', ...
              'Position', [20 430 150 20], ...
              'FontWeight', 'bold', 'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', get_core_info_text(data), ...
              'Position', [20 345 380 85], ...
              'HorizontalAlignment', 'left', ...
              'BackgroundColor', [0.95 0.95 0.95], ...
              'Tag', 'core_info');

    % --- Material dropdown (filtered by supplier) ---
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Core Material:', ...
              'Position', [20 318 120 20], ...
              'HorizontalAlignment', 'left');

    supplier_mats = data.api.get_materials_by_supplier(data.selected_supplier);
    if isempty(supplier_mats); supplier_mats = fieldnames(data.materials); end

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', supplier_mats, ...
              'Position', [20 296 380 25], ...
              'Tag', 'material_dropdown', ...
              'Callback', @select_material);

    % Material info
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', get_material_info_text(data), ...
              'Position', [20 240 380 55], ...
              'HorizontalAlignment', 'left', ...
              'BackgroundColor', [0.95 0.95 0.95], ...
              'Tag', 'material_info');

    % --- Gap Configuration ---
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Gap Configuration:', ...
              'Position', [20 212 180 20], ...
              'FontWeight', 'bold', 'HorizontalAlignment', 'left');

    % Gap Type
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Type:', ...
              'Position', [30 190 50 20], ...
              'HorizontalAlignment', 'left');

    gap_types = {'Ungapped', 'Ground', 'Spacer', 'Distributed'};
    gap_idx = find(strcmp(gap_types, data.core_gap_type), 1);
    if isempty(gap_idx); gap_idx = 1; end

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', gap_types, ...
              'Position', [130 190 200 25], ...
              'Value', gap_idx, ...
              'Tag', 'gap_type_dropdown', ...
              'TooltipString', 'Gap type: Ground=subtractive, Spacer=additive, Distributed=multiple gaps', ...
              'Callback', @update_gap_type);

    % Gap Length
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Length:', ...
              'Position', [30 165 50 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.core_gap_length * 1e3), ...
              'Position', [130 165 80 25], ...
              'Tag', 'gap_length', ...
              'Enable', 'off', ...
              'Callback', @update_gap_length);

    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'mm', ...
              'Position', [215 165 30 20], ...
              'HorizontalAlignment', 'left', ...
              'Tag', 'gap_length_unit');

    % Number of Gaps
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'No. Gaps:', ...
              'Position', [260 165 60 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.core_num_gaps), ...
              'Position', [330 165 60 25], ...
              'Tag', 'gap_num', ...
              'Enable', 'off', ...
              'Callback', @update_num_gaps);

    % Frequency input
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Operating Frequency (kHz):', ...
              'Position', [20 132 180 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.f/1e3), ...
              'Position', [210 132 80 25], ...
              'Tag', 'frequency', ...
              'Callback', @update_frequency);

    % Insulation class dropdown
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Insulation Class:', ...
              'Position', [20 105 180 20], ...
              'HorizontalAlignment', 'left');

    insulation_list = {'functional', 'basic', 'supplementary', 'reinforced'};
    ins_idx = find(strcmp(insulation_list, data.insulation_class), 1);
    if isempty(ins_idx); ins_idx = 2; end

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', insulation_list, ...
              'Position', [210 105 180 25], ...
              'Value', ins_idx, ...
              'Tag', 'insulation_class', ...
              'Callback', @update_insulation_class);

    % Tape thickness + layers
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Tape Thickness (mm):', ...
              'Position', [20 78 180 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.tape_thickness * 1e3), ...
              'Position', [210 78 60 25], ...
              'Tag', 'tape_thickness', ...
              'Callback', @update_tape_thickness);

    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Layers:', ...
              'Position', [280 78 60 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.tape_layers), ...
              'Position', [340 78 60 25], ...
              'Tag', 'tape_layers', ...
              'Callback', @update_tape_layers);

    % Tape strength + TIW rating
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Tape Strength (kV/mm):', ...
              'Position', [20 51 180 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.tape_kv_per_mm), ...
              'Position', [210 51 60 25], ...
              'Tag', 'tape_strength', ...
              'Callback', @update_tape_strength);

    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'TIW kV:', ...
              'Position', [280 51 60 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.tiw_kv), ...
              'Position', [340 51 60 25], ...
              'Tag', 'tiw_kv', ...
              'Callback', @update_tiw_kv);

    % Edge margin (mm)
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Edge Margin (mm):', ...
              'Position', [20 24 180 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.edge_margin * 1e3), ...
              'Position', [210 24 80 25], ...
              'Tag', 'edge_margin', ...
              'Callback', @update_edge_margin);

    % ========== CENTER PANEL: WINDING CONFIGURATION ==========
    winding_panel = uipanel('Parent', fig, ...
                           'Position', [0.33 0.16 0.34 0.76], ...
                           'Title', 'Winding Configuration', ...
                           'FontSize', 11, 'FontWeight', 'bold');

    % Tab buttons
    tab_group = uibuttongroup('Parent', winding_panel, ...
                              'Position', [0.02 0.90 0.96 0.08], ...
                              'BorderType', 'none');

    for w = 1:data.n_windings
        uicontrol('Parent', tab_group, 'Style', 'togglebutton', ...
                  'String', data.windings(w).name, ...
                  'Position', [10 + (w-1)*130, 6, 120, 28], ...
                  'FontSize', 10, ...
                  'Tag', sprintf('tab%d', w), ...
                  'Callback', {@switch_tab, w});
    end
    set(findobj(tab_group, 'Tag', 'tab1'), 'Value', 1);

    % Content panels for each winding
    for w = 1:data.n_windings
        panel = uipanel('Parent', winding_panel, ...
                        'Position', [0.02 0.02 0.96 0.86], ...
                        'Visible', 'off', ...
                        'Tag', sprintf('content%d', w));

        % Winding name header
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', sprintf('%s Winding', data.windings(w).name), ...
                  'Position', [20 480 300 25], ...
                  'FontSize', 12, 'FontWeight', 'bold', ...
                  'HorizontalAlignment', 'left');

        % --- Wire Type dropdown ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Wire Type:', ...
                  'Position', [20 430 100 20], ...
                  'FontWeight', 'bold', 'HorizontalAlignment', 'left');

        wire_list = fieldnames(data.wires);
        if isempty(wire_list); wire_list = {'AWG_22'}; end
        wire_idx = find(strcmp(wire_list, data.windings(w).wire_type), 1);
        if isempty(wire_idx); wire_idx = 1; end

        uicontrol('Parent', panel, 'Style', 'popupmenu', ...
                  'String', wire_list, ...
                  'Position', [130 430 230 25], ...
                  'Value', wire_idx, ...
                  'Tag', sprintf('wire_type_%d', w), ...
                  'Callback', {@select_wire, w});

        % --- Wire Standard dropdown ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Standard:', ...
                  'Position', [20 395 100 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'popupmenu', ...
                  'String', data.wire_options.standards, ...
                  'Position', [130 395 230 25], ...
                  'Tag', sprintf('wire_std_%d', w), ...
                  'Callback', {@select_wire_attribute, w, 'standard'});

        % --- Conductor diameter dropdown ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Cond. diameter:', ...
                  'Position', [20 360 120 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'popupmenu', ...
                  'String', data.wire_options.cond_diameters, ...
                  'Position', [130 360 230 25], ...
                  'Tag', sprintf('wire_diam_%d', w), ...
                  'Callback', {@select_wire_attribute, w, 'cond_diameter'});

        % --- Coating dropdown ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Coating:', ...
                  'Position', [20 325 100 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'popupmenu', ...
                  'String', data.wire_options.coatings, ...
                  'Position', [130 325 230 25], ...
                  'Tag', sprintf('wire_coat_%d', w), ...
                  'Callback', {@select_wire_attribute, w, 'coating'});

        % --- Wire insulation type ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Wire Insulation:', ...
                  'Position', [20 290 120 20], ...
                  'HorizontalAlignment', 'left');

        insulation_opts = {'Standard', 'TIW'};
        if isfield(data.windings(w), 'wire_insulation') && strcmpi(data.windings(w).wire_insulation, 'tiw')
            ins_val = 2;
        else
            ins_val = 1;
        end

        uicontrol('Parent', panel, 'Style', 'popupmenu', ...
                  'String', insulation_opts, ...
                  'Position', [130 290 230 25], ...
                  'Value', ins_val, ...
                  'Tag', sprintf('wire_insulation_%d', w), ...
                  'Callback', {@update_wire_insulation, w});

        % --- No. Turns ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'No. Turns:', ...
                  'Position', [20 255 120 20], ...
                  'FontWeight', 'bold', 'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                  'String', '-', ...
                  'Position', [180 255 30 25], ...
                  'FontSize', 14, ...
                  'Callback', {@adjust_turns, w, -1});

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).n_turns), ...
                  'Position', [215 255 60 25], ...
                  'FontSize', 11, 'HorizontalAlignment', 'center', ...
                  'Tag', sprintf('turns_val_%d', w), ...
                  'Callback', {@update_turns_manual, w});

        uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                  'String', '+', ...
                  'Position', [280 255 30 25], ...
                  'FontSize', 14, ...
                  'Callback', {@adjust_turns, w, 1});

        % --- No. Parallels (Filar) ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'No. Parallels:', ...
                  'Position', [20 220 120 20], ...
                  'FontWeight', 'bold', 'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                  'String', '-', ...
                  'Position', [180 220 30 25], ...
                  'FontSize', 14, ...
                  'Callback', {@adjust_filar, w, -1});

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).n_filar), ...
                  'Position', [215 220 60 25], ...
                  'FontSize', 11, 'HorizontalAlignment', 'center', ...
                  'Tag', sprintf('filar_val_%d', w), ...
                  'Callback', {@update_filar_manual, w});

        uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                  'String', '+', ...
                  'Position', [280 220 30 25], ...
                  'FontSize', 14, ...
                  'Callback', {@adjust_filar, w, 1});

        % Filar type label
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', get_filar_name(data.windings(w).n_filar), ...
                  'Position', [305 220 80 25], ...
                  'FontSize', 9, 'FontWeight', 'bold', ...
                  'HorizontalAlignment', 'left', ...
                  'ForegroundColor', [0.2 0.6 0.2], ...
                  'Tag', sprintf('filar_name_%d', w));

        % --- RMS Current ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'RMS Current (A):', ...
                  'Position', [20 180 150 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).current), ...
                  'Position', [180 180 80 25], ...
                  'Tag', sprintf('current_%d', w), ...
                  'Callback', {@update_current, w});

        % --- Voltage ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Voltage (V):', ...
                  'Position', [20 150 150 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).voltage), ...
                  'Position', [180 150 80 25], ...
                  'Tag', sprintf('voltage_%d', w), ...
                  'Callback', {@update_voltage, w});

        % --- Phase ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Phase (degrees):', ...
                  'Position', [20 120 150 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).phase), ...
                  'Position', [180 120 80 25], ...
                  'Tag', sprintf('phase_%d', w), ...
                  'Callback', {@update_phase, w});

        % --- Configuration Summary ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Configuration Summary:', ...
                  'Position', [20 90 300 20], ...
                  'FontSize', 10, 'FontWeight', 'bold', ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', get_winding_summary(data, w), ...
                  'Position', [20 5 360 80], ...
                  'HorizontalAlignment', 'left', ...
                  'VerticalAlignment', 'top', ...
                  'Tag', sprintf('summary_%d', w));
    end

    % Show first panel
    set(findobj(winding_panel, 'Tag', 'content1'), 'Visible', 'on');

    % Initial wire info update
    for w = 1:data.n_windings
        update_wire_info_fields(fig, data, w);
    end

    % ========== RIGHT PANEL: VISUALIZATION ==========
    vis_panel = uipanel('Parent', fig, ...
                        'Position', [0.69 0.16 0.29 0.76], ...
                        'Title', 'Winding Layout in Core Window', ...
                        'FontSize', 11, 'FontWeight', 'bold');

    uicontrol('Parent', vis_panel, 'Style', 'text', ...
              'String', 'View Mode:', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.92 0.18 0.05], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', vis_panel, 'Style', 'popupmenu', ...
              'String', {'Schematic (2D)', 'Core Window Fit', 'OpenMagnetics View', 'Loss Analysis'}, ...
              'Units', 'normalized', ...
              'Position', [0.20 0.92 0.40 0.06], ...
              'Value', 2, ...
              'Tag', 'vis_mode', ...
              'Callback', @change_vis_mode);

    uicontrol('Parent', vis_panel, 'Style', 'text', ...
              'String', 'Packing:', ...
              'Units', 'normalized', ...
              'Position', [0.62 0.92 0.14 0.05], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', vis_panel, 'Style', 'popupmenu', ...
              'String', {'Layered', 'Orthocyclic', 'Random'}, ...
              'Units', 'normalized', ...
              'Position', [0.76 0.92 0.22 0.06], ...
              'Value', 1, ...
              'Tag', 'packing_pattern', ...
              'Callback', @change_packing);

    uicontrol('Parent', vis_panel, 'Style', 'text', ...
              'String', 'Section Interl. Order:', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.84 0.30 0.05], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', vis_panel, 'Style', 'edit', ...
              'String', data.section_order, ...
              'Units', 'normalized', ...
              'Position', [0.32 0.84 0.24 0.06], ...
              'Tag', 'section_order', ...
              'Callback', @update_section_order);

    axes('Parent', vis_panel, ...
         'Position', [0.08 0.08 0.88 0.70], ...
         'Tag', 'vis_axes');

    uicontrol('Parent', vis_panel, 'Style', 'text', ...
              'String', '', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.01 0.96 0.06], ...
              'HorizontalAlignment', 'left', ...
              'BackgroundColor', [0.95 0.95 1.0], ...
              'FontSize', 8, ...
              'Tag', 'vis_info');

    % ========== BOTTOM BUTTONS ==========
    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
              'String', 'Run Analysis', ...
              'Position', [650 60 150 40], ...
              'FontSize', 12, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.2 0.7 0.3], ...
              'ForegroundColor', 'w', ...
              'Callback', @run_analysis);

    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
              'String', 'Reset to Defaults', ...
              'Position', [820 60 150 40], ...
              'FontSize', 11, ...
              'Callback', @reset_defaults);

    guidata(fig, data);
end

% ===============================================================
% WIRE INFO FIELD UPDATER (Issue #3)
% ===============================================================

function update_wire_info_fields(fig, data, w)
    wire_type = data.windings(w).wire_type;
    wire = data.api.get_wire_info(wire_type);

    % Keep wire type dropdown in sync
    wire_dd = findobj(fig, 'Tag', sprintf('wire_type_%d', w));
    set_popup_value(wire_dd, wire_type);

    % Standard dropdown
    if isfield(wire, 'standard')
        set_popup_value(findobj(fig, 'Tag', sprintf('wire_std_%d', w)), wire.standard);
    end

    % Conductor diameter dropdown
    if isfield(wire, 'cond_diameter')
        set_popup_value(findobj(fig, 'Tag', sprintf('wire_diam_%d', w)), wire.cond_diameter);
    end

    % Coating dropdown
    if isfield(wire, 'coating')
        set_popup_value(findobj(fig, 'Tag', sprintf('wire_coat_%d', w)), wire.coating);
    end

    % Wire insulation dropdown
    ins_dd = findobj(fig, 'Tag', sprintf('wire_insulation_%d', w));
    if ~isempty(ins_dd) && ishandle(ins_dd)
        if isfield(data.windings(w), 'wire_insulation') && strcmpi(data.windings(w).wire_insulation, 'tiw')
            set(ins_dd, 'Value', 2);
        else
            set(ins_dd, 'Value', 1);
        end
    end
end

% ===============================================================
% INFO TEXT GENERATORS
% ===============================================================

function str = get_core_info_text(data)
    if strcmp(data.selected_core, 'None')
        str = 'No core selected';
        return;
    end

    core = data.cores.(data.selected_core);
    str = sprintf('Shape: %s\n', core.shape);
    if isfield(core, 'manufacturer')
        str = [str sprintf('Manufacturer: %s\n', core.manufacturer)];
    end
    if isfield(core, 'material')
        str = [str sprintf('Material: %s\n', core.material)];
    end
    if isfield(core, 'Ae')
        str = [str sprintf('Ae: %.1f mm^2\n', core.Ae*1e6)];
    end
    if isfield(core, 'le')
        str = [str sprintf('le: %.1f mm\n', core.le*1e3)];
    end
    if isfield(core, 'Ve')
        str = [str sprintf('Ve: %.1f mm^3\n', core.Ve*1e9)];
    end
    if isfield(core, 'bobbin')
        str = [str sprintf('Bobbin: %.1f x %.1f mm', ...
            core.bobbin.width*1e3, core.bobbin.height*1e3)];
    end
end

function str = get_material_info_text(data)
    mat_name = data.selected_material;
    if ~isfield(data.materials, mat_name)
        str = 'No material data';
        return;
    end

    mat = data.materials.(mat_name);
    str = sprintf('Material: %s\n', mat_name);
    if isfield(mat, 'manufacturer')
        str = [str sprintf('Mfg: %s\n', mat.manufacturer)];
    end
    if isfield(mat, 'mu_initial')
        str = [str sprintf('ui: %d\n', mat.mu_initial)];
    end
    if isfield(mat, 'Bsat')
        str = [str sprintf('Bsat: %.2f T\n', mat.Bsat)];
    end
end

function str = get_winding_summary(data, winding)
    n_cond = data.windings(winding).n_turns * data.windings(winding).n_filar;
    I_per_strand = data.windings(winding).current / data.windings(winding).n_filar;

    wire_type = data.windings(winding).wire_type;
    wire = data.api.get_wire_info(wire_type);
    [w, h, shape] = data.api.wire_to_conductor_dims(wire_type);

    if isfield(wire, 'area') && wire.area > 0
        J_eff = I_per_strand / (wire.area * 1e6);  % A/mm^2
        j_str = sprintf('Eff. current density: %.2f A/mm^2', J_eff);
    else
        j_str = 'Eff. current density: n/a';
    end

    iso_str = get_isolation_summary(data, winding);

    str = sprintf('Total conductors: %d\nCurrent per strand: %.2f A\nConductor size: %.3f x %.3f mm\nShape: %s | %s\n%s', ...
        n_cond, I_per_strand, w*1e3, h*1e3, shape, iso_str, j_str);
end

function iso_str = get_isolation_summary(data, winding)
    if winding >= data.n_windings
        iso_str = 'Iso: n/a';
        return;
    end

    req = compute_insulation_requirements(data, winding, winding+1);

    tape_layers = 0;
    tape_gap_mm = 0;
    if isfield(data, 'tape_thickness') && isfield(data, 'tape_layers')
        tape_layers = max(0, data.tape_layers);
        tape_gap_mm = data.tape_thickness * tape_layers * 1e3;
    end

    edge_margin_mm = 0;
    if isfield(data, 'edge_margin')
        edge_margin_mm = max(0, data.edge_margin) * 1e3;
    end

    req_layers = req.tape_layers_required;
    req_gap_mm = req.tape_thickness * req_layers * 1e3;
    req_edge_mm = req.margin_distance * 0.5 * 1e3;

    tape_ok = (req_layers == 0) || (tape_layers >= req_layers);
    edge_ok = (req.margin_distance <= 0) || (edge_margin_mm >= req_edge_mm);

    status = 'OK';
    if ~(tape_ok && edge_ok)
        status = 'Need';
    end

    iso_str = sprintf(['Iso req: dV=%.0fV %s | withstand %.0fV | ' ...
                       'tape %dL (%.2fmm), edge >= %.2fmm\n' ...
                       'Iso act: tape %dL (%.2fmm), edge %.2fmm [%s]'], ...
                       req.Vdiff, req.insulation_class, req.withstand_voltage, ...
                       req_layers, req_gap_mm, req_edge_mm, ...
                       tape_layers, tape_gap_mm, edge_margin_mm, status);
end

function iso_str = get_isolation_summary_legacy(data, winding)
    if winding >= data.n_windings
        iso_str = 'Iso: n/a';
        return;
    end

    V1 = 0;
    V2 = 0;
    if isfield(data.windings(winding), 'voltage')
        V1 = data.windings(winding).voltage;
    end
    if isfield(data.windings(winding+1), 'voltage')
        V2 = data.windings(winding+1).voltage;
    end
    Vdiff = abs(V1 - V2);

    class = data.insulation_class;
    req_mult = get_insulation_multiplier(class);
    req_v = Vdiff * req_mult;

    tape_gap_mm = 0;
    tape_layers = 0;
    if isfield(data, 'tape_thickness') && isfield(data, 'tape_layers')
        tape_layers = max(0, data.tape_layers);
        tape_gap_mm = data.tape_thickness * tape_layers * 1e3;
    end

    layer_v = get_tape_layer_breakdown_v(data);
    tape_v = tape_layers * layer_v;

    tiw_v = 0;
    if is_tiw_used(data, winding, winding+1) && isfield(data, 'tiw_kv')
        tiw_v = data.tiw_kv * 1e3;
    end

    available_v = max(tape_v, tiw_v);
    if layer_v <= 0 && tiw_v <= 0
        avail_str = 'avail=n/a';
    else
        status = 'OK';
        if available_v < req_v
            status = 'Need';
        end
        avail_str = sprintf('avail=%.0fV %s', available_v, status);
    end

    iso_str = sprintf('Iso: ΔV=%.0fV %s, tape %dL (%.2fmm), %s', ...
        Vdiff, class, tape_layers, tape_gap_mm, avail_str);
end

function mult = get_insulation_multiplier(class)
    if ~ischar(class)
        mult = 1.0;
        return;
    end
    switch lower(class)
        case 'functional'
            mult = 1.0;
        case 'basic'
            mult = 1.0;
        case 'supplementary'
            mult = 2.0;
        case 'reinforced'
            mult = 3.0;
        otherwise
            mult = 1.0;
    end
end

function req = compute_insulation_requirements(data, winding_a, winding_b)
    req = struct();
    req.Vdiff = 0;
    req.withstand_voltage = 0;
    req.clearance = 0;
    req.creepage = 0;
    req.margin_distance = 0;
    req.distance_through_insulation = 0;
    req.tape_layers_required = 0;
    req.tape_thickness = 0;
    req.insulation_class = data.insulation_class;

    V1 = 0;
    V2 = 0;
    if winding_a >= 1 && winding_a <= data.n_windings && isfield(data.windings(winding_a), 'voltage')
        V1 = data.windings(winding_a).voltage;
    end
    if winding_b >= 1 && winding_b <= data.n_windings && isfield(data.windings(winding_b), 'voltage')
        V2 = data.windings(winding_b).voltage;
    end
    Vdiff = abs(V1 - V2);
    req.Vdiff = Vdiff;

    std_name = 'IEC 60664-1';
    if isfield(data, 'insulation_standard')
        std_name = data.insulation_standard;
    end

    if local_contains(std_name, '60664')
        req = iec60664_requirements(data, Vdiff, data.insulation_class);
    else
        req.insulation_class = data.insulation_class;
        req.Vdiff = Vdiff;
        req.withstand_voltage = Vdiff * get_insulation_multiplier(data.insulation_class);
        req.clearance = 0;
        req.creepage = 0;
        req.margin_distance = 0;
        req.distance_through_insulation = 0;
    end

    tape_thickness = 0;
    if isfield(data, 'tape_thickness')
        tape_thickness = max(0, data.tape_thickness);
    end
    req.tape_thickness = tape_thickness;

    layer_v = get_tape_layer_breakdown_v(data);
    req_layers = 0;
    if tape_thickness > 0 && layer_v > 0 && req.withstand_voltage > 0
        req_layers = max(1, ceil(req.withstand_voltage / layer_v));
    end

    if req.distance_through_insulation > 0 && tape_thickness > 0
        req_layers = max(req_layers, ceil(req.distance_through_insulation / tape_thickness));
    end

    if is_tiw_used(data, winding_a, winding_b) && isfield(data, 'allow_insulated_wire') && data.allow_insulated_wire
        req_layers = max(1, req_layers);
        req.margin_distance = 0;
    end

    req.tape_layers_required = req_layers;
end

function req = iec60664_requirements(data, Vdiff, insulation_class)
    req = struct();
    req.Vdiff = Vdiff;
    req.insulation_class = insulation_class;
    req.withstand_voltage = 0;
    req.clearance = 0;
    req.creepage = 0;
    req.margin_distance = 0;
    req.distance_through_insulation = 0;
    req.tape_layers_required = 0;
    req.tape_thickness = 0;

    tables = iec60664_tables();
    if isempty(tables)
        req.withstand_voltage = Vdiff * get_insulation_multiplier(insulation_class);
        return;
    end

    Vrms = abs(Vdiff);
    Vpeak = Vrms * sqrt(2);
    freq = data.f;
    altitude = 0;
    if isfield(data, 'altitude_m')
        altitude = max(0, data.altitude_m);
    end

    pd = 2;
    if isfield(data, 'pollution_degree')
        pd = data.pollution_degree;
    end
    pd_key = sprintf('P%d', max(1, min(3, round(pd))));

    ovc = 'OVC-II';
    if isfield(data, 'overvoltage_category')
        ovc = data.overvoltage_category;
    end
    ovc_key = strrep(upper(ovc), '-', '_');

    cti = 'Group II';
    if isfield(data, 'cti_group')
        cti = data.cti_group;
    end
    cti_key = strrep(cti, ' ', '_');

    wiring = 'Wound';
    if isfield(data, 'wiring_technology')
        wiring = data.wiring_technology;
    end
    wiring_key = wiring;

    is_reinforced = any(strcmpi(insulation_class, {'reinforced', 'double'}));

    rated_impulse = iec60664_get_rated_impulse_withstand_voltage(tables, ovc_key, Vrms, is_reinforced);
    req.withstand_voltage = iec60664_calculate_withstand_voltage(Vrms, Vpeak, rated_impulse, is_reinforced);

    clearance_transient = iec60664_get_clearance_f2(tables, pd_key, rated_impulse);
    steady_peak = Vpeak;
    if is_reinforced
        steady_peak = steady_peak * 1.6;
    end
    clearance_steady = iec60664_get_clearance_f8(tables, steady_peak);
    if freq > 30000
        clearance_steady = iec60664_get_clearance_over_30kHz(tables, steady_peak, freq, clearance_steady);
    end
    clearance = max(clearance_transient, clearance_steady);
    if altitude > 2000
        clearance = clearance * iec60664_get_altitude_factor(tables, altitude);
    end
    req.clearance = clearance;

    rated_insulation = iec60664_get_rated_insulation_voltage(tables, Vrms);
    voltage_rms = max(Vrms, rated_insulation);
    creepage = iec60664_get_creepage_f5(tables, wiring_key, pd_key, cti_key, voltage_rms);
    if freq > 30000
        creepage_over = iec60664_get_creepage_over_30kHz(tables, Vpeak, freq);
        switch pd_key
            case 'P2'
                creepage_over = creepage_over * 1.2;
            case 'P3'
                creepage_over = creepage_over * 1.4;
        end
        creepage = max(creepage, creepage_over);
    end
    if is_reinforced
        creepage = creepage * 2;
    end
    creepage = max(creepage, clearance);
    req.creepage = creepage;

    req.margin_distance = max(clearance, creepage);

    if freq > 30000
        req.distance_through_insulation = iec60664_distance_through_insulation_over_30kHz(Vrms);
    end
end

function tables = iec60664_tables()
    persistent cache
    if ~isempty(cache)
        tables = cache;
        return;
    end

    tables = struct();

    base_paths = {};
    try
        here = fileparts(mfilename('fullpath'));
        base_paths{end+1} = fullfile(here, 'insulation_standards'); %#ok<AGROW>
    catch
    end
    base_paths{end+1} = 'C:\Users\Will\Downloads\MKF-main\src\data\insulation_standards';

    path_60664_1 = '';
    path_60664_4 = '';
    for i = 1:numel(base_paths)
        p1 = fullfile(base_paths{i}, 'IEC_60664-1.json');
        p4 = fullfile(base_paths{i}, 'IEC_60664-4.json');
        if exist(p1, 'file')
            path_60664_1 = p1;
        end
        if exist(p4, 'file')
            path_60664_4 = p4;
        end
    end

    if isempty(path_60664_1)
        tables = [];
        return;
    end

    data1 = jsondecode(fileread(path_60664_1));
    tables.part1 = data1;

    if ~isempty(path_60664_4) && exist(path_60664_4, 'file')
        data4 = jsondecode(fileread(path_60664_4));
        tables.part4 = data4;
    else
        tables.part4 = struct();
    end

    cache = tables;
end

function rated = iec60664_get_rated_impulse_withstand_voltage(tables, ovc_key, rated_voltage, is_reinforced)
    ovc_field = pick_fieldname(tables.part1.F_1, ovc_key);
    if isempty(ovc_field)
        rated = rated_voltage;
        return;
    end
    table = ensure_table_array(tables.part1.F_1.(ovc_field));
    rated = lookup_step(table, rated_voltage);
    if is_reinforced
        idx = find(table(:,1) >= rated_voltage, 1);
        if ~isempty(idx) && idx < size(table, 1)
            rated = table(idx+1, 2);
        else
            rated = rated * 1.6;
        end
    end
end

function clearance = iec60664_get_clearance_f2(tables, pd_key, rated_impulse)
    pd_field = pick_fieldname(tables.part1.F_2.InhomogeneusField, pd_key);
    if isempty(pd_field)
        clearance = 0;
        return;
    end
    table = ensure_table_array(tables.part1.F_2.InhomogeneusField.(pd_field));
    clearance = lookup_step(table, rated_impulse);
end

function clearance = iec60664_get_clearance_f8(tables, rated_peak)
    table = ensure_table_array(tables.part1.F_8.InhomogeneusField);
    clearance = lookup_step(table, rated_peak);
end

function rated = iec60664_get_rated_insulation_voltage(tables, main_supply)
    table = ensure_table_array(tables.part1.F_3);
    rated = lookup_step(table, main_supply);
end

function creepage = iec60664_get_creepage_f5(tables, wiring_key, pd_key, cti_key, voltage_rms)
    wiring_field = pick_fieldname(tables.part1.F_5, wiring_key);
    if isempty(wiring_field)
        wiring_field = pick_fieldname(tables.part1.F_5, 'Wound');
    end
    if isempty(wiring_field)
        creepage = 0;
        return;
    end
    pd_field = pick_fieldname(tables.part1.F_5.(wiring_field), pd_key);
    if isempty(pd_field)
        creepage = 0;
        return;
    end
    cti_field = pick_fieldname(tables.part1.F_5.(wiring_field).(pd_field), cti_key);
    if isempty(cti_field)
        creepage = 0;
        return;
    end
    table = ensure_table_array(tables.part1.F_5.(wiring_field).(pd_field).(cti_field));
    creepage = lookup_step(table, voltage_rms);
end

function factor = iec60664_get_altitude_factor(tables, altitude)
    table = ensure_table_array(tables.part1.A_2);
    factor = linear_table_interpolation(table, altitude);
end

function clearance = iec60664_get_clearance_over_30kHz(tables, rated_peak, freq, current_clearance)
    if ~isfield(tables, 'part4') || ~isfield(tables.part4, 'Table_1')
        clearance = current_clearance;
        return;
    end
    skin = skin_depth_copper(freq);
    is_homogeneous = skin >= current_clearance * 0.2;
    if is_homogeneous
        freq_mhz = freq / 1e6;
        crit_mhz = 0.2 / current_clearance;
        min_mhz = 3;
        if freq_mhz < crit_mhz
            clearance = current_clearance;
        elseif freq_mhz > min_mhz
            clearance = current_clearance * 1.25;
        else
            factor = 1 + (freq_mhz - crit_mhz) / (min_mhz - crit_mhz) * 0.25;
            clearance = current_clearance * factor;
        end
    else
        table = ensure_table_array(tables.part4.Table_1);
        clearance = linear_table_interpolation(table, rated_peak);
    end
end

function creepage = iec60664_get_creepage_over_30kHz(tables, voltage_peak, freq)
    creepage = 0;
    if ~isfield(tables, 'part4') || ~isfield(tables.part4, 'Table_2')
        return;
    end
    table2 = tables.part4.Table_2;
    freq_fields = fieldnames(table2);
    freqs = zeros(numel(freq_fields), 1);
    for i = 1:numel(freq_fields)
        freqs(i) = str2double(freq_fields{i});
    end
    [freqs, idx] = sort(freqs);
    tables_sorted = cell(numel(freqs), 1);
    for i = 1:numel(freqs)
        tables_sorted{i} = ensure_table_array(table2.(freq_fields{idx(i)}));
    end

    prev_freq = 30000;
    prev_table = [];
    for i = 1:numel(freqs)
        f = freqs(i);
        if freq >= prev_freq && freq <= f
            top_val = linear_table_interpolation(tables_sorted{i}, voltage_peak);
            if isempty(prev_table)
                creepage = top_val;
            else
                bottom_val = linear_table_interpolation(prev_table, voltage_peak);
                prop = (freq - prev_freq) / (f - prev_freq);
                creepage = bottom_val + (top_val - bottom_val) * prop;
            end
            return;
        end
        prev_freq = f;
        prev_table = tables_sorted{i};
    end
end

function withstand = iec60664_calculate_withstand_voltage(Vrms, Vpeak, rated_impulse, is_reinforced)
    voltage_temp = Vrms + 1200;
    if is_reinforced
        voltage_temp = voltage_temp * 2;
    end
    F1 = 1.2;
    F3 = 1.25;
    F4 = 1.1;
    voltage_recurring = F1 * F4 * sqrt(2) * Vrms;
    if is_reinforced
        voltage_recurring = voltage_recurring * F3;
    end
    withstand = max([rated_impulse, voltage_temp, voltage_recurring, Vpeak]);
end

function dti = iec60664_distance_through_insulation_over_30kHz(working_voltage)
    dti = 0;
    max_iter = 5000;
    for i = 1:max_iter
        if electric_field_strength_is_valid(dti, working_voltage)
            return;
        end
        dti = dti + 1e-6;
    end
end

function ok = electric_field_strength_is_valid(dti, voltage)
    if dti == 0
        ok = false;
    elseif dti < 30e-6
        ok = (voltage / dti) < 10e6;
    elseif dti > 0.00075
        ok = (voltage / dti) < 2e6;
    else
        ok = (voltage / dti) < (0.25 / (dti * 1000) + 1.667) * 1e6;
    end
end

function delta = skin_depth_copper(freq)
    mu0 = 4*pi*1e-7;
    sigma = 5.8e7;
    omega = 2*pi*freq;
    delta = sqrt(2 / (omega * mu0 * sigma));
end

function table = ensure_table_array(table)
    if iscell(table)
        table = cell2mat(table);
    end
end

function y = lookup_step(table, x)
    if isempty(table)
        y = 0;
        return;
    end
    for i = 1:size(table, 1)
        if x <= table(i, 1)
            y = table(i, 2);
            return;
        end
    end
    y = table(end, 2);
end

function y = linear_table_interpolation(table, x)
    if isempty(table)
        y = 0;
        return;
    end
    if x <= table(1, 1)
        if size(table, 1) > 1
            slope = (table(2, 2) - table(1, 2)) / (table(2, 1) - table(1, 1));
            y = table(1, 2) + (x - table(1, 1)) * slope;
        else
            y = table(1, 2);
        end
        return;
    end
    if x >= table(end, 1)
        if size(table, 1) > 1
            slope = (table(end, 2) - table(end-1, 2)) / (table(end, 1) - table(end-1, 1));
            y = table(end, 2) + (x - table(end, 1)) * slope;
        else
            y = table(end, 2);
        end
        return;
    end
    for i = 1:size(table, 1) - 1
        if table(i, 1) <= x && x <= table(i+1, 1)
            proportion = (x - table(i, 1)) / (table(i+1, 1) - table(i, 1));
            y = table(i, 2) + proportion * (table(i+1, 2) - table(i, 2));
            return;
        end
    end
    y = table(end, 2);
end

function name = pick_fieldname(s, desired)
    name = '';
    if isempty(s) || ~isstruct(s)
        return;
    end
    fields = fieldnames(s);
    if isempty(fields)
        return;
    end
    desired_norm = normalize_key(desired);
    for i = 1:numel(fields)
        if strcmp(normalize_key(fields{i}), desired_norm)
            name = fields{i};
            return;
        end
    end
end

function norm = normalize_key(s)
    if ~ischar(s)
        if local_isstring(s)
            s = char(s);
        else
            norm = '';
            return;
        end
    end
    s = lower(s);
    norm = regexprep(s, '[^a-z0-9]', '');
end

function tf = local_contains(str, pattern)
    if ~ischar(str)
        if local_isstring(str)
            str = char(str);
        else
            tf = false;
            return;
        end
    end
    if ~ischar(pattern)
        if local_isstring(pattern)
            pattern = char(pattern);
        else
            tf = false;
            return;
        end
    end
    tf = ~isempty(strfind(lower(str), lower(pattern)));
end

function tf = local_isstring(val)
    tf = false;
    try
        tf = isa(val, 'string');
    catch
        tf = false;
    end
end

function order = parse_section_order(data)
    order = [];
    s = '';
    if isfield(data, 'section_order')
        s = data.section_order;
    end
    if local_isstring(s)
        s = char(s);
    end
    if ~ischar(s)
        s = '';
    end

    if data.n_windings <= 9 && ~isempty(regexp(s, '^[0-9]+$', 'once'))
        tokens = regexp(s, '\d', 'match');
    else
        tokens = regexp(s, '\d+', 'match');
    end
    for i = 1:length(tokens)
        v = str2double(tokens{i});
        if ~isnan(v) && v >= 1 && v <= data.n_windings
            order(end+1) = v; %#ok<AGROW>
        end
    end

    if isempty(order)
        order = 1:data.n_windings;
    end

    % Ensure all windings appear at least once
    for w = 1:data.n_windings
        if ~any(order == w)
            order(end+1) = w; %#ok<AGROW>
        end
    end
end

function [section_turns, section_windings] = build_section_plan(data, order)
    n_w = data.n_windings;
    counts = zeros(1, n_w);
    for i = 1:length(order)
        counts(order(i)) = counts(order(i)) + 1;
    end

    allocations = cell(1, n_w);
    indices = ones(1, n_w);

    for w = 1:n_w
        n_turns = data.windings(w).n_turns;
        c = counts(w);
        if c <= 0
            c = 1;
        end
        base = floor(n_turns / c);
        rem = mod(n_turns, c);
        arr = base * ones(1, c);
        if rem > 0
            arr(1:rem) = arr(1:rem) + 1;
        end
        allocations{w} = arr;
    end

    section_windings = order;
    section_turns = zeros(1, length(order));
    for i = 1:length(order)
        w = order(i);
        idx = indices(w);
        if idx <= length(allocations{w})
            section_turns(i) = allocations{w}(idx);
        else
            section_turns(i) = 0;
        end
        indices(w) = idx + 1;
    end
end

function v = get_tape_layer_breakdown_v(data)
    v = 0;
    if ~isfield(data, 'tape_kv_per_mm') || ~isfield(data, 'tape_thickness')
        return;
    end
    if data.tape_kv_per_mm <= 0 || data.tape_thickness <= 0
        return;
    end
    thickness_mm = data.tape_thickness * 1e3;
    v = data.tape_kv_per_mm * thickness_mm * 1e3;
end

function used = is_tiw_used(data, winding_a, winding_b)
    used = false;
    if winding_a >= 1 && winding_a <= data.n_windings
        if isfield(data.windings(winding_a), 'wire_insulation') && ...
                strcmpi(data.windings(winding_a).wire_insulation, 'tiw')
            used = true;
        end
    end
    if winding_b >= 1 && winding_b <= data.n_windings
        if isfield(data.windings(winding_b), 'wire_insulation') && ...
                strcmpi(data.windings(winding_b).wire_insulation, 'tiw')
            used = true;
        end
    end
end

function options = build_wire_option_lists(wires)
    wire_names = fieldnames(wires);
    standards = {};
    diameters = {};
    coatings = {};

    for i = 1:length(wire_names)
        winfo = wires.(wire_names{i});
        if isfield(winfo, 'standard')
            standards{end+1} = winfo.standard; %#ok<AGROW>
        end
        if isfield(winfo, 'cond_diameter')
            diameters{end+1} = winfo.cond_diameter; %#ok<AGROW>
        end
        if isfield(winfo, 'coating')
            coatings{end+1} = winfo.coating; %#ok<AGROW>
        end
    end

    standards = normalize_option_list(standards);
    diameters = normalize_option_list(diameters);
    coatings = normalize_option_list(coatings);

    options.standards = standards;
    options.cond_diameters = diameters;
    options.coatings = coatings;
end

function list = normalize_option_list(list)
    if isempty(list)
        list = {'-'};
        return;
    end
    out = {};
    for i = 1:length(list)
        v = list{i};
        if iscell(v)
            for j = 1:length(v)
                s = normalize_option_value(v{j});
                if ~isempty(s)
                    out{end+1} = s; %#ok<AGROW>
                end
            end
        else
            s = normalize_option_value(v);
            if ~isempty(s)
                out{end+1} = s; %#ok<AGROW>
            end
        end
    end
    if isempty(out)
        list = {'-'};
    else
        list = unique(out, 'stable');
    end
end

function s = normalize_option_value(v)
    if isempty(v)
        s = '';
    elseif ischar(v)
        s = strtrim(v);
    elseif isstring(v)
        s = strtrim(char(v));
    elseif isnumeric(v)
        s = strtrim(num2str(v));
    else
        s = '';
    end
end

function set_popup_value(handle, value)
    if isempty(handle) || ~ishandle(handle)
        return;
    end
    list = get(handle, 'String');
    if ischar(list)
        list = cellstr(list);
    end
    idx = find(strcmp(list, value), 1);
    if isempty(idx)
        idx = 1;
    end
    set(handle, 'Value', idx);
end

function gap = get_inter_winding_gap(data, winding_a, winding_b)
    gap = data.gap_winding;
    if winding_a < 1 || winding_b > data.n_windings
        return;
    end
    % Physical inter-winding gap is set by tape stack only
    if isfield(data, 'tape_thickness') && isfield(data, 'tape_layers')
        gap = data.tape_thickness * max(0, data.tape_layers);
    end
end

function is_foil = is_foil_wire(data, wire_type)
    wire = data.api.get_wire_info(wire_type);
    if isfield(wire, 'conductor_shape')
        is_rect = strcmp(wire.conductor_shape, 'rectangular');
    else
        is_rect = false;
    end
    [vis_w, vis_h] = data.api.get_wire_visual_dims(wire_type);
    bobbin_height = 0;
    if isfield(data, 'selected_core') && isfield(data.cores, data.selected_core)
        core = data.cores.(data.selected_core);
        bobbin = data.layout_calc.get_bobbin_dimensions(core);
        bobbin_height = bobbin.height;
    end
    is_foil = is_rect && (vis_w > 5 * vis_h) && (bobbin_height <= 0 || vis_w > bobbin_height * 0.3);
end

function layout = calculate_layout(data, wire_type, n_turns, pattern, n_filar)
    if nargin < 5 || isempty(n_filar)
        n_filar = 1;
    end

    edge_margin = 0;
    if isfield(data, 'edge_margin')
        edge_margin = data.edge_margin;
    end

    try
        layout = data.layout_calc.calculate_winding_layout(...
            data.selected_core, wire_type, n_turns, pattern, n_filar, edge_margin);
        return;
    catch err
        if local_contains(err.message, 'too many inputs') || local_contains(err.message, 'Too many input')
            % Legacy classdef without n_filar/edge_margin support
            n_turns_eff = n_turns * max(1, n_filar);
            layout = data.layout_calc.calculate_winding_layout(...
                data.selected_core, wire_type, n_turns_eff, pattern);
            layout.legacy_no_filar = true;
            layout.edge_margin = edge_margin;
            return;
        end
        rethrow(err);
    end
end

% ===============================================================
% CALLBACK: SUPPLIER CASCADE (Issue #4)
% ===============================================================

function select_supplier(src, ~)
    fig = gcbf;
    data = guidata(fig);

    sup_list = get(src, 'String');
    idx = get(src, 'Value');
    data.selected_supplier = sup_list{idx};

    % Update core shapes dropdown for this supplier
    new_cores = data.api.get_cores_by_supplier(data.selected_supplier);
    if isempty(new_cores)
        new_cores = fieldnames(data.cores);
    end

    core_dd = findobj(fig, 'Tag', 'core_dropdown');
    set(core_dd, 'String', new_cores, 'Value', 1);

    if ~isempty(new_cores)
        data.selected_core = new_cores{1};
    end

    % Update materials dropdown for this supplier
    new_mats = data.api.get_materials_by_supplier(data.selected_supplier);
    if isempty(new_mats)
        new_mats = fieldnames(data.materials);
    end

    mat_dd = findobj(fig, 'Tag', 'material_dropdown');
    set(mat_dd, 'String', new_mats, 'Value', 1);

    if ~isempty(new_mats)
        data.selected_material = new_mats{1};
    end

    % Update info displays
    set(findobj(fig, 'Tag', 'core_info'), 'String', get_core_info_text(data));
    set(findobj(fig, 'Tag', 'material_info'), 'String', get_material_info_text(data));

    guidata(fig, data);
    update_visualization(data);
end

function select_core(src, ~)
    fig = gcbf;
    data = guidata(fig);

    core_list = get(src, 'String');
    idx = get(src, 'Value');
    data.selected_core = core_list{idx};

    set(findobj(fig, 'Tag', 'core_info'), 'String', get_core_info_text(data));
    guidata(fig, data);
    update_visualization(data);
end

function select_material(src, ~)
    fig = gcbf;
    data = guidata(fig);

    mat_list = get(src, 'String');
    idx = get(src, 'Value');
    data.selected_material = mat_list{idx};

    set(findobj(fig, 'Tag', 'material_info'), 'String', get_material_info_text(data));
    guidata(fig, data);
end

function update_frequency(src, ~)
    fig = gcbf;
    data = guidata(fig);
    data.f = str2double(get(src, 'String')) * 1e3;
    guidata(fig, data);
end

function update_gap_type(src, ~)
    fig = gcbf;
    data = guidata(fig);
    gap_types = get(src, 'String');
    idx = get(src, 'Value');
    data.core_gap_type = gap_types{idx};

    % Enable/disable length and num_gaps based on type
    gap_len_ctrl = findobj(fig, 'Tag', 'gap_length');
    gap_num_ctrl = findobj(fig, 'Tag', 'gap_num');

    switch data.core_gap_type
        case 'Ungapped'
            data.core_gap_length = 0;
            data.core_num_gaps = 1;
            set(gap_len_ctrl, 'String', '0', 'Enable', 'off');
            set(gap_num_ctrl, 'String', '1', 'Enable', 'off');
        case {'Ground', 'Spacer'}
            set(gap_len_ctrl, 'Enable', 'on');
            set(gap_num_ctrl, 'String', '1', 'Enable', 'off');
            data.core_num_gaps = 1;
            if data.core_gap_length == 0
                data.core_gap_length = 1e-3;
                set(gap_len_ctrl, 'String', '1');
            end
        case 'Distributed'
            set(gap_len_ctrl, 'Enable', 'on');
            set(gap_num_ctrl, 'Enable', 'on');
            if data.core_gap_length == 0
                data.core_gap_length = 1e-3;
                set(gap_len_ctrl, 'String', '1');
            end
            if data.core_num_gaps < 2
                data.core_num_gaps = 3;
                set(gap_num_ctrl, 'String', '3');
            end
        otherwise
            data.core_gap_type = 'Ungapped';
            data.core_gap_length = 0;
            data.core_num_gaps = 1;
            set(gap_len_ctrl, 'String', '0', 'Enable', 'off');
            set(gap_num_ctrl, 'String', '1', 'Enable', 'off');
    end

    guidata(fig, data);
    update_visualization(data);
end

function update_gap_length(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val >= 0
        data.core_gap_length = val * 1e-3;  % Convert mm to meters
    end
    guidata(fig, data);
    update_visualization(data);
end

function update_num_gaps(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = round(str2double(get(src, 'String')));
    if ~isnan(val) && val >= 1
        data.core_num_gaps = val;
        set(src, 'String', num2str(val));
    end
    guidata(fig, data);
    update_visualization(data);
end

function select_wire(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);

    wire_list = get(src, 'String');
    idx = get(src, 'Value');
    wire_type = wire_list{idx};

    data.windings(winding).wire_type = wire_type;

    % Update wire dimensions and shape
    [w, h, shape] = data.api.wire_to_conductor_dims(wire_type);
    data.width = w;
    data.height = h;
    data.windings(winding).wire_shape = shape;

    % Update wire info fields (Issue #3)
    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);

    guidata(fig, data);
    update_visualization(data);
end

function select_wire_attribute(src, ~, winding, field)
    fig = gcbf;
    data = guidata(fig);

    list = get(src, 'String');
    if ischar(list)
        list = cellstr(list);
    end
    idx = get(src, 'Value');
    if isempty(idx) || idx < 1 || idx > numel(list)
        return;
    end
    selected_value = list{idx};

    % Find wires matching this attribute
    wire_names = fieldnames(data.wires);
    matches = {};
    for i = 1:length(wire_names)
        wname = wire_names{i};
        winfo = data.wires.(wname);
        if isfield(winfo, field) && strcmp(winfo.(field), selected_value)
            matches{end+1} = wname; %#ok<AGROW>
        end
    end

    if isempty(matches)
        update_wire_info_fields(fig, data, winding);
        return;
    end

    current = data.windings(winding).wire_type;
    if ~any(strcmp(matches, current))
        data.windings(winding).wire_type = matches{1};
        [w_dim, h_dim, shape] = data.api.wire_to_conductor_dims(data.windings(winding).wire_type);
        data.width = w_dim;
        data.height = h_dim;
        data.windings(winding).wire_shape = shape;
    end

    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);
    guidata(fig, data);
    update_visualization(data);
end

function switch_tab(~, ~, tab_num)
    fig = gcbf;
    data = guidata(fig);
    for w = 1:data.n_windings
        set(findobj(fig, 'Tag', sprintf('content%d', w)), 'Visible', 'off');
    end
    set(findobj(fig, 'Tag', sprintf('content%d', tab_num)), 'Visible', 'on');
end

function adjust_turns(~, ~, winding, delta)
    fig = gcbf;
    data = guidata(fig);
    new_val = max(1, data.windings(winding).n_turns + delta);
    data.windings(winding).n_turns = new_val;
    set(findobj(fig, 'Tag', sprintf('turns_val_%d', winding)), 'String', num2str(new_val));
    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);
    guidata(fig, data);
    update_visualization(data);
end

function adjust_filar(~, ~, winding, delta)
    fig = gcbf;
    data = guidata(fig);
    new_val = max(1, min(4, data.windings(winding).n_filar + delta));
    data.windings(winding).n_filar = new_val;
    set(findobj(fig, 'Tag', sprintf('filar_val_%d', winding)), 'String', num2str(new_val));
    set(findobj(fig, 'Tag', sprintf('filar_name_%d', winding)), 'String', get_filar_name(new_val));
    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);
    guidata(fig, data);
    update_visualization(data);
end

function update_turns_manual(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);
    new_val = max(1, round(str2double(get(src, 'String'))));
    data.windings(winding).n_turns = new_val;
    set(src, 'String', num2str(new_val));
    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);
    guidata(fig, data);
    update_visualization(data);
end

function update_filar_manual(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);
    new_val = max(1, min(4, round(str2double(get(src, 'String')))));
    data.windings(winding).n_filar = new_val;
    set(src, 'String', num2str(new_val));
    set(findobj(fig, 'Tag', sprintf('filar_name_%d', winding)), 'String', get_filar_name(new_val));
    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);
    guidata(fig, data);
    update_visualization(data);
end

function update_current(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);
    data.windings(winding).current = str2double(get(src, 'String'));
    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);
    guidata(fig, data);
end

function update_voltage(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);
    data.windings(winding).voltage = str2double(get(src, 'String'));
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_phase(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);
    data.windings(winding).phase = str2double(get(src, 'String'));
    guidata(fig, data);
end

function update_insulation_class(src, ~)
    fig = gcbf;
    data = guidata(fig);
    list = get(src, 'String');
    idx = get(src, 'Value');
    if ischar(list)
        list = cellstr(list);
    end
    if idx >= 1 && idx <= numel(list)
        data.insulation_class = list{idx};
    end
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_tape_thickness(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val_mm = str2double(get(src, 'String'));
    if isnan(val_mm) || val_mm < 0
        val_mm = 0;
    end
    data.tape_thickness = val_mm * 1e-3;
    set(src, 'String', num2str(val_mm));
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_tape_layers(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = round(str2double(get(src, 'String')));
    if isnan(val) || val < 0
        val = 0;
    end
    data.tape_layers = val;
    set(src, 'String', num2str(val));
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_tape_strength(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if isnan(val) || val < 0
        val = 0;
    end
    data.tape_kv_per_mm = val;
    set(src, 'String', num2str(val));
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_tiw_kv(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if isnan(val) || val < 0
        val = 0;
    end
    data.tiw_kv = val;
    set(src, 'String', num2str(val));
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_edge_margin(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val_mm = str2double(get(src, 'String'));
    if isnan(val_mm) || val_mm < 0
        val_mm = 0;
    end
    data.edge_margin = val_mm * 1e-3;
    set(src, 'String', num2str(val_mm));
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_data_mode(src, ~)
    fig = gcbf;
    data = guidata(fig);
    prev_data = data;
    list = get(src, 'String');
    idx = get(src, 'Value');
    if ischar(list)
        list = cellstr(list);
    end
    mode_label = 'Offline';
    if idx >= 1 && idx <= numel(list)
        mode_label = list{idx};
    end

    url = get(findobj(fig, 'Tag', 'server_url'), 'String');

    if local_contains(mode_label, 'online')
        ok = data.api.set_mode('online', url);
    else
        ok = data.api.set_mode('offline', url);
    end

    data.data_mode = data.api.get_mode();
    data.online_url = url;
    data = reload_databases(fig, data, prev_data);
    guidata(fig, data);

    % Update status + title
    status_text = 'Status: Offline';
    if strcmpi(data.data_mode, 'online') && ok
        status_text = sprintf('Status: Online (%s)', url);
        set(fig, 'Name', 'Interactive Transformer Design Tool [Online Mode]');
        title_ctrl = findobj(fig, 'Tag', 'main_title');
        if ~isempty(title_ctrl)
            set(title_ctrl, 'String', 'Interactive Transformer Design Tool [Online Mode]');
        end
    else
        set(fig, 'Name', 'Interactive Transformer Design Tool [Offline Mode]');
        set(src, 'Value', 1);
        title_ctrl = findobj(fig, 'Tag', 'main_title');
        if ~isempty(title_ctrl)
            set(title_ctrl, 'String', 'Interactive Transformer Design Tool [Offline Mode]');
        end
    end
    set(findobj(fig, 'Tag', 'data_mode_status'), 'String', status_text);
end

function update_server_url(src, ~)
    fig = gcbf;
    data = guidata(fig);
    data.online_url = get(src, 'String');
    guidata(fig, data);

    % If already online, try reconnect
    mode_ctrl = findobj(fig, 'Tag', 'data_mode');
    if ~isempty(mode_ctrl) && get(mode_ctrl, 'Value') == 2
        update_data_mode(mode_ctrl, []);
    end
end

function data = reload_databases(fig, data, prev_data)
    if nargin < 3
        prev_data = data;
    end
    data.wires = data.api.get_wires();
    data.cores = data.api.get_cores();
    data.materials = data.api.get_materials();
    data.suppliers = data.api.get_suppliers();
    data.wire_options = build_wire_option_lists(data.wires);

    supplier_list = data.suppliers;
    if isempty(supplier_list)
        supplier_list = {'TDK'};
    end
    sel_supplier = supplier_list{1};
    if isfield(prev_data, 'selected_supplier') && any(strcmp(supplier_list, prev_data.selected_supplier))
        sel_supplier = prev_data.selected_supplier;
    end
    data.selected_supplier = sel_supplier;
    set(findobj(fig, 'Tag', 'supplier_dropdown'), 'String', supplier_list, ...
        'Value', find(strcmp(supplier_list, sel_supplier), 1));

    core_list = data.api.get_cores_by_supplier(data.selected_supplier);
    if isempty(core_list)
        core_list = fieldnames(data.cores);
    end
    if isempty(core_list)
        core_list = {'None'};
    end
    sel_core = core_list{1};
    if isfield(prev_data, 'selected_core') && any(strcmp(core_list, prev_data.selected_core))
        sel_core = prev_data.selected_core;
    end
    data.selected_core = sel_core;
    set(findobj(fig, 'Tag', 'core_dropdown'), 'String', core_list, ...
        'Value', find(strcmp(core_list, sel_core), 1));

    mat_list = data.api.get_materials_by_supplier(data.selected_supplier);
    if isempty(mat_list)
        mat_list = fieldnames(data.materials);
    end
    if isempty(mat_list)
        mat_list = {'N87'};
    end
    sel_mat = mat_list{1};
    if isfield(prev_data, 'selected_material') && any(strcmp(mat_list, prev_data.selected_material))
        sel_mat = prev_data.selected_material;
    end
    data.selected_material = sel_mat;
    set(findobj(fig, 'Tag', 'material_dropdown'), 'String', mat_list, ...
        'Value', find(strcmp(mat_list, sel_mat), 1));

    wire_list = fieldnames(data.wires);
    if isempty(wire_list)
        wire_list = {'AWG_22'};
    end

    for w = 1:data.n_windings
        sel_wire = wire_list{1};
        if isfield(prev_data, 'windings') && numel(prev_data.windings) >= w
            prev_wire = prev_data.windings(w).wire_type;
            if any(strcmp(wire_list, prev_wire))
                sel_wire = prev_wire;
            end
        end
        data.windings(w).wire_type = sel_wire;
        set(findobj(fig, 'Tag', sprintf('wire_type_%d', w)), ...
            'String', wire_list, 'Value', find(strcmp(wire_list, sel_wire), 1));

        set(findobj(fig, 'Tag', sprintf('wire_std_%d', w)), ...
            'String', data.wire_options.standards, 'Value', 1);
        set(findobj(fig, 'Tag', sprintf('wire_diam_%d', w)), ...
            'String', data.wire_options.cond_diameters, 'Value', 1);
        set(findobj(fig, 'Tag', sprintf('wire_coat_%d', w)), ...
            'String', data.wire_options.coatings, 'Value', 1);

        update_wire_info_fields(fig, data, w);
    end

    set(findobj(fig, 'Tag', 'core_info'), 'String', get_core_info_text(data));
    set(findobj(fig, 'Tag', 'material_info'), 'String', get_material_info_text(data));

    update_all_summaries(fig, data);
    update_visualization(data);
end

function update_wire_insulation(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);
    list = get(src, 'String');
    idx = get(src, 'Value');
    if ischar(list)
        list = cellstr(list);
    end
    if idx >= 1 && idx <= numel(list)
        if strcmpi(list{idx}, 'TIW')
            data.windings(winding).wire_insulation = 'tiw';
        else
            data.windings(winding).wire_insulation = 'standard';
        end
    end
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_summary(fig, data, winding)
    set(findobj(fig, 'Tag', sprintf('summary_%d', winding)), ...
        'String', get_winding_summary(data, winding));
end

function update_all_summaries(fig, data)
    for w = 1:data.n_windings
        update_summary(fig, data, w);
    end
end

function change_vis_mode(~, ~)
    fig = gcbf;
    data = guidata(fig);
    update_visualization(data);
end

function change_packing(~, ~)
    fig = gcbf;
    data = guidata(fig);
    update_visualization(data);
end

function update_section_order(src, ~)
    fig = gcbf;
    data = guidata(fig);
    data.section_order = get(src, 'String');
    guidata(fig, data);
    update_visualization(data);
end

% ===============================================================
% VISUALIZATION
% ===============================================================

function update_visualization(data)
    fig = data.fig_gui;
    ax = findobj(fig, 'Tag', 'vis_axes');
    vis_mode = get(findobj(fig, 'Tag', 'vis_mode'), 'Value');

    cla(ax);

    switch vis_mode
        case 1
            visualize_schematic_2d(data, ax);
        case 2
            visualize_core_window(data, ax);
        case 3
            visualize_openmagnetics(data, ax);
        case 4
            text(ax, 0.5, 0.5, 'Run Analysis to see loss distribution', ...
                'HorizontalAlignment', 'center', 'FontSize', 10, ...
                'Units', 'normalized');
    end
end

function visualize_openmagnetics(data, ax)
% Render PyOpenMagnetics 2D cross-section (core + bobbin + turns)
% Calls Python script to generate SVG, then parses and renders it

    fig = data.fig_gui;
    info_ctrl = findobj(fig, 'Tag', 'vis_info');

    % Show generating status
    set(info_ctrl, 'String', 'Generating OpenMagnetics view...', ...
        'BackgroundColor', [0.95 0.95 0.8]);
    drawnow;

    try
        % Build the visualization config
        fprintf('[OM_VIZ] Building config...\n');
        config = build_om_viz_config(data);
        fprintf('[OM_VIZ] Config built: core=%s, material=%s, windings=%d\n', ...
            config.core_shape, config.material, length(config.windings));

        % Write config to temp JSON file
        % Use pwd for paths - avoids MSYS/Windows path mangling in Octave
        script_dir = pwd();
        config_file = fullfile(script_dir, 'om_viz_config.json');
        svg_file = fullfile(script_dir, 'om_visualization.svg');
        config.output_svg = strrep(svg_file, '\', '/');

        % Write JSON config
        fprintf('[OM_VIZ] Encoding JSON...\n');
        json_str = jsonencode(config);
        fprintf('[OM_VIZ] JSON length: %d chars\n', length(json_str));
        fid = fopen(config_file, 'w');
        if fid == -1
            error('Cannot write config file: %s', config_file);
        end
        fwrite(fid, json_str);
        fclose(fid);
        fprintf('[OM_VIZ] Config written to: %s\n', config_file);

        % Call Python script - use relative paths to avoid MSYS/Windows path mangling
        py_script_name = 'generate_om_visualization.py';
        config_file_name = 'om_viz_config.json';
        
        if ~exist(fullfile(script_dir, py_script_name), 'file')
             error('Python script "%s" not found in %s', py_script_name, script_dir);
        end

        % Check for local venv python (recommended setup)
        python_cmd = 'python';
        venv_python = fullfile(script_dir, '.venv', 'Scripts', 'python.exe');
        if exist(venv_python, 'file')
            python_cmd = ['"' venv_python '"'];
        end

        % Add stderr redirection (2>&1) to capture ModuleNotFoundError
        cmd = sprintf('%s "%s" "%s" 2>&1', python_cmd, py_script_name, config_file_name);
        fprintf('[OM_VIZ] Running: %s\n', cmd);
        
        % Debug: check which python is being used if not venv
        if strcmp(python_cmd, 'python')
            [~, py_path] = system('where python');
            if ~isempty(py_path)
                fprintf('[OM_VIZ] Resolved python:\n%s\n', strtrim(py_path));
            end
        end

        [status, output] = system(cmd);
        
        % Check for module errors (ImportError, ModuleNotFoundError, or "No module named")
        is_module_error = ~isempty(strfind(output, 'ModuleNotFoundError')) || ...
                          ~isempty(strfind(output, 'ImportError')) || ...
                          ~isempty(strfind(output, 'No module named'));

        % Fallback: If python failed with ModuleNotFoundError, try 'py' launcher (Windows)
        if status ~= 0 && is_module_error && ispc
            fprintf('[OM_VIZ] Standard python failed. Trying Windows Python Launcher (py)...\n');
            cmd_fallback = sprintf('py "%s" "%s" 2>&1', py_script_name, config_file_name);
            [status_fb, output_fb] = system(cmd_fallback);
            if status_fb == 0 && ~isempty(strfind(output_fb, 'OK'))
                status = status_fb;
                output = output_fb;
                fprintf('[OM_VIZ] Success using ''py'' launcher.\n');
            end
        end

        % Fallback 2: Try specific python paths from 'where python' if they look like system installs
        if status ~= 0 && is_module_error && ispc
             [~, py_paths_str] = system('where python');
             % Split by newlines
             py_paths = strsplit(strtrim(py_paths_str), char(10));
             for i = 1:length(py_paths)
                 p = strtrim(py_paths{i});
                 if isempty(p); continue; end
                 % Skip Octave bundled python or the one we just tried (if it was 'python')
                 if ~isempty(strfind(lower(p), 'octave')) || ~isempty(strfind(lower(p), 'usr\bin'))
                     continue;
                 end
                 
                 fprintf('[OM_VIZ] Trying alternative python: %s\n', p);
                 cmd_alt = sprintf('"%s" "%s" "%s" 2>&1', p, py_script_name, config_file_name);
                 [status_alt, output_alt] = system(cmd_alt);
                 if status_alt == 0 && ~isempty(strfind(output_alt, 'OK'))
                     status = status_alt;
                     output = output_alt;
                     fprintf('[OM_VIZ] Success using alternative python.\n');
                     break;
                 else
                     fprintf('[OM_VIZ] Alternative python failed (exit=%d): %s\n', status_alt, strtrim(output_alt));
                 end
             end
        end

        fprintf('[OM_VIZ] Python exit code: %d\n', status);
        fprintf('[OM_VIZ] Python output: "%s"\n', strtrim(output));

        if status ~= 0 || isempty(strfind(strtrim(output), 'OK'))
            if is_module_error
                fprintf('[OM_VIZ] Hint: PyOpenMagnetics module missing in the python environment used.\n');
                fprintf('[OM_VIZ] If you installed it globally, try running Octave from a terminal where ''python'' works.\n');
                fprintf('[OM_VIZ] Or create a .venv in this folder: %s\n', script_dir);
            end
            error('Python script failed (exit=%d): %s', status, strtrim(output));
        end

        % Read SVG file
        fprintf('[OM_VIZ] Reading SVG: %s\n', svg_file);
        fid = fopen(svg_file, 'r');
        if fid == -1
            error('Cannot read SVG file: %s', svg_file);
        end
        svg_str = fread(fid, '*char')';
        fclose(fid);
        fprintf('[OM_VIZ] SVG loaded: %d chars\n', length(svg_str));

        % Parse and render SVG
        parse_om_svg(svg_str, ax);

        % Update status
        core_name = config.core_shape;
        gap_str = '';
        if isfield(data, 'core_gap_type') && ~strcmp(data.core_gap_type, 'Ungapped')
            gap_str = sprintf(' | Gap: %s %.2fmm', data.core_gap_type, data.core_gap_length*1e3);
        end
        set(info_ctrl, 'String', ...
            sprintf('OpenMagnetics: %s%s', core_name, gap_str), ...
            'BackgroundColor', [0.85 0.95 0.85]);

    catch ME
        % Fallback: show error and use basic visualization
        fprintf('[OM_VIZ] ERROR: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf('[OM_VIZ]   at %s line %d\n', ME.stack(1).name, ME.stack(1).line);
        end
        text(ax, 0.5, 0.5, ...
            sprintf('OpenMagnetics view unavailable:\n%s\n\nFalling back to Core Window Fit', ME.message), ...
            'HorizontalAlignment', 'center', 'FontSize', 9, ...
            'Units', 'normalized', 'Color', [0.6 0.1 0.1]);
        set(info_ctrl, 'String', ...
            sprintf('OM View failed: %s', ME.message), ...
            'BackgroundColor', [1.0 0.85 0.85]);
    end
end


function config = build_om_viz_config(data)
% Build JSON config struct for generate_om_visualization.py

    % Get original core shape name (with spaces/slashes)
    core_name = data.selected_core;
    if isfield(data.cores, core_name) && isfield(data.cores.(core_name), 'name')
        core_name = data.cores.(core_name).name;
    end

    % Get original material name
    mat_name = data.selected_material;
    if isfield(data.materials, mat_name) && isfield(data.materials.(mat_name), 'name')
        mat_name = data.materials.(mat_name).name;
    end

    % Build gapping array
    gapping = {};
    if isfield(data, 'core_gap_type')
        gapping_cells = data.api.build_gapping_array( ...
            data.core_gap_type, data.core_gap_length, data.core_num_gaps);
        % Convert cell array of structs to cell array for JSON
        for i = 1:length(gapping_cells)
            gapping{i} = gapping_cells{i};
        end
    end
    if isempty(gapping)
        gapping = {struct('type', 'residual', 'length', 10e-6)};
    end

    % Build winding descriptions
    windings = {};
    for w = 1:data.n_windings
        winding = data.windings(w);

        % Get original wire name
        wire_key = winding.wire_type;
        wire_name = wire_key;
        if isfield(data.wires, wire_key) && isfield(data.wires.(wire_key), 'name')
            wire_name = data.wires.(wire_key).name;
        end

        if w == 1
            iso_side = 'primary';
        else
            iso_side = 'secondary';
        end

        wire_std = '';
        wire_shape = 'round';
        cond_w = 0;
        cond_h = 0;
        try
            wire_info = data.api.get_wire_info(wire_key);
            if isfield(wire_info, 'standard')
                wire_std = wire_info.standard;
            end
        catch
        end
        try
            [cond_w, cond_h, wire_shape] = data.api.wire_to_conductor_dims(wire_key);
        catch
        end

        windings{w} = struct( ...
            'name', winding.name, ...
            'wire_name', wire_name, ...
            'wire_standard', wire_std, ...
            'wire_shape', wire_shape, ...
            'wire_cond_w', cond_w, ...
            'wire_cond_h', cond_h, ...
            'num_turns', winding.n_turns, ...
            'num_parallels', winding.n_filar, ...
            'isolation_side', iso_side ...
        );
    end

    config = struct();
    config.core_shape = core_name;
    config.material = mat_name;
    config.gapping = gapping;
    config.windings = windings;
    config.section_order = data.section_order;
    if isfield(data, 'core_gap_type'); config.core_gap_type = data.core_gap_type; end
    if isfield(data, 'core_gap_length'); config.core_gap_length = data.core_gap_length; end
    if isfield(data, 'core_num_gaps'); config.core_num_gaps = data.core_num_gaps; end
    try
        pack_idx = get(findobj(data.fig_gui, 'Tag', 'packing_pattern'), 'Value');
        pack_vals = {'Layered', 'Orthocyclic', 'Random'};
        if pack_idx >= 1 && pack_idx <= numel(pack_vals)
            config.packing_pattern = pack_vals{pack_idx};
        end
    catch
    end
    if isfield(data, 'tape_thickness'); config.tape_thickness = data.tape_thickness; end
    if isfield(data, 'tape_layers'); config.tape_layers = data.tape_layers; end
    config.plot_type = 'magnetic';
end


function visualize_schematic_2d(data, ax)
    hold(ax, 'on');
    axis(ax, 'equal');
    grid(ax, 'on');

    x_offset = 0;
    max_y_all = 0;

    for w = 1:data.n_windings
        n_turns = data.windings(w).n_turns;
        n_filar = data.windings(w).n_filar;
        wire_type = data.windings(w).wire_type;

        [w_dim, h_dim, shape] = data.api.wire_to_conductor_dims(wire_type);
        [vis_w, vis_h] = data.api.get_wire_visual_dims(wire_type);
        if is_foil_wire(data, wire_type)
            tmp = w_dim; w_dim = h_dim; h_dim = tmp;
            tmp = vis_w; vis_w = vis_h; vis_h = tmp;
        end

        x_pos = x_offset;
        y_offset = 0;

        for turn = 1:n_turns
            for strand = 1:n_filar
                y_pos = y_offset + (strand - 1) * (h_dim + data.gap_filar);

                if strcmp(shape, 'round')
                    r = vis_w / 2;
                    theta = linspace(0, 2*pi, 50);
                    fill(ax, x_pos + r*cos(theta), y_pos + vis_h/2 + r*sin(theta), ...
                        data.winding_colors{w}, 'EdgeColor', 'k', 'LineWidth', 0.5);
                else
                    rectangle('Parent', ax, ...
                        'Position', [x_pos - vis_w/2, y_pos, vis_w, vis_h], ...
                        'FaceColor', data.winding_colors{w}, ...
                        'EdgeColor', 'k', 'LineWidth', 0.5);
                end
            end

            turn_height = n_filar * h_dim + (n_filar - 1) * data.gap_filar + data.gap_layer;
            y_offset = y_offset + turn_height;
        end

        max_y_all = max(max_y_all, y_offset);

        text(x_pos, y_offset + 0.5e-3, data.windings(w).name, 'Parent', ax, ...
            'HorizontalAlignment', 'center', 'FontWeight', 'bold', ...
            'FontSize', 10, 'Color', data.winding_colors{w});

        if w < data.n_windings
            gap_winding = get_inter_winding_gap(data, w, w+1);
            x_offset = x_offset + max(vis_w, w_dim)/2 + gap_winding + max(vis_w, w_dim)/2;
        end
    end

    ylim(ax, [-2e-3, max_y_all * 1.3]);
    xlabel(ax, 'X Position (m)');
    ylabel(ax, 'Y Position (m)');
    title(ax, 'Winding Schematic');
    hold(ax, 'off');

    set(findobj(data.fig_gui, 'Tag', 'vis_info'), 'String', ...
        'Schematic view showing winding arrangement');
end

function visualize_core_window(data, ax)
    % ISSUE #2 FIX: Draw correct shapes for foil/rect wire

    if strcmp(data.selected_core, 'None')
        text(ax, 0.5, 0.5, 'No core selected', ...
            'HorizontalAlignment', 'center', 'FontSize', 12, ...
            'Units', 'normalized');
        return;
    end

    packing_idx = get(findobj(data.fig_gui, 'Tag', 'packing_pattern'), 'Value');
    patterns = {'layered', 'orthocyclic', 'random'};
    pattern = patterns{packing_idx};

    hold(ax, 'on');
    axis(ax, 'equal');

    core = data.cores.(data.selected_core);
    bobbin = data.layout_calc.get_bobbin_dimensions(core);

    edge_margin = 0;
    if isfield(data, 'edge_margin')
        edge_margin = data.edge_margin;
    end

    % Draw bobbin window
    rectangle('Parent', ax, 'Position', [0, 0, bobbin.width, bobbin.height], ...
        'EdgeColor', 'k', 'LineWidth', 2, 'LineStyle', '--');
    if edge_margin > 0
        rectangle('Parent', ax, ...
            'Position', [edge_margin, edge_margin, ...
                         max(1e-6, bobbin.width - 2*edge_margin), ...
                         max(1e-6, bobbin.height - 2*edge_margin)], ...
            'EdgeColor', [0.5 0.5 0.5], 'LineStyle', ':', 'LineWidth', 1);
    end
    text(bobbin.width/2, bobbin.height + 0.001, 'Bobbin Window', ...
        'Parent', ax, 'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');

    x_start = 0;
    total_fits = true;
    x_origin = edge_margin;
    available_width = bobbin.width - 2*edge_margin;

    section_order = parse_section_order(data);
    [section_turns, section_windings] = build_section_plan(data, section_order);

    for s = 1:length(section_windings)
        w = section_windings(s);
        n_turns = section_turns(s);
        if n_turns <= 0
            continue;
        end

        wire_type = data.windings(w).wire_type;
        n_filar = data.windings(w).n_filar;

        layout = calculate_layout(data, wire_type, n_turns, pattern, n_filar);

        if ~layout.fits
            total_fits = false;
        end
        if (x_start + layout.required_width) > max(1e-9, available_width)
            total_fits = false;
        end

        % Determine wire shape for drawing
        is_rect = isfield(layout, 'wire_shape') && strcmp(layout.wire_shape, 'rectangular');

        % Draw turns with correct shapes
        for i = 1:size(layout.turn_positions, 1)
            x = x_origin + x_start + layout.turn_positions(i, 1);
            y = edge_margin + layout.turn_positions(i, 2);

            if is_rect
                % ISSUE #2 FIX: Draw rectangles for foil/rect
                if isfield(layout, 'draw_w')
                    vw = layout.draw_w;
                    vh = layout.draw_h;
                else
                    vw = layout.wire_vis_w;
                    vh = layout.wire_vis_h;
                end
                rectangle('Parent', ax, ...
                    'Position', [x - vw/2, y - vh/2, vw, vh], ...
                    'FaceColor', data.winding_colors{w}, ...
                    'EdgeColor', 'k', 'LineWidth', 0.3);
            else
                % Draw circles for round/litz wire
                r = layout.wire_od / 2;
                theta = linspace(0, 2*pi, 30);
                fill(ax, x + r*cos(theta), y + r*sin(theta), ...
                    data.winding_colors{w}, 'EdgeColor', 'k', 'LineWidth', 0.3);
            end
        end

        % Label winding section
        text(x_origin + x_start + layout.required_width/2, -0.0005, data.windings(w).name, ...
            'Parent', ax, 'HorizontalAlignment', 'center', 'FontSize', 8, ...
            'Color', data.winding_colors{w}, 'FontWeight', 'bold');

        gap_winding = 0;
        if s < length(section_windings)
            if section_windings(s+1) ~= w
                gap_winding = get_inter_winding_gap(data, w, section_windings(s+1));
            end
        end

        if gap_winding > 0
            tape_y = edge_margin;
            tape_h = max(1e-6, bobbin.height - 2*edge_margin);
            rect = rectangle('Parent', ax, ...
                'Position', [x_origin + x_start + layout.required_width, tape_y, ...
                             gap_winding, tape_h], ...
                'FaceColor', [0.95 0.85 0.4], 'EdgeColor', 'none');
            if isprop(rect, 'FaceAlpha')
                set(rect, 'FaceAlpha', 0.35);
            end
        end

        x_start = x_start + layout.required_width + gap_winding;
    end

    xlim(ax, [-0.001, bobbin.width + 0.001]);
    ylim(ax, [-0.002, bobbin.height + 0.002]);
    xlabel(ax, 'Width (m)');
    ylabel(ax, 'Height (m)');
    title(ax, sprintf('%s packing in %s', pattern, data.selected_core));
    hold(ax, 'off');

    if total_fits
        info_str = sprintf('All windings FIT in core\nPattern: %s', pattern);
        color = [0.8 1.0 0.8];
    else
        info_str = sprintf('Windings DO NOT FIT\nTry smaller wire or fewer turns');
        color = [1.0 0.8 0.8];
    end

    set(findobj(data.fig_gui, 'Tag', 'vis_info'), 'String', info_str, 'BackgroundColor', color);
end

% ===============================================================
% RUN ANALYSIS (Issue #1 FIX: use layout positions)
% ===============================================================

function run_analysis(~, ~)
    fig = gcbf;
    data = guidata(fig);

    fprintf('\n=== RUNNING ANALYSIS ===\n');

    % Get packing pattern from GUI
    packing_idx = get(findobj(fig, 'Tag', 'packing_pattern'), 'Value');
    patterns = {'layered', 'orthocyclic', 'random'};
    pattern = patterns{packing_idx};

    % ISSUE #1 FIX: Build conductors from LAYOUT POSITIONS
    % This ensures analysis geometry matches visualization
    all_conductors = [];
    all_winding_map = [];
    all_wire_shapes = {};
    x_start = 0;
    edge_margin = 0;
    if isfield(data, 'edge_margin')
        edge_margin = data.edge_margin;
    end

    section_order = parse_section_order(data);
    [section_turns, section_windings] = build_section_plan(data, section_order);

    for s = 1:length(section_windings)
        w = section_windings(s);
        n_turns = section_turns(s);
        if n_turns <= 0
            continue;
        end

        wire_type = data.windings(w).wire_type;
        [w_dim, h_dim, shape] = data.api.wire_to_conductor_dims(wire_type);
        if is_foil_wire(data, wire_type)
            tmp = w_dim; w_dim = h_dim; h_dim = tmp;
        end

        n_filar = data.windings(w).n_filar;
        total_conds = n_turns * n_filar;

        fprintf('Building winding %d (%s): %s wire (%s), %d turns x %d filar\n', ...
            w, data.windings(w).name, wire_type, shape, n_turns, n_filar);

        % Use SAME layout calculator as visualization
        if ~strcmp(data.selected_core, 'None')
            layout = calculate_layout(data, wire_type, n_turns, pattern, n_filar);
        else
            % Fallback: simple vertical stack if no core selected
            layout = struct();
            positions = zeros(total_conds, 2);
            for t = 1:total_conds
                positions(t, :) = [0, (t-0.5) * max(w_dim, h_dim)];
            end
            layout.turn_positions = positions;
            layout.required_width = max(w_dim, h_dim);
        end

        % Current assignment
        I_per_strand = data.windings(w).current / n_filar;
        phase = data.windings(w).phase;

        % Build conductor array from layout positions
        for t = 1:total_conds
            x = edge_margin + x_start + layout.turn_positions(t, 1);
            y = edge_margin + layout.turn_positions(t, 2);

            all_conductors = [all_conductors; x, y, w_dim, h_dim, I_per_strand, phase];
            all_winding_map = [all_winding_map; w];
            all_wire_shapes{end+1} = shape;
        end

        fprintf('  %d conductors at layout positions (pattern: %s)\n', total_conds, pattern);

        gap_winding = 0;
        if s < length(section_windings)
            if section_windings(s+1) ~= w
                gap_winding = get_inter_winding_gap(data, w, section_windings(s+1));
            end
        end
        x_start = x_start + layout.required_width + gap_winding;
    end

    fprintf('\nBuilding PEEC geometry with wire shapes...\n');
    fprintf('  Total conductors: %d\n', size(all_conductors, 1));

    geom = peec_build_geometry(all_conductors, data.sigma, data.mu0, ...
        data.Nx, data.Ny, all_winding_map, all_wire_shapes);

    fprintf('  Wire shapes: %d conductors\n', length(geom.wire_shapes));
    for i = 1:min(3, length(geom.wire_shapes))
        fprintf('    Conductor %d: %s\n', i, geom.wire_shapes{i});
    end

    fprintf('Solving at %.0f kHz...\n', data.f/1e3);
    results = peec_solve_frequency(geom, all_conductors, data.f, data.sigma, data.mu0);

    display_results(data, geom, all_conductors, all_winding_map, results);
end

% ===============================================================
% DISPLAY RESULTS
% ===============================================================

function display_results(data, geom, conductors, winding_map, results)
    if isempty(data.fig_results) || ~ishandle(data.fig_results)
        data.fig_results = figure('Name', 'Analysis Results', 'Position', [100 50 1400 900]);
    else
        figure(data.fig_results);
        clf;
    end

    % Calculate per-winding losses
    fils_per_cond = data.Nx * data.Ny;
    winding_losses = zeros(data.n_windings, 1);
    winding_Rdc = zeros(data.n_windings, 1);
    winding_Pdc = zeros(data.n_windings, 1);

    cond_offset = 0;
    for w = 1:data.n_windings
        n_cond_in_winding = data.windings(w).n_turns * data.windings(w).n_filar;

        for c = 1:n_cond_in_winding
            idx_start = (cond_offset + c - 1) * fils_per_cond + 1;
            idx_end = (cond_offset + c) * fils_per_cond;
            if idx_end <= length(results.P_fil)
                winding_losses(w) = winding_losses(w) + sum(results.P_fil(idx_start:idx_end));
            end
        end

        cond_offset = cond_offset + n_cond_in_winding;

        % DC loss
        [w_dim, h_dim] = data.api.wire_to_conductor_dims(data.windings(w).wire_type);
        A = w_dim * h_dim;
        winding_Rdc(w) = (data.windings(w).n_turns / data.windings(w).n_filar) / (data.sigma * A);
        winding_Pdc(w) = 0.5 * data.windings(w).current^2 * winding_Rdc(w);
    end

    annotation('textbox', [0 0.96 1 0.04], ...
        'String', sprintf('Analysis Results @ %.0f kHz', data.f/1e3), ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
        'FontSize', 14, 'FontWeight', 'bold');

    subplot(2,3,1);
    plot_current_density(geom, results);
    title('Current Density');

    subplot(2,3,2);
    plot_loss_density(geom, results);
    title('Loss Density');

    subplot(2,3,3);
    bar([winding_Pdc, winding_losses]*1e3);
    set(gca, 'XTickLabel', {data.windings.name});
    ylabel('Loss (mW)');
    legend('DC Loss', 'AC Loss', 'Location', 'best');
    title('Winding Loss Comparison');
    grid on;

    subplot(2,3,4);
    rac_rdc = winding_losses ./ max(winding_Pdc, 1e-12);
    bar(rac_rdc);
    set(gca, 'XTickLabel', {data.windings.name});
    ylabel('R_{AC}/R_{DC}');
    title('AC Resistance Factor');
    grid on;

    subplot(2,3,5);
    axis off;
    text(0.05, 0.95, 'Loss Summary', 'FontSize', 12, 'FontWeight', 'bold');
    y_pos = 0.85;

    for w = 1:data.n_windings
        text(0.05, y_pos, sprintf('%s:', data.windings(w).name), ...
            'FontSize', 10, 'FontWeight', 'bold', 'Color', data.winding_colors{w});
        y_pos = y_pos - 0.08;

        text(0.05, y_pos, sprintf('  Wire: %s', data.windings(w).wire_type), 'FontSize', 9);
        y_pos = y_pos - 0.07;

        text(0.05, y_pos, sprintf('  Config: %d turns, %s', ...
            data.windings(w).n_turns, get_filar_name(data.windings(w).n_filar)), 'FontSize', 9);
        y_pos = y_pos - 0.07;

        text(0.05, y_pos, sprintf('  DC Loss: %.4f W', winding_Pdc(w)), 'FontSize', 9);
        y_pos = y_pos - 0.07;

        text(0.05, y_pos, sprintf('  AC Loss: %.4f W', winding_losses(w)), 'FontSize', 9);
        y_pos = y_pos - 0.07;

        text(0.05, y_pos, sprintf('  Rac/Rdc: %.2f', rac_rdc(w)), 'FontSize', 9);
        y_pos = y_pos - 0.12;
    end

    text(0.05, y_pos, sprintf('PEEC Total Loss: %.4f W', results.P_total), ...
        'FontSize', 11, 'FontWeight', 'bold');

    subplot(2,3,6);
    axis off;
    text(0.05, 0.95, 'Core & Configuration', 'FontSize', 12, 'FontWeight', 'bold');
    text(0.05, 0.85, sprintf('Core: %s', data.selected_core), 'FontSize', 9);
    text(0.05, 0.75, sprintf('Frequency: %.0f kHz', data.f/1e3), 'FontSize', 9);

    y_pos = 0.65;
    for w = 1:data.n_windings
        text(0.05, y_pos, sprintf('%s: %d x %s', ...
            data.windings(w).name, data.windings(w).n_turns, ...
            get_filar_name(data.windings(w).n_filar)), ...
            'FontSize', 9, 'Color', data.winding_colors{w});
        y_pos = y_pos - 0.08;
    end

    text(0.05, y_pos - 0.05, 'Data: Offline database', 'FontSize', 8, ...
        'Color', [0.5 0.5 0.5]);

    fprintf('\n=== ANALYSIS COMPLETE ===\n');

    % Store results figure handle
    data.fig_results = gcf;
    guidata(data.fig_gui, data);
end

% ===============================================================
% UTILITY
% ===============================================================

function reset_defaults(~, ~)
    close all;
    interactive_winding_designer();
end

function name = get_filar_name(n)
    names = {'Single-filar', 'Bi-filar', 'Tri-filar', 'Quad-filar'};
    if n >= 1 && n <= 4
        name = names{n};
    else
        name = sprintf('%d-filar', n);
    end
end

function parse_om_svg(svg_str, ax)
    % Robust SVG parser for Octave - renders circles, rectangles, polygons, and paths
    cla(ax);
    hold(ax, 'on');
    color_map = parse_css_colors(svg_str);
    
    % Extract viewBox for coordinate mapping
    % Allow spaces around = and quotes
    vb_match = regexp(svg_str, 'viewBox\s*=\s*["'']([^"'']*)["'']', 'tokens', 'once');
    if ~isempty(vb_match)
        vb = sscanf(vb_match{1}, '%f %f %f %f');
        if length(vb) == 4
            pad = 0.05;
            x0 = vb(1); y0 = vb(2); w = vb(3); h = vb(4);
            xlim(ax, [x0 - pad*w, x0 + w*(1+pad)]);
            ylim(ax, [y0 - pad*h, y0 + h*(1+pad)]);
            % SVG Y is down, plot Y is up. OpenMagnetics usually handles this,
            % but if needed we could flip. For now assume standard Cartesian.
        end
    end

    % --- Helper to extract numeric attribute ---
    function val = get_attr(tag, attr)
        val = NaN;
        % Allow spaces around = and quotes
        pat = [attr '\s*=\s*["'']?([0-9\.\-eE]+)["'']?'];
        tok = regexp(tag, pat, 'tokens', 'once');
        if ~isempty(tok)
            val = str2double(tok{1});
        end
    end

    % --- Helper to extract string attribute ---
    function str_val = get_attr_str(tag, attr)
        str_val = '';
        pat = [attr '\s*=\s*["'']([^"'']*)["'']'];
        tok = regexp(tag, pat, 'tokens', 'once');
        if ~isempty(tok)
            str_val = tok{1};
        end
    end

    % --- Draw Paths (Core shapes) ---
    path_tags = regexp(svg_str, '<path[^>]*>', 'match');
    for i = 1:length(path_tags)
        tag = path_tags{i};
        d = get_attr_str(tag, 'd');
        class_name = get_attr_str(tag, 'class');
        style = get_attr_str(tag, 'style');
        [rgb, alpha, has_fill, known] = get_class_style(class_name, color_map);
        
        if ~isempty(d)
            % Heuristic: extract all numbers and plot as polygon
            % Handle "10-10" case by putting space before minus
            d_spaced = regexprep(d, '([0-9])-', '$1 -');
            % Remove commands
            d_clean = regexprep(d_spaced, '[a-zA-Z,]', ' ');
            nums = sscanf(d_clean, '%f');
            
            if length(nums) >= 4 && mod(length(nums), 2) == 0
                px = nums(1:2:end);
                py = nums(2:2:end);
                
                if tag_has_fill_none(tag) || contains(style, 'fill:none') || (known && ~has_fill)
                    line(px, py, 'Parent', ax, 'Color', 'k', 'LineWidth', 1);
                else
                    if ~(known && has_fill)
                        rgb = get_default_color(class_name);
                        alpha = 1.0;
                    end
                    h = patch(ax, px, py, rgb, 'EdgeColor', 'k', 'FaceAlpha', 0.5);
                    if alpha < 1.0
                        try
                            set(h, 'FaceAlpha', alpha);
                        catch
                        end
                    end
                end
            end
        end
    end

    % --- Draw Polygons ---
    poly_tags = regexp(svg_str, '<polygon[^>]*>', 'match');
    for i = 1:length(poly_tags)
        tag = poly_tags{i};
        pts_str = get_attr_str(tag, 'points');
        class_name = get_attr_str(tag, 'class');
        [rgb, alpha, has_fill, known] = get_class_style(class_name, color_map);
        if ~isempty(pts_str)
            if tag_has_fill_none(tag) || (known && ~has_fill)
                continue;
            end
            % Replace commas with spaces
            nums = sscanf(regexprep(pts_str, '[,]', ' '), '%f');
            if length(nums) >= 4 && mod(length(nums), 2) == 0
                px = nums(1:2:end);
                py = nums(2:2:end);
                if ~(known && has_fill)
                    rgb = get_default_color(class_name);
                    alpha = 1.0;
                end
                h = patch(ax, px, py, rgb, 'EdgeColor', 'k', 'FaceAlpha', 0.5);
                if alpha < 1.0
                    try
                        set(h, 'FaceAlpha', alpha);
                    catch
                    end
                end
            end
        end
    end

    % --- Draw Rectangles ---
    rect_tags = regexp(svg_str, '<rect[^>]*>', 'match');
    for i = 1:length(rect_tags)
        tag = rect_tags{i};
        x = get_attr(tag, 'x');
        y = get_attr(tag, 'y');
        w = get_attr(tag, 'width');
        h = get_attr(tag, 'height');
        class_name = get_attr_str(tag, 'class');
        [rgb, alpha, has_fill, known] = get_class_style(class_name, color_map);
        
        if ~isnan(x) && ~isnan(y) && ~isnan(w) && ~isnan(h)
            if tag_has_fill_none(tag) || (known && ~has_fill)
                continue;
            end
            if ~(known && has_fill)
                rgb = get_default_color(class_name);
                alpha = 1.0;
            end
            hrect = rectangle('Parent', ax, 'Position', [x, y, w, h], ...
                'EdgeColor', 'k', 'FaceColor', rgb);
            if alpha < 1.0
                try
                    set(hrect, 'FaceAlpha', alpha);
                catch
                end
            end
        end
    end

    % --- Draw Circles ---
    circle_tags = regexp(svg_str, '<circle[^>]*>', 'match');
    for i = 1:length(circle_tags)
        tag = circle_tags{i};
        cx = get_attr(tag, 'cx');
        cy = get_attr(tag, 'cy');
        r = get_attr(tag, 'r');
        class_name = get_attr_str(tag, 'class');
        [rgb, alpha, has_fill, known] = get_class_style(class_name, color_map);

        if ~isnan(cx) && ~isnan(cy) && ~isnan(r)
            if tag_has_fill_none(tag) || (known && ~has_fill)
                continue;
            end
            if ~(known && has_fill)
                rgb = get_default_color(class_name);
                alpha = 1.0;
            end
            theta = linspace(0, 2*pi, 30);
            h = fill(ax, cx + r*cos(theta), cy + r*sin(theta), ...
                rgb, 'EdgeColor', 'none');
            if alpha < 1.0
                try
                    set(h, 'FaceAlpha', alpha);
                catch
                end
            end
        end
    end
    
    axis(ax, 'equal');
    set(ax, 'XTick', [], 'YTick', [], 'Box', 'off', 'XColor', 'none', 'YColor', 'none');
    xlabel(ax, '');
    ylabel(ax, '');
    title(ax, '');
    hold(ax, 'off');
end

function color_map = parse_css_colors(svg_str)
    % Parse CSS <style> block to extract class name -> color mapping
    color_map = struct();
    style_match = regexp(svg_str, '<style[^>]*>\s*<!\[CDATA\[(.*?)\]\]>\s*</style>', 'tokens', 'once');
    if isempty(style_match)
        style_match = regexp(svg_str, '<style[^>]*>(.*?)</style>', 'tokens', 'once');
    end
    if isempty(style_match)
        return;
    end
    css_text = style_match{1};
    rules = regexp(css_text, '\.([A-Za-z_][A-Za-z0-9_]*)\s*\{([^}]*)\}', 'tokens');
    for i = 1:length(rules)
        class_name = rules{i}{1};
        rule_body = rules{i}{2};
        safe_name = make_safe_field(class_name);
        has_fill = false;
        rgb = [];
        fill_none = ~isempty(regexp(rule_body, 'fill:\s*none', 'once'));
        if ~fill_none
            fill_match = regexp(rule_body, 'fill:\s*#([0-9a-fA-F]{6})', 'tokens', 'once');
            if ~isempty(fill_match)
                hex = fill_match{1};
                rgb = [hex2dec(hex(1:2)), hex2dec(hex(3:4)), hex2dec(hex(5:6))] / 255;
                has_fill = true;
            end
        end
        opacity_match = regexp(rule_body, 'opacity:\s*([0-9.]+)', 'tokens', 'once');
        alpha = 1.0;
        if ~isempty(opacity_match)
            alpha = str2double(opacity_match{1});
        end
        color_map.(safe_name) = struct('rgb', rgb, 'alpha', alpha, 'has_fill', has_fill);
    end
end

function [rgb, alpha, has_fill, known] = get_class_style(class_name, color_map)
    rgb = [];
    alpha = 1.0;
    has_fill = true;
    known = false;
    safe_name = make_safe_field(class_name);
    if isfield(color_map, safe_name)
        entry = color_map.(safe_name);
        known = true;
        if isfield(entry, 'alpha'); alpha = entry.alpha; end
        if isfield(entry, 'has_fill'); has_fill = entry.has_fill; end
        if isfield(entry, 'rgb'); rgb = entry.rgb; end
    end
end

function rgb = get_default_color(class_name)
    switch class_name
        case 'ferrite'
            rgb = [0.482 0.486 0.490];
        case 'bobbin'
            rgb = [0.325 0.592 0.588];
        case 'copper'
            rgb = [0.722 0.451 0.200];
        case 'insulation'
            rgb = [1.000 0.941 0.357];
        case 'spacer'
            rgb = [0.231 0.231 0.231];
        case 'fr4'
            rgb = [0.0 0.5 0.0];
        otherwise
            rgb = [0.9 0.9 0.9];
    end
end

function tf = tag_has_fill_none(tag)
    tf = ~isempty(regexp(tag, 'fill\s*=\s*["'']none["'']', 'once')) || ...
         ~isempty(regexp(tag, 'fill\s*:\s*none', 'once'));
end

function safe = make_safe_field(name)
    safe = regexprep(name, '[^a-zA-Z0-9_]', '_');
    if ~isempty(safe) && (safe(1) >= '0' && safe(1) <= '9')
        safe = ['c_' safe];
    end
    if isempty(safe)
        safe = 'unknown';
    end
end
