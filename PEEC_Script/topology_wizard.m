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

    % Topology wizard defaults
    data.topology = 'two_switch_forward';  % key name
    data.topology_display = 'Two-Switch Forward Converter';  % display name
    data.design_mode = 'auto';  % 'auto' or 'advanced'
    data.n_outputs = 1;  % for isolated topologies

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

    % MAS inputs (from Python topology calculator)
    data.mas_inputs = struct();  % populated by generate_om_topology.py

    % Recommendation settings
    data.rec.n_results = 5;
    data.rec.weight_cost = 1/3;
    data.rec.weight_losses = 1/3;
    data.rec.weight_dimensions = 1/3;
    data.rec.wire_family_mode = 'auto_all';  % auto_all | round_litz_rect | foil_planar
    data.rec.results = {};       % cell array of result structs
    data.rec.selected_idx = 0;   % index of selected recommendation
    data.rec.cores_in_stock = false;  % false = all cores, true = in-stock only

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
    spec_title = sprintf('%s - Converter Specifications', data.topology_display);
    spec_panel = uipanel('Parent', panel, ...
                         'Position', [0.01 0.01 0.48 0.98], ...
                         'Title', spec_title, ...
                         'FontSize', 10, 'FontWeight', 'bold');

    % --- Topology Selection & Design Mode ---
    make_label(spec_panel, 'Converter Topology', [0.02 0.93 0.35 0.04]);
    data.pop_topology = uicontrol('Parent', spec_panel, 'Style', 'popupmenu', ...
              'String', {'Two-Switch Forward', 'Single-Switch Forward', 'Active Clamp Forward', ...
                        'Flyback', 'Push-Pull', 'Buck', 'Boost', 'Isolated Buck', 'Isolated Buck-Boost'}, ...
              'Units', 'normalized', ...
              'Position', [0.38 0.93 0.60 0.045], ...
              'Value', 1, ...
              'Tag', 'topology_popup', ...
              'Callback', @cb_topology_changed);

    % Design mode: Auto or Advanced
    make_label(spec_panel, 'Design Mode', [0.02 0.87 0.35 0.04]);
    data.radio_auto = uicontrol('Parent', spec_panel, 'Style', 'radiobutton', ...
              'String', 'Help me (Auto)', ...
              'Units', 'normalized', ...
              'Position', [0.38 0.87 0.20 0.045], ...
              'Value', 1, ...
              'Tag', 'design_mode_auto', ...
              'Callback', @cb_design_mode_changed);
    data.radio_advanced = uicontrol('Parent', spec_panel, 'Style', 'radiobutton', ...
              'String', 'I know (Advanced)', ...
              'Units', 'normalized', ...
              'Position', [0.60 0.87 0.20 0.045], ...
              'Value', 0, ...
              'Tag', 'design_mode_advanced', ...
              'Callback', @cb_design_mode_changed);

    % Number of outputs spinner (for isolated topologies)
    make_label(spec_panel, 'Outputs', [0.02 0.81 0.35 0.04]);
    data.edit_n_outputs = make_edit(spec_panel, num2str(data.n_outputs), ...
                                     [0.38 0.81 0.10 0.045], @cb_n_outputs);
    data.btn_n_outputs_plus = uicontrol('Parent', spec_panel, 'Style', 'pushbutton', ...
              'String', '+', ...
              'Units', 'normalized', ...
              'Position', [0.49 0.81 0.05 0.045], ...
              'FontSize', 8, ...
              'Callback', @cb_n_outputs_plus);
    data.btn_n_outputs_minus = uicontrol('Parent', spec_panel, 'Style', 'pushbutton', ...
              'String', '-', ...
              'Units', 'normalized', ...
              'Position', [0.55 0.81 0.05 0.045], ...
              'FontSize', 8, ...
              'Callback', @cb_n_outputs_minus);

    % Compute button (trigger topology requirements calculation)
    data.btn_compute = uicontrol('Parent', spec_panel, 'Style', 'pushbutton', ...
              'String', 'Compute Requirements', ...
              'Units', 'normalized', ...
              'Position', [0.38 0.75 0.60 0.045], ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.0 0.5 0.7], ...
              'ForegroundColor', 'w', ...
              'Callback', @cb_compute_topology);

    % --- Output Specification Table (for multi-output topologies) ---
    output_title = uicontrol('Parent', spec_panel, 'Style', 'text', ...
              'String', 'Output Specification', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.68 0.96 0.04], ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'ForegroundColor', [0.0 0.6 0.6], ...
              'HorizontalAlignment', 'left');

    % Output 1
    data.output1_label = make_label(spec_panel, 'Output 1:', [0.02 0.62 0.15 0.04]);
    data.output1_v = make_edit(spec_panel, '5.0', [0.18 0.62 0.15 0.045], @cb_output_v);
    make_label(spec_panel, 'V', [0.34 0.62 0.05 0.04]);
    data.output1_i = make_edit(spec_panel, '5.0', [0.40 0.62 0.15 0.045], @cb_output_i);
    make_label(spec_panel, 'A', [0.56 0.62 0.05 0.04]);

    % Output 2 (hidden by default for single-output topologies)
    data.output2_label = make_label(spec_panel, 'Output 2:', [0.02 0.56 0.15 0.04], 'off');
    data.output2_v = make_edit(spec_panel, '3.3', [0.18 0.56 0.15 0.045], @cb_output_v, 'off');
    make_label(spec_panel, 'V', [0.34 0.56 0.05 0.04], 'off');
    data.output2_i = make_edit(spec_panel, '2.0', [0.40 0.56 0.15 0.045], @cb_output_i, 'off');
    make_label(spec_panel, 'A', [0.56 0.56 0.05 0.04], 'off');

    % Output 3 (hidden by default)
    data.output3_label = make_label(spec_panel, 'Output 3:', [0.02 0.50 0.15 0.04], 'off');
    data.output3_v = make_edit(spec_panel, '12.0', [0.18 0.50 0.15 0.045], @cb_output_v, 'off');
    make_label(spec_panel, 'V', [0.34 0.50 0.05 0.04], 'off');
    data.output3_i = make_edit(spec_panel, '1.0', [0.40 0.50 0.15 0.045], @cb_output_i, 'off');
    make_label(spec_panel, 'A', [0.56 0.50 0.05 0.04], 'off');

    % Output 4 (hidden by default)
    data.output4_label = make_label(spec_panel, 'Output 4:', [0.02 0.44 0.15 0.04], 'off');
    data.output4_v = make_edit(spec_panel, '5.0', [0.18 0.44 0.15 0.045], @cb_output_v, 'off');
    make_label(spec_panel, 'V', [0.34 0.44 0.05 0.04], 'off');
    data.output4_i = make_edit(spec_panel, '1.0', [0.40 0.44 0.15 0.045], @cb_output_i, 'off');
    make_label(spec_panel, 'A', [0.56 0.44 0.05 0.04], 'off');

    % --- Required fields ---
    req_label = uicontrol('Parent', spec_panel, 'Style', 'text', ...
              'String', 'Required Specifications', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.40 0.96 0.04], ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'ForegroundColor', [0.0 0.6 0.6], ...
              'HorizontalAlignment', 'left');

    y = 0.34;
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

    % ----- RIGHT TOP: Computed Requirements -----
    req_panel = uipanel('Parent', panel, ...
                        'Position', [0.50 0.55 0.49 0.44], ...
                        'Title', 'Computed Design Requirements', ...
                        'FontSize', 10, 'FontWeight', 'bold');

    data.txt_requirements = uicontrol('Parent', req_panel, 'Style', 'text', ...
              'String', '(computing...)', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.02 0.96 0.94], ...
              'FontSize', 10, ...
              'HorizontalAlignment', 'left', ...
              'Max', 2);  % multi-line

    % ----- RIGHT MIDDLE: Waveforms Visualization -----
    waveform_panel = uipanel('Parent', panel, ...
                             'Position', [0.50 0.30 0.49 0.24], ...
                             'Title', 'Topology Waveforms', ...
                             'FontSize', 10, 'FontWeight', 'bold');

    data.ax_waveforms = axes('Parent', waveform_panel, ...
                             'Units', 'normalized', ...
                             'Position', [0.05 0.05 0.90 0.90]);
    cla(data.ax_waveforms);
    text(0.5, 0.5, 'Click "Compute Requirements" to see waveforms', ...
         'Parent', data.ax_waveforms, ...
         'HorizontalAlignment', 'center', ...
         'VerticalAlignment', 'middle', ...
         'FontSize', 10, ...
         'Color', [0.5 0.5 0.5]);
    axis(data.ax_waveforms, 'off');

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

    % Preferred wire family
    make_label(rec_panel, 'Wire family mode', [0.62 0.75 0.20 0.15]);
    data.pop_wire_family = uicontrol('Parent', rec_panel, 'Style', 'popupmenu', ...
              'String', {'Auto (All)', 'Round/Litz/Rectangular', 'Foil/Planar'}, ...
              'Units', 'normalized', ...
              'Position', [0.80 0.76 0.18 0.14], ...
              'Value', 1, ...
              'Callback', @cb_wire_family_mode);

    % Cores in stock toggle
    data.chk_cores_in_stock = uicontrol('Parent', rec_panel, 'Style', 'checkbox', ...
              'String', 'In-stock cores only', ...
              'Units', 'normalized', ...
              'Position', [0.62 0.62 0.36 0.12], ...
              'Value', 0, ...
              'FontSize', 8, ...
              'TooltipString', 'When checked, only cores marked as in-stock are considered', ...
              'Callback', @cb_cores_in_stock);

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

    % Results count label
    data.txt_rec_count = uicontrol('Parent', rec_panel, 'Style', 'text', ...
              'String', 'Results: (awaiting compute)', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.40 0.96 0.10], ...
              'FontSize', 8, ...
              'HorizontalAlignment', 'center', ...
              'ForegroundColor', [0.3 0.3 0.3]);

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

function h = make_label(parent, str, pos, vis)
    if nargin < 4
        vis = 'on';
    end
    h = uicontrol('Parent', parent, 'Style', 'text', ...
                  'String', str, ...
                  'Units', 'normalized', ...
                  'Position', pos, ...
                  'HorizontalAlignment', 'left', ...
                  'FontSize', 9, ...
                  'Visible', vis);
