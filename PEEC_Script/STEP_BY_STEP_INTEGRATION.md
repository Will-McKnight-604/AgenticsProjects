# Step-by-Step Integration Guide

## Prerequisites

- MATLAB R2016a or later (or Octave 5.0+)
- topology_wizard.m file open or ready for editing
- topology_field_visibility_system.m file available
- Text editor or MATLAB IDE

## Step 1: Prepare Files

### Action 1.1: Verify File Location
```bash
# Check that all files are in the same directory
cd c:\Users\Will\proximity_loss\Claude\PEEC_Script\
ls *.m | grep -E "topology_wizard|topology_field_visibility"
```

Expected output:
```
topology_wizard.m
topology_field_visibility_system.m
```

### Action 1.2: Backup Original File
```bash
# Create backup of topology_wizard.m
cp topology_wizard.m topology_wizard.m.backup
```

## Step 2: Add Path Setup

### Action 2.1: Locate main topology_wizard() function

Open `topology_wizard.m` and find the main function (line 10):
```matlab
function topology_wizard()

    close all;

    % ---------- data structure ----------
```

### Action 2.2: Add path setup (after close all;)

Insert the following code right after `close all;`:
```matlab
% Add visibility system functions to path
addpath(fileparts(mfilename('fullpath')));
```

**Example:**
```matlab
function topology_wizard()

    close all;

    % Add visibility system functions to path
    addpath(fileparts(mfilename('fullpath')));

    % ---------- data structure ----------
```

### Verification

Run in MATLAB command window:
```matlab
which get_topology_metadata
% Should output: c:\Users\Will\proximity_loss\Claude\PEEC_Script\topology_field_visibility_system.m
```

## Step 3: Update cb_topology_changed() Callback

### Action 3.1: Locate the callback

Find line ~1197 in topology_wizard.m:
```matlab
function cb_topology_changed(src, ~)
    fig = gcbf();
    data = guidata(fig);

    % Map selection index to topology key
    topology_keys = {'two_switch_forward', ...
```

### Action 3.2: Copy replacement code

From UPDATED_CALLBACKS_EXAMPLE.m, copy the entire `cb_topology_changed()` function

### Action 3.3: Replace in topology_wizard.m

1. Select lines 1197-1233 (entire function)
2. Delete selected lines
3. Paste replacement code

### Action 3.4: Verify replacement

The function should now:
- Map topology index to topology key (unchanged)
- Call `get_topology_metadata(data.topology)` (NEW)
- Call `update_field_visibility(fig, data.topology)` (CHANGED from `update_topology_visibility`)

**Before:**
```matlab
update_topology_visibility(data);
```

**After:**
```matlab
update_field_visibility(fig, data.topology);
```

### Testing
Run MATLAB:
```matlab
topology_wizard
% Select "Flyback" from dropdown
% Verify: Panel title updates, fields show/hide correctly
```

## Step 4: Update cb_n_outputs() Callback

### Action 4.1: Locate the callback

Find line ~1255:
```matlab
function cb_n_outputs(src, ~)
    fig = gcbf();
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val >= 1 && val <= 4
        data.n_outputs = round(val);
    else
        set(src, 'String', num2str(data.n_outputs));
    end
    guidata(fig, data);
end
```

### Action 4.2: Add the rebuild call

Replace entire function with:
```matlab
function cb_n_outputs(src, ~)
    fig = gcbf();
    data = guidata(fig);

    val = str2double(get(src, 'String'));
    if ~isnan(val) && val >= 1 && val <= 4
        data.n_outputs = round(val);
    else
        set(src, 'String', num2str(data.n_outputs));
    end

    % Rebuild output specification table if topology supports multiple outputs
    if ~strcmp(get_topology_output_type(data.topology), 'single')
        rebuild_output_spec_table(fig, data.topology);
    end

    guidata(fig, data);
end
```

