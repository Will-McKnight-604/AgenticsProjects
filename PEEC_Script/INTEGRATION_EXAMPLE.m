% INTEGRATION_EXAMPLE.m
% Shows how to integrate build_mas_structure.m and call_pyopenmagnetics_api.py
% into the existing topology_wizard.m workflow.
%
% This file is for reference and documentation only.
% Do not run this directly - use topology_wizard.m instead.

% ===============================================================
% EXAMPLE 1: In topology_wizard.m - cb_get_recommendations() callback
% ===============================================================

function cb_get_recommendations_NEW(~, ~)
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
        script_dir = pwd();
        config_file = 'om_mas_config.json';
        result_file = 'om_mas_results.json';
        config_path = fullfile(script_dir, config_file);
        output_path = fullfile(script_dir, result_file);

        % ===== STEP 1: Build MAS structure using new function =====
        fprintf('[WIZARD] Building MAS structure for topology: %s\n', data.topology);
        mas = build_mas_structure(data, data.topology);

        % ===== STEP 2: Write MAS JSON =====
        fid = fopen(config_path, 'w', 'n', 'UTF-8');
        fprintf(fid, '%s', jsonencode(mas));
        fclose(fid);
        fprintf('[WIZARD] MAS JSON saved to: %s\n', config_file);

        % ===== STEP 3: Find Python =====
        python_cmd = 'python';
        venv_python = fullfile(script_dir, '.venv', 'Scripts', 'python.exe');
        if exist(venv_python, 'file')
            python_cmd = ['"' strrep(venv_python, '\', '/') '"'];
        end

        % ===== STEP 4: Call API script =====
        max_results = str2double(get(data.pop_n_results, 'String'){get(data.pop_n_results, 'Value')});
        core_mode = 'STANDARD_CORES';  % or 'ALL_CORES' for comprehensive search

        cmd = sprintf('%s call_pyopenmagnetics_api.py "%s" "%s" %d %s 2>&1', ...
            python_cmd, config_file, result_file, max_results, core_mode);

        fprintf('[WIZARD] Running: %s\n', cmd);
        [status, output] = system(cmd);
        fprintf('[WIZARD] Status: %d\n', status);

        % Check for errors
        is_module_error = ~isempty(strfind(output, 'ModuleNotFoundError')) || ...
                          ~isempty(strfind(output, 'ImportError'));

        % Fallback 1: Try py launcher
        if status ~= 0 && is_module_error && ispc
            fprintf('[WIZARD] Trying py launcher...\n');
            cmd_fb = sprintf('py call_pyopenmagnetics_api.py "%s" "%s" %d %s 2>&1', ...
                config_file, result_file, max_results, core_mode);
            [status_fb, output_fb] = system(cmd_fb);
            if status_fb == 0
                status = status_fb;
                output = output_fb;
            end
        end

        % Fallback 2: Try alternative pythons
        if status ~= 0 && is_module_error && ispc
            [~, py_paths_str] = system('where python');
            py_paths = strsplit(strtrim(py_paths_str), char(10));
            for i = 1:length(py_paths)
                p = strtrim(py_paths{i});
                if isempty(p) || ~isempty(strfind(lower(p), 'octave'))
                    continue;
                end
                p = strrep(p, '\', '/');
                cmd_alt = sprintf('"%s" call_pyopenmagnetics_api.py "%s" "%s" %d %s 2>&1', ...
                    p, config_file, result_file, max_results, core_mode);
                [status_alt, output_alt] = system(cmd_alt);
                if status_alt == 0
                    status = status_alt;
                    output = output_alt;
                    break;
                end
            end
        end

        if status ~= 0
            error('API script failed: %s', output);
        end

        % ===== STEP 5: Load results =====
        if ~exist(output_path, 'file')
            error('Results file not found: %s', result_file);
        end

        fid = fopen(output_path, 'r', 'n', 'UTF-8');
        raw = fread(fid, '*char')';
        fclose(fid);
        results = jsondecode(raw);

        if ~strcmp(results.status, 'OK')
            error('API returned error: %s', results.error);
        end

        fprintf('[WIZARD] API succeeded: %d results\n', results.count);

        % ===== STEP 6: Process results (integration with GUI) =====
        data.rec.results = results.data;  % Store raw results
        data.rec.selected_idx = 0;

        % Display recommendations in dialog
        data = display_recommendations(data, results);

    catch err
        errordlg(sprintf('Recommendation failed:\n%s', err.message), 'Error');
    end

    set(data.btn_get_recs, 'String', 'Get Recommendations', 'Enable', 'on');
    guidata(fig, data);
end


% ===============================================================
% EXAMPLE 2: Minimal integration - just get 5 recommendations
% ===============================================================

function recommendations = get_mas_recommendations(gui_data, topology_key)
% Simple wrapper: pass GUI data, get recommendations back
%
% Usage:
%   gui_data = build_gui_data_from_form(figure_handle);
%   recs = get_mas_recommendations(gui_data, 'two_switch_forward');

    % Build MAS
    mas = build_mas_structure(gui_data, topology_key);

    % Save to temp JSON
    temp_dir = tempdir();
    config_file = fullfile(temp_dir, 'mas_temp.json');
    result_file = fullfile(temp_dir, 'mas_results.json');

    fid = fopen(config_file, 'w');
    fprintf(fid, '%s', jsonencode(mas));
    fclose(fid);

    % Call API
    [status, output] = system(sprintf('python call_pyopenmagnetics_api.py "%s" "%s" 5', ...
        config_file, result_file));

    if status ~= 0
        error('API failed: %s', output);
    end

    % Load results
    fid = fopen(result_file, 'r');
    raw = fread(fid, '*char')';
    fclose(fid);
    results = jsondecode(raw);

    if ~strcmp(results.status, 'OK')
        error('Recommendations failed: %s', results.error);
    end

    % Return just the data array
    recommendations = results.data;

    % Cleanup
    delete(config_file);
    delete(result_file);
end


% ===============================================================
% EXAMPLE 3: Display recommendations in dialog
% ===============================================================

function display_recommendation_dialog(results)
% Display API results in user-friendly dialog

    if isempty(results) || ~isfield(results, 'count') || results.count == 0
        msgbox('No recommendations available', 'No Results');
        return;
    end

    % Build recommendation strings
    rec_strings = {};
    for i = 1:min(10, results.count)
        rec = results.data(i);
        core_name = 'Unknown';
        if isfield(rec, 'core_name')
            core_name = rec.core_name;
        end

        loss_str = '';
        if isfield(rec, 'losses_total')
            loss_str = sprintf(', Loss: %.2f W', rec.losses_total);
        end

        temp_str = '';
        if isfield(rec, 'temperature_winding')
            temp_str = sprintf(', Temp: %.1f C', rec.temperature_winding);
        end

        rec_strings{i} = sprintf('[%d] %s%s%s', i, core_name, loss_str, temp_str);
    end

    % Show selection dialog
    [sel, ok] = listdlg('ListString', rec_strings, ...
                        'SelectionMode', 'single', ...
                        'PromptString', 'Select a design recommendation:', ...
                        'ListSize', [400 200]);

    if ok && ~isempty(sel)
        selected = results.data(sel);
        msgbox(sprintf('Selected: %s', selected.core_name), 'Selection Confirmed');
        % Could store selection and proceed to winding designer
    end
end


% ===============================================================
% EXAMPLE 4: Batch recommendations for multiple topologies
% ===============================================================

function batch_recommendations(gui_data)
% Get recommendations for all 9 topologies and compare

    topologies = {
        'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', ...
        'flyback', 'push_pull', 'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'
    };

    results_all = struct();

    for i = 1:length(topologies)
        topo = topologies{i};
        fprintf('Getting recommendations for %s...\n', topo);

        try
            mas = build_mas_structure(gui_data, topo);
            % ... call API ...
            results = jsondecode(fileread('temp_results.json'));
            if strcmp(results.status, 'OK')
                results_all.(topo) = results;
                fprintf('  %d results\n', results.count);
            end
        catch err
            fprintf('  Error: %s\n', err.message);
        end
    end

    % Compare across topologies
    fprintf('\n===== Topology Comparison =====\n');
    for i = 1:length(topologies)
        topo = topologies{i};
        if isfield(results_all, topo)
            res = results_all.(topo);
            if res.count > 0
                best = res.data(1);
                loss = best.losses_total;
                fprintf('%25s: Loss=%.2f W, Core=%s\n', topo, loss, best.core_name);
            end
        end
    end
end


% ===============================================================
% HELPER: Convert GUI form to gui_data struct
% ===============================================================

function gui_data = extract_gui_data(fig_handle)
% Extract all form fields from topology_wizard figure into gui_data struct
%
% This would typically be called from topology_wizard's guidata storage

    data = guidata(fig_handle);

    gui_data = struct();

    % Extract converter specs
    gui_data.converter = struct();
    gui_data.converter.vin_min = str2double(get(data.edit_vin_min, 'String'));
    gui_data.converter.vin_max = str2double(get(data.edit_vin_max, 'String'));
    gui_data.converter.vin_nom = str2double(get(data.edit_vin_nom, 'String'));
    gui_data.converter.vout = str2double(get(data.edit_vout, 'String'));
    gui_data.converter.iout = str2double(get(data.edit_iout, 'String'));
    gui_data.converter.fsw_khz = str2double(get(data.edit_fsw, 'String'));
    gui_data.converter.vd = str2double(get(data.edit_vd, 'String'));
    gui_data.converter.efficiency = str2double(get(data.edit_efficiency, 'String'));
    gui_data.converter.max_ripple = str2double(get(data.edit_ripple, 'String'));
    gui_data.converter.max_switch_current = str2double(get(data.edit_max_isw, 'String'));

    % Extract thermal
    gui_data.thermal = struct();
    gui_data.thermal.ambient_temp = str2double(get(data.edit_ambient, 'String'));

    % Extract insulation
    gui_data.insulation = struct();
    ins_class_idx = get(data.pop_insulation, 'Value');
    ins_class_options = get(data.pop_insulation, 'String');
    gui_data.insulation.class = ins_class_options{ins_class_idx};

    % (similar for other insulation fields...)

    % Extract topology
    topo_idx = get(data.pop_topology, 'Value');
    topo_options = get(data.pop_topology, 'String');
    gui_data.topology = topology_display_to_key(topo_options{topo_idx});

end


function topology_key = topology_display_to_key(display_name)
% Convert display name (from GUI dropdown) to topology key (snake_case)

    mapping = containers.Map();
    mapping('Two-Switch Forward') = 'two_switch_forward';
    mapping('Single-Switch Forward') = 'single_switch_forward';
    mapping('Active Clamp Forward') = 'active_clamp_forward';
    mapping('Flyback') = 'flyback';
    mapping('Push-Pull') = 'push_pull';
    mapping('Buck') = 'buck';
    mapping('Boost') = 'boost';
    mapping('Isolated Buck') = 'isolated_buck';
    mapping('Isolated Buck-Boost') = 'isolated_buck_boost';

    if isKey(mapping, display_name)
        topology_key = mapping(display_name);
    else
        error('Unknown topology display name: %s', display_name);
    end
end
