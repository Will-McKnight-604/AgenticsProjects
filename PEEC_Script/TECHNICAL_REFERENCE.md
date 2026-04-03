# Technical Reference

Consolidated technical reference for the PEEC Script project: a MATLAB/Octave electromagnetic simulation tool for transformer/inductor design using a 2D PEEC field solver, integrated with OpenMagnetics for component databases and design recommendations.

---

## 1. System Architecture

### Three-Layer Design

```
1. GUI Layer          - MATLAB/Octave interactive three-panel interface
2. Analysis Engine    - PEEC electromagnetic field solver (frequency domain)
3. Integration Layer  - OpenMagnetics API for real component data + design adviser
```

### Data Flow

```
User Input (GUI)
    |
Wire/Core Selection (OpenMagnetics API or local cache)
    |
Winding Layout Calculation
    |
Conductor Geometry Build (multi-filar)
    |
PEEC Geometry Construction (filament discretization)
    |
Electromagnetic Analysis (frequency domain solver)
    |
Results Visualization (current/loss density plots)
```

### Key Files

| File | Purpose |
|------|---------|
| `interactive_winding_designer.m` | Main GUI application (~2000 lines). Three-panel layout: Core, Windings, Visualization. |
| `topology_wizard.m` | Topology wizard GUI for converter design requirements. 9 topologies with dynamic field visibility. |
| `topology_metadata.m` | Registry of all 9 topologies with field metadata (27 fields). |
| `topology_field_visibility_system.m` | Dynamic show/hide of GUI fields based on topology. |
| `build_mas_structure.m` | Converts MATLAB GUI data to MAS JSON format. |
| `call_pyopenmagnetics_api.py` | Python bridge: calls PyOpenMagnetics adviser APIs. |
| `generate_om_topology.py` | Topology calculator: computes Lm, duty, turns, waveforms for 9 topologies. |
| `generate_om_recommendations.py` | Python wrapper (~1430 lines) for PyOpenMagnetics adviser with post-filtering. |
| `generate_om_visualization.py` | Python visualization: builds MAS objects for OpenMagnetics 3D/section views. |
| `generate_om_excitation.py` | Builds MAS excitation waveforms from topology parameters. |
| `openmagnetics_api_interface.m` | MATLAB interface to the Python OpenMagnetics scripts. |
| `om_client.m` | HTTP client for the local OpenMagnetics server (online mode). |
| `om_server.py` | Local Flask server wrapping PyOpenMagnetics. |

### File Dependencies

```
topology_wizard.m (GUI)
  +-- topology_metadata.m
  +-- topology_field_visibility_system.m
  +-- build_mas_structure.m (GUI values -> MAS JSON)
  +-- call_pyopenmagnetics_api.py
  |     +-- generate_om_recommendations.py
  |     +-- PyOpenMagnetics (pm.process_inputs, pm.calculate_advised_magnetics)
  +-- generate_om_topology.py (computes design requirements + waveforms)
  +-- interactive_winding_designer.m (receives selected design)

interactive_winding_designer.m (GUI)
  +-- openmagnetics_api_interface.m
  +-- om_client.m (online mode HTTP calls)
  +-- generate_om_visualization.py
  +-- generate_om_excitation.py
```

---

## 2. OpenMagnetics Server Setup

### Requirements
- Python 3.11.x 64-bit (required for PyOpenMagnetics compatibility)
- Windows 10/11

### Installation

```powershell
# Create virtual environment (recommended)
C:\Users\Will\AppData\Local\Programs\Python\Python311\python.exe -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install PyOpenMagnetics flask
```

### Running the Server

```powershell
# Keep this window open while using the GUI
python om_server.py --port 8484
```

### Verification

```powershell
Invoke-RestMethod http://localhost:8484/health
# Expected: status=ok, pyom_available=true
```

### Troubleshooting
- If `python --version` shows 3.14, use the full path to Python 3.11
- If pip install fails with long path errors, set `TEMP`/`TMP` to a short path
- If GUI health check fails, confirm `/health` returns JSON in browser
- Use `Invoke-RestMethod` instead of `curl` in PowerShell (avoids access denied errors)
- Server must stay running while GUI is in Online mode

---

## 3. MAS (Magnetic Agnostic Structure) Schema

