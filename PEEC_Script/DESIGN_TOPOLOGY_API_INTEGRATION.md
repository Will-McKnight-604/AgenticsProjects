# Design: Direct PyOpenMagnetics API Integration for topology_wizard.m

**Status**: Design Document v1.0
**Date**: 2026-02-25
**Objective**: Replace hand-coded equations in `generate_om_topology.py` with direct PyOpenMagnetics API calls for topology-aware design recommendations.

---

## 1. Executive Summary

### Current Flow
```
topology_wizard.m (GUI user inputs)
  └─> generate_om_topology.py (hand-coded topology equations)
      ├─ Computes Lm, turns ratio, duty cycle, currents
      ├─ Builds MAS JSON structure
      └─> output: om_topology_results.json (computed requirements + MAS inputs)
           └─> interactive_winding_designer.m (receives design_spec)
```

### Proposed Flow
```
topology_wizard.m (GUI user inputs)
  └─> NEW: request_openmagnetics_computation(data)
      ├─ Gathers: topology_key, inputVoltage{}, operatingPoints[], etc.
      ├─ Builds: MAS-compliant JSON structure per topology
      └─> NEW: call_pyopenmagnetics_api.py (Python wrapper)
          ├─ Step 1: pm.process_inputs(inputs) — adds harmonics
          ├─ Step 2: pm.calculate_advised_magnetics(inputs, max_results=5, core_mode='STANDARD_CORES')
          │   Returns: {data: [{mas, scoring, scoringPerFilter}, ...]}
          ├─ Step 3: parse_openmagnetics_results() — extract cores/wires
          └─> output: om_api_results.json (ranked designs with full MAS)
               └─> interactive_winding_designer.m (use first result or let user select)
```

### Key Advantages
1. **Physics-based**: PyOpenMagnetics uses Faraday's law, reluctance networks, loss models
2. **Topology-aware**: Adviser understands each topology's operating conditions and constraints
3. **Material database**: Full access to manufacturer cores, wires, materials (679 core shapes, 409 materials, 4329+ wires)
4. **Automatic winding design**: Adviser computes turn counts, wire sizes, losses, temps for each recommended core
5. **Scoring**: Each design ranked by EFFICIENCY, DIMENSIONS, COST trade-offs
6. **No equation duplication**: Single source of truth (PyOpenMagnetics C++ layer)

---

## 2. System Architecture

### 2.1 MATLAB Data Structure: `data` (topology_wizard.m)

**Current State** (lines 14-97 in topology_wizard.m):
```matlab
data.converter.vin_min       % V (100)
data.converter.vin_max       % V (190)
data.converter.vin_nom       % V (optional, computed as midpoint)
data.converter.vout          % V (5)
data.converter.iout          % A (5)
data.converter.fsw_khz       % kHz (200)
data.converter.efficiency    % percent (90)
data.converter.vd            % V (0.7) — diode forward drop
data.converter.max_ripple    % percent (30)
data.converter.max_duty      % [] (empty = derived)
data.converter.max_switch_current  % A ([] = unconstrained)
data.converter.n_outputs     % int (1-4 for multi-output topologies)

data.topology                % string: 'two_switch_forward', 'flyback', etc.
data.design_mode             % 'auto' | 'advanced'
data.n_outputs               % int (1-4)

data.insulation.class        % 'Basic'|'Functional'|'Supplementary'|'Reinforced'|'Double'
data.insulation.pollution_degree  % 1|2|3
data.insulation.overvoltage_cat   % 'I'|'II'|'III'|'IV'
data.insulation.standard     % 'IEC 60664-1'|'61558-1'|'60335-1'|'62368-1'
data.insulation.cti          % 'Group I'|'II'|'IIIA'|'IIIB'
data.insulation.altitude_max % m (2000)

data.thermal.ambient_temp    % C (25)
data.thermal.max_rise        % C (40)
data.thermal.cooling         % 'Natural'|'Forced'

data.requirements            % Struct with computed Lm, turns_ratio, currents, etc. (initially zeros)

data.rec.n_results           % int (5 recommendations)
data.rec.weight_cost         % float (1/3)
data.rec.weight_losses       % float (1/3)
data.rec.weight_dimensions   % float (1/3)
```

**Required Additions**:
```matlab
% Operating points for each topology (multi-point design)
data.operating_points = struct();
data.operating_points.points = {}  % Cell array of operating point structs

% Mapping of topology name → MAS topology key
data.topology_to_mas_key = containers.Map();
% Examples: 'two_switch_forward' → 'two-switch-forward'
%           'single_switch_forward' → 'single-switch-forward'
%           'buck' → 'buck', etc.

% Results from API
data.api_results = struct();  % Will contain ranked designs, scores, winding details
data.api_results.status = '';  % 'pending' | 'computing' | 'success' | 'error'
data.api_results.designs = {};  % Cell array of design result structs
data.api_results.selected_idx = 0;  % Which design user selected
```

---

## 3. Input Collection: `request_openmagnetics_computation(data)` [NEW MATLAB FUNCTION]

**Purpose**: Gather GUI parameters and call PyOpenMagnetics API via new Python bridge
**Location**: topology_wizard.m (replaces `request_topology_compute`)
**Called from**: `cb_compute_topology` callback (line 1290)

### 3.1 Function Signature
```matlab
function data = request_openmagnetics_computation(data)
    % Gather all GUI inputs and prepare MAS JSON for PyOpenMagnetics API
    %
    % Inputs:
    %   data  - topology_wizard data struct with converter, topology, insulation, thermal
    %
    % Outputs:
    %   data  - updated with api_results containing ranked designs
    %
    % Calls:
    %   build_mas_structure(topology_key, gui_params)
    %   call_pyopenmagnetics_api.py (via system command)
    %   parse_openmagnetics_results(api_output)
```

### 3.2 Implementation Outline

```matlab
function data = request_openmagnetics_computation(data)

    % Step 1: Validate converter specs
    validate_converter_specs(data.converter);

    % Step 2: Compute operating points (topology-specific)
    [op_points, design_req] = compute_operating_points(data);

    % Step 3: Build MAS JSON structure
    mas_inputs = build_mas_structure(data.topology, data.converter, ...
                                    op_points, design_req, data.insulation);

    % Step 4: Call Python API wrapper
    [api_output, status_msg] = call_pyopenmagnetics_api(mas_inputs, data.rec);

    if status_msg.has_error
        error(status_msg.message);
    end

    % Step 5: Parse API results and populate data.api_results
    data = parse_openmagnetics_results(data, api_output);

    % Step 6: Display results to user (in GUI)
    update_api_results_display(data);

end
```

