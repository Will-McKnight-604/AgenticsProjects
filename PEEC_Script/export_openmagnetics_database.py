#!/usr/bin/env python3
"""
Export OpenMagnetics database (wires, cores, materials, suppliers) to JSON
for MATLAB/Octave consumption. Uses PyOpenMagnetics (PyMKF) directly.

Usage:
    python export_openmagnetics_database.py           # Export everything
    python export_openmagnetics_database.py --wires   # Wires only
    python export_openmagnetics_database.py --cores   # Cores only
    python export_openmagnetics_database.py --materials  # Materials only

Requirements:
    pip install PyMKF
"""

import PyOpenMagnetics as pm
import json
import sys
import os
import time


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
        mx = field.get('maximum')
        mn = field.get('minimum')
        if mx is not None and mn is not None:
            return (mx + mn) / 2
        if mx is not None:
            return mx
        if mn is not None:
            return mn
    return None


# ============================================================
# WIRE EXPORT
# ============================================================

def export_wires(output_dir, wire_types=None):
    """Export wire database to JSON."""
    if wire_types is None:
        wire_types = ['foil']

    print("\n" + "=" * 60)
    print("EXPORTING WIRES")
    print("=" * 60)

    all_names = pm.get_wire_names()
    print(f"Total wires in database: {len(all_names)}")

    exported = {}
    type_counts = {}

    for name in all_names:
        try:
            wire = pm.get_wire_data_by_name(name)
        except Exception as e:
            continue

        wtype = wire.get('type', '')
        if wtype and wtype.lower() in [t.lower() for t in wire_types]:
            flat = {
                'name': wire.get('name', name),
                'type': wtype,
                'material': wire.get('material', 'copper'),
                'standard': wire.get('standard'),
                'numberConductors': wire.get('numberConductors', 1),
                'conductingWidth': extract_nominal(wire.get('conductingWidth')),
                'conductingHeight': extract_nominal(wire.get('conductingHeight')),
                'conductingArea': extract_nominal(wire.get('conductingArea')),
                'conductingDiameter': extract_nominal(wire.get('conductingDiameter')),
                'outerDiameter': extract_nominal(wire.get('outerDiameter')),
                'outerHeight': extract_nominal(wire.get('outerHeight')),
                'outerWidth': extract_nominal(wire.get('outerWidth')),
                'edgeRadius': extract_nominal(wire.get('edgeRadius')),
            }

            # Coating info
            coating = wire.get('coating')
            if coating and isinstance(coating, dict):
                flat['coating_type'] = coating.get('type')
                flat['coating_grade'] = coating.get('grade')
            else:
                flat['coating_type'] = None
                flat['coating_grade'] = None

            # Strand info (for litz)
            strand = wire.get('strand')
            if strand and isinstance(strand, dict):
                flat['strand_conductingDiameter'] = extract_nominal(
                    strand.get('conductingDiameter'))
                flat['strand_outerDiameter'] = extract_nominal(
                    strand.get('outerDiameter'))
                flat['strand_type'] = strand.get('type')
                flat['strand_numberConductors'] = strand.get('numberConductors')
                flat['strand_name'] = strand.get('name')
            elif strand and isinstance(strand, str):
                # Strand is a name reference (e.g. "Round 0.02 - Grade 1")
                flat['strand_name'] = strand
                # Try to resolve the strand wire for its dimensions
                try:
                    strand_wire = pm.get_wire_data_by_name(strand)
                    flat['strand_conductingDiameter'] = extract_nominal(
                        strand_wire.get('conductingDiameter'))
                    flat['strand_outerDiameter'] = extract_nominal(
                        strand_wire.get('outerDiameter'))
                    flat['strand_type'] = strand_wire.get('type', 'round')
                    flat['strand_numberConductors'] = strand_wire.get(
                        'numberConductors', 1)
                except Exception:
                    pass

            safe_key = name.replace(' ', '_').replace('.', '_').replace(
                '-', '_').replace('/', '_')
            exported[safe_key] = flat
            type_counts[wtype] = type_counts.get(wtype, 0) + 1

    print(f"Exported {len(exported)} wires:")
    for t, c in sorted(type_counts.items()):
        print(f"  {t}: {c}")

    output_file = os.path.join(output_dir, 'openmagnetics_wire_database.json')
    with open(output_file, 'w') as f:
        json.dump(exported, f, indent=2)
    print(f"Saved: {output_file} ({os.path.getsize(output_file):,} bytes)")
    return exported


# ============================================================
# CORE SHAPE EXPORT
# ============================================================

