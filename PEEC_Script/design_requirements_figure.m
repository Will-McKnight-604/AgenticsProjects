function fig = design_requirements_figure(main_fig)
% DESIGN_REQUIREMENTS_FIGURE  WebFrontend-style Design Requirements editor
%
% Opens a figure with left sidebar listing 15 requirement categories
% and right panel showing the editor for the selected category.
%
% Input:
%   main_fig - handle to the main topology_wizard figure
%
% The figure stores all values in guidata(main_fig).design_req

    % --- Initialize design_req in main figure if needed ---
    data = guidata(main_fig);
    if ~isfield(data, 'design_req')
        data.design_req = init_design_req(data);
        guidata(main_fig, data);
    end

    % --- Figure creation ---
    scr = get(0, 'ScreenSize');
    fig_w = 900;
    fig_h = 650;
    fig_x = max(20, floor((scr(3) - fig_w) / 2));
    fig_y = max(20, floor((scr(4) - fig_h) / 2));

    fig = figure('Name', 'Design Requirements Editor', ...
                 'Position', [fig_x fig_y fig_w fig_h], ...
                 'NumberTitle', 'off', ...
                 'MenuBar', 'none', ...
                 'ToolBar', 'none', ...
                 'Resize', 'on', ...
                 'Color', [0.94 0.94 0.94], ...
                 'UserData', main_fig);

    % Store handles for the design req figure internally
    drfig = struct();
    drfig.main_fig = main_fig;
    drfig.fig = fig;

    % --- Category definitions ---
    % {key, display_name, required_flag}
    categories = { ...
        'numberWindings',       'Number of Windings',       true;  ...
        'magnetizingInductance','Magnetizing Inductance',   true;  ...
        'turnsRatios',          'Turns Ratios',             true;  ...
        'minimumImpedance',     'Minimum Impedance',        false; ...
        'wiringTechnology',     'Wiring Technology',        false; ...
        'insulation',           'Insulation',               false; ...
        'leakageInductance',    'Leakage Inductance',       false; ...
        'strayCapacitance',     'Stray Capacitance',        false; ...
        'isolationSides',       'Isolation Sides',          false; ...
        'operatingTemperature', 'Operating Temperature',    false; ...
        'maximumWeight',        'Maximum Weight',           false; ...
        'maximumDimensions',    'Maximum Dimensions',       false; ...
        'terminalType',         'Terminal Type',             false; ...
        'topology',             'Topology',                 false; ...
        'market',               'Market',                   false  ...
    };
    n_cats = size(categories, 1);
    drfig.categories = categories;
    drfig.n_cats = n_cats;

    % --- Color scheme (dark sidebar) ---
    sidebar_bg = [0.14 0.14 0.22];
    sidebar_fg = [0.85 0.85 0.95];
    highlight_bg = [0.22 0.22 0.35];
    required_fg = [0.8 0.6 0.0];

    % --- Left sidebar panel (28% width) ---
    sidebar_panel = uipanel('Parent', fig, ...
        'Units', 'normalized', ...
        'Position', [0.0 0.0 0.28 1.0], ...
        'BackgroundColor', sidebar_bg, ...
        'BorderType', 'none');

    % Title in sidebar
    uicontrol('Parent', sidebar_panel, 'Style', 'text', ...
        'String', 'Requirements', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.95 0.96 0.04], ...
        'FontSize', 12, 'FontWeight', 'bold', ...
        'ForegroundColor', [0.95 0.95 1.0], ...
        'BackgroundColor', sidebar_bg, ...
        'HorizontalAlignment', 'center');

    % Create sidebar rows
    row_h = 0.055;
    row_gap = 0.005;
    start_y = 0.92;

    drfig.sidebar_labels = zeros(n_cats, 1);
    drfig.sidebar_btns = zeros(n_cats, 1);
    drfig.sidebar_rows = zeros(n_cats, 1);

    dr = data.design_req;

    for k = 1:n_cats
        cat_key = categories{k, 1};
        cat_name = categories{k, 2};
        is_required = categories{k, 3};
        y = start_y - (k - 1) * (row_h + row_gap);

        % Row background (for highlight on selection)
        drfig.sidebar_rows(k) = uicontrol('Parent', sidebar_panel, 'Style', 'text', ...
            'String', '', ...
            'Units', 'normalized', ...
            'Position', [0.0 y 1.0 row_h], ...
            'BackgroundColor', sidebar_bg, ...
            'Enable', 'inactive', ...
            'ButtonDownFcn', {@cb_sidebar_click, cat_key});

        % Category label
        drfig.sidebar_labels(k) = uicontrol('Parent', sidebar_panel, 'Style', 'text', ...
            'String', cat_name, ...
            'Units', 'normalized', ...
            'Position', [0.03 y 0.55 row_h], ...
            'FontSize', 8, ...
            'ForegroundColor', sidebar_fg, ...
            'BackgroundColor', sidebar_bg, ...
            'HorizontalAlignment', 'left', ...
            'Enable', 'inactive', ...
            'ButtonDownFcn', {@cb_sidebar_click, cat_key});

        if is_required
            % "Required" label
            drfig.sidebar_btns(k) = uicontrol('Parent', sidebar_panel, 'Style', 'text', ...
                'String', 'Required', ...
                'Units', 'normalized', ...
                'Position', [0.60 y+0.005 0.38 row_h-0.01], ...
                'FontSize', 7, ...
                'ForegroundColor', required_fg, ...
                'BackgroundColor', sidebar_bg, ...
                'HorizontalAlignment', 'center', ...
                'Enable', 'inactive', ...
                'ButtonDownFcn', {@cb_sidebar_click, cat_key});
        else
            % Add Req. / Remove button
            is_on = isfield(dr.enabled, cat_key) && dr.enabled.(cat_key);
            if is_on
                btn_str = 'Remove';
                btn_bg = [0.6 0.2 0.2];
            else
                btn_str = 'Add Req.';
                btn_bg = [0.2 0.5 0.3];
            end
            drfig.sidebar_btns(k) = uicontrol('Parent', sidebar_panel, 'Style', 'pushbutton', ...
                'String', btn_str, ...
                'Units', 'normalized', ...
                'Position', [0.60 y+0.005 0.38 row_h-0.01], ...
                'FontSize', 7, ...
                'ForegroundColor', [1 1 1], ...
                'BackgroundColor', btn_bg, ...
                'Tag', cat_key, ...
                'Callback', {@cb_toggle_requirement, cat_key});
        end
    end

    % --- Right editor panel (70% width) ---
    editor_panel = uipanel('Parent', fig, ...
        'Units', 'normalized', ...
        'Position', [0.29 0.0 0.71 1.0], ...
        'BorderType', 'none');
    drfig.editor_panel = editor_panel;

    % Create one sub-panel per category (only one visible at a time)
    drfig.editor_panels = struct();
    for k = 1:n_cats
        cat_key = categories{k, 1};
        cat_name = categories{k, 2};
        p = uipanel('Parent', editor_panel, ...
            'Units', 'normalized', ...
            'Position', [0.01 0.01 0.98 0.98], ...
            'Title', cat_name, ...
            'FontSize', 11, 'FontWeight', 'bold', ...
            'Visible', 'off');
        drfig.editor_panels.(cat_key) = p;
    end

    % --- Build editor content for each category ---
    drfig = build_number_windings_panel(drfig, dr);
    drfig = build_magnetizing_inductance_panel(drfig, dr);
    drfig = build_turns_ratios_panel(drfig, dr);
    drfig = build_minimum_impedance_panel(drfig, dr);
    drfig = build_wiring_technology_panel(drfig, dr);
    drfig = build_insulation_panel(drfig, dr);
    drfig = build_leakage_inductance_panel(drfig, dr);
    drfig = build_stray_capacitance_panel(drfig, dr);
    drfig = build_isolation_sides_panel(drfig, dr);
    drfig = build_operating_temperature_panel(drfig, dr);
    drfig = build_maximum_weight_panel(drfig, dr);
    drfig = build_maximum_dimensions_panel(drfig, dr);
    drfig = build_terminal_type_panel(drfig, dr);
    drfig = build_topology_panel(drfig, dr);
    drfig = build_market_panel(drfig, dr);

    % Store drfig struct on the design req figure
    guidata(fig, drfig);

    % Show the first category by default
    show_category(fig, 'numberWindings');

end


% ===============================================================
% INITIALIZATION
% ===============================================================