MAS is the standardized JSON format for describing magnetic components. All values use SI base units (meters, Hz, Henry, Ampere, Volt, Celsius).

### Document Structure

```json
{
  "inputs": {
    "designRequirements": { ... },
    "operatingPoints": [ ... ]
  },
  "magnetic": {
    "core": { ... },
    "coil": { ... }
  },
  "outputs": [ ... ]
}
```

### Design Requirements

| Field | Type | Description |
|-------|------|-------------|
| `magnetizingInductance` | DimensionWithTolerance | Required inductance |
| `turnsRatios` | Array | Secondary/primary ratios (empty for inductor) |
| `topology` | String | Circuit topology |
| `insulation` | Object | Safety requirements (optional) |
| `maximumDimensions` | Object | {width, height, depth} in meters (optional) |
| `operatingTemperature` | DimensionWithTolerance | Temperature limits (optional) |

### DimensionWithTolerance Pattern

Used throughout MAS for numeric values with tolerances. At least one numeric value required:

```json
{"nominal": 100e-6, "minimum": 90e-6, "maximum": 110e-6}
```

### Operating Points

Each operating point contains conditions (ambient temperature, cooling) and excitations per winding (frequency, current, voltage waveforms).

Waveform signals can be defined at three levels:
1. **Waveform** (raw): `data` array + optional `time` array
2. **Processed**: `label`, `peakToPeak`, `offset`, `dutyCycle`, `rms`, `effectiveFrequency`
3. **Harmonics**: `amplitudes` + `frequencies` arrays

### Waveform Labels

| Label | Use Case |
|-------|----------|
| `Triangular` | Inductor current, magnetizing current |
| `Rectangular` | Inductor voltage, transformer primary current |
| `Sinusoidal` | LLC, resonant, AC applications |
| `Flyback Primary` | Flyback primary current (ramp + discontinuous jump) |
| `Flyback Secondary` | Flyback secondary current |
| `Custom` | User-defined with data points |

### Core Specification

```json
{
  "functionalDescription": {
    "type": "two-piece set",
    "material": "N97",
    "shape": "E 55/28/21",
    "gapping": [
      {"type": "subtractive", "length": 0.001},
      {"type": "residual", "length": 0.00001},
      {"type": "residual", "length": 0.00001}
    ],
    "numberStacks": 1
  }
}
```

Core types: `"two-piece set"`, `"toroidal"`, `"closed shape"`, `"piece and plate"`

Gapping types: `"subtractive"` (ground gap), `"additive"` (spacer), `"residual"` (mating surfaces), `"distributed"`

### Core Shape Names (exact format required)

| Family | Examples |
|--------|----------|
| E | `"E 19/8/5"`, `"E 42/21/15"`, `"E 55/28/21"` |
| ETD | `"ETD 29/16/10"`, `"ETD 34/17/11"`, `"ETD 49/25/16"` |
| PQ | `"PQ 20/16"`, `"PQ 26/25"`, `"PQ 35/35"` |
| RM | `"RM 6"`, `"RM 8"`, `"RM 10"`, `"RM 12"` |
| Toroid | `"T 20/10/7"`, `"T 40/24/16"` |

### Core Materials

| Manufacturer | Examples |
|-------------|----------|
| TDK/EPCOS | `"N49"`, `"N87"`, `"N95"`, `"N97"` |
| Ferroxcube | `"3C90"`, `"3C95"`, `"3C97"`, `"3F46"` |
| Magnetics Inc | `"MPP"`, `"High Flux"`, `"XFlux"` |

### Wire Types

| Type | Format | Example |
|------|--------|---------|
| Round | `Round <dia_mm> - Grade <1-3>` | `"Round 1.0 - Grade 1"` |
| Litz | `Litz <strands>x<strand_dia> - Grade <1-3>` | `"Litz 40x0.1 - Grade 1"` |
| Rectangular | `Rectangular <w>x<h> - Grade <1-3>` | `"Rectangular 2.0x0.5 - Grade 1"` |
| Foil | `Foil <thickness_mm>` | `"Foil 0.1"` |

### Coil Specification

