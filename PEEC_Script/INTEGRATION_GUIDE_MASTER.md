# Master Integration Guide: Data-Driven Topology Wizard

**Date**: 2026-02-27
**Status**: Ready for Integration
**Estimated Implementation Time**: 2-3 hours

---

## Overview

This guide brings together all components created by sub-agents to transform `topology_wizard.m` from a static, hand-coded-equation GUI into a **data-driven system that collects topology-specific inputs and passes them directly to PyOpenMagnetics APIs**.

### What Changed

| Aspect | Before | After |
|--------|--------|-------|
| **Architecture** | GUI → generate_om_topology.py (hand-coded equations) | GUI → build_mas_structure.m → call_pyopenmagnetics_api.py → PyOpenMagnetics APIs |
| **Topology Support** | Only "Two-Switch Forward" | All 9 topologies with dynamic field visibility |
| **Field Visibility** | Static (same fields for all topologies) | **Dynamic** (fields show/hide based on topology) |
| **Output Types** | Hardcoded single-output | Supports both single-output (Buck/Boost) and multi-output (Forward/Flyback/etc.) |
| **Computation** | Local Python equations | PyOpenMagnetics adviser (authoritative source) |
| **Results** | Lm, duty, turns only | Full core/wire recommendations with losses, temps, scoring |

---

## Files Created by Sub-Agents

### Core Implementation (3 MATLAB files)

| File | Purpose | Lines | Agent |
|------|---------|-------|-------|
| **topology_metadata.m** | Registry of all 9 topologies + 27 fields with metadata | 387 | afda499 |
| **topology_field_visibility_system.m** | Dynamic field visibility, value collection, output table management | 750 | a4ff721 |
| **build_mas_structure.m** | Convert GUI parameters to MAS JSON format | 350 | ad981f3 |

### Python Bridge (1 Python file)

| File | Purpose | Lines | Agent |
|------|---------|-------|-------|
| **call_pyopenmagnetics_api.py** | Call PyOpenMagnetics adviser, return results | 280 | ad981f3 |

### Testing & Documentation (8+ files)

| File | Purpose |
|------|---------|
| **test_topology_metadata.m** | Validates all topology definitions |
| **test_mas_api_workflow.m** | Tests MAS builder and API integration |
| **TOPOLOGY_INPUTS_MAPPING.md** | Detailed input requirements per topology |
| + 5+ other documentation files | Integration guides, examples, references |

---

## Integration Checklist

### Phase 1: Verify Installation ✓
- [x] All files created in `c:\Users\Will\proximity_loss\Claude\PEEC_Script\`
- [x] MATLAB functions readable and syntactically valid
- [x] Python script executable

### Phase 2: Test Individual Components (30 min)

**Step 1**: Test topology metadata system
```matlab
cd c:\Users\Will\proximity_loss\Claude\PEEC_Script
test_topology_metadata  % Should show all tests PASSED
```

**Step 2**: Test MAS builder
```matlab
% Create sample GUI data
gui_data = struct();
gui_data.vin_min = 100;
gui_data.vin_max = 190;
gui_data.vin_nom = [];
gui_data.vout = 5;
gui_data.iout = 5;
gui_data.fsw_khz = 200;
gui_data.efficiency = 90;
gui_data.vd = 0.7;
gui_data.max_ripple = 30;
gui_data.ambient_temp = 25;

% Build MAS structure
mas = build_mas_structure(gui_data, 'two_switch_forward');
disp(mas);  % Should show proper structure
```

**Step 3**: Test PyOpenMagnetics API
```matlab
% Write test input
test_input = build_mas_structure(gui_data, 'two_switch_forward');
writematrix(jsonencode(test_input), 'test_input.json', 'FileType', 'text');

% Call Python script
[status, output] = system('python call_pyopenmagnetics_api.py test_input.json test_output.json');
disp(['Status: ' num2str(status)]);

% Read results
if status == 0
  results = jsondecode(fileread('test_output.json'));
  disp(results);  % Should show OK status + results
end
```

### Phase 3: Integrate into topology_wizard.m (1.5-2 hours)

#### 3.1 Add Topology Dropdown (if not present)

In `build_gui()` function, add topology selector with all 9 options:

```matlab
% Around line 200, add topology dropdown
topology_names = {
  'Two-Switch Forward', 'Single-Switch Forward', 'Active Clamp Forward', ...
  'Flyback', 'Push-Pull', 'Buck', 'Boost', 'Isolated Buck', 'Isolated Buck-Boost'
};
topology_keys = {
  'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', ...
  'flyback', 'push_pull', 'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'
};