def export_cores(output_dir):
    """Export core shapes with winding window dimensions."""
    print("\n" + "=" * 60)
    print("EXPORTING CORE SHAPES")
    print("=" * 60)

    shape_names = pm.get_core_shape_names(include_toroidal=True)
    print(f"Total core shapes (incl. toroidal): {len(shape_names)}")

    exported = {}
    failed = []
    t_start = time.time()

    for i, name in enumerate(shape_names):
        if (i + 1) % 50 == 0:
            elapsed = time.time() - t_start
            rate = (i + 1) / elapsed
            remaining = (len(shape_names) - i - 1) / rate
            print(f"  Processing {i+1}/{len(shape_names)} "
                  f"({elapsed:.0f}s elapsed, ~{remaining:.0f}s remaining)...")

        try:
            shape = pm.find_core_shape_by_name(name)

            # Extract raw dimensions
            dims_raw = shape.get('dimensions', {})
            dims = {}
            for k, v in dims_raw.items():
                val = extract_nominal(v)
                if val is not None:
                    dims[k] = val

            core_entry = {
                'name': name,
                'family': shape.get('family', ''),
                'type': shape.get('type', ''),
                'magneticCircuit': shape.get('magneticCircuit', ''),
                'aliases': shape.get('aliases', []),
                'dimensions': dims,
            }

            # Calculate processed description for winding window + effective params
            try:
                core_data = {
                    'functionalDescription': {
                        'name': name,
                        'type': 'two-piece set',
                        'shape': name,
                        'material': '3C95',
                        'gapping': [],
                        'numberStacks': 1
                    }
                }
                proc = pm.calculate_core_processed_description(core_data)

                if isinstance(proc, dict):
                    # Winding window
                    ww_list = proc.get('windingWindows', [])
                    if ww_list:
                        ww = ww_list[0]
                        core_entry['windingWindow'] = {
                            'width': ww.get('width'),
                            'height': ww.get('height'),
                        }

                    # Effective parameters
                    eff = proc.get('effectiveParameters', {})
                    if eff:
                        core_entry['effectiveArea'] = eff.get('effectiveArea')
                        core_entry['effectiveLength'] = eff.get('effectiveLength')
                        core_entry['effectiveVolume'] = eff.get('effectiveVolume')
                        core_entry['minimumArea'] = eff.get('minimumArea')

                    # Overall dimensions
                    core_entry['overallWidth'] = proc.get('width')
                    core_entry['overallHeight'] = proc.get('height')
                    core_entry['overallDepth'] = proc.get('depth')

            except Exception:
                # Fall back to estimating from dimensions
                D = dims.get('D')
                E = dims.get('E')
                C = dims.get('C')
                if D is not None:
                    core_entry['windingWindow'] = {
                        'width': None,  # Can't reliably compute for all families
                        'height': 2 * D,
                    }

            safe_key = name.replace(' ', '_').replace('.', '_').replace(
                '-', '_').replace('/', '_')
            exported[safe_key] = core_entry

        except Exception as e:
            failed.append((name, str(e)))

    elapsed = time.time() - t_start
    print(f"\nExported {len(exported)} core shapes in {elapsed:.1f}s")
    if failed:
        print(f"  Failed: {len(failed)} shapes")
        for name, err in failed[:5]:
            print(f"    {name}: {err}")

    # Count by family
    families = {}
    for entry in exported.values():
        fam = entry.get('family', 'unknown')
        families[fam] = families.get(fam, 0) + 1
    print("  By family:")
    for fam, count in sorted(families.items(), key=lambda x: -x[1]):
        print(f"    {fam}: {count}")

    output_file = os.path.join(output_dir, 'openmagnetics_core_database.json')
    with open(output_file, 'w') as f:
        json.dump(exported, f, indent=2)
    print(f"Saved: {output_file} ({os.path.getsize(output_file):,} bytes)")
    return exported


# ============================================================
# MATERIAL EXPORT
# ============================================================

