function fig = topology_waveform_viewer(converter_spec, topology_key, topology_results, python_path)
% TOPOLOGY_WAVEFORM_VIEWER  Standalone waveform viewer with C++-equivalent equations.
%
% Opens a dedicated figure window showing per-winding voltage/current waveforms
% for min and max input voltage operating points. Uses converter equations ported
% from MKF C++ source for accurate analytical waveform generation.
%
% Usage:
%   fig = topology_waveform_viewer(converter_spec, topology_key)
%   fig = topology_waveform_viewer(converter_spec, topology_key, topology_results)
%   fig = topology_waveform_viewer(converter_spec, topology_key, topology_results, python_path)
%
% Inputs:
%   converter_spec   - struct with fields: vin_min, vin_max, vin_nom, vd, fsw_khz,
%                      output_voltages, output_currents, efficiency, max_ripple, etc.
%   topology_key     - string: 'two_switch_forward', 'flyback', 'buck', etc.
%   topology_results - (optional) struct with Lm_uH, turns_ratios, Lout_uH from
%                      generate_om_topology.py compute step
%   python_path      - (optional) confirmed Python executable path from caller
%
% The figure stores waveform data in guidata for downstream PEEC extraction.

    if nargin < 3
        topology_results = struct();
    end
    if nargin < 4
        python_path = '';
    end

    % ── Find or create the waveform viewer figure ──
    fig = findobj('Type', 'figure', 'Tag', 'topology_waveform_viewer');
    if isempty(fig)
        fig = figure('Tag', 'topology_waveform_viewer', ...
                     'Name', 'Topology Waveforms', ...
                     'NumberTitle', 'off', ...
                     'Position', [100 50 900 750], ...
                     'Color', [0.10 0.10 0.18], ...
                     'MenuBar', 'none', ...
                     'ToolBar', 'figure');
    else
        fig = fig(1);
        figure(fig);
    end

    % ── Store state in figure ──
    state = struct();
    state.converter_spec = converter_spec;
    state.topology_key = topology_key;
    state.topology_results = topology_results;
    state.n_periods = 2;
    state.n_steady = 10;
    state.python_path = python_path;  % Confirmed Python from caller
    state.waveform_data = [];  % Will hold results from Python
    state.axes_handles = [];

    % ── Clear figure content ──
    clf(fig);
    set(fig, 'Color', [0.10 0.10 0.18]);

    % ── Create control panel at top ──
    ctrl_panel = uipanel('Parent', fig, ...
                         'Units', 'normalized', ...
                         'Position', [0 0.94 1 0.06], ...
                         'BackgroundColor', [0.14 0.14 0.22], ...
                         'BorderType', 'none');

    % Waveforms icon/title
    uicontrol('Parent', ctrl_panel, 'Style', 'text', ...
              'Units', 'normalized', 'Position', [0.01 0.1 0.12 0.8], ...
              'String', 'Waveforms', ...
              'FontSize', 11, 'FontWeight', 'bold', ...
              'ForegroundColor', [0.85 0.85 0.95], ...
              'BackgroundColor', [0.14 0.14 0.22], ...
              'HorizontalAlignment', 'left');

    % Periods label
    uicontrol('Parent', ctrl_panel, 'Style', 'text', ...
              'Units', 'normalized', 'Position', [0.15 0.1 0.08 0.8], ...
              'String', 'Periods:', ...
              'FontSize', 9, ...
              'ForegroundColor', [0.7 0.7 0.8], ...
              'BackgroundColor', [0.14 0.14 0.22], ...
              'HorizontalAlignment', 'right');

    % Periods dropdown
    periods_items = arrayfun(@num2str, 1:10, 'UniformOutput', false);
    h_periods = uicontrol('Parent', ctrl_panel, 'Style', 'popupmenu', ...
              'Units', 'normalized', 'Position', [0.24 0.15 0.06 0.7], ...
              'String', periods_items, ...
              'Value', 2, ...  % Default: 2 periods
              'FontSize', 9, ...
              'BackgroundColor', [0.20 0.20 0.30], ...
              'ForegroundColor', [0.9 0.9 1.0], ...
              'Tag', 'periods_dropdown');

    % Steady label
    uicontrol('Parent', ctrl_panel, 'Style', 'text', ...
              'Units', 'normalized', 'Position', [0.32 0.1 0.07 0.8], ...
              'String', 'Steady:', ...
              'FontSize', 9, ...
              'ForegroundColor', [0.7 0.7 0.8], ...
              'BackgroundColor', [0.14 0.14 0.22], ...
              'HorizontalAlignment', 'right');

    % Steady field
    h_steady = uicontrol('Parent', ctrl_panel, 'Style', 'edit', ...
              'Units', 'normalized', 'Position', [0.40 0.15 0.06 0.7], ...
              'String', '10', ...
              'FontSize', 9, ...
              'BackgroundColor', [0.20 0.20 0.30], ...
              'ForegroundColor', [0.5 0.5 0.6], ...
              'Enable', 'off', ...  % Disabled until Simulated mode
              'Tag', 'steady_field');

    % Analytical button
    h_analytical = uicontrol('Parent', ctrl_panel, 'Style', 'pushbutton', ...
              'Units', 'normalized', 'Position', [0.55 0.1 0.14 0.8], ...
              'String', 'Analytical', ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.20 0.45 0.65], ...
              'ForegroundColor', [1 1 1], ...
              'Tag', 'btn_analytical');

    % Simulated button (grayed out)
    h_simulated = uicontrol('Parent', ctrl_panel, 'Style', 'pushbutton', ...
              'Units', 'normalized', 'Position', [0.71 0.1 0.14 0.8], ...
              'String', 'Simulated', ...
              'FontSize', 9, ...
              'BackgroundColor', [0.25 0.25 0.35], ...
              'ForegroundColor', [0.5 0.5 0.6], ...
              'Enable', 'off', ...
              'TooltipString', 'Requires ngspice (future feature)', ...
              'Tag', 'btn_simulated');

    % Store handles
    state.h_periods = h_periods;
    state.h_steady = h_steady;
    state.h_analytical = h_analytical;

    % ── Create scrollable plot area ──
    state.plot_panel = uipanel('Parent', fig, ...
                               'Units', 'normalized', ...
                               'Position', [0 0 1 0.94], ...
                               'BackgroundColor', [0.10 0.10 0.18], ...
                               'BorderType', 'none');

    % Store state before setting callbacks (callbacks need state handle)
    guidata(fig, state);

    % ── Set callbacks ──
    set(h_periods, 'Callback', @cb_periods_changed);
    set(h_analytical, 'Callback', @cb_analytical_clicked);

    % ── Auto-run analytical waveforms ──
    show_loading_message(state.plot_panel);
    drawnow();
    run_analytical_waveforms(fig);