### 3.3 Step 1: Validate Converter Specs

```matlab
function validate_converter_specs(converter)
    % Check all required fields are populated and valid

    required_fields = {'vin_min', 'vin_max', 'vout', 'iout', 'fsw_khz'};
    for i = 1:length(required_fields)
        field = required_fields{i};
        if ~isfield(converter, field) || isempty(converter.(field)) || converter.(field) <= 0
            error('Missing or invalid converter spec: %s', field);
        end
    end

    if converter.vin_min >= converter.vin_max
        error('Input voltage: min must be less than max');
    end

    if converter.vout >= converter.vin_max
        error('Output voltage cannot exceed max input voltage');
    end

    % Optional: Warn if topology-specific constraints violated
    % (e.g., buck requires Vout < Vin, etc.)
end
```

### 3.4 Step 2: Compute Operating Points (Topology-Aware)

**Purpose**: Convert GUI params into PyOpenMagnetics excitation arrays

For each topology, generate appropriate operating point(s):

#### **2-Switch Forward / 1-Switch Forward / Active Clamp Forward**
```matlab
% Rectangular voltage on primary, triangular current (CCM)
% Multiple operating points: low line, nominal, high line

op_points(1).name = 'Low Line (85 VAC)';
op_points(1).vin = data.converter.vin_min;
op_points(1).frequency_hz = data.converter.fsw_khz * 1e3;
op_points(1).conditions.ambientTemperature = data.thermal.ambient_temp;

% Compute currents from topology equations
[n_pri, n_sec, duty, i_pri, i_sec, i_mag] = forward_topology_calcs(...);

op_points(1).excitationsPerWinding(1).name = 'Primary';
op_points(1).excitationsPerWinding(1).frequency = op_points(1).frequency_hz;
op_points(1).excitationsPerWinding(1).current.processed.label = 'Rectangular';
op_points(1).excitationsPerWinding(1).current.processed.peakToPeak = i_pri_pp;
op_points(1).excitationsPerWinding(1).current.processed.offset = i_pri_offset;
op_points(1).excitationsPerWinding(1).current.processed.dutyCycle = duty;
op_points(1).excitationsPerWinding(1).voltage.processed.label = 'Rectangular';
op_points(1).excitationsPerWinding(1).voltage.processed.peakToPeak = v_pri_pp;
op_points(1).excitationsPerWinding(1).voltage.processed.offset = 0;
op_points(1).excitationsPerWinding(1).voltage.processed.dutyCycle = duty;

op_points(1).excitationsPerWinding(2).name = 'Secondary';
% Similar structure for secondary...
```

#### **Flyback**
```matlab
% Primary: Rectangular voltage, triangular current (energy storage during on-time)
% Secondary: Triangular current during off-time (1-D duty), zero during on-time
% Typically just ONE operating point (worst-case low line or nominal)
```

#### **Buck / Boost / Isolated Buck**
```matlab
% Both primary/inductor: Triangular current (CCM ripple)
% Voltage: Rectangular (PWM switching)
% Duty cycle determines on/off ratio
```

#### **Isolated Buck-Boost**
```matlab
% Similar to IsolatedBuck but boost path (Vout = Vin * D/(1-D))
% Energy storage in primary (like flyback)
```

#### **Push-Pull**
```matlab
% Two switches operating 180° out of phase
% Primary: Dual-channel rectangular voltage
% Secondary: Rectified waveform (similar to forward)
```

**Key Point**: Each topology has distinct **waveform shapes** and **duty cycle constraints**. PyOpenMagnetics adviser uses these to compute realistic losses (core saturation, copper losses at specific waveforms).

### 3.5 Step 3: Build MAS JSON Structure

**Function Signature**:
```matlab
function mas_inputs = build_mas_structure(topology_key, converter, op_points, ...
                                         design_req, insulation)
    % Build PyOpenMagnetics MAS input structure per IEC/OpenMagnetics schema
    %
    % Inputs:
    %   topology_key: 'two_switch_forward', 'flyback', etc. (snake_case)
    %   converter: struct with vin_min, vin_max, vout, iout, fsw_khz, vd, etc.
    %   op_points: cell array of operating point structs
    %   design_req: struct with Lm, turns_ratios, n_windings (from topology calc)
    %   insulation: struct with class, standard, pollution_degree, etc.
    %
    % Returns:
    %   mas_inputs: struct with fields:
    %      - designRequirements (magnetizing inductance, turns ratios, insulation)
    %      - operatingPoints (frequency, excitations per winding)
    %      - [optional] simulationModels (loss models, reluctance models)
```

**MAS Schema Overview** (from PyOpenMagnetics/examples):

```json
{
  "designRequirements": {
    "topology": "two-switch-forward",
    "magnetizingInductance": {
      "nominal": 200e-6,
      "minimum": 180e-6,
      "maximum": 220e-6
    },
    "turnsRatios": [
      { "nominal": 2.0 }
    ],
    "insulation": {
      "insulationType": "Functional",
      "pollutionDegree": "P2",
      "overvoltageCategory": "OVC-II",
      "cti": "GroupII"
    }
  },
  "operatingPoints": [
    {
      "name": "Low Line",
      "conditions": {
        "ambientTemperature": 40,
        "coolingType": "Natural"
      },
      "excitationsPerWinding": [
        {
          "name": "Primary",
          "frequency": 200000,
          "current": {
            "processed": {
              "label": "Rectangular",
              "peakToPeak": 10.5,
              "offset": 5.25,
              "dutyCycle": 0.45
            }
          },
          "voltage": {
            "processed": {
              "label": "Rectangular",
              "peakToPeak": 150,
              "offset": 75,
              "dutyCycle": 0.45
            }
          }
        }
      ]
    }
  ]
}
```

**Implementation Details**:

