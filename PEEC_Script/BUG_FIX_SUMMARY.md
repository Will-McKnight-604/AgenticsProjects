# Bug Fix Summary: Unit Conversion & Test Script Issues

## Date: 2026-02-27
## Fixes: Bug 1 (MEDIUM) and Bug 5 (LOW)

---

## Bug 1: Double Unit Conversion (MEDIUM Priority)

### Root Cause
Efficiency and ripple percentage values were being converted twice:
1. **First conversion** (REMOVED): `collect_gui_field_values()` in `topology_wizard.m` divided by 100 (90% → 0.90)
2. **Second conversion** (KEPT): `build_mas_structure.m` divided by 100 again (0.90 → 0.0090)

This resulted in the MAS JSON receiving 0.009 instead of 0.9 for efficiency, causing PyOpenMagnetics adviser to receive incorrect input (0.9% efficiency instead of 90%).

### Files Modified
- **`topology_wizard.m` (Lines 3287-3309)**
  - Removed `/100` division from `gui_values.efficiency` (line 3291)
  - Removed `/100` division from `gui_values.max_ripple` (line 3303)
  - Updated comments to indicate values stay as percentages

- **`build_mas_structure.m` (Lines 63-73)**
  - Added `/100` division to `currentRippleRatio` (line 66)
  - Added `/100` division to `efficiency` (line 72)
  - Updated comments to indicate this is the "single source of truth" for conversion

### Before Fix
```matlab
% topology_wizard.m - collect_gui_field_values()
gui_values.efficiency = str2double(eff_str) / 100;  % 90 -> 0.90
gui_values.max_ripple = str2double(ripple_str) / 100;  % 30 -> 0.30

% build_mas_structure.m
mas_struct.inputs.designRequirements.efficiency = gui_data.converter.efficiency;  % 0.90 -> 0.0090 (WRONG!)
mas_struct.inputs.designRequirements.currentRippleRatio = gui_data.converter.max_ripple;  % 0.30 -> 0.003 (WRONG!)
```

### After Fix
```matlab
% topology_wizard.m - collect_gui_field_values()
gui_values.efficiency = str2double(eff_str);  % 90 stays as 90
gui_values.max_ripple = str2double(ripple_str);  % 30 stays as 30

% build_mas_structure.m
mas_struct.inputs.designRequirements.efficiency = gui_data.converter.efficiency / 100;  % 90 -> 0.9 (CORRECT)
mas_struct.inputs.designRequirements.currentRippleRatio = gui_data.converter.max_ripple / 100;  % 30 -> 0.3 (CORRECT)
```

### Expected Behavior After Fix
- User enters efficiency: 90 (percent) in GUI
- `collect_gui_field_values()` stores: 90 (no conversion)
- `build_mas_structure()` converts: 90 → 0.9 (decimal)
- MAS JSON receives: 0.9 (correct format for PyOpenMagnetics)
- Result: Adviser recommends correctly-sized components for 90% efficiency

---

## Bug 5: Test Script Field Name Error (LOW Priority)

### Root Cause
The test script `test_mas_api_workflow.m` accesses output voltage using singular field name `outputVoltage`, but the two-switch-forward converter is a multi-output topology that uses plural field names `outputVoltages` and `outputCurrents` (arrays).

This caused the test to fail on line 62 with a field access error for multi-output topologies.

### File Modified
- **`test_mas_api_workflow.m` (Lines 61-71)**
  - Added conditional check using `isfield()` to detect field name format
  - If multi-output fields exist (`outputVoltages`), use them and access first element
  - If single-output fields exist (`outputVoltage`), use them as scalars

### Before Fix
```matlab
fprintf('  Output: %.1f V @ %.1f A\n', ...
    mas.inputs.operatingPoints{1}.outputVoltage, ...  % ERROR: field doesn't exist for multi-output
    mas.inputs.operatingPoints{1}.outputCurrent);
```