```json
{
  "coil": {
    "bobbin": "E 55/28/21",
    "functionalDescription": [
      {"name": "Primary", "numberTurns": 42, "numberParallels": 1,
       "wire": "Round 1.0 - Grade 1", "isolationSide": "primary"},
      {"name": "Secondary", "numberTurns": 21, "numberParallels": 2,
       "wire": "Litz 60x0.1 - Grade 1", "isolationSide": "secondary"}
    ]
  }
}
```

### Insulation Requirements

```json
{
  "insulation": {
    "insulationType": "Reinforced",
    "overvoltageCategory": "OVC-II",
    "pollutionDegree": "P2",
    "altitude": {"maximum": 2000},
    "cti": "Group IIIA",
    "standards": ["IEC 62368-1"]
  }
}
```

Insulation types: `Functional`, `Basic`, `Supplementary`, `Double`, `Reinforced`

Overvoltage categories: `OVC-I` through `OVC-IV`

### Enumeration Values

Topologies: `Buck`, `Boost`, `BuckBoost`, `Flyback`, `Forward`, `PushPull`, `HalfBridge`, `FullBridge`, `LLC`, `DAB`, `CurrentTransformer`, `CommonModeChoke`

Markets: `Commercial`, `Industrial`, `Medical`, `Military`, `Space`

---

## 4. Topology Wizard

### Supported Topologies (9)

| Key | Display Name | Isolated | Output Type | MAS Topology Key |
|-----|-------------|----------|-------------|------------------|
| `two_switch_forward` | Two-Switch Forward | Yes | Multi (1-4) | `two-switch-forward` |
| `single_switch_forward` | Single-Switch Forward | Yes | Multi (1-4) | `single-switch-forward` |
| `active_clamp_forward` | Active Clamp Forward | Yes | Multi (1-4) | `active-clamp-forward` |
| `flyback` | Flyback | Yes | Multi (1-4) | `flyback` |
| `push_pull` | Push-Pull | Yes | Multi (1-4) | `push-pull` |
| `buck` | Buck | No | Single | `buck` |
| `boost` | Boost | No | Single | `boost` |
| `isolated_buck` | Isolated Buck | Yes | Multi (1-4) | `isolated-buck` |
| `isolated_buck_boost` | Isolated Buck-Boost | Yes | Multi (1-4) | `isolated-buck-boost` |

### Field Visibility Matrix

| Field | Two-Sw-Fwd | Flyback | Buck | Boost | Push-Pull | Iso-Buck |
|-------|:---:|:---:|:---:|:---:|:---:|:---:|
| Input Voltage Min/Max | Y | Y | Y | Y | Y | Y |
| Output Voltage/Current | Y | Y | Y | Y | Y | Y |
| Switching Frequency | Y | Y | Y | Y | Y | Y |
| Diode Fwd Voltage | Y | Y | Y | Y | Y | Y |
| Current Ripple % | Y | Y | Y | Y | Y | Y |
| N Outputs Spinner | N | Y | N | N | N | Y |
| Max Duty Cycle | N | Adv | N | N | N | N |
| Max Drain-Source V | N | Adv | N | N | Adv | N |
| Dead Time | N | Adv | N | N | N | N |
| Load Resistance | N | N | Adv | Adv | N | N |

Y=Always visible, Adv=Advanced mode only, N=Hidden

### MATLAB Data Structure (topology_wizard.m)

```matlab
data.converter.vin_min          % V
data.converter.vin_max          % V
data.converter.vin_nom          % V (optional, auto-computed as midpoint)
data.converter.vout             % V
data.converter.iout             % A
data.converter.fsw_khz          % kHz
data.converter.efficiency       % percent (90)
data.converter.vd               % V (0.7, diode forward drop)
data.converter.max_ripple       % percent (30)
data.converter.max_duty         % percent (flyback only)
data.converter.max_switch_current  % A
data.converter.n_outputs        % int (1-4)

data.topology                   % string: 'two_switch_forward', etc.
data.design_mode                % 'auto' | 'advanced'

data.insulation.class           % 'Basic'|'Functional'|'Supplementary'|'Reinforced'|'Double'
data.insulation.standard        % 'IEC 62368-1', etc.
data.insulation.pollution_degree % 1|2|3
data.insulation.overvoltage_cat  % 'I'|'II'|'III'|'IV'
data.insulation.cti             % 'Group I'|'II'|'IIIA'|'IIIB'
data.insulation.altitude_max    % m (2000)

data.thermal.ambient_temp       % C (25)

data.rec.n_results              % int (5)
data.rec.weight_cost            % float (1/3)
data.rec.weight_losses          % float (1/3)
data.rec.weight_dimensions      % float (1/3)
```

