% topology_wizard.m
% Entry-point GUI for the PEEC Proximity Loss Analysis Tool
% Provides three pathways into the design workflow:
%   1. Topology Wizard - Collect converter specs, compute requirements, get recommendations
%   2. Import MAS File - Load a MAS JSON from OpenMagnetics or other tools
%   3. Jump to Design Requirements - Skip topology, enter magnetic specs directly
%
% Output: a design_spec struct passed to interactive_winding_designer(design_spec)

function topology_wizard()

    close all;

    % ---------- data structure ----------
    data = struct();
    data.path_selected = '';   % 'wizard', 'mas_import', 'manual'

    % Topology wizard defaults (Two-Switch Forward)
    data.topology = 'two_switch_forward';

    % Converter specs - required
    data.converter.vin_min = 100;      % V
    data.converter.vin_max = 190;      % V
    data.converter.vin_nom = [];       % V (optional - computed as midpoint if empty)
    data.converter.vout = 5;           % V
    data.converter.iout = 5;           % A
    data.converter.fsw_khz = 200;      % kHz

    % Converter specs - optional (with defaults)
    data.converter.efficiency = 90;    % percent
    data.converter.vd = 0.7;           % V (diode forward drop)
    data.converter.max_ripple = 30;    % percent
    data.converter.max_duty = [];      % empty = derived
    data.converter.max_switch_current = [];  % A (empty = not constrained)
    data.converter.n_outputs = 1;

    % Insulation
    data.insulation.class = 'Basic';        % Functional/Basic/Supplementary/Reinforced/Double
    data.insulation.pollution_degree = 2;   % 1/2/3
    data.insulation.overvoltage_cat = 'II'; % I/II/III/IV
    data.insulation.standard = 'IEC 62368-1'; % IEC 60664-1/61558-1/60335-1/62368-1
    data.insulation.cti = 'Group II';       % Group I/II/IIIA/IIIB
    data.insulation.altitude_max = 2000;    % m (default per IEC)

    % Thermal
    data.thermal.ambient_temp = 25;    % C
    data.thermal.max_rise = 40;        % C
    data.thermal.cooling = 'Natural';  % Natural/Forced

    % Computed requirements (auto-updated from converter specs)
    data.requirements.Lm_uH = 0;
    data.requirements.turns_ratio = 0;
    data.requirements.n_windings = 2;
    data.requirements.duty_nom = 0;
    data.requirements.duty_min_vin = 0;
    data.requirements.duty_max_vin = 0;
    data.requirements.i_pri_rms = 0;
    data.requirements.i_sec_rms = 0;
    data.requirements.i_mag_peak = 0;
    data.requirements.i_mag_pp = 0;
    data.requirements.i_pri_rms_worst = 0;
    data.requirements.i_sec_rms_worst = 0;
    data.requirements.i_mag_pp_worst = 0;
    data.requirements.pin_nom = 0;
    data.requirements.pout_nom = 0;

    % Recommendation settings
    data.rec.n_results = 5;
    data.rec.weight_cost = 1/3;
    data.rec.weight_losses = 1/3;
    data.rec.weight_dimensions = 1/3;
    data.rec.results = {};       % cell array of result structs
    data.rec.selected_idx = 0;   % index of selected recommendation

    % MAS import
    data.mas.filepath = '';
    data.mas.loaded = false;
    data.mas.content = struct();

    % Manual design requirements
    data.manual.Lm_uH = 100;
    data.manual.n_windings = 2;
    data.manual.turns_ratio = 2.0;
    data.manual.fsw_khz = 200;

    % Constraints (optional size limits)
    data.constraints.max_width_mm = [];    % mm (empty = unconstrained)
    data.constraints.max_height_mm = [];   % mm
    data.constraints.max_depth_mm = [];    % mm

    % ---------- Optional fields visibility ----------
    data.show_optional = false;

    % ---------- Create figure ----------
    scr = get(0, 'ScreenSize');
    fig_w = min(1400, max(1000, scr(3) - 100));
    fig_h = min(850, max(650, scr(4) - 120));
    fig_x = max(20, floor((scr(3) - fig_w) / 2));
    fig_y = max(20, floor((scr(4) - fig_h) / 2));

    data.fig = figure('Name', 'PEEC Magnetics Design - Topology Wizard', ...
                      'Position', [fig_x fig_y fig_w fig_h], ...
                      'NumberTitle', 'off', ...
                      'MenuBar', 'none', ...
                      'Resize', 'on');

    build_gui(data);

    % Initial computation
    data = guidata(data.fig);
    data = compute_requirements(data);
    data = update_requirements_display(data);
    guidata(data.fig, data);

end


% ===============================================================
% BUILD GUI
% ===============================================================

function build_gui(data)

    fig = data.fig;

    % ===== TITLE =====
    uicontrol('Parent', fig, 'Style', 'text', ...
              'String', 'PEEC Magnetics Design Tool', ...
              'Units', 'normalized', ...
              'Position', [0.15 0.93 0.70 0.05], ...
              'FontSize', 16, 'FontWeight', 'bold', ...
              'HorizontalAlignment', 'center');

    % ===== THREE PATHWAY BUTTONS (top bar) =====
    path_panel = uipanel('Parent', fig, ...
                         'Position', [0.02 0.85 0.96 0.08], ...
                         'Title', 'Choose Your Design Path', ...
                         'FontSize', 10, 'FontWeight', 'bold');

    data.btn_wizard = uicontrol('Parent', path_panel, 'Style', 'pushbutton', ...
              'String', 'Topology Wizard (Two-Switch Forward)', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.15 0.30 0.70], ...
              'FontSize', 11, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.0 0.7 0.7], ...
              'ForegroundColor', 'w', ...
              'Callback', @select_path_wizard);

    data.btn_mas = uicontrol('Parent', path_panel, 'Style', 'pushbutton', ...
              'String', 'Import MAS File', ...
              'Units', 'normalized', ...
              'Position', [0.35 0.15 0.30 0.70], ...
              'FontSize', 11, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.5 0.3 0.7], ...
              'ForegroundColor', 'w', ...
              'Callback', @select_path_mas);

    data.btn_manual = uicontrol('Parent', path_panel, 'Style', 'pushbutton', ...
              'String', 'Jump to Design Requirements', ...
              'Units', 'normalized', ...
              'Position', [0.68 0.15 0.30 0.70], ...
              'FontSize', 11, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.3 0.5 0.3], ...
              'ForegroundColor', 'w', ...
              'Callback', @select_path_manual);

    % ===== MAIN CONTENT AREA (switched by path) =====
    % All three panels overlap - only one visible at a time

    % ---------- WIZARD PANEL ----------
    data.panel_wizard = uipanel('Parent', fig, ...
                                'Position', [0.02 0.02 0.96 0.82], ...
                                'Title', '', ...
                                'Visible', 'on');
    guidata(fig, data);
    build_wizard_panel(data);
    data = guidata(fig);  % retrieve handles stored by build_wizard_panel

    % ---------- MAS IMPORT PANEL ----------
    data.panel_mas = uipanel('Parent', fig, ...
                             'Position', [0.02 0.02 0.96 0.82], ...
                             'Title', '', ...
                             'Visible', 'off');
    guidata(fig, data);
    build_mas_panel(data);
    data = guidata(fig);  % retrieve handles stored by build_mas_panel

    % ---------- MANUAL PANEL ----------
    data.panel_manual = uipanel('Parent', fig, ...
                                'Position', [0.02 0.02 0.96 0.82], ...
                                'Title', '', ...
                                'Visible', 'off');
    guidata(fig, data);
    build_manual_panel(data);
    data = guidata(fig);  % retrieve handles stored by build_manual_panel

    % Default to wizard view
    data.path_selected = 'wizard';
    guidata(fig, data);

end


% ===============================================================
% WIZARD PANEL (Path 1)
% ===============================================================

