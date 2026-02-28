# MAS Structure + PyOpenMagnetics API Integration Guide

## Overview

Two complementary functions that replace hand-coded topology calculators with direct PyOpenMagnetics API calls:

1. **build_mas_structure.m** (MATLAB) - Converts GUI parameters to MAS JSON format
2. **call_pyopenmagnetics_api.py** (Python) - Calls PyOpenMagnetics adviser APIs and returns recommendations

## Architecture

```
GUI Data (MATLAB)
      ↓
build_mas_structure.m
      ↓
MAS JSON (intermediate)
      ↓
call_pyopenmagnetics_api.py
      ↓
PyOpenMagnetics Adviser
      ├─ pm.process_inputs()
      └─ pm.calculate_advised_magnetics()
      ↓
Results JSON
      ↓
MATLAB Results Processing
```

## Part 1: build_mas_structure.m

### Purpose
Converts MATLAB struct containing GUI parameters into MAS (Magnetic Assembly Specification) format compatible with PyOpenMagnetics.

### Function Signature
```matlab
mas_struct = build_mas_structure(gui_data, topology_key)
```

### Input: gui_data struct

```matlab
gui_data = struct();

% Required: Converter specifications
gui_data.converter.vin_min = 100;           % V
gui_data.converter.vin_max = 190;           % V
gui_data.converter.vin_nom = 145;           % V (optional, computed if empty)
gui_data.converter.vout = 5.0;              % V
gui_data.converter.iout = 5.0;              % A
gui_data.converter.fsw_khz = 200;           % kHz

% Optional: Converter parameters
gui_data.converter.vd = 0.7;                % Diode forward drop (V)
gui_data.converter.efficiency = 90;         % Target efficiency (%)
gui_data.converter.max_ripple = 30;         % Max current ripple (%)
gui_data.converter.max_switch_current = []; % (A, if constrained)
gui_data.converter.max_duty = [];           % (%, flyback-specific)
gui_data.converter.max_drain_source_voltage = []; % (V, flyback-specific)

% Required: Thermal
gui_data.thermal.ambient_temp = 25;         % C

% Optional: Insulation block
gui_data.insulation.class = 'Basic';        % Functional/Basic/Supplementary/Reinforced/Double
gui_data.insulation.standard = 'IEC 62368-1';
gui_data.insulation.pollution_degree = 2;   % 1/2/3
gui_data.insulation.overvoltage_cat = 'II'; % I/II/III/IV
gui_data.insulation.cti = 'Group II';       % Group I/II/IIIA/IIIB
gui_data.insulation.altitude_max = 2000;    % m
```

### Input: topology_key

One of 9 topology keys (snake_case):
- `'two_switch_forward'` → `'two-switch-forward'` (MAS format)
- `'single_switch_forward'` → `'single-switch-forward'`
- `'active_clamp_forward'` → `'active-clamp-forward'`
- `'flyback'` → `'flyback'`
- `'push_pull'` → `'push-pull'`
- `'buck'` → `'buck'`
- `'boost'` → `'boost'`
- `'isolated_buck'` → `'isolated-buck'`
- `'isolated_buck_boost'` → `'isolated-buck-boost'`

### Output: mas_struct

```matlab
mas_struct.inputs.designRequirements
    .topology = 'two-switch-forward'
    .inputVoltage
        .minimum = 100
        .nominal = 145
        .maximum = 190
    .diodeVoltageDrop = 0.7
    .currentRippleRatio = 0.30
    .efficiency = 0.90
    .maximumSwitchCurrent = [] (optional, topology-dependent)
    .insulation (optional)
        .insulationType = 'Basic'
        .standards = {'IEC 62368-1'}
        .pollutionDegree = 'P2'
        .overvoltageCategory = 'OVC-II'
        .cti = 'Group II'
        .altitude = {nominal, minimum, maximum}
        .wiringTechnology = 'Wound'

mas_struct.inputs.operatingPoints
    [1] (array of operating conditions)
        .switchingFrequency = 200000  (Hz)
        .ambientTemperature = 25
        .outputVoltage = 5.0          (single-output topologies)
        .outputCurrent = 5.0          (single-output topologies)
        % OR:
        .outputVoltages = [5, 3.3, 12]  (multi-output topologies)
        .outputCurrents = [5, 2, 1]

mas_struct.magnetic = {}  (empty, filled by adviser)
mas_struct.outputs = {}   (empty, filled by adviser)
```

### Key Features

1. **Topology-aware field selection**
   - Forward topologies: include `maximumSwitchCurrent`
   - Flyback: include `maximumDutyCycle`, `maximumDrainSourceVoltage`
   - Buck/Boost: no transformer, single output

