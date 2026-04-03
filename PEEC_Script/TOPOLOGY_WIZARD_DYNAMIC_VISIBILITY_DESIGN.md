# Dynamic Field Visibility System for Topology Wizard
## Design Document
**Date:** 2026-02-25
**Status:** Design Phase
**Applicable to:** topology_wizard.m

---

## Executive Summary

This document provides a comprehensive design for implementing dynamic field visibility in the PEEC topology wizard GUI. When users select a converter topology (9 available), the GUI will automatically show/hide relevant input fields, update output specification tables, and adjust the N-outputs spinner visibility. The system is built on topology metadata lookup, callback-driven updates, and structured field tagging.

---

## 1. Current Architecture Analysis

### 1.1 Existing GUI Structure (Lines 130-589)
- **Path Buttons** (lines 142-173): Three pathway buttons (Wizard, MAS Import, Manual)
- **Wizard Panel** (lines 179-471): Main converter specifications panel
  - **Left Panel** (lines 220-349): Converter specs & optional fields
  - **Right Panel** (lines 351-469): Requirements, waveforms, recommendations
- **Optional Fields Panel** (lines 342-349, 475-589): Collapsible section for advanced params

### 1.2 Current Topology Handling
- **Topology Selection** (lines 228-236): PopupMenu with 9 topologies
- **Current Callback** (lines 1197-1233, `cb_topology_changed`):
  - Updates `data.topology` and `data.topology_display`
  - Calls `update_topology_visibility(data)` (lines 1487-1610)
  - Calls `update_topology_requirements_display(data)`

### 1.3 Current Visibility Function (Lines 1487-1610)
The existing `update_topology_visibility()` function:
- Already handles N-outputs spinner visibility
- Shows/hides various converter specs based on topology categories
- Uses `is_isolated`, `is_forward`, `is_flyback`, `is_buck_boost` boolean logic
- **Problem**: Field visibility logic is hardcoded; difficult to extend and maintain

### 1.4 Data Structure
```matlab
data.converter
  .vin_min              % required
  .vin_max              % required
  .vin_nom              % optional
  .vout                 % required
  .iout                 % required
  .fsw_khz              % required
  .efficiency           % optional
  .vd                   % optional (diode forward drop)
  .max_ripple           % optional (current ripple %)
  .max_switch_current   % optional
  .max_duty             % optional (advanced field)
  .n_outputs            % for isolated topologies (1-4)
```

---

## 2. Topology Metadata Specification

### 2.1 Nine Topologies

| Key | Display Name | Category | Isolated | Stores Energy | Multi-Output |
|-----|--------------|----------|----------|----------------|--------------|
| two_switch_forward | Two-Switch Forward | Forward | Yes | Transformer | No |
| single_switch_forward | Single-Switch Forward | Forward | Yes | Transformer | Yes |
| active_clamp_forward | Active Clamp Forward | Forward | Yes | Transformer | No |
| flyback | Flyback | Flyback | Yes | Transformer | Yes |
| push_pull | Push-Pull | Forward | Yes | Transformer | No |
| buck | Buck | Buck-Boost | No | Inductor | No |
| boost | Boost | Buck-Boost | No | Inductor | No |
| isolated_buck | Isolated Buck | Buck-Boost | Yes | Inductor | Yes |
| isolated_buck_boost | Isolated Buck-Boost | Buck-Boost | Yes | Inductor | Yes |

### 2.2 Field Requirements by Topology

#### Always Visible (All Topologies)
- Input Voltage Min/Max
- Switching Frequency
- Design Mode (Auto/Advanced toggle)
- Topology Dropdown

#### Topology-Conditional Fields

**Two-Switch Forward, Single-Switch Forward, Active Clamp Forward**
- Output Voltage (V)
- Output Current (A)
- Diode Forward Voltage (Vd) - optional
- Current Ripple (%) - optional
- Duty Cycle display (computed)

**Flyback**
- Output Voltage (V)
- Output Current (A)
- Diode Forward Voltage (Vd) - optional
- Current Ripple (%) - optional
- Max Duty Cycle (%) - optional [Advanced mode]
- Max Drain-Source Voltage (Vds) - optional [Advanced mode]
- Dead Time (ns) - optional [Advanced mode]

**Push-Pull**
- Output Voltage (V)
- Output Current (A)
- Diode Forward Voltage (Vd) - optional
- Current Ripple (%) - optional
- Max Drain-Source Voltage (Vds) - optional [Advanced mode]

**Buck**
- Output Voltage (V)
- Output Current (A)
- Current Ripple (%) - optional
- Load Resistance - optional [Advanced mode]

**Boost**
- Output Voltage (V)
- Output Current (A)
- Current Ripple (%) - optional
- Load Resistance - optional [Advanced mode]

**Isolated Buck**
- Output Voltage (V)
- Output Current (A)
- Current Ripple (%) - optional
- N Outputs Spinner

**Isolated Buck-Boost**
- Output Voltage (V)
- Output Current (A)
- Current Ripple (%) - optional
- N Outputs Spinner

### 2.3 Metadata Structure

Define a global lookup table (or function) mapping topology keys to field metadata:

```matlab
function topology_meta = get_topology_metadata(topology_key)
    % Returns struct with field visibility and requirements for topology

    % Initialize defaults
    meta = struct();
    meta.topology_key = topology_key;
    meta.is_isolated = false;
    meta.is_forward = false;
    meta.is_flyback = false;
    meta.is_buck = false;
    meta.is_boost = false;
    meta.stores_energy_in_transformer = false;
    meta.supports_n_outputs = false;
    meta.max_outputs = 1;
    meta.n_secondaries = 0;  % 0 = no secondaries, 1 = 1 secondary, etc.

    % Field visibility flags
    meta.show_output_voltage = true;
    meta.show_output_current = true;
    meta.show_diode_forward_voltage = true;
    meta.show_current_ripple = true;
    meta.show_duty_cycle = false;  % computed, not input
    meta.show_max_duty_cycle = false;
    meta.show_max_switch_current = false;
    meta.show_max_vds = false;
    meta.show_dead_time = false;
    meta.show_load_resistance = false;
    meta.show_n_outputs_spinner = false;

    % Advanced mode only fields
    meta.adv_only_max_duty = false;
    meta.adv_only_max_vds = false;
    meta.adv_only_dead_time = false;
    meta.adv_only_load_resistance = false;

    % Now apply topology-specific overrides
    switch topology_key
        case 'two_switch_forward'
            meta.is_isolated = true;
            meta.is_forward = true;
            meta.stores_energy_in_transformer = true;

        case 'single_switch_forward'
            meta.is_isolated = true;
            meta.is_forward = true;
            meta.stores_energy_in_transformer = true;
            meta.supports_n_outputs = true;
            meta.max_outputs = 4;
            meta.show_n_outputs_spinner = true;

        case 'active_clamp_forward'
            meta.is_isolated = true;
            meta.is_forward = true;
            meta.stores_energy_in_transformer = true;
            meta.show_max_vds = true;
            meta.adv_only_max_vds = true;

        case 'flyback'
            meta.is_isolated = true;
            meta.is_flyback = true;
            meta.stores_energy_in_transformer = true;
            meta.supports_n_outputs = true;
            meta.max_outputs = 4;
            meta.show_n_outputs_spinner = true;
            meta.show_max_duty_cycle = true;
            meta.show_max_vds = true;
            meta.show_dead_time = true;
            meta.adv_only_max_duty = true;
            meta.adv_only_max_vds = true;
            meta.adv_only_dead_time = true;

        case 'push_pull'
            meta.is_isolated = true;
            meta.is_forward = true;
            meta.stores_energy_in_transformer = true;
            meta.show_max_vds = true;
            meta.adv_only_max_vds = true;

        case 'buck'
            meta.is_buck = true;
            meta.show_current_ripple = true;
            meta.show_load_resistance = true;
            meta.adv_only_load_resistance = true;

        case 'boost'
            meta.is_boost = true;
            meta.show_current_ripple = true;
            meta.show_load_resistance = true;
            meta.adv_only_load_resistance = true;

        case 'isolated_buck'
            meta.is_isolated = true;
            meta.is_buck = true;
            meta.supports_n_outputs = true;
            meta.max_outputs = 4;
            meta.show_n_outputs_spinner = true;
            meta.show_current_ripple = true;

        case 'isolated_buck_boost'
            meta.is_isolated = true;
            meta.supports_n_outputs = true;
            meta.max_outputs = 4;
            meta.show_n_outputs_spinner = true;
            meta.show_current_ripple = true;
    end

    topology_meta = meta;
end
```

---

## 3. GUI Element Tagging Strategy

### 3.1 Tag Naming Convention

All editable GUI elements should have a Tag for programmatic reference:

```matlab
% Format: 'field_<fieldname>'

% Required fields
'field_vin_min'                    % edit box
'field_vin_max'                    % edit box
'field_vin_nom'                    % edit box (optional)
'field_vout'                       % edit box
'field_iout'                       % edit box
'field_fsw'                        % edit box
'field_efficiency'                 % edit box (optional)

% Conditional fields
'field_diode_vd'                   % edit box
'field_current_ripple'             % edit box
'field_max_duty_cycle'             % edit box
'field_max_switch_current'         % edit box
'field_max_vds'                    % edit box
'field_dead_time'                  % edit box
'field_load_resistance'            % edit box

% Control spinners
'field_n_outputs'                  % edit box with +/- buttons
'btn_n_outputs_plus'               % button
'btn_n_outputs_minus'              % button

% Labels (associated with fields)
'label_vin_min'                    % text
'label_vin_max'                    % text
... (one label per field)
```

### 3.2 Current Implementation Gap

Currently, most controls don't have Tags. The visibility function finds them via:
```matlab
if isfield(data, 'edit_vin_min') && ~isempty(data.edit_vin_min)
    set(data.edit_vin_min, 'Visible', 'on');
end
```

**Improvement**: Add Tags to all controls + store in data struct for lookup

---

## 4. Dynamic Visibility System Design

### 4.1 Callback Flow

```
User selects topology dropdown
    ↓
cb_topology_changed() [CALLBACK]
    ├─ Read selected dropdown value
    ├─ Map index → topology_key
    ├─ Update data.topology & data.topology_display
    ├─ Call guidata(fig, data)  [SAVE before visibility update]
    ├─ Call update_topology_visibility(data)
    │   └─ Get topology metadata
    │   └─ Show/hide fields based on meta flags
    │   └─ Update output spec table (dynamic rows)
    └─ Call update_topology_requirements_display(data)
```