function build_wizard_panel(data)

    panel = data.panel_wizard;

    % ----- LEFT: Converter Specifications -----
    spec_panel = uipanel('Parent', panel, ...
                         'Position', [0.01 0.01 0.48 0.98], ...
                         'Title', 'Two-Switch Forward - Converter Specifications', ...
                         'FontSize', 10, 'FontWeight', 'bold');

    % --- Required fields ---
    req_label = uicontrol('Parent', spec_panel, 'Style', 'text', ...
              'String', 'Required Specifications', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.92 0.96 0.04], ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'ForegroundColor', [0.0 0.6 0.6], ...
              'HorizontalAlignment', 'left');

    y = 0.86;
    dy = 0.065;

    % Input Voltage Min
    make_label(spec_panel, 'Input Voltage Min.', [0.02 y 0.35 0.04]);
    data.edit_vin_min = make_edit(spec_panel, num2str(data.converter.vin_min), ...
                                  [0.38 y 0.20 0.045], @cb_vin_min);
    make_label(spec_panel, 'V', [0.59 y 0.05 0.04]);
    y = y - dy;

    % Input Voltage Max
    make_label(spec_panel, 'Input Voltage Max.', [0.02 y 0.35 0.04]);
    data.edit_vin_max = make_edit(spec_panel, num2str(data.converter.vin_max), ...
                                  [0.38 y 0.20 0.045], @cb_vin_max);
    make_label(spec_panel, 'V', [0.59 y 0.05 0.04]);
    y = y - dy;

    % Output Voltage
    make_label(spec_panel, 'Output Voltage', [0.02 y 0.35 0.04]);
    data.edit_vout = make_edit(spec_panel, num2str(data.converter.vout), ...
                               [0.38 y 0.20 0.045], @cb_vout);
    make_label(spec_panel, 'V', [0.59 y 0.05 0.04]);
    y = y - dy;

    % Output Current
    make_label(spec_panel, 'Output Current', [0.02 y 0.35 0.04]);
    data.edit_iout = make_edit(spec_panel, num2str(data.converter.iout), ...
                               [0.38 y 0.20 0.045], @cb_iout);
    make_label(spec_panel, 'A', [0.59 y 0.05 0.04]);
    y = y - dy;

    % Switching Frequency
    make_label(spec_panel, 'Switching Frequency', [0.02 y 0.35 0.04]);
    data.edit_fsw = make_edit(spec_panel, num2str(data.converter.fsw_khz), ...
                              [0.38 y 0.20 0.045], @cb_fsw);
    make_label(spec_panel, 'kHz', [0.59 y 0.08 0.04]);
    y = y - dy;

    % --- Separator and optional toggle ---
    y = y - 0.01;
    data.btn_toggle_optional = uicontrol('Parent', spec_panel, 'Style', 'pushbutton', ...
              'String', 'Show Optional Parameters', ...
              'Units', 'normalized', ...
              'Position', [0.02 y 0.60 0.04], ...
              'FontSize', 8, ...
              'BackgroundColor', [0.3 0.3 0.4], ...
              'ForegroundColor', 'w', ...
              'Callback', @cb_toggle_optional);
    y = y - 0.02;

    % --- Optional fields (in a sub-panel for show/hide) ---
    data.optional_panel = uipanel('Parent', spec_panel, ...
                                  'Position', [0.00 0.01 1.0 y], ...
                                  'Title', '', ...
                                  'BorderType', 'none', ...
                                  'Visible', 'off');
    guidata(data.fig, data);
    build_optional_fields(data);
    data = guidata(data.fig);  % retrieve optional field handles

    % ----- RIGHT: Computed Requirements -----
    req_panel = uipanel('Parent', panel, ...
                        'Position', [0.50 0.30 0.49 0.69], ...
                        'Title', 'Computed Design Requirements', ...
                        'FontSize', 10, 'FontWeight', 'bold');

    data.txt_requirements = uicontrol('Parent', req_panel, 'Style', 'text', ...
              'String', '(computing...)', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.02 0.96 0.94], ...
              'FontSize', 10, ...
              'HorizontalAlignment', 'left', ...
              'Max', 2);  % multi-line

    % ----- RIGHT BOTTOM: Recommendation Controls -----
    rec_panel = uipanel('Parent', panel, ...
                        'Position', [0.50 0.01 0.49 0.28], ...
                        'Title', 'Design Recommendations (PyOpenMagnetics)', ...
                        'FontSize', 10, 'FontWeight', 'bold');

    % Number of recommendations
    make_label(rec_panel, 'How many recommendations?', [0.02 0.75 0.45 0.15]);
    data.pop_n_results = uicontrol('Parent', rec_panel, 'Style', 'popupmenu', ...
              'String', {'3', '5', '10'}, ...
              'Units', 'normalized', ...
              'Position', [0.48 0.76 0.12 0.14], ...
              'Value', 2, ...
              'Callback', @cb_n_results);

    % Priority sliders (linked: always sum to 100%)
    make_label(rec_panel, 'Cost', [0.02 0.52 0.08 0.14]);
    data.slider_cost = uicontrol('Parent', rec_panel, 'Style', 'slider', ...
              'Units', 'normalized', ...
              'Position', [0.10 0.54 0.16 0.12], ...
              'Min', 0, 'Max', 1, 'Value', 1/3, ...
              'Callback', @cb_weight_cost);
    data.lbl_cost_pct = uicontrol('Parent', rec_panel, 'Style', 'text', ...
              'Units', 'normalized', ...
              'Position', [0.26 0.52 0.07 0.14], ...
              'String', '33%', 'FontSize', 8);

    make_label(rec_panel, 'Losses', [0.35 0.52 0.09 0.14]);
    data.slider_losses = uicontrol('Parent', rec_panel, 'Style', 'slider', ...
              'Units', 'normalized', ...
              'Position', [0.44 0.54 0.16 0.12], ...
              'Min', 0, 'Max', 1, 'Value', 1/3, ...
              'Callback', @cb_weight_losses);
    data.lbl_losses_pct = uicontrol('Parent', rec_panel, 'Style', 'text', ...
              'Units', 'normalized', ...
              'Position', [0.60 0.52 0.07 0.14], ...
              'String', '33%', 'FontSize', 8);

    make_label(rec_panel, 'Size', [0.69 0.52 0.07 0.14]);
    data.slider_dims = uicontrol('Parent', rec_panel, 'Style', 'slider', ...
              'Units', 'normalized', ...
              'Position', [0.76 0.54 0.16 0.12], ...
              'Min', 0, 'Max', 1, 'Value', 1/3, ...
              'Callback', @cb_weight_dims);
    data.lbl_dims_pct = uicontrol('Parent', rec_panel, 'Style', 'text', ...
              'Units', 'normalized', ...
              'Position', [0.92 0.52 0.07 0.14], ...
              'String', '33%', 'FontSize', 8);

    % Get Recommendations button
    data.btn_get_recs = uicontrol('Parent', rec_panel, 'Style', 'pushbutton', ...
              'String', 'Get Recommendations', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.08 0.40 0.35], ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.0 0.6 0.8], ...
              'ForegroundColor', 'w', ...
              'Callback', @cb_get_recommendations);

    % Continue to analysis/winding stage
    data.btn_continue_norec = uicontrol('Parent', rec_panel, 'Style', 'pushbutton', ...
              'String', 'Analyze Design', ...
              'Units', 'normalized', ...
              'Position', [0.45 0.08 0.52 0.35], ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.2 0.7 0.3], ...
              'ForegroundColor', 'w', ...
              'Callback', @cb_continue_wizard);

    guidata(data.fig, data);
end


