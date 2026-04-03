# Topology MAS Input Requirements Mapping

Based on OpenMagnetics MAS schema analysis, extracted from topology JSON files.

## Summary Table

| GUI Topology | MAS File | Output Type | Required Fields | Optional Fields |
|---|---|---|---|---|
| Two-Switch Forward | forward.json | Multi-output | inputVoltage, diodeVoltageDrop, currentRippleRatio | dutyCycle, maximumSwitchCurrent, efficiency |
| Single-Switch Forward | forward.json | Multi-output | inputVoltage, diodeVoltageDrop, currentRippleRatio | dutyCycle, maximumSwitchCurrent, efficiency |
| Active Clamp Forward | forward.json | Multi-output | inputVoltage, diodeVoltageDrop, currentRippleRatio | dutyCycle, maximumSwitchCurrent, efficiency |
| Flyback | flyback.json | Multi-output | inputVoltage, diodeVoltageDrop, currentRippleRatio, efficiency | maximumDutyCycle, maximumDrainSourceVoltage |
| Push-Pull | pushPull.json | Multi-output | inputVoltage, diodeVoltageDrop, currentRippleRatio | dutyCycle, maximumSwitchCurrent, maximumDrainSourceVoltage, efficiency |
| Buck | buck.json | Single-output | inputVoltage, diodeVoltageDrop | currentRippleRatio, maximumSwitchCurrent, efficiency |
| Boost | boost.json | Single-output | inputVoltage, diodeVoltageDrop | currentRippleRatio, maximumSwitchCurrent, efficiency |
| Isolated Buck | isolatedBuck.json | Multi-output | inputVoltage, diodeVoltageDrop | currentRippleRatio, maximumSwitchCurrent, efficiency |
| Isolated Buck-Boost | isolatedBuckBoost.json | Multi-output | inputVoltage, diodeVoltageDrop | currentRippleRatio, maximumSwitchCurrent, efficiency |

## Topology Input Details

### Forward Family (forward.json)
**MAS File:** `forward.json`
**Applies to:** Two-Switch Forward, Single-Switch Forward, Active Clamp Forward

**Global Parameters:**
- `inputVoltage`: Object with `{minimum, nominal, maximum}` (V)
- `diodeVoltageDrop`: Number (V)
- `currentRippleRatio`: Number (%, typically 10-30)
- `dutyCycle`: Number (optional, 0-0.5)
- `maximumSwitchCurrent`: Number (A, optional)
- `efficiency`: Number (0-1, optional, default 1)

**Operating Points Array:**
```json
{
  "outputVoltages": [5.0, 3.3, 12.0],     // Array for N outputs
  "outputCurrents": [5.0, 2.0, 1.0],      // Array for N outputs
  "switchingFrequency": 200000,            // Hz
  "ambientTemperature": 25                 // °C
}
```

### Flyback (flyback.json)
**MAS File:** `flyback.json`
**Applies to:** Flyback only

**Global Parameters:**
- `inputVoltage`: Object with `{minimum, nominal, maximum}` (V)
- `diodeVoltageDrop`: Number (V)
- `currentRippleRatio`: Number (%, typically 20-40)
- `efficiency`: Number (0-1, optional, default 1)
- `maximumDutyCycle`: Number (0-0.5, optional)
- `maximumDrainSourceVoltage`: Number (V, optional)

**Operating Points Array:**
```json
{
  "outputVoltages": [5.0, 3.3],            // Array for N outputs
  "outputCurrents": [5.0, 2.0],            // Array for N outputs
  "switchingFrequency": 200000,            // Hz
  "mode": "Continuous Conduction Mode",    // Optional
  "ambientTemperature": 25                 // °C
}
```

### Buck (buck.json)
**MAS File:** `buck.json`
**Applies to:** Buck only (NON-ISOLATED, single output)

**Global Parameters:**
- `inputVoltage`: Object with `{minimum, nominal, maximum}` (V)
- `diodeVoltageDrop`: Number (V)
- `currentRippleRatio`: Number (%, optional)
- `maximumSwitchCurrent`: Number (A, optional)
- `efficiency`: Number (0-1, optional, default 1)

**Operating Points Array:**
```json
{
  "outputVoltage": 5.0,                    // Single value, NOT array
  "outputCurrent": 5.0,                    // Single value, NOT array
  "switchingFrequency": 200000,            // Hz
  "ambientTemperature": 25                 // °C
}
```

### Boost (boost.json)
**MAS File:** `boost.json`
**Applies to:** Boost only (NON-ISOLATED, single output)

**Global Parameters:**
- `inputVoltage`: Object with `{minimum, nominal, maximum}` (V)
- `diodeVoltageDrop`: Number (V)
- `currentRippleRatio`: Number (%, optional)
- `maximumSwitchCurrent`: Number (A, optional)
- `efficiency`: Number (0-1, optional, default 1)

**Operating Points Array:**
```json
{
  "outputVoltage": 5.0,                    // Single value, NOT array
  "outputCurrent": 5.0,                    // Single value, NOT array
  "switchingFrequency": 200000,            // Hz
  "ambientTemperature": 25                 // °C
}
```

