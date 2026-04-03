# Phase 1b: Waveform Preview Generation Implementation

## Summary
Implemented waveform preview generation system for all 9 converter topologies in `generate_om_topology.py`. This provides time-domain voltage and current waveforms with correct C++ WaveformLabel types for visualization in the OpenMagnetics UI.

## Changes Made

### 1. Base Class Helper Methods (TopologyCalculator)

Added four waveform generation helper methods to the base class:

#### `_create_rectangular_waveform(peak_to_peak, frequency, duty_cycle, offset)`
- Generates rectangular waveform with 4 time points: [0, D*T, D*T, T]
- Data transitions from high during on-time to low during off-time
- Used for voltage in forward converters and rectangular current waveforms

#### `_create_triangular_waveform(peak_to_peak, frequency, duty_cycle, offset)`
- Generates triangular waveform with 3 time points: [0, D*T, T]
- Data ramps from minimum to maximum during on-time, back to minimum at off-time
- Used for current ripple in buck/boost inductors and forward converter secondaries

#### `_create_flyback_primary_waveform(peak_to_peak, frequency, duty_cycle, offset)`
- Generates flyback primary current waveform with discontinuous transition
- 4 time points: [0, D*T, D*T, T] showing ramp-up then jump-down at turn-off
- Models the characteristic flyback primary current behavior

#### `_create_custom_waveform(time, data)`
- Pass-through method for arbitrary time/data arrays
- Reserved for future custom waveforms (IsolatedBuck secondaries, etc.)

### 2. Base Class Abstract Method

Added `build_waveform_preview(design_reqs, operating_point, fsw)` abstract method:
- Topology-specific override required in each subclass
- Returns list of winding dicts with voltage and current waveforms
- Each winding contains: `{"winding_name": str, "voltage": {...}, "current": {...}}`

### 3. Topology-Specific Implementations

Implemented `build_waveform_preview()` for all 9 topologies:

#### **TwoSwitchForwardCalc**
- Primary: RECTANGULAR voltage + RECTANGULAR current
- Secondaries: SECONDARY_RECTANGULAR voltage + RECTANGULAR current

#### **SingleSwitchForwardCalc**
- Primary: RECTANGULAR voltage + RECTANGULAR current
- Secondaries: SECONDARY_RECTANGULAR voltage + RECTANGULAR current
- Demagnetization: RECTANGULAR voltage + RECTANGULAR current (during off-time)

#### **ActiveClampForwardCalc**
- Primary: RECTANGULAR voltage + RECTANGULAR current
- Secondaries: SECONDARY_RECTANGULAR voltage + RECTANGULAR current
(Same as two-switch forward, active clamp reduces stress but not fundamental waveforms)

#### **FlybackCalc**
- Primary: RECTANGULAR voltage + FLYBACK_PRIMARY current (ramp up, jump down)
- Secondaries: SECONDARY_RECTANGULAR voltage + FLYBACK_SECONDARY current (triangular during off-time)

#### **PushPullCalc**
- Primary: RECTANGULAR voltage (2x Vin effective) + RECTANGULAR current
- Secondaries: SECONDARY_RECTANGULAR voltage + RECTANGULAR current

#### **BuckCalc** (Non-isolated)
- Inductor: RECTANGULAR voltage + TRIANGULAR current

#### **BoostCalc** (Non-isolated)
- Inductor: RECTANGULAR voltage + TRIANGULAR current

#### **IsolatedBuckCalc**
- Primary: RECTANGULAR voltage + TRIANGULAR current (during on-time)
- Secondaries: RECTANGULAR voltage + TRIANGULAR current (during on-time)

#### **IsolatedBuckBoostCalc**
- Primary: RECTANGULAR voltage + TRIANGULAR current (during on-time, energy storage)
- Secondaries: RECTANGULAR voltage + TRIANGULAR current (during off-time, energy transfer)

### 4. Main compute_topology() Function Update

