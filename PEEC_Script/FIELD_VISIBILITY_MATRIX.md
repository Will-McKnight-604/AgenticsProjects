# Field Visibility Matrix - All 9 Topologies

Quick reference showing which input fields should be visible for each topology in Auto and Advanced modes.

## Legend
- **Y** = Visible
- **N** = Hidden
- **A** = Visible only in Advanced mode
- **O** = Visible in Optional panel (if toggled on)

---

## Matrix: Required Input Fields

| Field | Two-Sw-Fwd | Single-Sw-Fwd | Active-Clamp-Fwd | Flyback | Push-Pull | Buck | Boost | Iso-Buck | Iso-Buck-Boost |
|-------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Input Voltage Min | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Input Voltage Max | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Input Voltage Nom* | O | O | O | O | O | O | O | O | O |
| Output Voltage | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Output Current | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Switching Frequency | Y | Y | Y | Y | Y | Y | Y | Y | Y |

**Legend for table rows:**
- Input Voltage Min/Max: Always required for all topologies
- Input Voltage Nom: Optional, shown only if "Show Optional Parameters" toggled
- Output Voltage: For single-output topologies shown as scalar; for multi-output shown as table rows
- Output Current: For single-output topologies shown as scalar; for multi-output shown as table rows
- Switching Frequency: Required for all topologies

---

## Matrix: Optional Fields (Auto Mode)

| Field | Two-Sw-Fwd | Single-Sw-Fwd | Active-Clamp-Fwd | Flyback | Push-Pull | Buck | Boost | Iso-Buck | Iso-Buck-Boost |
|-------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Diode Forward Voltage (Vd) | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Efficiency Target | O | O | O | O | O | O | O | O | O |
| Current Ripple (%) | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Max Switch Current | N | N | N | N | N | N | N | N | N |

---

## Matrix: Advanced-Only Fields (Advanced Mode Only)

| Field | Two-Sw-Fwd | Single-Sw-Fwd | Active-Clamp-Fwd | Flyback | Push-Pull | Buck | Boost | Iso-Buck | Iso-Buck-Boost |
|-------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Max Duty Cycle (%) | N | N | N | A | N | N | N | N | N |
| Max Drain-Source Voltage (V) | N | N | A | A | A | N | N | N | N |
| Dead Time (ns) | N | N | N | A | N | N | N | N | N |
| Max Switch Current (A) | N | N | N | N | N | N | N | N | N |
| Load Resistance (Ω) | N | N | N | N | N | A | A | N | N |

---

## Matrix: Multi-Output Controls

| Field | Two-Sw-Fwd | Single-Sw-Fwd | Active-Clamp-Fwd | Flyback | Push-Pull | Buck | Boost | Iso-Buck | Iso-Buck-Boost |
|-------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| N Outputs Spinner | N | Y | N | Y | N | N | N | Y | Y |
| Max Outputs | 1 | 4 | 1 | 4 | 1 | 1 | 1 | 4 | 4 |
| Output Table Rows | 1 | N | 1 | N | 1 | 1 | 1 | N | N |

**Notes:**
- **N Outputs Spinner visible?**: Controls output count (1-4) for selected topology
- **Max Outputs**: Maximum N allowed (clamped in GUI)
- **Output Table Rows dynamic?**: For multi-output topologies (Single-Sw-Fwd, Flyback, Iso-Buck, Iso-Buck-Boost), output voltage/current is entered via dynamic table rows, not scalar fields

---

## Detailed Field Descriptions

### Always Visible (All Topologies)

#### Input Voltage Min (V)
- **Type:** Required
- **Range:** > 0
- **Purpose:** Lower end of input voltage range
- **Affects:** Duty cycle calculation, magnetizing current stress
- **Used by:** Python topology calculator

#### Input Voltage Max (V)
- **Type:** Required
- **Range:** > Input Voltage Min
- **Purpose:** Upper end of input voltage range
- **Affects:** Duty cycle calculation, minimum current stress
- **Used by:** Python topology calculator