function dr = init_design_req(data)
% Initialize design_req struct from existing topology wizard data.

    dr = struct();
    dr.enabled = struct();

    % --- Required fields: always populated ---

    % Number of windings
    if isfield(data, 'requirements') && isfield(data.requirements, 'n_windings') && data.requirements.n_windings > 0
        dr.numberWindings = data.requirements.n_windings;
    elseif isfield(data, 'n_outputs')
        dr.numberWindings = data.n_outputs + 1;  % primary + secondaries
    else
        dr.numberWindings = 2;
    end

    % Magnetizing inductance
    if isfield(data, 'requirements') && isfield(data.requirements, 'Lm_uH') && data.requirements.Lm_uH > 0
        lm_h = data.requirements.Lm_uH * 1e-6;
        dr.magnetizingInductance = struct('minimum', [], 'nominal', lm_h, 'maximum', []);
    else
        dr.magnetizingInductance = struct('minimum', [], 'nominal', 146e-6, 'maximum', []);
    end

    % Turns ratios (per secondary)
    n_sec = max(1, dr.numberWindings - 1);
    dr.turnsRatios = {};
    if isfield(data, 'requirements') && isfield(data.requirements, 'turns_ratios') && ~isempty(data.requirements.turns_ratios)
        tr_arr = data.requirements.turns_ratios;
        for k = 1:min(numel(tr_arr), n_sec)
            dr.turnsRatios{k} = struct('minimum', [], 'nominal', tr_arr(k), 'maximum', []);
        end
        % Pad remaining
        for k = numel(dr.turnsRatios)+1:n_sec
            dr.turnsRatios{k} = struct('minimum', [], 'nominal', 1.0, 'maximum', []);
        end
    elseif isfield(data, 'requirements') && isfield(data.requirements, 'turns_ratio') && data.requirements.turns_ratio > 0
        for k = 1:n_sec
            dr.turnsRatios{k} = struct('minimum', [], 'nominal', data.requirements.turns_ratio, 'maximum', []);
        end
    else
        for k = 1:n_sec
            dr.turnsRatios{k} = struct('minimum', [], 'nominal', 1.0, 'maximum', []);
        end
    end

    % --- Optional fields: default enabled states ---

    % Insulation: default ON
    dr.enabled.insulation = true;
    dr.insulation = struct();
    if isfield(data, 'insulation')
        ins = data.insulation;
        dr.insulation.altitude = struct('maximum', 2000);
        if isfield(ins, 'altitude_max') && ~isempty(ins.altitude_max)
            dr.insulation.altitude.maximum = ins.altitude_max;
        end
        dr.insulation.mainSupplyVoltage = struct('maximum', 400);
        if isfield(data, 'converter') && isfield(data.converter, 'vin_max')
            dr.insulation.mainSupplyVoltage.maximum = data.converter.vin_max;
        end
        if isfield(ins, 'cti')
            dr.insulation.cti = ins.cti;
        else
            dr.insulation.cti = 'Group II';
        end
        if isfield(ins, 'class')
            dr.insulation.insulationType = ins.class;
        else
            dr.insulation.insulationType = 'Basic';
        end
        if isfield(ins, 'overvoltage_cat')
            dr.insulation.overvoltageCategory = sprintf('OVC-%s', ins.overvoltage_cat);
        else
            dr.insulation.overvoltageCategory = 'OVC-III';
        end
        if isfield(ins, 'pollution_degree')
            dr.insulation.pollutionDegree = sprintf('P%d', ins.pollution_degree);
        else
            dr.insulation.pollutionDegree = 'P2';
        end
        if isfield(ins, 'standard')
            if ischar(ins.standard)
                dr.insulation.standards = {ins.standard};
            else
                dr.insulation.standards = ins.standard;
            end
        else
            dr.insulation.standards = {'IEC 60664-1'};
        end
    else
        dr.insulation.altitude = struct('maximum', 2000);
        dr.insulation.mainSupplyVoltage = struct('maximum', 400);
        dr.insulation.cti = 'Group II';
        dr.insulation.insulationType = 'Basic';
        dr.insulation.overvoltageCategory = 'OVC-III';
        dr.insulation.pollutionDegree = 'P2';
        dr.insulation.standards = {'IEC 60664-1'};
    end

    % All other optional categories: default OFF
    dr.enabled.minimumImpedance = false;
    dr.enabled.wiringTechnology = false;
    dr.enabled.leakageInductance = false;
    dr.enabled.strayCapacitance = false;
    dr.enabled.isolationSides = false;
    dr.enabled.operatingTemperature = false;
    dr.enabled.maximumWeight = false;
    dr.enabled.maximumDimensions = false;
    dr.enabled.terminalType = false;
    dr.enabled.topology = false;
    dr.enabled.market = false;

    % Pre-populate topology if available
    if isfield(data, 'topology_display') && ~isempty(data.topology_display)
        dr.topology = data.topology_display;
        dr.enabled.topology = true;
    else
        dr.topology = '';
    end

    % Default values for optional categories (set when enabled)
    dr.wiringTechnology = 'Wound';
    dr.operatingTemperature = struct('maximum', 85);
    dr.maximumWeight = [];
    dr.maximumDimensions = struct('width', [], 'height', [], 'depth', []);
    dr.leakageInductance = {};
    dr.strayCapacitance = {};
    dr.minimumImpedance = {};
    dr.isolationSides = {};
    dr.terminalType = {};
    dr.market = '';

end


% ===============================================================
% CATEGORY SHOW / TOGGLE
% ===============================================================

function show_category(fig, category_key)
% Hide all editor panels, show the one for category_key.
% Highlight the selected sidebar row.

    drfig = guidata(fig);
    cats = drfig.categories;
    n = drfig.n_cats;

    sidebar_bg = [0.14 0.14 0.22];
    highlight_bg = [0.22 0.22 0.35];

    for k = 1:n
        cat_key = cats{k, 1};
        % Hide all editor panels
        set(drfig.editor_panels.(cat_key), 'Visible', 'off');
        % Reset sidebar row background
        set(drfig.sidebar_rows(k), 'BackgroundColor', sidebar_bg);
        set(drfig.sidebar_labels(k), 'BackgroundColor', sidebar_bg);
        % Also reset the Required label background for required items
        if cats{k, 3}
            set(drfig.sidebar_btns(k), 'BackgroundColor', sidebar_bg);
        end
    end

    % Show selected panel
    if isfield(drfig.editor_panels, category_key)
        set(drfig.editor_panels.(category_key), 'Visible', 'on');
    end

    % Highlight selected row
    for k = 1:n
        if strcmp(cats{k, 1}, category_key)
            set(drfig.sidebar_rows(k), 'BackgroundColor', highlight_bg);
            set(drfig.sidebar_labels(k), 'BackgroundColor', highlight_bg);
            if cats{k, 3}
                set(drfig.sidebar_btns(k), 'BackgroundColor', highlight_bg);
            end
            break;
        end
    end

    drfig.selected_category = category_key;
    guidata(fig, drfig);
end


function cb_sidebar_click(src, ~, category_key)
% Callback when a sidebar row label or background is clicked.
    fig = get(src, 'Parent');
    % Walk up to the figure
    while ~strcmp(get(fig, 'Type'), 'figure')
        fig = get(fig, 'Parent');
    end
    show_category(fig, category_key);
end


function cb_toggle_requirement(src, ~, category_key)
% Toggle enabled state of an optional requirement.
    fig = get(src, 'Parent');
    while ~strcmp(get(fig, 'Type'), 'figure')
        fig = get(fig, 'Parent');
    end
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);
    dr = data.design_req;

    is_on = isfield(dr.enabled, category_key) && dr.enabled.(category_key);

    if is_on
        % Disable: clear values
        dr.enabled.(category_key) = false;
        set(src, 'String', 'Add Req.', 'BackgroundColor', [0.2 0.5 0.3]);
        dr = clear_category_values(dr, category_key);
    else
        % Enable: set defaults
        dr.enabled.(category_key) = true;
        set(src, 'String', 'Remove', 'BackgroundColor', [0.6 0.2 0.2]);
        dr = set_category_defaults(dr, data, category_key);
    end

    data.design_req = dr;
    guidata(main_fig, data);

    % Show that category editor
    show_category(fig, category_key);

    % Refresh the editor panel content if needed
    refresh_editor_panel(fig, category_key);
end


function dr = clear_category_values(dr, category_key)
% Clear values for a disabled category.
    switch category_key
        case 'minimumImpedance'
            dr.minimumImpedance = {};
        case 'wiringTechnology'
            dr.wiringTechnology = 'Wound';
        case 'insulation'
            % Keep struct but mark disabled
        case 'leakageInductance'
            dr.leakageInductance = {};
        case 'strayCapacitance'
            dr.strayCapacitance = {};
        case 'isolationSides'
            dr.isolationSides = {};
        case 'operatingTemperature'
            dr.operatingTemperature = struct('maximum', []);
        case 'maximumWeight'
            dr.maximumWeight = [];
        case 'maximumDimensions'
            dr.maximumDimensions = struct('width', [], 'height', [], 'depth', []);
        case 'terminalType'
            dr.terminalType = {};
        case 'topology'
            dr.topology = '';
        case 'market'
            dr.market = '';
    end
end


