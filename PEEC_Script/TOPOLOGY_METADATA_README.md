# Topology Metadata System

## Overview

The topology metadata system provides a centralized registry for all 9 converter topologies and their associated field requirements, constraints, and display properties. This system is used to:

- Define topology-specific field requirements
- Manage field visibility and constraints
- Generate GUI controls dynamically
- Map fields to MAS JSON structure
- Validate user inputs

## File Structure

### Core Files

#### 1. `topology_metadata.m` (387 lines)
**Main centralized registry** containing all topology and field definitions.

```matlab
topology_defs = topology_metadata();
% Returns struct with:
%   .TOPOLOGY_DEFINITIONS - struct with all 9 topologies
%   .FIELD_METADATA - struct with all field definitions
```

Uses persistent caching to load definitions only once per MATLAB session.

#### 2. `get_topology_metadata.m` (50 lines)
**Get complete metadata for a specific topology**

```matlab
topo_meta = get_topology_metadata('two_switch_forward');
% Returns:
%   .display_name - 'Two-Switch Forward'
%   .mas_filename - 'forward.json'
%   .output_type - 'multi'
%   .required_fields - {'inputVoltage_minimum', 'inputVoltage_maximum', ...}
%   .optional_fields - {'inputVoltage_nominal', 'efficiency', ...}
```

#### 3. `get_field_metadata.m` (51 lines)
**Get metadata for a specific field**

```matlab
field_meta = get_field_metadata('diodeVoltageDrop');
% Returns:
%   .label - 'Diode Voltage Drop'
%   .unit - 'V'
%   .data_type - 'number'
%   .default - 0.7
%   .min - 0.3
%   .max - 1.5
%   .tooltip - 'Forward voltage drop of output diode'
%   .mas_path - 'inputs.designRequirements.diodeVoltageDrop'
%   .optional - false
```

#### 4. `is_field_required.m` (50 lines)
**Check if a field is required for a given topology**

```matlab
required = is_field_required('flyback', 'efficiency');
% Returns: true (required for flyback)

required = is_field_required('buck', 'efficiency');
% Returns: false (optional for buck)
```

#### 5. `get_visible_fields_for_topology.m` (48 lines)
**Get all fields (required and optional) for a topology**

```matlab
[req, opt] = get_visible_fields_for_topology('two_switch_forward');
% req = {'inputVoltage_minimum', 'inputVoltage_maximum', ...}
% opt = {'inputVoltage_nominal', 'efficiency', ...}
```

#### 6. `get_topology_output_type.m` (45 lines)
**Check if topology supports single or multiple outputs**

```matlab
output_type = get_topology_output_type('buck');
% Returns: 'single'

output_type = get_topology_output_type('flyback');
% Returns: 'multi'
```

### Test File

#### `test_topology_metadata.m`
Comprehensive test script verifying all functions, field completeness, error handling, etc.

## Topology Definitions

### Output Types

| Topology | Output Type | MAS Filename | Description |
|----------|------------|--------------|-------------|
| two_switch_forward | multi | forward.json | Forward converter with two switches |
| single_switch_forward | multi | forward.json | Forward converter with single switch + demagnetization winding |
| active_clamp_forward | multi | forward.json | Forward converter with active clamping |
| flyback | multi | flyback.json | Transformer-isolated topologies with flyback operation |
| push_pull | multi | pushPull.json | Push-pull forward topology |
| buck | single | buck.json | Step-down non-isolated converter |
| boost | single | boost.json | Step-up non-isolated converter |
| isolated_buck | multi | isolatedBuck.json | Transformer-isolated buck converter |
| isolated_buck_boost | multi | isolatedBuckBoost.json | Transformer-isolated buck-boost converter |

### Required vs Optional Fields

#### Multi-Output Forward Topologies
(two_switch_forward, single_switch_forward, active_clamp_forward)

**Required:**
- inputVoltage_minimum
- inputVoltage_maximum
- outputVoltages_0
- outputCurrents_0
- switchingFrequency
- diodeVoltageDrop
- currentRippleRatio

**Optional:**
- inputVoltage_nominal
- efficiency
- maximumSwitchCurrent
- maximumDutyCycle

#### Flyback

**Required:**
- inputVoltage_minimum
- inputVoltage_maximum
- outputVoltages_0
- outputCurrents_0
- switchingFrequency
- diodeVoltageDrop
- currentRippleRatio
- efficiency (required for flyback!)

**Optional:**
- inputVoltage_nominal
- maximumDutyCycle
- maximumDrainSourceVoltage
- maximumSwitchCurrent

#### Push-Pull

**Required:**
- inputVoltage_minimum
- inputVoltage_maximum
- outputVoltages_0
- outputCurrents_0
- switchingFrequency
- diodeVoltageDrop
- currentRippleRatio

