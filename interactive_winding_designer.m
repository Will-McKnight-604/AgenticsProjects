% interactive_winding_designer.m
% Interactive GUI for designing multi-filar transformer windings
% Layout: Core (left) | Windings (center) | Visualization (right)

function interactive_winding_designer()

    close all;

    % Initialize global data structure
    data = struct();

    % Initialize OpenMagnetics API
    data.api = openmagnetics_api_interface();

    % Initialize layout calculator
    data.layout_calc = openmagnetics_winding_layout(data.api);

    % Load databases
    fprintf('Loading wire and core databases...\n');
    data.wires = data.api.get_wires();
    data.cores = data.api.get_cores();
    data.materials = data.api.get_materials();

    % Default transformer configuration
    data.n_windings = 2;
    data.winding_names = {'Primary', 'Secondary'};
    data.winding_colors = {[0.2 0.4 0.8], [0.8 0.2 0.2]};

    % Default winding parameters
    data.windings(1).name = 'Primary';
    data.windings(1).n_turns = 10;
    data.windings(1).n_filar = 1;
    data.windings(1).current = 10;
    data.windings(1).phase = 0;
    data.windings(1).wire_type = 'AWG_22';
    data.windings(1).wire_shape = 'round';

    data.windings(2).name = 'Secondary';
    data.windings(2).n_turns = 5;
    data.windings(2).n_filar = 1;
    data.windings(2).current = 5;
    data.windings(2).phase = 180;
    data.windings(2).wire_type = 'AWG_22';
    data.windings(2).wire_shape = 'round';

    % Default core selection
    core_list = fieldnames(data.cores);
    if ~isempty(core_list)
        data.selected_core = core_list{1};
    else
        data.selected_core = 'None';
    end

    % Geometry parameters (from selected wire)
    wire_info = data.api.get_wire_info(data.windings(1).wire_type);
    [w, h, shape] = data.api.wire_to_conductor_dims(data.windings(1).wire_type);

    data.width = w;
    data.height = h;
    data.windings(1).wire_shape = shape;
    data.windings(2).wire_shape = shape;
    data.gap_layer = 0.2e-3;
    data.gap_filar = 0.05e-3;
    data.gap_winding = 1e-3;

    % Analysis parameters
    data.sigma = 5.8e7;
    data.mu0 = 4*pi*1e-7;
    data.f = 100e3;
    data.Nx = 6;
    data.Ny = 6;

    % Create main GUI figure
    data.fig_gui = figure('Name', 'Interactive Winding Designer', ...
                          'Position', [50 100 1600 700], ...
                          'NumberTitle', 'off', ...
                          'MenuBar', 'none', ...
                          'Resize', 'off');

    % Create results figure (initially hidden)
    data.fig_results = [];

    % Build GUI layout
    build_gui(data);

    % Initial visualization
    update_visualization(data);
end