### MAS Input Mapping per Topology

| Topology | MAS File | Required Global Fields | Output Format |
|----------|----------|----------------------|---------------|
| Forward family | forward.json | inputVoltage, diodeVoltageDrop, currentRippleRatio | Multi: `outputVoltages[]`, `outputCurrents[]` |
| Flyback | flyback.json | inputVoltage, diodeVoltageDrop, currentRippleRatio, efficiency | Multi: `outputVoltages[]`, `outputCurrents[]` |
| Buck | buck.json | inputVoltage, diodeVoltageDrop | Single: `outputVoltage`, `outputCurrent` |
| Boost | boost.json | inputVoltage, diodeVoltageDrop | Single: `outputVoltage`, `outputCurrent` |
| Isolated Buck/Buck-Boost | isolatedBuck/BuckBoost.json | inputVoltage, diodeVoltageDrop | Multi: `outputVoltages[]`, `outputCurrents[]` |
| Push-Pull | pushPull.json | inputVoltage, diodeVoltageDrop, currentRippleRatio | Multi: `outputVoltages[]`, `outputCurrents[]` |

### Waveform Label Mapping per Topology

| Topology | Primary V | Primary I | Secondary V | Secondary I |
|----------|-----------|-----------|-------------|-------------|
| Forward family | RECTANGULAR | RECTANGULAR | SEC_RECTANGULAR | RECTANGULAR |
| Flyback | RECTANGULAR | FLYBACK_PRIMARY | SEC_RECTANGULAR | FLYBACK_SECONDARY |
| Buck/Boost | RECTANGULAR | TRIANGULAR | - | - |
| Isolated Buck/Buck-Boost | RECTANGULAR | TRIANGULAR | RECTANGULAR | TRIANGULAR |

---

## 5. MATLAB-Python Integration Pipeline

### Recommendation Pipeline

```
topology_wizard.m
  -> build_mas_structure(gui_data, topology_key)  [MATLAB -> MAS JSON]
  -> system("python call_pyopenmagnetics_api.py config.json results.json 5 STANDARD_CORES")
     -> pm.process_inputs(mas)          [validate + add harmonics, ~100ms]
     -> pm.calculate_advised_magnetics() [core+winding search, 10-30s]
  -> jsondecode(fileread('results.json'))
  -> display results in GUI
  -> user selects design -> interactive_winding_designer.m
```

### Unit Conversions in build_mas_structure.m

- Percentages (efficiency, ripple, duty) -> decimals (divide by 100)
- kHz -> Hz (multiply by 1000)
- Topology keys: snake_case (`two_switch_forward`) -> kebab-case (`two-switch-forward`)
- `vin_nom`: auto-computed as `(vin_min + vin_max) / 2` if empty

### call_pyopenmagnetics_api.py

Usage: `python call_pyopenmagnetics_api.py <config.json> [results.json] [max_results] [core_mode]`

- `core_mode`: `STANDARD_CORES` (679 cores, faster) or `ALL_CORES` (4000+, slow)
- Returns JSON: `{status: "OK"|"ERROR", count: N, data: [{core_name, losses_total, losses_core, losses_winding, temperature_core, temperature_winding, magnetic, scoring}, ...]}`
- Python fallback chain: Octave bundled Python 3.12 -> `py -3.11` -> system Python 3.11
- 600-second subprocess timeout

### Performance Characteristics

| Stage | Time | Notes |
|-------|------|-------|
| build_mas_structure() | <1 ms | Pure MATLAB |
| JSON encoding | ~10 ms | |
| Python startup + DB load | 2-3s | Cached after first call |
| pm.process_inputs() | ~100 ms | Validation + harmonics |
| pm.calculate_advised_magnetics() | 10-30s | Database search (2 windings) |
| Total pipeline | ~30-35s | Typical for 2-winding design |

For 3+ windings, multiply CoilAdviser time by 3-10x due to combinatorial explosion.

---

## 6. PyOpenMagnetics Adviser Algorithm

### Three-Stage C++ Pipeline