Modified `compute_topology()` to:
1. Call `build_waveform_preview()` for each operating point
2. Add `"waveforms_preview"` key to output JSON
3. Structure: `waveforms_preview[operating_point_index][winding_index][{winding_name, voltage, current}]`

### 5. Output Structure

Added to result JSON:
```json
{
  "status": "OK",
  "topology": "two_switch_forward",
  "topology_display": "Two-Switch Forward Converter",
  "design_mode": "auto",
  "computed": { ... },
  "mas_inputs": { ... },
  "waveforms_preview": [
    [
      {
        "winding_name": "Primary",
        "voltage": {
          "time": [0.0, 1.13e-06, 1.13e-06, 5e-06],
          "data": [97.5, 97.5, -52.5, -52.5],
          "label": "RECTANGULAR",
          "unit": "V"
        },
        "current": {
          "time": [0.0, 1.13e-06, 1.13e-06, 5e-06],
          "data": [0.8, 0.8, -0.2, -0.2],
          "label": "RECTANGULAR",
          "unit": "A"
        }
      },
      { ... "Secondary" winding ... }
    ]
  ]
}
```

## Waveform Label Mapping

| Topology | Primary Voltage | Primary Current | Secondary Voltage | Secondary Current |
|----------|---|---|---|---|
| Two-Switch Forward | RECTANGULAR | RECTANGULAR | SECONDARY_RECTANGULAR | RECTANGULAR |
| Single-Switch Forward | RECTANGULAR | RECTANGULAR | SECONDARY_RECTANGULAR | RECTANGULAR |
| Active Clamp Forward | RECTANGULAR | RECTANGULAR | SECONDARY_RECTANGULAR | RECTANGULAR |
| Flyback | RECTANGULAR | FLYBACK_PRIMARY | SECONDARY_RECTANGULAR | FLYBACK_SECONDARY |
| Push-Pull | RECTANGULAR | RECTANGULAR | SECONDARY_RECTANGULAR | RECTANGULAR |
| Buck | RECTANGULAR | TRIANGULAR | - | - |
| Boost | RECTANGULAR | TRIANGULAR | - | - |
| Isolated Buck | RECTANGULAR | TRIANGULAR | RECTANGULAR | TRIANGULAR |
| Isolated Buck-Boost | RECTANGULAR | TRIANGULAR | RECTANGULAR | TRIANGULAR |

## Waveform Equations

### Rectangular Waveform
- Time: [0, D·T, D·T, T] (normalized by period)
- Data: [offset + pp/2, offset + pp/2, offset - pp/2, offset - pp/2]
- Represents: high voltage/current during on-time, low during off-time

### Triangular Waveform
- Time: [0, D·T, T]
- Data: [offset - pp/2, offset + pp/2, offset - pp/2]
- Represents: ramp-up during on-time, ramp-down during off-time

### Flyback Primary Waveform
- Time: [0, D·T, D·T, T]
- Data: [offset - pp/2, offset + pp/2, offset - pp/2, offset - pp/2]
- Represents: linear ramp during on-time, discontinuous jump at turn-off

## Testing

All 9 topologies verified to:
1. Generate valid waveforms_preview structure
2. Have correct C++ WaveformLabel types
3. Produce physically meaningful time arrays (non-decreasing)
4. Generate correct peak-to-peak and offset values from design requirements

## Files Modified

- `/c/Users/Will/proximity_loss/Claude/PEEC_Script/generate_om_topology.py`
  - Added 4 helper methods to TopologyCalculator (lines ~161-240)
  - Added abstract build_waveform_preview() method to TopologyCalculator (lines ~241-255)
  - Added build_waveform_preview() implementation to each of 9 topology subclasses
  - Modified compute_topology() to generate and include waveforms_preview in output

## Integration Notes

- Waveforms are generated from the same design_reqs used for MAS inputs
- Physical time is computed using topology-specific switching frequency
- Duty cycles and current/voltage values are derived from design requirement calculations
- No changes to MAS input generation or callback wiring required
- Backward compatible: existing code not relying on waveforms_preview is unaffected