data.ui.topology_dropdown = uicontrol('Parent', spec_panel, ...
  'Style', 'popupmenu', ...
  'String', topology_names, ...
  'Value', 1, ...
  'Units', 'normalized', ...
  'Position', [0.1 0.85 0.35 0.04], ...
  'Callback', {@cb_topology_changed, fig});

data.topology_keys = topology_keys;
```

#### 3.2 Add Field Visibility Callback

Replace or enhance `cb_topology_changed()`:

```matlab
function cb_topology_changed(hObject, eventdata, fig)
  data = guidata(fig);
  idx = get(hObject, 'Value');
  data.topology = data.topology_keys{idx};

  % Update field visibility based on topology
  update_field_visibility(fig, data.topology);

  guidata(fig, data);
end
```

#### 3.3 Add Dynamic Field Visibility Function

From `topology_field_visibility_system.m`, integrate the visibility update logic:

```matlab
function update_field_visibility(fig, topology_key)
  data = guidata(fig);

  % Get metadata for this topology
  topo_meta = get_topology_metadata(topology_key);

  % Show required fields
  for i = 1:length(topo_meta.required_fields)
    field_name = topo_meta.required_fields{i};
    if isfield(data.ui, field_name)
      set(data.ui.(field_name), 'Visible', 'on');
    end
  end

  % Hide optional fields if not toggled
  for i = 1:length(topo_meta.optional_fields)
    field_name = topo_meta.optional_fields{i};
    if isfield(data.ui, field_name)
      if ~data.show_optional
        set(data.ui.(field_name), 'Visible', 'off');
      else
        set(data.ui.(field_name), 'Visible', 'on');
      end
    end
  end

  % Show/hide N outputs spinner based on output type
  output_type = get_topology_output_type(topology_key);
  if strcmp(output_type, 'multi')
    set(data.ui.n_outputs_spinner, 'Visible', 'on');
  else
    set(data.ui.n_outputs_spinner, 'Visible', 'off');
  end

  % Update output specification table
  rebuild_output_spec_table(fig, topology_key);

  % Update requirements display title
  set(data.ui.req_title, 'String', ...
    sprintf('--- %s Design Requirements ---', topo_meta.display_name));

  guidata(fig, data);
end
```

#### 3.4 Add Output Specification Table (Multi-Output Support)

```matlab
function rebuild_output_spec_table(fig, topology_key)
  data = guidata(fig);

  output_type = get_topology_output_type(topology_key);

  if strcmp(output_type, 'single')
    % Single output (Buck/Boost): One row
    set(data.ui.output1_label, 'String', 'Output:');
    set(data.ui.output2_label, 'Visible', 'off');
    set(data.ui.output3_label, 'Visible', 'off');
    set(data.ui.output4_label, 'Visible', 'off');
  else
    % Multi-output: Show N rows based on n_outputs spinner
    n_outputs = str2double(get(data.ui.n_outputs_spinner, 'String'));
    for i = 1:4
      if i <= n_outputs
        set(data.ui.(sprintf('output%d_label', i)), 'Visible', 'on');
        set(data.ui.(sprintf('output%d_label', i)), ...
          'String', sprintf('Output %d:', i));
      else
        set(data.ui.(sprintf('output%d_label', i)), 'Visible', 'off');
      end
    end
  end

  guidata(fig, data);