### After Fix
```matlab
% Handle both single-output and multi-output topologies
if isfield(mas.inputs.operatingPoints{1}, 'outputVoltages')
    fprintf('  Output: %.1f V @ %.1f A\n', ...
        mas.inputs.operatingPoints{1}.outputVoltages(1), ...  % Access first element of array
        mas.inputs.operatingPoints{1}.outputCurrents(1));
else
    fprintf('  Output: %.1f V @ %.1f A\n', ...
        mas.inputs.operatingPoints{1}.outputVoltage, ...  % Scalar field
        mas.inputs.operatingPoints{1}.outputCurrent);
end
```

### Expected Behavior After Fix
- Test script TEST 1 (Two-Switch Forward - multi-output): Uses `outputVoltages(1)` and `outputCurrents(1)`
- Test script TEST 4 (Buck - single-output): Uses `outputVoltage` and `outputCurrent`
- Both test cases complete without field access errors

---

## Verification

A verification script has been created: **`verify_unit_conversion.m`**

This script tests:
1. ✓ Efficiency correctly converted from 90 (percent) to 0.9 (decimal)
2. ✓ Ripple correctly converted from 30 (percent) to 0.3 (decimal)
3. ✓ Multi-output topology (Two-Switch Forward) uses `outputVoltages` (plural, array)
4. ✓ Single-output topology (Buck) uses `outputVoltage` (singular, scalar)

Run the verification:
```matlab
verify_unit_conversion
```

Expected output:
```
✓ BUG 1 FIX VERIFIED: Efficiency correctly converted to 0.9 (not 0.009 or 90)
✓ BUG 1 FIX VERIFIED: Ripple correctly converted to 0.3 (not 0.003 or 30)
✓ BUG 5 FIX VERIFIED: Multi-output topology uses outputVoltages (plural)
✓ Single-output topology uses outputVoltage (singular)
```

---

## Architecture Notes

### Unit Conversion Strategy (Bug 1 Fix)
- **Data Flow**: GUI (percent) → `collect_gui_field_values()` (percent) → `build_mas_structure()` (decimal) → JSON (decimal)
- **Single Source of Truth**: All percentage-to-decimal conversions happen in `build_mas_structure.m` only
- **Advantage**: If conversion logic needs to change in future, only one place to update

### Multi-Topology Support (Bug 5 Fix)
- **Topology Classification** (from `build_mas_structure.m`):
  - **Multi-output**: `two_switch_forward`, `single_switch_forward`, `active_clamp_forward`, `flyback`, `push_pull`, `isolated_buck`, `isolated_buck_boost`
  - **Single-output**: `buck`, `boost`
- **Field Names**:
  - Multi-output: `outputVoltages` (array), `outputCurrents` (array)
  - Single-output: `outputVoltage` (scalar), `outputCurrent` (scalar)
- **Test Script**: Now robust to both field formats

---

## Summary of Changes

| File | Lines | Change | Type |
|------|-------|--------|------|
| `topology_wizard.m` | 3291 | Remove `/100` from efficiency | Bug Fix 1 |
| `topology_wizard.m` | 3303 | Remove `/100` from ripple | Bug Fix 1 |
| `build_mas_structure.m` | 66 | Add `/100` to ripple | Bug Fix 1 |
| `build_mas_structure.m` | 72 | Add `/100` to efficiency | Bug Fix 1 |
| `test_mas_api_workflow.m` | 61-71 | Add conditional field check | Bug Fix 5 |
| `verify_unit_conversion.m` | NEW | Verification script | Testing |

---

## Impact Analysis

### Bug 1 Impact
- **Severity**: MEDIUM (causes incorrect adviser recommendations)
- **User-Visible**: Yes (wrong component recommendations from PyOpenMagnetics)
- **Scope**: All 9 topologies that use efficiency and ripple fields
- **Backward Compatibility**: No change to API contract, only fixes internal conversion

### Bug 5 Impact
- **Severity**: LOW (test script only, does not affect GUI)
- **User-Visible**: No (test script is internal verification)
- **Scope**: Test script `test_mas_api_workflow.m` for all topologies
- **Backward Compatibility**: Improves robustness without breaking existing code

---

## Future Improvements
- Consider adding unit validation in `build_mas_structure.m` to catch percentage-range values (e.g., warn if efficiency > 1.0)
- Document expected input ranges in function comments
- Add similar field-name detection for future features with conditional field names