```matlab
function mas_inputs = build_mas_structure(topology_key, converter, op_points, ...
                                         design_req, insulation)

    % Initialize MAS structure
    mas_inputs = struct();

    % --- designRequirements section ---
    mas_inputs.designRequirements = struct();

    % Map topology from snake_case to kebab-case (two_switch_forward → two-switch-forward)
    topology_display = strrep(topology_key, '_', '-');
    mas_inputs.designRequirements.topology = topology_display;

    % Magnetizing inductance (if applicable — skip for non-transformer topologies)
    if isfield(design_req, 'magnetizing_inductance_H') && design_req.magnetizing_inductance_H > 0
        mas_inputs.designRequirements.magnetizingInductance = struct();
        Lm = design_req.magnetizing_inductance_H;
        mas_inputs.designRequirements.magnetizingInductance.nominal = Lm;
        mas_inputs.designRequirements.magnetizingInductance.minimum = Lm * 0.9;
        mas_inputs.designRequirements.magnetizingInductance.maximum = Lm * 1.1;
    end

    % Turns ratios (for isolated topologies)
    if isfield(design_req, 'turns_ratios') && ~isempty(design_req.turns_ratios)
        mas_inputs.designRequirements.turnsRatios = design_req.turns_ratios;
    end

    % Insulation (safety requirements per IEC 60664-1, 62368-1, etc.)
    mas_inputs.designRequirements.insulation = struct();
    insulation_type_map = containers.Map();
    insulation_type_map('Basic') = 'Basic';
    insulation_type_map('Functional') = 'Functional';
    insulation_type_map('Supplementary') = 'Supplementary';
    insulation_type_map('Reinforced') = 'Reinforced';
    insulation_type_map('Double') = 'Double';

    mas_inputs.designRequirements.insulation.insulationType = ...
        insulation_type_map(insulation.class);

    % Map pollution degree: 1→P1, 2→P2, 3→P3
    pollution_degree_str = sprintf('P%d', insulation.pollution_degree);
    mas_inputs.designRequirements.insulation.pollutionDegree = pollution_degree_str;

    % Overvoltage category: I/II/III/IV → OVC-I/II/III/IV
    mas_inputs.designRequirements.insulation.overvoltageCategory = ...
        sprintf('OVC-%s', insulation.overvoltage_cat);

    % CTI (Comparative Tracking Index)
    cti_map = containers.Map();
    cti_map('Group I') = 'GroupI';
    cti_map('Group II') = 'GroupII';
    cti_map('Group IIIA') = 'GroupIIIA';
    cti_map('Group IIIB') = 'GroupIIIB';
    if isKey(cti_map, insulation.cti)
        mas_inputs.designRequirements.insulation.cti = cti_map(insulation.cti);
    end

    % --- operatingPoints section ---
    mas_inputs.operatingPoints = op_points;

    % Ensure operatingPoints is an array (convert from cell if needed)
    if iscell(mas_inputs.operatingPoints)
        mas_inputs.operatingPoints = cell2mat(mas_inputs.operatingPoints);
    end

end
```

**Handling Multi-Output Topologies**:

For topologies like Isolated Buck with N outputs (N=1-4 secondaries):

```matlab
% In build_mas_structure, when N > 1:
if isfield(design_req, 'n_outputs') && design_req.n_outputs > 1
    % Create secondary winding excitations for each output
    for out_idx = 1:design_req.n_outputs
        % Secondary_1, Secondary_2, ... or just duplicate structure
        secondary_exc = struct();
        secondary_exc.name = sprintf('Secondary_%d', out_idx);
        secondary_exc.frequency = op_points(1).frequency_hz;
        secondary_exc.current.processed.label = 'Rectangular';
        secondary_exc.current.processed.peakToPeak = design_req.i_sec_pp(out_idx);
        secondary_exc.current.processed.offset = 0;
        secondary_exc.current.processed.dutyCycle = 1 - design_req.duty;
        % ... voltage structure ...

        excitations_array(end+1) = secondary_exc;
    end
    op_points(1).excitationsPerWinding = excitations_array;
end
```

### 3.6 Step 4: Call PyOpenMagnetics API

**Function Signature**:
```matlab
function [api_output, status_msg] = call_pyopenmagnetics_api(mas_inputs, rec_settings)
    % Call new Python bridge to PyOpenMagnetics API
    %
    % Inputs:
    %   mas_inputs: struct built by build_mas_structure()
    %   rec_settings: struct with weights, n_results, core_mode
    %
    % Returns:
    %   api_output: parsed JSON from Python (list of {mas, scoring, scoringPerFilter})
    %   status_msg: struct with .has_error, .message
```

**Implementation**:
```matlab
function [api_output, status_msg] = call_pyopenmagnetics_api(mas_inputs, rec_settings)

    status_msg.has_error = false;
    status_msg.message = '';

    script_dir = pwd();
    config_file = 'call_api_config.json';
    output_file = 'call_api_results.json';
    py_script = 'call_pyopenmagnetics_api.py';

    % Build config JSON (input to Python script)
    config = struct();
    config.mode = 'calculate_advised_magnetics';
    config.inputs = mas_inputs;
    config.settings = struct();
    config.settings.max_results = rec_settings.n_results;
    config.settings.core_mode = 'STANDARD_CORES';  % or 'AVAILABLE_CORES' if in-stock only
    config.output_file = strrep(fullfile(script_dir, output_file), '\', '/');

    % Optional: Weights for multi-criteria optimization
    % (Note: PyOpenMagnetics adviser doesn't use these; it returns all criteria)
    config.settings.weights = struct();
    config.settings.weights.EFFICIENCY = rec_settings.weight_losses;
    config.settings.weights.DIMENSIONS = rec_settings.weight_dimensions;
    config.settings.weights.COST = rec_settings.weight_cost;

    % Write config JSON
    config_path = fullfile(script_dir, config_file);
    fid = fopen(config_path, 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonencode(config));
    fclose(fid);

    % Find Python with same fallback chain as interactive_winding_designer.m
    python_cmd = find_python_executable(script_dir);

    % Run Python script
    cmd = sprintf('%s "%s" "%s" 2>&1', python_cmd, py_script, config_file);
    fprintf('[API] Running: %s\n', cmd);
    [status, output] = system(cmd);
    fprintf('[API] Status: %d\n', status);

    if status ~= 0
        status_msg.has_error = true;
        status_msg.message = sprintf('Python API call failed: %s', strtrim(output));
        api_output = [];
        return;
    end

    % Load results JSON
    output_path = fullfile(script_dir, output_file);
    if ~exist(output_path, 'file')
        status_msg.has_error = true;
        status_msg.message = 'Python API did not produce output file';
        api_output = [];
        return;
    end

    fid = fopen(output_path, 'r', 'n', 'UTF-8');
    raw = fread(fid, '*char')';
    fclose(fid);

    try
        api_output = jsondecode(raw);
    catch err
        status_msg.has_error = true;
        status_msg.message = sprintf('Failed to parse API output: %s', err.message);
        api_output = [];
        return;
    end

    % Check for API errors
    if isfield(api_output, 'error') && ~isempty(api_output.error)
        status_msg.has_error = true;
        status_msg.message = api_output.error;
        return;
    end

    if isfield(api_output, 'status') && strcmp(api_output.status, 'error')
        status_msg.has_error = true;
        status_msg.message = api_output.message;
        return;
    end

end
```

