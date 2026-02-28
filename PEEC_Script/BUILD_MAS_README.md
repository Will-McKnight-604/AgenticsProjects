# build_mas_structure.m + call_pyopenmagnetics_api.py

## Quick Start

These two functions replace hand-coded topology calculators with direct PyOpenMagnetics API calls.

### MATLAB Usage
```matlab
% Create GUI data struct
gui_data = struct();
gui_data.converter.vin_min = 100;
gui_data.converter.vin_max = 190;
gui_data.converter.vin_nom = 145;
gui_data.converter.vout = 5.0;
gui_data.converter.iout = 5.0;
gui_data.converter.fsw_khz = 200;
gui_data.converter.vd = 0.7;
gui_data.converter.efficiency = 90;
gui_data.converter.max_ripple = 30;
gui_data.thermal.ambient_temp = 25;

% Build MAS structure
mas = build_mas_structure(gui_data, 'two_switch_forward');

% Save to JSON
jsontext = jsonencode(mas);
fid = fopen('config.json', 'w');
fprintf(fid, '%s', jsontext);
fclose(fid);
```

### Python Usage
```bash
python call_pyopenmagnetics_api.py config.json results.json 5 STANDARD_CORES
```

Then in MATLAB:
```matlab
results = jsondecode(fileread('results.json'));
for i = 1:results.count
    fprintf('Design %d: %s, Loss: %.2f W\n', ...
        i, results.data(i).core_name, results.data(i).losses_total);
end
```

## Files

### 1. build_mas_structure.m
**Purpose**: Convert GUI parameters to MAS JSON format

**Location**: `/c/Users/Will/proximity_loss/Claude/PEEC_Script/build_mas_structure.m`

**Function Signature**:
```matlab
mas_struct = build_mas_structure(gui_data, topology_key)
```

**Key Points**:
- Converts snake_case topology keys to kebab-case (MAS format)
- Validates input voltages and required fields
- Computes nominal voltage if not provided (midpoint of min/max)
- Converts percentages to decimals (%, %)
- Converts kHz to Hz
- Handles topology-specific optional fields:
  - Forward topologies: `maximumSwitchCurrent`
  - Flyback: `maximumDutyCycle`, `maximumDrainSourceVoltage`
- Wraps insulation block in JSON-compatible format
- Omits empty optional fields (no nulls sent to JSON)

**Examples**:
- Two-Switch Forward: forward converter with transformer
- Flyback: isolated, high-power-density, single switch
- Buck: non-isolated, step-down, inductor (not transformer)

### 2. call_pyopenmagnetics_api.py
**Purpose**: Call PyOpenMagnetics adviser APIs and return recommendations

**Location**: `/c/Users/Will/proximity_loss/Claude/PEEC_Script/call_pyopenmagnetics_api.py`

**Script Invocation**:
```bash
python call_pyopenmagnetics_api.py <config.json> [results.json] [max_results] [core_mode]
```

**Key Points**:
- Reads MAS JSON from file
- Calls `pm.process_inputs()` to validate and enrich
- Calls `pm.calculate_advised_magnetics()` for recommendations
- Handles both list and dict return types from adviser
- Extracts core names, losses, temperatures for easy MATLAB access
- Returns JSON with status, count, and array of designs
- Full error handling with diagnostic info

**Output Fields**:
```json
{
  "status": "OK|ERROR",
  "count": 5,
  "data": [
    {
      "index": 1,
      "core_name": "Ferrite EI 26 Core A",
      "losses_total": 4.3,
      "losses_core": 2.5,
      "losses_winding": 1.8,
      "temperature_core": 85.2,
      "temperature_winding": 92.1,
      "magnetic": {...},
      "losses": {...},
      "temperature": {...},
      "scoring": {...}
    }
  ]
}
```

### 3. test_mas_api_workflow.m
**Purpose**: Test script demonstrating the workflow

**Location**: `/c/Users/Will/proximity_loss/Claude/PEEC_Script/test_mas_api_workflow.m`

**Run**:
```matlab
test_mas_api_workflow()
```