**Optional:**
- inputVoltage_nominal
- efficiency
- dutyCycle
- maximumSwitchCurrent
- maximumDrainSourceVoltage

#### Buck / Boost

**Required:**
- inputVoltage_minimum
- inputVoltage_maximum
- outputVoltage (single, not indexed)
- outputCurrent (single, not indexed)
- switchingFrequency
- diodeVoltageDrop

**Optional:**
- currentRippleRatio
- maximumSwitchCurrent
- efficiency
- inputVoltage_nominal

#### Isolated Buck / Isolated Buck-Boost

Same as bucket but multi-output variant:

**Required:**
- inputVoltage_minimum
- inputVoltage_maximum
- outputVoltages_0
- outputCurrents_0
- switchingFrequency
- diodeVoltageDrop

**Optional:**
- currentRippleRatio
- maximumSwitchCurrent
- efficiency
- inputVoltage_nominal

## Field Definitions

### Input Voltage Fields

| Field Name | Label | Unit | Default | Min | Max | Optional |
|------------|-------|------|---------|-----|-----|----------|
| inputVoltage_minimum | Input Voltage Min | V | 100 | 5 | 1000 | No |
| inputVoltage_maximum | Input Voltage Max | V | 190 | 5 | 1000 | No |
| inputVoltage_nominal | Input Voltage Nom. | V | [] | 5 | 1000 | Yes |

### Output Fields (Indexed)

Multi-output topologies use indexed fields: `_0`, `_1`, `_2`, `_3`
Single-output topologies (buck, boost) use non-indexed fields.

| Field Name | Label | Unit | Default | Min | Max | Optional |
|------------|-------|------|---------|-----|-----|----------|
| outputVoltages_0 | Output 1 Voltage | V | 5 | 0.1 | 1000 | No |
| outputVoltages_1 | Output 2 Voltage | V | 5 | 0.1 | 1000 | Yes |
| outputVoltages_2 | Output 3 Voltage | V | 5 | 0.1 | 1000 | Yes |
| outputVoltages_3 | Output 4 Voltage | V | 5 | 0.1 | 1000 | Yes |
| outputCurrents_0 | Output 1 Current | A | 5 | 0.1 | 1000 | No |
| outputCurrents_1 | Output 2 Current | A | 5 | 0.1 | 1000 | Yes |
| outputCurrents_2 | Output 3 Current | A | 5 | 0.1 | 1000 | Yes |
| outputCurrents_3 | Output 4 Current | A | 5 | 0.1 | 1000 | Yes |
| outputVoltage | Output Voltage | V | 5 | 0.1 | 1000 | No |
| outputCurrent | Output Current | A | 5 | 0.1 | 1000 | No |

### Control Parameters

| Field Name | Label | Unit | Default | Min | Max | Optional |
|------------|-------|------|---------|-----|-----|----------|
| switchingFrequency | Switching Frequency | kHz | 200 | 10 | 10000 | No |
| diodeVoltageDrop | Diode Voltage Drop | V | 0.7 | 0.3 | 1.5 | No |
| currentRippleRatio | Current Ripple % | % | 30 | 5 | 100 | No |
| dutyCycle | Duty Cycle | % | [] | 1 | 99 | Yes |
| maximumDutyCycle | Max Duty Cycle | % | [] | 1 | 99 | Yes |

### Constraints

| Field Name | Label | Unit | Default | Min | Max | Optional |
|------------|-------|------|---------|-----|-----|----------|
| efficiency | Efficiency | % | 90 | 50 | 99 | Yes |
| maximumSwitchCurrent | Max Switch Current | A | [] | 0.1 | 1000 | Yes |
| maximumDrainSourceVoltage | Max Drain-Source Voltage | V | [] | 1 | 10000 | Yes |

## MAS Path Mapping

Each field includes a `mas_path` property that specifies where the field maps in the MAS JSON structure:

### Design Requirements
```
inputs.designRequirements.inputVoltage.minimum
inputs.designRequirements.inputVoltage.maximum
inputs.designRequirements.inputVoltage.nominal
inputs.designRequirements.outputVoltage
inputs.designRequirements.outputCurrent
inputs.designRequirements.diodeVoltageDrop
inputs.designRequirements.currentRippleRatio
inputs.designRequirements.efficiency
inputs.designRequirements.maximumSwitchCurrent
inputs.designRequirements.maximumDutyCycle
inputs.designRequirements.dutyCycle
inputs.designRequirements.maximumDrainSourceVoltage
```

### Operating Points
```
inputs.operatingPoints(1).switchingFrequency
inputs.operatingPoints(1).outputVoltages(1)
inputs.operatingPoints(1).outputVoltages(2)
inputs.operatingPoints(1).outputVoltages(3)
inputs.operatingPoints(1).outputVoltages(4)
inputs.operatingPoints(1).outputCurrents(1)
inputs.operatingPoints(1).outputCurrents(2)
inputs.operatingPoints(1).outputCurrents(3)
inputs.operatingPoints(1).outputCurrents(4)
```