function build_optional_fields(data)

    panel = data.optional_panel;
    y = 0.90;
    dy = 0.11;

    % Input Voltage Nominal (optional)
    make_label(panel, 'Input Voltage Nom. (optional)', [0.02 y 0.35 0.06]);
    data.edit_vin_nom = make_edit(panel, '', [0.38 y 0.20 0.07], @cb_vin_nom);
    make_label(panel, 'V', [0.59 y 0.05 0.06]);
    y = y - dy;

    % Efficiency target
    make_label(panel, 'Efficiency target', [0.02 y 0.35 0.06]);
    data.edit_efficiency = make_edit(panel, num2str(data.converter.efficiency), ...
                                     [0.38 y 0.20 0.07], @cb_efficiency);
    make_label(panel, '%', [0.59 y 0.05 0.06]);
    y = y - dy;

    % Diode forward voltage
    make_label(panel, 'Diode forward voltage', [0.02 y 0.35 0.06]);
    data.edit_vd = make_edit(panel, num2str(data.converter.vd), ...
                              [0.38 y 0.20 0.07], @cb_vd);
    make_label(panel, 'V', [0.59 y 0.05 0.06]);
    y = y - dy;

    % Max current ripple
    make_label(panel, 'Max current ripple', [0.02 y 0.35 0.06]);
    data.edit_ripple = make_edit(panel, num2str(data.converter.max_ripple), ...
                                 [0.38 y 0.20 0.07], @cb_ripple);
    make_label(panel, '%', [0.59 y 0.05 0.06]);
    y = y - dy;

    % Max switch current
    make_label(panel, 'Max switch current', [0.02 y 0.35 0.06]);
    data.edit_max_isw = make_edit(panel, '', [0.38 y 0.20 0.07], @cb_max_isw);
    make_label(panel, 'A', [0.59 y 0.05 0.06]);
    y = y - dy;

    % --- Insulation ---
    make_label(panel, 'Insulation class', [0.02 y 0.35 0.06]);
    data.pop_insulation = uicontrol('Parent', panel, 'Style', 'popupmenu', ...
              'String', {'Functional', 'Basic', 'Supplementary', 'Reinforced', 'Double'}, ...
              'Units', 'normalized', ...
              'Position', [0.38 y 0.25 0.07], ...
              'Value', 2, ...
              'Callback', @cb_insulation_class);
    y = y - dy;

    make_label(panel, 'CTI group', [0.02 y 0.35 0.06]);
    data.pop_cti = uicontrol('Parent', panel, 'Style', 'popupmenu', ...
              'String', {'Group I', 'Group II', 'Group IIIA', 'Group IIIB'}, ...
              'Units', 'normalized', ...
              'Position', [0.38 y 0.25 0.07], ...
              'Value', 2, ...
              'Callback', @cb_cti);
    y = y - dy;

    make_label(panel, 'Pollution degree', [0.02 y 0.35 0.06]);
    data.pop_pollution = uicontrol('Parent', panel, 'Style', 'popupmenu', ...
              'String', {'1', '2', '3'}, ...
              'Units', 'normalized', ...
              'Position', [0.38 y 0.25 0.07], ...
              'Value', 2, ...
              'Callback', @cb_pollution_degree);
    y = y - dy;

    make_label(panel, 'Overvoltage category', [0.02 y 0.35 0.06]);
    data.pop_ovc = uicontrol('Parent', panel, 'Style', 'popupmenu', ...
              'String', {'I', 'II', 'III', 'IV'}, ...
              'Units', 'normalized', ...
              'Position', [0.38 y 0.25 0.07], ...
              'Value', 2, ...
              'Callback', @cb_overvoltage_cat);
    y = y - dy;

    make_label(panel, 'Insulation standard', [0.02 y 0.35 0.06]);
    data.pop_ins_std = uicontrol('Parent', panel, 'Style', 'popupmenu', ...
              'String', {'IEC 62368-1', 'IEC 60664-1', 'IEC 61558-1', 'IEC 60335-1'}, ...
              'Units', 'normalized', ...
              'Position', [0.38 y 0.25 0.07], ...
              'Value', 1, ...
              'Callback', @cb_insulation_standard);
    y = y - dy;

    % --- Thermal ---
    make_label(panel, 'Ambient temperature', [0.02 y 0.35 0.06]);
    data.edit_ambient = make_edit(panel, num2str(data.thermal.ambient_temp), ...
                                  [0.38 y 0.20 0.07], @cb_ambient_temp);
    make_label(panel, 'C', [0.59 y 0.05 0.06]);
    y = y - dy - 0.005;

    make_label(panel, 'Max temperature rise', [0.02 y 0.35 0.06]);
    data.edit_max_rise = make_edit(panel, num2str(data.thermal.max_rise), ...
                                   [0.38 y 0.20 0.07], @cb_max_rise);
    make_label(panel, 'C', [0.59 y 0.05 0.06]);
    y = y - dy;

    % --- Size Constraints ---
    make_label(panel, 'Max width (optional)', [0.02 y 0.35 0.06]);
    data.edit_max_width = make_edit(panel, '', [0.38 y 0.20 0.07], @cb_max_width);
    make_label(panel, 'mm', [0.59 y 0.05 0.06]);
    y = y - dy;

    make_label(panel, 'Max height (optional)', [0.02 y 0.35 0.06]);
    data.edit_max_height = make_edit(panel, '', [0.38 y 0.20 0.07], @cb_max_height);
    make_label(panel, 'mm', [0.59 y 0.05 0.06]);
    y = y - dy;

    make_label(panel, 'Max depth (optional)', [0.02 y 0.35 0.06]);
    data.edit_max_depth = make_edit(panel, '', [0.38 y 0.20 0.07], @cb_max_depth);
    make_label(panel, 'mm', [0.59 y 0.05 0.06]);

    guidata(data.fig, data);
end


% ===============================================================
% MAS IMPORT PANEL (Path 2)
% ===============================================================

function build_mas_panel(data)

    panel = data.panel_mas;

    uicontrol('Parent', panel, 'Style', 'text', ...
              'String', 'Import a Magnetic Assembly Specification (MAS) File', ...
              'Units', 'normalized', ...
              'Position', [0.05 0.88 0.90 0.06], ...
              'FontSize', 12, 'FontWeight', 'bold', ...
              'HorizontalAlignment', 'center');

    uicontrol('Parent', panel, 'Style', 'text', ...
              'String', 'Load a .json MAS file from OpenMagnetics, PyOpenMagnetics, or other compatible tools.', ...
              'Units', 'normalized', ...
              'Position', [0.05 0.82 0.90 0.05], ...
              'FontSize', 9, ...
              'HorizontalAlignment', 'center');

    % File path display
    make_label(panel, 'File:', [0.05 0.73 0.06 0.04]);
    data.edit_mas_path = uicontrol('Parent', panel, 'Style', 'edit', ...
              'String', '', ...
              'Units', 'normalized', ...
              'Position', [0.12 0.73 0.65 0.045], ...
              'HorizontalAlignment', 'left', ...
              'Enable', 'inactive');

    data.btn_mas_browse = uicontrol('Parent', panel, 'Style', 'pushbutton', ...
              'String', 'Browse...', ...
              'Units', 'normalized', ...
              'Position', [0.78 0.73 0.15 0.045], ...
              'FontSize', 10, ...
              'Callback', @cb_mas_browse);

    % Summary display area
    data.panel_mas_summary = uipanel('Parent', panel, ...
                                     'Position', [0.05 0.12 0.90 0.58], ...
                                     'Title', 'MAS File Summary', ...
                                     'FontSize', 10);

    data.txt_mas_summary = uicontrol('Parent', data.panel_mas_summary, 'Style', 'text', ...
              'String', '(No file loaded)', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.02 0.96 0.94], ...
              'FontSize', 10, ...
              'HorizontalAlignment', 'left', ...
              'Max', 2);

    % Continue button
    data.btn_continue_mas = uicontrol('Parent', panel, 'Style', 'pushbutton', ...
              'String', 'Continue to Winding Designer', ...
              'Units', 'normalized', ...
              'Position', [0.30 0.03 0.40 0.07], ...
              'FontSize', 12, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.2 0.7 0.3], ...
              'ForegroundColor', 'w', ...
              'Enable', 'off', ...
              'Callback', @cb_continue_mas);

    guidata(data.fig, data);
end


% ===============================================================
% MANUAL DESIGN REQUIREMENTS PANEL (Path 3)
% ===============================================================

function build_manual_panel(data)

    panel = data.panel_manual;

    uicontrol('Parent', panel, 'Style', 'text', ...
              'String', 'Direct Design Requirements Entry', ...
              'Units', 'normalized', ...
              'Position', [0.05 0.88 0.90 0.06], ...
              'FontSize', 12, 'FontWeight', 'bold', ...
              'HorizontalAlignment', 'center');

    uicontrol('Parent', panel, 'Style', 'text', ...
              'String', 'Enter magnetic requirements directly without converter topology calculations.', ...
              'Units', 'normalized', ...
              'Position', [0.05 0.82 0.90 0.05], ...
              'FontSize', 9, ...
              'HorizontalAlignment', 'center');

    spec_panel = uipanel('Parent', panel, ...
                         'Position', [0.20 0.35 0.60 0.45], ...
                         'Title', 'Magnetic Requirements', ...
                         'FontSize', 10, 'FontWeight', 'bold');

    y = 0.80;
    dy = 0.18;

    % Magnetizing inductance
    make_label(spec_panel, 'Magnetizing Inductance', [0.05 y 0.40 0.10]);
    data.edit_manual_lm = make_edit(spec_panel, num2str(data.manual.Lm_uH), ...
                                    [0.48 y 0.22 0.12], @cb_manual_lm);
    make_label(spec_panel, 'uH', [0.72 y 0.10 0.10]);
    y = y - dy;

    % Number of windings
    make_label(spec_panel, 'Number of Windings', [0.05 y 0.40 0.10]);
    data.pop_manual_nw = uicontrol('Parent', spec_panel, 'Style', 'popupmenu', ...
              'String', {'1', '2', '3', '4'}, ...
              'Units', 'normalized', ...
              'Position', [0.48 y 0.22 0.12], ...
              'Value', data.manual.n_windings, ...
              'Callback', @cb_manual_nw);
    y = y - dy;

    % Turns ratio
    make_label(spec_panel, 'Turns Ratio (Np:Ns)', [0.05 y 0.40 0.10]);
    data.edit_manual_ratio = make_edit(spec_panel, num2str(data.manual.turns_ratio), ...
                                       [0.48 y 0.22 0.12], @cb_manual_ratio);
    y = y - dy;

    % Operating frequency
    make_label(spec_panel, 'Operating Frequency', [0.05 y 0.40 0.10]);
    data.edit_manual_fsw = make_edit(spec_panel, num2str(data.manual.fsw_khz), ...
                                     [0.48 y 0.22 0.12], @cb_manual_fsw);
    make_label(spec_panel, 'kHz', [0.72 y 0.10 0.10]);

    % Continue button
    data.btn_continue_manual = uicontrol('Parent', panel, 'Style', 'pushbutton', ...
              'String', 'Continue to Winding Designer', ...
              'Units', 'normalized', ...
              'Position', [0.30 0.10 0.40 0.08], ...
              'FontSize', 12, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.2 0.7 0.3], ...
              'ForegroundColor', 'w', ...
              'Callback', @cb_continue_manual);

    guidata(data.fig, data);
