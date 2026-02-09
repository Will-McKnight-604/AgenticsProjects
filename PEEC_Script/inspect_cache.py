#!/usr/bin/env python3
"""
Inspect the openmagnetics_cache.mat file to diagnose wire dimension issues
"""

import scipy.io
import numpy as np
import sys

def print_struct_fields(struct, indent=0):
    """Recursively print struct fields"""
    prefix = "  " * indent
    if isinstance(struct, dict):
        for key, value in struct.items():
            if isinstance(value, (np.ndarray, list)) and len(str(value)) > 100:
                print(f"{prefix}{key}: <array/data>")
            elif isinstance(value, dict):
                print(f"{prefix}{key}:")
                print_struct_fields(value, indent+1)
            else:
                print(f"{prefix}{key}: {value}")

def inspect_cache():
    print("\n=== WIRE CACHE INSPECTION ===\n")

    # Load the cache file
    cache_file = 'openmagnetics_cache.mat'
    try:
        print(f"Loading cache file: {cache_file}")
        cache_data = scipy.io.loadmat(cache_file, struct_as_record=False, squeeze_me=True)
        print("Cache loaded successfully\n")
    except FileNotFoundError:
        print(f"ERROR: Cache file not found: {cache_file}")
        return
    except Exception as e:
        print(f"ERROR loading cache: {e}")
        return

    # Check for wire_database
    if 'wire_database' not in cache_data:
        print("ERROR: No wire_database field in cache")
        print(f"Available fields: {list(cache_data.keys())}")
        return

    wire_db = cache_data['wire_database']
    print(f"Wire database type: {type(wire_db)}")

    # Try to access wire data
    if hasattr(wire_db, '_fieldnames'):
        wire_names = wire_db._fieldnames
        print(f"Total wires in cache: {len(wire_names)}\n")

        # Find foil wires
        print("=== FOIL WIRES ===")
        foil_wires = [name for name in wire_names if 'foil' in name.lower()]
        print(f"Found {len(foil_wires)} foil wires:")
        for i, name in enumerate(foil_wires[:20], 1):  # Show first 20
            print(f"  {i}. {name}")
        print()

        # Inspect first few foil wires in detail
        print("=== DETAILED INSPECTION OF FOIL WIRES ===\n")
        for i, wire_name in enumerate(foil_wires[:5], 1):
            print(f"--- Wire {i}: {wire_name} ---")
            wire = getattr(wire_db, wire_name)

            if hasattr(wire, '_fieldnames'):
                fields = wire._fieldnames
                print(f"Fields present: {', '.join(fields)}")

                # Check dimensional fields
                print("Dimensional data:")
                dim_fields = ['foil_width', 'foil_thickness', 'rect_width', 'rect_height',
                              'width', 'thickness', 'conductor_shape', 'area']

                for field in dim_fields:
                    if field in fields:
                        value = getattr(wire, field)
                        if field in ['foil_width', 'foil_thickness', 'rect_width',
                                     'rect_height', 'width', 'thickness']:
                            if isinstance(value, (int, float, np.number)):
                                print(f"  {field}: {value:.6f} m ({value*1e3:.3f} mm)")
                            else:
                                print(f"  {field}: {value}")
                        else:
                            print(f"  {field}: {value}")
                    else:
                        print(f"  {field}: NOT FOUND")
            else:
                print(f"Cannot inspect wire structure: {type(wire)}")
            print()

        # Check specific wires mentioned by user
        print("=== CHECKING SPECIFIC WIRES MENTIONED ===")
        test_wires = ['Foil_0_038', 'Foil_0_005']

        for wire_name in test_wires:
            # Try both with and without sanitization
            variants = [wire_name, wire_name.replace('.', '_')]

            found = False
            for variant in variants:
                if hasattr(wire_db, variant):
                    found = True
                    print(f"\nWire: {wire_name} (field: {variant}) - FOUND")
                    wire = getattr(wire_db, variant)

                    if hasattr(wire, '_fieldnames'):
                        fields = wire._fieldnames
                        print(f"  All fields: {', '.join(fields)}")

                        # Check for dimensional data
                        has_foil = hasattr(wire, 'foil_width') and hasattr(wire, 'foil_thickness')
                        has_rect = hasattr(wire, 'rect_width') and hasattr(wire, 'rect_height')

                        if has_foil:
                            w = getattr(wire, 'foil_width')
                            t = getattr(wire, 'foil_thickness')
                            print(f"  Dimensions (foil): {w*1e3:.3f} mm x {t*1e3:.3f} mm")
                        elif has_rect:
                            w = getattr(wire, 'rect_width')
                            h = getattr(wire, 'rect_height')
                            print(f"  Dimensions (rect): {w*1e3:.3f} mm x {h*1e3:.3f} mm")
                        else:
                            print(f"  WARNING: No dimensional data found!")
                    break

            if not found:
                print(f"\nWire: {wire_name} - NOT FOUND in cache")

    else:
        print(f"Cannot access wire database structure: {type(wire_db)}")
        print(f"Available attributes: {dir(wire_db)}")

    print("\n=== INSPECTION COMPLETE ===")

if __name__ == '__main__':
    inspect_cache()