## Usage Examples

### Example 1: Build a Form for Two-Switch Forward

```matlab
% Get topology definition
topo = get_topology_metadata('two_switch_forward');
fprintf('Building form for: %s\n', topo.display_name);

% Get required and optional fields
[required, optional] = get_visible_fields_for_topology('two_switch_forward');

% Build required fields section
fprintf('Required fields:\n');
for i = 1:length(required)
    field_name = required{i};
    field_meta = get_field_metadata(field_name);
    fprintf('  %s [%s]: default = %g, range [%g, %g]\n', ...
        field_meta.label, field_meta.unit, ...
        field_meta.default, field_meta.min, field_meta.max);
end

% Build optional fields section
fprintf('Optional fields:\n');
for i = 1:length(optional)
    field_name = optional{i};
    field_meta = get_field_metadata(field_name);
    fprintf('  %s [%s]: default = %g, range [%g, %g]\n', ...
        field_meta.label, field_meta.unit, ...
        field_meta.default, field_meta.min, field_meta.max);
end
```

### Example 2: Check Output Type for Multi-Output Support

```matlab
topology_key = 'buck';
output_type = get_topology_output_type(topology_key);

if strcmp(output_type, 'multi')
    % Support up to 4 outputs
    n_outputs = 4;
else
    % Single output only
    n_outputs = 1;
end

fprintf('Topology %s supports %d output(s)\n', topology_key, n_outputs);
```

### Example 3: Validate Field Requirements

```matlab
topology_key = 'flyback';
user_fields = {'inputVoltage_minimum', 'inputVoltage_maximum', ...
               'outputVoltages_0', 'outputCurrents_0', ...
               'switchingFrequency', 'diodeVoltageDrop', ...
               'currentRippleRatio'};

[required, optional] = get_visible_fields_for_topology(topology_key);

for i = 1:length(required)
    field = required{i};
    if ~any(strcmp(user_fields, field))
        fprintf('ERROR: Missing required field: %s\n', field);
    end
end

% Check if efficiency is provided (required for flyback)
if any(strcmp(user_fields, 'efficiency'))
    fprintf('Good: Efficiency field provided\n');
else
    fprintf('WARNING: Efficiency is required for flyback topology\n');
end
```

## Performance

All getter functions use persistent caching:
- First call to `get_topology_metadata()`, `get_field_metadata()`, etc. initializes cache
- Subsequent calls return from cache in O(1) time
- Single `topology_metadata()` call per MATLAB session to build definitions

## Error Handling

All functions validate inputs and throw informative errors:

```matlab
try
    topo = get_topology_metadata('invalid_topology');
catch ME
    % Error: Unknown topology "invalid_topology". Valid options: ...
end

try
    field = get_field_metadata('invalid_field');
catch ME
    % Error: Unknown field "invalid_field". Valid options: ...
end
```

## Integration with GUI

The topology wizard should use these functions to:

1. **Populate topology dropdown**
   ```matlab
   topos = get_all_topology_keys();
   for i = 1:length(topos)
       topo = get_topology_metadata(topos{i});
       % Add to dropdown with display_name
   end
   ```

2. **Show/hide fields based on topology**
   ```matlab
   selected_topology = get(dropdown, 'Value');
   [req, opt] = get_visible_fields_for_topology(selected_topology);
   % Create UI controls for req and opt fields
   ```

3. **Update field constraints**
   ```matlab
   field_name = 'switchingFrequency';
   meta = get_field_metadata(field_name);
   set(slider, 'Min', meta.min, 'Max', meta.max);
   set(edit, 'String', num2str(meta.default));
   ```

4. **Check output type**
   ```matlab
   output_type = get_topology_output_type(topology);
   if strcmp(output_type, 'multi')
       % Show N-outputs spinner
   else
       % Hide N-outputs spinner
   end
   ```

## Extension Points

To add a new topology:

1. Add entry to `TOPOLOGY_DEFINITIONS` in `topology_metadata.m`
2. Add required/optional fields to the definition
3. Ensure all referenced fields exist in `FIELD_METADATA`
4. Test with `test_topology_metadata.m`

To add a new field:

1. Add entry to `FIELD_METADATA` in `topology_metadata.m`
2. Include all required metadata: label, unit, data_type, default, min/max, tooltip, mas_path, optional
3. Add field to appropriate topology `required_fields` or `optional_fields`
4. Test with `test_topology_metadata.m`

## Summary

The topology metadata system provides a clean, extensible way to manage converter topology definitions and field requirements. By centralizing this information, the system ensures consistency across the GUI, MAS generation, and advisor integration.
