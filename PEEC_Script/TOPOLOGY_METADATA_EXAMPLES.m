% TOPOLOGY_METADATA_EXAMPLES - Code examples for using the metadata system
%
% This file contains real-world code examples showing how to use the
% topology metadata functions in your MATLAB application.
%
% Copy and adapt these examples for your use case.

% ==============================================================================
% EXAMPLE 1: Print information about all topologies
% ==============================================================================
function example_list_all_topologies()
    fprintf('\n=== EXAMPLE 1: List All Topologies ===\n\n');

    % Get topology definitions
    topos = get_all_topology_keys();

    fprintf('Available topologies:\n');
    for i = 1:length(topos)
        topo_key = topos{i};
        topo_meta = get_topology_metadata(topo_key);
        output_type = get_topology_output_type(topo_key);

        fprintf('  [%d] %s\n', i, topo_meta.display_name);
        fprintf('      Key: %s\n', topo_key);
        fprintf('      Output: %s\n', output_type);
        fprintf('      MAS: %s\n', topo_meta.mas_filename);
        fprintf('\n');
    end
end

% ==============================================================================
% EXAMPLE 2: Display required and optional fields for a topology
% ==============================================================================
function example_show_fields_for_topology(topology_key)
    fprintf('\n=== EXAMPLE 2: Show Fields for Topology ===\n\n');

    if nargin < 1
        topology_key = 'two_switch_forward';
    end

    topo = get_topology_metadata(topology_key);
    [req, opt] = get_visible_fields_for_topology(topology_key);

    fprintf('Topology: %s\n\n', topo.display_name);

    fprintf('REQUIRED FIELDS (%d):\n', length(req));
    fprintf('-------------------\n');
    for i = 1:length(req)
        field_name = req{i};
        meta = get_field_metadata(field_name);
        fprintf('  %2d. %s\n', i, meta.label);
        fprintf('      Field:   %s\n', field_name);
        fprintf('      Unit:    %s\n', meta.unit);
        fprintf('      Range:   [%g, %g]\n', meta.min, meta.max);
        fprintf('      Default: %g\n', meta.default);
        fprintf('      Tooltip: %s\n', meta.tooltip);
        fprintf('\n');
    end

    fprintf('\nOPTIONAL FIELDS (%d):\n', length(opt));
    fprintf('-------------------\n');
    for i = 1:length(opt)
        field_name = opt{i};
        meta = get_field_metadata(field_name);
        fprintf('  %2d. %s\n', i, meta.label);
        fprintf('      Field:   %s\n', field_name);
        fprintf('      Unit:    %s\n', meta.unit);
        fprintf('      Range:   [%g, %g]\n', meta.min, meta.max);
        if isempty(meta.default)
            fprintf('      Default: [] (empty)\n');
        else
            fprintf('      Default: %g\n', meta.default);
        end
        fprintf('\n');
    end
end

% ==============================================================================
% EXAMPLE 3: Check if a field is required
% ==============================================================================
function example_check_field_requirement()
    fprintf('\n=== EXAMPLE 3: Check Field Requirements ===\n\n');

    test_cases = {
        'two_switch_forward', 'diodeVoltageDrop';
        'two_switch_forward', 'efficiency';
        'flyback', 'efficiency';
        'flyback', 'inputVoltage_nominal';
        'buck', 'currentRippleRatio';
        'buck', 'efficiency';
    };

    for i = 1:size(test_cases, 1)
        topology = test_cases{i, 1};
        field = test_cases{i, 2};
        required = is_field_required(topology, field);

        topo = get_topology_metadata(topology);
        field_meta = get_field_metadata(field);

        status = 'OPTIONAL';
        if required
            status = 'REQUIRED';
        end

        fprintf('%s + %s = %s\n', ...
            topo.display_name, field_meta.label, status);
    end
end

% ==============================================================================
% EXAMPLE 4: Build a data structure from user input
% ==============================================================================
function example_build_design_data()
    fprintf('\n=== EXAMPLE 4: Build Design Data from User Input ===\n\n');

    topology_key = 'two_switch_forward';
    topo = get_topology_metadata(topology_key);
    [required, optional] = get_visible_fields_for_topology(topology_key);

    % Simulate user input
    user_input = struct();
    user_input.inputVoltage_minimum = 100;
    user_input.inputVoltage_maximum = 190;
    user_input.inputVoltage_nominal = 150;  % Optional
    user_input.outputVoltages_0 = 5;
    user_input.outputCurrents_0 = 10;
    user_input.switchingFrequency = 200;
    user_input.diodeVoltageDrop = 0.7;
    user_input.currentRippleRatio = 30;
    user_input.efficiency = 90;  % Optional

    % Validate required fields
    fprintf('Validating required fields...\n');
    all_valid = true;
    for i = 1:length(required)
        field = required{i};
        if ~isfield(user_input, field)
            fprintf('  ERROR: Missing required field: %s\n', field);
            all_valid = false;
        else
            fprintf('  OK: %s = %g\n', field, user_input.(field));
        end
    end

    if all_valid
        fprintf('\nAll required fields present!\n');

        % Check optional fields
        fprintf('\nOptional fields provided:\n');
        for i = 1:length(optional)
            field = optional{i};
            if isfield(user_input, field)
                fprintf('  %s = %g\n', field, user_input.(field));
            end
        end
    end
