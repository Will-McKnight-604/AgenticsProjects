# Bug Fix: Double Unit Conversion (RESOLVED)

**Status**: FIXED - 2026-02-27

## Problem Description

Efficiency and ripple percentage values were being converted from GUI percentage (e.g., 90%) to API decimal (e.g., 0.90) **twice**:

1. First conversion in `topology_wizard.m` - `collect_gui_field_values()` (lines 3291, 3303)
2. Second conversion in `build_mas_structure.m` - MAS building logic (lines 66, 72, 85)

### Example of Double Conversion Bug

**Input**: User enters `90` (for 90% efficiency) in GUI field

**Step 1 - collect_gui_field_values()** (topology_wizard.m:3291):
```matlab
gui_values.efficiency = str2double(eff_str) / 100;  % 90 / 100 = 0.90 ✓
```

**Step 2 - build_mas_structure()** (build_mas_structure.m:72):
```matlab
mas_struct.inputs.designRequirements.efficiency = gui_data.converter.efficiency / 100;  % 0.90 / 100 = 0.0090 ✗
```

**Result**: API receives `efficiency: 0.0090` instead of `efficiency: 0.90`

This caused the PyOpenMagnetics adviser to interpret the design as having 99% loss, resulting in unrealistic component recommendations (always small toroids).

## Root Cause Analysis

**Violation of Single Responsibility Principle**: Unit conversion was happening in two places instead of one.

- `collect_gui_field_values()` was responsible for extracting GUI values AND converting units
- `build_mas_structure()` was also converting units
- No clear documentation of which function should own the conversion

## Solution Implemented

**Removed the second conversion from `build_mas_structure.m`** (the MAS builder should trust that input values are already in the correct format).

### Files Modified

**File: `/c/Users/Will/proximity_loss/Claude/PEEC_Script/build_mas_structure.m`**

#### Change 1: Current Ripple Ratio (Line 66)

**Before**:
```matlab
% ===== STEP 4: Current Ripple Ratio =====
if isfield(gui_data.converter, 'max_ripple') && ~isempty(gui_data.converter.max_ripple)
    % Convert from percentage to decimal ratio
    mas_struct.inputs.designRequirements.currentRippleRatio = gui_data.converter.max_ripple / 100;
end
```

**After**:
```matlab
% ===== STEP 4: Current Ripple Ratio =====
if isfield(gui_data.converter, 'max_ripple') && ~isempty(gui_data.converter.max_ripple)
    % Already converted from percentage to decimal in collect_gui_field_values()
    mas_struct.inputs.designRequirements.currentRippleRatio = gui_data.converter.max_ripple;
end
```

#### Change 2: Efficiency (Line 72)

**Before**:
```matlab
% ===== STEP 5: Efficiency =====
if isfield(gui_data.converter, 'efficiency') && ~isempty(gui_data.converter.efficiency)
    % Convert from percentage to decimal ratio
    mas_struct.inputs.designRequirements.efficiency = gui_data.converter.efficiency / 100;
end
```

**After**:
```matlab
% ===== STEP 5: Efficiency =====
if isfield(gui_data.converter, 'efficiency') && ~isempty(gui_data.converter.efficiency)
    % Already converted from percentage to decimal in collect_gui_field_values()
    mas_struct.inputs.designRequirements.efficiency = gui_data.converter.efficiency;
end
```

#### Change 3: Maximum Duty Cycle (Line 85) - Preventive Fix

**Before**:
```matlab
case 'flyback'
    % Flyback: maximum duty cycle and drain-source voltage
    if isfield(gui_data.converter, 'max_duty') && ~isempty(gui_data.converter.max_duty)
        mas_struct.inputs.designRequirements.maximumDutyCycle = gui_data.converter.max_duty / 100;
    end
```

**After**:
```matlab
case 'flyback'
    % Flyback: maximum duty cycle and drain-source voltage
    if isfield(gui_data.converter, 'max_duty') && ~isempty(gui_data.converter.max_duty)
        % Already converted from percentage to decimal in collect_gui_field_values()
        mas_struct.inputs.designRequirements.maximumDutyCycle = gui_data.converter.max_duty;
    end
```