end


% ===============================================================
% UI HELPERS
% ===============================================================

function h = make_label(parent, str, pos)
    h = uicontrol('Parent', parent, 'Style', 'text', ...
                  'String', str, ...
                  'Units', 'normalized', ...
                  'Position', pos, ...
                  'HorizontalAlignment', 'left', ...
                  'FontSize', 9);
end

function h = make_edit(parent, str, pos, cb)
    h = uicontrol('Parent', parent, 'Style', 'edit', ...
                  'String', str, ...
                  'Units', 'normalized', ...
                  'Position', pos, ...
                  'FontSize', 9, ...
                  'Callback', cb);
end


% ===============================================================
% PATH SWITCHING CALLBACKS
% ===============================================================

function select_path_wizard(~, ~)
    fig = gcbf();
    data = guidata(fig);
    data.path_selected = 'wizard';
    set(data.panel_wizard, 'Visible', 'on');
    set(data.panel_mas, 'Visible', 'off');
    set(data.panel_manual, 'Visible', 'off');
    % Highlight active button
    set(data.btn_wizard, 'BackgroundColor', [0.0 0.7 0.7]);
    set(data.btn_mas, 'BackgroundColor', [0.35 0.2 0.5]);
    set(data.btn_manual, 'BackgroundColor', [0.2 0.35 0.2]);
    guidata(fig, data);
end

function select_path_mas(~, ~)
    fig = gcbf();
    data = guidata(fig);
    data.path_selected = 'mas_import';
    set(data.panel_wizard, 'Visible', 'off');
    set(data.panel_mas, 'Visible', 'on');
    set(data.panel_manual, 'Visible', 'off');
    set(data.btn_wizard, 'BackgroundColor', [0.0 0.5 0.5]);
    set(data.btn_mas, 'BackgroundColor', [0.5 0.3 0.7]);
    set(data.btn_manual, 'BackgroundColor', [0.2 0.35 0.2]);
    guidata(fig, data);
end

function select_path_manual(~, ~)
    fig = gcbf();
    data = guidata(fig);
    data.path_selected = 'manual';
    set(data.panel_wizard, 'Visible', 'off');
    set(data.panel_mas, 'Visible', 'off');
    set(data.panel_manual, 'Visible', 'on');
    set(data.btn_wizard, 'BackgroundColor', [0.0 0.5 0.5]);
    set(data.btn_mas, 'BackgroundColor', [0.35 0.2 0.5]);
    set(data.btn_manual, 'BackgroundColor', [0.3 0.5 0.3]);
    guidata(fig, data);
end


% ===============================================================
% CONVERTER SPEC CALLBACKS (Wizard Path)
% ===============================================================