function build_gui(data)

    fig = data.fig_gui;

    % Main title
    uicontrol('Parent', fig, 'Style', 'text', ...
              'String', 'Interactive Transformer Design Tool with OpenMagnetics Integration', ...
              'Position', [20 660 1560 30], ...
              'FontSize', 14, 'FontWeight', 'bold', ...
              'HorizontalAlignment', 'center');

    % ========== LEFT PANEL: CORE SELECTION ==========
    core_panel = uipanel('Parent', fig, ...
                        'Position', [0.02 0.15 0.28 0.8], ...
                        'Title', 'Core Selection (OpenMagnetics)');

    % Core shape dropdown
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Core Shape:', ...
              'Position', [20 480 120 20], ...
              'HorizontalAlignment', 'left');

    core_list = fieldnames(data.cores);
    if isempty(core_list)
        core_list = {'None'};
    end

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', core_list, ...
              'Position', [20 455 380 25], ...
              'Tag', 'core_dropdown', ...
              'Callback', @select_core);

    % Core information display
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Core Information:', ...
              'Position', [20 420 150 20], ...
              'FontWeight', 'bold', ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', get_core_info_text(data), ...
              'Position', [20 250 380 165], ...
              'HorizontalAlignment', 'left', ...
              'BackgroundColor', [0.95 0.95 0.95], ...
              'Tag', 'core_info');

    % Material selection
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Core Material:', ...
              'Position', [20 215 120 20], ...
              'HorizontalAlignment', 'left');

    mat_list = fieldnames(data.materials);
    if isempty(mat_list)
        mat_list = {'N87'};
    end

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', mat_list, ...
              'Position', [20 190 380 25], ...
              'Tag', 'material_dropdown', ...
              'Callback', @select_material);

    % Material info
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', get_material_info_text(data), ...
              'Position', [20 80 380 105], ...
              'HorizontalAlignment', 'left', ...
              'BackgroundColor', [0.95 0.95 0.95], ...
              'Tag', 'material_info');

    % Frequency input
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Operating Frequency (kHz):', ...
              'Position', [20 45 180 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.f/1e3), ...
              'Position', [210 45 80 25], ...
              'Tag', 'frequency', ...
              'Callback', @update_frequency);

    % ========== CENTER PANEL: WINDING CONFIGURATION ==========
    winding_panel = uipanel('Parent', fig, ...
                           'Position', [0.32 0.15 0.34 0.8], ...
                           'Title', 'Winding Configuration');

    % Create tabs using button group
    tab_group = uibuttongroup('Parent', winding_panel, ...
                              'Position', [0.02 0.88 0.96 0.1], ...
                              'BorderType', 'none');

    % Tab buttons
    for w = 1:data.n_windings
        uicontrol('Parent', tab_group, 'Style', 'togglebutton', ...
                  'String', data.windings(w).name, ...
                  'Position', [10 + (w-1)*120, 5, 110, 30], ...
                  'Tag', sprintf('tab%d', w), ...
                  'Callback', {@switch_tab, w});
    end

    % Set first tab as selected
    set(findobj(tab_group, 'Tag', 'tab1'), 'Value', 1);

    % Content panels for each winding
    for w = 1:data.n_windings
        panel = uipanel('Parent', winding_panel, ...
                        'Position', [0.02 0.02 0.96 0.84], ...
                        'Visible', 'off', ...
                        'Tag', sprintf('content%d', w));

        % Winding name
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', sprintf('%s Winding', data.windings(w).name), ...
                  'Position', [20 430 300 25], ...
                  'FontSize', 12, 'FontWeight', 'bold', ...
                  'HorizontalAlignment', 'left');

        % Wire type selection
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Wire Type:', ...
                  'Position', [20 395 100 20], ...
                  'HorizontalAlignment', 'left');

        wire_list = fieldnames(data.wires);
        if isempty(wire_list)
            wire_list = {'AWG_22'};
        end

        uicontrol('Parent', panel, 'Style', 'popupmenu', ...
                  'String', wire_list, ...
                  'Position', [130 395 250 25], ...
                  'Tag', sprintf('wire_type_%d', w), ...
                  'Callback', {@select_wire, w});

        % Wire info display
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', get_wire_info_text(data, w), ...
                  'Position', [20 335 460 55], ...
                  'HorizontalAlignment', 'left', ...
                  'BackgroundColor', [0.95 0.95 1.0], ...
                  'Tag', sprintf('wire_info_%d', w));

        % Number of turns
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Number of Turns:', ...
                  'Position', [20 290 150 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                  'String', 'âˆ’', ...
                  'Position', [180 290 30 25], ...
                  'FontSize', 14, ...
                  'Tag', sprintf('turns_dec_%d', w), ...
                  'Callback', {@adjust_turns, w, -1});

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).n_turns), ...
                  'Position', [215 290 50 25], ...
                  'FontSize', 11, ...
                  'HorizontalAlignment', 'center', ...
                  'Tag', sprintf('turns_val_%d', w), ...
                  'Callback', {@update_turns_manual, w});

        uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                  'String', '+', ...
                  'Position', [270 290 30 25], ...
                  'FontSize', 14, ...
                  'Tag', sprintf('turns_inc_%d', w), ...
                  'Callback', {@adjust_turns, w, 1});

        % Parallel strands (filar)
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Parallel Strands (Filar):', ...
                  'Position', [20 240 150 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                  'String', 'âˆ’', ...
                  'Position', [180 240 30 25], ...
                  'FontSize', 14, ...
                  'Tag', sprintf('filar_dec_%d', w), ...
                  'Callback', {@adjust_filar, w, -1});

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).n_filar), ...
                  'Position', [215 240 50 25], ...
                  'FontSize', 11, ...
                  'HorizontalAlignment', 'center', ...
                  'Tag', sprintf('filar_val_%d', w), ...
                  'Callback', {@update_filar_manual, w});

        uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                  'String', '+', ...
                  'Position', [270 240 30 25], ...
                  'FontSize', 14, ...
                  'Tag', sprintf('filar_inc_%d', w), ...
                  'Callback', {@adjust_filar, w, 1});

        % Filar type label
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', get_filar_name(data.windings(w).n_filar), ...
                  'Position', [310 240 150 25], ...
                  'FontSize', 10, 'FontWeight', 'bold', ...
                  'HorizontalAlignment', 'left', ...
                  'ForegroundColor', [0.2 0.6 0.2], ...
                  'Tag', sprintf('filar_name_%d', w));

        % Current settings
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'RMS Current (A):', ...
                  'Position', [20 190 150 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).current), ...
                  'Position', [180 190 80 25], ...
                  'Tag', sprintf('current_%d', w), ...
                  'Callback', {@update_current, w});

        % Phase settings
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Phase (degrees):', ...
                  'Position', [20 140 150 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).phase), ...
                  'Position', [180 140 80 25], ...
                  'Tag', sprintf('phase_%d', w), ...
                  'Callback', {@update_phase, w});

        % Summary info
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Configuration Summary:', ...
                  'Position', [20 90 300 20], ...
                  'FontSize', 10, 'FontWeight', 'bold', ...
                  'HorizontalAlignment', 'left');

        summary_str = get_winding_summary(data, w);

        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', summary_str, ...
                  'Position', [20 20 460 65], ...
                  'HorizontalAlignment', 'left', ...
                  'Tag', sprintf('summary_%d', w));
    end

    % Show first panel
    set(findobj(winding_panel, 'Tag', 'content1'), 'Visible', 'on');

    % ========== RIGHT PANEL: VISUALIZATION ==========
    vis_panel = uipanel('Parent', fig, ...
                        'Position', [0.68 0.15 0.30 0.8], ...
                        'Title', 'Winding Layout in Core Window');

    % Visualization mode selector
    uicontrol('Parent', vis_panel, 'Style', 'text', ...
              'String', 'View Mode:', ...
              'Position', [10 500 80 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', vis_panel, 'Style', 'popupmenu', ...
              'String', {'Schematic (2D)', 'Core Window Fit', 'Loss Analysis'}, ...
              'Position', [90 500 150 25], ...
              'Value', 2, ...
              'Tag', 'vis_mode', ...
              'Callback', @change_vis_mode);

    % Packing pattern selector (for Core Window Fit mode)
    uicontrol('Parent', vis_panel, 'Style', 'text', ...
              'String', 'Packing:', ...
              'Position', [250 500 60 20], ...
              'HorizontalAlignment', 'left', ...
              'Tag', 'packing_label');

    uicontrol('Parent', vis_panel, 'Style', 'popupmenu', ...
              'String', {'Layered', 'Orthocyclic', 'Random'}, ...
              'Position', [310 500 120 25], ...
              'Value', 1, ...
              'Tag', 'packing_pattern', ...
              'Callback', @change_packing);

    % Axes for visualization
    ax = axes('Parent', vis_panel, ...
              'Position', [0.1 0.1 0.85 0.75], ...
              'Tag', 'vis_axes');

    % Info text box
    uicontrol('Parent', vis_panel, 'Style', 'text', ...
              'String', '', ...
              'Position', [10 10 430 40], ...
              'HorizontalAlignment', 'left', ...
              'BackgroundColor', [0.95 0.95 1.0], ...
              'FontSize', 8, ...
              'Tag', 'vis_info');

    % ========== BOTTOM BUTTONS ==========
    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
              'String', 'Run Analysis', ...
              'Position', [650 50 150 40], ...
              'FontSize', 12, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.2 0.7 0.3], ...
              'ForegroundColor', 'w', ...
              'Callback', @run_analysis);

    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
              'String', 'Reset to Defaults', ...
              'Position', [820 50 150 40], ...
              'FontSize', 11, ...
              'Callback', @reset_defaults);

    % Store data in figure
    guidata(fig, data);