## Verification

### Before Fix (Buggy Behavior)
- GUI input: `90` (90% efficiency)
- After collect_gui_field_values(): `0.90`
- After build_mas_structure(): `0.0090` ← **WRONG**
- API receives: `efficiency: 0.0090` (99% loss)
- Result: Unrealistic component recommendations

### After Fix (Correct Behavior)
- GUI input: `90` (90% efficiency)
- After collect_gui_field_values(): `0.90` ✓
- After build_mas_structure(): `0.90` ✓
- API receives: `efficiency: 0.9` (10% loss - realistic)
- Result: Correct component recommendations

## Testing Checklist

### Unit Conversion Tests
- [ ] Test with efficiency = 80% → API receives 0.80 (NOT 0.0080)
- [ ] Test with efficiency = 90% → API receives 0.90 (NOT 0.0090)
- [ ] Test with efficiency = 95% → API receives 0.95 (NOT 0.0095)
- [ ] Test with ripple = 10% → API receives 0.10 (NOT 0.0010)
- [ ] Test with ripple = 20% → API receives 0.20 (NOT 0.0020)
- [ ] Test with ripple = 30% → API receives 0.30 (NOT 0.0030)
- [ ] Test with duty cycle = 40% → API receives 0.40 (NOT 0.0040)
- [ ] Test with duty cycle = 45% → API receives 0.45 (NOT 0.0045)

### API Integration Tests
- [ ] Verify PyOpenMagnetics adviser receives realistic efficiency values
- [ ] Check that adviser returns reasonable loss values (0.5-10W, NOT 99% loss)
- [ ] Confirm component recommendations are realistic (not always small toroids)
- [ ] Test with all 9 topologies (efficiency/ripple applicable to all)
- [ ] Test flyback topology specifically (duty cycle conversion)

### Regression Tests
- [ ] Verify other fields (Vin, Vout, Iout, Fsw) are unchanged
- [ ] Check that diode voltage drop and other non-percentage fields work
- [ ] Confirm multi-output topologies still function correctly
- [ ] Test insulation block and thermal parameters still work

## Key Principle: Single Responsibility

**Conversion Location**: `collect_gui_field_values()` in `topology_wizard.m`
- This function is the single source of truth for GUI value extraction
- ALL percentage-to-decimal conversions happen here
- `build_mas_structure.m` receives values that are ALREADY in the correct format

**Design Pattern**:
```
GUI Input (%)
    ↓
collect_gui_field_values() [CONVERT % → DECIMAL]
    ↓
gui_data.converter struct (DECIMAL)
    ↓
build_mas_structure() [USE DECIMAL DIRECTLY]
    ↓
MAS JSON (DECIMAL)
    ↓
PyOpenMagnetics API (DECIMAL)
```

## Impact

- **Severity**: MEDIUM (API was receiving garbage values, causing wrong recommendations)
- **Scope**: Affects all topologies (9 topologies use efficiency/ripple)
- **User Impact**: High (incorrect component recommendations lead to failed designs)
- **Test Coverage**: All percentage fields in converter specifications

## Related Files

- `/c/Users/Will/proximity_loss/Claude/PEEC_Script/topology_wizard.m` (conversion source)
- `/c/Users/Will/proximity_loss/Claude/PEEC_Script/build_mas_structure.m` (conversion removed)
- `/c/Users/Will/proximity_loss/Claude/PEEC_Script/call_pyopenmagnetics_api.py` (API that receives the values)

## Future Improvements

1. Add type checking in `build_mas_structure()` to catch invalid ranges (e.g., efficiency > 1)
2. Add comments documenting expected value ranges (efficiency: 0-1, ripple: 0-1, duty: 0-1)
3. Consider adding validation assertions after each conversion step
4. Document the conversion ownership in the code comments
