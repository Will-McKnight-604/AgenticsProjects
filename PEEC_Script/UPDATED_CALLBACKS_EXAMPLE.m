% ===============================================================
% UPDATED CALLBACKS FOR topology_wizard.m
% ===============================================================
%
% This file shows the exact callback functions and code snippets
% needed to integrate the topology field visibility system into
% topology_wizard.m
%
% Copy and paste these into the corresponding sections of topology_wizard.m
%

% ===============================================================
% 1. UPDATED: cb_topology_changed() callback
% ===============================================================
% Location: Replace lines 1197-1233 in topology_wizard.m
%
% This callback is triggered when user selects a different topology
% from the dropdown menu.

function cb_topology_changed(src, ~)
    fig = gcbf();
    data = guidata(fig);

    % Map selection index to topology key
    topology_keys = {'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', ...
                     'flyback', 'push_pull', 'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'};

    idx = get(src, 'Value');
    if idx >= 1 && idx <= numel(topology_keys)
        data.topology = topology_keys{idx};

        % Get metadata to get proper display name
        metadata = get_topology_metadata(data.topology);
        data.topology_display = metadata.display_name;
    end

    % Save updated data BEFORE calling update functions
    % This is critical - update functions will retrieve data with guidata()
    guidata(fig, data);

    % Update field visibility based on topology selection
    % This shows/hides fields and N outputs spinner
    update_field_visibility(fig, data.topology);

    % Update computed design requirements display with topology-specific info
    if isfield(data, 'requirements') && isstruct(data.requirements)
        update_topology_requirements_display(data, data.requirements);
    end

end


% ===============================================================
% 2. UPDATED: cb_n_outputs() callback
% ===============================================================
% Location: Replace lines 1255-1265 in topology_wizard.m
%
% Called when user manually edits the N outputs spinner text field

function cb_n_outputs(src, ~)
    fig = gcbf();
    data = guidata(fig);

    val = str2double(get(src, 'String'));
    if ~isnan(val) && val >= 1 && val <= 4
        data.n_outputs = round(val);
    else
        % Revert to previous valid value if user entered invalid input
        set(src, 'String', num2str(data.n_outputs));
    end

    % Rebuild output specification table rows if topology has multiple outputs
    if ~strcmp(get_topology_output_type(data.topology), 'single')
        rebuild_output_spec_table(fig, data.topology);
    end

    guidata(fig, data);
end


% ===============================================================
% 3. UPDATED: cb_n_outputs_plus() callback
% ===============================================================
% Location: Replace lines 1268-1276 in topology_wizard.m
%
% Called when user clicks the + button next to N outputs

function cb_n_outputs_plus(~, ~)
    fig = gcbf();
    data = guidata(fig);

    if data.n_outputs < 4
        data.n_outputs = data.n_outputs + 1;
        set(data.edit_n_outputs, 'String', num2str(data.n_outputs));

        % Rebuild output specification table rows
        if ~strcmp(get_topology_output_type(data.topology), 'single')
            rebuild_output_spec_table(fig, data.topology);
        end
    end

    guidata(fig, data);
end


% ===============================================================
% 4. UPDATED: cb_n_outputs_minus() callback
% ===============================================================
% Location: Replace lines 1279-1287 in topology_wizard.m
%
% Called when user clicks the - button next to N outputs

function cb_n_outputs_minus(~, ~)
    fig = gcbf();
    data = guidata(fig);

    if data.n_outputs > 1
        data.n_outputs = data.n_outputs - 1;
        set(data.edit_n_outputs, 'String', num2str(data.n_outputs));

        % Rebuild output specification table rows
        if ~strcmp(get_topology_output_type(data.topology), 'single')
            rebuild_output_spec_table(fig, data.topology);
        end
    end

    guidata(fig, data);
end


% ===============================================================
% 5. NEW CODE IN: build_gui() function
% ===============================================================
% Location: Add to the end of build_gui() function (after line 207)
%
% This initializes the visibility system on GUI startup

% Add to END of build_gui(), right before final guidata() call:

    % Initialize UI handle structure for visibility management
    if ~isfield(data, 'ui_handles')
        data.ui_handles = struct();
        data.ui_handles.fields = struct();
    end

    % Store references to all field controls for visibility management
    if isfield(data, 'edit_vin_min')
        data.ui_handles.fields.edit_vin_min = data.edit_vin_min;
    end
    if isfield(data, 'edit_vin_max')
        data.ui_handles.fields.edit_vin_max = data.edit_vin_max;
    end
    if isfield(data, 'edit_vin_nom')
        data.ui_handles.fields.edit_vin_nom = data.edit_vin_nom;
    end
    if isfield(data, 'edit_vout')
        data.ui_handles.fields.edit_vout = data.edit_vout;
    end
    if isfield(data, 'edit_iout')
        data.ui_handles.fields.edit_iout = data.edit_iout;
    end
    if isfield(data, 'edit_fsw')
        data.ui_handles.fields.edit_fsw = data.edit_fsw;
    end
    if isfield(data, 'edit_vd')
        data.ui_handles.fields.edit_vd = data.edit_vd;
    end
    if isfield(data, 'edit_efficiency')
        data.ui_handles.fields.edit_efficiency = data.edit_efficiency;
    end
    if isfield(data, 'edit_ripple')
        data.ui_handles.fields.edit_ripple = data.edit_ripple;
    end
    if isfield(data, 'edit_max_isw')
        data.ui_handles.fields.edit_max_isw = data.edit_max_isw;
    end

    % Initialize field visibility based on default topology (two_switch_forward)
    update_field_visibility(data.fig, data.topology);

    % Store the updated data structure
    guidata(data.fig, data);