end

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
end

function str = get_material_info_text(data)
    mat_list = fieldnames(data.materials);
    if isempty(mat_list)
        str = 'No material data';
        return;
    end

    mat_name = mat_list{1};  % Default to first material
    mat = data.materials.(mat_name);

    str = sprintf('Material: %s\n', mat_name);
    if isfield(mat, 'manufacturer')
        str = [str sprintf('Mfg: %s\n', mat.manufacturer)];
    end
    if isfield(mat, 'mu_initial')
        str = [str sprintf('mu_i: %d\n', mat.mu_initial)];
    end
    if isfield(mat, 'Bsat')
        str = [str sprintf('Bsat: %.2f T\n', mat.Bsat)];
    end
end

function str = get_wire_info_text(data, winding)
    wire_type = data.windings(winding).wire_type;
    wire = data.wires.(wire_type);

    if isfield(wire, 'diameter')
        str = sprintf('Diameter: %.3f mm\nArea: %.3e m^2\nR: %.3f Î©/m', ...
            wire.diameter*1e3, wire.area, wire.resistance);
    elseif isfield(wire, 'strands')
        str = sprintf('Litz: %d x %.3f mm\nOuter: %.3f mm\nArea: %.3e m^2', ...
            wire.strands, wire.strand_diameter*1e3, wire.outer_diameter*1e3, wire.area);
    else
        str = 'Wire info not available';
    end