### 4.2 Updated `update_topology_visibility()` Function

```matlab
function update_topology_visibility(data)
    % Update field visibility based on selected topology
    % Uses topology metadata lookup instead of hardcoded booleans

    fig = gcbf();

    % Get topology metadata
    meta = get_topology_metadata(data.topology);

    % Determine if advanced mode enabled
    adv_mode = strcmp(data.design_mode, 'advanced');

    % ===== INPUT VOLTAGE (always visible) =====
    set_field_visible(fig, 'field_vin_min', true);
    set_field_visible(fig, 'field_vin_max', true);
    if isfield(data, 'show_optional') && data.show_optional
        set_field_visible(fig, 'field_vin_nom', true);
    end

    % ===== OUTPUT SPECIFICATION (always visible but format varies) =====
    % Single-output topologies: Show 1 row with Vout/Iout
    % Multi-output topologies: Show N rows with Vout[1]/Iout[1], ..., Vout[N]/Iout[N]
    if meta.show_output_voltage && meta.show_output_current
        rebuild_output_spec_table(data, meta);
    end

    % ===== SWITCHING FREQUENCY (always visible) =====
    set_field_visible(fig, 'field_fsw', true);

    % ===== EFFICIENCY (always visible in optional) =====
    if isfield(data, 'show_optional') && data.show_optional
        set_field_visible(fig, 'field_efficiency', true);
    end

    % ===== CONDITIONAL FIELDS =====
    set_field_visible(fig, 'field_diode_vd', meta.show_diode_forward_voltage);
    set_field_visible(fig, 'field_current_ripple', meta.show_current_ripple);

    % Max Duty Cycle (advanced or Flyback)
    show_max_duty = meta.show_max_duty_cycle && (~meta.adv_only_max_duty || adv_mode);
    set_field_visible(fig, 'field_max_duty_cycle', show_max_duty);

    % Max Drain-Source Voltage (some topologies + advanced)
    show_max_vds = meta.show_max_vds && (~meta.adv_only_max_vds || adv_mode);
    set_field_visible(fig, 'field_max_vds', show_max_vds);

    % Dead Time (Flyback advanced)
    show_dead_time = meta.show_dead_time && (~meta.adv_only_dead_time || adv_mode);
    set_field_visible(fig, 'field_dead_time', show_dead_time);

    % Max Switch Current (advanced)
    show_max_isw = meta.show_max_switch_current && (~meta.adv_only_max_switch_current || adv_mode);
    set_field_visible(fig, 'field_max_switch_current', show_max_isw);

    % Load Resistance (Buck/Boost advanced)
    show_load_res = meta.show_load_resistance && (~meta.adv_only_load_resistance || adv_mode);
    set_field_visible(fig, 'field_load_resistance', show_load_res);

    % ===== N OUTPUTS SPINNER (isolated topologies only) =====
    if meta.show_n_outputs_spinner
        set_field_visible(fig, 'field_n_outputs', true);
        set_field_visible(fig, 'btn_n_outputs_plus', true);
        set_field_visible(fig, 'btn_n_outputs_minus', true);

        % Clamp n_outputs to max_outputs for this topology
        if data.n_outputs > meta.max_outputs
            data.n_outputs = meta.max_outputs;
            if isfield(data, 'edit_n_outputs')
                set(data.edit_n_outputs, 'String', num2str(data.n_outputs));
            end
        end
    else
        set_field_visible(fig, 'field_n_outputs', false);
        set_field_visible(fig, 'btn_n_outputs_plus', false);
        set_field_visible(fig, 'btn_n_outputs_minus', false);
        data.n_outputs = 1;  % Reset to 1 for non-isolated
    end

    guidata(fig, data);
end


function set_field_visible(fig, field_tag, is_visible)
    % Helper: Set visibility of a field and its label by tag

    % Find all controls with this tag
    controls = findobj(fig, 'Tag', field_tag);
    if ~isempty(controls)
        if is_visible
            set(controls, 'Visible', 'on');
        else
            set(controls, 'Visible', 'off');
        end
    end

    % Also hide associated label (convention: 'label_<fieldname>')
    label_tag = strrep(field_tag, 'field_', 'label_');
    labels = findobj(fig, 'Tag', label_tag);
    if ~isempty(labels)
        if is_visible
            set(labels, 'Visible', 'on');
        else
            set(labels, 'Visible', 'off');
        end
    end

    % Hide associated units label (convention: 'unit_<fieldname>')
    unit_tag = strrep(field_tag, 'field_', 'unit_');
    units = findobj(fig, 'Tag', unit_tag);
    if ~isempty(units)
        if is_visible
            set(units, 'Visible', 'on');
        else
            set(units, 'Visible', 'off');
        end
    end
end
```

### 4.3 Output Specification Table Rebuilding

For multi-output topologies, the GUI needs to dynamically create/destroy output specification rows.

