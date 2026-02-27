function mas_struct = build_mas_structure(gui_data, topology_key)
% MATLAB: build_mas_structure.m
% Converts GUI parameter struct to MAS-compatible format for PyOpenMagnetics
%
% Inputs:
%   gui_data: struct with fields collected from topology_wizard.m GUI
%     .converter: struct with vin_min, vin_max, vin_nom, vout, iout, fsw_khz, etc.
%     .thermal: struct with ambient_temp
%     .insulation: struct with class, standard, pollution_degree, overvoltage_cat, cti, altitude_max
%   topology_key: string, one of 9 topology keys (e.g., 'two_switch_forward')
%
% Outputs:
%   mas_struct: struct ready to be JSON-encoded for PyOpenMagnetics API
%     .inputs.designRequirements
%     .inputs.operatingPoints
%     .magnetic: {} (empty, will be filled by adviser)
%     .outputs: {} (empty, will be filled by adviser)

    % Initialize output structure
    mas_struct = struct();
    mas_struct.inputs = struct();
    mas_struct.inputs.designRequirements = struct();
    mas_struct.inputs.operatingPoints = {};
    mas_struct.magnetic = struct();
    mas_struct.outputs = struct();

    % ===== STEP 1: Map topology key to MAS format =====
    topology_mas = topology_key_to_mas(topology_key);
    mas_struct.inputs.designRequirements.topology = topology_mas;

    % ===== STEP 2: Build Input Voltage =====
    % Validation: ensure vin_min and vin_max are valid
    if ~isfield(gui_data, 'converter') || ~isfield(gui_data.converter, 'vin_min')
        error('gui_data.converter.vin_min is required');
    end
    if ~isfield(gui_data.converter, 'vin_max')
        error('gui_data.converter.vin_max is required');
    end

    vin_min = gui_data.converter.vin_min;
    vin_max = gui_data.converter.vin_max;

    if vin_min <= 0 || vin_max <= 0 || vin_min > vin_max
        error('Input voltage min/max invalid: min=%.1f, max=%.1f', vin_min, vin_max);
    end

    mas_struct.inputs.designRequirements.inputVoltage = struct();
    mas_struct.inputs.designRequirements.inputVoltage.minimum = vin_min;
    mas_struct.inputs.designRequirements.inputVoltage.maximum = vin_max;

    % Compute nominal if not provided
    if isfield(gui_data.converter, 'vin_nom') && ~isempty(gui_data.converter.vin_nom) && gui_data.converter.vin_nom ~= 0
        mas_struct.inputs.designRequirements.inputVoltage.nominal = gui_data.converter.vin_nom;
    else
        mas_struct.inputs.designRequirements.inputVoltage.nominal = (vin_min + vin_max) / 2;
    end

    % ===== STEP 3: Diode Voltage Drop =====
    if isfield(gui_data.converter, 'vd') && ~isempty(gui_data.converter.vd)
        mas_struct.inputs.designRequirements.diodeVoltageDrop = gui_data.converter.vd;
    end

    % ===== STEP 4: Current Ripple Ratio =====
    if isfield(gui_data.converter, 'max_ripple') && ~isempty(gui_data.converter.max_ripple)
        % Convert from percentage to decimal (single source of truth)
        mas_struct.inputs.designRequirements.currentRippleRatio = gui_data.converter.max_ripple / 100;
    end

    % ===== STEP 5: Efficiency =====
    if isfield(gui_data.converter, 'efficiency') && ~isempty(gui_data.converter.efficiency)
        % Convert from percentage to decimal (single source of truth)
        mas_struct.inputs.designRequirements.efficiency = gui_data.converter.efficiency / 100;
    end

    % ===== STEP 6: Topology-Specific Optional Fields =====
    switch topology_key
        case {'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', 'push_pull'}
            % Forward topologies: maximum switch current
            if isfield(gui_data.converter, 'max_switch_current') && ~isempty(gui_data.converter.max_switch_current)
                mas_struct.inputs.designRequirements.maximumSwitchCurrent = gui_data.converter.max_switch_current;
            end
        case 'flyback'
            % Flyback: maximum duty cycle and drain-source voltage
            if isfield(gui_data.converter, 'max_duty') && ~isempty(gui_data.converter.max_duty)
                % Already converted from percentage to decimal in collect_gui_field_values()
                mas_struct.inputs.designRequirements.maximumDutyCycle = gui_data.converter.max_duty;
            end
            if isfield(gui_data.converter, 'max_drain_source_voltage') && ~isempty(gui_data.converter.max_drain_source_voltage)
                mas_struct.inputs.designRequirements.maximumDrainSourceVoltage = gui_data.converter.max_drain_source_voltage;
            end
    end

    % ===== STEP 7: Build Operating Points =====
    % Determine if topology supports multi-output
    output_type = get_topology_output_type(topology_key);

    operating_point = struct();

    % Switching frequency (convert from kHz to Hz)
    if ~isfield(gui_data.converter, 'fsw_khz')
        error('gui_data.converter.fsw_khz is required');
    end
    operating_point.switchingFrequency = gui_data.converter.fsw_khz * 1000;

    % Ambient temperature
    if isfield(gui_data, 'thermal') && isfield(gui_data.thermal, 'ambient_temp')
        operating_point.ambientTemperature = gui_data.thermal.ambient_temp;
    else
        operating_point.ambientTemperature = 25;  % Default: 25C
    end

    % Output voltage(s) and current(s)
    if strcmp(output_type, 'multi')
        % Multi-output topology: use arrays
        if isfield(gui_data.converter, 'output_voltages') && ~isempty(gui_data.converter.output_voltages)
            operating_point.outputVoltages = gui_data.converter.output_voltages;
        else
            % Fallback: single output
            if ~isfield(gui_data.converter, 'vout')
                error('gui_data.converter.vout is required');
            end
            operating_point.outputVoltages = [gui_data.converter.vout];
        end

        if isfield(gui_data.converter, 'output_currents') && ~isempty(gui_data.converter.output_currents)
            operating_point.outputCurrents = gui_data.converter.output_currents;
        else
            % Fallback: single output
            if ~isfield(gui_data.converter, 'iout')
                error('gui_data.converter.iout is required');
            end
            operating_point.outputCurrents = [gui_data.converter.iout];
        end
    else
        % Single-output topology: use scalars
        if ~isfield(gui_data.converter, 'vout')
            error('gui_data.converter.vout is required');
        end
        if ~isfield(gui_data.converter, 'iout')
            error('gui_data.converter.iout is required');
        end
        operating_point.outputVoltage = gui_data.converter.vout;
        operating_point.outputCurrent = gui_data.converter.iout;
    end

    % Operating points is an array of structures
    mas_struct.inputs.operatingPoints = {operating_point};

    % ===== STEP 8: Insulation Block (optional) =====
    if isfield(gui_data, 'insulation') && isstruct(gui_data.insulation)
        insulation = struct();

        if isfield(gui_data.insulation, 'class')
            insulation.insulationType = gui_data.insulation.class;
        end

        if isfield(gui_data.insulation, 'standard')
            % Wrap in cell array for JSON encoding
            if ischar(gui_data.insulation.standard)
                insulation.standards = {gui_data.insulation.standard};
            else
                insulation.standards = gui_data.insulation.standard;
            end
        end

        if isfield(gui_data.insulation, 'pollution_degree')
            insulation.pollutionDegree = sprintf('P%d', gui_data.insulation.pollution_degree);
        end

        if isfield(gui_data.insulation, 'overvoltage_cat')
            insulation.overvoltageCategory = sprintf('OVC-%s', gui_data.insulation.overvoltage_cat);
        end

        if isfield(gui_data.insulation, 'cti')
            insulation.cti = gui_data.insulation.cti;
        end

        if isfield(gui_data.insulation, 'altitude_max')
            insulation.altitude = struct();
            insulation.altitude.nominal = gui_data.insulation.altitude_max;
            insulation.altitude.minimum = 0;
            insulation.altitude.maximum = gui_data.insulation.altitude_max;
        end

        insulation.wiringTechnology = 'Wound';

        mas_struct.inputs.designRequirements.insulation = insulation;
    end