function cb_vin_min(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.converter.vin_min = val;
        data = compute_requirements(data);
        data = update_requirements_display(data);
    end
    guidata(fig, data);
end

function cb_vin_max(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.converter.vin_max = val;
        data = compute_requirements(data);
        data = update_requirements_display(data);
    end
    guidata(fig, data);
end

function cb_vin_nom(src, ~)
    fig = gcbf();
    data = guidata(fig);
    str = strtrim(get(src, 'String'));
    if isempty(str)
        data.converter.vin_nom = [];
    else
        val = str2double(str);
        if ~isnan(val) && val > 0
            data.converter.vin_nom = val;
        end
    end
    data = compute_requirements(data);
    data = update_requirements_display(data);
    guidata(fig, data);
end

function cb_vout(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.converter.vout = val;
        data = compute_requirements(data);
        data = update_requirements_display(data);
    end
    guidata(fig, data);
end

function cb_iout(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.converter.iout = val;
        data = compute_requirements(data);
        data = update_requirements_display(data);
    end
    guidata(fig, data);
end

function cb_fsw(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.converter.fsw_khz = val;
        data = compute_requirements(data);
        data = update_requirements_display(data);
    end
    guidata(fig, data);
end

function cb_efficiency(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0 && val <= 100
        data.converter.efficiency = val;
        data = compute_requirements(data);
        data = update_requirements_display(data);
    end
    guidata(fig, data);
end

function cb_vd(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val >= 0
        data.converter.vd = val;
        data = compute_requirements(data);
        data = update_requirements_display(data);
    end
    guidata(fig, data);
end

function cb_ripple(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0 && val <= 100
        data.converter.max_ripple = val;
        data = compute_requirements(data);
        data = update_requirements_display(data);
    end
    guidata(fig, data);
end

function cb_max_isw(src, ~)
    fig = gcbf();
    data = guidata(fig);
    str = strtrim(get(src, 'String'));
    if isempty(str)
        data.converter.max_switch_current = [];
    else
        val = str2double(str);
        if ~isnan(val) && val > 0
            data.converter.max_switch_current = val;
        end
    end
    guidata(fig, data);
end

function cb_toggle_optional(~, ~)
    fig = gcbf();
    data = guidata(fig);
    data.show_optional = ~data.show_optional;
    if data.show_optional
        set(data.optional_panel, 'Visible', 'on');
        set(data.btn_toggle_optional, 'String', 'Hide Optional Parameters');
    else
        set(data.optional_panel, 'Visible', 'off');
        set(data.btn_toggle_optional, 'String', 'Show Optional Parameters');
    end
    guidata(fig, data);
end

function cb_insulation_class(src, ~)
    fig = gcbf();
    data = guidata(fig);
    items = get(src, 'String');
    data.insulation.class = items{get(src, 'Value')};
    guidata(fig, data);
end

function cb_pollution_degree(src, ~)
    fig = gcbf();
    data = guidata(fig);
    data.insulation.pollution_degree = get(src, 'Value');
    guidata(fig, data);
end

function cb_overvoltage_cat(src, ~)
    fig = gcbf();
    data = guidata(fig);
    items = get(src, 'String');
    data.insulation.overvoltage_cat = items{get(src, 'Value')};
    guidata(fig, data);
end

function cb_insulation_standard(src, ~)
    fig = gcbf();
    data = guidata(fig);
    items = get(src, 'String');
    data.insulation.standard = items{get(src, 'Value')};
    guidata(fig, data);
end

function cb_cti(src, ~)
    fig = gcbf();
    data = guidata(fig);
    items = get(src, 'String');
    data.insulation.cti = items{get(src, 'Value')};
    guidata(fig, data);
end

function cb_ambient_temp(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val)
        data.thermal.ambient_temp = val;
    end
    guidata(fig, data);
end

function cb_max_rise(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.thermal.max_rise = val;
    end
    guidata(fig, data);
end

function cb_max_width(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if isnan(val) || val <= 0
        data.constraints.max_width_mm = [];
    else
        data.constraints.max_width_mm = val;
    end
    guidata(fig, data);
end

function cb_max_height(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if isnan(val) || val <= 0
        data.constraints.max_height_mm = [];
    else
        data.constraints.max_height_mm = val;
    end
    guidata(fig, data);
end

function cb_max_depth(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if isnan(val) || val <= 0
        data.constraints.max_depth_mm = [];
    else
        data.constraints.max_depth_mm = val;
    end
    guidata(fig, data);
end

function cb_n_results(src, ~)
    fig = gcbf();
    data = guidata(fig);
    items = get(src, 'String');
    data.rec.n_results = str2double(items{get(src, 'Value')});
    guidata(fig, data);
end

function cb_weight_cost(src, ~)
    fig = gcbf();
    data = guidata(fig);
    new_val = get(src, 'Value');
    data = redistribute_weights(data, 'cost', new_val);
    guidata(fig, data);
end

function cb_weight_losses(src, ~)
    fig = gcbf();
    data = guidata(fig);
    new_val = get(src, 'Value');
    data = redistribute_weights(data, 'losses', new_val);
    guidata(fig, data);
end

function cb_weight_dims(src, ~)
    fig = gcbf();
    data = guidata(fig);
    new_val = get(src, 'Value');
    data = redistribute_weights(data, 'dimensions', new_val);
    guidata(fig, data);
end

function data = redistribute_weights(data, changed, new_val)
    % Linked weight sliders: always sum to 1.0 (100%).
    % When one slider changes, the other two redistribute proportionally.
    new_val = max(0, min(1, new_val));
    remaining = 1.0 - new_val;

    switch changed
        case 'cost'
            other1 = data.rec.weight_losses;
            other2 = data.rec.weight_dimensions;
        case 'losses'
            other1 = data.rec.weight_cost;
            other2 = data.rec.weight_dimensions;
        case 'dimensions'
            other1 = data.rec.weight_cost;
            other2 = data.rec.weight_losses;
    end

    old_sum = other1 + other2;
    if old_sum > 1e-9
        % Scale proportionally
        other1_new = other1 * remaining / old_sum;
        other2_new = other2 * remaining / old_sum;
    else
        % Both were zero — split equally
        other1_new = remaining / 2;
        other2_new = remaining / 2;
    end

    switch changed
        case 'cost'
            data.rec.weight_cost = new_val;
            data.rec.weight_losses = other1_new;
            data.rec.weight_dimensions = other2_new;
        case 'losses'
            data.rec.weight_cost = other1_new;
            data.rec.weight_losses = new_val;
            data.rec.weight_dimensions = other2_new;
        case 'dimensions'
            data.rec.weight_cost = other1_new;
            data.rec.weight_dimensions = new_val;
            data.rec.weight_losses = other2_new;
    end

    % Update slider positions
    set(data.slider_cost, 'Value', data.rec.weight_cost);
    set(data.slider_losses, 'Value', data.rec.weight_losses);
    set(data.slider_dims, 'Value', data.rec.weight_dimensions);

    % Update percentage labels
    set(data.lbl_cost_pct, 'String', sprintf('%.0f%%', data.rec.weight_cost * 100));
    set(data.lbl_losses_pct, 'String', sprintf('%.0f%%', data.rec.weight_losses * 100));
    set(data.lbl_dims_pct, 'String', sprintf('%.0f%%', data.rec.weight_dimensions * 100));
end


% ===============================================================
% MANUAL PATH CALLBACKS
% ===============================================================

function cb_manual_lm(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.manual.Lm_uH = val;
    end
    guidata(fig, data);
end

function cb_manual_nw(src, ~)
    fig = gcbf();
    data = guidata(fig);
    data.manual.n_windings = get(src, 'Value');
    guidata(fig, data);
end

function cb_manual_ratio(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.manual.turns_ratio = val;
    end
    guidata(fig, data);
end

function cb_manual_fsw(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.manual.fsw_khz = val;
    end
    guidata(fig, data);
end


% ===============================================================
% MAS IMPORT CALLBACKS
% ===============================================================

function cb_mas_browse(~, ~)
    fig = gcbf();
    data = guidata(fig);

    [fname, fpath] = uigetfile({'*.json', 'MAS JSON Files (*.json)'; ...
                                 '*.*', 'All Files (*.*)'}, ...
                                'Select MAS File');
    if isequal(fname, 0)
        return;  % user cancelled
    end

    full_path = fullfile(fpath, fname);
    set(data.edit_mas_path, 'String', full_path);
    data.mas.filepath = full_path;

    % Try to load and parse
    try
        fid = fopen(full_path, 'r', 'n', 'UTF-8');
        raw = fread(fid, '*char')';
        fclose(fid);
        mas = jsondecode(raw);
        data.mas.content = mas;
        data.mas.loaded = true;

        % Build summary text
        summary = build_mas_summary(mas);
        set(data.txt_mas_summary, 'String', summary);
        set(data.btn_continue_mas, 'Enable', 'on');
    catch err
        data.mas.loaded = false;
        data.mas.content = struct();
        set(data.txt_mas_summary, 'String', ...
            sprintf('Error loading file:\n%s', err.message));
        set(data.btn_continue_mas, 'Enable', 'off');
    end

    guidata(fig, data);
end


% ===============================================================
% TWO-SWITCH FORWARD CALCULATIONS
% ===============================================================

function data = compute_requirements(data)
    % Two-Switch Forward converter equations
    % Derives magnetic requirements from converter specifications

    c = data.converter;
    fsw = c.fsw_khz * 1e3;  % Hz
    eta = c.efficiency / 100;
    vd = c.vd;
    vout = c.vout;
    iout = c.iout;
    vin_min = c.vin_min;
    vin_max = c.vin_max;

    if isempty(c.vin_nom)
        vin_nom = (vin_min + vin_max) / 2;
    else
        vin_nom = c.vin_nom;
    end

    % Output power
    pout = vout * iout;
    pin_nom = pout / max(eta, 0.01);

    % For a two-switch forward, the transformer couples input to output.
    % Duty cycle: D = (Vout + Vd) / (Vin * N), where N = Ns/Np
    % At max Vin, duty is minimum; at min Vin, duty is maximum.
    % Max duty for two-switch forward is limited to 0.50 (no overlap).

    % We need to choose turns ratio such that D_max at Vin_min <= 0.48
    % D_max = (Vout + Vd) / (Vin_min * Ns/Np)
    % Choose Ns/Np so D_max ~ 0.45 at Vin_min
    d_target_max = 0.45;
    ns_np = (vout + vd) / (vin_min * d_target_max);  % Ns/Np ratio
    np_ns = 1 / ns_np;  % Np/Ns (primary to secondary turns ratio)

    % Actual duty cycles
    d_min_vin = (vout + vd) / (vin_min * ns_np);   % duty at min Vin (highest)
    d_max_vin = (vout + vd) / (vin_max * ns_np);   % duty at max Vin (lowest)
    d_nom = (vout + vd) / (vin_nom * ns_np);        % duty at nominal Vin

    % Clamp duties
    d_min_vin = min(d_min_vin, 0.49);
    d_max_vin = max(d_max_vin, 0.01);
    d_nom = max(min(d_nom, 0.49), 0.01);

    % Output inductor sizing (for forward converter, output inductor Lout)
    % delta_I = Vout * (1 - D) / (Lout * fsw)
    % Lout_min = Vout * (1 - D_min) / (delta_I_max * fsw)
    % where delta_I_max = max_ripple * Iout
    ripple_frac = c.max_ripple / 100;
    delta_i_max = ripple_frac * iout;
    if delta_i_max > 0
        lout = vout * (1 - d_max_vin) / (delta_i_max * fsw);  % worst case at max Vin
    else
        lout = 100e-6;  % fallback
    end

    % Magnetizing inductance (transformer Lm)
    % For forward converter, Lm is usually much larger (doesn't store energy)
    % Lm determines magnetizing current ripple: delta_Im = Vin * D / (Lm * fsw)
    % Typically design for low magnetizing current (5-10% of load current reflected)
    i_load_reflected = iout * ns_np;  % secondary current reflected to primary
    i_mag_ripple_target = 0.10 * i_load_reflected;  % 10% magnetizing current
    if i_mag_ripple_target > 0
        lm = vin_nom * d_nom / (i_mag_ripple_target * fsw);
    else
        lm = 500e-6;  % fallback
    end

    % RMS currents
    % Primary: I_pri_rms = Iout * (Ns/Np) * sqrt(D)  (during on-time)
    i_pri_rms = iout * ns_np * sqrt(d_nom);
    i_sec_rms = iout * sqrt(d_nom);  % secondary conducts during on-time

    % Peak magnetizing current and pk-pk ripple
    i_mag_peak = vin_nom * d_nom / (2 * lm * fsw);
    i_mag_pp = vin_nom * d_nom / (lm * fsw);  % full peak-to-peak magnetizing ripple

    % Worst-case currents at Vin_min (max duty / max stress)
    i_pri_rms_worst = iout * ns_np * sqrt(d_min_vin);
    i_sec_rms_worst = iout * sqrt(d_min_vin);
    i_mag_pp_worst = vin_min * d_min_vin / (lm * fsw);

    % Store results
    data.requirements.Lm_uH = lm * 1e6;
    data.requirements.Lout_uH = lout * 1e6;
    data.requirements.turns_ratio = np_ns;
    data.requirements.ns_np = ns_np;
    data.requirements.n_windings = 2;
    data.requirements.duty_nom = d_nom;
    data.requirements.duty_min_vin = d_min_vin;
    data.requirements.duty_max_vin = d_max_vin;
    data.requirements.i_pri_rms = i_pri_rms;
    data.requirements.i_sec_rms = i_sec_rms;
    data.requirements.i_mag_peak = i_mag_peak;
    data.requirements.i_mag_pp = i_mag_pp;
    data.requirements.i_pri_rms_worst = i_pri_rms_worst;
    data.requirements.i_sec_rms_worst = i_sec_rms_worst;
    data.requirements.i_mag_pp_worst = i_mag_pp_worst;
    data.requirements.pin_nom = pin_nom;
    data.requirements.pout_nom = pout;
    data.requirements.vin_nom = vin_nom;
    data.requirements.fsw_hz = fsw;

end


function data = update_requirements_display(data)

    r = data.requirements;
    c = data.converter;

    lines = {};
    lines{end+1} = sprintf('--- Two-Switch Forward Design ---');
    lines{end+1} = '';
    lines{end+1} = sprintf('Turns ratio  Np:Ns = %.2f : 1', r.turns_ratio);
    lines{end+1} = sprintf('  (Ns/Np = %.4f)', r.ns_np);
    lines{end+1} = '';
    lines{end+1} = sprintf('Duty cycle:');
    lines{end+1} = sprintf('  at Vin_min (%g V): D = %.3f', c.vin_min, r.duty_min_vin);
    lines{end+1} = sprintf('  at Vin_nom (%g V): D = %.3f', r.vin_nom, r.duty_nom);
    lines{end+1} = sprintf('  at Vin_max (%g V): D = %.3f', c.vin_max, r.duty_max_vin);
    lines{end+1} = '';
    lines{end+1} = sprintf('Magnetizing inductance  Lm = %.1f uH', r.Lm_uH);
    lines{end+1} = sprintf('Output inductor        Lout = %.1f uH', r.Lout_uH);
    lines{end+1} = '';
    lines{end+1} = sprintf('Primary RMS current   = %.2f A', r.i_pri_rms);
    lines{end+1} = sprintf('Secondary RMS current = %.2f A', r.i_sec_rms);
    lines{end+1} = sprintf('Magnetizing Ipk       = %.3f A', r.i_mag_peak);
    lines{end+1} = '';
    lines{end+1} = sprintf('Output power  = %.1f W', r.pout_nom);
    lines{end+1} = sprintf('Input power   = %.1f W (at %.0f%% eff.)', r.pin_nom, c.efficiency);
    lines{end+1} = sprintf('Frequency     = %g kHz', c.fsw_khz);

    set(data.txt_requirements, 'String', strjoin(lines, char(10)));

end


% ===============================================================
% MAS FILE PARSING
% ===============================================================

function summary = build_mas_summary(mas)
    lines = {};

    % Check for inputs section
    if isfield(mas, 'inputs')
        inp = mas.inputs;
        lines{end+1} = '--- Inputs ---';

        if isfield(inp, 'designRequirements')
            dr = inp.designRequirements;
            if isfield(dr, 'topology')
                lines{end+1} = sprintf('Topology: %s', stringify(dr.topology));
            end
            if isfield(dr, 'magnetizingInductance')
                mi = dr.magnetizingInductance;
                if isfield(mi, 'nominal')
                    lines{end+1} = sprintf('Magnetizing Inductance (nom): %.2f uH', mi.nominal * 1e6);
                end
            end
            if isfield(dr, 'turnsRatios') && ~isempty(dr.turnsRatios)
                for k = 1:numel(dr.turnsRatios)
                    tr = dr.turnsRatios(k);
                    if isfield(tr, 'nominal')
                        lines{end+1} = sprintf('Turns ratio %d: %.3f', k, tr.nominal);
                    end
                end
            end
        end

        if isfield(inp, 'operatingPoints')
            n_ops = numel(inp.operatingPoints);
            lines{end+1} = sprintf('Operating points: %d', n_ops);
        end
        lines{end+1} = '';
    end

    % Check for magnetic section
    if isfield(mas, 'magnetic')
        mag = mas.magnetic;
        lines{end+1} = '--- Magnetic (Physical Design) ---';

        if isfield(mag, 'core')
            core = mag.core;
            if isfield(core, 'functionalDescription')
                fd = core.functionalDescription;
                if isfield(fd, 'shape') && isfield(fd.shape, 'name')
                    lines{end+1} = sprintf('Core shape: %s', fd.shape.name);
                end
                if isfield(fd, 'material')
                    lines{end+1} = sprintf('Material: %s', stringify(fd.material));
                end
                if isfield(fd, 'gapping') && ~isempty(fd.gapping)
                    lines{end+1} = sprintf('Gaps: %d', numel(fd.gapping));
                end
            end
        end

        if isfield(mag, 'coil')
            coil = mag.coil;
            if isfield(coil, 'functionalDescription')
                fd = coil.functionalDescription;
                n_w = numel(fd);
                lines{end+1} = sprintf('Windings: %d', n_w);
                for k = 1:n_w
                    w = fd(k);
                    name = '';
                    if isfield(w, 'name'), name = w.name; end
                    nt = 0;
                    if isfield(w, 'numberTurns'), nt = w.numberTurns; end
                    lines{end+1} = sprintf('  %s: %d turns', name, nt);
                end
            end
        end
        lines{end+1} = '';
    end

    % Check for outputs section
    if isfield(mas, 'outputs')
        lines{end+1} = '--- Outputs ---';
        lines{end+1} = '(Loss/thermal data available)';
    end

    if isempty(lines)
        lines{1} = 'File loaded but no recognized MAS sections found.';
    end

    summary = strjoin(lines, char(10));
end


function s = stringify(val)
    if ischar(val)
        s = val;
    elseif isnumeric(val)
        s = num2str(val);
    elseif iscell(val)
        s = strjoin(cellfun(@stringify, val, 'UniformOutput', false), ', ');
    else
        s = '(complex)';
    end
end


% ===============================================================
% BUILD design_spec FROM CURRENT STATE
% ===============================================================

function spec = build_design_spec_wizard(data)
    % Build design_spec struct from wizard state

    spec = struct();
    spec.source = 'wizard';
    spec.topology = data.topology;

    % Converter specs
    spec.converter = data.converter;
    spec.converter.fsw_hz = data.converter.fsw_khz * 1e3;

    % Computed requirements
    spec.requirements = data.requirements;

    % Operating points will be generated by the Python script
    spec.operating_points = [];

    % Recommendation (if user selected one)
    spec.recommendation = struct();
    if data.rec.selected_idx > 0 && data.rec.selected_idx <= numel(data.rec.results)
        spec.recommendation = data.rec.results{data.rec.selected_idx};
    end

    % Insulation
    spec.insulation = data.insulation;

    % Thermal
    spec.thermal = data.thermal;
end


function spec = build_design_spec_mas(data)
    % Build design_spec from imported MAS file

    spec = struct();
    spec.source = 'mas_import';
    spec.topology = '';
    spec.mas_content = data.mas.content;

    mas = data.mas.content;

    % Extract what we can from MAS
    spec.converter = struct();
    spec.requirements = struct();
    spec.recommendation = struct();
    spec.insulation = data.insulation;  % use defaults
    spec.thermal = data.thermal;

    if isfield(mas, 'inputs') && isfield(mas.inputs, 'designRequirements')
        dr = mas.inputs.designRequirements;
        if isfield(dr, 'topology')
            spec.topology = dr.topology;
        end
        if isfield(dr, 'magnetizingInductance') && isfield(dr.magnetizingInductance, 'nominal')
            spec.requirements.Lm_uH = dr.magnetizingInductance.nominal * 1e6;
        end
        if isfield(dr, 'turnsRatios') && ~isempty(dr.turnsRatios)
            spec.requirements.turns_ratio = dr.turnsRatios(1).nominal;
        end
    end

    % Extract physical design if present
    if isfield(mas, 'magnetic')
        mag = mas.magnetic;
        if isfield(mag, 'core') && isfield(mag.core, 'functionalDescription')
            fd = mag.core.functionalDescription;
            if isfield(fd, 'shape') && isfield(fd.shape, 'name')
                spec.recommendation.core_shape = fd.shape.name;
            end
            if isfield(fd, 'material')
                spec.recommendation.core_material = stringify(fd.material);
            end
            if isfield(fd, 'gapping')
                spec.recommendation.gapping = fd.gapping;
            end
        end
        if isfield(mag, 'coil') && isfield(mag.coil, 'functionalDescription')
            wds = mag.coil.functionalDescription;
            spec.recommendation.windings = [];
            for k = 1:numel(wds)
                w = wds(k);
                wd = struct();
                if isfield(w, 'name'), wd.name = w.name; end
                if isfield(w, 'numberTurns'), wd.n_turns = w.numberTurns; end
                if isfield(w, 'numberParallels'), wd.n_parallels = w.numberParallels; end
                if isfield(w, 'wire'), wd.wire = w.wire; end
                if isempty(spec.recommendation.windings)
                    spec.recommendation.windings = wd;
                else
                    spec.recommendation.windings(end+1) = wd;
                end
            end
        end
    end

    % Extract operating points if present
    if isfield(mas, 'inputs') && isfield(mas.inputs, 'operatingPoints')
        spec.operating_points = mas.inputs.operatingPoints;
    else
        spec.operating_points = [];
    end
end


function spec = build_design_spec_manual(data)
    % Build design_spec from manual requirements entry

    spec = struct();
    spec.source = 'manual';
    spec.topology = '';

    spec.converter = struct();
    spec.converter.fsw_hz = data.manual.fsw_khz * 1e3;

    spec.requirements = struct();
    spec.requirements.Lm_uH = data.manual.Lm_uH;
    spec.requirements.turns_ratio = data.manual.turns_ratio;
    spec.requirements.n_windings = data.manual.n_windings;
    spec.requirements.fsw_hz = data.manual.fsw_khz * 1e3;

    spec.recommendation = struct();
    spec.insulation = data.insulation;
    spec.thermal = data.thermal;
    spec.operating_points = [];
end


% ===============================================================
% CONTINUE / LAUNCH CALLBACKS
% ===============================================================

function cb_continue_wizard(~, ~)
    fig = gcbf();
    data = guidata(fig);

    % Validate required fields
    c = data.converter;
    if c.vin_min <= 0 || c.vin_max <= 0 || c.vout <= 0 || c.iout <= 0 || c.fsw_khz <= 0
        errordlg('Please fill in all required converter specifications.', 'Missing Data');
        return;
    end
    if c.vin_min >= c.vin_max
        errordlg('Input voltage min must be less than max.', 'Invalid Data');
        return;
    end

    spec = build_design_spec_wizard(data);
    launch_winding_designer(spec);
end


function cb_continue_mas(~, ~)
    fig = gcbf();
    data = guidata(fig);

    if ~data.mas.loaded
        errordlg('No MAS file loaded.', 'Missing Data');
        return;
    end

    spec = build_design_spec_mas(data);
    launch_winding_designer(spec);
end


function cb_continue_manual(~, ~)
    fig = gcbf();
    data = guidata(fig);

    if data.manual.Lm_uH <= 0
        errordlg('Please enter a valid magnetizing inductance.', 'Missing Data');
        return;
    end

    spec = build_design_spec_manual(data);
    launch_winding_designer(spec);
end


function launch_winding_designer(spec)
    % Launch interactive_winding_designer with the design_spec
    fprintf('Launching winding designer with design_spec (source: %s)...\n', spec.source);
    interactive_winding_designer(spec);
end


% ===============================================================
% RECOMMENDATIONS (PyOpenMagnetics Advisor)
% ===============================================================

function cb_get_recommendations(~, ~)
    fig = gcbf();
    data = guidata(fig);

    % Validate required fields first
    c = data.converter;
    if c.vin_min <= 0 || c.vin_max <= 0 || c.vout <= 0 || c.iout <= 0 || c.fsw_khz <= 0
        errordlg('Please fill in all required converter specifications.', 'Missing Data');
        return;
    end

    set(data.btn_get_recs, 'String', 'Computing...', 'Enable', 'off');
    drawnow();

    try
        % Build config for Python script
        config = build_recommendation_config(data);

        % Use relative filenames to avoid Octave MSYS path mangling in system() calls
        script_dir = pwd();
        config_file = 'om_recommendation_config.json';
        output_file = 'om_recommendation_results.json';
        py_script = 'generate_om_recommendations.py';
        config_path = fullfile(script_dir, config_file);
        output_path = fullfile(script_dir, output_file);
        config.output_file = strrep(output_path, '\', '/');

        % Write JSON config
        fid = fopen(config_path, 'w', 'n', 'UTF-8');
        fprintf(fid, '%s', jsonencode(config));
        fclose(fid);

        % Verify script exists
        if ~exist(fullfile(script_dir, py_script), 'file')
            error('Python script "%s" not found in %s', py_script, script_dir);
        end

        % Find Python - check venv first, then fallback chain
        python_cmd = 'python';
        venv_python = fullfile(script_dir, '.venv', 'Scripts', 'python.exe');
        if exist(venv_python, 'file')
            python_cmd = ['"' strrep(venv_python, '\', '/') '"'];
        end

        cmd = sprintf('%s "%s" "%s" 2>&1', python_cmd, py_script, config_file);
        fprintf('[WIZARD] Running: %s\n', cmd);
        [status, output] = system(cmd);
        fprintf('[WIZARD] Status: %d, Output: %s\n', status, strtrim(output));

        % Check for module import errors
        is_module_error = ~isempty(strfind(output, 'ModuleNotFoundError')) || ...
                          ~isempty(strfind(output, 'ImportError')) || ...
                          ~isempty(strfind(output, 'No module named'));

        % Fallback 1: Try Windows Python Launcher (py)
        if status ~= 0 && is_module_error && ispc
            fprintf('[WIZARD] Standard python failed. Trying ''py'' launcher...\n');
            cmd_fb = sprintf('py "%s" "%s" 2>&1', py_script, config_file);
            [status_fb, output_fb] = system(cmd_fb);
            fprintf('[WIZARD] py launcher exit=%d, output: %s\n', status_fb, strtrim(output_fb));
            if status_fb == 0
                status = status_fb;
                output = output_fb;
                fprintf('[WIZARD] Success using ''py'' launcher.\n');
            end
        end

        % Fallback 2: Try specific python paths from 'where python'
        if status ~= 0 && is_module_error && ispc
            [~, py_paths_str] = system('where python');
            py_paths = strsplit(strtrim(py_paths_str), char(10));
            for i = 1:length(py_paths)
                p = strtrim(py_paths{i});
                if isempty(p); continue; end
                % Skip Octave bundled python
                if ~isempty(strfind(lower(p), 'octave')) || ~isempty(strfind(lower(p), 'usr\bin'))
                    continue;
                end
                % Convert backslashes for MSYS shell compatibility
                p = strrep(p, '\', '/');
                fprintf('[WIZARD] Trying alternative python: %s\n', p);
                cmd_alt = sprintf('"%s" "%s" "%s" 2>&1', p, py_script, config_file);
                [status_alt, output_alt] = system(cmd_alt);
                fprintf('[WIZARD] Alt python exit=%d, output: %s\n', status_alt, strtrim(output_alt));
                if status_alt == 0
                    status = status_alt;
                    output = output_alt;
                    fprintf('[WIZARD] Success using alternative python.\n');
                    break;
                end
            end
        end

        if status ~= 0
            error('Python script failed: %s', output);
        end

        % Load results
        fid = fopen(output_path, 'r', 'n', 'UTF-8');
        raw = fread(fid, '*char')';
        fclose(fid);
        results = jsondecode(raw);

        if isfield(results, 'status') && ~strcmp(results.status, 'OK')
            error('Recommendation failed: %s', results.error);
        end

        % Display recommendations in a selection dialog
        data = display_recommendations(data, results);

    catch err
        errordlg(sprintf('Recommendation failed:\n%s', err.message), 'Error');
    end

    set(data.btn_get_recs, 'String', 'Get Recommendations', 'Enable', 'on');
    guidata(fig, data);
end


function config = build_recommendation_config(data)
    % Build JSON config for generate_om_recommendations.py

    r = data.requirements;
    c = data.converter;

    config = struct();
    config.mode = 'recommend';
    config.topology = 'two_switch_forward';
    config.max_results = data.rec.n_results;

    config.weights = struct();
    config.weights.COST = data.rec.weight_cost;
    config.weights.LOSSES = data.rec.weight_losses;
    config.weights.DIMENSIONS = data.rec.weight_dimensions;

    % Design requirements (MAS format)
    config.design_requirements = struct();
    config.design_requirements.topology = 'Two Switch Forward Converter';

    % Magnetizing inductance with ±20% tolerance
    config.design_requirements.magnetizingInductance = struct();
    config.design_requirements.magnetizingInductance.nominal = r.Lm_uH * 1e-6;
    config.design_requirements.magnetizingInductance.minimum = r.Lm_uH * 0.8 * 1e-6;
    config.design_requirements.magnetizingInductance.maximum = r.Lm_uH * 1.2 * 1e-6;

    % Turns ratio with ±5% tolerance
    config.design_requirements.turnsRatios = struct( ...
        'nominal', r.turns_ratio, ...
        'minimum', r.turns_ratio * 0.95, ...
        'maximum', r.turns_ratio * 1.05);

    % Operating temperature (ambient + max rise)
    max_op_temp = data.thermal.ambient_temp + data.thermal.max_rise;
    config.design_requirements.operatingTemperature = struct('maximum', max_op_temp);

    % Insulation requirements — all 7 fields required by PyOpenMagnetics advisor
    config.design_requirements.insulation = struct();
    config.design_requirements.insulation.insulationType = data.insulation.class;
    config.design_requirements.insulation.pollutionDegree = sprintf('P%d', data.insulation.pollution_degree);
    config.design_requirements.insulation.overvoltageCategory = sprintf('OVC-%s', data.insulation.overvoltage_cat);
    config.design_requirements.insulation.standards = {data.insulation.standard};
    config.design_requirements.insulation.cti = data.insulation.cti;
    config.design_requirements.insulation.altitude = struct('maximum', data.insulation.altitude_max);
    % mainSupplyVoltage from converter Vin range (RMS for DC ≈ DC value)
    config.design_requirements.insulation.mainSupplyVoltage = struct( ...
        'nominal', r.vin_nom, ...
        'minimum', c.vin_min, ...
        'maximum', c.vin_max);

    % Maximum dimensions (optional, mm → m)
    has_dims = false;
    dims = struct();
    if ~isempty(data.constraints.max_width_mm)
        dims.width = data.constraints.max_width_mm * 1e-3;
        has_dims = true;
    end
    if ~isempty(data.constraints.max_height_mm)
        dims.height = data.constraints.max_height_mm * 1e-3;
        has_dims = true;
    end
    if ~isempty(data.constraints.max_depth_mm)
        dims.depth = data.constraints.max_depth_mm * 1e-3;
        has_dims = true;
    end
    if has_dims
        config.design_requirements.maximumDimensions = dims;
    end

    % --- Operating points (nominal + worst-case) ---
    config.operating_points = {};

    % Nominal operating point
    nom_op = struct();
    nom_op.name = 'nominal';
    nom_op.frequency_hz = r.fsw_hz;
    nom_op.duty = r.duty_nom;
    nom_op.ambient_temperature = data.thermal.ambient_temp;
    nom_op.vin = r.vin_nom;
    nom_op.windings = {};
    % Primary: Triangular current (magnetizing ramp), Rectangular voltage
    nom_op.windings{1} = struct();
    nom_op.windings{1}.name = 'Primary';
    nom_op.windings{1}.waveform_label = 'Triangular';
    nom_op.windings{1}.i_pp = r.i_mag_pp;           % magnetizing ripple pk-pk
    nom_op.windings{1}.i_offset = r.i_pri_rms;       % average primary current as offset
    nom_op.windings{1}.v_pp = r.vin_nom;              % two-switch forward: pk-pk = Vin
    nom_op.windings{1}.v_offset = 0;
    % Secondary: Rectangular current, Rectangular voltage
    nom_op.windings{2} = struct();
    nom_op.windings{2}.name = 'Secondary';
    nom_op.windings{2}.waveform_label = 'Rectangular';
    nom_op.windings{2}.rms_current_a = r.i_sec_rms;
    nom_op.windings{2}.rms_voltage_v = c.vout;
    config.operating_points{1} = nom_op;

    % Worst-case operating point (Vin_min, max duty, max stress)
    worst_op = struct();
    worst_op.name = 'worst_case';
    worst_op.frequency_hz = r.fsw_hz;
    worst_op.duty = r.duty_min_vin;
    worst_op.ambient_temperature = data.thermal.ambient_temp;
    worst_op.vin = c.vin_min;
    worst_op.windings = {};
    % Primary worst-case
    worst_op.windings{1} = struct();
    worst_op.windings{1}.name = 'Primary';
    worst_op.windings{1}.waveform_label = 'Triangular';
    worst_op.windings{1}.i_pp = r.i_mag_pp_worst;
    worst_op.windings{1}.i_offset = r.i_pri_rms_worst;
    worst_op.windings{1}.v_pp = c.vin_min;
    worst_op.windings{1}.v_offset = 0;
    % Secondary worst-case
    worst_op.windings{2} = struct();
    worst_op.windings{2}.name = 'Secondary';
    worst_op.windings{2}.waveform_label = 'Rectangular';
    worst_op.windings{2}.rms_current_a = r.i_sec_rms_worst;
    worst_op.windings{2}.rms_voltage_v = c.vout;
    config.operating_points{2} = worst_op;

    % Legacy single operating point (backward compat)
    config.operating_point = struct();
    config.operating_point.frequency_hz = r.fsw_hz;
    config.operating_point.duty = r.duty_nom;
    config.operating_point.n_windings = 2;
    config.operating_point.ambient_temperature = data.thermal.ambient_temp;

    config.samples_per_period = 512;

end


function data = display_recommendations(data, results)
    % Show recommendation results in a dialog for selection

    if ~isfield(results, 'recommendations') || isempty(results.recommendations)
        msgbox('No recommendations returned.', 'Results');
        return;
    end

    recs = results.recommendations;
    n = numel(recs);

    % Ensure highest-scoring recommendations are shown first (UI weighted score)
    ui_scores = zeros(n, 1);
    for k = 1:n
        if isfield(recs(k), 'ui_score')
            ui_scores(k) = double(recs(k).ui_score);
        elseif isfield(recs(k), 'ui_weighted_score')
            ui_scores(k) = double(recs(k).ui_weighted_score);
        elseif isfield(recs(k), 'raw_score')
            ui_scores(k) = double(recs(k).raw_score);
        elseif isfield(recs(k), 'score')
            ui_scores(k) = double(recs(k).score);
        end
    end
    [~, order] = sort(ui_scores, 'descend');
    recs = recs(order);
    raw_scores = ui_scores(order);

    % Build display strings
    items = cell(n, 1);
    max_raw = max(raw_scores);
    if max_raw <= 0
        max_raw = 1;
    end
    for k = 1:n
        r = recs(k);
        core_name = '?';
        material = '?';
        turns = '?';
        raw_score = 0;
        ui_score = NaN;
        total_loss = 0;
        core_loss = 0;
        winding_loss = 0;
        has_losses = false;

        if isfield(r, 'core_shape'), core_name = r.core_shape; end
        if isfield(r, 'material'), material = r.material; end
        if isfield(r, 'primary_turns') && isfield(r, 'secondary_turns')
            turns = sprintf('%d/%d', r.primary_turns, r.secondary_turns);
        elseif isfield(r, 'primary_turns')
            turns = sprintf('%d', r.primary_turns);
        end
        if isfield(r, 'raw_score')
            raw_score = r.raw_score;
        elseif isfield(r, 'score')
            raw_score = r.score;
        end
        if isfield(r, 'ui_score')
            ui_score = r.ui_score;
        elseif isfield(r, 'weighted_score')
            ui_score = r.weighted_score;
        end
        if isfield(r, 'total_losses_w')
            total_loss = double(r.total_losses_w);
        end
        if isfield(r, 'core_losses_w')
            core_loss = double(r.core_losses_w);
        end
        if isfield(r, 'winding_losses_w')
            winding_loss = double(r.winding_losses_w);
        end
        has_losses = (total_loss > 0);

        rel_pct = 100 * raw_score / max_raw;

        % Build the display line
        line = sprintf('#%d  %s  |  %s  |  Turns: %s', k, core_name, material, turns);
        if has_losses
            line = sprintf('%s  |  OM Loss: %.2fW (Core:%.2f + Wind:%.2f)', ...
                           line, total_loss, core_loss, winding_loss);
        end
        line = sprintf('%s  |  Score: %.0f pts (%.0f%%)', line, raw_score * 100, rel_pct);
        items{k} = line;
    end

    [sel, ok] = listdlg('ListString', items, ...
                         'SelectionMode', 'single', ...
                         'Name', 'Select Design Recommendation', ...
                         'ListSize', [1100, 320], ...
                         'PromptString', 'Choose a recommended design (losses via OpenMagnetics Core + Winding calculation):');

    if ok && ~isempty(sel)
        data.rec.selected_idx = sel;
        % Convert to cell array if struct array
        if isstruct(recs)
            rec_cell = cell(n, 1);
            for k = 1:n
                rec_cell{k} = recs(k);
            end
            data.rec.results = rec_cell;
        else
            data.rec.results = recs;
        end

        msgbox(sprintf('Selected recommendation #%d: %s', sel, items{sel}), 'Selection');
    end

end


% ===============================================================
% PYTHON HELPER
% ===============================================================

function python_cmd = find_python()
    % Find a working Python executable

    candidates = {'python', 'python3', 'py'};
    for k = 1:numel(candidates)
        [status, ~] = system(sprintf('"%s" --version', candidates{k}));
        if status == 0
            python_cmd = candidates{k};
            return;
        end
    end

    % Try Windows-specific 'where python'
    [status, output] = system('where python');
    if status == 0
        lines = strsplit(strtrim(output), char(10));
        for k = 1:numel(lines)
            path = strtrim(lines{k});
            if ~isempty(path)
                python_cmd = path;
                return;
            end
        end
    end

    error('Could not find Python executable. Please ensure Python is installed and on PATH.');
end