### 3.7 Step 5: Parse API Results

**Function Signature**:
```matlab
function data = parse_openmagnetics_results(data, api_output)
    % Extract ranked designs from PyOpenMagnetics adviser output
    % Populate data.api_results with cores, wires, losses, temps, etc.
```

**PyOpenMagnetics API Output Format** (from examples):
```json
{
  "data": [
    {
      "mas": {
        "magnetic": {
          "core": {
            "functionalDescription": {
              "shape": {"name": "E 42/21/15"},
              "material": {"name": "3C95"},
              "gapping": [...]
            },
            "processedDescription": {
              "effectiveLength": 0.082,
              "effectiveArea": 4.9e-5,
              "effectivePermeability": 1800,
              "initialPermeability": 2900
            }
          },
          "coil": {
            "functionalDescription": [
              {
                "name": "Primary",
                "numberTurns": 45,
                "wireSize": "Round 0.5",
                "numberParallels": 1
              },
              {
                "name": "Secondary",
                "numberTurns": 90,
                ...
              }
            ]
          }
        },
        "inputs": {...},
        "outputs": {
          "coreLosses": 0.235,
          "windingLosses": 0.412,
          "totalLosses": 0.647,
          "coreTemperatureRise": 35,
          "hotspotTemperatureRise": 45,
          "magneticFluxDensityPeak": 0.285
        }
      },
      "scoring": 0.892,
      "scoringPerFilter": {
        "EFFICIENCY": 0.91,
        "DIMENSIONS": 0.85,
        "COST": 0.88
      }
    },
    ... (up to N results)
  ]
}
```

**Implementation**:
```matlab
function data = parse_openmagnetics_results(data, api_output)

    data.api_results = struct();
    data.api_results.designs = {};
    data.api_results.status = 'success';
    data.api_results.selected_idx = 1;  % Default to top recommendation

    % Extract designs list
    if isfield(api_output, 'data') && iscell(api_output.data)
        results = api_output.data;
    else
        data.api_results.status = 'error';
        data.api_results.message = 'Unexpected API output format';
        return;
    end

    % Process each recommendation
    for i = 1:length(results)
        result_item = results{i};

        % Initialize design struct
        design = struct();
        design.rank = i;
        design.score = result_item.scoring;
        design.scores = result_item.scoringPerFilter;  % {EFFICIENCY, DIMENSIONS, COST}

        % Extract from MAS structure
        if ~isfield(result_item, 'mas') || ~isfield(result_item.mas, 'magnetic')
            continue;  % Skip malformed results
        end

        mas = result_item.mas;
        magnetic = mas.magnetic;

        % --- Core information ---
        core = magnetic.core;
        design.core = struct();

        if isfield(core, 'functionalDescription')
            fd = core.functionalDescription;
            if isfield(fd, 'shape') && isfield(fd.shape, 'name')
                design.core.shape = fd.shape.name;
            end
            if isfield(fd, 'material') && isfield(fd.material, 'name')
                design.core.material = fd.material.name;
            end
            if isfield(fd, 'gapping')
                design.core.gapping = fd.gapping;
            end
        end

        if isfield(core, 'processedDescription')
            pd = core.processedDescription;
            design.core.effective_length_m = pd.effectiveLength;
            design.core.effective_area_m2 = pd.effectiveArea;
            design.core.effective_permeability = pd.effectivePermeability;
            design.core.initial_permeability = pd.initialPermeability;
        end

        % --- Coil (winding) information ---
        coil = magnetic.coil;
        design.windings = {};

        if isfield(coil, 'functionalDescription')
            windings = coil.functionalDescription;
            if iscell(windings)
                % Multiple windings
                for w_idx = 1:length(windings)
                    winding = windings{w_idx};
                    w_info = extract_winding_info(winding);
                    design.windings{w_idx} = w_info;
                end
            else
                % Single winding (Octave struct)
                w_info = extract_winding_info(windings);
                design.windings{1} = w_info;
            end
        end

        % --- Calculated parameters (magnetizing inductance, turns ratios) ---
        if isfield(mas, 'inputs') && isfield(mas.inputs, 'designRequirements')
            dr = mas.inputs.designRequirements;
            if isfield(dr, 'magnetizingInductance')
                design.lm_H = dr.magnetizingInductance.nominal;
            end
            if isfield(dr, 'turnsRatios') && ~isempty(dr.turnsRatios)
                design.turns_ratios = dr.turnsRatios;
            end
        end

        % --- Performance metrics (losses, temperatures) ---
        if isfield(mas, 'outputs')
            outputs = mas.outputs;
            design.losses = struct();
            design.losses.core_W = outputs.coreLosses;
            design.losses.winding_W = outputs.windingLosses;
            design.losses.total_W = outputs.totalLosses;
            design.losses.core_temp_rise_C = outputs.coreTemperatureRise;
            design.losses.hotspot_temp_rise_C = outputs.hotspotTemperatureRise;
            design.losses.B_peak_T = outputs.magneticFluxDensityPeak;
        end

        % --- Store design ---
        data.api_results.designs{i} = design;
    end

    fprintf('[API] Parsed %d designs from PyOpenMagnetics adviser\n', length(data.api_results.designs));

end

function w_info = extract_winding_info(winding)
    % Extract name, turns, wire size from winding struct
    w_info = struct();

    if isfield(winding, 'name')
        w_info.name = winding.name;
    end

    if isfield(winding, 'numberTurns')
        w_info.number_turns = winding.numberTurns;
    end

    if isfield(winding, 'numberParallels')
        w_info.number_parallels = winding.numberParallels;
    end

    if isfield(winding, 'wireSize') || isfield(winding, 'wire')
        wire_info = winding.wireSize;
        if isempty(wire_info) || ~isfield(winding, 'wireSize')
            if isfield(winding, 'wire')
                wire_info = winding.wire.name;
            end
        end
        w_info.wire = wire_info;
    end

    % Additional fields (copper area, insulation, etc.)
    if isfield(winding, 'conductingArea')
        w_info.conducting_area_m2 = winding.conductingArea;
    end

end
```