#### Output Voltage (V)
- **Type:** Required (but varies by topology)
- **Range:** > 0
- **Purpose:** Output voltage specification
- **Multi-output variant:** For topologies supporting multiple secondaries, entered via dynamic table with one row per output
- **Affects:** Turns ratio, duty cycle
- **Used by:** Python topology calculator

#### Output Current (A)
- **Type:** Required (but varies by topology)
- **Range:** > 0
- **Purpose:** Output current specification
- **Multi-output variant:** For topologies supporting multiple secondaries, entered via dynamic table with one row per output
- **Affects:** Wire size, loss calculations
- **Used by:** Python topology calculator

#### Switching Frequency (kHz)
- **Type:** Required
- **Range:** > 0, typically 50-500 for power converters
- **Purpose:** Converter switching frequency
- **Affects:** Inductor/transformer sizing (inverse relationship)
- **Used by:** Python topology calculator, loss calculations

---

### Optional (Shown in "Show Optional Parameters" Panel)

#### Input Voltage Nominal (V)
- **Type:** Optional
- **Default:** (Vin_min + Vin_max) / 2 if not specified
- **Purpose:** Nominal operating point for duty cycle calculations
- **Affects:** Nominal duty cycle, loss calculations
- **Notes:** If empty, wizard auto-computes midpoint

#### Efficiency Target (%)
- **Type:** Optional
- **Default:** 90%
- **Range:** 0-100
- **Purpose:** Target converter efficiency for power calculations
- **Affects:** Input power = Output Power / Efficiency
- **Notes:** Influences cooling/thermal requirements

#### Diode Forward Voltage Drop (V)
- **Type:** Optional / Conditional (visible for all topologies)
- **Default:** 0.7 V
- **Range:** 0-2
- **Purpose:** Forward voltage drop of rectifier diode
- **Affects:** Duty cycle, output power budget
- **Topologies:** All isolated topologies, Buck, Boost

#### Current Ripple (%)
- **Type:** Optional / Conditional
- **Default:** 30%
- **Range:** 1-100
- **Purpose:** Maximum allowable inductor/winding current ripple
- **Affects:** Output filter inductor size, magnetizing current ripple
- **Topologies:** All topologies
- **Affects Lm Calculation:** Ripple = Vin * D / (Lm * fsw) → solve for Lm

---

### Advanced-Only Fields (Visible only in "Advanced" Design Mode)

#### Max Duty Cycle (%)
- **Type:** Advanced
- **Range:** 0-50 (typically)
- **Topology-specific visibility:**
  - **Flyback:** Yes (unique to flyback due to finite magnetizing current)
  - **Others:** No
- **Purpose:** Upper limit on duty cycle (hardware constraint)
- **Affects:** Magnetizing inductance sizing, peak current stress
- **Notes:** Flyback primary peak voltage = Vin_max + Lm * dI/dt ∝ D_max

#### Max Drain-Source Voltage (V)
- **Type:** Advanced
- **Topology-specific visibility:**
  - **Flyback:** Yes
  - **Active Clamp Forward:** Yes (leakage spike clamping)
  - **Push-Pull:** Yes
  - **Others:** No
- **Purpose:** Maximum switch voltage rating constraint
- **Affects:** Required clamp voltage/circuit design
- **Notes:** For Flyback: Vds_max = Vin_max + Vout * (Ns/Np) + leakage margin

#### Dead Time (ns)
- **Type:** Advanced
- **Range:** 10-500 ns typically
- **Topology-specific visibility:**
  - **Flyback:** Yes
  - **Others:** No
- **Purpose:** Delay between switching events to prevent cross-conduction
- **Affects:** Soft-switching margin, shooting-through losses
- **Notes:** Critical for synchronous rectification