end


% ═══════════════════════════════════════════════════════════════════════════════
% CALLBACKS
% ═══════════════════════════════════════════════════════════════════════════════

function cb_analytical_clicked(src, ~)
    fig = ancestor(src, 'figure');
    state = guidata(fig);
    show_loading_message(state.plot_panel);
    drawnow();
    run_analytical_waveforms(fig);
end

function cb_periods_changed(src, ~)
    fig = ancestor(src, 'figure');
    state = guidata(fig);
    state.n_periods = get(src, 'Value');
    guidata(fig, state);
    % Re-render with new period count (no Python call needed)
    if ~isempty(state.waveform_data)
        render_waveforms(fig);
    end
end


% ═══════════════════════════════════════════════════════════════════════════════
% PYTHON BRIDGE
% ═══════════════════════════════════════════════════════════════════════════════

function run_analytical_waveforms(fig)
% Call generate_om_waveforms.py to get analytical waveforms (ported C++ equations).
    state = guidata(fig);

    % Build config JSON
    config = struct();
    config.topology = state.topology_key;
    config.mode = 'analytical';
    config.numberOfPeriods = state.n_periods;

    % Converter spec
    config.converter = state.converter_spec;

    % Topology results (inductance, turns ratios)
    if isstruct(state.topology_results) && ~isempty(fieldnames(state.topology_results))
        config.topology_results = state.topology_results;
    end

    config.output_file = 'om_waveform_results.json';

    % Write config
    script_dir = fileparts(mfilename('fullpath'));
    if isempty(script_dir)
        script_dir = pwd();
    end
    config_path = fullfile(script_dir, 'om_waveform_config.json');
    result_path = fullfile(script_dir, 'om_waveform_results.json');

    try
        json_str = jsonencode(config);
        fid = fopen(config_path, 'w');
        fprintf(fid, '%s', json_str);
        fclose(fid);
    catch err
        show_error_message(state.plot_panel, sprintf('JSON encode error: %s', err.message));
        return;
    end

    % Find Python executable — use passed-in path or discover
    script_path = fullfile(script_dir, 'generate_om_waveforms.py');
    script_path_unix = strrep(script_path, '\', '/');
    config_path_unix = strrep(config_path, '\', '/');

    % Build list of Python candidates to try
    py_candidates = {};
    % 1) Use confirmed path from caller (topology_wizard)
    if ~isempty(state.python_path)
        py_candidates{end+1} = state.python_path;
    end
    % 2) Explicit Python 3.11 path (known to have PyOpenMagnetics)
    p311 = 'C:/Users/Will/AppData/Local/Programs/Python/Python311/python.exe';
    py_candidates{end+1} = p311;
    % 3) System python
    py_candidates{end+1} = 'python';

    status = -1;
    output = '';
    found_py = '';
    for k = 1:numel(py_candidates)
        py = py_candidates{k};
        % Strip surrounding quotes if present (from topology_wizard format)
        if length(py) > 1 && py(1) == '"' && py(end) == '"'
            py = py(2:end-1);
        end
        cmd = sprintf('"%s" "%s" "%s" 2>&1', py, script_path_unix, config_path_unix);
        fprintf('[WAVEFORM] Trying: %s\n', cmd);
        [status, output] = system(cmd);
        fprintf('[WAVEFORM] Exit code: %d\n', status);
        if status == 0
            found_py = py;
            fprintf('[WAVEFORM] Success with: %s\n', py);
            break;
        end
    end

    if status ~= 0
        show_error_message(state.plot_panel, sprintf('Python error (exit %d): %s', status, strtrim(output)));
        return;
    end

    % Store confirmed Python for next time
    state.python_path = found_py;
    guidata(fig, state);

    % Read results
    if ~exist(result_path, 'file')
        show_error_message(state.plot_panel, 'Results file not found');
        return;
    end

    try
        result_json = fileread(result_path);
        results = jsondecode(result_json);
    catch err
        show_error_message(state.plot_panel, sprintf('JSON decode error: %s', err.message));
        return;
    end

    if ~isfield(results, 'status') || ~strcmp(results.status, 'OK')
        msg = 'Unknown error';
        if isfield(results, 'message')
            msg = results.message;
        end
        show_error_message(state.plot_panel, sprintf('API error: %s', msg));
        return;
    end

    % Store waveform data
    state.waveform_data = results;
    guidata(fig, state);

    fprintf('[WAVEFORM] Success: %d operating points\n', numel(results.operatingPoints));

    % Render
    render_waveforms(fig);