### Isolated Buck (isolatedBuck.json)
**MAS File:** `isolatedBuck.json`
**Applies to:** Isolated Buck (ISOLATED, multi-output)

**Global Parameters:**
- `inputVoltage`: Object with `{minimum, nominal, maximum}` (V)
- `diodeVoltageDrop`: Number (V)
- `currentRippleRatio`: Number (%, optional)
- `maximumSwitchCurrent`: Number (A, optional)
- `efficiency`: Number (0-1, optional, default 1)

**Operating Points Array:**
```json
{
  "outputVoltages": [5.0, 3.3],            // Array for N outputs
  "outputCurrents": [5.0, 2.0],            // Array for N outputs
  "switchingFrequency": 200000,            // Hz
  "ambientTemperature": 25                 // °C
}
```

### Isolated Buck-Boost (isolatedBuckBoost.json)
**MAS File:** `isolatedBuckBoost.json`
**Applies to:** Isolated Buck-Boost (ISOLATED, multi-output)

**Global Parameters:**
- `inputVoltage`: Object with `{minimum, nominal, maximum}` (V)
- `diodeVoltageDrop`: Number (V)
- `currentRippleRatio`: Number (%, optional)
- `maximumSwitchCurrent`: Number (A, optional)
- `efficiency`: Number (0-1, optional, default 1)

**Operating Points Array:**
```json
{
  "outputVoltages": [5.0, 3.3],            // Array for N outputs
  "outputCurrents": [5.0, 2.0],            // Array for N outputs
  "switchingFrequency": 200000,            // Hz
  "ambientTemperature": 25                 // °C
}
```

### Push-Pull (pushPull.json)
**MAS File:** `pushPull.json`
**Applies to:** Push-Pull (ISOLATED, multi-output)

**Global Parameters:**
- `inputVoltage`: Object with `{minimum, nominal, maximum}` (V)
- `diodeVoltageDrop`: Number (V)
- `currentRippleRatio`: Number (% required)
- `dutyCycle`: Number (optional, max 0.5)
- `maximumSwitchCurrent`: Number (A, optional)
- `maximumDrainSourceVoltage`: Number (V, optional)
- `efficiency`: Number (0-1, optional, default 1)

**Operating Points Array:**
```json
{
  "outputVoltages": [5.0, 3.3],            // Array for N outputs
  "outputCurrents": [5.0, 2.0],            // Array for N outputs
  "switchingFrequency": 200000,            // Hz
  "ambientTemperature": 25                 // °C
}
```

## GUI Field Visibility Logic

### Global Parameters (Always shown)
- Input Voltage (min/nom/max)
- Diode Voltage Drop
- Switching Frequency
- Ambient Temperature

### Conditional Fields

| Field | Shown for Topologies |
|---|---|
| Current Ripple Ratio | Forward, Flyback, Push-Pull (required); Buck, Boost, Iso Buck, Iso BuckBoost (optional) |
| Duty Cycle | Forward, Push-Pull (optional) |
| Max Switch Current | All (optional) |
| Max Drain-Source Voltage | Flyback, Push-Pull (optional) |
| Efficiency | All (optional, default 1) |
| N Outputs | Forward, Flyback, Push-Pull, Iso Buck, Iso BuckBoost (multi-output support) |

### Output Specification Format

**For Multi-Output Topologies (show N rows):**
```
Output 1:  Voltage [5.0] V   Current [5.0] A
Output 2:  Voltage [3.3] V   Current [2.0] A
Output 3:  Voltage [12.0] V  Current [1.0] A
```

**For Single-Output Topologies (one row):**
```
Output:    Voltage [5.0] V   Current [5.0] A
```

### N Outputs Spinner
- **Multi-output topologies:** Spinner control (1-4 outputs)
- **Single-output topologies:** Hidden

When N outputs changes, the output specification table dynamically adds/removes rows.

## Implementation Plan

1. **Create topology metadata structure** in MATLAB that maps each topology to:
   - MAS filename
   - Required global fields
   - Optional global fields
   - Output type (single vs multi)
   - Default values

2. **Update topology_wizard.m GUI**:
   - When topology dropdown changes → call `update_field_visibility(topology)`
   - This function shows/hides global parameter fields based on topology
   - Update output specification section (single row vs dynamic rows per N outputs)
   - N outputs spinner visible only for multi-output topologies

3. **Build dynamic output specification table**:
   - Add/remove rows based on N outputs spinner
   - Each row: Output X | Voltage [input] V | Current [input] A
   - For single-output topologies: Single row labeled "Output" (not "Output 1")

4. **Collect user inputs into MAS structure**:
   - Map topology selection → correct MAS filename
   - Gather global parameters from visible fields
   - Build operatingPoints array from output specification table
   - Call PyOpenMagnetics API with properly structured MAS inputs

5. **No waveform simulation**:
   - Don't hand-code waveforms
   - Just pass inputs to PyOpenMagnetics APIs
   - Display results from API (let OpenMagnetics compute everything)