function dr = set_category_defaults(dr, data, category_key)
% Set default values when enabling an optional category.
    n_sec = max(1, dr.numberWindings - 1);
    n_wind = dr.numberWindings;
    switch category_key
        case 'minimumImpedance'
            dr.minimumImpedance = {struct('frequency', 100000, 'impedance', struct('magnitude', 1000))};
        case 'wiringTechnology'
            dr.wiringTechnology = 'Wound';
        case 'insulation'
            dr.insulation.altitude = struct('maximum', 2000);
            dr.insulation.mainSupplyVoltage = struct('maximum', 400);
            dr.insulation.cti = 'Group II';
            dr.insulation.insulationType = 'Basic';
            dr.insulation.overvoltageCategory = 'OVC-III';
            dr.insulation.pollutionDegree = 'P2';
            dr.insulation.standards = {'IEC 60664-1'};
        case 'leakageInductance'
            dr.leakageInductance = {};
            for k = 1:n_sec
                dr.leakageInductance{k} = struct('maximum', 3e-6);
            end
        case 'strayCapacitance'
            dr.strayCapacitance = {};
            for k = 1:n_sec
                dr.strayCapacitance{k} = struct('maximum', 50e-12);
            end
        case 'isolationSides'
            dr.isolationSides = {};
            sides = {'Primary', 'Secondary', 'Tertiary', 'Quaternary'};
            for k = 1:n_wind
                if k <= numel(sides)
                    dr.isolationSides{k} = sides{k};
                else
                    dr.isolationSides{k} = 'Secondary';
                end
            end
        case 'operatingTemperature'
            dr.operatingTemperature = struct('maximum', 85);
        case 'maximumWeight'
            dr.maximumWeight = 0.3;  % 300 g = 0.3 kg
        case 'maximumDimensions'
            dr.maximumDimensions = struct('width', 0.05, 'height', 0.05, 'depth', 0.05);
        case 'terminalType'
            dr.terminalType = {};
            for k = 1:n_wind
                dr.terminalType{k} = 'Pin/Through-hole';
            end
        case 'topology'
            if isfield(data, 'topology_display') && ~isempty(data.topology_display)
                dr.topology = data.topology_display;
            else
                dr.topology = 'Two Switch Forward Converter';
            end
        case 'market'
            dr.market = 'Industrial';
    end
end


function refresh_editor_panel(fig, category_key)
% Refresh editor panel content after enable/disable toggle.
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);
    dr = data.design_req;

    switch category_key
        case 'leakageInductance'
            drfig = build_leakage_inductance_panel(drfig, dr);
        case 'strayCapacitance'
            drfig = build_stray_capacitance_panel(drfig, dr);
        case 'isolationSides'
            drfig = build_isolation_sides_panel(drfig, dr);
        case 'terminalType'
            drfig = build_terminal_type_panel(drfig, dr);
        case 'minimumImpedance'
            drfig = build_minimum_impedance_panel(drfig, dr);
        case 'insulation'
            drfig = build_insulation_panel(drfig, dr);
        case 'turnsRatios'
            drfig = build_turns_ratios_panel(drfig, dr);
        case 'operatingTemperature'
            drfig = build_operating_temperature_panel(drfig, dr);
        case 'maximumWeight'
            drfig = build_maximum_weight_panel(drfig, dr);
        case 'maximumDimensions'
            drfig = build_maximum_dimensions_panel(drfig, dr);
        case 'wiringTechnology'
            drfig = build_wiring_technology_panel(drfig, dr);
        case 'topology'
            drfig = build_topology_panel(drfig, dr);
        case 'market'
            drfig = build_market_panel(drfig, dr);
    end
    guidata(fig, drfig);
end


% ===============================================================
% EDITOR PANEL BUILDERS
% ===============================================================

% --- 1. Number of Windings ---
function drfig = build_number_windings_panel(drfig, dr)
    p = drfig.editor_panels.numberWindings;
    delete(get(p, 'Children'));

    val = dr.numberWindings;

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Number of Windings (Primary + Secondaries):', ...
        'Units', 'normalized', 'Position', [0.05 0.80 0.55 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    opts = {};
    for k = 1:12
        opts{k} = num2str(k);
    end
    drfig.edit_numberWindings = uicontrol('Parent', p, 'Style', 'popupmenu', ...
        'String', opts, ...
        'Units', 'normalized', 'Position', [0.62 0.80 0.15 0.06], ...
        'Value', min(max(val, 1), 12), ...
        'FontSize', 10, ...
        'Callback', @cb_number_windings);

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'This sets the total number of windings (1 primary + N-1 secondaries). Auto-set from topology.', ...
        'Units', 'normalized', 'Position', [0.05 0.65 0.90 0.10], ...
        'FontSize', 9, 'ForegroundColor', [0.4 0.4 0.4], ...
        'HorizontalAlignment', 'left');
end

function cb_number_windings(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    val = get(src, 'Value');
    data.design_req.numberWindings = val;

    % Resize turns ratios array
    n_sec = max(1, val - 1);
    old_tr = data.design_req.turnsRatios;
    new_tr = {};
    for k = 1:n_sec
        if k <= numel(old_tr)
            new_tr{k} = old_tr{k};
        else
            new_tr{k} = struct('minimum', [], 'nominal', 1.0, 'maximum', []);
        end
    end
    data.design_req.turnsRatios = new_tr;

    % Resize leakage, stray, isolation, terminal arrays
    data.design_req = resize_per_winding_arrays(data.design_req, val, n_sec);

    guidata(main_fig, data);

    % Rebuild dependent panels
    dr = data.design_req;
    drfig = build_turns_ratios_panel(drfig, dr);
    drfig = build_leakage_inductance_panel(drfig, dr);
    drfig = build_stray_capacitance_panel(drfig, dr);
    drfig = build_isolation_sides_panel(drfig, dr);
    drfig = build_terminal_type_panel(drfig, dr);
    guidata(fig, drfig);
end

function dr = resize_per_winding_arrays(dr, n_wind, n_sec)
% Resize arrays that depend on number of windings or secondaries.

    % Leakage inductance (per secondary)
    if isfield(dr.enabled, 'leakageInductance') && dr.enabled.leakageInductance
        old = dr.leakageInductance;
        dr.leakageInductance = {};
        for k = 1:n_sec
            if k <= numel(old)
                dr.leakageInductance{k} = old{k};
            else
                dr.leakageInductance{k} = struct('maximum', 3e-6);
            end
        end
    end

    % Stray capacitance (per secondary)
    if isfield(dr.enabled, 'strayCapacitance') && dr.enabled.strayCapacitance
        old = dr.strayCapacitance;
        dr.strayCapacitance = {};
        for k = 1:n_sec
            if k <= numel(old)
                dr.strayCapacitance{k} = old{k};
            else
                dr.strayCapacitance{k} = struct('maximum', 50e-12);
            end
        end
    end

    % Isolation sides (per winding)
    if isfield(dr.enabled, 'isolationSides') && dr.enabled.isolationSides
        old = dr.isolationSides;
        sides = {'Primary', 'Secondary', 'Tertiary', 'Quaternary'};
        dr.isolationSides = {};
        for k = 1:n_wind
            if k <= numel(old)
                dr.isolationSides{k} = old{k};
            elseif k <= numel(sides)
                dr.isolationSides{k} = sides{k};
            else
                dr.isolationSides{k} = 'Secondary';
            end
        end
    end

    % Terminal type (per winding)
    if isfield(dr.enabled, 'terminalType') && dr.enabled.terminalType
        old = dr.terminalType;
        dr.terminalType = {};
        for k = 1:n_wind
            if k <= numel(old)
                dr.terminalType{k} = old{k};
            else
                dr.terminalType{k} = 'Pin/Through-hole';
            end
        end
    end
end


% --- 2. Magnetizing Inductance ---
function drfig = build_magnetizing_inductance_panel(drfig, dr)
    p = drfig.editor_panels.magnetizingInductance;
    delete(get(p, 'Children'));

    mi = dr.magnetizingInductance;
    unit_options = {'H', 'mH', 'uH', 'nH'};
    unit_multipliers = [1, 1e-3, 1e-6, 1e-9];
    default_unit_idx = 3; % uH

    [drfig.mi_edits, drfig.mi_unit_popup] = build_dim_tolerance_controls( ...
        p, 'magnetizingInductance', mi, unit_options, unit_multipliers, default_unit_idx, ...
        0.80, @cb_magnetizing_inductance);
end

function cb_magnetizing_inductance(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    unit_options = {'H', 'mH', 'uH', 'nH'};
    unit_multipliers = [1, 1e-3, 1e-6, 1e-9];

    vals = read_dim_tolerance_controls(drfig.mi_edits, drfig.mi_unit_popup, unit_multipliers);
    data.design_req.magnetizingInductance = vals;
    guidata(main_fig, data);
end


% --- 3. Turns Ratios ---
function drfig = build_turns_ratios_panel(drfig, dr)
    p = drfig.editor_panels.turnsRatios;
    delete(get(p, 'Children'));

    n_sec = numel(dr.turnsRatios);
    if n_sec < 1
        n_sec = 1;
        dr.turnsRatios = {struct('minimum', [], 'nominal', 1.0, 'maximum', [])};
    end

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Turns Ratios (Np/Ns per secondary)', ...
        'Units', 'normalized', 'Position', [0.05 0.90 0.90 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    % Column headers
    y_header = 0.83;
    uicontrol('Parent', p, 'Style', 'text', 'String', '', ...
        'Units', 'normalized', 'Position', [0.05 y_header 0.15 0.05], ...
        'FontSize', 8, 'HorizontalAlignment', 'left');
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Minimum', ...
        'Units', 'normalized', 'Position', [0.22 y_header 0.20 0.05], ...
        'FontSize', 8, 'HorizontalAlignment', 'center');
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Nominal', ...
        'Units', 'normalized', 'Position', [0.44 y_header 0.20 0.05], ...
        'FontSize', 8, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Maximum', ...
        'Units', 'normalized', 'Position', [0.66 y_header 0.20 0.05], ...
        'FontSize', 8, 'HorizontalAlignment', 'center');

    dy = 0.07;
    drfig.tr_edits = {};

    for k = 1:n_sec
        y = 0.76 - (k-1) * dy;
        tr = dr.turnsRatios{k};

        label_str = sprintf('Secondary %d:', k);
        uicontrol('Parent', p, 'Style', 'text', 'String', label_str, ...
            'Units', 'normalized', 'Position', [0.05 y 0.16 0.05], ...
            'FontSize', 9, 'HorizontalAlignment', 'left');

        min_str = val_to_str(tr.minimum);
        nom_str = val_to_str(tr.nominal);
        max_str = val_to_str(tr.maximum);

        e_min = uicontrol('Parent', p, 'Style', 'edit', 'String', min_str, ...
            'Units', 'normalized', 'Position', [0.22 y 0.18 0.05], ...
            'FontSize', 9, 'Tag', sprintf('tr_min_%d', k), ...
            'Callback', {@cb_turns_ratio, k, 'minimum'});
        e_nom = uicontrol('Parent', p, 'Style', 'edit', 'String', nom_str, ...
            'Units', 'normalized', 'Position', [0.44 y 0.18 0.05], ...
            'FontSize', 9, 'Tag', sprintf('tr_nom_%d', k), ...
            'Callback', {@cb_turns_ratio, k, 'nominal'});
        e_max = uicontrol('Parent', p, 'Style', 'edit', 'String', max_str, ...
            'Units', 'normalized', 'Position', [0.66 y 0.18 0.05], ...
            'FontSize', 9, 'Tag', sprintf('tr_max_%d', k), ...
            'Callback', {@cb_turns_ratio, k, 'maximum'});

        drfig.tr_edits{k} = struct('min', e_min, 'nom', e_nom, 'max', e_max);
    end

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Turns ratios are dimensionless (Np/Ns). Auto-set from topology computation.', ...
        'Units', 'normalized', 'Position', [0.05 0.02 0.90 0.06], ...
        'FontSize', 8, 'ForegroundColor', [0.4 0.4 0.4], ...
        'HorizontalAlignment', 'left');