end



% ═══════════════════════════════════════════════════════════════════════════════
% WAVEFORM RENDERING
% ═══════════════════════════════════════════════════════════════════════════════

function render_waveforms(fig)
% Render all waveform subplots from stored data.
    state = guidata(fig);
    results = state.waveform_data;
    n_periods = state.n_periods;

    % Clear plot panel
    delete(get(state.plot_panel, 'Children'));

    op_points = results.operatingPoints;
    if isstruct(op_points)
        % jsondecode may return struct array instead of cell
        n_ops = numel(op_points);
        tmp = cell(1, n_ops);
        for k = 1:n_ops
            tmp{k} = op_points(k);
        end
        op_points = tmp;
    elseif ~iscell(op_points)
        op_points = {op_points};
    end

    n_ops = numel(op_points);

    % Count total subplots needed
    total_subplots = 0;
    for i = 1:n_ops
        op = op_points{i};
        exc = get_excitations(op);
        total_subplots = total_subplots + numel(exc);
    end

    if total_subplots == 0
        show_error_message(state.plot_panel, 'No winding excitations found in results');
        return;
    end

    % Colors matching OpenMagnetics theme
    color_voltage = [0.30 0.85 0.40];   % Green
    color_current = [0.65 0.40 0.85];   % Purple

    % Section label color
    label_color = [0.45 0.75 0.90];     % Light cyan

    % Compute layout heights
    % Each OP section: label (small) + N winding subplots
    label_height = 0.035;
    gap = 0.015;
    available_height = 1.0 - gap;
    total_labels = n_ops;
    plot_area = available_height - total_labels * (label_height + gap);
    subplot_height = plot_area / max(total_subplots, 1) - gap;
    subplot_height = max(subplot_height, 0.08);

    % Build subplots from top to bottom
    y_pos = 1.0 - gap;
    subplot_idx = 0;
    state.axes_handles = [];

    for i = 1:n_ops
        op = op_points{i};

        % Operating point label
        op_label = 'Operating Point';
        if isfield(op, 'label')
            op_label = op.label;
        end

        y_pos = y_pos - label_height;
        uicontrol('Parent', state.plot_panel, 'Style', 'text', ...
                  'Units', 'normalized', ...
                  'Position', [0.02 y_pos 0.96 label_height], ...
                  'String', op_label, ...
                  'FontSize', 10, 'FontWeight', 'bold', ...
                  'ForegroundColor', label_color, ...
                  'BackgroundColor', [0.10 0.10 0.18], ...
                  'HorizontalAlignment', 'left');
        y_pos = y_pos - gap;

        % Get excitations for this OP
        exc_list = get_excitations(op);

        for j = 1:numel(exc_list)
            exc = exc_list{j};
            subplot_idx = subplot_idx + 1;

            y_pos = y_pos - subplot_height;
            ax = axes('Parent', state.plot_panel, ...
                      'Units', 'normalized', ...
                      'Position', [0.10 y_pos 0.80 subplot_height - gap], ...
                      'Color', [0.12 0.12 0.20], ...
                      'XColor', [0.5 0.5 0.6], ...
                      'GridColor', [0.25 0.25 0.35], ...
                      'GridAlpha', 0.5, ...
                      'Box', 'on');
            hold(ax, 'on');
            grid(ax, 'on');

            state.axes_handles(end+1) = ax;

            % Winding name
            winding_name = sprintf('Winding %d', j);
            if isfield(exc, 'name')
                winding_name = exc.name;
            end

            % Extract frequency for period calculation
            freq = 0;
            if isfield(exc, 'frequency')
                freq = exc.frequency;
            end

            % ── Plot voltage on left Y-axis (primary axes) ──
            set(ax, 'YColor', color_voltage);

            v_time = [];
            v_data = [];
            if isfield(exc, 'voltage') && isstruct(exc.voltage)
                [v_time, v_data] = extract_waveform_arrays(exc.voltage, freq);
            end

            if ~isempty(v_time) && ~isempty(v_data)
                [vt_rep, vd_rep] = tile_waveform(v_time, v_data, n_periods);
                plot(ax, vt_rep * 1e6, vd_rep, '-', ...
                     'Color', color_voltage, 'LineWidth', 1.5);

                % Auto-scale with margin
                v_range = max(vd_rep) - min(vd_rep);
                if v_range > 0
                    v_margin = v_range * 0.15;
                    ylim(ax, [min(vd_rep) - v_margin, max(vd_rep) + v_margin]);
                end
            end

            ylabel(ax, 'V', 'Color', color_voltage, 'FontSize', 8);

            % Format voltage tick labels
            ytl = get(ax, 'YTick');
            ytls = cell(size(ytl));
            for t = 1:numel(ytl)
                ytls{t} = sprintf('%.4g V', ytl(t));
            end
            set(ax, 'YTickLabel', ytls);

            % ── Create overlaid axes for current (right Y-axis) ──
            % Octave lacks yyaxis(), so we overlay a second transparent axes
            ax_pos = get(ax, 'Position');
            ax2 = axes('Parent', state.plot_panel, ...
                       'Units', 'normalized', ...
                       'Position', ax_pos, ...
                       'YAxisLocation', 'right', ...
                       'Color', 'none', ...
                       'Box', 'off', ...
                       'YColor', color_current, ...
                       'XColor', [0.12 0.12 0.20]);
            set(ax2, 'XTick', []);
            hold(ax2, 'on');

            i_time = [];
            i_data = [];
            if isfield(exc, 'current') && isstruct(exc.current)
                [i_time, i_data] = extract_waveform_arrays(exc.current, freq);
            end

            if ~isempty(i_time) && ~isempty(i_data)
                [it_rep, id_rep] = tile_waveform(i_time, i_data, n_periods);
                plot(ax2, it_rep * 1e6, id_rep, '-', ...
                     'Color', color_current, 'LineWidth', 1.5);

                % Auto-scale with margin
                i_range = max(id_rep) - min(id_rep);
                if i_range > 0
                    i_margin = i_range * 0.15;
                    ylim(ax2, [min(id_rep) - i_margin, max(id_rep) + i_margin]);
                end

                % Sync X-axis limits with voltage axes
                xlim(ax2, xlim(ax));
            end

            ylabel(ax2, 'A', 'Color', color_current, 'FontSize', 8);

            % Format current tick labels
            ytl = get(ax2, 'YTick');
            ytls = cell(size(ytl));
            for t = 1:numel(ytl)
                ytls{t} = sprintf('%.4g A', ytl(t));
            end
            set(ax2, 'YTickLabel', ytls);

            % ── X-axis & title ──
            xlabel(ax, '', 'FontSize', 7);
            set(ax, 'XColor', [0.5 0.5 0.6]);

            % Only show x-label on bottom subplot of each group
            if j == numel(exc_list)
                xlabel(ax, 'Time (\mus)', 'Color', [0.6 0.6 0.7], 'FontSize', 8);
            end

            % Format x-axis ticks
            xtl = get(ax, 'XTick');
            xtls = cell(size(xtl));
            for t = 1:numel(xtl)
                xtls{t} = sprintf('%.3g', xtl(t));
            end
            set(ax, 'XTickLabel', xtls);

            % Title: winding name (V=green left axis, A=purple right axis)
            title(ax, winding_name, ...
                  'Color', [0.85 0.85 0.95], 'FontSize', 10, 'FontWeight', 'bold');

            y_pos = y_pos - gap;
        end
    end

    guidata(fig, state);