**Stage 1 - Core Selection (CoreAdviser):**
All ~1271 cores are filtered through: material application check -> toroid/concentric exclusion -> gap processing -> AreaProduct filter (Aw x Ae >= required) -> EnergyStored filter (L x I^2/2 capacity) -> initial turns computation -> Cost/Dimensions/Losses scoring.

Scoring: `final_score = sum(normalized_score_i * weight_i)` for COST (log, inverted), EFFICIENCY (log, inverted), DIMENSIONS (linear, inverted).

**Stage 2 - Winding Optimization (CoilAdviser):**
For each surviving core (up to 50): generates winding patterns x repetitions, searches ~4329 wires with 4 configurations per winding (2 J_max x 2 parallel options), evaluates Cartesian product of wire choices across windings. This is the primary bottleneck.

**Stage 3 - Full Simulation (MagneticSimulator):**
For each wound design: Steinmetz/iGSE core losses with temperature iteration, PEEC winding losses, inductance verification, thermal convergence loop.

### Key Hardcoded Parameters

| Parameter | Value | Impact |
|-----------|-------|--------|
| maxEvaluatedCores | 50 | Hard cap on cores entering CoilAdviser |
| Wire configurations | 4 per winding | 2 J_max x 2 parallel limits |
| B_peak reference | 0.18 T | AreaProduct pre-filter threshold |
| Subprocess timeout | 600 seconds | Python wrapper kill timeout |

### Database Sizes

| Database | Entries |
|----------|---------|
| Cores | 1,271 |
| Materials | 409 (94 with Steinmetz data) |
| Wires | 4,329 |

### Known Issues

1. **Oversized core recommendations for transformers**: `process_inputs()` inflates `magnetizingCurrent.peak` by adding DC load current offset. Fix: pre-populate `magnetizingCurrent` field in primary excitation with correct small-ripple waveform before calling `process_inputs()`.

2. **C++ segfault with insulation + 3+ windings**: MKF crashes (ACCESS_VIOLATION) with insulation data on multi-winding topologies. Workaround: strip insulation before adviser call, restore after.

3. **Slow/unreliable for multi-winding**: CoilAdviser timeout formula `1 - numberWindings` gives almost no search budget for 3+ windings.

### Optimization Strategies (not yet implemented)

- **Pre-filtering**: Add GUI controls for core shape family, manufacturer, material type to reduce search space before calling adviser
- **Settings tuning**: Reduce `coreAdviserMaximumMagneticsAfterFiltering` from ~500 to 100, disable unwanted wire types
- **Two-pass strategy**: Quick core-only pass (~1-5s) for preview, detailed pass on user-selected cores

---

## 7. Interactive Winding Designer

### GUI Panels

1. **Left - Core Selection**: Core shape dropdown, material selection, operating frequency
2. **Center - Winding Configuration**: Tabbed per winding, wire type, turns, multi-filar (1-4), current magnitude/phase
3. **Right - Visualization**: Geometry, Schematic, Packing (orthocyclic/layered/random), 3D Preview

### Default Configuration

```matlab
data.sigma = 5.8e7;          % Copper conductivity (S/m)
data.mu0 = 4*pi*1e-7;        % Permeability of free space
data.f = 100e3;               % Operating frequency (Hz)
data.Nx = 6;                  % Filaments per conductor (X)
data.Ny = 6;                  % Filaments per conductor (Y)
data.gap_layer = 0.2e-3;      % Gap between layers (m)
data.gap_filar = 0.05e-3;     % Gap between parallel strands (m)
data.gap_winding = 1e-3;      % Gap between windings (m)
```

### Insulation Support

- IEC 60664-style lookup tables for clearance/creepage/withstand
- User inputs: Voltage, Insulation Class, Tape Thickness, Tape Strength, TIW kV, Edge Margin
- Inter-winding physical spacing depends on tape stack, not voltage directly
- Wire insulation types: Standard vs TIW (Triple Insulated Wire) per winding
- TIW variant lookup: if TIW wire not found in database, falls back to standard wire

### Data Mode

- **Offline**: Uses local cached data (`openmagnetics_cache.mat`)
- **Online**: Fetches from local OpenMagnetics server, normalizes to match local schema, caches for offline use

---

## 8. Web Frontend Architecture (OpenMagnetics Web)

### Stack