2. **Unit conversion**
   - Percentages (%) → Decimals (0-1): efficiency, ripple, duty
   - kHz → Hz: switching frequency (×1000)

3. **Fallback handling**
   - If `vin_nom` empty or zero: computed as midpoint of min/max
   - If insulation fields missing: omitted from output (not nulls)
   - If max_switch_current empty: omitted (not required for all topologies)

4. **Type safety**
   - Validates vin_min, vin_max > 0 and vin_min ≤ vin_max
   - Ensures converter.fsw_khz exists
   - Wraps insulation.standard in cell array for JSON arrays

## Part 2: call_pyopenmagnetics_api.py

### Purpose
Python bridge that calls PyOpenMagnetics adviser APIs to generate design recommendations.

### Function Signature
```python
def call_pyopenmagnetics_adviser(mas_inputs, max_results=5, core_mode='STANDARD_CORES')
```

### Script Usage

```bash
# Basic usage
python call_pyopenmagnetics_api.py config.json results.json

# With parameters
python call_pyopenmagnetics_api.py config.json results.json 10 ALL_CORES
```

### Arguments
- `config.json` - MAS JSON input (from MATLAB build_mas_structure())
- `results.json` - Output file (default: config_result.json)
- `max_results` - Number of recommendations (default: 5)
- `core_mode` - 'STANDARD_CORES' or 'ALL_CORES' (default: STANDARD_CORES)

### Input JSON (from build_mas_structure())
```json
{
  "inputs": {
    "designRequirements": {
      "topology": "two-switch-forward",
      "inputVoltage": {"minimum": 100, "nominal": 145, "maximum": 190},
      "diodeVoltageDrop": 0.7,
      "currentRippleRatio": 0.3,
      "efficiency": 0.9,
      "insulation": {...}
    },
    "operatingPoints": [
      {
        "switchingFrequency": 200000,
        "ambientTemperature": 25,
        "outputVoltage": 5.0,
        "outputCurrent": 5.0
      }
    ]
  },
  "magnetic": {},
  "outputs": {}
}
```

### Output JSON
```json
{
  "status": "OK",
  "count": 5,
  "data": [
    {
      "index": 1,
      "status": "OK",
      "core_name": "Ferrite EI 26 Core A",
      "magnetic": {...},
      "coil": {...},
      "losses": {...},
      "losses_core": 2.5,
      "losses_winding": 1.8,
      "losses_total": 4.3,
      "temperature": {...},
      "temperature_core": 85.2,
      "temperature_winding": 92.1,
      "scoring": {...}
    },
    ...
  ]
}
```

### Return Values

**Success**: status='OK'
- `count` - Number of designs returned
- `data` - Array of design objects with fields:
  - `index` - Recommendation index (1-based)
  - `status` - 'OK'
  - `core_name` - Human-readable core name
  - `magnetic` - Full magnetic object from adviser
  - `losses_core`, `losses_winding`, `losses_total` - Loss breakdown
  - `temperature_core`, `temperature_winding` - Temperature estimates
  - `scoring` - Score object (if returned by adviser)

**Error**: status='ERROR'
- `error` - Error message
- `traceback` - Full Python traceback (for debugging)
- `suggestion` - Installation hint (if PyOpenMagnetics missing)

### PyOpenMagnetics API Details

The script calls two APIs in sequence:

1. **pm.process_inputs(mas)**
   - Validates MAS structure
   - Computes harmonics
   - Enriches with defaults
   - Returns: processed dict

2. **pm.calculate_advised_magnetics(processed, max_results, core_mode)**
   - Generates design recommendations
   - Computes losses, temperatures
   - Scores designs (cost, efficiency, size)
   - Returns: list of design dicts (or dict with 'data' key)

### Error Handling

| Error | Cause | Resolution |
|-------|-------|-----------|
| `PyOpenMagnetics not found` | Module not installed | `pip install PyOpenMagnetics` |
| `process_inputs() returned None` | Invalid MAS structure | Check JSON fields against schema |
| `Invalid JSON in input file` | Malformed JSON from MATLAB | Verify build_mas_structure() output |
| `Input file not found` | Path issue | Verify file paths in MATLAB |
| `Input JSON missing 'inputs' field` | Incomplete struct | Check build_mas_structure() output |

## Integration with topology_wizard.m

### Workflow