### Key Changes
- **Added lines**: 4-6 (the rebuild call)
- **New function call**: `get_topology_output_type()` + `rebuild_output_spec_table()`

### Testing
```matlab
topology_wizard
% Select "Flyback" (multi-output)
% Change N outputs spinner to 2
% Verify: rebuild_output_spec_table() is called (check via breakpoint if needed)
```

## Step 5: Update cb_n_outputs_plus() and cb_n_outputs_minus()

### Action 5.1: Locate cb_n_outputs_plus()

Find line ~1268:
```matlab
function cb_n_outputs_plus(~, ~)
    fig = gcbf();
    data = guidata(fig);
    if data.n_outputs < 4
        data.n_outputs = data.n_outputs + 1;
        set(data.edit_n_outputs, 'String', num2str(data.n_outputs));
    end
    guidata(fig, data);
end
```

### Action 5.2: Replace cb_n_outputs_plus()

```matlab
function cb_n_outputs_plus(~, ~)
    fig = gcbf();
    data = guidata(fig);

    if data.n_outputs < 4
        data.n_outputs = data.n_outputs + 1;
        set(data.edit_n_outputs, 'String', num2str(data.n_outputs));

        % Rebuild output specification table rows
        if ~strcmp(get_topology_output_type(data.topology), 'single')
            rebuild_output_spec_table(fig, data.topology);
        end
    end

    guidata(fig, data);
end
```

### Action 5.3: Replace cb_n_outputs_minus()

Find line ~1279 and replace similarly:
```matlab
function cb_n_outputs_minus(~, ~)
    fig = gcbf();
    data = guidata(fig);

    if data.n_outputs > 1
        data.n_outputs = data.n_outputs - 1;
        set(data.edit_n_outputs, 'String', num2str(data.n_outputs));

        % Rebuild output specification table rows
        if ~strcmp(get_topology_output_type(data.topology), 'single')
            rebuild_output_spec_table(fig, data.topology);
        end
    end

    guidata(fig, data);
end
```

### Testing
```matlab
topology_wizard
% Select "Flyback"
% Click + button to increase N outputs
% Click - button to decrease N outputs
% Verify: No errors, values update correctly
```

## Step 6: Update build_gui() Initialization

### Action 6.1: Locate end of build_gui()

Find the end of build_gui() function (around line 207):
```matlab
    % Default to wizard view
    data.path_selected = 'wizard';
    guidata(fig, data);

end
```

### Action 6.2: Add initialization code BEFORE guidata()

Replace:
```matlab
    % Default to wizard view
    data.path_selected = 'wizard';
    guidata(fig, data);
```

With:
```matlab
    % Default to wizard view
    data.path_selected = 'wizard';

    % Initialize UI handle structure for visibility management
    if ~isfield(data, 'ui_handles')
        data.ui_handles = struct();
        data.ui_handles.fields = struct();
    end

    % Store references to field controls for visibility management
    if isfield(data, 'edit_vin_min')
        data.ui_handles.fields.edit_vin_min = data.edit_vin_min;
    end
    if isfield(data, 'edit_vin_max')
        data.ui_handles.fields.edit_vin_max = data.edit_vin_max;
    end
    if isfield(data, 'edit_vin_nom')
        data.ui_handles.fields.edit_vin_nom = data.edit_vin_nom;
    end
    if isfield(data, 'edit_vout')
        data.ui_handles.fields.edit_vout = data.edit_vout;
    end
    if isfield(data, 'edit_iout')
        data.ui_handles.fields.edit_iout = data.edit_iout;
    end
    if isfield(data, 'edit_fsw')
        data.ui_handles.fields.edit_fsw = data.edit_fsw;
    end
    if isfield(data, 'edit_vd')
        data.ui_handles.fields.edit_vd = data.edit_vd;
    end
    if isfield(data, 'edit_efficiency')
        data.ui_handles.fields.edit_efficiency = data.edit_efficiency;
    end
    if isfield(data, 'edit_ripple')
        data.ui_handles.fields.edit_ripple = data.edit_ripple;
    end
    if isfield(data, 'edit_max_isw')
        data.ui_handles.fields.edit_max_isw = data.edit_max_isw;
    end

    % Initialize field visibility based on default topology
    update_field_visibility(fig, data.topology);

    % Store the updated data structure
    guidata(fig, data);
```

