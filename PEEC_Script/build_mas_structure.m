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

    % ===== STEP 7b: Operating Temperature =====
    if isfield(gui_data, 'thermal') && isstruct(gui_data.thermal)
        if isfield(gui_data.thermal, 'ambient_temp')
            if isfield(gui_data.thermal, 'max_rise')
                max_op_temp = gui_data.thermal.ambient_temp + gui_data.thermal.max_rise;
            else
                max_op_temp = gui_data.thermal.ambient_temp + 40;  % Default +40°C rise
            end
            mas_struct.inputs.designRequirements.operatingTemperature = struct('maximum', max_op_temp);
        end
    end

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

        % mainSupplyVoltage is required by PyOpenMagnetics insulation calculations
        % (creepage/clearance rules depend on the mains voltage seen by primary insulation)
        if isfield(gui_data.converter, 'vin_nom') && ~isempty(gui_data.converter.vin_nom) && gui_data.converter.vin_nom > 0
            vin_nom_val = gui_data.converter.vin_nom;
        else
            vin_nom_val = (gui_data.converter.vin_min + gui_data.converter.vin_max) / 2;
        end
        insulation.mainSupplyVoltage = struct( ...
            'nominal', vin_nom_val, ...
            'minimum', gui_data.converter.vin_min, ...
            'maximum', gui_data.converter.vin_max);

        insulation.wiringTechnology = 'Wound';

        mas_struct.inputs.designRequirements.insulation = insulation;
    end

    % ===== STEP 9: Overlay Design Requirements from Design Requirements figure =====
    % When gui_data.design_req is present, it contains fields matching the MAS
    % designRequirements schema (already in SI units). Optional fields are gated
    % by gui_data.design_req.enabled.<fieldName> flags.
    if isfield(gui_data, 'design_req')
        dr = gui_data.design_req;
        mas = mas_struct;  % shorthand alias (written back at end)

        % magnetizingInductance (always present, required)
        if isfield(dr, 'magnetizingInductance') && isstruct(dr.magnetizingInductance)
            lm = dr.magnetizingInductance;
            lm_out = struct();
            if isfield(lm, 'minimum') && ~isempty(lm.minimum), lm_out.minimum = lm.minimum; end
            if isfield(lm, 'nominal') && ~isempty(lm.nominal), lm_out.nominal = lm.nominal; end
            if isfield(lm, 'maximum') && ~isempty(lm.maximum), lm_out.maximum = lm.maximum; end
            if ~isempty(fieldnames(lm_out))
                mas.inputs.designRequirements.magnetizingInductance = lm_out;
            end
        end

        % turnsRatios (always present, required) - cell array of structs
        if isfield(dr, 'turnsRatios') && iscell(dr.turnsRatios) && ~isempty(dr.turnsRatios)
            tr_arr = {};
            for k = 1:numel(dr.turnsRatios)
                tr_item = dr.turnsRatios{k};
                tr_out = struct();
                if isfield(tr_item, 'minimum') && ~isempty(tr_item.minimum), tr_out.minimum = tr_item.minimum; end
                if isfield(tr_item, 'nominal') && ~isempty(tr_item.nominal), tr_out.nominal = tr_item.nominal; end
                if isfield(tr_item, 'maximum') && ~isempty(tr_item.maximum), tr_out.maximum = tr_item.maximum; end
                tr_arr{k} = tr_out;
            end
            mas.inputs.designRequirements.turnsRatios = tr_arr;
        end

        % Check enabled flags for optional requirements
        enabled = struct();
        if isfield(dr, 'enabled'), enabled = dr.enabled; end

        % insulation (if enabled) - overrides Step 8 insulation with Design Requirements values
        if isfield(enabled, 'insulation') && enabled.insulation && isfield(dr, 'insulation')
            ins = dr.insulation;
            ins_out = struct();
            if isfield(ins, 'cti'), ins_out.cti = ins.cti; end
            if isfield(ins, 'pollutionDegree'), ins_out.pollutionDegree = ins.pollutionDegree; end
            if isfield(ins, 'overvoltageCategory'), ins_out.overvoltageCategory = ins.overvoltageCategory; end
            if isfield(ins, 'insulationType'), ins_out.insulationType = ins.insulationType; end
            if isfield(ins, 'standards'), ins_out.standards = ins.standards; end
            if isfield(ins, 'altitude') && isstruct(ins.altitude)
                ins_out.altitude = filter_dim_tolerance(ins.altitude);
            end
            if isfield(ins, 'mainSupplyVoltage') && isstruct(ins.mainSupplyVoltage)
                ins_out.mainSupplyVoltage = filter_dim_tolerance(ins.mainSupplyVoltage);
            end
            mas.inputs.designRequirements.insulation = ins_out;
        end

        % operatingTemperature (if enabled) - overrides Step 7b value
        if isfield(enabled, 'operatingTemperature') && enabled.operatingTemperature
            if isfield(dr, 'operatingTemperature') && isstruct(dr.operatingTemperature)
                mas.inputs.designRequirements.operatingTemperature = filter_dim_tolerance(dr.operatingTemperature);
            end
        end

        % maximumWeight (in kg)
        if isfield(enabled, 'maximumWeight') && enabled.maximumWeight
            if isfield(dr, 'maximumWeight') && ~isempty(dr.maximumWeight)
                mas.inputs.designRequirements.maximumWeight = dr.maximumWeight;
            end
        end

        % maximumDimensions (in m)
        if isfield(enabled, 'maximumDimensions') && enabled.maximumDimensions
            if isfield(dr, 'maximumDimensions') && isstruct(dr.maximumDimensions)
                dims = struct();
                if isfield(dr.maximumDimensions, 'width') && ~isempty(dr.maximumDimensions.width)
                    dims.width = dr.maximumDimensions.width;
                end
                if isfield(dr.maximumDimensions, 'height') && ~isempty(dr.maximumDimensions.height)
                    dims.height = dr.maximumDimensions.height;
                end
                if isfield(dr.maximumDimensions, 'depth') && ~isempty(dr.maximumDimensions.depth)
                    dims.depth = dr.maximumDimensions.depth;
                end
                if ~isempty(fieldnames(dims))
                    mas.inputs.designRequirements.maximumDimensions = dims;
                end
            end
        end

        % wiringTechnology
        if isfield(enabled, 'wiringTechnology') && enabled.wiringTechnology
            if isfield(dr, 'wiringTechnology') && ~isempty(dr.wiringTechnology)
                mas.inputs.designRequirements.wiringTechnology = dr.wiringTechnology;
            end
        end

        % market
        if isfield(enabled, 'market') && enabled.market
            if isfield(dr, 'market') && ~isempty(dr.market)
                mas.inputs.designRequirements.market = dr.market;
            end
        end

        % topology (string name) - overrides Step 1 value if design_req provides it
        if isfield(enabled, 'topology') && enabled.topology
            if isfield(dr, 'topology') && ~isempty(dr.topology)
                mas.inputs.designRequirements.topology = dr.topology;
            end
        end

        % leakageInductance (cell array, per secondary)
        if isfield(enabled, 'leakageInductance') && enabled.leakageInductance
            if isfield(dr, 'leakageInductance') && iscell(dr.leakageInductance)
                llk_arr = {};
                for k = 1:numel(dr.leakageInductance)
                    llk_arr{k} = filter_dim_tolerance(dr.leakageInductance{k});
                end
                mas.inputs.designRequirements.leakageInductance = llk_arr;
            end
        end

        % strayCapacitance (cell array, per secondary)
        if isfield(enabled, 'strayCapacitance') && enabled.strayCapacitance
            if isfield(dr, 'strayCapacitance') && iscell(dr.strayCapacitance)
                sc_arr = {};
                for k = 1:numel(dr.strayCapacitance)
                    sc_arr{k} = filter_dim_tolerance(dr.strayCapacitance{k});
                end
                mas.inputs.designRequirements.strayCapacitance = sc_arr;
            end
        end

        % minimumImpedance (cell array of {frequency, magnitude} structs)
        if isfield(enabled, 'minimumImpedance') && enabled.minimumImpedance
            if isfield(dr, 'minimumImpedance') && iscell(dr.minimumImpedance)
                imp_arr = {};
                for k = 1:numel(dr.minimumImpedance)
                    item = dr.minimumImpedance{k};
                    imp_arr{k} = struct('frequency', item.frequency, ...
                                         'impedance', struct('magnitude', item.magnitude));
                end
                mas.inputs.designRequirements.minimumImpedance = imp_arr;
            end
        end

        % isolationSides (cell array of strings)
        if isfield(enabled, 'isolationSides') && enabled.isolationSides
            if isfield(dr, 'isolationSides') && iscell(dr.isolationSides)
                mas.inputs.designRequirements.isolationSides = dr.isolationSides;
            end
        end

        % terminalType (cell array of strings)
        if isfield(enabled, 'terminalType') && enabled.terminalType
            if isfield(dr, 'terminalType') && iscell(dr.terminalType)
                mas.inputs.designRequirements.terminalType = dr.terminalType;
            end
        end

        mas_struct = mas;  % write back from shorthand alias
    end