```matlab
function rebuild_output_spec_table(data, meta)
    % Rebuild output voltage/current specification table based on N outputs

    fig = gcbf();

    n_outputs = data.n_outputs;
    if n_outputs < 1
        n_outputs = 1;
    elseif n_outputs > meta.max_outputs
        n_outputs = meta.max_outputs;
    end

    % Initialize output storage if not present
    if ~isfield(data.converter, 'outputs') || isempty(data.converter.outputs)
        data.converter.outputs = repmat(struct('voltage', [], 'current', []), n_outputs, 1);
    end

    % Resize to match n_outputs
    if numel(data.converter.outputs) ~= n_outputs
        old_outputs = data.converter.outputs;
        data.converter.outputs = repmat(struct('voltage', [], 'current', []), n_outputs, 1);
        % Copy over old values if shrinking
        for i = 1:min(numel(old_outputs), n_outputs)
            data.converter.outputs(i) = old_outputs(i);
        end
    end

    % Find or create output specification panel
    spec_panel = findobj(fig, 'Type', 'uipanel', '-regexp', 'Title', '.*Converter Specifications');
    if isempty(spec_panel)
        return;
    end
    spec_panel = spec_panel(1);

    % Look for existing output table container or create one
    table_container = findobj(spec_panel, 'Tag', 'output_spec_container');
    if ~isempty(table_container)
        delete(table_container);
    end

    % Create container for output specification rows
    y_top = 0.35;  % Position below converter specs
    height_per_row = 0.08;
    total_height = height_per_row * n_outputs + 0.02;

    table_container = uipanel('Parent', spec_panel, ...
                              'Position', [0.02 y_top-total_height 0.96 total_height], ...
                              'Title', 'Output Specification', ...
                              'FontSize', 9, ...
                              'Tag', 'output_spec_container');

    % Create rows
    for i = 1:n_outputs
        y = 0.95 - (i-1) * (height_per_row / total_height);
        row_height = (height_per_row / total_height);

        % Label
        if n_outputs == 1
            label_str = 'Output';
        else
            label_str = sprintf('Output %d', i);
        end

        uicontrol('Parent', table_container, 'Style', 'text', ...
                  'String', label_str, ...
                  'Units', 'normalized', ...
                  'Position', [0.02 y-row_height 0.15 0.8*row_height], ...
                  'FontSize', 9, ...
                  'HorizontalAlignment', 'right');

        % Voltage edit
        default_vout = data.converter.vout;
        if i <= numel(data.converter.outputs) && ~isempty(data.converter.outputs(i).voltage)
            default_vout = data.converter.outputs(i).voltage;
        end

        data.(['edit_vout_' num2str(i)]) = uicontrol('Parent', table_container, ...
                                                       'Style', 'edit', ...
                                                       'String', num2str(default_vout), ...
                                                       'Units', 'normalized', ...
                                                       'Position', [0.20 y-row_height 0.12 0.8*row_height], ...
                                                       'FontSize', 9, ...
                                                       'Tag', ['field_vout_' num2str(i)], ...
                                                       'Callback', @(src,evt) cb_vout_n(src, evt, i));

        uicontrol('Parent', table_container, 'Style', 'text', ...
                  'String', 'V', ...
                  'Units', 'normalized', ...
                  'Position', [0.33 y-row_height 0.05 0.8*row_height], ...
                  'FontSize', 9, ...
                  'Tag', ['unit_vout_' num2str(i)]);

        % Current edit
        default_iout = data.converter.iout;
        if i <= numel(data.converter.outputs) && ~isempty(data.converter.outputs(i).current)
            default_iout = data.converter.outputs(i).current;
        end

        data.(['edit_iout_' num2str(i)]) = uicontrol('Parent', table_container, ...
                                                       'Style', 'edit', ...
                                                       'String', num2str(default_iout), ...
                                                       'Units', 'normalized', ...
                                                       'Position', [0.40 y-row_height 0.12 0.8*row_height], ...
                                                       'FontSize', 9, ...
                                                       'Tag', ['field_iout_' num2str(i)], ...
                                                       'Callback', @(src,evt) cb_iout_n(src, evt, i));

        uicontrol('Parent', table_container, 'Style', 'text', ...
                  'String', 'A', ...
                  'Units', 'normalized', ...
                  'Position', [0.53 y-row_height 0.05 0.8*row_height], ...
                  'FontSize', 9, ...
                  'Tag', ['unit_iout_' num2str(i)]);
    end

    guidata(fig, data);
end


function cb_vout_n(src, ~, output_index)
    % Callback for output voltage edit box (multi-output)

    fig = gcbf();
    data = guidata(fig);

    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        % Store in output array
        if output_index <= numel(data.converter.outputs)
            data.converter.outputs(output_index).voltage = val;
        end

        % Update requirements (topology-specific)
        data = compute_requirements(data);
        data = update_requirements_display(data);
    end

    guidata(fig, data);
end


function cb_iout_n(src, ~, output_index)
    % Callback for output current edit box (multi-output)

    fig = gcbf();
    data = guidata(fig);

    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        % Store in output array
        if output_index <= numel(data.converter.outputs)
            data.converter.outputs(output_index).current = val;
        end

        % Update requirements
        data = compute_requirements(data);
        data = update_requirements_display(data);
    end

    guidata(fig, data);
end
```

---

## 5. Implementation Steps

### Phase 1: Tagging & Metadata (No Functional Change)