end


% ===== HELPER FUNCTIONS =====

function topology_mas = topology_key_to_mas(topology_key)
% Map MATLAB topology key (snake_case) to MAS format (kebab-case)

    mapping = struct();
    mapping.two_switch_forward = 'two-switch-forward';
    mapping.single_switch_forward = 'single-switch-forward';
    mapping.active_clamp_forward = 'active-clamp-forward';
    mapping.flyback = 'flyback';
    mapping.push_pull = 'push-pull';
    mapping.buck = 'buck';
    mapping.boost = 'boost';
    mapping.isolated_buck = 'isolated-buck';
    mapping.isolated_buck_boost = 'isolated-buck-boost';

    if isfield(mapping, topology_key)
        topology_mas = mapping.(topology_key);
    else
        error('Unknown topology key: %s', topology_key);
    end
end


function output_type = get_topology_output_type(topology_key)
% Determine if topology supports single or multi-output
% Non-isolated topologies (Buck, Boost): single output (inductor, not transformer)
% Isolated topologies (Forward, Flyback, etc.): can have multiple secondary outputs

    multi_output_topologies = {
        'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', ...
        'flyback', 'push_pull', 'isolated_buck', 'isolated_buck_boost'
    };

    if ismember(topology_key, multi_output_topologies)
        output_type = 'multi';
    else
        output_type = 'single';
    end
end