- **Frontend**: Vue 3 SPA (Vite + Pinia + Bootstrap), MKF/WASM client-side computation
- **Backend**: FastAPI, Celery + RabbitMQ for async tasks, PyMKF + OpenMagnetics Virtual Builder
- **Database**: Postgres/Mongo/SQLite cache

### Main Workflows

1. **Magnetic Builder**: Home -> /magnetic_tool -> Design Requirements -> Operating Points -> Magnetic Builder -> Summary/Export
2. **Catalog**: Home -> /catalog_tool -> Design Requirements -> Operating Points -> Catalog Adviser -> Viewer
3. **Wizards**: Home -> /wizards_landing -> Pick wizard -> /wizards -> Generate MAS inputs -> Review in /magnetic_tool or go directly to design
4. **Cross-Referencer**: Selection page -> Core/Shape/Material cross-referencer -> Details + export

### Wizard Components

All converter wizards use `ConverterWizardBase.vue` with 3-column layout (design params | voltage/outputs | waveform viewer). Common buttons: Analytical, Simulated, Review Specs, Design Magnetic.

Wizard IDs: `commonModeChoke`, `differentialModeChoke`, `flyback`, `buck`, `boost`, `isolatedBuck`, `isolatedBuckBoost`, `pushPull`, `singleSwitchForward`, `twoSwitchForward`, `activeClampForward`, `pfc`, `dualActiveBridge`, `llcResonant`, `cllcResonant`, `phaseShiftFullBridge`

Shared components map: Buck+Boost -> `BuckBoostWizard`, Forward family -> `ForwardWizard`, IsolatedBuck+BuckBoost -> `IsolatedBuckBoostWizard`.

Wizard computations are frontend MKF/WASM-driven via `taskQueue` store. No dedicated wizard endpoints in the backend.

### Backend API Endpoints

`/get_notifications`, `/report_bug`, `/core_compute_shape_stl`, `/core_compute_shape_stp`, `/core_compute_core_3d_model_stl`, `/core_compute_core_3d_model_stp`, `/core_compute_gapping_technical_drawing`, `/plot_core`, `/plot_core_and_fields`, `/plot_wire`, `/plot_wire_and_current_density`, `/process_latex`, `/insert_mas`, `/insert_intermediate_mas`, `/load_external_core_materials`, `/create_simulation_from_mas`, `/is_high_performance_backend_available`

### Frontend Dependencies

Git submodules: `WebSharedComponents`, `MagneticBuilder`

Pinia stores: `state`, `style`, `settings`, `taskQueue`, `masStore`

---

## 9. Design Decisions

### Why Direct PyOpenMagnetics API Instead of Hand-Coded Equations

The original approach (`generate_om_topology.py`) used hand-coded topology equations to compute Lm, turns ratio, duty cycle, and currents. This was replaced with direct PyOpenMagnetics API calls because:

1. PyOpenMagnetics uses physics-based models (Faraday's law, reluctance networks, Steinmetz loss models)
2. Topology-aware: the adviser understands each topology's operating conditions
3. Full material database access (679+ core shapes, 409 materials, 4329+ wires)
4. Automatic winding design with loss/temperature calculations
5. Single source of truth (MKF C++ engine) instead of duplicated equations

### Why Topology Metadata is Data-Driven

Field visibility was originally hardcoded with boolean flags (`is_isolated`, `is_forward`, etc.). The data-driven metadata system (`topology_metadata.m`) maps each topology to its field requirements, making it easy to add new topologies or modify field visibility without touching callback logic.

### Why Magnetizing Current Must Be Pre-Populated for Transformers

For forward-type transformers, `process_inputs()` incorrectly adds the DC load current component to the magnetizing current calculation. This inflates energy storage requirements by ~290x, causing absurdly oversized core recommendations. Pre-populating the `magnetizingCurrent` field in the primary excitation with the correct small AC ripple waveform causes `process_inputs()` to skip its calculation entirely.

### Octave Compatibility

The codebase must run on Octave 10.3+. Key constraints:
- No `contains()` function (use `strfind` or equivalent)
- Octave bundles Python 3.12 which lacks PyOpenMagnetics; the Python fallback chain finds Python 3.11
- `webread`/`webwrite` response parsing requires robust JSON handling in `om_client.m`