1. **Add Tags to all GUI controls** in `build_wizard_panel()` and `build_optional_fields()`
   - Use naming convention: `field_<fieldname>`, `label_<fieldname>`, `unit_<fieldname>`
   - Example: Vin_min edit box gets Tag='field_vin_min', label gets Tag='label_vin_min'

2. **Create `get_topology_metadata()` function**
   - Returns struct with all field visibility flags for 9 topologies
   - Hardcoded metadata (no dependencies on Python)
   - Can be extended for future topologies

3. **Create `set_field_visible()` helper function**
   - Takes (fig, field_tag, is_visible)
   - Finds control by tag + associated label/unit tags
   - Sets Visible property

4. **Test**: Verify all controls have correct tags, no crashes

### Phase 2: Refactor Visibility Function

1. **Replace hardcoded boolean logic in `update_topology_visibility()`**
   - Call `get_topology_metadata()` instead of manual is_isolated, is_forward, etc.
   - Use loop over metadata flags instead of individual set() calls
   - Apply advanced mode filtering for conditional fields

2. **Update `cb_topology_changed()`**
   - Ensure `guidata(fig, data)` is called BEFORE `update_topology_visibility(data)`
   - This was a bug in original code (lines 1223 vs 1226)

3. **Test**: Select each topology, verify correct fields show/hide

### Phase 3: Multi-Output Support

1. **Create `rebuild_output_spec_table()` function**
   - Dynamic row creation based on n_outputs
   - Called when topology changes OR n_outputs spinner changes

2. **Update `cb_n_outputs_changed()` and `cb_n_outputs_plus/minus()`**
   - Call `rebuild_output_spec_table()` after updating n_outputs

3. **Create `cb_vout_n()` and `cb_iout_n()` callbacks**
   - Store multi-output voltages/currents in `data.converter.outputs` array

4. **Update `compute_requirements()` and `build_design_spec_wizard()`**
   - Handle multi-output case when passing to Python topology calculator
   - Include output array in JSON config

5. **Test**: Create Flyback with 2 outputs, verify table appears/updates correctly

### Phase 4: Integration & Polish

1. **Update all converter spec callbacks** (cb_vin_min, cb_vout, etc.)
   - Ensure they handle both single-output and multi-output cases
   - Call appropriate compute_requirements variant

2. **Add visual feedback**
   - Highlight currently active topology in dropdown
   - Show field categories (Required/Optional/Advanced)

3. **Test**: Full workflow with each topology

---

## 6. Data Flow for Multi-Output Topologies

### 6.1 Single-Output Example (Two-Switch Forward)

```
data.converter.vout = 5;      % Single scalar
data.converter.iout = 10;
data.converter.outputs = [];  % Not used

Python input:
{
  "converter": {
    "vout": 5,
    "iout": 10,
    ...
  }
}
```

### 6.2 Multi-Output Example (Flyback with 2 secondaries)

```
data.converter.vout = [];      % Not used for multi-output
data.converter.iout = [];
data.n_outputs = 2;
data.converter.outputs(1).voltage = 5;    % Output 1
data.converter.outputs(1).current = 10;
data.converter.outputs(2).voltage = 12;   % Output 2
data.converter.outputs(2).current = 5;

GUI Table:
┌─────────────────────────────────┐
│Output 1   [5     ] V  [10    ] A│
│Output 2   [12    ] V  [5     ] A│
└─────────────────────────────────┘

Python input:
{
  "n_outputs": 2,
  "outputs": [
    {"voltage": 5, "current": 10},
    {"voltage": 12, "current": 5}
  ],
  ...
}
```

---

## 7. Callback Dependency Graph

```
Topology Dropdown Selected
    ↓
cb_topology_changed()
    ├─ Map index → topology_key
    ├─ Update data.topology, data.topology_display
    ├─ guidata(fig, data)  [SAVE]
    ├─ update_topology_visibility(data)
    │   ├─ get_topology_metadata()
    │   ├─ Show/hide fields
    │   └─ rebuild_output_spec_table(data, meta)  [if multi-output]
    └─ update_topology_requirements_display(data)

N Outputs Spinner Changed (+ or -)
    ↓
cb_n_outputs_plus() or cb_n_outputs_minus()
    ├─ Increment/decrement data.n_outputs
    ├─ Update edit box display
    ├─ guidata(fig, data)  [SAVE]
    └─ rebuild_output_spec_table(data, meta)

Output Voltage Edit[i] Changed
    ↓
cb_vout_n(src, evt, i)
    ├─ Parse string → float
    ├─ Store in data.converter.outputs(i).voltage
    ├─ compute_requirements(data)
    ├─ update_requirements_display(data)
    └─ guidata(fig, data)  [SAVE]

Output Current Edit[i] Changed
    ↓
cb_iout_n(src, evt, i)
    ├─ Parse string → float
    ├─ Store in data.converter.outputs(i).current
    ├─ compute_requirements(data)
    ├─ update_requirements_display(data)
    └─ guidata(fig, data)  [SAVE]
```

---

## 8. Testing Strategy

### 8.1 Unit Tests (Per Topology)

For each of 9 topologies:
1. Select topology in dropdown
2. Verify correct fields are visible
3. Verify correct fields are hidden
4. Check Requirements panel updates
5. Test with Advanced mode ON → additional fields appear