end
```

#### 3.5 Add Input Collection & API Call

Create new callback for "Compute Requirements" button:

```matlab
function cb_compute_requirements(hObject, eventdata, fig)
  data = guidata(fig);

  try
    % Step 1: Collect GUI values
    gui_values = collect_gui_field_values(fig, data.topology);

    % Step 2: Build MAS structure
    mas_struct = build_mas_structure(gui_values, data.topology);

    % Step 3: Write MAS to JSON file
    config_file = fullfile(pwd(), 'om_topology_api_config.json');
    writematrix(jsonencode(mas_struct), config_file, 'FileType', 'text');

    fprintf('[TOPOLOGY] MAS config written to: %s\n', config_file);

    % Step 4: Call Python API
    result_file = fullfile(pwd(), 'om_topology_api_results.json');
    python_script = fullfile(pwd(), 'call_pyopenmagnetics_api.py');

    cmd = sprintf('python "%s" "%s" "%s"', python_script, config_file, result_file);
    fprintf('[TOPOLOGY] Calling: %s\n', cmd);
    [status, output] = system(cmd);

    if status ~= 0
      errordlg(sprintf('Python API call failed:\n%s', output), 'API Error');
      return;
    end

    % Step 5: Read results
    if isfile(result_file)
      results = jsondecode(fileread(result_file));

      if strcmp(results.status, 'OK')
        % Store results
        data.api_results = results;

        % Display results in recommendations panel
        display_api_results(fig, results);

        fprintf('[TOPOLOGY] API returned %d recommendations\n', results.count);
      else
        errordlg(sprintf('API Error: %s', results.error), 'API Error');
      end
    end

    guidata(fig, data);

  catch ME
    errordlg(sprintf('Error: %s', ME.message), 'Computation Error');
  end
end
```

#### 3.6 Add Helper: Collect GUI Field Values

```matlab
function gui_values = collect_gui_field_values(fig, topology_key)
  data = guidata(fig);

  [required_fields, optional_fields] = get_visible_fields_for_topology(topology_key);
  all_fields = [required_fields, optional_fields];

  gui_values = struct();

  % Core fields
  gui_values.vin_min = str2double(get(data.ui.vin_min, 'String'));
  gui_values.vin_max = str2double(get(data.ui.vin_max, 'String'));
  vin_nom_str = get(data.ui.vin_nom, 'String');
  gui_values.vin_nom = [];
  if ~isempty(vin_nom_str) && ~strcmpi(vin_nom_str, '')
    gui_values.vin_nom = str2double(vin_nom_str);
  end

  gui_values.vout = str2double(get(data.ui.vout, 'String'));
  gui_values.iout = str2double(get(data.ui.iout, 'String'));
  gui_values.fsw_khz = str2double(get(data.ui.fsw, 'String'));
  gui_values.vd = str2double(get(data.ui.vd, 'String'));
  gui_values.max_ripple = str2double(get(data.ui.ripple, 'String'));
  gui_values.efficiency = str2double(get(data.ui.efficiency, 'String'));
  gui_values.ambient_temp = str2double(get(data.ui.ambient_temp, 'String'));

  % Conditional fields
  if isfield(data.ui, 'max_switch_current') && get(data.ui.max_switch_current, 'Visible')
    gui_values.max_switch_current = str2double(get(data.ui.max_switch_current, 'String'));
  end

  if isfield(data.ui, 'max_duty') && get(data.ui.max_duty, 'Visible')
    gui_values.max_duty = str2double(get(data.ui.max_duty, 'String'));
  end

  % Multi-output fields
  output_type = get_topology_output_type(topology_key);
  if strcmp(output_type, 'multi')
    n_outputs = str2double(get(data.ui.n_outputs_spinner, 'String'));
    gui_values.output_voltages = [];
    gui_values.output_currents = [];
    for i = 1:n_outputs
      v_str = get(data.ui.(sprintf('output%d_v', i)), 'String');
      i_str = get(data.ui.(sprintf('output%d_i', i)), 'String');
      gui_values.output_voltages = [gui_values.output_voltages, str2double(v_str)];
      gui_values.output_currents = [gui_values.output_currents, str2double(i_str)];
    end
  else
    gui_values.output_voltages = [str2double(get(data.ui.vout, 'String'))];
    gui_values.output_currents = [str2double(get(data.ui.iout, 'String'))];
  end

  gui_values.topology = topology_key;
end
```

#### 3.7 Add Display Results Function

```matlab
function display_api_results(fig, results)
  data = guidata(fig);

  % Clear previous results
  cla(data.ax_results);

  if isempty(results.data) || results.count == 0
    text(data.ax_results, 0.5, 0.5, 'No results returned', ...
      'HorizontalAlignment', 'center', 'FontSize', 12);
    return;
  end

  % Display top 5 results as selectable options
  y_pos = 0.95;
  for i = 1:min(5, results.count)
    design = results.data(i);

    % Extract info
    core_name = 'Unknown core';
    if isfield(design, 'core_name')
      core_name = design.core_name;
    end

    losses_str = '';
    if isfield(design, 'losses')
      losses = design.losses;
      if isfield(losses, 'total')
        losses_str = sprintf(' | Losses: %.2f W', losses.total);
      end
    end

    result_str = sprintf('[%d] %s%s', i, core_name, losses_str);

    % Create selectable button
    uicontrol('Parent', fig, ...
      'Style', 'pushbutton', ...
      'String', result_str, ...
      'Units', 'normalized', ...
      'Position', [0.05 y_pos-0.05*i 0.9 0.04], ...
      'Callback', {@cb_select_design, i, fig});

    y_pos = y_pos - 0.06;
  end

  guidata(fig, data);
