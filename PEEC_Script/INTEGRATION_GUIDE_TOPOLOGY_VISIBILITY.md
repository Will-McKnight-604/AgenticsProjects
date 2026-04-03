# Dynamic Field Visibility System - Integration Guide

## Overview

This guide explains how to integrate the topology field visibility system into `topology_wizard.m`. The system enables dynamic show/hide of GUI fields based on the selected topology and a metadata-driven architecture.

## Files

- **topology_field_visibility_system.m** - Core functions implementing the visibility system
- **topology_wizard.m** - Main GUI file (to be updated)

## Key Functions

### 1. `get_topology_metadata(topology_key)`
Returns metadata struct for a topology, including:
- Display name
- Category (forward, flyback, buck, boost, etc.)
- Is isolated (true/false)
- Min/max number of outputs
- Required and optional fields

**Usage:**
```matlab
metadata = get_topology_metadata('two_switch_forward');
disp(metadata.display_name);  % 'Two-Switch Forward Converter'
disp(metadata.is_isolated);   % true
```

### 2. `get_visible_fields_for_topology(topology_key)`
Returns cell arrays of field names that should be visible.

**Returns:**
```matlab
[required_fields, optional_fields] = get_visible_fields_for_topology('flyback');
% required_fields = {'inputVoltage_min', 'inputVoltage_max', ...}
% optional_fields = {'inputVoltage_nom', 'currentRippleRatio', ...}
```

### 3. `get_topology_output_type(topology_key)`
Returns whether topology is 'single' or 'multi' output capable.

**Usage:**
```matlab
type = get_topology_output_type('buck');      % 'single'
type = get_topology_output_type('flyback');   % 'multi'
```

### 4. `update_field_visibility(fig, topology_key)`
**Main function** - Updates all field visibility when topology changes.

**Called from:**
- `cb_topology_changed()` when user selects new topology
- On GUI initialization to set up correct initial state

**What it does:**
1. Gets topology metadata
2. Gets required and optional field lists
3. Shows all required fields
4. Shows optional fields based on `data.show_optional` flag
5. Hides fields not needed for topology
6. Shows/hides N outputs spinner for multi-output topologies
7. Updates panel titles with topology name

### 5. `rebuild_output_spec_table(fig, topology_key)`
Rebuilds output specification rows (Voltage/Current inputs for each output).

**Currently:** Placeholder for future enhancement
**Future:** Will dynamically add/remove output rows based on N outputs spinner

### 6. `collect_gui_field_values(fig, topology_key)`
Gathers all user-entered values from visible GUI fields into a struct.

**Returns:**
```matlab
values = collect_gui_field_values(fig, 'two_switch_forward');
% values.inputVoltage_min = 100
% values.inputVoltage_max = 190
% values.outputVoltage = 5.0
% ... etc
```

## Topology Metadata Reference

| Topology | Key | Is Isolated | Outputs | Required Fields |
|----------|-----|-------------|---------|-----------------|
| Two-Switch Forward | `two_switch_forward` | Yes | 1-4 | inputVoltage_{min,max}, diodeVoltageDrop, fsw, vout, iout |
| Single-Switch Forward | `single_switch_forward` | Yes | 1-4 | inputVoltage_{min,max}, diodeVoltageDrop, fsw, vout, iout |
| Active Clamp Forward | `active_clamp_forward` | Yes | 1-4 | inputVoltage_{min,max}, diodeVoltageDrop, fsw, vout, iout |
| Flyback | `flyback` | Yes | 1-4 | inputVoltage_{min,max}, diodeVoltageDrop, fsw, vout, iout, efficiency |
| Push-Pull | `push_pull` | Yes | 1-4 | inputVoltage_{min,max}, diodeVoltageDrop, fsw, vout, iout |
| Buck | `buck` | No | 1 | inputVoltage_{min,max}, fsw, vout, iout |
| Boost | `boost` | No | 1 | inputVoltage_{min,max}, fsw, vout, iout |
| Isolated Buck | `isolated_buck` | Yes | 1-4 | inputVoltage_{min,max}, diodeVoltageDrop, fsw, vout, iout |
| Isolated Buck-Boost | `isolated_buck_boost` | Yes | 1-4 | inputVoltage_{min,max}, diodeVoltageDrop, fsw, vout, iout |