### 8.2 Integration Tests

1. **Single-output flow (Two-Switch Forward)**
   - Enter Vin, Vout, Iout, Fsw
   - Click "Compute Requirements"
   - Verify requirements display updates
   - Verify N-outputs spinner is hidden

2. **Multi-output flow (Flyback)**
   - Select Flyback
   - N-outputs spinner appears
   - Click + to set to 3 outputs
   - Output spec table shows 3 rows
   - Enter Vout[1..3], Iout[1..3]
   - Click "Compute Requirements"
   - Verify Python receives 3-output JSON

3. **Mode switching**
   - Select Flyback in Auto mode → only basic fields
   - Switch to Advanced mode → Max Duty, Max Vds, Dead Time appear
   - Switch back to Auto → fields hidden

4. **Cross-topology switching**
   - Start with Two-Switch Forward
   - Switch to Buck → Output spec table shrinks to single row
   - Switch to Flyback → Multi-output controls reappear

### 8.3 Edge Cases

1. N-outputs clamping: Flyback allows max 4, attempt to set 5 → clamped to 4
2. Empty output specs: Create Flyback with 2 outputs, delete one Vout value → error or default?
3. Tab order: Ensure Tab navigation works across dynamic elements

---

## 9. Future Extensions

### 9.1 Multi-Winding Topologies

For isolated topologies with multiple secondaries, enhance `compute_requirements()` to:
- Calculate Ns[1]/Np, Ns[2]/Np for each secondary
- Handle unequal secondary voltages (buck/boost on secondaries)
- Generate multi-operating-point excitation profiles

### 9.2 Insulation Field Grouping

Move insulation/thermal fields into a separate panel, shown/hidden together:
```matlab
if strcmp(data.design_mode, 'advanced')
    set(data.panel_insulation, 'Visible', 'on');
end
```

### 9.3 Load Profile Editor

Add button to define multiple operating points per topology:
```
Design Mode: Auto | Advanced | Load Profile
                              └─ Opens editor for Vin/Iout/Duty multiple points
```

### 9.4 Topology-Specific Help Tooltips

Associate help text with each topology, displayed in a callout when selected:
```matlab
meta.help_text = 'Two-Switch Forward: Transformer stores no energy. Peak voltage = 2*Vin + Vd.';
```

---

## 10. Code Organization Summary

### Files Modified
1. `topology_wizard.m`
   - Add `get_topology_metadata()` function
   - Add `set_field_visible()` helper
   - Refactor `update_topology_visibility()` to use metadata
   - Add tags to all GUI controls in `build_wizard_panel()`
   - Add `rebuild_output_spec_table()` function
   - Add `cb_vout_n()` and `cb_iout_n()` callbacks
   - Update `cb_topology_changed()` to ensure guidata timing
   - Update `cb_n_outputs_plus/minus()` to call rebuild

### New Functions (Inline)
```matlab
% Core visibility system
get_topology_metadata(topology_key)        % Returns field visibility metadata
set_field_visible(fig, field_tag, visible) % Helper to show/hide field + label + unit

% Multi-output support
rebuild_output_spec_table(data, meta)      % Create/destroy output rows dynamically
cb_vout_n(src, evt, output_index)          % Multi-output voltage callback
cb_iout_n(src, evt, output_index)          % Multi-output current callback

% Existing, to be updated
cb_topology_changed()                      % Existing, fix guidata timing
cb_n_outputs_plus/minus()                  % Existing, call rebuild on change
update_topology_visibility()                % Existing, refactor to use metadata
```

---

## 11. Code Sketch Examples

### 11.1 Complete `get_topology_metadata()` Function

