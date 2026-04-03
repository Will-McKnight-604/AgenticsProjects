# PEEC Magnetic Design Platform

A cross-language electromagnetic design tool for power transformer and inductor optimization. Specify your converter topology and requirements, and the platform automatically recommends optimal core/winding combinations with full electromagnetic loss analysis.

---

## What It Does

Power electronics engineers typically spend weeks manually iterating through core shapes, wire gauges, and winding layouts to arrive at an optimal magnetic design. This tool collapses that process into minutes:

1. **Select a converter topology** and enter your electrical specs (voltage, current, frequency)
2. **The platform computes** magnetizing inductance, turns ratio, duty cycle, and excitation waveforms
3. **OpenMagnetics searches** 679+ core shapes and 4,329+ wire options to find viable designs
4. **Designs are ranked** by cost, efficiency, and size on a Pareto front
5. **Select a design** and enter the interactive winding designer for detailed loss analysis

```
 Converter Specs          Topology Equations         Component Search         Loss Analysis
+-----------------+     +------------------+     +------------------+     +------------------+
| Vin, Vout, Fsw  | --> | Lm, N, D, duty   | --> | Core + Wire DB   | --> | PEEC 2D Solver   |
| Iout, Topology  |     | Waveform builder |     | Pareto ranking   |     | Proximity losses |
+-----------------+     +------------------+     +------------------+     +------------------+
```

---

## Supported Topologies

| Isolated | Non-Isolated |
|----------|-------------|
| Two-Switch Forward | Buck |
| Single-Switch Forward | Boost |
| Active Clamp Forward | |
| Flyback | |
| Push-Pull | |
| Isolated Buck | |
| Isolated Buck-Boost | |

---

## Tool Workflow

### Stage 1: Topology Wizard (`topology_wizard.m`)

The entry point. A MATLAB/Octave GUI where you specify your converter:

```
+---------------------------------------------------------------+
|  TOPOLOGY WIZARD                                              |
|                                                               |
|  Topology:  [Two-Switch Forward v]                            |
|                                                               |
|  Input Voltage:    400 V        Output Voltage:   12 V        |
|  Switching Freq:   100 kHz      Output Current:   20 A        |
|  Current Ripple:   30%          Ambient Temp:     40 C        |
|                                                               |
|  [Compute Requirements]  [Get Recommendations]                |
+---------------------------------------------------------------+
```

The wizard dynamically shows/hides input fields based on the selected topology, computes the magnetic requirements (inductance, turns ratio, waveforms), and calls the OpenMagnetics adviser to return ranked design recommendations.

### Stage 2: Interactive Winding Designer (`interactive_winding_designer.m`)

Select a recommended design and enter the three-panel winding designer:

```
+-------------------+---------------------+---------------------+
|   CORE SELECTION  |  WINDING CONFIG     |  VISUALIZATION      |
|                   |                     |                     |
|  Core: E 55/28/21 |  Primary:           |   +-----------+    |
|  Material: N97    |    Wire: AWG 24     |   |  .  .  .  |    |
|  Gap: 0.5 mm      |    Turns: 32        |   |  .  .  .  |    |
|                   |    Layers: 4        |   |  o  o  o  |    |
|  Winding Area:    |    Filar: 1         |   |  o  o  o  |    |
|  12.3 x 8.1 mm   |                     |   +-----------+    |
|                   |  Secondary:         |   2D Cross-Section  |
|  Fill Factor:     |    Wire: AWG 18     |                     |
|  0.42             |    Turns: 4         |  [Geometry] [Schema]|
|                   |    Layers: 1        |  [Packing]  [3D]   |
+-------------------+---------------------+---------------------+
```

Features:
- Multi-filar winding support (1-4 parallel strands)
- Wire types: round, Litz, rectangular, foil
- IEC 60664 insulation clearance/creepage tables
- Real-time 2D cross-section, schematic, packing, and 3D views

### Stage 3: PEEC Electromagnetic Analysis

The built-in 2D PEEC (Partial Element Equivalent Circuit) solver computes:

- **Proximity effect losses** between adjacent windings
- **Skin effect** via sub-filament discretization
- **Current density distribution** across conductor cross-sections
- **Frequency-domain impedance** (R + jwL matrices)

