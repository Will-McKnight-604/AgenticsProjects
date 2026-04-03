# Dynamic Field Visibility Implementation - Quick Reference

## Overview
This document summarizes the design for a topology-aware dynamic field visibility system in topology_wizard.m. See the full design document (TOPOLOGY_WIZARD_DYNAMIC_VISIBILITY_DESIGN.md) for complete details.

## Core Concept
Replace hardcoded boolean logic (`is_isolated`, `is_forward`, etc.) with a metadata-driven system that:
1. Maps each of 9 topologies to field visibility flags
2. Shows/hides fields dynamically based on topology selection
3. Supports multi-output topologies with dynamic output specification tables
4. Filters advanced-only fields based on design mode (Auto/Advanced)

## Key Functions to Implement

### 1. `get_topology_metadata(topology_key)` - NEW
Returns struct with visibility flags for a given topology.

**Input:** topology_key (string)
- 'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', 'flyback', 'push_pull', 'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'

**Output:** meta (struct)
```matlab
meta.is_isolated                      % boolean
meta.is_forward                       % boolean
meta.is_flyback                       % boolean
meta.stores_energy_in_transformer     % boolean
meta.supports_n_outputs               % boolean for multi-output capability
meta.max_outputs                      % 1-4
meta.show_output_voltage              % boolean
meta.show_output_current              % boolean
meta.show_diode_forward_voltage       % boolean
meta.show_current_ripple              % boolean
meta.show_max_duty_cycle              % boolean
meta.show_max_vds                     % boolean
meta.show_dead_time                   % boolean
meta.show_load_resistance             % boolean
meta.show_n_outputs_spinner           % boolean
% ... (advanced-only flags)
meta.adv_only_max_duty                % only visible if Advanced mode
meta.adv_only_max_vds
meta.adv_only_dead_time
meta.adv_only_load_resistance
```

**Location:** Add to topology_wizard.m after line 1486 (before `update_topology_visibility`)

---

### 2. `set_field_visible(fig, field_tag, is_visible)` - NEW HELPER
Shows/hides a field and its associated label/units by Tag.

**Input:**
- fig: figure handle
- field_tag: string like 'field_vin_min'
- is_visible: boolean

**Implementation:** Finds all controls with matching Tags:
- 'field_<name>' (the control itself)
- 'label_<name>' (label before the control)
- 'unit_<name>' (units after the control)

**Location:** Add to topology_wizard.m as inline helper after `get_topology_metadata()`

---

### 3. `rebuild_output_spec_table(data, meta)` - NEW
Dynamically creates/destroys output specification rows for multi-output topologies.

**Input:**
- data: main data struct with converter, n_outputs, etc.
- meta: topology metadata from `get_topology_metadata()`

**Behavior:**
- For single-output topologies: Shows standard field_vout, field_iout
- For multi-output topologies: Creates dynamic panel with N rows
  - Row 1: "Output 1" [Vout1] V [Iout1] A
  - Row 2: "Output 2" [Vout2] V [Iout2] A
  - ... up to meta.max_outputs

**Data Storage:** `data.converter.outputs` is a struct array:
```matlab
data.converter.outputs(1).voltage = 5;    % Vout1
data.converter.outputs(1).current = 10;   % Iout1
data.converter.outputs(2).voltage = 12;   % Vout2
data.converter.outputs(2).current = 5;    % Iout2
```

**Location:** Add to topology_wizard.m after `update_topology_visibility()`

---

### 4. `cb_vout_n(src, evt, output_index)` - NEW
Callback for multi-output voltage edit boxes.

**Behavior:**
- Parse string to double
- Store in `data.converter.outputs(output_index).voltage`
- Call `compute_requirements()` and `update_requirements_display()`
- Save with `guidata(fig, data)`

**Location:** Add to callback section (after line 1680)

---

### 5. `cb_iout_n(src, evt, output_index)` - NEW
Callback for multi-output current edit boxes.

**Behavior:** Same as cb_vout_n but for current values.