#### Max Switch Current (A)
- **Type:** Advanced
- **Default:** Unconstrained
- **Purpose:** Switch current rating constraint
- **Affects:** Wire size, inductor design
- **Reserved for future:** Not yet implemented in all topologies

#### Load Resistance (Ω)
- **Type:** Advanced
- **Topology-specific visibility:**
  - **Buck:** Yes
  - **Boost:** Yes
  - **Others:** No
- **Purpose:** Load resistance (alternative to fixed Iout specification)
- **Affects:** Output current = Vout / R_load
- **Notes:** Allows ripple-based design vs. fixed current

---

### Multi-Output Controls

#### N Outputs Spinner
- **Type:** Control for multi-output topologies
- **Range:** 1-4 (clamped per topology max)
- **Topology-specific visibility:**
  - **Single-Switch Forward:** Yes (1-4 outputs)
  - **Flyback:** Yes (1-4 outputs)
  - **Isolated Buck:** Yes (1-4 outputs)
  - **Isolated Buck-Boost:** Yes (1-4 outputs)
  - **Others:** No
- **Controls:** +/- buttons to increment/decrement
- **Behavior:** Clicking +/- rebuilds output spec table with new row count
- **Data storage:** `data.n_outputs`, `data.converter.outputs` array

---

## Visibility Pseudocode

```
function show_field(topology, field_name, design_mode):
    meta = get_topology_metadata(topology)
    adv_mode = (design_mode == "advanced")

    // Always visible (return true immediately)
    if field_name in ["vin_min", "vin_max", "vout", "iout", "fsw"]:
        return True

    // Optional panel fields (check if panel open)
    if field_name in ["vin_nom", "efficiency"]:
        return optional_panel_visible

    // Conditional fields (check metadata)
    if field_name == "diode_vd":
        return meta.show_diode_forward_voltage

    if field_name == "current_ripple":
        return meta.show_current_ripple

    // Advanced-only conditional fields
    if field_name == "max_duty_cycle":
        if not meta.show_max_duty_cycle:
            return False
        if meta.adv_only_max_duty:
            return adv_mode
        return True

    if field_name == "max_vds":
        if not meta.show_max_vds:
            return False
        if meta.adv_only_max_vds:
            return adv_mode
        return True

    if field_name == "dead_time":
        if not meta.show_dead_time:
            return False
        if meta.adv_only_dead_time:
            return adv_mode
        return True

    if field_name == "load_resistance":
        if not meta.show_load_resistance:
            return False
        if meta.adv_only_load_resistance:
            return adv_mode
        return True

    // Multi-output control
    if field_name == "n_outputs_spinner":
        return meta.show_n_outputs_spinner

    // Default
    return False
```

---

## GUI Layout by Topology

### Two-Switch Forward Converter
```
┌─ Converter Specifications ─────────────────────┐
│ Topology: [Two-Switch Forward     ▼]           │
│ Design Mode: (◉ Auto  ○ Advanced)              │
│ Outputs: [1] +  -                              │
│ [Compute Requirements]                         │
│                                                │
│ Required Specifications                        │
│ Input Voltage Min.: [100  ] V                  │
│ Input Voltage Max.: [190  ] V                  │
│ Output Voltage:     [5    ] V                  │
│ Output Current:     [5    ] A                  │
│ Switching Frequency:[200  ] kHz                │
│                                                │
│ [Show Optional Parameters]                     │
│ ┌─ Optional Panel (hidden initially) ────┐    │
│ │ Input Voltage Nom. (opt): [145   ] V   │    │
│ │ Efficiency target:         [90    ] %   │    │
│ │ Diode forward voltage:     [0.7   ] V   │    │
│ │ Max current ripple:        [30    ] %   │    │
│ │ ... (insulation, thermal, constraints) │    │
│ └────────────────────────────────────────┘    │
└────────────────────────────────────────────────┘
```

