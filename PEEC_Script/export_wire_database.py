#!/usr/bin/env python3
"""
Export OpenMagnetics wire database to JSON for MATLAB/Octave consumption.
Uses PyOpenMagnetics (PyMKF) directly - no HTTP server needed.

Usage:
    python export_wire_database.py              # Export foil wires only
    python export_wire_database.py --all        # Export all wire types
    python export_wire_database.py --types foil rectangular  # Export specific types
"""

import PyOpenMagnetics as pm
import json
import sys
import os

def extract_nominal(field):
    """Extract the nominal value from a PyOpenMagnetics dimension field."""
    if field is None:
        return None
    if isinstance(field, (int, float)):
        return field
    if isinstance(field, dict):
        nom = field.get('nominal')
        if nom is not None:
            return nom
        # Try maximum or minimum if nominal is missing
        mx = field.get('maximum')
        mn = field.get('minimum')
        if mx is not None and mn is not None:
            return (mx + mn) / 2
        return mx or mn
    return None


def export_wires(wire_types=None, output_file='openmagnetics_wire_database.json'):
    """Export wire database to JSON file.

    Args:
        wire_types: List of types to export, e.g. ['foil', 'rectangular'].
                    None = foil only.
        output_file: Output JSON file path.
    """
    if wire_types is None:
        wire_types = ['foil']

    all_names = pm.get_wire_names()
    print(f"Total wires in database: {len(all_names)}")

    # Get all wire data and filter by type
    exported = {}
    type_counts = {}

    for name in all_names:
        try:
            wire = pm.get_wire_data_by_name(name)
        except Exception as e:
            print(f"  Warning: Could not get data for '{name}': {e}")
            continue

        wtype = wire.get('type', '')
        if wtype and wtype.lower() in [t.lower() for t in wire_types]:
            # Flatten the nested nominal structure for easier MATLAB consumption
            flat = {
                'name': wire.get('name', name),
                'type': wtype,
                'material': wire.get('material', 'copper'),
                'standard': wire.get('standard'),
                'numberConductors': wire.get('numberConductors', 1),
            }

            # Extract dimensions (flatten .nominal)
            flat['conductingWidth'] = extract_nominal(wire.get('conductingWidth'))
            flat['conductingHeight'] = extract_nominal(wire.get('conductingHeight'))
            flat['conductingArea'] = extract_nominal(wire.get('conductingArea'))
            flat['conductingDiameter'] = extract_nominal(wire.get('conductingDiameter'))
            flat['outerDiameter'] = extract_nominal(wire.get('outerDiameter'))
            flat['outerHeight'] = extract_nominal(wire.get('outerHeight'))
            flat['outerWidth'] = extract_nominal(wire.get('outerWidth'))
            flat['edgeRadius'] = extract_nominal(wire.get('edgeRadius'))

            # Coating info
            coating = wire.get('coating')
            if coating and isinstance(coating, dict):
                flat['coating_type'] = coating.get('type')
                flat['coating_grade'] = coating.get('grade')
                flat['coating_breakdownVoltage'] = coating.get('breakdownVoltage')
            else:
                flat['coating_type'] = None
                flat['coating_grade'] = None
                flat['coating_breakdownVoltage'] = None

            # Strand info (for litz)
            strand = wire.get('strand')
            if strand and isinstance(strand, dict):
                flat['strand_conductingDiameter'] = extract_nominal(strand.get('conductingDiameter'))
                flat['strand_outerDiameter'] = extract_nominal(strand.get('outerDiameter'))
                flat['strand_type'] = strand.get('type')

            # Sanitize name for use as MATLAB struct field
            safe_key = name.replace(' ', '_').replace('.', '_').replace('-', '_').replace('/', '_')
            exported[safe_key] = flat

            type_counts[wtype] = type_counts.get(wtype, 0) + 1

    # Summary
    print(f"\nExported {len(exported)} wires:")
    for t, c in sorted(type_counts.items()):
        print(f"  {t}: {c}")

    # Write JSON
    with open(output_file, 'w') as f:
        json.dump(exported, f, indent=2)

    file_size = os.path.getsize(output_file)
    print(f"\nSaved to: {output_file} ({file_size:,} bytes)")

    return exported


if __name__ == '__main__':
    # Parse arguments
    if '--all' in sys.argv:
        types = ['foil', 'rectangular', 'round', 'litz']
    elif '--types' in sys.argv:
        idx = sys.argv.index('--types')
        types = sys.argv[idx+1:]
    else:
        types = ['foil']

    print(f"Exporting wire types: {', '.join(types)}")
    print("=" * 50)

    output = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'openmagnetics_wire_database.json')
    export_wires(wire_types=types, output_file=output)
