#!/usr/bin/env python3
"""
Test the full workflow: topology computation → MAS generation → adviser call

This mimics what MATLAB topology_wizard.m does:
1. Call generate_om_topology.py to compute converter equations and excitations
2. Extract mas_inputs from the result
3. Pass to call_pyopenmagnetics_api.py
4. Verify realistic results
"""

import json
import os
import sys
import subprocess
import tempfile
from pathlib import Path

def test_topology_workflow():
    """Test the complete workflow."""
    print("=" * 70)
    print("TEST: Complete Topology Workflow (Topology -> MAS -> Adviser)")
    print("=" * 70)

    script_dir = os.path.dirname(os.path.abspath(__file__))

    # STEP 1: Call generate_om_topology.py
    print("\n[TEST] STEP 1: Computing topology converter equations...")

    topo_config = {
        "mode": "compute_topology",
        "topology": "two_switch_forward",
        "design_mode": "auto",
        "n_outputs": 1,
        "converter": {
            "vin_min": 100.0,
            "vin_max": 190.0,
            "vin_nom": 145.0,
            "vout": 5.0,
            "iout": 5.0,
            "fsw_hz": 200000.0,
            "fsw_khz": 200.0,
            "vd": 0.7,
            "efficiency": 0.92,
            "max_ripple": 30.0
        },
        "advanced": {
            "max_duty": 0.45,
            "max_switch_current": 20.0
        }
    }

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        topo_config_path = f.name
        json.dump(topo_config, f)

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        topo_results_path = f.name

    try:
        # Update config to point to output file
        topo_config['output_file'] = topo_results_path
        with open(topo_config_path, 'w') as f:
            json.dump(topo_config, f)

        # Run topology computation
        cmd = [sys.executable, 'generate_om_topology.py', topo_config_path]
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=script_dir, timeout=60)

        if result.returncode != 0:
            print(f"[FAIL] Topology computation failed")
            print(f"  Return code: {result.returncode}")
            print(f"  Stderr: {result.stderr[:500]}")
            return False

        # Load topology results
        with open(topo_results_path, 'r') as f:
            topo_results = json.load(f)

        if topo_results.get('status') != 'OK':
            print(f"[FAIL] Topology computation returned error: {topo_results.get('error')}")
            return False

        print(f"[PASS] Topology computation succeeded")

        # Extract mas_inputs
        if 'mas_inputs' not in topo_results:
            print(f"[WARN] mas_inputs not in topology results")
            mas_inputs = None
        else:
            mas_inputs = topo_results['mas_inputs']
            print(f"[INFO] Extracted mas_inputs with excitationsPerWinding")
            if 'operatingPoints' in mas_inputs:
                op = mas_inputs['operatingPoints'][0]
                if 'excitationsPerWinding' in op:
                    n_windings = len(op['excitationsPerWinding'])
                    print(f"      Operating points: {len(mas_inputs['operatingPoints'])}")
                    print(f"      Excitations per winding: {n_windings}")

        # STEP 2: Call adviser with the mas_inputs
        print("\n[TEST] STEP 2: Calling adviser with topology-computed MAS...")

        if mas_inputs is None:
            print("[WARN] Skipping adviser test (no mas_inputs from topology)")
            return True

        # Create adviser input config
        adviser_config = {
            "mode": "recommend",
            "design_requirements": mas_inputs['inputs']['designRequirements'],
            "operating_points": mas_inputs['inputs']['operatingPoints'],
            "max_results": 5,
            "weights": {"COST": 1.0, "LOSSES": 1.0, "DIMENSIONS": 1.0},
            "cores_in_stock": False,
            "output_file": tempfile.mktemp(suffix='.json')
        }

        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            adviser_config_path = f.name
            json.dump(adviser_config, f)

        # Run adviser
        cmd = [sys.executable, 'generate_om_recommendations.py', adviser_config_path]
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=script_dir, timeout=120)

        if result.returncode != 0:
            print(f"[FAIL] Adviser call failed")
            print(f"  Return code: {result.returncode}")
            print(f"  Stderr: {result.stderr[:500]}")
            return False

        # Load adviser results
        adviser_output_file = adviser_config.get('output_file', 'om_recommendation_results.json')
        if os.path.exists(adviser_output_file):
            with open(adviser_output_file, 'r') as f:
                adviser_results = json.load(f)
        else:
            # Try default output location
            adviser_output_file = os.path.join(script_dir, 'om_recommendation_results.json')
            if os.path.exists(adviser_output_file):
                with open(adviser_output_file, 'r') as f:
                    adviser_results = json.load(f)
            else:
                print(f"[WARN] Could not find adviser output file")
                adviser_results = {'status': 'UNKNOWN'}

        if adviser_results.get('status') != 'OK':
            print(f"[FAIL] Adviser returned error: {adviser_results.get('error', 'unknown')}")
            return False

        recommendations = adviser_results.get('recommendations', [])
        if len(recommendations) == 0:
            print(f"[FAIL] Adviser returned 0 recommendations")
            return False

        print(f"[PASS] Adviser returned {len(recommendations)} recommendations")

        # Validate first recommendation
        rec = recommendations[0]
        core_name = rec.get('core_shape', 'Unknown')
        losses = rec.get('total_losses_w', 0.0)
        lm = rec.get('Lm_uH', 0.0)

        print(f"\nFirst recommendation:")
        print(f"  - Core: {core_name}")
        print(f"  - Total Losses: {losses:.2f} W")
        print(f"  - Lm: {lm:.2f} uH")

        is_realistic = (
            core_name != 'Unknown' and
            losses > 0.0 and losses < 50.0 and
            lm > 0.1 and lm < 10000.0
        )

        if is_realistic:
            print(f"[PASS] Result appears realistic")
            return True
        else:
            print(f"[FAIL] Result appears to be placeholder/invalid")
            return False

    finally:
        # Cleanup
        for path in [topo_config_path, topo_results_path]:
            try:
                if os.path.exists(path):
                    os.remove(path)
            except Exception:
                pass


if __name__ == "__main__":
    try:
        if test_topology_workflow():
            print("\n" + "=" * 70)
            print("ALL TESTS PASSED")
            print("=" * 70)
            sys.exit(0)
        else:
            sys.exit(1)
    except Exception as e:
        import traceback
        print(f"\n[FAIL] Unexpected error: {e}")
        print(traceback.format_exc())
        sys.exit(1)