end


% ═══════════════════════════════════════════════════════════════════════════════
% HELPER FUNCTIONS
% ═══════════════════════════════════════════════════════════════════════════════

function exc_list = get_excitations(op)
% Extract excitations list from an operating point struct.
% Handles jsondecode quirks (struct array vs cell).
    exc_list = {};

    if ~isfield(op, 'excitationsPerWinding')
        return;
    end

    raw = op.excitationsPerWinding;

    if iscell(raw)
        exc_list = raw;
    elseif isstruct(raw)
        n = numel(raw);
        exc_list = cell(1, n);
        for k = 1:n
            exc_list{k} = raw(k);
        end
    end
end


function [t_arr, d_arr] = extract_waveform_arrays(signal, freq)
% Extract time and data arrays from a signal descriptor.
% Handles both waveform format and processed format.
    t_arr = [];
    d_arr = [];

    if isfield(signal, 'waveform') && isstruct(signal.waveform)
        wf = signal.waveform;
        if isfield(wf, 'time') && isfield(wf, 'data')
            t_arr = ensure_col(wf.time);
            d_arr = ensure_col(wf.data);
            return;
        end
    end

    % Fallback: reconstruct from processed parameters
    if isfield(signal, 'processed') && isstruct(signal.processed)
        proc = signal.processed;
        if freq <= 0
            return;
        end
        T = 1.0 / freq;

        label = '';
        if isfield(proc, 'label')
            label = lower(proc.label);
        end

        pp = 0;
        if isfield(proc, 'peakToPeak')
            pp = proc.peakToPeak;
        end

        offset = 0;
        if isfield(proc, 'offset')
            offset = proc.offset;
        end

        dc = 0.5;
        if isfield(proc, 'dutyCycle')
            dc = proc.dutyCycle;
        end

        high_val = offset + pp/2;
        low_val = offset - pp/2;

        if ~isempty(strfind(label, 'rectangular')) || ~isempty(strfind(label, 'flyback'))
            % Rectangular waveform: 4 points
            t_arr = [0; dc*T; dc*T; T];
            d_arr = [high_val; high_val; low_val; low_val];
        elseif ~isempty(strfind(label, 'triangular'))
            % Triangular waveform: 3 points
            t_arr = [0; dc*T; T];
            d_arr = [low_val; high_val; low_val];
        elseif ~isempty(strfind(label, 'sinusoidal'))
            % Sinusoidal: 100 points
            n_pts = 100;
            t_arr = linspace(0, T, n_pts)';
            d_arr = offset + (pp/2) * sin(2*pi*t_arr/T);
        else
            % Default: rectangular
            t_arr = [0; dc*T; dc*T; T];
            d_arr = [high_val; high_val; low_val; low_val];
        end
    end