### Flyback Converter (Auto Mode)
```
┌─ Converter Specifications ─────────────────────┐
│ Topology: [Flyback                ▼]           │
│ Design Mode: (◉ Auto  ○ Advanced)              │
│ Outputs: [2] +  -          ← N OUTPUTS VISIBLE│
│ [Compute Requirements]                         │
│                                                │
│ Required Specifications                        │
│ Input Voltage Min.: [100  ] V                  │
│ Input Voltage Max.: [190  ] V                  │
│ ┌─ Output Specification ───┐                  │
│ │ Output 1: [12  ] V [3  ] A│ ← MULTI-OUTPUT  │
│ │ Output 2: [5   ] V [10 ] A│   TABLE         │
│ └──────────────────────────┘                  │
│ Switching Frequency:[200  ] kHz                │
│ Diode forward voltage: [0.7] V                 │
│ Max current ripple:    [30 ] %                 │
│                                                │
│ [Show Optional Parameters]                     │
│ ┌─ Advanced-Only (hidden initially) ────┐     │
│ │ Max Duty Cycle (Adv):  [45  ] %       │     │
│ │ Max Drain-Source V:    [600 ] V       │     │
│ │ Dead Time (Adv):       [100 ] ns      │     │
│ │ ... (insulation, thermal, constraints)│     │
│ └────────────────────────────────────────┘    │
└────────────────────────────────────────────────┘

Note: In Auto mode, the Advanced-Only fields are HIDDEN.
```

### Flyback Converter (Advanced Mode)
```
Same as above, but Advanced-Only fields are VISIBLE:

│ Advanced-Only Fields (now VISIBLE) ────────────│
│ Max Duty Cycle:      [45  ] %                  │
│ Max Drain-Source V:  [600 ] V                  │
│ Dead Time:           [100 ] ns                 │
│                                                │
```

### Buck Converter
```
┌─ Converter Specifications ─────────────────────┐
│ Topology: [Buck                   ▼]           │
│ Design Mode: (◉ Auto  ○ Advanced)              │
│ Outputs: [1] (hidden, N-outputs not visible)   │
│ [Compute Requirements]                         │
│                                                │
│ Required Specifications                        │
│ Input Voltage Min.: [100  ] V                  │
│ Input Voltage Max.: [190  ] V                  │
│ Output Voltage:     [5    ] V  ← Standard field│
│ Output Current:     [5    ] A  ← Standard field│
│ Switching Frequency:[200  ] kHz                │
│ Diode forward voltage: [0.7] V                 │
│ Max current ripple:    [30 ] %                 │
│                                                │
│ [Show Optional Parameters]                     │
│ ┌─ Optional/Advanced ──────────────┐           │
│ │ Efficiency target:      [90  ] %  │           │
│ │ Load Resistance (Adv): [    ] Ω  │ ← Adv only│
│ │ ... (insulation, thermal, constraints)       │
│ └──────────────────────────────────┘           │
└────────────────────────────────────────────────┘
```

---

## Implementation Notes

### Tag Naming Convention
Every GUI control should have a Tag for programmatic visibility control:

```matlab
'field_vin_min'            % edit box for Vin_min
'label_vin_min'            % label "Input Voltage Min."
'unit_vin_min'             % unit label "V"

'field_vout_1'             % edit box for Vout[1] in multi-output table
'field_iout_1'             % edit box for Iout[1] in multi-output table
'field_vout_2'             % edit box for Vout[2] in multi-output table
'field_iout_2'             % edit box for Iout[2] in multi-output table
...

'field_n_outputs'          % spinner for N outputs
'btn_n_outputs_plus'       % + button
'btn_n_outputs_minus'      % - button
```

### Helper Function
`set_field_visible(fig, field_tag, is_visible)` automatically handles:
- Setting Visible property on 'field_*' control
- Setting Visible on associated 'label_*' control
- Setting Visible on associated 'unit_*' control
- Gracefully handling missing tags (no errors)