```matlab
function meta = get_topology_metadata(topology_key)
    % Get topology-specific field visibility and configuration
    % Input: topology_key (string) e.g., 'flyback', 'buck'
    % Output: struct with flags for each field

    % Initialize with all defaults (most fields hidden)
    meta = struct();
    meta.topology_key = topology_key;
    meta.is_isolated = false;
    meta.is_forward = false;
    meta.is_flyback = false;
    meta.stores_energy_in_transformer = false;
    meta.supports_n_outputs = false;
    meta.max_outputs = 1;

    % Field visibility flags (most false by default)
    meta.show_output_voltage = true;
    meta.show_output_current = true;
    meta.show_diode_forward_voltage = false;
    meta.show_current_ripple = false;
    meta.show_max_duty_cycle = false;
    meta.show_max_vds = false;
    meta.show_max_switch_current = false;
    meta.show_dead_time = false;
    meta.show_load_resistance = false;
    meta.show_n_outputs_spinner = false;

    % Advanced mode only flags
    meta.adv_only_max_duty = false;
    meta.adv_only_max_vds = false;
    meta.adv_only_dead_time = false;
    meta.adv_only_max_switch_current = false;
    meta.adv_only_load_resistance = false;

    % Topology-specific configuration
    switch topology_key
        case 'two_switch_forward'
            meta.is_isolated = true;
            meta.is_forward = true;
            meta.stores_energy_in_transformer = true;
            meta.show_diode_forward_voltage = true;
            meta.show_current_ripple = true;

        case 'single_switch_forward'
            meta.is_isolated = true;
            meta.is_forward = true;
            meta.stores_energy_in_transformer = true;
            meta.show_diode_forward_voltage = true;
            meta.show_current_ripple = true;
            meta.supports_n_outputs = true;
            meta.max_outputs = 4;
            meta.show_n_outputs_spinner = true;

        case 'active_clamp_forward'
            meta.is_isolated = true;
            meta.is_forward = true;
            meta.stores_energy_in_transformer = true;
            meta.show_diode_forward_voltage = true;
            meta.show_current_ripple = true;
            meta.show_max_vds = true;
            meta.adv_only_max_vds = true;

        case 'flyback'
            meta.is_isolated = true;
            meta.is_flyback = true;
            meta.stores_energy_in_transformer = true;
            meta.show_diode_forward_voltage = true;
            meta.show_current_ripple = true;
            meta.show_max_duty_cycle = true;
            meta.show_max_vds = true;
            meta.show_dead_time = true;
            meta.adv_only_max_duty = true;
            meta.adv_only_max_vds = true;
            meta.adv_only_dead_time = true;
            meta.supports_n_outputs = true;
            meta.max_outputs = 4;
            meta.show_n_outputs_spinner = true;

        case 'push_pull'
            meta.is_isolated = true;
            meta.is_forward = true;
            meta.stores_energy_in_transformer = true;
            meta.show_diode_forward_voltage = true;
            meta.show_current_ripple = true;
            meta.show_max_vds = true;
            meta.adv_only_max_vds = true;

        case 'buck'
            meta.show_diode_forward_voltage = true;
            meta.show_current_ripple = true;
            meta.show_load_resistance = true;
            meta.adv_only_load_resistance = true;

        case 'boost'
            meta.show_diode_forward_voltage = true;
            meta.show_current_ripple = true;
            meta.show_load_resistance = true;
            meta.adv_only_load_resistance = true;

        case 'isolated_buck'
            meta.is_isolated = true;
            meta.show_diode_forward_voltage = true;
            meta.show_current_ripple = true;
            meta.supports_n_outputs = true;
            meta.max_outputs = 4;
            meta.show_n_outputs_spinner = true;

        case 'isolated_buck_boost'
            meta.is_isolated = true;
            meta.show_diode_forward_voltage = true;
            meta.show_current_ripple = true;
            meta.supports_n_outputs = true;
            meta.max_outputs = 4;
            meta.show_n_outputs_spinner = true;

        otherwise
            % Unknown topology, use defaults
    end
end
```

### 11.2 Refactored `update_topology_visibility()` Using Metadata

```matlab
function update_topology_visibility(data)
    % Update field visibility based on selected topology and design mode
    % Uses topology metadata lookup instead of hardcoded booleans

    fig = gcbf();

    % Get topology metadata
    meta = get_topology_metadata(data.topology);

    % Determine if advanced mode enabled
    adv_mode = strcmp(data.design_mode, 'advanced');

    % ===== ALWAYS VISIBLE =====
    set_field_visible(fig, 'field_vin_min', true);
    set_field_visible(fig, 'field_vin_max', true);
    set_field_visible(fig, 'field_fsw', true);

    % Optional nominal input voltage (shown only if optional panel is open)
    show_vin_nom = isfield(data, 'show_optional') && data.show_optional;
    set_field_visible(fig, 'field_vin_nom', show_vin_nom);

    % ===== CONDITIONAL FIELDS (from metadata) =====
    set_field_visible(fig, 'field_diode_vd', meta.show_diode_forward_voltage);
    set_field_visible(fig, 'field_current_ripple', meta.show_current_ripple);

    % Fields visible in optional panel
    if isfield(data, 'show_optional') && data.show_optional
        set_field_visible(fig, 'field_efficiency', true);
    else
        set_field_visible(fig, 'field_efficiency', false);
    end

    % Advanced-only fields
    show_max_duty = meta.show_max_duty_cycle && (~meta.adv_only_max_duty || adv_mode);
    set_field_visible(fig, 'field_max_duty_cycle', show_max_duty);

    show_max_vds = meta.show_max_vds && (~meta.adv_only_max_vds || adv_mode);
    set_field_visible(fig, 'field_max_vds', show_max_vds);

    show_dead_time = meta.show_dead_time && (~meta.adv_only_dead_time || adv_mode);
    set_field_visible(fig, 'field_dead_time', show_dead_time);

    show_max_isw = meta.show_max_switch_current && (~meta.adv_only_max_switch_current || adv_mode);
    set_field_visible(fig, 'field_max_switch_current', show_max_isw);

    show_load_res = meta.show_load_resistance && (~meta.adv_only_load_resistance || adv_mode);
    set_field_visible(fig, 'field_load_resistance', show_load_res);

    % ===== OUTPUT SPECIFICATIONS (always visible, format varies) =====
    % For single-output topologies, show single Vout/Iout
    % For multi-output topologies, show dynamic table
    if meta.show_n_outputs_spinner
        % Multi-output topology: will be handled by rebuild_output_spec_table
        data = rebuild_output_spec_table(data, meta);
    else
        % Single-output topology: show standard Vout/Iout fields
        set_field_visible(fig, 'field_vout', meta.show_output_voltage);
        set_field_visible(fig, 'field_iout', meta.show_output_current);

        % Clean up any multi-output controls
        for i = 1:4
            set_field_visible(fig, ['field_vout_' num2str(i)], false);
            set_field_visible(fig, ['field_iout_' num2str(i)], false);
        end
    end

    % ===== N OUTPUTS SPINNER (isolated topologies only) =====
    if meta.show_n_outputs_spinner
        set_field_visible(fig, 'field_n_outputs', true);
        set_field_visible(fig, 'btn_n_outputs_plus', true);
        set_field_visible(fig, 'btn_n_outputs_minus', true);

        % Clamp n_outputs to topology maximum
        if data.n_outputs > meta.max_outputs
            data.n_outputs = meta.max_outputs;
            if isfield(data, 'edit_n_outputs') && ~isempty(data.edit_n_outputs)
                set(data.edit_n_outputs, 'String', num2str(data.n_outputs));
            end
        end
    else
        set_field_visible(fig, 'field_n_outputs', false);
        set_field_visible(fig, 'btn_n_outputs_plus', false);
        set_field_visible(fig, 'btn_n_outputs_minus', false);
        data.n_outputs = 1;  % Reset for non-isolated topologies
    end

    guidata(fig, data);
end


function set_field_visible(fig, field_tag, is_visible)
    % Helper: Set visibility of a field and its associated labels
    %
    % Looks for controls with tags:
    %   - field_tag (the control itself)
    %   - 'label_' + fieldname (associated label)
    %   - 'unit_' + fieldname (associated units label)

    % Determine field name from tag
    if startsWith(field_tag, 'field_')
        fieldname = field_tag(7:end);  % Remove 'field_' prefix
    else
        fieldname = field_tag;
    end

    % Set visibility for all matching controls
    all_controls = findobj(fig, 'Tag', field_tag);
    if ~isempty(all_controls)
        for i = 1:numel(all_controls)
            set(all_controls(i), 'Visible', onoff(is_visible));
        end
    end

    % Set visibility for label
    label_tag = ['label_' fieldname];
    label_controls = findobj(fig, 'Tag', label_tag);
    if ~isempty(label_controls)
        for i = 1:numel(label_controls)
            set(label_controls(i), 'Visible', onoff(is_visible));
        end
    end

    % Set visibility for units
    unit_tag = ['unit_' fieldname];
    unit_controls = findobj(fig, 'Tag', unit_tag);
    if ~isempty(unit_controls)
        for i = 1:numel(unit_controls)
            set(unit_controls(i), 'Visible', onoff(is_visible));
        end
    end
end


function str = onoff(is_visible)
    % Convert boolean to 'on'/'off' string
    if is_visible
        str = 'on';
    else
        str = 'off';
    end
end
```