### 3.8 Step 6: Update GUI Display

```matlab
function update_api_results_display(data)
    % Show top 3-5 recommendations in GUI results panel
    % Allow user to click/select a design to load into interactive_winding_designer

    if data.api_results.status ~= "success"
        errordlg(data.api_results.message, 'API Error');
        return;
    end

    if isempty(data.api_results.designs)
        errordlg('No designs returned from PyOpenMagnetics adviser', 'No Results');
        return;
    end

    % Create results summary text
    lines = {};
    lines{end+1} = 'TOP RECOMMENDATIONS FROM PyOpenMagnetics ADVISER:';
    lines{end+1} = '';

    for i = 1:min(5, length(data.api_results.designs))
        des = data.api_results.designs{i};
        lines{end+1} = sprintf('Design #%d: %s / %s', i, des.core.shape, des.core.material);
        lines{end+1} = sprintf('  Score: %.3f (Eff: %.2f, Size: %.2f, Cost: %.2f)', ...
            des.score, des.scores.EFFICIENCY, des.scores.DIMENSIONS, des.scores.COST);

        % Winding info
        for w_idx = 1:length(des.windings)
            w = des.windings{w_idx};
            lines{end+1} = sprintf('  %s: %d turns, %s', ...
                w.name, w.number_turns, w.wire);
        end

        % Losses and temperatures
        lines{end+1} = sprintf('  Losses: Core=%.2f W, Winding=%.2f W, Total=%.2f W', ...
            des.losses.core_W, des.losses.winding_W, des.losses.total_W);
        lines{end+1} = sprintf('  Temps: Core rise=%.0f°C, Hotspot rise=%.0f°C', ...
            des.losses.core_temp_rise_C, des.losses.hotspot_temp_rise_C);
        lines{end+1} = sprintf('  B_peak: %.0f mT', des.losses.B_peak_T * 1000);
        lines{end+1} = '';
    end

    % Update text display in GUI
    set(data.txt_api_results, 'String', strjoin(lines, char(10)));

    % Enable "Select Design" buttons for each result
    for i = 1:min(5, length(data.api_results.designs))
        if isfield(data, sprintf('btn_select_design_%d', i))
            set(data.(sprintf('btn_select_design_%d', i)), 'Enable', 'on');
        end
    end

end
```

---

## 4. Python Bridge: `call_pyopenmagnetics_api.py` [NEW PYTHON SCRIPT]

**Purpose**: Wrapper around PyOpenMagnetics API functions
**Called from**: MATLAB via `system()` command
**Input**: JSON config with MAS inputs, settings
**Output**: JSON with ranked designs from adviser

### 4.1 File Structure

```python
#!/usr/bin/env python3
"""
PyOpenMagnetics API Bridge for MATLAB topology_wizard

Modes:
  calculate_advised_magnetics - Run full adviser workflow

Usage:
    python call_pyopenmagnetics_api.py config.json

Input JSON (call_api_config.json):
  {
    "mode": "calculate_advised_magnetics",
    "inputs": { ... MAS JSON ... },
    "settings": {
      "max_results": 5,
      "core_mode": "STANDARD_CORES",
      "weights": { "EFFICIENCY": 1.0, "DIMENSIONS": 0.5, "COST": 0.3 }
    },
    "output_file": "call_api_results.json"
  }

Output JSON (call_api_results.json):
  {
    "status": "OK|ERROR",
    "error": "error message if status=ERROR",
    "data": [
      {
        "mas": { ... full MAS with magnetic, inputs, outputs ... },
        "scoring": 0.892,
        "scoringPerFilter": { "EFFICIENCY": 0.91, ... }
      },
      ...
    ]
  }
"""

import json
import sys
import traceback

try:
    import PyOpenMagnetics as pm
except Exception as exc:
    print(f"[API] ImportError: {exc}", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) < 2:
        print("[API] Usage: python call_pyopenmagnetics_api.py config.json", file=sys.stderr)
        sys.exit(1)

    config_file = sys.argv[1]

    try:
        with open(config_file, 'r', encoding='utf-8') as f:
            config = json.load(f)
    except Exception as e:
        output = {
            "status": "ERROR",
            "error": f"Failed to read config: {e}"
        }
        print(json.dumps(output))
        sys.exit(1)

    mode = config.get("mode", "calculate_advised_magnetics")

    try:
        if mode == "calculate_advised_magnetics":
            result = handle_calculate_advised_magnetics(config)
        else:
            result = {
                "status": "ERROR",
                "error": f"Unknown mode: {mode}"
            }
    except Exception as e:
        result = {
            "status": "ERROR",
            "error": f"{type(e).__name__}: {str(e)}",
            "traceback": traceback.format_exc()
        }
        print(f"[API] Exception: {e}", file=sys.stderr)

    # Write output
    output_file = config.get("output_file", "call_api_results.json")
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(result, f, indent=2)
        print(f"[API] Results written to {output_file}")
    except Exception as e:
        print(f"[API] Failed to write output: {e}", file=sys.stderr)
        sys.exit(1)


def handle_calculate_advised_magnetics(config):
    """
    Main adviser workflow:
    1. Load inputs from config
    2. Call pm.process_inputs(inputs) to add harmonics
    3. Call pm.calculate_advised_magnetics(inputs, max_results, core_mode)
    4. Return ranked list of {mas, scoring, scoringPerFilter}
    """

    inputs = config.get("inputs", {})
    settings = config.get("settings", {})

    max_results = int(settings.get("max_results", 5))
    core_mode = settings.get("core_mode", "STANDARD_CORES")

    print(f"[API] Processing inputs...", file=sys.stderr)

    # Step 1: Process inputs (adds harmonics for loss calculations)
    try:
        processed = pm.process_inputs(inputs)
    except Exception as e:
        return {
            "status": "ERROR",
            "error": f"pm.process_inputs() failed: {e}"
        }

    print(f"[API] Calling calculate_advised_magnetics(max_results={max_results}, core_mode={core_mode})...",
          file=sys.stderr)

    # Step 2: Get design recommendations
    try:
        result = pm.calculate_advised_magnetics(processed, max_results, core_mode)
    except Exception as e:
        return {
            "status": "ERROR",
            "error": f"pm.calculate_advised_magnetics() failed: {e}"
        }

    # Step 3: Extract and validate results
    if isinstance(result, dict) and "data" in result:
        magnetics = result["data"]
    elif isinstance(result, list):
        magnetics = result
    else:
        magnetics = result

    if isinstance(magnetics, str):
        # Error string returned
        return {
            "status": "ERROR",
            "error": magnetics
        }

    if not isinstance(magnetics, list):
        magnetics = [magnetics]

    print(f"[API] Received {len(magnetics)} designs", file=sys.stderr)

    # Package results for MATLAB
    output_data = []
    for i, item in enumerate(magnetics):
        # Each item should have 'mas' and 'scoring' keys
        if isinstance(item, dict):
            output_data.append({
                "mas": item.get("mas", item),  # Full MAS object
                "scoring": item.get("scoring", 0.0),
                "scoringPerFilter": item.get("scoringPerFilter", {})
            })

    return {
        "status": "OK",
        "data": output_data
    }


if __name__ == "__main__":
    main()
```