end
```

### Phase 4: Testing (30 min)

#### Test 1: Dynamic Field Visibility
- [ ] Open topology_wizard.m
- [ ] Select "Two-Switch Forward" → verify Duty Cycle field appears
- [ ] Select "Flyback" → verify Max Duty Cycle field appears (not plain duty)
- [ ] Select "Buck" → verify N outputs spinner hidden, single output row shown
- [ ] Select "Isolated Buck" → verify N outputs spinner visible

#### Test 2: Multi-Output
- [ ] Select "Two-Switch Forward" → set N outputs to 3
- [ ] Verify Output 1, 2, 3 rows appear with separate V/I inputs
- [ ] Enter values for all 3 outputs
- [ ] Click Compute

#### Test 3: API Integration
- [ ] Compute requirements for "Two-Switch Forward" (100-190V, 5V/5A, 200kHz)
- [ ] Verify MAS JSON file created (`om_topology_api_config.json`)
- [ ] Verify results JSON file created (`om_topology_api_results.json`)
- [ ] Verify results show cores, losses, temperatures
- [ ] Repeat for Flyback, Buck, Isolated Buck

#### Test 4: Error Handling
- [ ] Try to compute with invalid values (negative voltage) → should show error
- [ ] Try with Python not installed → should show helpful error
- [ ] Try with invalid topology → should handle gracefully

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    topology_wizard.m                        │
│                                                             │
│  Topology Dropdown: [Flyback ▼]                            │
│  Design Mode: (●) Auto  ( ) Advanced                       │
│  ────────────────────────────────────────────────────────  │
│  Input Voltage Min: [100] V                                │
│  Input Voltage Max: [190] V                                │
│  Current Ripple %: [30] %                                  │
│  Efficiency: [90] % (required for Flyback)                │
│  Max Duty Cycle: [____] %  (optional)                     │
│  Max Drain-Source Voltage: [____] V  (optional)           │
│  ────────────────────────────────────────────────────────  │
│  Number of Outputs: [1] [↑↓]                              │
│  ────────────────────────────────────────────────────────  │
│  Output 1: Voltage [5.0] V    Current [5.0] A             │
│  Output 2: Voltage [3.3] V    Current [2.0] A             │
│                                                             │
│  [Compute Requirements] [Get Recommendations]              │
└────────────────────────┬────────────────────────────────────┘
                         │ collect_gui_field_values()
                         │ build_mas_structure()
                         ↓
             ┌─────────────────────────┐
             │  om_topology_api_      │
             │  config.json (MAS)     │
             │  {                     │
             │    inputs: {           │
             │      designRequirements│
             │      operatingPoints[] │
             │    }                   │
             │  }                     │
             └────────────┬────────────┘
                          │
                    [Python Script]
                          │
                          ↓
          call_pyopenmagnetics_api.py
                          │
         ┌────────────────┴────────────────┐
         │                                 │
         ↓                                 ↓
   pm.process_inputs()         pm.calculate_advised_magnetics()
   (validate, enrich)          (run adviser, get recommendations)
         │                                 │
         └────────────────┬────────────────┘
                          │
                          ↓
             ┌─────────────────────────┐
             │ om_topology_api_       │
             │ results.json           │
             │ {                      │
             │   status: "OK"         │
             │   count: 5             │
             │   data: [{             │
             │     core: {...}        │
             │     losses: {...}      │
             │     temperature: {...} │
             │   }, ...]              │
             │ }                      │
             └────────────┬────────────┘
                          │
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  display_api_results()                                      │
│  ────────────────────────────────────────────────────────  │
│  [1] EI32-Magmatite | Losses: 2.34W | Score: 0.89          │
│  [2] PQ32-Magmatite | Losses: 2.51W | Score: 0.87          │
│  [3] EI33-Magmatite | Losses: 2.45W | Score: 0.85          │
│  [4] PQ33-Magmatite | Losses: 2.62W | Score: 0.83          │
│  [5] EI35-Magmatite | Losses: 2.78W | Score: 0.81          │
│                                                             │
│  [Select Design #1]                                        │
│                                                             │
│  → interactive_winding_designer(design_spec)               │
└─────────────────────────────────────────────────────────────┘
```