**Location:** Add to callback section

---

## Modifications to Existing Functions

### 1. `cb_topology_changed()` - FIX GUIDATA TIMING (Lines 1197-1233)

**Problem:** Current code calls `guidata(fig, data)` AFTER `update_topology_visibility()`, causing visibility function to read stale topology value.

**Fix:**
```matlab
% OLD (WRONG):
data.topology = topology_keys{idx};
spec_panel update...
update_topology_visibility(data);  % reads STALE data.topology!
guidata(fig, data);

% NEW (CORRECT):
data.topology = topology_keys{idx};
spec_panel update...
guidata(fig, data);  % SAVE FIRST
update_topology_visibility(data);  % now reads FRESH data.topology
guidata(fig, data);  % save again after updates
```

---

### 2. `update_topology_visibility()` - REFACTOR (Lines 1487-1610)

**Current:** Hardcoded boolean logic for each field

**New:** Use metadata-driven approach
```matlab
function update_topology_visibility(data)
    meta = get_topology_metadata(data.topology);
    adv_mode = strcmp(data.design_mode, 'advanced');

    % Always visible
    set_field_visible(fig, 'field_vin_min', true);
    set_field_visible(fig, 'field_vin_max', true);
    set_field_visible(fig, 'field_fsw', true);

    % Conditional
    set_field_visible(fig, 'field_diode_vd', meta.show_diode_forward_voltage);
    set_field_visible(fig, 'field_current_ripple', meta.show_current_ripple);

    % Advanced-only
    show_max_duty = meta.show_max_duty_cycle && (~meta.adv_only_max_duty || adv_mode);
    set_field_visible(fig, 'field_max_duty_cycle', show_max_duty);

    % Multi-output support
    if meta.show_n_outputs_spinner
        data = rebuild_output_spec_table(data, meta);
        set_field_visible(fig, 'field_n_outputs', true);
    else
        set_field_visible(fig, 'field_vout', meta.show_output_voltage);
        set_field_visible(fig, 'field_iout', meta.show_output_current);
        set_field_visible(fig, 'field_n_outputs', false);
    end
end
```

---

### 3. `cb_n_outputs_plus()` and `cb_n_outputs_minus()` - UPDATE (Lines 1268-1287)

**Add after incrementing/decrementing:**
```matlab
% OLD (ending at line 1276):
set(data.edit_n_outputs, 'String', num2str(data.n_outputs));
guidata(fig, data);

% NEW:
set(data.edit_n_outputs, 'String', num2str(data.n_outputs));
meta = get_topology_metadata(data.topology);
data = rebuild_output_spec_table(data, meta);
guidata(fig, data);
```

---

### 4. `build_wizard_panel()` - ADD TAGS (Lines 216-472)

**Every control needs a Tag.** Examples:

```matlab
% Vin Min
make_label(spec_panel, 'Input Voltage Min.', [0.02 y 0.35 0.04]);
data.edit_vin_min = make_edit(spec_panel, num2str(data.converter.vin_min), ...
                              [0.38 y 0.20 0.045], @cb_vin_min, ...
                              'field_vin_min');  % ADD TAG
make_label(spec_panel, 'V', [0.59 y 0.05 0.04], 'unit_vin_min');  % ADD TAG

% Topology Dropdown
data.pop_topology = uicontrol('Parent', spec_panel, 'Style', 'popupmenu', ...
                              'String', {...}, ...
                              'Tag', 'field_topology_popup', ...  % ADD TAG
                              'Callback', @cb_topology_changed);
```

**Helper function update:** Modify `make_label()` and `make_edit()` to accept Tag parameter.

---

## File Changes Summary