end

% ==============================================================================
% EXAMPLE 5: Detect topology output capability
% ==============================================================================
function example_detect_output_capability()
    fprintf('\n=== EXAMPLE 5: Detect Output Capability ===\n\n');

    all_topos = get_all_topology_keys();

    fprintf('Single-Output Topologies:\n');
    for i = 1:length(all_topos)
        topo_key = all_topos{i};
        output_type = get_topology_output_type(topo_key);
        if strcmp(output_type, 'single')
            topo = get_topology_metadata(topo_key);
            fprintf('  - %s\n', topo.display_name);
        end
    end

    fprintf('\nMulti-Output Topologies:\n');
    for i = 1:length(all_topos)
        topo_key = all_topos{i};
        output_type = get_topology_output_type(topo_key);
        if strcmp(output_type, 'multi')
            topo = get_topology_metadata(topo_key);
            fprintf('  - %s\n', topo.display_name);
        end
    end
end

% ==============================================================================
% EXAMPLE 6: Create MAS structure from metadata
% ==============================================================================
function mas = example_create_mas_from_metadata()
    fprintf('\n=== EXAMPLE 6: Create MAS Structure ===\n\n');

    topology_key = 'two_switch_forward';

    % User input
    input_data = struct();
    input_data.inputVoltage_minimum = 100;
    input_data.inputVoltage_maximum = 190;
    input_data.outputVoltages_0 = 5;
    input_data.outputCurrents_0 = 10;
    input_data.switchingFrequency = 200;
    input_data.diodeVoltageDrop = 0.7;
    input_data.currentRippleRatio = 30;

    % Initialize MAS structure
    mas = struct();
    mas.inputs = struct();
    mas.inputs.designRequirements = struct();
    mas.inputs.operatingPoints = struct();

    % Get all fields for this topology
    [required, optional] = get_visible_fields_for_topology(topology_key);
    all_fields = [required, optional];

    % Map each field to MAS structure
    for i = 1:length(all_fields)
        field_name = all_fields{i};
        meta = get_field_metadata(field_name);

        % Check if user provided this field
        if isfield(input_data, field_name)
            value = input_data.(field_name);

            % Map to MAS path
            mas_path = meta.mas_path;
            fprintf('Mapping %s = %g to MAS path: %s\n', field_name, value, mas_path);

            % In real code, you would use a setByPath() function here
            % setByPath(mas, mas_path, value);
        end
    end

    fprintf('\nMAS structure created (see function for path mapping)\n');
end

% ==============================================================================
% EXAMPLE 7: Generate GUI controls dynamically
% ==============================================================================
function example_generate_gui_controls()
    fprintf('\n=== EXAMPLE 7: Generate GUI Controls Dynamically ===\n\n');

    topology_key = 'buck';
    [required, optional] = get_visible_fields_for_topology(topology_key);

    % Create a figure
    fig = figure('Name', topology_key, 'NumberTitle', 'off');
    y_pos = 0.9;

    % Add required fields
    fprintf('Creating UI controls for required fields:\n');
    for i = 1:length(required)
        field_name = required{i};
        meta = get_field_metadata(field_name);

        % Label
        uicontrol('Style', 'text', ...
            'String', sprintf('%s [%s]:', meta.label, meta.unit), ...
            'Units', 'normalized', ...
            'Position', [0.05, y_pos, 0.35, 0.05]);

        % Input field
        uicontrol('Style', 'edit', ...
            'String', num2str(meta.default), ...
            'Units', 'normalized', ...
            'Position', [0.45, y_pos, 0.45, 0.05], ...
            'Tag', field_name);

        % Tooltip
        uicontrol('Style', 'text', ...
            'String', sprintf('[%g - %g]', meta.min, meta.max), ...
            'Units', 'normalized', ...
            'Position', [0.05, y_pos-0.03, 0.85, 0.02], ...
            'FontSize', 9);

        fprintf('  %s: [%g, %g]\n', meta.label, meta.min, meta.max);

        y_pos = y_pos - 0.1;
    end

    close(fig);
    fprintf('GUI creation example complete\n');
end

% ==============================================================================
% EXAMPLE 8: List all available topologies (helper function)
% ==============================================================================
function topology_keys = get_all_topology_keys()
    % Helper: Get list of all topology keys
    defs = topology_metadata();
    TOPOLOGY_DEFS = defs.TOPOLOGY_DEFINITIONS;
    topology_keys = fieldnames(TOPOLOGY_DEFS);
end

% ==============================================================================
% RUN ALL EXAMPLES
% ==============================================================================

function run_all_examples()
    fprintf('\n');
    fprintf('================================================================================\n');
    fprintf('TOPOLOGY METADATA EXAMPLES\n');
    fprintf('================================================================================\n');

    example_list_all_topologies();
    example_show_fields_for_topology('two_switch_forward');
    example_check_field_requirement();
    example_build_design_data();
    example_detect_output_capability();
    example_create_mas_from_metadata();
    example_generate_gui_controls();

    fprintf('\n');
    fprintf('================================================================================\n');
    fprintf('All examples complete!\n');
    fprintf('================================================================================\n');
end
