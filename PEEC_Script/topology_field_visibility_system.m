% ===============================================================
% TOPOLOGY FIELD VISIBILITY SYSTEM - topology_wizard.m
% ===============================================================
%
% This module provides dynamic field visibility management for topology_wizard.m
% Allows GUI fields to show/hide based on selected topology and metadata system
%
% Functions to integrate into topology_wizard.m:
%   - get_topology_metadata()     - Returns metadata for a given topology
%   - get_visible_fields_for_topology()  - Returns required + optional field lists
%   - get_topology_output_type()  - Returns 'single' or 'multi' for output spec table
%   - update_field_visibility()   - Main visibility update function
%   - rebuild_output_spec_table() - Rebuild output rows based on topology
%   - collect_gui_field_values()  - Gather user-entered values from visible fields
%
% ===============================================================

% ===============================================================
% TOPOLOGY METADATA DEFINITIONS
% ===============================================================

function metadata = get_topology_metadata(topology_key)
    % Returns a struct containing metadata for the given topology
    %
    % Fields:
    %   key:              Internal identifier (e.g., 'two_switch_forward')
    %   display_name:     User-friendly display name
    %   category:         'forward' | 'flyback' | 'push_pull' | 'buck' | 'boost' | 'isolated_buck' | 'isolated_buck_boost'
    %   is_isolated:      true if transformer isolated
    %   n_outputs_min:    Minimum number of output windings
    %   n_outputs_max:    Maximum number of output windings
    %   supports_auto:    true if 'auto' design mode makes sense
    %   supports_advanced: true if 'advanced' design mode available
    %   required_fields:  Cell array of field names required for this topology
    %   optional_fields:  Cell array of field names optionally shown
    %

    % Define all topology metadata
    all_metadata = struct();

    % 1. Two-Switch Forward Converter
    all_metadata.two_switch_forward = struct( ...
        'key', 'two_switch_forward', ...
        'display_name', 'Two-Switch Forward Converter', ...
        'category', 'forward', ...
        'is_isolated', true, ...
        'n_outputs_min', 1, ...
        'n_outputs_max', 4, ...
        'supports_auto', true, ...
        'supports_advanced', true, ...
        'required_fields', {{'inputVoltage_min', 'inputVoltage_max', 'diodeVoltageDrop', ...
                             'switchingFrequency', 'outputVoltage', 'outputCurrent'}}, ...
        'optional_fields', {{'inputVoltage_nom', 'efficiency', 'currentRippleRatio', ...
                             'maxSwitchCurrent'}} ...
    );

    % 2. Single-Switch Forward Converter
    all_metadata.single_switch_forward = struct( ...
        'key', 'single_switch_forward', ...
        'display_name', 'Single-Switch Forward Converter', ...
        'category', 'forward', ...
        'is_isolated', true, ...
        'n_outputs_min', 1, ...
        'n_outputs_max', 4, ...
        'supports_auto', true, ...
        'supports_advanced', true, ...
        'required_fields', {{'inputVoltage_min', 'inputVoltage_max', 'diodeVoltageDrop', ...
                             'switchingFrequency', 'outputVoltage', 'outputCurrent'}}, ...
        'optional_fields', {{'inputVoltage_nom', 'efficiency', 'currentRippleRatio', ...
                             'maxSwitchCurrent'}} ...
    );

    % 3. Active Clamp Forward Converter
    all_metadata.active_clamp_forward = struct( ...
        'key', 'active_clamp_forward', ...
        'display_name', 'Active Clamp Forward Converter', ...
        'category', 'forward', ...
        'is_isolated', true, ...
        'n_outputs_min', 1, ...
        'n_outputs_max', 4, ...
        'supports_auto', true, ...
        'supports_advanced', true, ...
        'required_fields', {{'inputVoltage_min', 'inputVoltage_max', 'diodeVoltageDrop', ...
                             'switchingFrequency', 'outputVoltage', 'outputCurrent'}}, ...
        'optional_fields', {{'inputVoltage_nom', 'efficiency', 'currentRippleRatio', ...
                             'maxSwitchCurrent'}} ...
    );

    % 4. Flyback Converter
    all_metadata.flyback = struct( ...
        'key', 'flyback', ...
        'display_name', 'Flyback Converter', ...
        'category', 'flyback', ...
        'is_isolated', true, ...
        'n_outputs_min', 1, ...
        'n_outputs_max', 4, ...
        'supports_auto', true, ...
        'supports_advanced', true, ...
        'required_fields', {{'inputVoltage_min', 'inputVoltage_max', 'diodeVoltageDrop', ...
                             'switchingFrequency', 'outputVoltage', 'outputCurrent', 'efficiency'}}, ...
        'optional_fields', {{'inputVoltage_nom', 'currentRippleRatio', 'maxSwitchCurrent', ...
                             'maxDutyCycle'}} ...
    );

    % 5. Push-Pull Converter
    all_metadata.push_pull = struct( ...
        'key', 'push_pull', ...
        'display_name', 'Push-Pull Converter', ...
        'category', 'push_pull', ...
        'is_isolated', true, ...
        'n_outputs_min', 1, ...
        'n_outputs_max', 4, ...
        'supports_auto', true, ...
        'supports_advanced', true, ...
        'required_fields', {{'inputVoltage_min', 'inputVoltage_max', 'diodeVoltageDrop', ...
                             'switchingFrequency', 'outputVoltage', 'outputCurrent'}}, ...
        'optional_fields', {{'inputVoltage_nom', 'efficiency', 'currentRippleRatio'}} ...
    );

    % 6. Buck Converter (non-isolated, step-down)
    all_metadata.buck = struct( ...
        'key', 'buck', ...
        'display_name', 'Buck Converter', ...
        'category', 'buck', ...
        'is_isolated', false, ...
        'n_outputs_min', 1, ...
        'n_outputs_max', 1, ...
        'supports_auto', true, ...
        'supports_advanced', true, ...
        'required_fields', {{'inputVoltage_min', 'inputVoltage_max', 'switchingFrequency', ...
                             'outputVoltage', 'outputCurrent'}}, ...
        'optional_fields', {{'inputVoltage_nom', 'efficiency', 'currentRippleRatio'}} ...
    );

    % 7. Boost Converter (non-isolated, step-up)
    all_metadata.boost = struct( ...
        'key', 'boost', ...
        'display_name', 'Boost Converter', ...
        'category', 'boost', ...
        'is_isolated', false, ...
        'n_outputs_min', 1, ...
        'n_outputs_max', 1, ...
        'supports_auto', true, ...
        'supports_advanced', true, ...
        'required_fields', {{'inputVoltage_min', 'inputVoltage_max', 'switchingFrequency', ...
                             'outputVoltage', 'outputCurrent'}}, ...
        'optional_fields', {{'inputVoltage_nom', 'efficiency', 'currentRippleRatio'}} ...
    );

    % 8. Isolated Buck Converter
    all_metadata.isolated_buck = struct( ...
        'key', 'isolated_buck', ...
        'display_name', 'Isolated Buck Converter', ...
        'category', 'isolated_buck', ...
        'is_isolated', true, ...
        'n_outputs_min', 1, ...
        'n_outputs_max', 4, ...
        'supports_auto', true, ...
        'supports_advanced', true, ...
        'required_fields', {{'inputVoltage_min', 'inputVoltage_max', 'diodeVoltageDrop', ...
                             'switchingFrequency', 'outputVoltage', 'outputCurrent'}}, ...
        'optional_fields', {{'inputVoltage_nom', 'efficiency', 'currentRippleRatio'}} ...
    );

    % 9. Isolated Buck-Boost Converter
    all_metadata.isolated_buck_boost = struct( ...
        'key', 'isolated_buck_boost', ...
        'display_name', 'Isolated Buck-Boost Converter', ...
        'category', 'isolated_buck_boost', ...
        'is_isolated', true, ...
        'n_outputs_min', 1, ...
        'n_outputs_max', 4, ...
        'supports_auto', true, ...
        'supports_advanced', true, ...
        'required_fields', {{'inputVoltage_min', 'inputVoltage_max', 'diodeVoltageDrop', ...
                             'switchingFrequency', 'outputVoltage', 'outputCurrent'}}, ...
        'optional_fields', {{'inputVoltage_nom', 'efficiency', 'currentRippleRatio'}} ...
    );

    % Lookup requested topology
    if isfield(all_metadata, topology_key)
        metadata = all_metadata.(topology_key);
    else
        % Default to two_switch_forward if unknown
        metadata = all_metadata.two_switch_forward;
        warning('Unknown topology: %s, using default (two_switch_forward)', topology_key);
    end