end

function h = make_edit(parent, str, pos, cb, vis)
    if nargin < 5
        vis = 'on';
    end
    h = uicontrol('Parent', parent, 'Style', 'edit', ...
                  'String', str, ...
                  'Units', 'normalized', ...
                  'Position', pos, ...
                  'FontSize', 9, ...
                  'Callback', cb, ...
                  'Visible', vis);
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


function cb_output_v(src, ~)
    % Callback for multi-output voltage fields (output1_v, output2_v, etc.)
    fig = gcbf();
    data = guidata(fig);
    % Just validate that it's a positive number, don't recompute
    val = str2double(get(src, 'String'));
    if isnan(val) || val <= 0
        set(src, 'String', '0');
    end
end


function cb_output_i(src, ~)
    % Callback for multi-output current fields (output1_i, output2_i, etc.)
    fig = gcbf();
    data = guidata(fig);
    % Just validate that it's a positive number, don't recompute
    val = str2double(get(src, 'String'));
    if isnan(val) || val <= 0
        set(src, 'String', '0');
    end
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

function cb_wire_family_mode(src, ~)
    fig = gcbf();
    data = guidata(fig);
    v = get(src, 'Value');
    switch v
        case 2
            data.rec.wire_family_mode = 'round_litz_rect';
        case 3
            data.rec.wire_family_mode = 'foil_planar';
        otherwise
            data.rec.wire_family_mode = 'auto_all';
    end
    guidata(fig, data);
end

function cb_cores_in_stock(src, ~)
    fig = gcbf();
    data = guidata(fig);
    data.rec.cores_in_stock = logical(get(src, 'Value'));
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
% TOPOLOGY SELECTION CALLBACKS
% ===============================================================

function cb_topology_changed(src, ~)
    % [TOPOLOGY] Enhanced callback: dynamic field visibility on topology selection
    fig = gcbf();
    data = guidata(fig);

    % Map selection index to topology key
    topology_keys = {'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', ...
                     'flyback', 'push_pull', 'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'};
    topology_names = {'Two-Switch Forward Converter', 'Single-Switch Forward Converter', ...
                      'Active Clamp Forward Converter', 'Flyback Converter', 'Push-Pull Converter', ...
                      'Buck Converter', 'Boost Converter', 'Isolated Buck Converter', ...
                      'Isolated Buck-Boost Converter'};

    idx = get(src, 'Value');
    if idx >= 1 && idx <= numel(topology_keys)
        data.topology = topology_keys{idx};
        data.topology_display = topology_names{idx};
    end

    % Save updated data BEFORE calling update functions
    guidata(fig, data);

    % [PHASE 3.2] Update field visibility based on topology
    % This calls new enhanced visibility function
    fprintf('[TOPOLOGY] Topology changed to: %s (%s)\n', data.topology_display, data.topology);
    update_field_visibility(fig, data.topology);
    data = guidata(fig);  % Refresh in case visibility function updated it

    % Update spec panel title
    spec_panel = findobj(fig, 'Type', 'uipanel', '-regexp', 'Title', '.*Converter Specifications');
    if ~isempty(spec_panel)
        spec_title = sprintf('%s - Converter Specifications', data.topology_display);
        set(spec_panel(1), 'Title', spec_title);
    end

    % Update computed design requirements display
    if isfield(data, 'requirements') && isstruct(data.requirements)
        update_topology_requirements_display(data, data.requirements);
    end

    guidata(fig, data);
end


function cb_design_mode_changed(src, ~)
    fig = gcbf();
    data = guidata(fig);

    tag = get(src, 'Tag');
    if strcmp(tag, 'design_mode_auto')
        data.design_mode = 'auto';
        set(findobj(fig, 'Tag', 'design_mode_auto'), 'Value', 1);
        set(findobj(fig, 'Tag', 'design_mode_advanced'), 'Value', 0);
    else
        data.design_mode = 'advanced';
        set(findobj(fig, 'Tag', 'design_mode_auto'), 'Value', 0);
        set(findobj(fig, 'Tag', 'design_mode_advanced'), 'Value', 1);
    end

    guidata(fig, data);
end