def export_materials(output_dir):
    """Export core materials with manufacturer info."""
    print("\n" + "=" * 60)
    print("EXPORTING CORE MATERIALS")
    print("=" * 60)

    mat_names = pm.get_core_material_names()
    print(f"Total core materials: {len(mat_names)}")

    # Build material -> manufacturer mapping (primary source of truth)
    manufacturers = pm.get_available_core_manufacturers()
    material_to_mfr = {}
    for mfr in manufacturers:
        try:
            mats = pm.get_core_material_names_by_manufacturer(mfr)
            for m in mats:
                material_to_mfr[m] = mfr
        except Exception:
            pass
    print(f"Manufacturer mapping: {len(material_to_mfr)} materials assigned")

    exported = {}
    mfr_counts = {}

    for name in mat_names:
        try:
            mat = pm.find_core_material_by_name(name)

            # Find manufacturer - use mapping first, then fall back to data
            manufacturer = material_to_mfr.get(name)
            if not manufacturer:
                mfr_info = mat.get('manufacturerInfo')
                if isinstance(mfr_info, dict):
                    manufacturer = mfr_info.get('name')

            # Get key material properties (keep it lightweight)
            entry = {
                'name': name,
                'manufacturer': manufacturer,
                'type': mat.get('type', ''),
                'family': mat.get('family', ''),
                'material': mat.get('material', ''),
                'curieTemperature': mat.get('curieTemperature'),
                'density': mat.get('density'),
                'resistivity': extract_nominal(mat.get('resistivity')),
            }

            # Saturation
            sat = mat.get('saturation')
            if isinstance(sat, list) and len(sat) > 0:
                entry['saturationFluxDensity'] = sat[0].get(
                    'magneticFluxDensity', {}).get('typical')

            # Initial permeability
            perm = mat.get('permeability')
            if isinstance(perm, dict):
                init = perm.get('initial', {})
                if isinstance(init, dict):
                    entry['initialPermeability'] = init.get('value')

            if manufacturer:
                mfr_counts[manufacturer] = mfr_counts.get(manufacturer, 0) + 1

            safe_key = name.replace(' ', '_').replace('.', '_').replace(
                '-', '_').replace('/', '_')
            exported[safe_key] = entry

        except Exception as e:
            safe_key = name.replace(' ', '_').replace('.', '_').replace(
                '-', '_').replace('/', '_')
            manufacturer = material_to_mfr.get(name)
            exported[safe_key] = {'name': name, 'manufacturer': manufacturer}

    print(f"Exported {len(exported)} materials")
    print("  By manufacturer:")
    for mfr, count in sorted(mfr_counts.items(), key=lambda x: -x[1]):
        print(f"    {mfr}: {count}")
    unassigned = sum(1 for e in exported.values() if not e.get('manufacturer'))
    if unassigned:
        print(f"    (unassigned): {unassigned}")

    output_file = os.path.join(output_dir, 'openmagnetics_material_database.json')
    with open(output_file, 'w') as f:
        json.dump(exported, f, indent=2)
    print(f"Saved: {output_file} ({os.path.getsize(output_file):,} bytes)")
    return exported


# ============================================================
# SUPPLIER/MANUFACTURER EXPORT
# ============================================================

def export_suppliers(output_dir, core_db, material_db):
    """Export supplier mapping (manufacturer -> cores and materials)."""
    print("\n" + "=" * 60)
    print("EXPORTING SUPPLIER DATABASE")
    print("=" * 60)

    manufacturers = sorted(pm.get_available_core_manufacturers())
    print(f"Core manufacturers: {len(manufacturers)}")

    supplier_db = {}
    for mfr in manufacturers:
        entry = {'name': mfr, 'cores': [], 'materials': []}

        # Get materials for this manufacturer
        try:
            mats = pm.get_core_material_names_by_manufacturer(mfr)
            entry['materials'] = sorted(mats)
        except Exception:
            pass

        # Find cores that use this manufacturer's materials
        # (Core shapes themselves don't have manufacturers in OpenMagnetics,
        #  but we can associate via common material-manufacturer pairings)
        entry['material_count'] = len(entry['materials'])

        safe_key = mfr.replace(' ', '_').replace('.', '_').replace(
            '-', '_').replace('/', '_')
        supplier_db[safe_key] = entry
        print(f"  {mfr}: {len(entry['materials'])} materials")

    output_file = os.path.join(output_dir, 'openmagnetics_supplier_database.json')
    with open(output_file, 'w') as f:
        json.dump(supplier_db, f, indent=2)
    print(f"Saved: {output_file} ({os.path.getsize(output_file):,} bytes)")
    return supplier_db


# ============================================================
# MAIN
# ============================================================

if __name__ == '__main__':
    output_dir = os.path.dirname(os.path.abspath(__file__))

    # Selective export flags: --wires, --cores, --materials
    # --all-wires is NOT a selective flag (it modifies wire types, not what to export)
    selective_flags = {'--wires', '--cores', '--materials'}
    has_selective = any(a in selective_flags for a in sys.argv[1:])
    do_wires = '--wires' in sys.argv or not has_selective
    do_cores = '--cores' in sys.argv or not has_selective
    do_materials = '--materials' in sys.argv or not has_selective

    # Wire types to export
    if '--all-wires' in sys.argv:
        wire_types = ['foil', 'rectangular', 'round', 'litz']
    else:
        wire_types = ['foil']

    print("OpenMagnetics Database Export")
    print("=" * 60)
    print(f"Output directory: {output_dir}")
    print(f"Wire types: {', '.join(wire_types)}")
    print(f"Export: wires={do_wires}, cores={do_cores}, materials={do_materials}")

    t_total = time.time()

    wire_db = {}
    core_db = {}
    mat_db = {}

    if do_wires:
        wire_db = export_wires(output_dir, wire_types)

    if do_cores:
        core_db = export_cores(output_dir)

    if do_materials:
        mat_db = export_materials(output_dir)
        export_suppliers(output_dir, core_db, mat_db)

    elapsed = time.time() - t_total
    print(f"\n{'=' * 60}")
    print(f"EXPORT COMPLETE in {elapsed:.1f}s")
    print(f"{'=' * 60}")