end


% ===============================================================
% FIELD VISIBILITY LOGIC
% ===============================================================

function [required_fields, optional_fields] = get_visible_fields_for_topology(topology_key)
    % Returns lists of field names that should be visible for a given topology
    %
    % Returns:
    %   required_fields:  Cell array of required field names
    %   optional_fields:  Cell array of optional field names
    %

    metadata = get_topology_metadata(topology_key);
    required_fields = metadata.required_fields{1};
    optional_fields = metadata.optional_fields{1};
end


function output_type = get_topology_output_type(topology_key)
    % Returns whether topology supports single or multi-output configurations
    %
    % Returns:
    %   'single'  - Only one output (Buck, Boost)
    %   'multi'   - Multiple outputs possible (Isolated converters)
    %

    metadata = get_topology_metadata(topology_key);
    if metadata.n_outputs_max > 1
        output_type = 'multi';
    else
        output_type = 'single';
    end
end


% ===============================================================
% MAIN VISIBILITY UPDATE FUNCTION
% ===============================================================

function update_field_visibility(fig, topology_key)
    % Updates GUI field visibility based on topology selection
    %
    % Handles:
    %   - Show/hide all converter specification fields
    %   - Update field labels to show required vs optional
    %   - Show/hide N outputs spinner (for multi-output topologies)
    %   - Update panel titles with topology name
    %   - Update requirements display title
    %

    data = guidata(fig);
    metadata = get_topology_metadata(topology_key);
    [req_fields, opt_fields] = get_visible_fields_for_topology(topology_key);

    % ===== FIELD VISIBILITY MAPPING =====
    % Map field names to GUI control handles
    field_handles = struct();

    % Map internal field names to GUI handles
    field_map = {
        'inputVoltage_min',        'edit_vin_min';
        'inputVoltage_max',        'edit_vin_max';
        'inputVoltage_nom',        'edit_vin_nom';
        'outputVoltage',           'edit_vout';
        'outputCurrent',           'edit_iout';
        'switchingFrequency',      'edit_fsw';
        'diodeVoltageDrop',        'edit_vd';
        'efficiency',              'edit_efficiency';
        'currentRippleRatio',      'edit_ripple';
        'maxSwitchCurrent',        'edit_max_isw';
        'maxDutyCycle',            'edit_max_duty';
        'maxDrainSourceVoltage',   'edit_max_vds';
    };

    % Show all required fields
    for i = 1:numel(req_fields)
        field_name = req_fields{i};
        handle_idx = find(strcmp(field_map(:,1), field_name), 1);
        if ~isempty(handle_idx)
            handle_field = field_map{handle_idx, 2};
            if isfield(data, handle_field) && ~isempty(data.(handle_field))
                set(data.(handle_field), 'Visible', 'on');
                % Update label to indicate "required" (can be done by label color)
            end
        end
    end

    % Show optional fields only if show_optional flag is set
    for i = 1:numel(opt_fields)
        field_name = opt_fields{i};
        handle_idx = find(strcmp(field_map(:,1), field_name), 1);
        if ~isempty(handle_idx)
            handle_field = field_map{handle_idx, 2};
            if isfield(data, handle_field) && ~isempty(data.(handle_field))
                if isfield(data, 'show_optional') && data.show_optional
                    set(data.(handle_field), 'Visible', 'on');
                else
                    % Optional fields controlled by show_optional toggle
                    % (already hidden by optional_panel visibility)
                end
            end
        end
    end

    % Hide fields NOT in required or optional list
    all_valid_fields = [req_fields; opt_fields];
    for i = 1:size(field_map, 1)
        field_name = field_map{i, 1};
        if ~any(strcmp(all_valid_fields, field_name))
            handle_field = field_map{i, 2};
            if isfield(data, handle_field) && ~isempty(data.(handle_field))
                set(data.(handle_field), 'Visible', 'off');
            end
        end
    end

    % ===== UPDATE N OUTPUTS SPINNER =====
    % Only show for multi-output topologies
    output_type = get_topology_output_type(topology_key);
    if strcmp(output_type, 'multi')
        if isfield(data, 'edit_n_outputs') && ~isempty(data.edit_n_outputs)
            set(data.edit_n_outputs, 'Visible', 'on');
        end
        if isfield(data, 'btn_n_outputs_plus') && ~isempty(data.btn_n_outputs_plus)
            set(data.btn_n_outputs_plus, 'Visible', 'on');
        end
        if isfield(data, 'btn_n_outputs_minus') && ~isempty(data.btn_n_outputs_minus)
            set(data.btn_n_outputs_minus, 'Visible', 'on');
        end
    else
        if isfield(data, 'edit_n_outputs') && ~isempty(data.edit_n_outputs)
            set(data.edit_n_outputs, 'Visible', 'off');
        end
        if isfield(data, 'btn_n_outputs_plus') && ~isempty(data.btn_n_outputs_plus)
            set(data.btn_n_outputs_plus, 'Visible', 'off');
        end
        if isfield(data, 'btn_n_outputs_minus') && ~isempty(data.btn_n_outputs_minus)
            set(data.btn_n_outputs_minus, 'Visible', 'off');
        end
    end

    % ===== UPDATE PANEL TITLES =====
    % Update spec panel title with topology name
    spec_panel = findobj(fig, 'Type', 'uipanel', '-regexp', 'Title', '.*Converter Specifications');
    if ~isempty(spec_panel)
        spec_title = sprintf('%s - Converter Specifications', metadata.display_name);
        set(spec_panel(1), 'Title', spec_title);
    end

    % Update requirements panel title
    req_panel = findobj(fig, 'Type', 'uipanel', '-regexp', 'Title', '.*Design Requirements');
    if ~isempty(req_panel)
        req_title = sprintf('%s - Design Requirements', metadata.display_name);
        set(req_panel(1), 'Title', req_title);
    end

    guidata(fig, data);