---

## 5. Error Handling & Fallback Strategy

### 5.1 Python Executable Discovery

**Same chain as `interactive_winding_designer.m`** (lines 4345-4393):

```matlab
function python_cmd = find_python_executable(script_dir)
    % Find Python 3 with PyOpenMagnetics installed
    % Fallback chain:
    %  1. venv in project (.venv/Scripts/python.exe)
    %  2. 'python' in PATH
    %  3. 'py' launcher (Windows)
    %  4. Manual search via 'where python' (skip Octave bundled)

    % Try 1: Virtual environment
    venv_python = fullfile(script_dir, '.venv', 'Scripts', 'python.exe');
    if exist(venv_python, 'file')
        python_cmd = ['"' strrep(venv_python, '\', '/') '"'];
        fprintf('[API] Using venv python: %s\n', python_cmd);
        return;
    end

    % Try 2: Direct 'python' command
    [status, output] = system('python --version 2>&1');
    if status == 0
        python_cmd = 'python';
        fprintf('[API] Using system python\n');
        return;
    end

    % Try 3: 'py' launcher (Windows)
    if ispc
        [status, output] = system('py --version 2>&1');
        if status == 0
            python_cmd = 'py';
            fprintf('[API] Using ''py'' launcher\n');
            return;
        end
    end

    % Try 4: Manual search via 'where python'
    if ispc
        [status, py_paths_str] = system('where python');
        py_paths = strsplit(strtrim(py_paths_str), char(10));

        for i = 1:length(py_paths)
            p = strtrim(py_paths{i});
            if isempty(p) || contains(lower(p), 'octave') || contains(lower(p), 'usr\bin')
                continue;
            end

            p_forward = strrep(p, '\', '/');
            [status_alt, output_alt] = system(sprintf('"%s" --version 2>&1', p_forward));
            if status_alt == 0
                python_cmd = ['"' p_forward '"'];
                fprintf('[API] Using alternative python: %s\n', p_forward);
                return;
            end
        end
    end

    % Fallback: assume 'python' is in PATH
    python_cmd = 'python';
    fprintf('[API] WARNING: Could not verify python executable, using fallback ''python''\n');
end
```

### 5.2 API Error Messages

**When PyOpenMagnetics fails** (e.g., invalid magnetizing inductance, unrealistic requirements):

```matlab
% In call_pyopenmagnetics_api() error handling:

if status ~= 0
    % Parse Python stderr for specific errors
    if contains(output, 'magnetizingInductance')
        status_msg.message = ...
            'Invalid magnetizing inductance: check topology equations';
    elseif contains(output, 'turnsRatios')
        status_msg.message = ...
            'Invalid turns ratio: may violate topology constraints';
    elseif contains(output, 'ImportError') || contains(output, 'ModuleNotFoundError')
        status_msg.message = ...
            'PyOpenMagnetics not installed: run export_openmagnetics_database.py';
    else
        status_msg.message = output;  % Raw error
    end
    status_msg.has_error = true;
    return;
end
```

---

## 6. Integration with `interactive_winding_designer.m`

### 6.1 After API Returns Designs

```matlab
% In topology_wizard.m, after parse_openmagnetics_results():

function cb_select_design(design_idx)
    % User clicked "Select Design #N" button

    fig = gcbf();
    data = guidata(fig);

    if design_idx > length(data.api_results.designs)
        errordlg('Invalid design index', 'Error');
        return;
    end

    design = data.api_results.designs{design_idx};

    % Build design_spec struct to pass to interactive_winding_designer
    design_spec = build_design_spec_from_api_result(data, design);

    % Save current topology_wizard state (optional, for back button)
    save_topology_state(data);

    % Launch interactive_winding_designer with design_spec
    close(data.fig);  % Close topology_wizard
    interactive_winding_designer(design_spec);
end

function design_spec = build_design_spec_from_api_result(data, design)
    % Convert API result into format expected by interactive_winding_designer

    design_spec = struct();

    % From converter specs
    design_spec.vin_min = data.converter.vin_min;
    design_spec.vin_max = data.converter.vin_max;
    design_spec.vin_nom = data.converter.vin_nom;
    design_spec.vout = data.converter.vout;
    design_spec.iout = data.converter.iout;
    design_spec.fsw_khz = data.converter.fsw_khz;

    % From API recommendation
    design_spec.core_shape = design.core.shape;
    design_spec.core_material = design.core.material;
    design_spec.gapping = design.core.gapping;

    % Winding info
    design_spec.windings = design.windings;
    design_spec.lm_H = design.lm_H;

    % Topology for reference
    design_spec.topology = data.topology;
    design_spec.design_mode = data.design_mode;

    % API results for comparison
    design_spec.api_rank = design.rank;
    design_spec.api_score = design.score;
    design_spec.api_losses = design.losses;

end
```

### 6.2 Display Results in GUI

Add to topology_wizard GUI (after "Compute Requirements" button):