end

function str = get_winding_summary(data, winding)
    n_cond = data.windings(winding).n_turns * data.windings(winding).n_filar;
    I_per_strand = data.windings(winding).current / data.windings(winding).n_filar;

    wire_type = data.windings(winding).wire_type;
    [w, h] = data.api.wire_to_conductor_dims(wire_type);

    str = sprintf('Total conductors: %d\nCurrent per strand: %.2f A\nConductor size: %.3f x %.3f mm', ...
        n_cond, I_per_strand, w*1e3, h*1e3);
end

function select_core(src, ~)
    fig = gcbf;
    data = guidata(fig);

    core_list = get(src, 'String');
    idx = get(src, 'Value');
    data.selected_core = core_list{idx};

    % Update core info display
    set(findobj(fig, 'Tag', 'core_info'), 'String', get_core_info_text(data));

    guidata(fig, data);
end

function select_material(src, ~)
    fig = gcbf;
    data = guidata(fig);

    mat_list = get(src, 'String');
    idx = get(src, 'Value');

    % Update material info display
    set(findobj(fig, 'Tag', 'material_info'), 'String', get_material_info_text(data));

    guidata(fig, data);
end

function update_frequency(src, ~)
    fig = gcbf;
    data = guidata(fig);

    data.f = str2double(get(src, 'String')) * 1e3;
    guidata(fig, data);
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

    % Update displays
    set(findobj(fig, 'Tag', sprintf('wire_info_%d', winding)), ...
        'String', get_wire_info_text(data, winding));
    update_summary(fig, data, winding);

    guidata(fig, data);
    update_visualization(data);