**Tests**:
1. Two-Switch Forward (isolated, multi-output capable)
2. Flyback (isolated, with Vds constraint)
3. Buck (non-isolated, single output)

### 4. MAS_API_INTEGRATION.md
**Purpose**: Complete integration documentation

**Contents**:
- Architecture overview
- Function signatures and inputs/outputs
- Topology-aware field handling
- PyOpenMagnetics API details
- Integration with topology_wizard.m
- Performance notes
- Troubleshooting guide

### 5. INTEGRATION_EXAMPLE.m
**Purpose**: Code examples for integration

**Examples**:
1. Integrating into topology_wizard.m callback
2. Simple wrapper function
3. Display recommendations dialog
4. Batch recommendations across topologies
5. Helper functions

## Input Format

### gui_data Structure (MATLAB)

**Required Fields**:
```matlab
gui_data.converter.vin_min          % V (minimum)
gui_data.converter.vin_max          % V (maximum)
gui_data.converter.vout             % V (output voltage)
gui_data.converter.iout             % A (output current)
gui_data.converter.fsw_khz          % kHz (switching frequency)
```

**Optional Fields**:
```matlab
gui_data.converter.vin_nom          % V (nominal, computed if empty)
gui_data.converter.vd               % V (diode forward drop)
gui_data.converter.efficiency       % % (target efficiency)
gui_data.converter.max_ripple       % % (max current ripple)
gui_data.converter.max_switch_current % A (forward topologies)
gui_data.converter.max_duty         % % (flyback)
gui_data.converter.max_drain_source_voltage % V (flyback)

gui_data.thermal.ambient_temp       % C (temperature)

gui_data.insulation.class           % string
gui_data.insulation.standard        % string
gui_data.insulation.pollution_degree % 1-3
gui_data.insulation.overvoltage_cat % 'I', 'II', 'III', 'IV'
gui_data.insulation.cti             % string
gui_data.insulation.altitude_max    % m
```

## Output Format

### MAS Structure (JSON)

```json
{
  "inputs": {
    "designRequirements": {
      "topology": "two-switch-forward",
      "inputVoltage": {
        "minimum": 100,
        "nominal": 145,
        "maximum": 190
      },
      "diodeVoltageDrop": 0.7,
      "currentRippleRatio": 0.3,
      "efficiency": 0.9,
      "insulation": {
        "insulationType": "Basic",
        "standards": ["IEC 62368-1"],
        "pollutionDegree": "P2",
        "overvoltageCategory": "OVC-II",
        "cti": "Group II",
        "altitude": {
          "nominal": 2000,
          "minimum": 0,
          "maximum": 2000
        },
        "wiringTechnology": "Wound"
      }
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

## Topology Support

All 9 topologies supported with topology-specific fields:

| Topology | Key | Type | Features |
|----------|-----|------|----------|
| Two-Switch Forward | `two_switch_forward` | Isolated | Continuous primary current |
| Single-Switch Forward | `single_switch_forward` | Isolated | Cheaper, requires demagnetization |
| Active Clamp Forward | `active_clamp_forward` | Isolated | Extended MOSFET voltage range |
| Flyback | `flyback` | Isolated | High power density, simple |
| Push-Pull | `push_pull` | Isolated | Symmetric drives, transformer utilization |
| Buck | `buck` | Non-isolated | Step-down inductor |
| Boost | `boost` | Non-isolated | Step-up inductor |
| Isolated Buck | `isolated_buck` | Isolated | Transformer + filter inductor |
| Isolated Buck-Boost | `isolated_buck_boost` | Isolated | Universal input, complex |

## Data Flow

```
topology_wizard.m (GUI)
    ↓
[User fills form, clicks "Get Recommendations"]
    ↓
cb_get_recommendations()
    ↓
extract_gui_data() → gui_data struct
    ↓
build_mas_structure(gui_data, 'two_switch_forward')
    ↓
JSON: config.json
    ↓
system("python call_pyopenmagnetics_api.py config.json results.json 5 STANDARD_CORES")
    ↓