| File | Action | Lines | Details |
|------|--------|-------|---------|
| topology_wizard.m | ADD | ~1490 | `get_topology_metadata()` |
| topology_wizard.m | ADD | ~1600 | `set_field_visible()` |
| topology_wizard.m | ADD | ~1700 | `rebuild_output_spec_table()` |
| topology_wizard.m | ADD | ~200 | `cb_vout_n()`, `cb_iout_n()` |
| topology_wizard.m | MODIFY | 216-472 | Add Tags to all GUI controls |
| topology_wizard.m | MODIFY | 1197-1233 | Fix guidata timing in `cb_topology_changed()` |
| topology_wizard.m | MODIFY | 1487-1610 | Refactor `update_topology_visibility()` to use metadata |
| topology_wizard.m | MODIFY | 1268-1287 | Update `cb_n_outputs_plus/minus()` to call rebuild |

---

## Data Flow Examples

### Single-Output Topology (Two-Switch Forward)
```
data.converter.vout = 5;           % Single scalar field
data.converter.iout = 10;
data.n_outputs = 1;
data.converter.outputs = [];        % Not used

GUI shows:
[Output Voltage: 5] V
[Output Current: 10] A
(N Outputs spinner is HIDDEN)
```

### Multi-Output Topology (Flyback with N=2)
```
data.n_outputs = 2;
data.converter.vout = [];           % Not used
data.converter.iout = [];
data.converter.outputs(1).voltage = 5;
data.converter.outputs(1).current = 10;
data.converter.outputs(2).voltage = 12;
data.converter.outputs(2).current = 5;

GUI shows:
[N Outputs spinner: 2] +  -
┌──────────────────────────┐
│Output 1  [5 ] V  [10] A  │
│Output 2  [12] V  [5 ] A  │
└──────────────────────────┘
(Standard Vout/Iout fields are HIDDEN)
```

---

## Testing Checklist

### Unit Tests (Per Topology)
- [ ] Two-Switch Forward: Vout/Iout visible, N-outputs hidden, Vd visible
- [ ] Flyback: Vout/Iout visible, N-outputs visible, Max Duty visible (Adv only)
- [ ] Buck: Vout/Iout visible, N-outputs hidden, Ripple visible
- [ ] Boost: Vout/Iout visible, N-outputs hidden, Ripple visible
- [ ] Isolated Buck: Multi-output table appears with N-outputs spinner
- [ ] All topologies: Correct fields visible in Auto vs Advanced mode

### Integration Tests
- [ ] Switch topologies: Old fields hide, new fields show
- [ ] Multi-output creation: Click + to add output row
- [ ] Multi-output cleanup: Delete row when output_index out of range
- [ ] Python JSON: Correct multi-output format sent to generate_om_topology.py

### Edge Cases
- [ ] N-outputs clamping: Set to 5 in Flyback (max=4) → clamped to 4
- [ ] Empty output values: Vout[2] empty in 3-output table → error or default?
- [ ] Tab order: Tab through Vout[1] → Iout[1] → Vout[2] → Iout[2] → ...

---

## Implementation Strategy

**Phase 1 (No Breaking Changes):**
1. Add Tags to all GUI controls
2. Create `get_topology_metadata()` function
3. Create `set_field_visible()` helper

**Phase 2 (Behavior Fix):**
1. Refactor `update_topology_visibility()` to use metadata
2. Fix `cb_topology_changed()` guidata timing

**Phase 3 (Multi-Output):**
1. Create `rebuild_output_spec_table()` function
2. Add `cb_vout_n()` and `cb_iout_n()` callbacks
3. Update `cb_n_outputs_plus/minus()` to trigger rebuild
4. Update `compute_requirements()` and `build_design_spec_wizard()` for multi-output case

**Phase 4 (Testing & Polish):**
1. Test all 9 topologies
2. Test multi-output workflows
3. Verify Python integration

---

## Code Sketch Locations in Design Document

Full code examples are provided in Section 11 of TOPOLOGY_WIZARD_DYNAMIC_VISIBILITY_DESIGN.md:
- 11.1: Complete `get_topology_metadata()` function (all 9 topologies)
- 11.2: Refactored `update_topology_visibility()` with metadata lookup
- 11.3: Updated `cb_topology_changed()` with correct guidata timing