end


function [t_rep, d_rep] = tile_waveform(t_arr, d_arr, n_periods)
% Repeat a single-period waveform for n_periods cycles.
    if isempty(t_arr) || isempty(d_arr)
        t_rep = t_arr;
        d_rep = d_arr;
        return;
    end

    T = t_arr(end) - t_arr(1);
    if T <= 0
        T = 1e-6;  % Fallback
    end

    t_rep = [];
    d_rep = [];
    for c = 0:(n_periods - 1)
        t_rep = [t_rep; t_arr + c * T];
        d_rep = [d_rep; d_arr];
    end
end


function v = ensure_col(v)
% Ensure value is a column vector.
    if isscalar(v)
        return;
    end
    if isrow(v)
        v = v(:);
    end
end


function show_loading_message(panel)
% Show loading indicator in the plot panel.
    delete(get(panel, 'Children'));
    uicontrol('Parent', panel, 'Style', 'text', ...
              'Units', 'normalized', 'Position', [0.2 0.4 0.6 0.2], ...
              'String', 'Computing analytical waveforms...', ...
              'FontSize', 12, ...
              'ForegroundColor', [0.6 0.6 0.8], ...
              'BackgroundColor', [0.10 0.10 0.18], ...
              'HorizontalAlignment', 'center');
end


function show_error_message(panel, msg)
% Show error message in the plot panel.
    delete(get(panel, 'Children'));
    uicontrol('Parent', panel, 'Style', 'text', ...
              'Units', 'normalized', 'Position', [0.05 0.3 0.9 0.4], ...
              'String', sprintf('Error: %s', msg), ...
              'FontSize', 10, ...
              'ForegroundColor', [0.95 0.40 0.40], ...
              'BackgroundColor', [0.10 0.10 0.18], ...
              'HorizontalAlignment', 'center');
    fprintf('[WAVEFORM] ERROR: %s\n', msg);
end
