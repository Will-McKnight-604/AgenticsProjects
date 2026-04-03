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
    % Update line data only — no axes rebuild needed
    if ~isempty(state.waveform_data)
        if isfield(state, 'voltage_lines') && ~isempty(state.voltage_lines)
            update_plot_data(fig);
        else
            render_waveforms(fig);
        end
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

    % Timeout in seconds for Python subprocess
    py_timeout = 30;

    % Try cached Python path first (skip discovery on repeat calls)
    status = -1;
    output = '';
    if ~isempty(state.python_path)
        py = state.python_path;
        if length(py) > 1 && py(1) == '"' && py(end) == '"'
            py = py(2:end-1);
        end
        cmd = sprintf('timeout %d "%s" "%s" "%s" 2>&1', py_timeout, py, script_path_unix, config_path_unix);
        fprintf('[WAVEFORM] Using cached Python: %s\n', py);
        [status, output] = system(cmd);
        if status == 124
            show_error_message(state.plot_panel, sprintf('Python timed out after %ds', py_timeout));
            return;
        end
    end

    % Fall back to discovery if cached path failed or not set
    if status ~= 0
        py_candidates = { ...
            'C:/Users/Will/AppData/Local/Programs/Python/Python311/python.exe', ...
            'python' ...
        };
        for k = 1:numel(py_candidates)
            py = py_candidates{k};
            cmd = sprintf('timeout %d "%s" "%s" "%s" 2>&1', py_timeout, py, script_path_unix, config_path_unix);
            fprintf('[WAVEFORM] Trying: %s\n', cmd);
            [status, output] = system(cmd);
            if status == 124
                show_error_message(state.plot_panel, sprintf('Python timed out after %ds', py_timeout));
                return;
            end
            if status == 0
                fprintf('[WAVEFORM] Found Python: %s\n', py);
                break;
            end
        end
    end

    if status ~= 0
        show_error_message(state.plot_panel, sprintf('Python error (exit %d): %s', status, strtrim(output)));
        return;
    end

    % Cache confirmed Python for next call
    state.python_path = py;
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
% On first call or layout change: creates axes and lines, stores handles.
% On subsequent calls with same layout: updates line data only.
    state = guidata(fig);
    results = state.waveform_data;

    % Normalize operating points to cell array
    op_points = normalize_op_points(results.operatingPoints);
    n_ops = numel(op_points);

    % Count total subplots needed
    total_subplots = 0;
    for i = 1:n_ops
        exc = get_excitations(op_points{i});
        total_subplots = total_subplots + numel(exc);
    end

    if total_subplots == 0
        show_error_message(state.plot_panel, 'No winding excitations found in results');
        return;
    end

    % Check if layout can be reused
    can_reuse = isfield(state, 'cached_subplot_count') ...
                && state.cached_subplot_count == total_subplots ...
                && isfield(state, 'voltage_lines') ...
                && numel(state.voltage_lines) == total_subplots ...
                && all(cellfun(@ishandle, state.voltage_lines)) ...
                && all(cellfun(@ishandle, state.current_lines));

    if ~can_reuse
        create_plot_layout(fig, op_points, total_subplots);
    end

    update_plot_data(fig);
end


function create_plot_layout(fig, op_points, total_subplots)
% Create axes, labels, and empty line objects. Store handles in state.
    state = guidata(fig);
    n_ops = numel(op_points);

    % Clear existing content
    delete(get(state.plot_panel, 'Children'));

    % Colors matching OpenMagnetics theme
    color_voltage = [0.30 0.85 0.40];   % Green
    color_current = [0.65 0.40 0.85];   % Purple
    label_color = [0.45 0.75 0.90];     % Light cyan

    % Compute layout heights
    label_height = 0.035;
    gap = 0.015;
    available_height = 1.0 - gap;
    plot_area = available_height - n_ops * (label_height + gap);
    subplot_height = plot_area / max(total_subplots, 1) - gap;
    subplot_height = max(subplot_height, 0.08);

    % Pre-allocate handle storage
    state.voltage_axes = cell(1, total_subplots);
    state.current_axes = cell(1, total_subplots);
    state.voltage_lines = cell(1, total_subplots);
    state.current_lines = cell(1, total_subplots);
    state.cached_subplot_count = total_subplots;
    state.axes_handles = [];

    % Build subplots from top to bottom
    y_pos = 1.0 - gap;
    subplot_idx = 0;

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

        exc_list = get_excitations(op);

        for j = 1:numel(exc_list)
            exc = exc_list{j};
            subplot_idx = subplot_idx + 1;

            y_pos = y_pos - subplot_height;

            % Voltage axes (left Y)
            ax = axes('Parent', state.plot_panel, ...
                      'Units', 'normalized', ...
                      'Position', [0.10 y_pos 0.80 subplot_height - gap], ...
                      'Color', [0.12 0.12 0.20], ...
                      'XColor', [0.5 0.5 0.6], ...
                      'YColor', color_voltage, ...
                      'GridColor', [0.25 0.25 0.35], ...
                      'GridAlpha', 0.5, ...
                      'Box', 'on');
            hold(ax, 'on');
            grid(ax, 'on');
            ylabel(ax, 'V', 'Color', color_voltage, 'FontSize', 8);

            % Create empty voltage line
            hv = plot(ax, 0, 0, '-', 'Color', color_voltage, 'LineWidth', 1.5);
            state.voltage_axes{subplot_idx} = ax;
            state.voltage_lines{subplot_idx} = hv;
            state.axes_handles(end+1) = ax;

            % Current axes (right Y, overlaid)
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
            ylabel(ax2, 'A', 'Color', color_current, 'FontSize', 8);

            % Create empty current line
            hi = plot(ax2, 0, 0, '-', 'Color', color_current, 'LineWidth', 1.5);
            state.current_axes{subplot_idx} = ax2;
            state.current_lines{subplot_idx} = hi;

            % Winding name title
            winding_name = sprintf('Winding %d', j);
            if isfield(exc, 'name')
                winding_name = exc.name;
            end
            title(ax, winding_name, ...
                  'Color', [0.85 0.85 0.95], 'FontSize', 10, 'FontWeight', 'bold');

            % X-axis label on bottom subplot only
            xlabel(ax, '', 'FontSize', 7);
            if j == numel(exc_list)
                xlabel(ax, 'Time (\mus)', 'Color', [0.6 0.6 0.7], 'FontSize', 8);
            end

            y_pos = y_pos - gap;
        end
    end

    guidata(fig, state);