### Key Points
- **Insert BEFORE `guidata(fig, data)`**
- **Initialize all field handles**
- **Call `update_field_visibility()` BEFORE final `guidata()`**

### Testing
```matlab
topology_wizard
% GUI should open with correct field visibility for Two-Switch Forward
% Efficiency field should be hidden (optional)
% Diode voltage drop should be visible (required)
```

## Step 7: Update cb_toggle_optional() Callback

### Action 7.1: Locate the callback

Find line ~932:
```matlab
function cb_toggle_optional(~, ~)
    fig = gcbf();
    data = guidata(fig);

    if isfield(data, 'optional_panel')
        current_vis = get(data.optional_panel, 'Visible');
        if strcmp(current_vis, 'on')
            set(data.optional_panel, 'Visible', 'off');
            data.show_optional = false;
        else
            set(data.optional_panel, 'Visible', 'on');
            data.show_optional = true;
        end
    end

    guidata(fig, data);
end
```

### Action 7.2: Add refresh call and button update

Replace with:
```matlab
function cb_toggle_optional(~, ~)
    fig = gcbf();
    data = guidata(fig);

    if isfield(data, 'optional_panel')
        current_vis = get(data.optional_panel, 'Visible');
        if strcmp(current_vis, 'on')
            set(data.optional_panel, 'Visible', 'off');
            data.show_optional = false;
            set(data.btn_toggle_optional, 'String', 'Show Optional Parameters');
        else
            set(data.optional_panel, 'Visible', 'on');
            data.show_optional = true;
            set(data.btn_toggle_optional, 'String', 'Hide Optional Parameters');
        end
    end

    % Refresh field visibility to ensure optional fields are shown correctly for topology
    update_field_visibility(fig, data.topology);

    guidata(fig, data);
end
```

### Key Changes
- **Added line**: Button label update (2 lines)
- **Added lines**: `update_field_visibility()` call (1 line)

### Testing
```matlab
topology_wizard
% Select "Flyback" topology
% Click "Show Optional Parameters"
% Verify: Only optional fields relevant to Flyback are shown
% Click button again to hide
% Verify: Button label changes
```

## Step 8: Verify All Changes

### Action 8.1: Check for syntax errors

In MATLAB, press Ctrl+Shift+P (or F1 > Check Code):
```matlab
% Open topology_wizard.m and run code analyzer
% Should show 0 errors (warnings OK)
```

### Action 8.2: Run the application

```matlab
topology_wizard
```

### Action 8.3: Test each topology

For each topology:
1. Select from dropdown
2. Verify panel title updates
3. Verify N outputs spinner visibility
4. Verify field visibility
5. Toggle optional parameters
6. Verify correct optional fields shown

**Test sequence:**
```matlab
% In topology_wizard GUI:
% 1. Select "Two-Switch Forward" - should have N outputs spinner
% 2. Select "Buck" - should hide N outputs spinner
% 3. Select "Flyback" - should show efficiency as required
% 4. Select "Boost" - should hide diode voltage drop
% 5. Click "Show Optional Parameters" - only relevant fields
```

### Action 8.4: Test field collection (optional)

In compute callback, add debug print:
```matlab
% In cb_compute_topology(), after calling collect_gui_field_values():
values = collect_gui_field_values(fig, data.topology);
disp('Collected values:');
disp(values);
```

## Step 9: Commit Changes

### Action 9.1: Create backup

```bash
cp topology_wizard.m topology_wizard.m.v2_with_visibility
```

