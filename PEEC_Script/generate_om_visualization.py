#!/usr/bin/env python3
"""
Generate OpenMagnetics 2D cross-section SVG visualization.
Called from MATLAB/Octave via system() command.

Usage:
    python generate_om_visualization.py config.json

Config JSON format:
{
    "core_shape": "ETD 34/17/11",
    "material": "3C95",
    "gapping": [{"type": "subtractive", "length": 0.001}],
    "windings": [
        {"wire_name": "Round 0.5 - Grade 1", "num_turns": 10, "num_parallels": 1, "isolation_side": "primary"},
        {"wire_name": "Round 0.5 - Grade 1", "num_turns": 5, "num_parallels": 1, "isolation_side": "secondary"}
    ],
    "output_svg": "om_visualization.svg",
    "plot_type": "magnetic"
}

Requires: pip install PyMKF
"""

import PyOpenMagnetics as pm
import json
import sys
import os


def generate_visualization(config):
    """Build magnetic from config and generate SVG."""

    core_shape_name = config['core_shape']
    material_name = config['material']
    gapping = config.get('gapping', [])
    windings = config.get('windings', [])
    plot_type = config.get('plot_type', 'magnetic')
    output_svg = config.get('output_svg', 'om_visualization.svg')

    # 1. Get shape and material as full dict objects
    shape = pm.find_core_shape_by_name(core_shape_name)
    material = pm.find_core_material_by_name(material_name)

    # 2. Build core functional description
    core_data = {
        'functionalDescription': {
            'name': 'gui_core',
            'type': 'two-piece set',
            'shape': shape,
            'material': material,
            'gapping': gapping if gapping else [],
            'numberStacks': 1
        }
    }

    # 3. Calculate full core data
    core_full = pm.calculate_core_data(core_data, True)

    # 4. Create bobbin
    bobbin = pm.create_basic_bobbin(core_full, False)

    # 5. Build coil functional description
    coil_func = []
    for i, w in enumerate(windings):
        wire_name = w.get('wire_name', 'Round 0.5 - Grade 1')
        try:
            wire = pm.get_wire_data_by_name(wire_name)
        except Exception:
            # Fallback: try without exact match
            wire = pm.get_wire_data_by_name('Round 0.5 - Grade 1')

        winding_entry = {
            'name': w.get('name', f'winding_{i}'),
            'numberTurns': w.get('num_turns', 10),
            'numberParallels': w.get('num_parallels', 1),
            'wire': wire,
            'isolationSide': w.get('isolation_side', 'primary')
        }
        coil_func.append(winding_entry)

    # 6. Assemble magnetic
    magnetic = {
        'core': core_full,
        'coil': {
            'bobbin': bobbin,
            'functionalDescription': coil_func
        }
    }

    # 7. Autocomplete to fill in sections, layers, turns
    mag_complete = pm.magnetic_autocomplete(magnetic, {})

    # 8. Generate SVG
    if plot_type == 'core':
        result = pm.plot_core(mag_complete)
    elif plot_type == 'bobbin':
        result = pm.plot_bobbin(mag_complete)
    else:
        result = pm.plot_magnetic(mag_complete)

    if not result.get('success', False):
        error_msg = result.get('error', 'Unknown error')
        print(f'ERROR: {error_msg}', file=sys.stderr)
        return False

    # 9. Write SVG to file
    svg_content = result['svg']
    with open(output_svg, 'w') as f:
        f.write(svg_content)

    print('OK')
    return True


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: python generate_om_visualization.py config.json', file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]
    if not os.path.exists(config_path):
        print(f'ERROR: Config file not found: {config_path}', file=sys.stderr)
        sys.exit(1)

    with open(config_path, 'r') as f:
        config = json.load(f)

    success = generate_visualization(config)
    sys.exit(0 if success else 1)