% End of additions


% ===============================================================
% 6. UPDATED: cb_compute_topology() function
% ===============================================================
% Location: Update lines 1290-1320 (the part that builds config JSON)
%
% This shows how to use collect_gui_field_values() to build the config

function cb_compute_topology(~, ~)
    fig = gcbf();
    data = guidata(fig);

    % Validate required fields
    c = data.converter;
    if c.vin_min <= 0 || c.vin_max <= 0 || c.vout <= 0 || c.iout <= 0 || c.fsw_khz <= 0
        errordlg('Please fill in all required converter specifications (Vin, Vout, Iout, Fsw)', ...
                 'Missing Required Fields');
        return;
    end

    if c.vin_min >= c.vin_max
        errordlg('Input voltage max must be greater than min', 'Invalid Input Range');
        return;
    end

    % Collect GUI field values for the selected topology
    % This ensures we only send values for fields that are visible/relevant
    gui_values = collect_gui_field_values(fig, data.topology);

    % Request topology computation from Python
    data = request_topology_compute(data);

    guidata(fig, data);

end


% ===============================================================
% 7. HELPER: Modified collect_gui_field_values() usage
% ===============================================================
% Location: Show how to use the collected values
%
% In request_topology_compute() when building the JSON config:

% When building om_topology_config.json, use:
    gui_values = collect_gui_field_values(fig, data.topology);

    % Build converter struct from collected values
    config.converter = struct();

    % Always include these if available
    if isfield(gui_values, 'inputVoltage_min')
        config.converter.inputVoltage_min = gui_values.inputVoltage_min;
    else
        config.converter.inputVoltage_min = data.converter.vin_min;
    end

    if isfield(gui_values, 'inputVoltage_max')
        config.converter.inputVoltage_max = gui_values.inputVoltage_max;
    else
        config.converter.inputVoltage_max = data.converter.vin_max;
    end

    % Include optional fields if they were entered
    if isfield(gui_values, 'inputVoltage_nom') && ~isnan(gui_values.inputVoltage_nom)
        config.converter.inputVoltage_nom = gui_values.inputVoltage_nom;
    end

    % ... etc for other fields


% ===============================================================
% 8. OPTIONAL: Enhanced cb_toggle_optional() callback
% ===============================================================
% Location: Update lines 932-944 in topology_wizard.m
%
% Make sure field visibility is refreshed when optional toggle changes

function cb_toggle_optional(~, ~)
    fig = gcbf();
    data = guidata(fig);

    % Toggle the optional fields visibility
    if isfield(data, 'optional_panel')
        current_vis = get(data.optional_panel, 'Visible');
        if strcmp(current_vis, 'on')
            set(data.optional_panel, 'Visible', 'off');
            data.show_optional = false;
            set(data.btn_toggle_optional, 'String', 'Show Optional Parameters');
        else
            set(data.optional_panel, 'Visible', 'on');
            data.show_optional = true;
            set(data.btn_toggle_optional, 'String', 'Hide Optional Parameters');
        end
    end

    % Refresh field visibility to ensure optional fields are shown correctly for topology
    update_field_visibility(fig, data.topology);

    guidata(fig, data);
end


% ===============================================================
% 9. REFERENCE: How to use metadata in custom code
% ===============================================================

% Get all info about a topology:
metadata = get_topology_metadata('flyback');
fprintf('Topology: %s\n', metadata.display_name);
fprintf('Is isolated: %d\n', metadata.is_isolated);
fprintf('Min outputs: %d, Max outputs: %d\n', ...
        metadata.n_outputs_min, metadata.n_outputs_max);
fprintf('Required fields: %s\n', strjoin(metadata.required_fields{1}, ', '));

% Check if topology is isolated:
if topology_is_isolated('buck')
    % Buck is NOT isolated - this block won't execute
end

% Get what type of output table to show:
type = get_topology_output_type('push_pull');  % Returns 'multi'
type = get_topology_output_type('buck');        % Returns 'single'

% Get field lists for a topology:
[req, opt] = get_visible_fields_for_topology('two_switch_forward');
% req = {'inputVoltage_min', 'inputVoltage_max', ...}
% opt = {'inputVoltage_nom', 'efficiency', ...}


% ===============================================================
% END OF CALLBACK EXAMPLES
% ===============================================================
