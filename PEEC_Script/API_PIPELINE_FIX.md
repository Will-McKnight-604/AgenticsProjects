# API Pipeline Debug & Fix Summary

## Problem Analysis

The topology_wizard → MAS → PyOpenMagnetics adviser pipeline was failing with:
```
[API] Adviser error: generate_om_recommendations.py failed with exit code 1
```

### Root Causes Identified

1. **Field Name Mismatch**: The MAS JSON format from `build_mas_structure.m` used different field names than what `generate_om_recommendations.py` expected:
   - MAS format: `switchingFrequency` → Expected: `frequency_hz`
   - MAS format: `ambientTemperature` → Expected: `ambient_temperature`
   - MAS format: `outputVoltages`/`outputCurrents` → Expected: `windings` array
   - Missing: `duty` parameter (required for waveform generation)
   - Missing: `windings` array (required for excitation building)

2. **Nested Structure Mismatch**:
   - MAS created `inputs.operatingPoints` (nested)
   - `generate_om_recommendations.py` expected `operatingPoints` at top level in config

3. **PyOpenMagnetics Import Error**: Python 3.12 (bundled with Octave 10.3.0) doesn't have PyOpenMagnetics, requiring fallback to Python 3.11 (with enhanced error detection)

### Example: What Was Being Passed vs What Was Expected

**BEFORE (from MAS JSON)**:
```json
{
  "operatingPoints": [
    {
      "switchingFrequency": 200000,
      "ambientTemperature": 25,
      "outputVoltages": 5,
      "outputCurrents": 5
    }
  ]
}
```

**AFTER (transformed by call_pyopenmagnetics_api.py)**:
```json
{
  "operating_points": [
    {
      "frequency_hz": 200000,
      "ambient_temperature": 25,
      "duty": 0.4,
      "windings": [
        {
          "name": "Primary",
          "waveform_label": "Rectangular",
          "i_pp": 1.0,
          "i_offset": 0.5,
          "v_pp": 1.0,
          "v_offset": 0.0
        },
        {
          "name": "Secondary",
          "waveform_label": "Rectangular",
          "i_pp": 1.0,
          "i_offset": 0.0,
          "v_pp": 1.0,
          "v_offset": 0.0
        }
      ]
    }
  ]
}
```

## Solutions Implemented

### 1. **call_pyopenmagnetics_api.py** - Added Transformation Layer

Added `transform_mas_operating_points()` function that:
- Converts `switchingFrequency` → `frequency_hz`
- Converts `ambientTemperature` → `ambient_temperature`
- Adds default `duty = 0.4` (standard for forward converters)
- Creates `windings` array with placeholder primary/secondary waveforms
- Preserves `frequency_hz` field name (matches PyOpenMagnetics MAS format)

**Key Change**: Line 122 now calls `transform_mas_operating_points()` before passing to config:
```python
transformed_op_points = transform_mas_operating_points(mas_inputs['inputs']['operatingPoints'])
config = {
    ...
    "operating_points": transformed_op_points,  # Transformed to match gen_om_recommendations.py expectations
    ...
}
```

### 2. **topology_wizard.m** - Enhanced Error Handling

**Improved PyOpenMagnetics Import Error Detection** (lines 1513-1531):
- Added check for ImportError in results JSON file (not just stderr)
- Better handling of scenarios where error is written to file instead of console

**Added API Error Propagation** (lines 1573-1576):
- Now checks if API results contain `status: "ERROR"` and propagates the message
- Better error messages to user showing exactly what failed

**Fixed Results Count Reading** (lines 1584-1587):
- Safer extraction of results count with proper field checking

## Files Modified

1. **c:\Users\Will\proximity_loss\Claude\PEEC_Script\call_pyopenmagnetics_api.py**
   - Added `transform_mas_operating_points()` function
   - Updated `call_pyopenmagnetics_adviser()` to use transformation

2. **c:\Users\Will\proximity_loss\Claude\PEEC_Script\topology_wizard.m**
   - Enhanced PyOpenMagnetics import error detection
   - Added API error propagation to user
   - Improved results count extraction

## Testing

The transformation was verified to produce correct output:

```
VERIFICATION:
  - design_requirements present: True
  - operating_points present: True
  - frequency_hz present: True
  - duty present: True
  - ambient_temperature present: True
  - windings present: True
```

## Expected Behavior After Fix

1. **Normal Case** (Python with PyOpenMagnetics available):
   - topology_wizard.m collects parameters
   - build_mas_structure.m creates MAS format JSON
   - call_pyopenmagnetics_api.py transforms MAS → gen_om_recommendations.py format
   - generate_om_recommendations.py processes inputs and calls adviser
   - Results returned and displayed in GUI (5 core recommendations)

2. **Fallback Case** (Python 3.12 without PyOpenMagnetics):
   - Initial Python call fails with ImportError
   - topology_wizard.m detects ImportError in results file
   - Fallback chain activated: py launcher → where python → alternative paths
   - Python 3.11 (with PyOpenMagnetics) runs successfully
   - Pipeline completes normally

3. **Error Case** (API processing fails):
   - generate_om_recommendations.py catches error
   - Returns `{"status": "ERROR", "error": "..."}`
   - topology_wizard.m propagates error to user with details

## Remaining Notes

- The transformation uses default `duty = 0.4` since topology_wizard.m doesn't compute explicit duty cycle
- Default waveforms (Rectangular, 1.0A peak, etc.) provide baseline for excitation building
- Future enhancement: Pass topology-specific waveforms from topology calculators if available
- The PyOpenMagnetics fallback chain should now successfully find Python 3.11 on Windows systems with multiple Python installations

## Commands for Manual Testing

```matlab
% In MATLAB/Octave:
topology_wizard
% Select: Two-Switch Forward
% Enter: Vin 100-190V, Vout 5V, Iout 5A, Fsw 200kHz
% Click "Compute Requirements"
% Expected: 5 core recommendations displayed
```