```matlab
% In build_gui() function, add results panel:

% Results panel (initially hidden until API called)
data.panel_api_results = uipanel('Parent', fig, ...
    'Position', [0.02 0.10 0.96 0.35], ...
    'Title', 'PyOpenMagnetics Recommendations', ...
    'FontSize', 10, 'FontWeight', 'bold', ...
    'Visible', 'off');

data.txt_api_results = uicontrol('Parent', data.panel_api_results, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.02 0.05 0.96 0.90], ...
    'HorizontalAlignment', 'left', ...
    'VerticalAlignment', 'top', ...
    'FontSize', 9, 'FontName', 'monospace', ...
    'String', 'Results will appear here...');

% Select design buttons (show 1-5 top recommendations)
for i = 1:5
    btn_y = 0.95 - (i-1) * 0.15;
    data.(sprintf('btn_select_design_%d', i)) = uicontrol('Parent', data.panel_api_results, ...
        'Style', 'pushbutton', ...
        'String', sprintf('Select Design #%d', i), ...
        'Units', 'normalized', ...
        'Position', [0.72 btn_y 0.22 0.10], ...
        'FontSize', 9, ...
        'Enable', 'off', ...
        'Callback', {@cb_select_design_wrapper, i});
end

function cb_select_design_wrapper(src, ~, design_idx)
    fig = gcbf();
    data = guidata(fig);
    cb_select_design(design_idx);
    guidata(fig, data);
end
```

---