## Integration Steps

### Step 1: Add topology_field_visibility_system.m to Path

In `topology_wizard.m` main function (beginning):
```matlab
function topology_wizard()
    close all;

    % Add visibility system functions to path
    addpath(fileparts(mfilename('fullpath')));

    % ... rest of initialization
```

### Step 2: Update `cb_topology_changed()` Callback

Current code (lines 1197-1233) already calls `update_topology_visibility(data)`, which is the old function.

**Replace with:**
```matlab
function cb_topology_changed(src, ~)
    fig = gcbf();
    data = guidata(fig);

    % Map selection index to topology key
    topology_keys = {'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', ...
                     'flyback', 'push_pull', 'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'};
    idx = get(src, 'Value');

    if idx >= 1 && idx <= numel(topology_keys)
        data.topology = topology_keys{idx};
        % Get metadata for display name
        metadata = get_topology_metadata(data.topology);
        data.topology_display = metadata.display_name;
    end

    % Save updated data BEFORE calling update functions
    guidata(fig, data);

    % Update field visibility based on topology
    update_field_visibility(fig, data.topology);

    % Update computed design requirements display if available
    if isfield(data, 'requirements') && isstruct(data.requirements)
        update_topology_requirements_display(data, data.requirements);
    end
end
```

### Step 3: Update `build_wizard_panel()` to Store Field Handles

In `build_wizard_panel()`, after creating all UI controls, initialize handle tracking:

```matlab
% In build_wizard_panel(), after all controls are created:

% Initialize UI handle structure for visibility management
data.ui_handles = struct();
data.ui_handles.field_containers = struct();
data.ui_handles.fields = struct();

% Store references to key field controls
data.ui_handles.fields.edit_vin_min = data.edit_vin_min;
data.ui_handles.fields.edit_vin_max = data.edit_vin_max;
data.ui_handles.fields.edit_vin_nom = data.edit_vin_nom;
data.ui_handles.fields.edit_vout = data.edit_vout;
data.ui_handles.fields.edit_iout = data.edit_iout;
data.ui_handles.fields.edit_fsw = data.edit_fsw;
data.ui_handles.fields.edit_vd = data.edit_vd;
data.ui_handles.fields.edit_efficiency = data.edit_efficiency;
data.ui_handles.fields.edit_ripple = data.edit_ripple;
data.ui_handles.fields.edit_max_isw = data.edit_max_isw;
data.ui_handles.n_outputs_spinner = data.edit_n_outputs;
data.ui_handles.n_outputs_plus = data.btn_n_outputs_plus;
data.ui_handles.n_outputs_minus = data.btn_n_outputs_minus;

guidata(data.fig, data);
```

### Step 4: Initialize Field Visibility on Startup

Add this to the end of `build_gui()`:

```matlab
% In build_gui(), at the very end before final return/end:

% Initialize field visibility based on default topology
update_field_visibility(data.fig, data.topology);

guidata(data.fig, data);
```

### Step 5: Update `cb_n_outputs()` and Related Callbacks (Optional)

If you want to rebuild the output specification table dynamically:

```matlab
function cb_n_outputs(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val >= 1 && val <= 4
        data.n_outputs = round(val);
        % Rebuild output specification table
        rebuild_output_spec_table(fig, data.topology);
    else
        set(src, 'String', num2str(data.n_outputs));
    end
    guidata(fig, data);
end
```

### Step 6: Use `collect_gui_field_values()` in Compute Function

In `cb_compute_topology()` or when building MAS config:

```matlab
% Before calling Python topology calculator:
gui_values = collect_gui_field_values(fig, data.topology);

% These values can be used to populate the JSON config
% Example:
config.converter.inputVoltage_min = gui_values.inputVoltage_min;
config.converter.inputVoltage_max = gui_values.inputVoltage_max;
% ... etc
```

## Field Name Mapping