function cb_n_outputs(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val >= 1 && val <= 4
        data.n_outputs = round(val);
        % Rebuild output table when user changes spinner
        topology_key = get(data.pop_topology, 'Value');
        topology_names = {'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', ...
                         'flyback', 'push_pull', 'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'};
        if topology_key > 0 && topology_key <= length(topology_names)
            topo_key = topology_names{topology_key};
            metadata = get_topology_metadata(topo_key);
            output_type = metadata.output_type;
            rebuild_output_spec_table(fig, topo_key, output_type);
        end
    else
        set(src, 'String', num2str(data.n_outputs));
    end
    guidata(fig, data);
end


function cb_n_outputs_plus(~, ~)
    fig = gcbf();
    data = guidata(fig);
    if data.n_outputs < 4
        data.n_outputs = data.n_outputs + 1;
        set(data.edit_n_outputs, 'String', num2str(data.n_outputs));
        % Rebuild output table when user increments
        topology_key = get(data.pop_topology, 'Value');
        topology_names = {'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', ...
                         'flyback', 'push_pull', 'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'};
        if topology_key > 0 && topology_key <= length(topology_names)
            topo_key = topology_names{topology_key};
            metadata = get_topology_metadata(topo_key);
            output_type = metadata.output_type;
            rebuild_output_spec_table(fig, topo_key, output_type);
        end
    end
    guidata(fig, data);
end


function cb_n_outputs_minus(~, ~)
    fig = gcbf();
    data = guidata(fig);
    if data.n_outputs > 1
        data.n_outputs = data.n_outputs - 1;
        set(data.edit_n_outputs, 'String', num2str(data.n_outputs));
        % Rebuild output table when user decrements
        topology_key = get(data.pop_topology, 'Value');
        topology_names = {'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', ...
                         'flyback', 'push_pull', 'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'};
        if topology_key > 0 && topology_key <= length(topology_names)
            topo_key = topology_names{topology_key};
            metadata = get_topology_metadata(topo_key);
            output_type = metadata.output_type;
            rebuild_output_spec_table(fig, topo_key, output_type);
        end
    end
    guidata(fig, data);
end


function cb_compute_topology(~, ~)
    fig = gcbf();
    data = guidata(fig);

    % Re-entrancy guard: drawnow() inside callbacks can cause pending events to fire,
    % re-triggering this callback before the previous run completes. Return early if busy.
    if isfield(data, 'computing') && data.computing
        return;
    end

    % Validate required fields BEFORE setting computing=true so early returns don't block future runs
    c = data.converter;
    if c.vin_min <= 0 || c.vin_max <= 0 || c.vout <= 0 || c.iout <= 0 || c.fsw_khz <= 0
        errordlg('Please fill in all required converter specifications.', 'Missing Data');
        return;
    end
    if c.vin_min >= c.vin_max
        errordlg('Input voltage min must be less than max.', 'Invalid Data');
        return;
    end

    data.computing = true;
    guidata(fig, data);

    set(data.btn_compute, 'String', 'Computing...', 'Enable', 'off');
    drawnow();

    try
        % STEP 1: Request topology computation (generates waveforms + computed requirements)
        data = request_topology_compute(data);

        % STEP 2: Collect GUI field values for API submission
        fprintf('[TOPOLOGY] Collecting GUI field values...\n');
        gui_values = collect_gui_field_values(fig, data.topology);

        % STEP 3: Build base MAS and enrich with topology-computed values if available
        fprintf('[TOPOLOGY] Building MAS structure...\n');
        gui_data = struct();
        gui_data.converter = struct();
        gui_data.converter.vin_min = gui_values.vin_min;
        gui_data.converter.vin_max = gui_values.vin_max;
        gui_data.converter.vin_nom = gui_values.vin_nom;
        gui_data.converter.vout = gui_values.vout;
        gui_data.converter.iout = gui_values.iout;
        gui_data.converter.fsw_khz = gui_values.fsw_khz;
        gui_data.converter.vd = gui_values.vd;
        gui_data.converter.efficiency = gui_values.efficiency;
        gui_data.converter.max_ripple = gui_values.max_ripple;
        gui_data.converter.max_switch_current = gui_values.max_switch_current;
        gui_data.converter.max_duty = gui_values.max_duty;

        gui_data.thermal = struct();
        gui_data.thermal.ambient_temp = gui_values.ambient_temp;
        gui_data.thermal.max_rise = gui_values.max_temp_rise;

        gui_data.insulation = struct();
        gui_data.insulation.class = gui_values.insulation_class;
        gui_data.insulation.cti = gui_values.cti;
        gui_data.insulation.pollution_degree = gui_values.pollution_degree;
        gui_data.insulation.overvoltage_cat = gui_values.overvoltage_cat;
        gui_data.insulation.standard = gui_values.insulation_standard;

        mas_struct = build_mas_structure(gui_data, data.topology);

        % Enrich with topology-computed values if available
        if isfield(data, 'mas_inputs') && isstruct(data.mas_inputs) && ~isempty(data.mas_inputs)
            fprintf('[TOPOLOGY] Merging topology-computed designRequirements...\n');

            % The topology calculator provides more accurate designRequirements
            % (magnetizingInductance, turnsRatios) - merge these into our MAS
            topo_design_req = data.mas_inputs.designRequirements;
            if isstruct(topo_design_req)
                % Copy computed fields from topology (will override build_mas_structure defaults)
                if isfield(topo_design_req, 'magnetizingInductance')
                    mas_struct.inputs.designRequirements.magnetizingInductance = ...
                        topo_design_req.magnetizingInductance;
                    fprintf('  - Added magnetizingInductance from topology\n');
                end
                if isfield(topo_design_req, 'turnsRatios')
                    mas_struct.inputs.designRequirements.turnsRatios = ...
                        topo_design_req.turnsRatios;
                    fprintf('  - Added turnsRatios from topology\n');
                end
            end
        end
        % Merge topology-computed operating points (with waveform excitation data)
        % These are produced by generate_om_topology.py's build_operating_points()
        if isfield(data, 'mas_inputs') && isstruct(data.mas_inputs) && ...
                isfield(data.mas_inputs, 'operatingPoints') && ~isempty(data.mas_inputs.operatingPoints)
            mas_struct.inputs.operatingPoints = data.mas_inputs.operatingPoints;
            fprintf('  - Added operatingPoints from topology (with waveform excitations)\n');
        end

        % STEP 4: Write MAS JSON to config file
        script_dir = pwd();
        config_file = 'om_topology_api_config.json';
        results_file = 'om_topology_api_results.json';
        config_path = fullfile(script_dir, config_file);
        results_path = fullfile(script_dir, results_file);

        fid = fopen(config_path, 'w', 'n', 'UTF-8');
        fprintf(fid, '%s', jsonencode(mas_struct));
        fclose(fid);
        fprintf('[TOPOLOGY] MAS config written to %s\n', config_file);

        % STEP 5: Call Python API (call_pyopenmagnetics_api.py will delegate to generate_om_recommendations.py)
        fprintf('[TOPOLOGY] Calling PyOpenMagnetics API...\n');
        py_script = 'call_pyopenmagnetics_api.py';

        % Reuse the Python found during topology computation (already confirmed to have PyOpenMagnetics)
        if isfield(data, 'found_python') && ~isempty(data.found_python)
            python_cmd = data.found_python;
            fprintf('[TOPOLOGY] Reusing confirmed Python: %s\n', python_cmd);
        else
            python_cmd = 'python';
            venv_python = fullfile(script_dir, '.venv', 'Scripts', 'python.exe');
            if exist(venv_python, 'file')
                python_cmd = ['"' strrep(venv_python, '\', '/') '"'];
            end
        end

        cmd = sprintf('%s "%s" "%s" "%s" 2>&1', python_cmd, py_script, config_file, results_file);
        fprintf('[TOPOLOGY] Running: %s\n', cmd);
        [status, output] = system(cmd);
        fprintf('[TOPOLOGY] Python exit status: %d\n', status);

        % Fallback chain if the confirmed Python still fails for any reason
        if status ~= 0 && ispc
            fprintf('[TOPOLOGY] API call failed. Trying fallback chain...\n');

            % Fallback 1: py launcher
            cmd_fb = sprintf('py "%s" "%s" "%s" 2>&1', py_script, config_file, results_file);
            [status_fb, output_fb] = system(cmd_fb);
            fprintf('[TOPOLOGY] py launcher exit=%d\n', status_fb);
            if status_fb == 0
                status = status_fb;
                output = output_fb;
                fprintf('[TOPOLOGY] Success using ''py'' launcher\n');
            else
                % Fallback 2: where python
                [~, py_paths_str] = system('where python');
                py_paths = strsplit(strtrim(py_paths_str), char(10));
                for i = 1:length(py_paths)
                    p = strtrim(py_paths{i});
                    if isempty(p); continue; end
                    if ~isempty(strfind(lower(p), 'octave')) || ~isempty(strfind(lower(p), 'usr\bin'))
                        continue;
                    end
                    p = strrep(p, '\', '/');
                    fprintf('[TOPOLOGY] Trying alternative python: %s\n', p);
                    cmd_alt = sprintf('"%s" "%s" "%s" "%s" 2>&1', p, py_script, config_file, results_file);
                    [status_alt, output_alt] = system(cmd_alt);
                    fprintf('[TOPOLOGY] Alt python exit=%d\n', status_alt);
                    if status_alt == 0
                        status = status_alt;
                        output = output_alt;
                        fprintf('[TOPOLOGY] Success using alternative python\n');
                        break;
                    end
                end
            end
        end

        if status ~= 0
            error('Python API script failed: %s', output);
        end

        % STEP 7: Read results JSON
        fprintf('[TOPOLOGY] Reading API results...\n');
        fid = fopen(results_path, 'r', 'n', 'UTF-8');
        if fid < 0
            error('Cannot open results file: %s', results_path);
        end
        raw = fread(fid, '*char')';
        fclose(fid);
        results = jsondecode(raw);

        % Check for API errors in results
        if isfield(results, 'status') && strcmp(results.status, 'ERROR')
            error('PyOpenMagnetics API error: %s', results.error);
        end

        % STEP 8: Store and display results
        data.api_results = results;
        results_count = 0;
        if isfield(results, 'data') && isnumeric(results.count)
            results_count = results.count;
        end
        fprintf('[TOPOLOGY] API returned %d results\n', results_count);

        % STEP 9: Display results in GUI
        display_api_results(fig, results);

        % Show success message
        msgbox(sprintf('Topology analysis complete!\nRecommendations displayed below.'), ...
               'Success', 'help');

    catch err
        fprintf('[TOPOLOGY] ERROR: %s\n', err.message);
        if isfield(err, 'stack') && ~isempty(err.stack)
            for si = 1:length(err.stack)
                fprintf('[TOPOLOGY]   at %s() line %d in %s\n', ...
                    err.stack(si).name, err.stack(si).line, err.stack(si).file);
            end
        end
        data.computing = false;
        if ishandle(data.btn_compute)
            set(data.btn_compute, 'String', 'Compute Requirements', 'Enable', 'on');
        end
        guidata(fig, data);
        errordlg(sprintf('Computation failed:\n\n%s', err.message), 'Error');
        return;
    end

    data.computing = false;
    if ishandle(data.btn_compute)
        set(data.btn_compute, 'String', 'Compute Requirements', 'Enable', 'on');
    end
    guidata(fig, data);
end


function data = request_topology_compute(data)
    % Call generate_om_topology.py to compute topology-specific requirements

    fig = gcbf();
    script_dir = pwd();
    config_file = 'om_topology_config.json';
    output_file = 'om_topology_results.json';
    py_script = 'generate_om_topology.py';
    config_path = fullfile(script_dir, config_file);
    output_path = fullfile(script_dir, output_file);

    % Build config JSON
    config = struct();
    config.mode = 'compute_topology';
    config.topology = data.topology;
    config.design_mode = data.design_mode;
    config.n_outputs = data.n_outputs;
    config.converter = data.converter;
    config.converter.fsw_hz = data.converter.fsw_khz * 1e3;
    config.output_file = strrep(output_path, '\', '/');

    % Add a nominal operating point so generate_om_topology.py can build waveform excitations.
    % Without operatingPoints, build_operating_points() returns [] and waveforms are blank.
    nom_op = struct();
    nom_op.switchingFrequency = data.converter.fsw_khz * 1e3;
    if isfield(data, 'thermal') && isfield(data.thermal, 'ambient_temp')
        nom_op.ambientTemperature = data.thermal.ambient_temp;
    else
        nom_op.ambientTemperature = 25;
    end
    if isfield(data.converter, 'output_voltages') && ~isempty(data.converter.output_voltages)
        nom_op.outputVoltages = data.converter.output_voltages;
    elseif isfield(data.converter, 'vout') && ~isempty(data.converter.vout)
        nom_op.outputVoltages = [data.converter.vout];
    else
        nom_op.outputVoltages = [5.0];
    end
    if isfield(data.converter, 'output_currents') && ~isempty(data.converter.output_currents)
        nom_op.outputCurrents = data.converter.output_currents;
    elseif isfield(data.converter, 'iout') && ~isempty(data.converter.iout)
        nom_op.outputCurrents = [data.converter.iout];
    else
        nom_op.outputCurrents = [1.0];
    end
    config.converter.operatingPoints = {nom_op};

    % Optional advanced params
    config.advanced = struct();
    config.advanced.max_duty = data.converter.max_duty;
    config.advanced.max_switch_current = data.converter.max_switch_current;

    % Write JSON config
    fid = fopen(config_path, 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonencode(config));
    fclose(fid);

    % Verify script exists
    if ~exist(fullfile(script_dir, py_script), 'file')
        error('Python script "%s" not found in %s', py_script, script_dir);
    end

    % Find Python - same fallback chain as recommendations
    python_cmd = 'python';
    venv_python = fullfile(script_dir, '.venv', 'Scripts', 'python.exe');
    if exist(venv_python, 'file')
        python_cmd = ['"' strrep(venv_python, '\', '/') '"'];
    end
    found_python = python_cmd;  % Track which Python ends up working

    cmd = sprintf('%s "%s" "%s" 2>&1', python_cmd, py_script, config_file);
    fprintf('[TOPOLOGY] Running: %s\n', cmd);
    [status, output] = system(cmd);
    fprintf('[TOPOLOGY] Status: %d, Output: %s\n', status, strtrim(output));

    % Check for module import errors
    is_module_error = ~isempty(strfind(output, 'ModuleNotFoundError')) || ...
                      ~isempty(strfind(output, 'ImportError')) || ...
                      ~isempty(strfind(output, 'No module named'));

    % Fallback 1: Try Windows Python Launcher (py)
    if status ~= 0 && is_module_error && ispc
        fprintf('[TOPOLOGY] Standard python failed. Trying ''py'' launcher...\n');
        cmd_fb = sprintf('py "%s" "%s" 2>&1', py_script, config_file);
        [status_fb, output_fb] = system(cmd_fb);
        fprintf('[TOPOLOGY] py launcher exit=%d, output: %s\n', status_fb, strtrim(output_fb));
        if status_fb == 0
            status = status_fb;
            output = output_fb;
            found_python = 'py';
            fprintf('[TOPOLOGY] Success using ''py'' launcher.\n');
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
            fprintf('[TOPOLOGY] Trying alternative python: %s\n', p);
            cmd_alt = sprintf('"%s" "%s" "%s" 2>&1', p, py_script, config_file);
            [status_alt, output_alt] = system(cmd_alt);
            fprintf('[TOPOLOGY] Alt python exit=%d, output: %s\n', status_alt, strtrim(output_alt));
            if status_alt == 0
                status = status_alt;
                output = output_alt;
                found_python = ['"' p '"'];
                fprintf('[TOPOLOGY] Success using alternative python.\n');
                break;
            end
        end
    end

    if status ~= 0
        error('Python script failed: %s', output);
    end

    % Store the working Python path so the API call can reuse it (avoids re-discovery)
    data.found_python = found_python;
    fprintf('[TOPOLOGY] Python confirmed: %s\n', found_python);

    % Load results
    fprintf('[DEBUG] Loading results from %s\n', output_path);
    fid = fopen(output_path, 'r', 'n', 'UTF-8');
    raw = fread(fid, '*char')';
    fclose(fid);
    results = jsondecode(raw);
    fprintf('[DEBUG] jsondecode done, results class=%s, isstruct=%d\n', class(results), isstruct(results));

    if isfield(results, 'status') && ~strcmp(results.status, 'OK')
        error('Topology computation failed: %s', results.error);
    end
    fprintf('[DEBUG] Status check passed\n');

    % Extract computed requirements
    if isfield(results, 'computed')
        comp = results.computed;
        fprintf('[DEBUG] comp class=%s, isstruct=%d\n', class(comp), isstruct(comp));
        % Update requirements from computed values
        if isfield(comp, 'Lm_uH')
            data.requirements.Lm_uH = comp.Lm_uH;
        end
        if isfield(comp, 'turns_ratio')
            data.requirements.turns_ratio = comp.turns_ratio;
        end
        if isfield(comp, 'n_windings')
            data.requirements.n_windings = comp.n_windings;
        end
        if isfield(comp, 'duty_nom')
            data.requirements.duty_nom = comp.duty_nom;
        end
        if isfield(comp, 'duty_min_vin')
            data.requirements.duty_min_vin = comp.duty_min_vin;
        end
        if isfield(comp, 'duty_max_vin')
            data.requirements.duty_max_vin = comp.duty_max_vin;
        end
        if isfield(comp, 'pin_nom')
            data.requirements.pin_nom = comp.pin_nom;
        end
        if isfield(comp, 'pout_nom')
            data.requirements.pout_nom = comp.pout_nom;
        end
        % Waveform-related fields needed by build_recommendation_config()
        if isfield(comp, 'i_mag_pp')
            data.requirements.i_mag_pp = comp.i_mag_pp;
        end
        if isfield(comp, 'i_mag_pp_worst')
            data.requirements.i_mag_pp_worst = comp.i_mag_pp_worst;
        end
        if isfield(comp, 'i_pri_rms')
            data.requirements.i_pri_rms = comp.i_pri_rms;
        end
        if isfield(comp, 'i_pri_rms_worst')
            data.requirements.i_pri_rms_worst = comp.i_pri_rms_worst;
        end
        if isfield(comp, 'i_sec_rms')
            data.requirements.i_sec_rms = comp.i_sec_rms;
        end
        if isfield(comp, 'vin_nom')
            data.requirements.vin_nom = comp.vin_nom;
        end
        if isfield(comp, 'fsw_hz')
            data.requirements.fsw_hz = comp.fsw_hz;
        end
        % turns_ratios is an array in JSON; use first element as turns_ratio scalar
        if ~isfield(comp, 'turns_ratio') && isfield(comp, 'turns_ratios')
            tr = comp.turns_ratios;
            if isnumeric(tr) && ~isempty(tr)
                data.requirements.turns_ratio = tr(1);
            end
        end
        fprintf('[DEBUG] Computed fields extracted OK\n');
    end

    % Store MAS inputs from Python for later use in recommendations
    fprintf('[DEBUG] Checking mas_inputs...\n');
    if isfield(results, 'mas_inputs')
        fprintf('[DEBUG] mas_inputs class=%s, isstruct=%d\n', class(results.mas_inputs), isstruct(results.mas_inputs));
        data.mas_inputs = results.mas_inputs;
        fprintf('[DEBUG] mas_inputs stored OK\n');
    end

    % Update display
    fprintf('[DEBUG] Calling update_topology_requirements_display...\n');
    data = update_topology_requirements_display(data, results);
    fprintf('[DEBUG] update_topology_requirements_display done\n');

    % Plot waveforms if available
    fprintf('[DEBUG] Checking waveforms...\n');
    has_ax = isfield(data, 'ax_waveforms') && ~isempty(data.ax_waveforms) && ishandle(data.ax_waveforms);
    has_wf = isfield(results, 'waveforms_preview') && ~isempty(results.waveforms_preview);
    fprintf('[DEBUG] has_ax=%d, has_wf=%d\n', has_ax, has_wf);
    if has_ax
        if has_wf
            fprintf('[DEBUG] waveforms_preview class=%s, size=[%s]\n', class(results.waveforms_preview), num2str(size(results.waveforms_preview)));
            plot_topology_waveforms(data.ax_waveforms, ...
                                   results.waveforms_preview, ...
                                   data.topology_display);
        else
            cla(data.ax_waveforms);
            text(0.5, 0.5, 'No waveform data available', ...
                 'Parent', data.ax_waveforms, ...
                 'HorizontalAlignment', 'center', ...
                 'VerticalAlignment', 'middle', ...
                 'FontSize', 10, ...
                 'Color', [0.5 0.5 0.5]);
            axis(data.ax_waveforms, 'off');
        end
    end

    guidata(fig, data);
end


function update_topology_visibility(data)
    % Update field visibility based on selected topology
    % Shows/hides topology-specific input fields in the Converter Specifications panel

    fig = gcbf();
    topology = data.topology;

    % Determine topology categories
    is_isolated = any(strcmp(topology, {'flyback', 'push_pull', 'isolated_buck', ...
                                        'isolated_buck_boost', 'two_switch_forward', ...
                                        'single_switch_forward', 'active_clamp_forward'}));
    is_forward = any(strcmp(topology, {'two_switch_forward', 'single_switch_forward', ...
                                       'active_clamp_forward'}));
    is_flyback = strcmp(topology, 'flyback');
    is_buck_boost = any(strcmp(topology, {'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'}));

    % ===== Show/Hide N Outputs Spinner =====
    % Only show for isolated topologies
    if isfield(data, 'edit_n_outputs') && ~isempty(data.edit_n_outputs)
        if is_isolated
            set(data.edit_n_outputs, 'Visible', 'on');
            if isfield(data, 'btn_n_outputs_plus') && ~isempty(data.btn_n_outputs_plus)
                set(data.btn_n_outputs_plus, 'Visible', 'on');
            end
            if isfield(data, 'btn_n_outputs_minus') && ~isempty(data.btn_n_outputs_minus)
                set(data.btn_n_outputs_minus, 'Visible', 'on');
            end
        else
            set(data.edit_n_outputs, 'Visible', 'off');
            if isfield(data, 'btn_n_outputs_plus') && ~isempty(data.btn_n_outputs_plus)
                set(data.btn_n_outputs_plus, 'Visible', 'off');
            end
            if isfield(data, 'btn_n_outputs_minus') && ~isempty(data.btn_n_outputs_minus)
                set(data.btn_n_outputs_minus, 'Visible', 'off');
            end
        end
    end

    % ===== Update Input Voltage Fields =====
    % All topologies need input voltage, but visibility may change dynamically
    if isfield(data, 'edit_vin_min') && ~isempty(data.edit_vin_min)
        set(data.edit_vin_min, 'Visible', 'on');
    end
    if isfield(data, 'edit_vin_max') && ~isempty(data.edit_vin_max)
        set(data.edit_vin_max, 'Visible', 'on');
    end
    if isfield(data, 'edit_vin_nom') && ~isempty(data.edit_vin_nom)
        set(data.edit_vin_nom, 'Visible', 'on');
    end

    % ===== Output Voltage/Current Fields =====
    % All topologies except Buck/Boost (non-isolated single winding) need output
    if isfield(data, 'edit_vout') && ~isempty(data.edit_vout)
        if is_isolated || strcmp(topology, 'boost')  % Boost has output voltage
            set(data.edit_vout, 'Visible', 'on');
        else
            set(data.edit_vout, 'Visible', 'on');  % Most topologies need this
        end
    end
    if isfield(data, 'edit_iout') && ~isempty(data.edit_iout)
        if is_isolated || strcmp(topology, 'boost')
            set(data.edit_iout, 'Visible', 'on');
        else
            set(data.edit_iout, 'Visible', 'on');
        end
    end

    % ===== Switching Frequency (all topologies) =====
    if isfield(data, 'edit_fsw') && ~isempty(data.edit_fsw)
        set(data.edit_fsw, 'Visible', 'on');
    end

    % ===== Efficiency (all topologies) =====
    if isfield(data, 'edit_efficiency') && ~isempty(data.edit_efficiency)
        set(data.edit_efficiency, 'Visible', 'on');
    end

    % ===== Diode Forward Drop (all topologies except ideal cases) =====
    if isfield(data, 'edit_vd') && ~isempty(data.edit_vd)
        set(data.edit_vd, 'Visible', 'on');
    end

    % ===== Ripple Current (all topologies) =====
    if isfield(data, 'edit_ripple') && ~isempty(data.edit_ripple)
        set(data.edit_ripple, 'Visible', 'on');
    end

    % ===== Max Switch Current (most isolated topologies, not buck/boost) =====
    % Not yet implemented in GUI, but reserve for future use
    if isfield(data, 'edit_max_switch_current') && ~isempty(data.edit_max_switch_current)
        if ~any(strcmp(topology, {'buck', 'boost'}))
            set(data.edit_max_switch_current, 'Visible', 'on');
        else
            set(data.edit_max_switch_current, 'Visible', 'off');
        end
    end

    % ===== Flyback-Specific Controls =====
    % Flyback may have max_duty OR max_Vds constraint selector (future implementation)
    if isfield(data, 'rb_flyback_max_duty') && ~isempty(data.rb_flyback_max_duty)
        if is_flyback
            set(data.rb_flyback_max_duty, 'Visible', 'on');
        else
            set(data.rb_flyback_max_duty, 'Visible', 'off');
        end
    end
    if isfield(data, 'rb_flyback_max_vds') && ~isempty(data.rb_flyback_max_vds)
        if is_flyback
            set(data.rb_flyback_max_vds, 'Visible', 'on');
        else
            set(data.rb_flyback_max_vds, 'Visible', 'off');
        end
    end

    % ===== Dead Time (Flyback advanced) =====
    if isfield(data, 'edit_dead_time') && ~isempty(data.edit_dead_time)
        if is_flyback && isfield(data, 'design_mode') && strcmp(data.design_mode, 'advanced')
            set(data.edit_dead_time, 'Visible', 'on');
        else
            set(data.edit_dead_time, 'Visible', 'off');
        end
    end

end


% ===============================================================
% [PHASE 3.2-3.3] DYNAMIC FIELD VISIBILITY SYSTEM
% ===============================================================
% These functions implement the data-driven topology field visibility:
% - update_field_visibility() - Main orchestrator
% - get_topology_output_type() - Returns 'single' or 'multi'
% - get_visible_fields_for_topology() - Returns required/optional field lists
% - rebuild_output_spec_table() - Update output rows based on topology

function update_field_visibility(fig, topology_key)
    % [TOPOLOGY] Update field visibility based on selected topology
    % Calls get_topology_metadata() to determine which fields to show
    %
    % Inputs:
    %   fig - figure handle
    %   topology_key - string, topology identifier (e.g., 'two_switch_forward')
    %
    % This function:
    % 1. Gets metadata from get_topology_metadata(topology_key)
    % 2. Shows/hides required fields
    % 3. Shows/hides optional fields (based on data.show_optional)
    % 4. Shows/hides N outputs spinner for multi-output topologies
    % 5. Calls rebuild_output_spec_table() to update output rows
    % 6. Updates requirements title with topology display name

    data = guidata(fig);

    % [Step 1] Get topology metadata
    try
        topo_meta = get_topology_metadata(topology_key);
        fprintf('[TOPOLOGY] Loaded metadata for %s\n', topo_meta.display_name);
    catch err
        fprintf('[TOPOLOGY] ERROR: Failed to get metadata for %s: %s\n', topology_key, err.message);
        return;
    end

    % [Step 2] Show/hide required fields
    required_fields = topo_meta.required_fields;
    for i = 1:length(required_fields)
        field_name = required_fields{i};
        ui_handle = get_ui_handle_for_field(data, field_name);
        if ~isempty(ui_handle) && ishandle(ui_handle)
            set(ui_handle, 'Visible', 'on');
            fprintf('[TOPOLOGY] Showing required field: %s\n', field_name);
        end
    end

    % [Step 3] Show/hide optional fields based on show_optional flag
    optional_fields = topo_meta.optional_fields;
    for i = 1:length(optional_fields)
        field_name = optional_fields{i};
        ui_handle = get_ui_handle_for_field(data, field_name);
        if ~isempty(ui_handle) && ishandle(ui_handle)
            if data.show_optional
                set(ui_handle, 'Visible', 'on');
                fprintf('[TOPOLOGY] Showing optional field: %s\n', field_name);
            else
                set(ui_handle, 'Visible', 'off');
                fprintf('[TOPOLOGY] Hiding optional field: %s\n', field_name);
            end
        end
    end

    % [Step 4] Show/hide N outputs spinner based on output type
    output_type = get_topology_output_type(topology_key);
    if isfield(data, 'edit_n_outputs') && ~isempty(data.edit_n_outputs) && ishandle(data.edit_n_outputs)
        if strcmp(output_type, 'multi')
            set(data.edit_n_outputs, 'Visible', 'on');
            if isfield(data, 'btn_n_outputs_plus') && ~isempty(data.btn_n_outputs_plus) && ishandle(data.btn_n_outputs_plus)
                set(data.btn_n_outputs_plus, 'Visible', 'on');
            end
            if isfield(data, 'btn_n_outputs_minus') && ~isempty(data.btn_n_outputs_minus) && ishandle(data.btn_n_outputs_minus)
                set(data.btn_n_outputs_minus, 'Visible', 'on');
            end
            fprintf('[TOPOLOGY] Showing N outputs spinner (multi-output topology)\n');
        else
            set(data.edit_n_outputs, 'Visible', 'off');
            if isfield(data, 'btn_n_outputs_plus') && ~isempty(data.btn_n_outputs_plus) && ishandle(data.btn_n_outputs_plus)
                set(data.btn_n_outputs_plus, 'Visible', 'off');
            end
            if isfield(data, 'btn_n_outputs_minus') && ~isempty(data.btn_n_outputs_minus) && ishandle(data.btn_n_outputs_minus)
                set(data.btn_n_outputs_minus, 'Visible', 'off');
            end
            fprintf('[TOPOLOGY] Hiding N outputs spinner (single-output topology)\n');
        end
    end

    % [Step 5] Update output specification table
    rebuild_output_spec_table(fig, topology_key, output_type);

    % [Step 6] Update requirements display title
    req_title_handles = findobj(fig, 'Style', 'text', '-regexp', 'String', '.*Design Requirements.*');
    if ~isempty(req_title_handles)
        for j = 1:length(req_title_handles)
            if ishandle(req_title_handles(j))
                set(req_title_handles(j), 'String', sprintf('--- %s Design Requirements ---', topo_meta.display_name));
            end
        end
        fprintf('[TOPOLOGY] Updated requirements title to: %s\n', topo_meta.display_name);
    end

    guidata(fig, data);
end


function output_type = get_topology_output_type(topology_key)
    % [TOPOLOGY] Get output type for a topology
    %
    % Returns:
    %   'multi' - Multi-output isolated topologies
    %   'single' - Single-output non-isolated topologies
    %
    % Multi-output topologies:
    %   Two-Switch Forward, Single-Switch Forward, Active Clamp Forward,
    %   Flyback, Push-Pull, Isolated Buck, Isolated Buck-Boost
    %
    % Single-output topologies:
    %   Buck, Boost

    multi_output_topologies = {
        'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', ...
        'flyback', 'push_pull', 'isolated_buck', 'isolated_buck_boost'
    };

    if any(strcmp(topology_key, multi_output_topologies))
        output_type = 'multi';
    else
        % Buck, Boost and others default to single
        output_type = 'single';
    end
end


function [required_fields, optional_fields] = get_visible_fields_for_topology(topology_key)
    % [TOPOLOGY] Get field visibility lists for a topology
    %
    % Returns cell arrays of field names that should be shown for the given topology.
    % These are merged from topology_metadata.m definitions.
    %
    % Inputs:
    %   topology_key - string identifier (e.g., 'two_switch_forward')
    %
    % Outputs:
    %   required_fields - cell array of required field names
    %   optional_fields - cell array of optional field names

    try
        topo_meta = get_topology_metadata(topology_key);
        required_fields = topo_meta.required_fields;
        optional_fields = topo_meta.optional_fields;
    catch
        % Fallback if metadata not available
        fprintf('[TOPOLOGY] WARNING: Could not load topology metadata, using defaults\n');
        required_fields = {};
        optional_fields = {};
    end
end


function rebuild_output_spec_table(fig, topology_key, output_type)
    % [TOPOLOGY] Rebuild output specification table rows based on topology
    %
    % For single-output topologies (Buck, Boost):
    %   - Hide output 2, 3, 4 rows
    %   - Show single "Output:" row
    %
    % For multi-output topologies:
    %   - Show N rows based on n_outputs spinner value
    %   - Each row: "Output X: Voltage [___] V  Current [___] A"
    %
    % Inputs:
    %   fig - figure handle
    %   topology_key - string topology identifier
    %   output_type - 'single' or 'multi' (cached from get_topology_output_type)

    data = guidata(fig);

    if strcmp(output_type, 'single')
        % Single output topology - show only one row
        fprintf('[TOPOLOGY] Configuring single-output table\n');

        % Update label to "Output:" (no number)
        output_labels = {'output1_label', 'output2_label', 'output3_label', 'output4_label'};
        for i = 1:length(output_labels)
            if isfield(data, output_labels{i}) && ~isempty(data.(output_labels{i})) && ishandle(data.(output_labels{i}))
                if i == 1
                    set(data.output1_label, 'String', 'Output:', 'Visible', 'on');
                else
                    set(data.(output_labels{i}), 'Visible', 'off');
                end
            end
        end

        % Hide output 2, 3, 4 edit fields
        for i = 2:4
            for suffix = {'_v', '_i'}
                field_name = sprintf('output%d%s', i, suffix{1});
                if isfield(data, field_name) && ~isempty(data.(field_name)) && ishandle(data.(field_name))
                    set(data.(field_name), 'Visible', 'off');
                end
            end
        end

    else
        % Multi-output topology - show N rows based on spinner
        fprintf('[TOPOLOGY] Configuring multi-output table\n');

        n_outputs = 1;
        if isfield(data, 'edit_n_outputs') && ~isempty(data.edit_n_outputs) && ishandle(data.edit_n_outputs)
            n_outputs = str2double(get(data.edit_n_outputs, 'String'));
            if isnan(n_outputs) || n_outputs < 1
                n_outputs = 1;
            end
        end

        % Update labels and visibility for outputs 1-4
        for i = 1:4
            label_field = sprintf('output%d_label', i);
            v_field = sprintf('output%d_v', i);
            i_field = sprintf('output%d_i', i);

            if i <= n_outputs
                % Show this output row
                if isfield(data, label_field) && ~isempty(data.(label_field)) && ishandle(data.(label_field))
                    set(data.(label_field), 'String', sprintf('Output %d:', i), 'Visible', 'on');
                end
                if isfield(data, v_field) && ~isempty(data.(v_field)) && ishandle(data.(v_field))
                    set(data.(v_field), 'Visible', 'on');
                end
                if isfield(data, i_field) && ~isempty(data.(i_field)) && ishandle(data.(i_field))
                    set(data.(i_field), 'Visible', 'on');
                end
                fprintf('[TOPOLOGY] Output %d: VISIBLE\n', i);
            else
                % Hide this output row
                if isfield(data, label_field) && ~isempty(data.(label_field)) && ishandle(data.(label_field))
                    set(data.(label_field), 'Visible', 'off');
                end
                if isfield(data, v_field) && ~isempty(data.(v_field)) && ishandle(data.(v_field))
                    set(data.(v_field), 'Visible', 'off');
                end
                if isfield(data, i_field) && ~isempty(data.(i_field)) && ishandle(data.(i_field))
                    set(data.(i_field), 'Visible', 'off');
                end
                fprintf('[TOPOLOGY] Output %d: HIDDEN\n', i);
            end
        end
    end

    guidata(fig, data);
end


function ui_handle = get_ui_handle_for_field(data, field_name)
    % [TOPOLOGY] Helper: Get UI handle for a topology field
    %
    % Maps field names from topology_metadata.m to GUI edit/control handles
    % Supports field naming conventions from topology_metadata:
    %   - inputVoltage_minimum -> edit_vin_min
    %   - inputVoltage_maximum -> edit_vin_max
    %   - outputVoltages_0 -> output1_v (for first output)
    %   - outputCurrents_1 -> output2_i (for second output)
    %   etc.

    ui_handle = [];

    % Map topology field names to GUI handle field names
    field_mapping = containers.Map(...
        {'inputVoltage_minimum', 'inputVoltage_maximum', 'inputVoltage_nominal', ...
         'outputVoltage', 'outputCurrent', ...
         'switchingFrequency', 'diodeVoltageDrop', 'currentRippleRatio', ...
         'efficiency', 'maximumSwitchCurrent', 'maximumDutyCycle', 'dutyCycle', ...
         'maximumDrainSourceVoltage'}, ...
        {'edit_vin_min', 'edit_vin_max', 'edit_vin_nom', ...
         'edit_vout', 'edit_iout', ...
         'edit_fsw', 'edit_vd', 'edit_ripple', ...
         'edit_efficiency', 'edit_max_switch_current', 'edit_max_duty', 'edit_duty_cycle', ...
         'edit_max_drain_source_voltage'} ...
    );

    % Handle multi-output fields (outputVoltages_0, outputCurrents_1, etc.)
    if strncmp(field_name, 'outputVoltages_', 15)
        idx = str2double(field_name(16:end));  % Extract index from "outputVoltages_0"
        if ~isnan(idx) && idx >= 0 && idx < 4
            field_name = sprintf('output%d_v', idx + 1);  % Convert to output1_v, output2_v, etc.
        end
    elseif strncmp(field_name, 'outputCurrents_', 15)
        idx = str2double(field_name(16:end));  % Extract index from "outputCurrents_0"
        if ~isnan(idx) && idx >= 0 && idx < 4
            field_name = sprintf('output%d_i', idx + 1);  % Convert to output1_i, output2_i, etc.
        end
    elseif isKey(field_mapping, field_name)
        field_name = field_mapping(field_name);
    end

    % Look up the handle in data struct
    if isfield(data, field_name) && ~isempty(data.(field_name))
        ui_handle = data.(field_name);
    end
end


function data = update_topology_requirements_display(data, results)
    % Update requirements display from computed topology values
    fprintf('[DEBUG] update_topology_requirements_display entered\n');

    fig = gcbf();
    fprintf('[DEBUG] gcbf() returned class=%s, ishandle=%d\n', class(fig), ishandle(fig));
    r = data.requirements;
    fprintf('[DEBUG] r class=%s, isstruct=%d\n', class(r), isstruct(r));
    c = data.converter;

    % Build display text
    lines = {};
    lines{end+1} = sprintf('--- %s Design ---', data.topology_display);
    lines{end+1} = '';

    fprintf('[DEBUG] About to call isfield(results, topology_display), results class=%s, isstruct=%d\n', class(results), isstruct(results));
    if isfield(results, 'topology_display')
        lines{end+1} = sprintf('Topology: %s', results.topology_display);
        lines{end+1} = '';
    end

    if r.turns_ratio > 0
        lines{end+1} = sprintf('Turns ratio Np:Ns = %.2f : 1', r.turns_ratio);
        lines{end+1} = '';
    end

    if r.duty_nom > 0
        lines{end+1} = sprintf('Duty cycle:');
        if r.duty_min_vin > 0
            lines{end+1} = sprintf('  at Vin_min (%g V): D = %.3f', c.vin_min, r.duty_min_vin);
        end
        if r.duty_nom > 0
            lines{end+1} = sprintf('  at Vin_nom (%g V): D = %.3f', c.vin_min, r.duty_nom);
        end
        if r.duty_max_vin > 0
            lines{end+1} = sprintf('  at Vin_max (%g V): D = %.3f', c.vin_max, r.duty_max_vin);
        end
        lines{end+1} = '';
    end

    if r.Lm_uH > 0
        lines{end+1} = sprintf('Magnetizing inductance Lm = %.1f uH', r.Lm_uH);
        lines{end+1} = '';
    end

    if r.i_pri_rms > 0
        lines{end+1} = sprintf('Primary RMS current = %.2f A', r.i_pri_rms);
    end
    if r.i_sec_rms > 0
        lines{end+1} = sprintf('Secondary RMS current = %.2f A', r.i_sec_rms);
    end

    if r.pout_nom > 0
        lines{end+1} = '';
        lines{end+1} = sprintf('Output power = %.1f W', r.pout_nom);
    end
    if r.pin_nom > 0
        lines{end+1} = sprintf('Input power = %.1f W (at %.0f%% eff.)', r.pin_nom, c.efficiency);
    end
    lines{end+1} = sprintf('Frequency = %g kHz', c.fsw_khz);

    fprintf('[DEBUG] findobj for display text...\n');
    txt = findobj(fig, 'Style', 'text', '-regexp', 'String', '(computing|---.*Design)');
    if ~isempty(txt)
        set(txt(1), 'String', strjoin(lines, char(10)));
    end
    fprintf('[DEBUG] update_topology_requirements_display done\n');
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
    spec.topology_display = data.topology_display;
    spec.design_mode = data.design_mode;

    % Converter specs
    spec.converter = data.converter;
    spec.converter.fsw_hz = data.converter.fsw_khz * 1e3;

    % Computed requirements
    spec.requirements = data.requirements;
    spec.requirements.n_windings = data.requirements.n_windings;

    % MAS inputs (from Python topology calculator)
    if ~isempty(data.mas_inputs) && isstruct(data.mas_inputs)
        spec.mas_inputs = data.mas_inputs;
    else
        spec.mas_inputs = [];
    end

    % Operating points will be generated by the Python script
    spec.operating_points = [];

    % Recommendation (if user selected one)
    spec.recommendation = struct();
    if data.rec.selected_idx > 0 && data.rec.selected_idx <= numel(data.rec.results)
        spec.recommendation = data.rec.results{data.rec.selected_idx};
    end

    % Core-loss method preferences — pass through to interactive designer
    % Default to iGSE; carry Steinmetz coefficients from recommendation if present.
    spec.core_loss = struct('method', 'iGSE');
    if data.rec.selected_idx > 0 && data.rec.selected_idx <= numel(data.rec.results)
        r = data.rec.results{data.rec.selected_idx};
        if isfield(r, 'steinmetz_k') && ~isempty(r.steinmetz_k)
            spec.core_loss.k     = r.steinmetz_k;
            spec.core_loss.alpha = r.steinmetz_alpha;
            spec.core_loss.beta  = r.steinmetz_beta;
        end
        if isfield(r, 'core_loss_method') && ~isempty(r.core_loss_method)
            spec.core_loss.method = r.core_loss_method;
        end
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

        % Surface any recommendation fallbacks so behavior is explicit.
        notes = '';
        if isfield(results, 'compatibility_filter') && isstruct(results.compatibility_filter)
            cf = results.compatibility_filter;
            if isfield(cf, 'fallback_to_incompatible') && logical(cf.fallback_to_incompatible)
                notes = [notes sprintf('No recommendations matched local GUI core DB. Showing raw adviser cores.\n')];
            elseif isfield(cf, 'skipped_incompatible_cores') && cf.skipped_incompatible_cores > 0
                notes = [notes sprintf('Filtered out %d core(s) not present in local GUI DB.\n', cf.skipped_incompatible_cores)];
            end
        end
        if isfield(results, 'wire_family_filter') && isstruct(results.wire_family_filter)
            wf = results.wire_family_filter;
            if isfield(wf, 'fallback_to_unfiltered') && logical(wf.fallback_to_unfiltered)
                notes = [notes sprintf('Wire-family filter returned 0 matches. Showing unfiltered wire families.\n')];
            end
        end
        if ~isempty(notes)
            warndlg(strtrim(notes), 'Recommendation Notes');
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
    config.topology = data.topology;  % Use selected topology, not hardcoded
    config.max_results = data.rec.n_results;
    config.wire_family_mode = data.rec.wire_family_mode;

    % If MAS inputs already computed, pass them through
    if ~isempty(data.mas_inputs) && isstruct(data.mas_inputs)
        config.mas_inputs = data.mas_inputs;
    end

    config.cores_in_stock = data.rec.cores_in_stock;

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

        % Extract MKF-computed inductance and flux density
        Lm_uH = 0; Llk_uH = 0; B_peak_mT = 0; B_pp_mT = 0;
        has_magnetics = false;
        if isfield(r, 'Lm_uH') && ~isempty(r.Lm_uH)
            Lm_uH = double(r.Lm_uH);
            has_magnetics = true;
        end
        if isfield(r, 'Llk_uH') && ~isempty(r.Llk_uH)
            Llk_uH = double(r.Llk_uH);
        end
        if isfield(r, 'B_peak_mT') && ~isempty(r.B_peak_mT)
            B_peak_mT = double(r.B_peak_mT);
        end
        if isfield(r, 'B_pp_mT') && ~isempty(r.B_pp_mT)
            B_pp_mT = double(r.B_pp_mT);
        end

        rel_pct = 100 * raw_score / max_raw;

        % Build the display line
        line = sprintf('#%d  %s  |  %s  |  Turns: %s', k, core_name, material, turns);
        if has_magnetics
            line = sprintf('%s  |  Lm=%.1fuH  Llk=%.2fuH  Bpk=%.1fmT  dB=%.1fmT', ...
                           line, Lm_uH, Llk_uH, B_peak_mT, B_pp_mT);
        end
        if has_losses
            line = sprintf('%s  |  Loss: %.2fW (C:%.2f+W:%.2f)', ...
                           line, total_loss, core_loss, winding_loss);
        end
        line = sprintf('%s  |  Score: %.0f%%', line, rel_pct);
        items{k} = line;
    end

    [sel, ok] = listdlg('ListString', items, ...
                         'SelectionMode', 'single', ...
                         'Name', 'Select Design Recommendation', ...
                         'ListSize', [1400, 320], ...
                         'PromptString', 'Choose a recommended design (Lm, B, losses computed by OpenMagnetics):');

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


% ===============================================================
% WAVEFORM VISUALIZATION
% ===============================================================

function plot_topology_waveforms(ax, waveforms_preview, topology_name)
    fprintf('[DEBUG] plot_topology_waveforms entered, class=%s, iscell=%d, isstruct=%d, size=[%s]\n', ...
        class(waveforms_preview), iscell(waveforms_preview), isstruct(waveforms_preview), num2str(size(waveforms_preview)));

    if isempty(waveforms_preview)
        cla(ax);
        text(0.5, 0.5, 'No waveform data available', ...
             'Parent', ax, ...
             'HorizontalAlignment', 'center', ...
             'VerticalAlignment', 'middle', ...
             'FontSize', 10, ...
             'Color', [0.5 0.5 0.5]);
        axis(ax, 'off');
        return;
    end

    % Unwrap nested JSON structure: Python generates [[w1, w2, ...]] (outer = op-points, inner = windings).
    % jsondecode produces {[1×N struct]} — a 1-element cell containing a struct array.
    % We only display one operating point, so extract the struct array and convert to cell array.
    if iscell(waveforms_preview) && ~isempty(waveforms_preview)
        first_op = waveforms_preview{1};
        if isstruct(first_op)
            % Convert 1×N struct array → 1×N cell array so each winding is accessible as {k}
            n = numel(first_op);
            tmp = cell(1, n);
            for k = 1:n
                tmp{k} = first_op(k);
            end
            waveforms_preview = tmp;
        elseif iscell(first_op)
            waveforms_preview = first_op;
        end
    end

    % Convert struct array to cell array of individual structs
    if isstruct(waveforms_preview)
        if numel(waveforms_preview) > 1
            n = numel(waveforms_preview);
            tmp = cell(1, n);
            for k = 1:n
                tmp{k} = waveforms_preview(k);
            end
            waveforms_preview = tmp;
        else
            waveforms_preview = {waveforms_preview};
        end
    end

    n_windings = length(waveforms_preview);
    fprintf('[DEBUG] After unwrap: n_windings=%d, iscell=%d\n', n_windings, iscell(waveforms_preview));
    for dbg_k = 1:min(n_windings, 4)
        fprintf('[DEBUG]   winding{%d} class=%s, isstruct=%d\n', dbg_k, class(waveforms_preview{dbg_k}), isstruct(waveforms_preview{dbg_k}));
    end
    if n_windings == 0
        cla(ax);
        text(0.5, 0.5, 'No winding data available', ...
             'Parent', ax, ...
             'HorizontalAlignment', 'center', ...
             'VerticalAlignment', 'middle', ...
             'FontSize', 10, ...
             'Color', [0.5 0.5 0.5]);
        axis(ax, 'off');
        return;
    end

    % Clear axes
    cla(ax);

    % Define colors for different windings
    colors_v = [0.2 0.4 0.8; 0.8 0.2 0.2; 0.2 0.8 0.2; 0.8 0.8 0.2];  % voltage colors
    colors_i = [0.2 0.6 1.0; 1.0 0.2 0.2; 0.2 1.0 0.2; 1.0 1.0 0.2];  % current colors

    % Determine period T from the first winding's voltage or current time array.
    % The Python generator outputs one full period; we repeat for n_cycles.
    n_cycles = 3;
    T = 0;
    for w = 1:n_windings
        winding = waveforms_preview{w};
        if isfield(winding, 'voltage') && isfield(winding.voltage, 'time')
            t_arr = ensure_array(winding.voltage.time);
            if ~isempty(t_arr) && max(t_arr) > 0
                T = max(t_arr);
                break;
            end
        end
        if isfield(winding, 'current') && isfield(winding.current, 'time')
            t_arr = ensure_array(winding.current.time);
            if ~isempty(t_arr) && max(t_arr) > 0
                T = max(t_arr);
                break;
            end
        end
    end
    if T <= 0
        T = 5e-6;  % fallback 5 us period
    end

    % Plot each winding's voltage and current for n_cycles cycles
    legend_handles = [];
    legend_labels = {};

    for w = 1:n_windings
        winding = waveforms_preview{w};

        % Extract winding name
        winding_name = 'Winding';
        if isfield(winding, 'winding_name')
            winding_name = winding.winding_name;
        end

        % Extract voltage data and tile for n_cycles cycles
        if isfield(winding, 'voltage') && isfield(winding.voltage, 'time') && isfield(winding.voltage, 'data')
            v_time = ensure_array(winding.voltage.time);
            v_data = ensure_array(winding.voltage.data);

            if ~isempty(v_time) && ~isempty(v_data) && length(v_time) == length(v_data)
                % Repeat waveform for n_cycles cycles by offsetting time
                v_time_rep = [];
                v_data_rep = [];
                for c = 0:(n_cycles - 1)
                    v_time_rep = [v_time_rep; v_time + c * T];
                    v_data_rep = [v_data_rep; v_data];
                end

                hold(ax, 'on');
                h_v = plot(ax, v_time_rep * 1e6, v_data_rep, '-', ...
                           'Color', colors_v(min(w, size(colors_v, 1)), :), ...
                           'LineWidth', 1.5, 'DisplayName', sprintf('%s Voltage', winding_name));
                legend_handles = [legend_handles, h_v];
                legend_labels = [legend_labels, {sprintf('%s Voltage', winding_name)}];
            end
        end

        % Extract current data and tile for n_cycles cycles
        if isfield(winding, 'current') && isfield(winding.current, 'time') && isfield(winding.current, 'data')
            i_time = ensure_array(winding.current.time);
            i_data = ensure_array(winding.current.data);

            if ~isempty(i_time) && ~isempty(i_data) && length(i_time) == length(i_data)
                % Repeat waveform for n_cycles cycles by offsetting time
                i_time_rep = [];
                i_data_rep = [];
                for c = 0:(n_cycles - 1)
                    i_time_rep = [i_time_rep; i_time + c * T];
                    i_data_rep = [i_data_rep; i_data];
                end

                hold(ax, 'on');
                h_i = plot(ax, i_time_rep * 1e6, i_data_rep, '--', ...
                           'Color', colors_i(min(w, size(colors_i, 1)), :), ...
                           'LineWidth', 1.5, 'DisplayName', sprintf('%s Current', winding_name));
                legend_handles = [legend_handles, h_i];
                legend_labels = [legend_labels, {sprintf('%s Current', winding_name)}];
            end
        end
    end

    % Format axes
    hold(ax, 'off');
    xlabel(ax, 'Time (\mus)', 'FontSize', 9);
    ylabel(ax, 'Voltage (V) / Current (A)', 'FontSize', 9);
    title(ax, sprintf('%s - Waveforms (%d cycles)', topology_name, n_cycles), ...
          'FontSize', 10, 'FontWeight', 'bold');
    grid(ax, 'on');
    grid(ax, 'minor');
    set(ax, 'XGrid', 'on', 'YGrid', 'on');

    % Add legend
    if ~isempty(legend_handles)
        legend(ax, legend_handles, legend_labels, 'Interpreter', 'none', 'FontSize', 8, 'Location', 'best');
    end

end


function arr = ensure_array(data)
    % Ensure data is a column vector (jsondecode may return scalar or array)
    if isnumeric(data)
        if isscalar(data)
            arr = [data];
        else
            arr = data;
            if size(arr, 2) > size(arr, 1)
                arr = arr';  % convert to column if needed
            end
        end
    else
        arr = [];
    end
end


% ===============================================================
% INPUT COLLECTION & API INTEGRATION (Phase 3.4-3.7)
% ===============================================================

function gui_values = collect_gui_field_values(fig, topology_key)
    % Collects all visible GUI field values into a struct for API submission
    %
    % Input:
    %   fig: figure handle
    %   topology_key: topology identifier (e.g., 'two_switch_forward')
    %
    % Output:
    %   gui_values: struct with all converter/thermal/insulation specs

    data = guidata(fig);
    gui_values = struct();

    % ===== REQUIRED FIELDS =====

    % Input voltage (always required)
    gui_values.vin_min = str2double(get(data.edit_vin_min, 'String'));
    gui_values.vin_max = str2double(get(data.edit_vin_max, 'String'));

    % Input voltage nominal (optional, but extract if visible and filled)
    vin_nom_str = get(data.edit_vin_nom, 'String');
    if ~isempty(vin_nom_str)
        gui_values.vin_nom = str2double(vin_nom_str);
    else
        gui_values.vin_nom = [];
    end

    % Switching frequency (kHz)
    gui_values.fsw_khz = str2double(get(data.edit_fsw, 'String'));

    % Diode forward drop voltage
    gui_values.vd = str2double(get(data.edit_vd, 'String'));

    % Output specs
    gui_values.vout = str2double(get(data.edit_vout, 'String'));
    gui_values.iout = str2double(get(data.edit_iout, 'String'));

    % ===== OPTIONAL FIELDS (Extract if visible) =====

    % Efficiency (stored as percent in GUI, keep as-is for conversion in build_mas_structure)
    if isfield(data, 'edit_efficiency') && ~isempty(data.edit_efficiency)
        eff_str = get(data.edit_efficiency, 'String');
        if ~isempty(eff_str)
            gui_values.efficiency = str2double(eff_str);
        else
            gui_values.efficiency = [];
        end
    else
        gui_values.efficiency = [];
    end

    % Max current ripple (stored as percent, keep as-is for conversion in build_mas_structure)
    if isfield(data, 'edit_ripple') && ~isempty(data.edit_ripple)
        ripple_str = get(data.edit_ripple, 'String');
        if ~isempty(ripple_str)
            gui_values.max_ripple = str2double(ripple_str);
        else
            gui_values.max_ripple = [];
        end
    else
        gui_values.max_ripple = [];
    end

    % Max switch current (A, optional)
    if isfield(data, 'edit_max_isw') && ~isempty(data.edit_max_isw)
        max_isw_str = get(data.edit_max_isw, 'String');
        if ~isempty(max_isw_str)
            gui_values.max_switch_current = str2double(max_isw_str);
        else
            gui_values.max_switch_current = [];
        end
    else
        gui_values.max_switch_current = [];
    end

    % Max duty cycle (optional, topology-specific)
    gui_values.max_duty = [];

    % Max drain-source voltage (optional, topology-specific)
    gui_values.max_drain_source_voltage = [];

    % Ambient temperature
    if isfield(data, 'edit_ambient') && ~isempty(data.edit_ambient)
        ambient_str = get(data.edit_ambient, 'String');
        if ~isempty(ambient_str)
            gui_values.ambient_temp = str2double(ambient_str);
        else
            gui_values.ambient_temp = 25;  % default
        end
    else
        gui_values.ambient_temp = 25;
    end

    % ===== INSULATION & THERMAL FIELDS =====

    % Insulation class (from popup)
    if isfield(data, 'pop_insulation') && ~isempty(data.pop_insulation)
        insulation_options = get(data.pop_insulation, 'String');
        insulation_idx = get(data.pop_insulation, 'Value');
        if iscell(insulation_options)
            gui_values.insulation_class = insulation_options{insulation_idx};
        else
            gui_values.insulation_class = insulation_options;
        end
    else
        gui_values.insulation_class = 'Basic';
    end

    % CTI group
    if isfield(data, 'pop_cti') && ~isempty(data.pop_cti)
        cti_options = get(data.pop_cti, 'String');
        cti_idx = get(data.pop_cti, 'Value');
        if iscell(cti_options)
            gui_values.cti = cti_options{cti_idx};
        else
            gui_values.cti = cti_options;
        end
    else
        gui_values.cti = 'Group II';
    end

    % Pollution degree
    if isfield(data, 'pop_pollution') && ~isempty(data.pop_pollution)
        pollution_str = get(data.pop_pollution, 'String');
        pollution_idx = get(data.pop_pollution, 'Value');
        if iscell(pollution_str)
            gui_values.pollution_degree = str2double(pollution_str{pollution_idx});
        else
            gui_values.pollution_degree = str2double(pollution_str);
        end
    else
        gui_values.pollution_degree = 2;
    end

    % Overvoltage category
    if isfield(data, 'pop_ovc') && ~isempty(data.pop_ovc)
        ovc_options = get(data.pop_ovc, 'String');
        ovc_idx = get(data.pop_ovc, 'Value');
        if iscell(ovc_options)
            gui_values.overvoltage_cat = ovc_options{ovc_idx};
        else
            gui_values.overvoltage_cat = ovc_options;
        end
    else
        gui_values.overvoltage_cat = 'II';
    end

    % Insulation standard
    if isfield(data, 'pop_ins_std') && ~isempty(data.pop_ins_std)
        ins_std_options = get(data.pop_ins_std, 'String');
        ins_std_idx = get(data.pop_ins_std, 'Value');
        if iscell(ins_std_options)
            gui_values.insulation_standard = ins_std_options{ins_std_idx};
        else
            gui_values.insulation_standard = ins_std_options;
        end
    else
        gui_values.insulation_standard = 'IEC 62368-1';
    end

    % Maximum temperature rise
    if isfield(data, 'edit_max_rise') && ~isempty(data.edit_max_rise)
        max_rise_str = get(data.edit_max_rise, 'String');
        if ~isempty(max_rise_str)
            gui_values.max_temp_rise = str2double(max_rise_str);
        else
            gui_values.max_temp_rise = 40;
        end
    else
        gui_values.max_temp_rise = 40;
    end

    % Size constraints (optional)
    gui_values.max_width_mm = [];
    gui_values.max_height_mm = [];
    gui_values.max_depth_mm = [];

    if isfield(data, 'edit_max_width') && ~isempty(data.edit_max_width)
        width_str = get(data.edit_max_width, 'String');
        if ~isempty(width_str)
            gui_values.max_width_mm = str2double(width_str);
        end
    end
    if isfield(data, 'edit_max_height') && ~isempty(data.edit_max_height)
        height_str = get(data.edit_max_height, 'String');
        if ~isempty(height_str)
            gui_values.max_height_mm = str2double(height_str);
        end
    end
    if isfield(data, 'edit_max_depth') && ~isempty(data.edit_max_depth)
        depth_str = get(data.edit_max_depth, 'String');
        if ~isempty(depth_str)
            gui_values.max_depth_mm = str2double(depth_str);
        end
    end

end


function display_api_results(fig, results)
    % Display PyOpenMagnetics adviser results in the recommendation panel
    %
    % Input:
    %   fig: figure handle
    %   results: struct from om_topology_api_results.json containing:
    %     .status: 'OK' or 'ERROR'
    %     .data: array of 1-5 design results, each with:
    %       .magnetic.core.name
    %       .outputs.powerLosses.total (W)
    %       .outputs.temperature (C)

    data = guidata(fig);

    % Clear previous results
    if isfield(data, 'rec') && isfield(data.rec, 'result_buttons')
        for i = 1:length(data.rec.result_buttons)
            delete(data.rec.result_buttons{i});
        end
        data.rec.result_buttons = {};
    end

    % Check API status
    if ~isfield(results, 'status') || ~strcmp(results.status, 'OK')
        error_msg = 'API call failed';
        if isfield(results, 'error')
            error_msg = results.error;
        end
        msgbox(sprintf('API Error: %s', error_msg), 'Error', 'error');
        guidata(fig, data);
        return;
    end

    % Extract results
    if ~isfield(results, 'data') || isempty(results.data)
        msgbox('No recommendations generated. Check your input parameters.', 'Warning', 'warn');
        guidata(fig, data);
        return;
    end

    result_data = results.data;
    if ~iscell(result_data)
        result_data = {result_data};
    end

    n_results = min(length(result_data), 5);  % max 5 results

    fprintf('[TOPOLOGY] Displaying %d API results\n', n_results);

    % Store results for selection callback
    data.api_results = results;
    data.rec.result_buttons = {};

    % Create button for each result
    for i = 1:n_results
        result = result_data{i};

        % Extract core name
        core_name = 'Unknown';
        if isfield(result, 'magnetic') && isfield(result.magnetic, 'core') && ...
           isfield(result.magnetic.core, 'name')
            core_name = result.magnetic.core.name;
        end

        % Extract total losses (W)
        total_losses = 0;
        if isfield(result, 'outputs') && isfield(result.outputs, 'powerLosses') && ...
           isfield(result.outputs.powerLosses, 'total')
            total_losses = result.outputs.powerLosses.total;
        end

        % Extract temperature (C)
        temperature = 25;
        if isfield(result, 'outputs') && isfield(result.outputs, 'temperature')
            temperature = result.outputs.temperature;
        end

        % Create button label
        btn_label = sprintf('[%d] %s | Losses: %.2fW | Temp: %.0fC', ...
                           i, core_name, total_losses, temperature);

        % Position buttons vertically in recommendation panel
        % Assuming rec_panel height is ~0.28 normalized, buttons should fit in grid
        y_pos = 0.50 - (i - 1) * 0.08;  % top-down layout

        % Create button (positioned in figure, mapped to rec_panel later)
        btn = uicontrol('Parent', data.fig, 'Style', 'pushbutton', ...
                       'String', btn_label, ...
                       'Units', 'normalized', ...
                       'Position', [0.52 y_pos 0.46 0.075], ...
                       'FontSize', 8, ...
                       'HorizontalAlignment', 'left', ...
                       'BackgroundColor', [0.85 0.85 0.85], ...
                       'Callback', {@cb_select_design, i, fig});

        data.rec.result_buttons{i} = btn;
    end

    % Show result count
    count_label = sprintf('Results: %d recommendations', n_results);
    if isfield(data, 'txt_rec_count')
        set(data.txt_rec_count, 'String', count_label);
    end

    fprintf('[TOPOLOGY] API results displayed successfully\n');
    guidata(fig, data);
end


function cb_select_design(hObject, eventdata, selected_idx, fig)
    % Handle design selection from API results
    %
    % Input:
    %   hObject: callback object (button)
    %   eventdata: event data (unused)
    %   selected_idx: index of selected design (1-5)
    %   fig: figure handle

    data = guidata(fig);

    fprintf('[TOPOLOGY] Design %d selected\n', selected_idx);

    % Store selection
    data.rec.selected_idx = selected_idx;

    % Extract full design from API results
    if isfield(data, 'api_results') && isfield(data.api_results, 'data')
        result_data = data.api_results.data;
        if ~iscell(result_data)
            result_data = {result_data};
        end

        if selected_idx <= length(result_data)
            data.rec.results = result_data{selected_idx};
        end
    end

    % Highlight selected button
    for i = 1:length(data.rec.result_buttons)
        if i == selected_idx
            set(data.rec.result_buttons{i}, 'BackgroundColor', [0.2 0.6 0.8], ...
                                            'ForegroundColor', 'w', 'FontWeight', 'bold');
        else
            set(data.rec.result_buttons{i}, 'BackgroundColor', [0.85 0.85 0.85], ...
                                            'ForegroundColor', 'k', 'FontWeight', 'normal');
        end
    end

    guidata(fig, data);

    % Proceed to winding designer with selected design
    try
        % Validate required fields before continuing
        c = data.converter;
        if c.vin_min <= 0 || c.vin_max <= 0 || c.vout <= 0 || c.iout <= 0 || c.fsw_khz <= 0
            errordlg('Please fill in all required converter specifications.', 'Missing Data');
            return;
        end
        if c.vin_min >= c.vin_max
            errordlg('Input voltage min must be less than max.', 'Invalid Data');
            return;
        end

        % Build design spec from topology wizard + API results
        spec = build_design_spec_wizard(data);
        fprintf('[TOPOLOGY] Launching winding designer with API-selected design...\n');
        launch_winding_designer(spec);

    catch err
        fprintf('[TOPOLOGY] Error launching winding designer: %s\n', err.message);
        errordlg(sprintf('Failed to launch winding designer:\n%s', err.message), 'Error');
    end
end