```
 Conductor Cross-Section          Current Density Map
+---+---+---+---+---+          +---+---+---+---+---+
| . | . | . | . | . |          |   | * | **| * |   |
+---+---+---+---+---+          +---+---+---+---+---+
| . | . | . | . | . |   --->  | * | **|***| **| * |
+---+---+---+---+---+          +---+---+---+---+---+
| . | . | . | . | . |          |   | * | **| * |   |
+---+---+---+---+---+          +---+---+---+---+---+
  Uniform filament grid          Higher density at edges
                                 (proximity + skin effect)
```

---

## Architecture

The platform bridges three languages through JSON config files:

```
MATLAB/Octave GUI
    |
    |  writes JSON configs
    v
Python Scripts (topology equations, API bridges)
    |
    |  calls C++ bindings via pybind11
    v
OpenMagnetics / MKF (C++ electromagnetic solver + component databases)
    |
    |  returns JSON results
    v
MATLAB/Octave GUI (displays results, visualizations)
```

### File Map

```
PEEC_Script/
|
|-- topology_wizard.m                  Entry point GUI
|-- interactive_winding_designer.m     Winding designer + analysis GUI
|
|-- Topology & Recommendations
|   |-- generate_om_topology.py        Computes Lm, duty, turns ratio for 9 topologies
|   |-- generate_om_recommendations.py Calls OpenMagnetics adviser, ranks designs
|   |-- call_converter_api.py          Full pipeline: specs -> adviser -> results
|   |-- call_pyopenmagnetics_api.py    Low-level PyOpenMagnetics interface
|   |-- om_shared.py                   Shared utilities (type coercion, logging)
|
|-- Winding Analysis
|   |-- openmagnetics_api_interface.m  Database queries (cores, wires, materials)
|   |-- openmagnetics_winding_layout.m Winding geometry computation
|   |-- generate_om_excitation.py      Harmonic excitation waveform builder
|   |-- generate_om_visualization.py   SVG cross-section rendering
|   |-- generate_om_waveforms.py       Waveform generation for viewer
|
|-- PEEC Solver
|   |-- peec_build_geometry.m          Discretizes conductors into filament grid
|   |-- peec_solve_frequency.m         Frequency-domain impedance solver
|   |-- compute_winding_inductance_matrix.m  Mutual inductance calculation
|
|-- Visualization
|   |-- plot_current_density.m         Current density heatmap
|   |-- plot_loss_density.m            Loss density visualization
|   |-- parse_om_svg.m                 SVG parser for winding cross-sections
|   |-- design_requirements_figure.m   Requirements summary display
|   |-- topology_waveform_viewer.m     Voltage/current waveform plots
|
|-- Supporting
|   |-- topology_metadata.m            Topology definitions and field rules
|   |-- get_topology_metadata.m        Metadata accessor
|   |-- om_client.m                    HTTP client for OpenMagnetics server
|   |-- export_openmagnetics_database.py  Core/material DB export
|   |-- export_wire_database.py        Wire DB export
|
|-- experimental_backends/             Future solver enhancements
|-- validation/                        Regression test suite
```

---

## Requirements

- **MATLAB** or **GNU Octave 10.3+**
- **Python 3.11** (OpenMagnetics compatibility)
- **OpenMagnetics** Python package (`pip install PyOpenMagnetics`)

### Quick Start

```bash
# 1. Install Python dependencies
pip install PyOpenMagnetics

# 2. Launch the topology wizard in MATLAB/Octave
topology_wizard
```

---

## Performance

| Stage | Typical Time |
|-------|-------------|
| GUI to MAS specification | < 1 ms |
| Python startup + DB load | 2-3 s (cached after first call) |
| OpenMagnetics adviser search | 10-30 s (2-winding design) |
| PEEC frequency solve | 1-5 s per frequency point |
| **Total design cycle** | **~35 s** |

---

## Component Database Coverage

| Category | Count |
|----------|-------|
| Core shapes (E, ETD, PQ, RM, Toroid) | 679+ |
| Wire options (round, Litz, rectangular, foil) | 4,329+ |
| Materials (TDK, Ferroxcube, Magnetics Inc) | 50+ |

---

## License

This project is for personal/research use.