Internal field names used throughout:
- `inputVoltage_min` → `data.converter.vin_min` (GUI: `data.edit_vin_min`)
- `inputVoltage_max` → `data.converter.vin_max` (GUI: `data.edit_vin_max`)
- `inputVoltage_nom` → `data.converter.vin_nom` (GUI: `data.edit_vin_nom`)
- `outputVoltage` → `data.converter.vout` (GUI: `data.edit_vout`)
- `outputCurrent` → `data.converter.iout` (GUI: `data.edit_iout`)
- `switchingFrequency` → `data.converter.fsw_khz` (GUI: `data.edit_fsw`)
- `diodeVoltageDrop` → `data.converter.vd` (GUI: `data.edit_vd`)
- `efficiency` → `data.converter.efficiency` (GUI: `data.edit_efficiency`)
- `currentRippleRatio` → `data.converter.max_ripple` (GUI: `data.edit_ripple`)
- `maxSwitchCurrent` → `data.converter.max_switch_current` (GUI: `data.edit_max_isw`)

## Example: Switching to Flyback Topology

When user selects "Flyback" from dropdown:

1. **cb_topology_changed()** is triggered
2. Sets `data.topology = 'flyback'`
3. Calls `update_field_visibility(fig, 'flyback')`
4. Visibility system:
   - Gets metadata for flyback
   - Required fields: inputVoltage_min, inputVoltage_max, diodeVoltageDrop, fsw, vout, iout, **efficiency**
   - Shows all required fields
   - Hides fields not in required/optional list
   - Shows N outputs spinner (flyback is multi-output)
   - Updates panel title to "Flyback Converter - Converter Specifications"

Result: User sees flyback-specific UI with efficiency field now visible.

## Testing Checklist

- [ ] Select each topology from dropdown → verify correct fields shown/hidden
- [ ] Toggle optional parameters button → shows/hides optional fields correctly
- [ ] Switch between isolated (Forward) and non-isolated (Buck) → N outputs spinner appears/disappears
- [ ] Change N outputs spinner for multi-output topology → spinner is functional
- [ ] All field labels and units correct for selected topology
- [ ] Panel titles update with topology name
- [ ] `collect_gui_field_values()` returns correct values after filling fields
- [ ] Topology-specific constraints applied (e.g., Buck max 1 output)

## Future Enhancements

### Phase 2: Dynamic Output Row Management
Currently output specification rows (Output 1 Voltage/Current, Output 2, etc.) are static.

Enhance `rebuild_output_spec_table()` to:
1. Detect current number of output rows in GUI
2. Add/remove output rows based on `data.n_outputs`
3. Update layout and spacing dynamically
4. Maintain user-entered values when adding/removing rows

### Phase 3: Advanced Mode Field Management
Add advanced-only fields that only appear when `data.design_mode == 'advanced'`:
- Max duty cycle constraints
- Deadtime settings
- Advanced reluctance model selection

Update `update_field_visibility()` to check `design_mode` in addition to topology.

### Phase 4: Field Validation
Add topology-aware validation:
- Buck/Boost: vout must be < vin_max (step-down/up constraints)
- Flyback: efficiency required, typically 80-95%
- Forward: vin_nom typically centered in vin_min to vin_max range

### Phase 5: Contextual Help
Add tooltips that change based on topology:
```matlab
% In update_field_visibility():
set(data.edit_ripple, 'TooltipString', ...
    'Flyback: Ripple in primary magnetizing current. 30-50% typical.');
```

## Troubleshooting

### Problem: Fields not showing when topology changes
**Solution:** Verify `update_field_visibility()` is called from `cb_topology_changed()` and that `guidata()` is called to save data before the function.

### Problem: N outputs spinner not appearing
**Solution:** Check that topology is in multi-output list:
```matlab
output_type = get_topology_output_type(topology_key);
% Should return 'multi' for Forward/Flyback/etc.
```

### Problem: Optional fields always shown/hidden
**Solution:** Check `data.show_optional` flag is being set correctly when user clicks "Show Optional Parameters" button.

## References

- **Topology Equations:** See `generate_om_topology.py` for design requirement calculations
- **MAS Format:** See `build_mas_structure()` in topology_wizard.m for output format
- **OpenMagnetics:** PyOpenMagnetics topology calculators for validation