### 11.3 Updated `cb_topology_changed()` with Proper Timing

```matlab
function cb_topology_changed(src, ~)
    % Callback when topology dropdown changes

    fig = gcbf();
    data = guidata(fig);

    % Map selection index to topology key
    topology_keys = {'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', ...
                     'flyback', 'push_pull', 'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'};
    topology_names = {'Two-Switch Forward Converter', 'Single-Switch Forward Converter', ...
                      'Active Clamp Forward Converter', 'Flyback Converter', 'Push-Pull Converter', ...
                      'Buck Converter', 'Boost Converter', 'Isolated Buck Converter', ...
                      'Isolated Buck-Boost Converter'};

    idx = get(src, 'Value');
    if idx >= 1 && idx <= numel(topology_keys)
        data.topology = topology_keys{idx};
        data.topology_display = topology_names{idx};
    end

    % Update spec panel title
    spec_panel = findobj(fig, 'Type', 'uipanel', '-regexp', 'Title', '.*Converter Specifications');
    if ~isempty(spec_panel)
        spec_title = sprintf('%s - Converter Specifications', data.topology_display);
        set(spec_panel(1), 'Title', spec_title);
    end

    % === CRITICAL: Save updated data BEFORE calling visibility functions ===
    % This ensures that update_topology_visibility() sees the correct data.topology
    guidata(fig, data);

    % Update field visibility based on topology (now data is saved)
    update_topology_visibility(data);

    % Update computed design requirements display
    if isfield(data, 'requirements') && isstruct(data.requirements)
        data = update_topology_requirements_display(data, data.requirements);
    end

    % Re-retrieve data after update functions and save
    data = guidata(fig);
    guidata(fig, data);
end
```

---

## 12. Summary Checklist

- [ ] Add Tags to all GUI controls
- [ ] Create `get_topology_metadata()` function
- [ ] Create `set_field_visible()` helper
- [ ] Refactor `update_topology_visibility()` to use metadata
- [ ] Create `rebuild_output_spec_table()` function
- [ ] Add `cb_vout_n()` and `cb_iout_n()` callbacks
- [ ] Update `cb_n_outputs_plus/minus()` to trigger rebuild
- [ ] Fix `cb_topology_changed()` guidata timing
- [ ] Update `compute_requirements()` for multi-output case
- [ ] Update `build_design_spec_wizard()` to include outputs array
- [ ] Test all 9 topologies individually
- [ ] Test multi-output workflows (Flyback, Single-Switch Forward, etc.)
- [ ] Test mode switching (Auto ↔ Advanced)
- [ ] Test cross-topology switching
- [ ] Verify Python receives correct JSON for multi-output cases