end


function update_plot_data(fig)
% Update XData/YData on existing line handles — no axes recreation.
    state = guidata(fig);
    results = state.waveform_data;
    n_periods = state.n_periods;

    op_points = normalize_op_points(results.operatingPoints);
    n_ops = numel(op_points);
    subplot_idx = 0;

    for i = 1:n_ops
        exc_list = get_excitations(op_points{i});

        for j = 1:numel(exc_list)
            exc = exc_list{j};
            subplot_idx = subplot_idx + 1;

            if subplot_idx > numel(state.voltage_lines)
                break;
            end

            ax = state.voltage_axes{subplot_idx};
            ax2 = state.current_axes{subplot_idx};
            hv = state.voltage_lines{subplot_idx};
            hi = state.current_lines{subplot_idx};

            % Extract frequency
            freq = 0;
            if isfield(exc, 'frequency')
                freq = exc.frequency;
            end

            % ── Update voltage line ──
            v_time = [];
            v_data = [];
            if isfield(exc, 'voltage') && isstruct(exc.voltage)
                [v_time, v_data] = extract_waveform_arrays(exc.voltage, freq);
            end

            if ~isempty(v_time) && ~isempty(v_data)
                [vt_rep, vd_rep] = tile_waveform(v_time, v_data, n_periods);
                if any(~isfinite(vt_rep)) || any(~isfinite(vd_rep))
                    vt_rep(~isfinite(vt_rep)) = 0;
                    vd_rep(~isfinite(vd_rep)) = 0;
                end
                set(hv, 'XData', vt_rep * 1e6, 'YData', vd_rep);
                v_range = max(vd_rep) - min(vd_rep);
                if v_range > 0
                    v_margin = v_range * 0.15;
                    ylim(ax, [min(vd_rep) - v_margin, max(vd_rep) + v_margin]);
                end
            else
                set(hv, 'XData', 0, 'YData', 0);
            end

            % ── Update current line ──
            i_time = [];
            i_data = [];
            if isfield(exc, 'current') && isstruct(exc.current)
                [i_time, i_data] = extract_waveform_arrays(exc.current, freq);
            end

            if ~isempty(i_time) && ~isempty(i_data)
                [it_rep, id_rep] = tile_waveform(i_time, i_data, n_periods);
                if any(~isfinite(it_rep)) || any(~isfinite(id_rep))
                    it_rep(~isfinite(it_rep)) = 0;
                    id_rep(~isfinite(id_rep)) = 0;
                end
                set(hi, 'XData', it_rep * 1e6, 'YData', id_rep);
                i_range = max(id_rep) - min(id_rep);
                if i_range > 0
                    i_margin = i_range * 0.15;
                    ylim(ax2, [min(id_rep) - i_margin, max(id_rep) + i_margin]);
                end
                xlim(ax2, xlim(ax));
            else
                set(hi, 'XData', 0, 'YData', 0);
            end
        end
    end
end


function op_points = normalize_op_points(raw)
% Normalize jsondecode operating points to cell array.
    if isstruct(raw)
        n = numel(raw);
        op_points = cell(1, n);
        for k = 1:n
            op_points{k} = raw(k);
        end
    elseif iscell(raw)
        op_points = raw;
    else
        op_points = {raw};
    end
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

    n = numel(t_arr);
    t_rep = zeros(n * n_periods, 1);
    d_rep = zeros(n * n_periods, 1);
    for c = 0:(n_periods - 1)
        idx = (c*n+1):((c+1)*n);
        t_rep(idx) = t_arr + c * T;
        d_rep(idx) = d_arr;
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