end


% ===============================================================
% OUTPUT SPECIFICATION TABLE MANAGEMENT
% ===============================================================

function rebuild_output_spec_table(fig, topology_key)
    % Rebuilds the output specification table based on topology and N outputs
    %
    % For single-output topologies: Single row with Voltage/Current
    % For multi-output topologies: N rows based on n_outputs spinner value
    %

    data = guidata(fig);
    output_type = get_topology_output_type(topology_key);

    % Determine number of output rows to show
    if strcmp(output_type, 'single')
        n_outputs_to_show = 1;
    else
        n_outputs_to_show = data.n_outputs;
    end

    % For now, this is a placeholder for future table management
    % The actual output specification rows are currently hardcoded in build_wizard_panel
    % This function can be extended to dynamically add/remove output rows

    % TODO: Implement dynamic row addition/removal in output specification section
    % This would involve:
    % 1. Creating/destroying uicontrol edit boxes for Output 1, 2, 3, 4 voltage/current
    % 2. Repositioning them dynamically based on n_outputs_to_show
    % 3. Storing handles in data.output_rows structure

    guidata(fig, data);
end


% ===============================================================
% VALUE COLLECTION FROM GUI
% ===============================================================

function gui_values = collect_gui_field_values(fig, topology_key)
    % Collects user-entered values from all visible GUI fields
    %
    % Returns:
    %   gui_values: struct with field_name -> value mappings
    %

    data = guidata(fig);
    gui_values = struct();

    % Collect standard converter specs
    if isfield(data, 'edit_vin_min')
        gui_values.inputVoltage_min = str2double(get(data.edit_vin_min, 'String'));
    end
    if isfield(data, 'edit_vin_max')
        gui_values.inputVoltage_max = str2double(get(data.edit_vin_max, 'String'));
    end
    if isfield(data, 'edit_vin_nom')
        val_str = get(data.edit_vin_nom, 'String');
        if ~isempty(val_str)
            gui_values.inputVoltage_nom = str2double(val_str);
        end
    end
    if isfield(data, 'edit_vout')
        gui_values.outputVoltage = str2double(get(data.edit_vout, 'String'));
    end
    if isfield(data, 'edit_iout')
        gui_values.outputCurrent = str2double(get(data.edit_iout, 'String'));
    end
    if isfield(data, 'edit_fsw')
        gui_values.switchingFrequency = str2double(get(data.edit_fsw, 'String'));
    end
    if isfield(data, 'edit_vd')
        gui_values.diodeVoltageDrop = str2double(get(data.edit_vd, 'String'));
    end
    if isfield(data, 'edit_efficiency')
        val_str = get(data.edit_efficiency, 'String');
        if ~isempty(val_str)
            gui_values.efficiency = str2double(val_str);
        end
    end
    if isfield(data, 'edit_ripple')
        val_str = get(data.edit_ripple, 'String');
        if ~isempty(val_str)
            gui_values.currentRippleRatio = str2double(val_str);
        end
    end
    if isfield(data, 'edit_max_isw')
        val_str = get(data.edit_max_isw, 'String');
        if ~isempty(val_str)
            gui_values.maxSwitchCurrent = str2double(val_str);
        end
    end
end


% ===============================================================
% TOPOLOGY CATEGORIZATION HELPERS (for internal logic)
% ===============================================================

function is_isolated = topology_is_isolated(topology_key)
    % Quick check if topology requires transformer/isolated
    metadata = get_topology_metadata(topology_key);
    is_isolated = metadata.is_isolated;
end


function is_forward = topology_is_forward(topology_key)
    % Check if topology is a forward converter variant
    metadata = get_topology_metadata(topology_key);
    is_forward = any(strcmp(metadata.category, {'forward'}));
end


function is_flyback = topology_is_flyback(topology_key)
    % Check if topology is flyback
    metadata = get_topology_metadata(topology_key);
    is_flyback = strcmp(metadata.category, 'flyback');
end


function is_buck_boost = topology_is_buck_boost(topology_key)
    % Check if topology is buck, boost, or similar inductor-based
    metadata = get_topology_metadata(topology_key);
    is_buck_boost = any(strcmp(metadata.category, {'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'}));
end


% ===============================================================
% END OF TOPOLOGY FIELD VISIBILITY SYSTEM
% ===============================================================