end

function switch_tab(~, ~, tab_num)
    fig = gcbf;
    data = guidata(fig);

    % Hide all content panels
    for w = 1:data.n_windings
        set(findobj(fig, 'Tag', sprintf('content%d', w)), 'Visible', 'off');
    end

    % Show selected panel
    set(findobj(fig, 'Tag', sprintf('content%d', tab_num)), 'Visible', 'on');
end

function adjust_turns(~, ~, winding, delta)
    fig = gcbf;
    data = guidata(fig);

    new_val = max(1, data.windings(winding).n_turns + delta);
    data.windings(winding).n_turns = new_val;

    set(findobj(fig, 'Tag', sprintf('turns_val_%d', winding)), 'String', num2str(new_val));
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
    update_summary(fig, data, winding);

    guidata(fig, data);
    update_visualization(data);
end

function update_turns_manual(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);

    new_val = round(str2double(get(src, 'String')));
    new_val = max(1, new_val);

    data.windings(winding).n_turns = new_val;
    set(src, 'String', num2str(new_val));
    update_summary(fig, data, winding);

    guidata(fig, data);
    update_visualization(data);
end

function update_filar_manual(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);

    new_val = round(str2double(get(src, 'String')));
    new_val = max(1, min(4, new_val));

    data.windings(winding).n_filar = new_val;
    set(src, 'String', num2str(new_val));
    set(findobj(fig, 'Tag', sprintf('filar_name_%d', winding)), 'String', get_filar_name(new_val));
    update_summary(fig, data, winding);

    guidata(fig, data);
    update_visualization(data);
end

function update_current(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);

    data.windings(winding).current = str2double(get(src, 'String'));
    update_summary(fig, data, winding);
    guidata(fig, data);
end

function update_phase(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);

    data.windings(winding).phase = str2double(get(src, 'String'));
    guidata(fig, data);
end

function update_summary(fig, data, winding)
    summary_str = get_winding_summary(data, winding);
    set(findobj(fig, 'Tag', sprintf('summary_%d', winding)), 'String', summary_str);
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

function update_visualization(data)
    fig = data.fig_gui;
    ax = findobj(fig, 'Tag', 'vis_axes');
    vis_mode_ctrl = findobj(fig, 'Tag', 'vis_mode');
    vis_mode = get(vis_mode_ctrl, 'Value');

    cla(ax);

    switch vis_mode
        case 1
            % Schematic 2D view (original)
            visualize_schematic_2d(data, ax);
        case 2
            % Core window fit view
            visualize_core_window(data, ax);
        case 3
            % Loss analysis placeholder
            visualize_schematic_2d(data, ax);
            text(ax, 0, 0, 'Run Analysis to see loss distribution', ...
                'HorizontalAlignment', 'center', 'FontSize', 10);
    end
end