end

function cb_turns_ratio(src, ~, sec_idx, field)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    val = str2double(get(src, 'String'));
    if isnan(val)
        val = [];
    end

    if sec_idx <= numel(data.design_req.turnsRatios)
        data.design_req.turnsRatios{sec_idx}.(field) = val;
    end
    guidata(main_fig, data);
end


% --- 4. Minimum Impedance ---
function drfig = build_minimum_impedance_panel(drfig, dr)
    p = drfig.editor_panels.minimumImpedance;
    delete(get(p, 'Children'));

    imp_data = dr.minimumImpedance;
    if isempty(imp_data)
        imp_data = {};
    end
    n_rows = numel(imp_data);

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Minimum Impedance Requirement (Frequency + Magnitude Pairs)', ...
        'Units', 'normalized', 'Position', [0.05 0.90 0.90 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    % Column headers
    y_header = 0.83;
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Frequency (Hz)', ...
        'Units', 'normalized', 'Position', [0.05 y_header 0.30 0.05], ...
        'FontSize', 9, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Impedance (Ohms)', ...
        'Units', 'normalized', 'Position', [0.38 y_header 0.30 0.05], ...
        'FontSize', 9, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');

    dy = 0.07;
    drfig.imp_edits = {};

    for k = 1:n_rows
        y = 0.76 - (k-1) * dy;
        row = imp_data{k};
        freq_val = 100000;
        mag_val = 1000;
        if isfield(row, 'frequency')
            freq_val = row.frequency;
        end
        if isfield(row, 'impedance') && isfield(row.impedance, 'magnitude')
            mag_val = row.impedance.magnitude;
        end

        e_freq = uicontrol('Parent', p, 'Style', 'edit', 'String', num2str(freq_val), ...
            'Units', 'normalized', 'Position', [0.05 y 0.28 0.05], ...
            'FontSize', 9, 'Callback', {@cb_impedance_row, k, 'frequency'});
        e_mag = uicontrol('Parent', p, 'Style', 'edit', 'String', num2str(mag_val), ...
            'Units', 'normalized', 'Position', [0.38 y 0.28 0.05], ...
            'FontSize', 9, 'Callback', {@cb_impedance_row, k, 'magnitude'});

        % Remove button for this row
        uicontrol('Parent', p, 'Style', 'pushbutton', 'String', '-', ...
            'Units', 'normalized', 'Position', [0.70 y 0.06 0.05], ...
            'FontSize', 10, 'FontWeight', 'bold', ...
            'BackgroundColor', [0.7 0.2 0.2], 'ForegroundColor', [1 1 1], ...
            'Callback', {@cb_impedance_remove, k});

        drfig.imp_edits{k} = struct('freq', e_freq, 'mag', e_mag);
    end

    % Add row button
    add_y = 0.76 - n_rows * dy;
    if add_y < 0.05
        add_y = 0.05;
    end
    uicontrol('Parent', p, 'Style', 'pushbutton', 'String', '+ Add Row', ...
        'Units', 'normalized', 'Position', [0.05 add_y 0.25 0.05], ...
        'FontSize', 9, 'FontWeight', 'bold', ...
        'BackgroundColor', [0.2 0.5 0.3], 'ForegroundColor', [1 1 1], ...
        'Callback', @cb_impedance_add);
end

function cb_impedance_row(src, ~, row_idx, field)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    val = str2double(get(src, 'String'));
    if isnan(val) || val <= 0
        return;
    end

    if row_idx <= numel(data.design_req.minimumImpedance)
        row = data.design_req.minimumImpedance{row_idx};
        if strcmp(field, 'frequency')
            row.frequency = val;
        elseif strcmp(field, 'magnitude')
            if ~isfield(row, 'impedance')
                row.impedance = struct();
            end
            row.impedance.magnitude = val;
        end
        data.design_req.minimumImpedance{row_idx} = row;
        guidata(main_fig, data);
    end
end

function cb_impedance_add(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    new_row = struct('frequency', 100000, 'impedance', struct('magnitude', 1000));
    data.design_req.minimumImpedance{end+1} = new_row;
    guidata(main_fig, data);

    drfig = build_minimum_impedance_panel(drfig, data.design_req);
    guidata(fig, drfig);
end

function cb_impedance_remove(src, ~, row_idx)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    if row_idx <= numel(data.design_req.minimumImpedance)
        data.design_req.minimumImpedance(row_idx) = [];
        guidata(main_fig, data);
    end

    drfig = build_minimum_impedance_panel(drfig, data.design_req);
    guidata(fig, drfig);
end


% --- 5. Wiring Technology ---
function drfig = build_wiring_technology_panel(drfig, dr)
    p = drfig.editor_panels.wiringTechnology;
    delete(get(p, 'Children'));

    cur_val = dr.wiringTechnology;
    is_wound = strcmp(cur_val, 'Wound');

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Wiring Technology:', ...
        'Units', 'normalized', 'Position', [0.05 0.80 0.30 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    drfig.radio_wound = uicontrol('Parent', p, 'Style', 'radiobutton', ...
        'String', 'Wound', ...
        'Units', 'normalized', 'Position', [0.38 0.80 0.20 0.06], ...
        'FontSize', 10, 'Value', is_wound, ...
        'Callback', @cb_wiring_tech);

    drfig.radio_planar = uicontrol('Parent', p, 'Style', 'radiobutton', ...
        'String', 'Planar', ...
        'Units', 'normalized', 'Position', [0.60 0.80 0.20 0.06], ...
        'FontSize', 10, 'Value', ~is_wound, ...
        'Callback', @cb_wiring_tech);
end

function cb_wiring_tech(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    str = get(src, 'String');
    if strcmp(str, 'Wound')
        data.design_req.wiringTechnology = 'Wound';
        set(drfig.radio_wound, 'Value', 1);
        set(drfig.radio_planar, 'Value', 0);
    else
        data.design_req.wiringTechnology = 'Planar';
        set(drfig.radio_wound, 'Value', 0);
        set(drfig.radio_planar, 'Value', 1);
    end
    guidata(main_fig, data);
end


% --- 6. Insulation ---
function drfig = build_insulation_panel(drfig, dr)
    p = drfig.editor_panels.insulation;
    delete(get(p, 'Children'));

    ins = dr.insulation;

    % --- Row 1: Altitude and Main Supply Voltage ---
    y1 = 0.82;
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Altitude (max):', ...
        'Units', 'normalized', 'Position', [0.03 y1 0.18 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    alt_km = 2;
    if isfield(ins, 'altitude') && isfield(ins.altitude, 'maximum') && ~isempty(ins.altitude.maximum)
        alt_km = ins.altitude.maximum / 1000;  % m to km
    end
    drfig.edit_ins_altitude = uicontrol('Parent', p, 'Style', 'edit', ...
        'String', num2str(alt_km), ...
        'Units', 'normalized', 'Position', [0.22 y1 0.12 0.06], ...
        'FontSize', 9, 'Callback', @cb_insulation_altitude);
    uicontrol('Parent', p, 'Style', 'text', 'String', 'km', ...
        'Units', 'normalized', 'Position', [0.35 y1 0.05 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    uicontrol('Parent', p, 'Style', 'text', 'String', 'Main Supply Voltage (max):', ...
        'Units', 'normalized', 'Position', [0.45 y1 0.28 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    msv = 400;
    if isfield(ins, 'mainSupplyVoltage') && isfield(ins.mainSupplyVoltage, 'maximum') && ~isempty(ins.mainSupplyVoltage.maximum)
        msv = ins.mainSupplyVoltage.maximum;
    end
    drfig.edit_ins_msv = uicontrol('Parent', p, 'Style', 'edit', ...
        'String', num2str(msv), ...
        'Units', 'normalized', 'Position', [0.74 y1 0.12 0.06], ...
        'FontSize', 9, 'Callback', @cb_insulation_msv);
    uicontrol('Parent', p, 'Style', 'text', 'String', 'V', ...
        'Units', 'normalized', 'Position', [0.87 y1 0.05 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    % --- Row 2: CTI and Insulation Type ---
    y2 = 0.68;
    uicontrol('Parent', p, 'Style', 'text', 'String', 'CTI:', ...
        'Units', 'normalized', 'Position', [0.03 y2 0.12 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    cti_options = {'Group I', 'Group II', 'Group IIIA', 'Group IIIB'};
    cti_val = 2;
    if isfield(ins, 'cti')
        idx = find_string_index(cti_options, ins.cti);
        if idx > 0, cti_val = idx; end
    end
    drfig.pop_ins_cti = uicontrol('Parent', p, 'Style', 'popupmenu', ...
        'String', cti_options, ...
        'Units', 'normalized', 'Position', [0.16 y2 0.25 0.06], ...
        'Value', cti_val, 'FontSize', 9, ...
        'Callback', @cb_insulation_cti);

    uicontrol('Parent', p, 'Style', 'text', 'String', 'Insulation Type:', ...
        'Units', 'normalized', 'Position', [0.45 y2 0.18 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    type_options = {'Functional', 'Basic', 'Supplementary', 'Reinforced', 'Double'};
    type_val = 2;
    if isfield(ins, 'insulationType')
        idx = find_string_index(type_options, ins.insulationType);
        if idx > 0, type_val = idx; end
    end
    drfig.pop_ins_type = uicontrol('Parent', p, 'Style', 'popupmenu', ...
        'String', type_options, ...
        'Units', 'normalized', 'Position', [0.64 y2 0.28 0.06], ...
        'Value', type_val, 'FontSize', 9, ...
        'Callback', @cb_insulation_type);

    % --- Row 3: Overvoltage Category and Pollution Degree ---
    y3 = 0.54;
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Overvoltage Category:', ...
        'Units', 'normalized', 'Position', [0.03 y3 0.24 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    ovc_options = {'OVC-I', 'OVC-II', 'OVC-III', 'OVC-IV'};
    ovc_val = 3;
    if isfield(ins, 'overvoltageCategory')
        idx = find_string_index(ovc_options, ins.overvoltageCategory);
        if idx > 0, ovc_val = idx; end
    end
    drfig.pop_ins_ovc = uicontrol('Parent', p, 'Style', 'popupmenu', ...
        'String', ovc_options, ...
        'Units', 'normalized', 'Position', [0.28 y3 0.16 0.06], ...
        'Value', ovc_val, 'FontSize', 9, ...
        'Callback', @cb_insulation_ovc);

    uicontrol('Parent', p, 'Style', 'text', 'String', 'Pollution Degree:', ...
        'Units', 'normalized', 'Position', [0.50 y3 0.20 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    pd_options = {'P1', 'P2', 'P3'};
    pd_val = 2;
    if isfield(ins, 'pollutionDegree')
        idx = find_string_index(pd_options, ins.pollutionDegree);
        if idx > 0, pd_val = idx; end
    end
    drfig.pop_ins_pd = uicontrol('Parent', p, 'Style', 'popupmenu', ...
        'String', pd_options, ...
        'Units', 'normalized', 'Position', [0.71 y3 0.16 0.06], ...
        'Value', pd_val, 'FontSize', 9, ...
        'Callback', @cb_insulation_pd);

    % --- Row 4: Standards checkboxes ---
    y4 = 0.40;
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Standards:', ...
        'Units', 'normalized', 'Position', [0.03 y4 0.14 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left', 'FontWeight', 'bold');

    std_names = {'IEC 60335-1', 'IEC 60664-1', 'IEC 61558-1', 'IEC 62368-1'};
    active_stds = {};
    if isfield(ins, 'standards')
        active_stds = ins.standards;
    end

    drfig.chk_standards = zeros(1, 4);
    x_pos = [0.18 0.40 0.62 0.82];
    for k = 1:4
        is_checked = false;
        for s = 1:numel(active_stds)
            if strcmp(active_stds{s}, std_names{k})
                is_checked = true;
                break;
            end
        end
        drfig.chk_standards(k) = uicontrol('Parent', p, 'Style', 'checkbox', ...
            'String', std_names{k}, ...
            'Units', 'normalized', 'Position', [x_pos(k) y4 0.20 0.06], ...
            'Value', is_checked, 'FontSize', 8, ...
            'Callback', @cb_insulation_standards);
    end
end

function cb_insulation_altitude(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    val_km = str2double(get(src, 'String'));
    if ~isnan(val_km) && val_km >= 0
        data.design_req.insulation.altitude.maximum = val_km * 1000;  % km to m
    end
    guidata(main_fig, data);
end

function cb_insulation_msv(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    val = str2double(get(src, 'String'));
    if ~isnan(val) && val >= 0
        data.design_req.insulation.mainSupplyVoltage.maximum = val;
    end
    guidata(main_fig, data);
end

function cb_insulation_cti(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    opts = get(src, 'String');
    idx = get(src, 'Value');
    data.design_req.insulation.cti = opts{idx};
    guidata(main_fig, data);
end

function cb_insulation_type(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    opts = get(src, 'String');
    idx = get(src, 'Value');
    data.design_req.insulation.insulationType = opts{idx};
    guidata(main_fig, data);
end

function cb_insulation_ovc(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    opts = get(src, 'String');
    idx = get(src, 'Value');
    data.design_req.insulation.overvoltageCategory = opts{idx};
    guidata(main_fig, data);
end

function cb_insulation_pd(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    opts = get(src, 'String');
    idx = get(src, 'Value');
    data.design_req.insulation.pollutionDegree = opts{idx};
    guidata(main_fig, data);
end

function cb_insulation_standards(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    std_names = {'IEC 60335-1', 'IEC 60664-1', 'IEC 61558-1', 'IEC 62368-1'};
    selected = {};
    for k = 1:4
        if get(drfig.chk_standards(k), 'Value')
            selected{end+1} = std_names{k};
        end
    end
    data.design_req.insulation.standards = selected;
    guidata(main_fig, data);
end


% --- 7. Leakage Inductance ---
function drfig = build_leakage_inductance_panel(drfig, dr)
    p = drfig.editor_panels.leakageInductance;
    delete(get(p, 'Children'));

    n_sec = max(1, dr.numberWindings - 1);
    leak = dr.leakageInductance;

    unit_options = {'H', 'mH', 'uH', 'nH'};
    unit_multipliers = [1, 1e-3, 1e-6, 1e-9];
    default_unit_idx = 3; % uH

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Leakage Inductance (Maximum per Secondary)', ...
        'Units', 'normalized', 'Position', [0.05 0.90 0.90 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    dy = 0.08;
    drfig.leak_edits = {};
    drfig.leak_units = {};

    for k = 1:n_sec
        y = 0.80 - (k-1) * dy;
        label_str = sprintf('Secondary %d (max):', k);
        uicontrol('Parent', p, 'Style', 'text', 'String', label_str, ...
            'Units', 'normalized', 'Position', [0.05 y 0.25 0.05], ...
            'FontSize', 9, 'HorizontalAlignment', 'left');

        % Get current value
        max_val = 3e-6;  % default 3 uH
        if k <= numel(leak) && isfield(leak{k}, 'maximum') && ~isempty(leak{k}.maximum)
            max_val = leak{k}.maximum;
        end
        display_val = max_val / unit_multipliers(default_unit_idx);

        e = uicontrol('Parent', p, 'Style', 'edit', 'String', num2str(display_val), ...
            'Units', 'normalized', 'Position', [0.32 y 0.18 0.05], ...
            'FontSize', 9, 'Callback', {@cb_leakage, k});

        u = uicontrol('Parent', p, 'Style', 'popupmenu', 'String', unit_options, ...
            'Units', 'normalized', 'Position', [0.52 y 0.12 0.05], ...
            'Value', default_unit_idx, 'FontSize', 9, ...
            'Callback', {@cb_leakage, k});

        drfig.leak_edits{k} = e;
        drfig.leak_units{k} = u;
    end
end

function cb_leakage(src, ~, sec_idx)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    unit_multipliers = [1, 1e-3, 1e-6, 1e-9];

    if sec_idx <= numel(drfig.leak_edits) && sec_idx <= numel(drfig.leak_units)
        val_str = get(drfig.leak_edits{sec_idx}, 'String');
        val = str2double(val_str);
        unit_idx = get(drfig.leak_units{sec_idx}, 'Value');
        mult = unit_multipliers(unit_idx);

        if ~isnan(val) && val >= 0
            si_val = val * mult;
            while sec_idx > numel(data.design_req.leakageInductance)
                data.design_req.leakageInductance{end+1} = struct('maximum', 3e-6);
            end
            data.design_req.leakageInductance{sec_idx} = struct('maximum', si_val);
            guidata(main_fig, data);
        end
    end
end


% --- 8. Stray Capacitance ---
function drfig = build_stray_capacitance_panel(drfig, dr)
    p = drfig.editor_panels.strayCapacitance;
    delete(get(p, 'Children'));

    n_sec = max(1, dr.numberWindings - 1);
    stray = dr.strayCapacitance;

    unit_options = {'F', 'nF', 'pF'};
    unit_multipliers = [1, 1e-9, 1e-12];
    default_unit_idx = 3; % pF

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Stray Capacitance (Maximum per Secondary)', ...
        'Units', 'normalized', 'Position', [0.05 0.90 0.90 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    dy = 0.08;
    drfig.stray_edits = {};
    drfig.stray_units = {};

    for k = 1:n_sec
        y = 0.80 - (k-1) * dy;
        label_str = sprintf('Secondary %d (max):', k);
        uicontrol('Parent', p, 'Style', 'text', 'String', label_str, ...
            'Units', 'normalized', 'Position', [0.05 y 0.25 0.05], ...
            'FontSize', 9, 'HorizontalAlignment', 'left');

        max_val = 50e-12;  % default 50 pF
        if k <= numel(stray) && isfield(stray{k}, 'maximum') && ~isempty(stray{k}.maximum)
            max_val = stray{k}.maximum;
        end
        display_val = max_val / unit_multipliers(default_unit_idx);

        e = uicontrol('Parent', p, 'Style', 'edit', 'String', num2str(display_val), ...
            'Units', 'normalized', 'Position', [0.32 y 0.18 0.05], ...
            'FontSize', 9, 'Callback', {@cb_stray, k});

        u = uicontrol('Parent', p, 'Style', 'popupmenu', 'String', unit_options, ...
            'Units', 'normalized', 'Position', [0.52 y 0.12 0.05], ...
            'Value', default_unit_idx, 'FontSize', 9, ...
            'Callback', {@cb_stray, k});

        drfig.stray_edits{k} = e;
        drfig.stray_units{k} = u;
    end
end

function cb_stray(src, ~, sec_idx)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    unit_multipliers = [1, 1e-9, 1e-12];

    if sec_idx <= numel(drfig.stray_edits) && sec_idx <= numel(drfig.stray_units)
        val_str = get(drfig.stray_edits{sec_idx}, 'String');
        val = str2double(val_str);
        unit_idx = get(drfig.stray_units{sec_idx}, 'Value');
        mult = unit_multipliers(unit_idx);

        if ~isnan(val) && val >= 0
            si_val = val * mult;
            while sec_idx > numel(data.design_req.strayCapacitance)
                data.design_req.strayCapacitance{end+1} = struct('maximum', 50e-12);
            end
            data.design_req.strayCapacitance{sec_idx} = struct('maximum', si_val);
            guidata(main_fig, data);
        end
    end
end


% --- 9. Isolation Sides ---
function drfig = build_isolation_sides_panel(drfig, dr)
    p = drfig.editor_panels.isolationSides;
    delete(get(p, 'Children'));

    n_wind = dr.numberWindings;
    iso = dr.isolationSides;

    side_options = {'Primary', 'Secondary', 'Tertiary', 'Quaternary'};

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Isolation Side Assignment (per Winding)', ...
        'Units', 'normalized', 'Position', [0.05 0.90 0.90 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    dy = 0.08;
    drfig.iso_popups = {};

    for k = 1:n_wind
        y = 0.80 - (k-1) * dy;
        if k == 1
            label_str = 'Winding 1 (Primary):';
        else
            label_str = sprintf('Winding %d (Secondary %d):', k, k-1);
        end
        uicontrol('Parent', p, 'Style', 'text', 'String', label_str, ...
            'Units', 'normalized', 'Position', [0.05 y 0.35 0.05], ...
            'FontSize', 9, 'HorizontalAlignment', 'left');

        cur_side = 'Secondary';
        if k == 1
            cur_side = 'Primary';
        end
        if k <= numel(iso) && ~isempty(iso{k})
            cur_side = iso{k};
        end
        side_idx = find_string_index(side_options, cur_side);
        if side_idx < 1, side_idx = 2; end

        pop = uicontrol('Parent', p, 'Style', 'popupmenu', 'String', side_options, ...
            'Units', 'normalized', 'Position', [0.42 y 0.25 0.05], ...
            'Value', side_idx, 'FontSize', 9, ...
            'Callback', {@cb_isolation_side, k});

        drfig.iso_popups{k} = pop;
    end
end

function cb_isolation_side(src, ~, winding_idx)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    opts = get(src, 'String');
    idx = get(src, 'Value');
    val = opts{idx};

    while winding_idx > numel(data.design_req.isolationSides)
        data.design_req.isolationSides{end+1} = 'Secondary';
    end
    data.design_req.isolationSides{winding_idx} = val;
    guidata(main_fig, data);
end


% --- 10. Operating Temperature ---
function drfig = build_operating_temperature_panel(drfig, dr)
    p = drfig.editor_panels.operatingTemperature;
    delete(get(p, 'Children'));

    ot = dr.operatingTemperature;
    max_val = 85;
    if isfield(ot, 'maximum') && ~isempty(ot.maximum)
        max_val = ot.maximum;
    end

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Maximum Operating Temperature:', ...
        'Units', 'normalized', 'Position', [0.05 0.80 0.40 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    drfig.edit_op_temp = uicontrol('Parent', p, 'Style', 'edit', ...
        'String', num2str(max_val), ...
        'Units', 'normalized', 'Position', [0.46 0.80 0.15 0.06], ...
        'FontSize', 10, 'Callback', @cb_op_temp);

    uicontrol('Parent', p, 'Style', 'text', 'String', 'deg C', ...
        'Units', 'normalized', 'Position', [0.63 0.80 0.10 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Maximum allowed temperature at the magnetic component surface during operation.', ...
        'Units', 'normalized', 'Position', [0.05 0.65 0.90 0.08], ...
        'FontSize', 9, 'ForegroundColor', [0.4 0.4 0.4], ...
        'HorizontalAlignment', 'left');
end

function cb_op_temp(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    val = str2double(get(src, 'String'));
    if ~isnan(val)
        data.design_req.operatingTemperature.maximum = val;
    end
    guidata(main_fig, data);
end


% --- 11. Maximum Weight ---
function drfig = build_maximum_weight_panel(drfig, dr)
    p = drfig.editor_panels.maximumWeight;
    delete(get(p, 'Children'));

    unit_options = {'g', 'kg'};
    unit_multipliers = [1e-3, 1];  % g->kg, kg->kg (SI: kg)
    default_unit_idx = 1;  % grams

    cur_val = dr.maximumWeight;
    display_val = '';
    if ~isempty(cur_val) && isnumeric(cur_val) && cur_val > 0
        display_val = num2str(cur_val / unit_multipliers(default_unit_idx));
    end

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Maximum Weight:', ...
        'Units', 'normalized', 'Position', [0.05 0.80 0.25 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    drfig.edit_max_weight = uicontrol('Parent', p, 'Style', 'edit', ...
        'String', display_val, ...
        'Units', 'normalized', 'Position', [0.32 0.80 0.18 0.06], ...
        'FontSize', 10, 'Callback', @cb_max_weight);

    drfig.pop_weight_unit = uicontrol('Parent', p, 'Style', 'popupmenu', ...
        'String', unit_options, ...
        'Units', 'normalized', 'Position', [0.52 0.80 0.10 0.06], ...
        'Value', default_unit_idx, 'FontSize', 9, ...
        'Callback', @cb_max_weight);
end

function cb_max_weight(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    unit_multipliers = [1e-3, 1];  % g->kg, kg->kg

    val = str2double(get(drfig.edit_max_weight, 'String'));
    unit_idx = get(drfig.pop_weight_unit, 'Value');
    mult = unit_multipliers(unit_idx);

    if ~isnan(val) && val > 0
        data.design_req.maximumWeight = val * mult;
    else
        data.design_req.maximumWeight = [];
    end
    guidata(main_fig, data);
end


% --- 12. Maximum Dimensions ---
function drfig = build_maximum_dimensions_panel(drfig, dr)
    p = drfig.editor_panels.maximumDimensions;
    delete(get(p, 'Children'));

    dims = dr.maximumDimensions;
    mm_mult = 1e-3;  % mm to m

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Maximum Dimensions (mm)', ...
        'Units', 'normalized', 'Position', [0.05 0.88 0.60 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left', 'FontWeight', 'bold');

    y = 0.78;
    dy = 0.09;

    % Width
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Width:', ...
        'Units', 'normalized', 'Position', [0.05 y 0.12 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');
    w_val = '';
    if isfield(dims, 'width') && ~isempty(dims.width)
        w_val = num2str(dims.width / mm_mult);
    end
    drfig.edit_dim_width = uicontrol('Parent', p, 'Style', 'edit', 'String', w_val, ...
        'Units', 'normalized', 'Position', [0.18 y 0.18 0.06], ...
        'FontSize', 9, 'Callback', @cb_dim_width);
    uicontrol('Parent', p, 'Style', 'text', 'String', 'mm', ...
        'Units', 'normalized', 'Position', [0.37 y 0.06 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');
    y = y - dy;

    % Height
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Height:', ...
        'Units', 'normalized', 'Position', [0.05 y 0.12 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');
    h_val = '';
    if isfield(dims, 'height') && ~isempty(dims.height)
        h_val = num2str(dims.height / mm_mult);
    end
    drfig.edit_dim_height = uicontrol('Parent', p, 'Style', 'edit', 'String', h_val, ...
        'Units', 'normalized', 'Position', [0.18 y 0.18 0.06], ...
        'FontSize', 9, 'Callback', @cb_dim_height);
    uicontrol('Parent', p, 'Style', 'text', 'String', 'mm', ...
        'Units', 'normalized', 'Position', [0.37 y 0.06 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');
    y = y - dy;

    % Depth
    uicontrol('Parent', p, 'Style', 'text', 'String', 'Depth:', ...
        'Units', 'normalized', 'Position', [0.05 y 0.12 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');
    d_val = '';
    if isfield(dims, 'depth') && ~isempty(dims.depth)
        d_val = num2str(dims.depth / mm_mult);
    end
    drfig.edit_dim_depth = uicontrol('Parent', p, 'Style', 'edit', 'String', d_val, ...
        'Units', 'normalized', 'Position', [0.18 y 0.18 0.06], ...
        'FontSize', 9, 'Callback', @cb_dim_depth);
    uicontrol('Parent', p, 'Style', 'text', 'String', 'mm', ...
        'Units', 'normalized', 'Position', [0.37 y 0.06 0.06], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');
end

function cb_dim_width(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.design_req.maximumDimensions.width = val * 1e-3;
    else
        data.design_req.maximumDimensions.width = [];
    end
    guidata(main_fig, data);
end

function cb_dim_height(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.design_req.maximumDimensions.height = val * 1e-3;
    else
        data.design_req.maximumDimensions.height = [];
    end
    guidata(main_fig, data);
end

function cb_dim_depth(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.design_req.maximumDimensions.depth = val * 1e-3;
    else
        data.design_req.maximumDimensions.depth = [];
    end
    guidata(main_fig, data);
end


% --- 13. Terminal Type ---
function drfig = build_terminal_type_panel(drfig, dr)
    p = drfig.editor_panels.terminalType;
    delete(get(p, 'Children'));

    n_wind = dr.numberWindings;
    tt = dr.terminalType;

    term_options = {'Pin/Through-hole', 'SMD/Gull Wing', 'SMD/J-Lead', 'Flying Leads', ...
                    'Screw Terminal', 'Solder Lug', 'Tab Terminal', 'Wire Lead'};

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Terminal Type (per Winding)', ...
        'Units', 'normalized', 'Position', [0.05 0.90 0.90 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    dy = 0.08;
    drfig.term_popups = {};

    for k = 1:n_wind
        y = 0.80 - (k-1) * dy;
        if k == 1
            label_str = 'Winding 1 (Primary):';
        else
            label_str = sprintf('Winding %d (Secondary %d):', k, k-1);
        end
        uicontrol('Parent', p, 'Style', 'text', 'String', label_str, ...
            'Units', 'normalized', 'Position', [0.05 y 0.35 0.05], ...
            'FontSize', 9, 'HorizontalAlignment', 'left');

        cur_term = 'Pin/Through-hole';
        if k <= numel(tt) && ~isempty(tt{k})
            cur_term = tt{k};
        end
        term_idx = find_string_index(term_options, cur_term);
        if term_idx < 1, term_idx = 1; end

        pop = uicontrol('Parent', p, 'Style', 'popupmenu', 'String', term_options, ...
            'Units', 'normalized', 'Position', [0.42 y 0.35 0.05], ...
            'Value', term_idx, 'FontSize', 9, ...
            'Callback', {@cb_terminal_type, k});

        drfig.term_popups{k} = pop;
    end
end

function cb_terminal_type(src, ~, winding_idx)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    opts = get(src, 'String');
    idx = get(src, 'Value');
    val = opts{idx};

    while winding_idx > numel(data.design_req.terminalType)
        data.design_req.terminalType{end+1} = 'Pin/Through-hole';
    end
    data.design_req.terminalType{winding_idx} = val;
    guidata(main_fig, data);
end


% --- 14. Topology ---
function drfig = build_topology_panel(drfig, dr)
    p = drfig.editor_panels.topology;
    delete(get(p, 'Children'));

    topo_options = { ...
        'Two Switch Forward Converter', ...
        'Single Switch Forward Converter', ...
        'Active Clamp Forward Converter', ...
        'Flyback Converter', ...
        'Push Pull Converter', ...
        'Full Bridge Converter', ...
        'Half Bridge Converter', ...
        'Buck Converter', ...
        'Boost Converter', ...
        'Isolated Buck Converter', ...
        'Isolated Buck Boost Converter', ...
        'Forward Converter', ...
        'Phase Shifted Full Bridge Converter', ...
        'LLC Resonant Converter', ...
        'Dual Active Bridge Converter', ...
        'SEPIC Converter', ...
        'Cuk Converter', ...
        'Zeta Converter', ...
        'Interleaved Boost Converter', ...
        'Current Fed Full Bridge Converter', ...
        'Current Fed Half Bridge Converter' ...
    };

    cur_topo = dr.topology;
    topo_idx = 1;
    if ~isempty(cur_topo)
        idx = find_string_index(topo_options, cur_topo);
        if idx > 0, topo_idx = idx; end
    end

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Converter Topology:', ...
        'Units', 'normalized', 'Position', [0.05 0.80 0.25 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    drfig.pop_topology = uicontrol('Parent', p, 'Style', 'popupmenu', ...
        'String', topo_options, ...
        'Units', 'normalized', 'Position', [0.32 0.80 0.55 0.06], ...
        'Value', topo_idx, 'FontSize', 9, ...
        'Callback', @cb_topology_dr);

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Auto-set from the topology wizard selection. Select manually to override.', ...
        'Units', 'normalized', 'Position', [0.05 0.65 0.90 0.08], ...
        'FontSize', 9, 'ForegroundColor', [0.4 0.4 0.4], ...
        'HorizontalAlignment', 'left');
end

function cb_topology_dr(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    opts = get(src, 'String');
    idx = get(src, 'Value');
    data.design_req.topology = opts{idx};
    guidata(main_fig, data);
end


% --- 15. Market ---
function drfig = build_market_panel(drfig, dr)
    p = drfig.editor_panels.market;
    delete(get(p, 'Children'));

    market_options = {'Commercial', 'Industrial', 'Medical', 'Military', 'Space'};

    cur_market = dr.market;
    market_idx = 1;
    if ~isempty(cur_market)
        idx = find_string_index(market_options, cur_market);
        if idx > 0, market_idx = idx; end
    end

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Target Market:', ...
        'Units', 'normalized', 'Position', [0.05 0.80 0.25 0.06], ...
        'FontSize', 10, 'HorizontalAlignment', 'left');

    drfig.pop_market = uicontrol('Parent', p, 'Style', 'popupmenu', ...
        'String', market_options, ...
        'Units', 'normalized', 'Position', [0.32 0.80 0.30 0.06], ...
        'Value', market_idx, 'FontSize', 9, ...
        'Callback', @cb_market);

    uicontrol('Parent', p, 'Style', 'text', ...
        'String', 'Determines component grade and reliability requirements.', ...
        'Units', 'normalized', 'Position', [0.05 0.65 0.90 0.08], ...
        'FontSize', 9, 'ForegroundColor', [0.4 0.4 0.4], ...
        'HorizontalAlignment', 'left');
end

function cb_market(src, ~)
    fig = ancestor(src, 'figure');
    drfig = guidata(fig);
    main_fig = drfig.main_fig;
    data = guidata(main_fig);

    opts = get(src, 'String');
    idx = get(src, 'Value');
    data.design_req.market = opts{idx};
    guidata(main_fig, data);
end


% ===============================================================
% REUSABLE EDITOR HELPERS
% ===============================================================

function [edits, unit_popup] = build_dim_tolerance_controls(parent, field_name, ...
    dim_struct, unit_options, unit_multipliers, default_unit_idx, y_start, callback)
% Build Min/Nom/Max edit fields + unit dropdown.
% Returns handles to the edit fields and unit popup.

    mult = unit_multipliers(default_unit_idx);

    % Labels
    uicontrol('Parent', parent, 'Style', 'text', 'String', 'Minimum:', ...
        'Units', 'normalized', 'Position', [0.05 y_start 0.12 0.05], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');
    uicontrol('Parent', parent, 'Style', 'text', 'String', 'Nominal:', ...
        'Units', 'normalized', 'Position', [0.05 y_start-0.08 0.12 0.05], ...
        'FontSize', 9, 'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    uicontrol('Parent', parent, 'Style', 'text', 'String', 'Maximum:', ...
        'Units', 'normalized', 'Position', [0.05 y_start-0.16 0.12 0.05], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    % Values
    min_str = '';
    nom_str = '';
    max_str = '';
    if isfield(dim_struct, 'minimum') && ~isempty(dim_struct.minimum)
        min_str = num2str(dim_struct.minimum / mult);
    end
    if isfield(dim_struct, 'nominal') && ~isempty(dim_struct.nominal)
        nom_str = num2str(dim_struct.nominal / mult);
    end
    if isfield(dim_struct, 'maximum') && ~isempty(dim_struct.maximum)
        max_str = num2str(dim_struct.maximum / mult);
    end

    e_min = uicontrol('Parent', parent, 'Style', 'edit', 'String', min_str, ...
        'Units', 'normalized', 'Position', [0.20 y_start 0.25 0.06], ...
        'FontSize', 9, 'Callback', callback);
    e_nom = uicontrol('Parent', parent, 'Style', 'edit', 'String', nom_str, ...
        'Units', 'normalized', 'Position', [0.20 y_start-0.08 0.25 0.06], ...
        'FontSize', 9, 'Callback', callback);
    e_max = uicontrol('Parent', parent, 'Style', 'edit', 'String', max_str, ...
        'Units', 'normalized', 'Position', [0.20 y_start-0.16 0.25 0.06], ...
        'FontSize', 9, 'Callback', callback);

    % Unit dropdown
    unit_popup = uicontrol('Parent', parent, 'Style', 'popupmenu', ...
        'String', unit_options, ...
        'Units', 'normalized', 'Position', [0.48 y_start-0.08 0.12 0.06], ...
        'Value', default_unit_idx, 'FontSize', 9, ...
        'Callback', callback);

    edits = struct('min', e_min, 'nom', e_nom, 'max', e_max);
end


function vals = read_dim_tolerance_controls(edits, unit_popup, unit_multipliers)
% Read Min/Nom/Max from edit fields, converting from display units to SI.

    unit_idx = get(unit_popup, 'Value');
    mult = unit_multipliers(unit_idx);

    min_val = str2double(get(edits.min, 'String'));
    nom_val = str2double(get(edits.nom, 'String'));
    max_val = str2double(get(edits.max, 'String'));

    vals = struct();
    if ~isnan(min_val)
        vals.minimum = min_val * mult;
    else
        vals.minimum = [];
    end
    if ~isnan(nom_val)
        vals.nominal = nom_val * mult;
    else
        vals.nominal = [];
    end
    if ~isnan(max_val)
        vals.maximum = max_val * mult;
    else
        vals.maximum = [];
    end
end


% ===============================================================
% UTILITY FUNCTIONS
% ===============================================================

function s = val_to_str(val)
% Convert a value to string for display, handling empty/NaN.
    if isempty(val) || (isnumeric(val) && isnan(val))
        s = '';
    else
        s = num2str(val);
    end
end


function idx = find_string_index(cell_array, target)
% Find index of target string in cell array. Returns 0 if not found.
% Uses strfind for Octave compatibility (no contains()).
    idx = 0;
    for k = 1:numel(cell_array)
        if strcmp(cell_array{k}, target)
            idx = k;
            return;
        end
    end
end


% ===============================================================
% PUBLIC API: Update from topology computation
% ===============================================================

function update_design_req_from_topology(main_fig, results)
% Called after topology computation to refresh Lm, turns ratios, n_windings.
% Updates both the data.design_req struct AND the editor panel display.

    data = guidata(main_fig);
    if ~isfield(data, 'design_req')
        data.design_req = init_design_req(data);
    end
    dr = data.design_req;

    % Update from computed results
    if isfield(results, 'computed')
        comp = results.computed;

        % Magnetizing inductance
        if isfield(comp, 'Lm_uH') && comp.Lm_uH > 0
            lm_h = comp.Lm_uH * 1e-6;
            dr.magnetizingInductance.nominal = lm_h;
        end

        % Number of windings
        if isfield(comp, 'n_windings') && comp.n_windings > 0
            dr.numberWindings = comp.n_windings;
        end

        % Turns ratios
        if isfield(comp, 'turns_ratios') && ~isempty(comp.turns_ratios)
            tr_arr = comp.turns_ratios;
            n_sec = max(1, dr.numberWindings - 1);
            dr.turnsRatios = {};
            for k = 1:n_sec
                if k <= numel(tr_arr)
                    dr.turnsRatios{k} = struct('minimum', [], 'nominal', tr_arr(k), 'maximum', []);
                else
                    dr.turnsRatios{k} = struct('minimum', [], 'nominal', 1.0, 'maximum', []);
                end
            end
        elseif isfield(comp, 'turns_ratio') && comp.turns_ratio > 0
            n_sec = max(1, dr.numberWindings - 1);
            dr.turnsRatios = {};
            for k = 1:n_sec
                dr.turnsRatios{k} = struct('minimum', [], 'nominal', comp.turns_ratio, 'maximum', []);
            end
        end
    end

    % Update topology display name
    if isfield(data, 'topology_display') && ~isempty(data.topology_display)
        dr.topology = data.topology_display;
        dr.enabled.topology = true;
    end

    data.design_req = dr;
    guidata(main_fig, data);

    % Update the design requirements figure if it exists
    dr_fig = find_dr_figure(main_fig);
    if ~isempty(dr_fig) && ishandle(dr_fig)
        drfig = guidata(dr_fig);

        % Rebuild panels that depend on topology results
        drfig = build_number_windings_panel(drfig, dr);
        drfig = build_magnetizing_inductance_panel(drfig, dr);
        drfig = build_turns_ratios_panel(drfig, dr);
        drfig = build_topology_panel(drfig, dr);

        % Also update per-winding panels
        drfig = build_leakage_inductance_panel(drfig, dr);
        drfig = build_stray_capacitance_panel(drfig, dr);
        drfig = build_isolation_sides_panel(drfig, dr);
        drfig = build_terminal_type_panel(drfig, dr);

        guidata(dr_fig, drfig);
    end
end


function dr_fig = find_dr_figure(main_fig)
% Find the design requirements figure that references this main figure.
    dr_fig = [];
    figs = findobj(0, 'Type', 'figure');
    for k = 1:numel(figs)
        fig_h = figs(k);
        try
            ud = get(fig_h, 'UserData');
            if isequal(ud, main_fig)
                fig_name = get(fig_h, 'Name');
                if ~isempty(strfind(fig_name, 'Design Requirements'))
                    dr_fig = fig_h;
                    return;
                end
            end
        catch
            % Skip figures that error on UserData access
        end
    end
end