---

## File Dependencies

```
topology_wizard.m (GUI)
  ├─ topology_metadata.m (provide metadata)
  ├─ get_topology_metadata.m (lookup topology def)
  ├─ get_visible_fields_for_topology.m (field lists)
  ├─ get_topology_output_type.m (output type check)
  ├─ topology_field_visibility_system.m (field mgmt functions)
  ├─ build_mas_structure.m (convert GUI → MAS)
  │   └─ [uses field metadata for MAS path mapping]
  │
  └─ call_pyopenmagnetics_api.py (Python API wrapper)
       ├─ pm.process_inputs() [PyOpenMagnetics]
       └─ pm.calculate_advised_magnetics() [PyOpenMagnetics]

interactive_winding_designer.m
  └─ [receives design_spec from topology_wizard.m]
```

---

## Rollback Plan

If integration breaks existing functionality:

1. **Keep backup of original topology_wizard.m**:
   ```bash
   cp topology_wizard.m topology_wizard.m.backup.2026-02-27
   ```

2. **If GUI callbacks fail**:
   - Remove the new `cb_topology_changed()` and `cb_compute_requirements()` callbacks
   - Keep `compute_requirements()` function for backward compatibility
   - Revert to hardcoded topology selection

3. **If API calls fail**:
   - Check PyOpenMagnetics installation: `python -c "import PyOpenMagnetics"`
   - Verify Python fallback chain is working
   - Check file permissions for JSON I/O

4. **Complete rollback**:
   ```bash
   cp topology_wizard.m.backup.2026-02-27 topology_wizard.m
   rm build_mas_structure.m call_pyopenmagnetics_api.py
   # Keep metadata functions (they're additive, non-breaking)
   ```

---

## Success Criteria

After integration is complete, verify:

- [ ] All 9 topologies selectable from dropdown
- [ ] Field visibility changes dynamically when topology changes
- [ ] Multi-output topologies show N outputs spinner and dynamic output rows
- [ ] Single-output topologies (Buck/Boost) hide N outputs spinner
- [ ] "Compute Requirements" button collects GUI values without errors
- [ ] MAS JSON files created successfully in working directory
- [ ] Python script executes without errors
- [ ] Results JSON files created with status='OK' and design recommendations
- [ ] Top 5 core recommendations displayed in GUI
- [ ] No errors in MATLAB Command Window
- [ ] Can proceed to interactive_winding_designer.m with pre-selected design

---

## Next Steps After Integration

1. **Implement design selection**: Add callbacks to select each result → pre-populate interactive_winding_designer.m
2. **Add insulation support**: Extend GUI to collect IEC standards (radio buttons for 4 standards)
3. **Add constraint inputs**: Allow user to specify max size, max cost, efficiency targets
4. **Add waveform preview**: Display converter waveforms from API results in topology wizard
5. **Add batch optimization**: Run multiple topologies in parallel, compare results
6. **Update MEMORY.md**: Document final architecture and lessons learned

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| PyOpenMagnetics not found | Install: `pip install PyOpenMagnetics` or use Python 3.11 |
| "Unknown topology key" error | Check topology dropdown lists match keys in topology_metadata.m |
| MAS JSON file not created | Check file permissions, verify build_mas_structure.m runs |
| API returns ERROR status | Check error message in results JSON, verify inputs |
| Results panel is empty | Verify results.count > 0 and results.data is array |
| MATLAB crashes on GUI update | Check Visible property assignments, verify handle validity |

---

## Support

For issues or questions:
1. Check generated log files: `om_topology_api_config.json`, `om_topology_api_results.json`
2. Review diagnostic output in MATLAB Command Window (lines with `[TOPOLOGY]` prefix)
3. Consult sub-agent documentation files:
   - `TOPOLOGY_INPUTS_MAPPING.md` - Input requirements
   - `MAS_API_INTEGRATION.md` - API details
   - `INTEGRATION_EXAMPLE.m` - Code examples
4. Run unit tests: `test_topology_metadata()`, `test_mas_api_workflow()`

---

**Last Updated**: 2026-02-27
**Integration Status**: Ready for Phase 3
**Estimated Total Time**: 2-3 hours