Python: pm.process_inputs() → pm.calculate_advised_magnetics()
    ↓
JSON: results.json
    ↓
jsondecode(fileread('results.json'))
    ↓
display_recommendations(fig, results)
    ↓
[User selects core, proceeds to interactive_winding_designer.m]
```

## Error Handling

### Common Errors and Solutions

| Error | Cause | Fix |
|-------|-------|-----|
| `PyOpenMagnetics not found` | Module not installed | `pip install PyOpenMagnetics` |
| `Input JSON missing topology` | Missing required field | Check build_mas_structure() output |
| `Invalid topology key` | Misspelled topology (not kebab-case) | Use correct key mapping |
| `vin_min <= 0` | Invalid voltage range | Ensure vin_min > 0, vin_max > vin_min |
| `process_inputs() returned None` | Invalid MAS structure | Check JSON against PyOpenMagnetics schema |
| `Script timeout` | Adviser takes too long | Use STANDARD_CORES instead of ALL_CORES |

## Performance

- **build_mas_structure()**: <1 ms
- **JSON encoding**: ~10 ms
- **Python startup**: ~500 ms
- **pm.process_inputs()**: ~100 ms
- **pm.calculate_advised_magnetics()**: 10-30 seconds (database search)
- **Total pipeline**: ~30-35 seconds

## Testing

### Manual Test
```matlab
test_mas_api_workflow()
```

### Unit Test
```matlab
% Test build_mas_structure
gui_data.converter.vin_min = 100;
gui_data.converter.vin_max = 190;
gui_data.converter.vout = 5;
gui_data.converter.iout = 5;
gui_data.converter.fsw_khz = 200;
gui_data.thermal.ambient_temp = 25;

mas = build_mas_structure(gui_data, 'two_switch_forward');
assert(strcmp(mas.inputs.designRequirements.topology, 'two-switch-forward'));
assert(mas.inputs.designRequirements.inputVoltage.minimum == 100);
```

### Integration Test
```bash
python call_pyopenmagnetics_api.py test_config.json test_results.json 3
```

## Integration Checklist

- [ ] Files created in PEEC_Script directory
- [ ] Python script is executable: `chmod +x call_pyopenmagnetics_api.py`
- [ ] PyOpenMagnetics installed: `pip install PyOpenMagnetics`
- [ ] MATLAB can call build_mas_structure() without errors
- [ ] MATLAB can write JSON with jsonencode()
- [ ] Python script can read JSON with proper error handling
- [ ] Python script returns correct status codes
- [ ] MATLAB can parse results JSON
- [ ] Recommendations appear in topology_wizard.m UI

## Deprecation Notes

- `generate_om_topology.py` - Hand-coded topology calculators, now replaced by direct API calls
- These scripts still available for reference but new code should use `build_mas_structure()` + `call_pyopenmagnetics_api.py()`

## Future Improvements

1. Add multi-output support for isolated topologies
2. Streaming results (yield cores as adviser processes)
3. Caching for repeated designs
4. Constraint-aware adviser (size/weight limits)
5. Full MAS round-trip export/import
6. Parallel topology evaluation (all 9 at once)

## Support

For issues or questions:
1. Check MAS_API_INTEGRATION.md for detailed docs
2. Review test_mas_api_workflow.m for working examples
3. Check INTEGRATION_EXAMPLE.m for use patterns
4. See troubleshooting section above

## Files Summary

| File | Type | Size | Purpose |
|------|------|------|---------|
| build_mas_structure.m | MATLAB | ~350 LOC | GUI → MAS conversion |
| call_pyopenmagnetics_api.py | Python | ~280 LOC | MAS → Recommendations |
| test_mas_api_workflow.m | MATLAB | ~200 LOC | Test script |
| MAS_API_INTEGRATION.md | Docs | ~1500 LOC | Full documentation |
| INTEGRATION_EXAMPLE.m | MATLAB | ~400 LOC | Code examples |
| BUILD_MAS_README.md | Docs | This file | Quick reference |