```matlab
% In topology_wizard.m - cb_get_recommendations() callback

% Step 1: Build recommendation config
config = build_recommendation_config(data);

% Step 2: Convert to MAS format
mas = build_mas_structure(data.converter, data.topology);

% Step 3: Write MAS JSON
config_file = 'om_mas_config.json';
jsontext = jsonencode(mas);
writematrix(jsontext, config_file, 'FileType', 'text');

% Step 4: Call Python API
result_file = 'om_mas_results.json';
cmd = sprintf('python call_pyopenmagnetics_api.py "%s" "%s" %d %s', ...
    config_file, result_file, data.rec.n_results, 'STANDARD_CORES');
[status, output] = system(cmd);

if status == 0
    % Step 5: Load and process results
    results = jsondecode(fileread(result_file));
    % Display, store, or proceed to winding designer
else
    error('API call failed: %s', output);
end
```

## Testing

### Manual Test (MATLAB)
```matlab
test_mas_api_workflow()
```

This runs three test cases:
1. Two-Switch Forward (isolated, multi-output capable)
2. Flyback (isolated, with Vds constraint)
3. Buck (non-isolated, single output)

### Manual Test (Python)
```bash
python call_pyopenmagnetics_api.py test_mas_config.json test_mas_results.json 3
```

### Validation Checklist

- [ ] build_mas_structure() runs without errors
- [ ] JSON output has correct topology key (kebab-case)
- [ ] inputVoltage contains min/nominal/max
- [ ] switchingFrequency in Hz (not kHz)
- [ ] Percentages converted to decimals (0-1)
- [ ] call_pyopenmagnetics_api.py runs successfully
- [ ] Output JSON contains "status": "OK"
- [ ] Results array has expected number of designs
- [ ] Each result has core_name and loss estimates
- [ ] Python handles both list and dict return types from adviser

## Troubleshooting

### "PyOpenMagnetics not found"
**Problem**: Python script can't import PyOpenMagnetics
**Solution**: Install via pip in the correct Python environment
```bash
pip install PyOpenMagnetics
```

If using venv or Octave bundled Python, ensure consistency.

### "process_inputs() returned None"
**Problem**: Invalid MAS structure passed to adviser
**Solution**:
1. Check build_mas_structure() output JSON
2. Verify all required fields present (topology, inputVoltage, operatingPoints)
3. Ensure topology key is kebab-case (e.g., 'two-switch-forward')

### "Script times out"
**Problem**: Adviser takes 10-30 seconds for large core databases
**Solution**:
1. Use `core_mode='STANDARD_CORES'` for faster results (default)
2. Use `ALL_CORES` only when needed
3. Reduce `max_results` to speed up search

### Results missing loss/temperature data
**Problem**: Adviser didn't compute losses
**Reason**: Operating points may be missing excitation waveforms
**Solution**: Ensure `generate_om_excitation.py` or adviser generates waveforms internally

### JSON encoding issues in MATLAB
**Problem**: `jsonencode()` converts arrays to scalars
**Solution**: Explicitly wrap single values in arrays
```matlab
% Wrong:
operating_point.outputVoltage = 5.0;  % becomes scalar in JSON

% Right (for multi-output):
operating_point.outputVoltages = [5.0];  % becomes array in JSON
```

## File Structure

```
PEEC_Script/
├── build_mas_structure.m              # MATLAB: GUI → MAS
├── call_pyopenmagnetics_api.py        # Python: MAS → Recommendations
├── test_mas_api_workflow.m            # Test script
├── topology_wizard.m                  # Uses build_mas_structure()
├── interactive_winding_designer.m     # Final design tool
├── generate_om_topology.py            # [DEPRECATED: replaced by direct API]
└── generate_om_recommendations.py     # [STILL USED: for GUI DB filtering]
```

## Performance Notes

- **build_mas_structure()**: <1 ms (pure MATLAB)
- **JSON encoding**: ~10 ms (MATLAB jsonencode)
- **Python startup**: ~500 ms
- **pm.process_inputs()**: ~100 ms
- **pm.calculate_advised_magnetics()**: 10-30 seconds (database search)
- **Total pipeline**: ~30-35 seconds for full recommendation workflow

### Optimization Tips

1. Use `STANDARD_CORES` (679 cores) instead of `ALL_CORES` (4000+ cores)
2. Reduce `max_results` to speed convergence
3. Cache results if re-running same specs
4. Run in background (MATLAB parallel computing)

## Future Enhancements

1. **Multi-threading**: Run multiple topology recommendations in parallel
2. **Caching**: Store adviser results by design_spec hash
3. **Streaming**: Stream results as adviser processes (10+ cores at a time)
4. **Validation UI**: Show live progress during adviser computation
5. **Advanced constraints**: Add size/weight/cost limits to adviser
6. **MAS round-trip**: Full export/import of designed magnetic