end


% ===== HELPER FUNCTIONS =====

function topology_mas = topology_key_to_mas(topology_key)
% Map MATLAB topology key (snake_case) to PyOpenMagnetics formal names.
% PyOpenMagnetics C++ requires exact formal names (not kebab-case).

    mapping = struct();
    mapping.two_switch_forward = 'Two Switch Forward Converter';
    mapping.single_switch_forward = 'Single Switch Forward Converter';
    mapping.active_clamp_forward = 'Active Clamp Forward Converter';
    mapping.flyback = 'Flyback Converter';
    mapping.push_pull = 'Push Pull Converter';
    mapping.buck = 'Buck Converter';
    mapping.boost = 'Boost Converter';
    mapping.isolated_buck = 'Isolated Buck Converter';
    mapping.isolated_buck_boost = 'Isolated Buck Boost Converter';

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


function out = filter_dim_tolerance(dt)
% Filter a dimensionWithTolerance struct, keeping only non-empty fields.
% Input: struct with optional fields 'minimum', 'nominal', 'maximum'
% Output: struct with only the non-empty fields preserved
    out = struct();
    if isfield(dt, 'minimum') && ~isempty(dt.minimum), out.minimum = dt.minimum; end
    if isfield(dt, 'nominal') && ~isempty(dt.nominal), out.nominal = dt.nominal; end
    if isfield(dt, 'maximum') && ~isempty(dt.maximum), out.maximum = dt.maximum; end
end