## 7. Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         topology_wizard.m                       │
│                                                                   │
│  GUI INPUTS:                        COMPUTED FIELDS:            │
│  • Vin (min/nom/max)       ──┐     • Lm, turns_ratio            │
│  • Vout, Iout              ├──> compute_requirements()        │
│  • Fsw, Efficiency         ├──> operating_points[]            │
│  • Vd, Ripple %            │     • i_pri, i_sec, i_mag         │
│  • Topology, Mode          │     • B_peak, duty_cycles        │
│  • Insulation specs        ──┘                                  │
│                                                                   │
│  ┌─────────────────────────────────────────────────────┐        │
│  │ COMPUTE BUTTON (cb_compute_topology)               │        │
│  │                                                     │        │
│  │ request_openmagnetics_computation(data)            │        │
│  │   ├─ validate_converter_specs(data.converter)      │        │
│  │   ├─ compute_operating_points(data) ──────────┐   │        │
│  │   ├─ build_mas_structure(...) ────────────────┼──>│        │
│  │   │                                            │   │        │
│  │   └─ call_pyopenmagnetics_api(mas_inputs) ────┼──>│        │
│  └─────────────────────────────────────────────────────┘        │
│          ↓                                              ↓        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │        MATLAB ↔ PYTHON BRIDGE                           │   │
│  │                                                          │   │
│  │  om_topology_config.json ──[write]─→ call_api_config.json
│  │                                 Python Script:          │   │
│  │                         call_pyopenmagnetics_api.py    │   │
│  │                                                          │   │
│  │  call_api_results.json ←─[read]─ om_api_results.json   │   │
│  └──────────────────────────────────────────────────────────┘   │
│          ↓                                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │     PYTHON: PyOpenMagnetics API Adviser                 │   │
│  │                                                          │   │
│  │  inputs = MAS JSON (from MATLAB)                        │   │
│  │                                                          │   │
│  │  pm.process_inputs(inputs)                             │   │
│  │    → adds harmonics, processes excitations             │   │
│  │                                                          │   │
│  │  pm.calculate_advised_magnetics(inputs, 5, "STANDARD") │   │
│  │    → Core search + Winding design + Loss calc           │   │
│  │    → Returns: {data: [{mas, scoring, scoringPerFilter}]}
│  │                                                          │   │
│  │  Result: Top 5 cores with full winding designs        │   │
│  │          (turns, wire sizes, losses, temps)            │   │
│  └──────────────────────────────────────────────────────────┘   │
│          ↓                                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  MATLAB: parse_openmagnetics_results()                  │   │
│  │                                                          │   │
│  │  Extract from each {mas}:                              │   │
│  │   • Core: shape, material, gapping                     │   │
│  │   • Coil: windings (name, turns, wire)                │   │
│  │   • Outputs: core_loss, winding_loss, temps, B_peak   │   │
│  │                                                          │   │
│  │  Populate data.api_results.designs[] ───→ GUI display   │   │
│  └──────────────────────────────────────────────────────────┘   │
│          ↓                                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  GUI: Display Top 5 Recommendations                    │   │
│  │                                                          │   │
│  │  For each design:                                      │   │
│  │   • [Design #1 | Score: 0.892 | Select] ───┐          │   │
│  │   • Core: E 42/21/15 / 3C95                  │          │   │
│  │   • Primary: 45 turns, Round 0.5            │          │   │
│  │   • Losses: Core=0.24W Winding=0.41W        │          │   │
│  │   • Temps: ΔT_core=35°C, ΔT_hs=45°C         │          │   │
│  │   • B_peak: 285 mT                           │          │   │
│  │                                              │          │   │
│  │   [Design #2 | Score: 0.881 | Select] ─────┤          │   │
│  │   ... (3-5 more)                            │          │   │
│  │                                              │          │   │
│  │   User clicks "Select Design #1"  ──────────┘          │   │
│  └──────────────────────────────────────────────────────────┘   │
│          ↓                                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  build_design_spec_from_api_result(design)             │   │
│  │                                                          │   │
│  │  design_spec = {                                        │   │
│  │    vin_min, vin_max, vout, iout, fsw_khz,            │   │
│  │    core_shape, core_material, gapping,                │   │
│  │    windings[], lm_H, topology,                         │   │
│  │    api_rank, api_score, api_losses                    │   │
│  │  }                                                      │   │
│  └──────────────────────────────────────────────────────────┘   │
│          ↓                                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  close(fig); interactive_winding_designer(design_spec) │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. Implementation Checklist

### Phase 1: Core Functions (MATLAB)
- [ ] `build_mas_structure()` — Map topology GUI params → MAS JSON
- [ ] `request_openmagnetics_computation()` — Main entry point from callback
- [ ] `call_pyopenmagnetics_api()` — Python wrapper and result loading
- [ ] `parse_openmagnetics_results()` — Extract designs, populate GUI
- [ ] `find_python_executable()` — Same fallback chain as excitation

### Phase 2: GUI Integration (MATLAB)
- [ ] Add results panel to topology_wizard.m GUI
- [ ] Add "Select Design #N" buttons
- [ ] Wire callbacks to `build_design_spec_from_api_result()`
- [ ] Test flow: Compute → Results → Select → Launch designer

### Phase 3: Python Bridge
- [ ] Create `call_pyopenmagnetics_api.py`
- [ ] Implement `handle_calculate_advised_magnetics()`
- [ ] Test: JSON I/O, API calls, error handling

### Phase 4: Topology-Specific Operating Points
- [ ] Forward topologies: Rectangular voltage, duty cycles
- [ ] Buck/Boost: Triangular current, single operating point
- [ ] Flyback: Primary triangular, secondary off-time
- [ ] Isolated Buck-Boost: Energy storage path

### Phase 5: Testing & Validation
- [ ] Test each topology (2-switch forward, flyback, buck)
- [ ] Test multi-output topologies
- [ ] Test error cases (invalid Lm, unrealistic specs)
- [ ] Verify loss predictions vs. interactive designer
- [ ] Test Python fallback chain (venv, py, manual search)

---

## 9. Known Challenges & Mitigations

### Challenge 1: Operating Point Specification
**Problem**: Each topology has different waveform shapes (rectangular, triangular, trapezoidal). Wrong waveforms → wrong losses.

**Mitigation**:
- Encode topology-specific waveform generators in MATLAB
- Reference PyOpenMagnetics examples (flyback_design.py, buck_inductor.py)
- Validate B_peak results: if Bpeak > 0.35 T (saturation risk), recompute Lm upward

### Challenge 2: Multi-Output Handling
**Problem**: Isolated topologies can have 1-4 outputs; MAS schema expects N secondaries.

**Mitigation**:
- Accept `data.n_outputs` from GUI
- In `build_mas_structure()`, create N secondary excitations with independent currents
- Each secondary's current based on its Vout, Iout from converter specs

### Challenge 3: Insulation Standard Mapping
**Problem**: MATLAB uses IEC 60664-1, 61558-1, etc.; PyOpenMagnetics expects abbreviated keys (OVC-II, GroupII).

**Mitigation**:
- Create mapping containers in `build_mas_structure()` (as shown in section 3.5)
- Test against PyOpenMagnetics test suite (test_inputs.py)

### Challenge 4: Topology Equations Removal
**Problem**: Existing `generate_om_topology.py` hand-codes equations; need to redirect API users.

**Mitigation**:
- Keep `generate_om_topology.py` for backward compatibility (existing workflows)
- New `request_openmagnetics_computation()` uses API directly
- Eventually deprecate `generate_om_topology.py` in favor of API approach

### Challenge 5: API Result Interpretation
**Problem**: PyOpenMagnetics returns full MAS with winding layout already computed; interactive_winding_designer expects user to do layout.

**Mitigation**:
- Use API result as **starting point**, not final design
- Pre-populate designer with API core, material, gapping, initial winding counts
- Allow user to adjust layers, parallelism, turn distribution
- Re-run PEEC simulation with user's layout

---

## 10. Future Enhancements

1. **Weights-based adviser**: Let user adjust cost/efficiency/size trade-offs
2. **Constraint-based search**: Filter by max dimensions, weight, cost target
3. **Core availability**: Search only in-stock cores (AVAILABLE_CORES mode)
4. **Material grades**: Filter by thermal class (Class B, F, H)
5. **Wire family preference**: Auto-select litz for high-frequency, round for cost
6. **MAS export/import**: Save/load designs for collaboration
7. **Comparison tool**: Side-by-side loss/temp/cost comparison of top 5 designs

---

## 11. Appendix: Example MAS JSON (Two-Switch Forward)

```json
{
  "designRequirements": {
    "topology": "two-switch-forward",
    "magnetizingInductance": {
      "nominal": 2.5e-4,
      "minimum": 2.25e-4,
      "maximum": 2.75e-4
    },
    "turnsRatios": [
      {
        "nominal": 0.5,
        "minimum": 0.45,
        "maximum": 0.55
      }
    ],
    "insulation": {
      "insulationType": "Functional",
      "pollutionDegree": "P2",
      "overvoltageCategory": "OVC-II",
      "cti": "GroupII"
    }
  },
  "operatingPoints": [
    {
      "name": "Low Line (100V)",
      "conditions": {
        "ambientTemperature": 25,
        "coolingType": "Natural"
      },
      "excitationsPerWinding": [
        {
          "name": "Primary",
          "frequency": 200000,
          "current": {
            "processed": {
              "label": "Rectangular",
              "peakToPeak": 10.8,
              "offset": 5.4,
              "dutyCycle": 0.45
            }
          },
          "voltage": {
            "processed": {
              "label": "Rectangular",
              "peakToPeak": 150,
              "offset": 75,
              "dutyCycle": 0.45
            }
          }
        },
        {
          "name": "Secondary",
          "frequency": 200000,
          "current": {
            "processed": {
              "label": "Rectangular",
              "peakToPeak": 21.6,
              "offset": 10.8,
              "dutyCycle": 0.45
            }
          },
          "voltage": {
            "processed": {
              "label": "Rectangular",
              "peakToPeak": 10,
              "offset": 5,
              "dutyCycle": 0.45
            }
          }
        }
      ]
    },
    {
      "name": "High Line (190V)",
      "conditions": {
        "ambientTemperature": 25,
        "coolingType": "Natural"
      },
      "excitationsPerWinding": [
        {
          "name": "Primary",
          "frequency": 200000,
          "current": {
            "processed": {
              "label": "Rectangular",
              "peakToPeak": 5.7,
              "offset": 2.85,
              "dutyCycle": 0.238
            }
          },
          "voltage": {
            "processed": {
              "label": "Rectangular",
              "peakToPeak": 285,
              "offset": 142.5,
              "dutyCycle": 0.238
            }
          }
        },
        {
          "name": "Secondary",
          "frequency": 200000,
          "current": {
            "processed": {
              "label": "Rectangular",
              "peakToPeak": 11.4,
              "offset": 5.7,
              "dutyCycle": 0.238
            }
          },
          "voltage": {
            "processed": {
              "label": "Rectangular",
              "peakToPeak": 10,
              "offset": 5,
              "dutyCycle": 0.238
            }
          }
        }
      ]
    }
  ]
}
```

---

## 12. Summary

This design provides a **complete blueprint** for replacing hand-coded topology equations with direct PyOpenMagnetics API calls:

1. **Input Collection** (request_openmagnetics_computation): Gathers topology-specific operating points and builds MAS JSON
2. **API Call** (call_pyopenmagnetics_api.py): Processes inputs, runs adviser, returns ranked designs
3. **Result Parsing** (parse_openmagnetics_results): Extracts cores, wires, losses, temps from API output
4. **GUI Integration**: Display top 5 recommendations, allow user selection
5. **Downstream**: Pass selected design to interactive_winding_designer as starting point

**Key Benefits**:
- Physics-based (Faraday's law, reluctance networks)
- No equation duplication
- Full material/wire database access
- Automatic winding design
- Multi-criteria optimization (efficiency, size, cost)