### Action 9.2: Document changes

Create commit message:
```
feat(topology_wizard): implement dynamic field visibility system

- Add topology_field_visibility_system.m with metadata definitions
- Update cb_topology_changed() to use metadata-driven visibility
- Update cb_n_outputs* callbacks to support output table rebuilding
- Add initialization in build_gui() for correct startup state
- Enhance cb_toggle_optional() to refresh field visibility
- All 9 topologies now have topology-specific field visibility
- Supports single and multi-output topology configurations
```

## Step 10: Testing Checklist

- [ ] GUI starts without errors
- [ ] Two-Switch Forward topology selected by default
- [ ] Topology dropdown changes topology (verified by panel title)
- [ ] N outputs spinner visible for isolated topologies (Forward, Flyback, Push-Pull, etc.)
- [ ] N outputs spinner hidden for non-isolated topologies (Buck, Boost)
- [ ] Efficiency field only visible for Flyback (as required field)
- [ ] Optional fields appear when "Show Optional Parameters" clicked
- [ ] Optional fields correct for each topology
- [ ] No debug output or errors in command window
- [ ] Topology can be changed multiple times without issues
- [ ] N outputs spinner can be incremented/decremented
- [ ] "Compute Requirements" button still works
- [ ] "Get Recommendations" button still works
- [ ] All three path buttons (Wizard, MAS Import, Manual) still work

## Troubleshooting

### Issue: "Undefined function or variable 'get_topology_metadata'"

**Cause**: Path not set up correctly

**Solution**:
```matlab
% Option 1: Run in MATLAB working directory
cd c:\Users\Will\proximity_loss\Claude\PEEC_Script\
topology_wizard

% Option 2: Add path manually
addpath('c:\Users\Will\proximity_loss\Claude\PEEC_Script\');
topology_wizard
```

### Issue: Fields don't update when changing topology

**Cause**: `guidata()` called after `update_field_visibility()`

**Solution**: Make sure `guidata(fig, data)` is called BEFORE `update_field_visibility()`

```matlab
% WRONG - field visibility sees old data
guidata(fig, data);
update_field_visibility(fig, data.topology);

% RIGHT - function retrieves updated data
guidata(fig, data);
update_field_visibility(fig, data.topology);
```

### Issue: Optional fields always hidden

**Cause**: `data.show_optional` not being set

**Solution**: Check cb_toggle_optional() sets this variable

```matlab
if strcmp(current_vis, 'on')
    set(data.optional_panel, 'Visible', 'off');
    data.show_optional = false;  % <-- Must set this
else
    set(data.optional_panel, 'Visible', 'on');
    data.show_optional = true;   % <-- Must set this
end
```

### Issue: N outputs spinner always visible

**Cause**: Topology not correctly identified as single-output

**Solution**: Check topology metadata

```matlab
type = get_topology_output_type('buck');
disp(type);  % Should print 'single'
```

## Success Criteria

Implementation is successful when:

1. ✅ GUI launches without errors
2. ✅ Topology dropdown works and updates all UI elements
3. ✅ Field visibility matches topology requirements
4. ✅ N outputs spinner visible only for multi-output topologies
5. ✅ Optional fields show/hide correctly with toggle button
6. ✅ All 9 topologies can be selected without issues
7. ✅ No warnings or errors in MATLAB command window
8. ✅ Compute and recommendations workflows still functional
9. ✅ No performance degradation (GUI still responsive)
10. ✅ Code is maintainable and documented

## Next Steps

After successful integration:

1. **Phase 2**: Implement dynamic output table row management in `rebuild_output_spec_table()`
2. **Phase 3**: Add advanced mode field management
3. **Phase 4**: Implement field validation (topology-aware constraints)
4. **Phase 5**: Add contextual help tooltips

See INTEGRATION_GUIDE_TOPOLOGY_VISIBILITY.md for future enhancement details.