function visualize_schematic_2d(data, ax)
    % Original 2D schematic visualization with proper wire shapes

    hold(ax, 'on');
    axis(ax, 'equal');
    grid(ax, 'on');

    x_offset = 0;
    max_y_all = 0;

    for w = 1:data.n_windings
        n_turns = data.windings(w).n_turns;
        n_filar = data.windings(w).n_filar;

        [w_dim, h_dim, shape] = data.api.wire_to_conductor_dims(data.windings(w).wire_type);

        x_pos = x_offset;
        y_offset = 0;

        for turn = 1:n_turns
            for strand = 1:n_filar
                y_pos = y_offset + (strand - 1) * (h_dim + data.gap_filar);

                % Draw based on wire shape
                if strcmp(shape, 'round')
                    % Draw circle for round wire
                    r = w_dim / 2;
                    theta = linspace(0, 2*pi, 50);
                    fill(ax, x_pos + r*cos(theta), y_pos + h_dim/2 + r*sin(theta), ...
                        data.winding_colors{w}, 'EdgeColor', 'k', 'LineWidth', 0.5);
                else
                    % Draw rectangle for rectangular/foil wire
                    rectangle('Parent', ax, 'Position', [x_pos - w_dim/2, y_pos, w_dim, h_dim], ...
                        'FaceColor', data.winding_colors{w}, ...
                        'EdgeColor', 'k', 'LineWidth', 0.5);
                end

                if n_filar > 1 && strand > 1
                    plot(ax, [x_pos + w_dim/2 + 0.05e-3, x_pos + w_dim/2 + 0.15e-3], ...
                        [y_pos + h_dim/2, y_pos + h_dim/2], ...
                        'Color', data.winding_colors{w}, 'LineWidth', 2);
                end
            end

            turn_center_y = y_offset + (n_filar * h_dim + (n_filar-1) * data.gap_filar) / 2;
            text(x_pos - w_dim/2 - 0.3e-3, turn_center_y, ...
                sprintf('T%d', turn), 'FontSize', 7, 'Parent', ax, ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');

            if turn == 1 && n_filar > 1
                text(x_pos + w_dim/2 + 0.25e-3, turn_center_y, ...
                    sprintf('%dx', n_filar), 'FontSize', 7, 'Parent', ax, ...
                    'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
                    'Color', data.winding_colors{w}, 'FontWeight', 'bold');
            end

            turn_height = n_filar * h_dim + (n_filar - 1) * data.gap_filar + data.gap_layer;
            y_offset = y_offset + turn_height;
        end

        max_y_all = max(max_y_all, y_offset);

        text(x_pos, y_offset + 0.5e-3, data.windings(w).name, 'Parent', ax, ...
            'HorizontalAlignment', 'center', 'FontWeight', 'bold', ...
            'FontSize', 10, 'Color', data.winding_colors{w});

        info_str = sprintf('%d turns\n%s\n%s (%s)', n_turns, ...
            get_filar_name(n_filar), data.windings(w).wire_type, shape);
        text(x_pos, -1.5e-3, info_str, 'Parent', ax, ...
            'HorizontalAlignment', 'center', 'FontSize', 7);

        if w < data.n_windings
            x_offset = x_offset + w_dim/2 + data.gap_winding + w_dim/2;
        end
    end

    ylim(ax, [-2e-3, max_y_all * 1.5]);
    xlabel(ax, 'X Position (m)');
    ylabel(ax, 'Y Position (m)');
    title(ax, 'Winding Schematic');
    hold(ax, 'off');

    % Update info text
    set(findobj(data.fig_gui, 'Tag', 'vis_info'), 'String', ...
        'Schematic view showing winding arrangement');
end

function visualize_core_window(data, ax)
    % Show how windings fit in selected core's bobbin window
    % Uses MAS-style section-based layout with IEC insulation gaps

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

    % Build winding definitions for multi-winding layout
    winding_defs = cell(data.n_windings, 1);
    for w = 1:data.n_windings
        def = struct();
        def.wire_type  = data.windings(w).wire_type;
        def.n_turns    = data.windings(w).n_turns * data.windings(w).n_filar;
        def.name       = data.windings(w).name;
        % Voltage for IEC insulation calculation (default 0 if not set)
        if isfield(data.windings(w), 'voltage')
            def.voltage = data.windings(w).voltage;
        else
            def.voltage = 0;
        end
        % Insulation type (default basic for transformers)
        if isfield(data.windings(w), 'insulation')
            def.insulation = data.windings(w).insulation;
        else
            def.insulation = 'basic';
        end
        winding_defs{w} = def;
    end

    % Calculate section-based multi-winding layout
    layouts = data.layout_calc.calculate_multi_winding_layout(...
        data.selected_core, winding_defs, pattern);

    % Draw
    hold(ax, 'on');
    axis(ax, 'equal');

    bobbin = layouts{1}.bobbin;

    % Bobbin outline
    rectangle('Parent', ax, 'Position', [0, 0, bobbin.width, bobbin.height], ...
        'EdgeColor', 'k', 'LineWidth', 2, 'LineStyle', '--');
    text(bobbin.width/2, bobbin.height + 0.001, 'Bobbin Window', ...
        'Parent', ax, 'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');

    % Draw each winding
    total_fits = true;
    for w = 1:length(layouts)
        lay = layouts{w};
        col = data.winding_colors{mod(w-1, length(data.winding_colors)) + 1};

        if isfield(lay, 'all_fit') && ~lay.all_fit
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
            rectangle('Parent', ax, ...
                'Position', [lay.section_x_offset, 0, lay.section_width, bobbin.height], ...
                'EdgeColor', [0.6 0.6 0.6], 'LineWidth', 0.5, 'LineStyle', ':');
        end

        % Winding label
        if isfield(lay, 'section_x_offset') && isfield(lay, 'section_width')
            label_x = lay.section_x_offset + lay.section_width / 2;
        else
            label_x = mean(lay.turn_positions(:,1));
        end
        wname = 'Winding';
        if isfield(lay, 'winding_name'); wname = lay.winding_name; end
        text(label_x, -0.0005, wname, ...
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

function run_analysis(~, ~)
    fig = gcbf;
    data = guidata(fig);

    fprintf('\n=== RUNNING ANALYSIS ===\n');

    % Build conductors for all windings
    all_conductors = [];
    all_winding_map = [];
    all_wire_shapes = {};
    x_offset = 0;

    for w = 1:data.n_windings
        % Get wire dimensions for this winding
        [w_dim, h_dim, shape] = data.api.wire_to_conductor_dims(data.windings(w).wire_type);

        cfg = struct();
        cfg.n_filar = data.windings(w).n_filar;
        cfg.n_turns = data.windings(w).n_turns;
        cfg.n_windings = 1;
        cfg.width = w_dim;
        cfg.height = h_dim;
        cfg.gap_layer = data.gap_layer;
        cfg.gap_filar = data.gap_filar;
        cfg.currents = data.windings(w).current;
        cfg.phases = data.windings(w).phase;
        cfg.x_offset = x_offset;
        cfg.wire_shape = shape;

        fprintf('Building winding %d (%s) with %s wire (%s)...\n', ...
            w, data.windings(w).name, data.windings(w).wire_type, shape);
        [cond, map, shapes] = build_multifilar_winding(cfg);

        all_conductors = [all_conductors; cond];
        all_winding_map = [all_winding_map; map + (w-1)];
        all_wire_shapes = [all_wire_shapes, shapes];

        % Update x_offset
        if w < data.n_windings
            x_offset = x_offset + w_dim/2 + data.gap_winding + w_dim/2;
        end
    end

    fprintf('\nBuilding PEEC geometry with wire shapes...\n');
    geom = peec_build_geometry(all_conductors, data.sigma, data.mu0, data.Nx, data.Ny, all_winding_map, all_wire_shapes);

    fprintf('  Wire shapes: %d conductors\n', length(geom.wire_shapes));
    for i = 1:min(3, length(geom.wire_shapes))
        fprintf('    Conductor %d: %s\n', i, geom.wire_shapes{i});
    end

    fprintf('Solving at %.0f kHz...\n', data.f/1e3);
    results = peec_solve_frequency(geom, all_conductors, data.f, data.sigma, data.mu0);

    display_results(data, geom, all_conductors, all_winding_map, results);
end

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
            winding_losses(w) = winding_losses(w) + sum(results.P_fil(idx_start:idx_end));
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
    rac_rdc = winding_losses ./ winding_Pdc;
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

    text(0.05, y_pos, sprintf('Total Loss: %.4f W', results.P_total), ...
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

    fprintf('\n=== ANALYSIS COMPLETE ===\n');
end

function reset_defaults(~, ~)
    close all;
    interactive_winding_designer();
end

function name = get_filar_name(n)
    names = {'Single-filar', 'Bi-filar', 'Tri-filar', 'Quad-filar'};
    name = names{n};
end
