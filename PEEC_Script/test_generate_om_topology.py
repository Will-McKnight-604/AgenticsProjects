#!/usr/bin/env python3
"""
Test script for generate_om_topology.py - validates all 9 topology calculators.

Usage:
    python test_generate_om_topology.py
"""

import json
import sys
import os

# Import the topology module
sys.path.insert(0, os.path.dirname(__file__))
from generate_om_topology import compute_topology


def test_topology(topology_key, n_outputs=1):
    """Test a single topology computation."""
    config = {
        "mode": "compute_topology",
        "topology": topology_key,
        "design_mode": "auto",
        "converter": {
            "inputVoltage": {"minimum": 100, "nominal": 145, "maximum": 190},
            "diodeVoltageDrop": 0.7,
            "efficiency": 90,
            "currentRippleRatio": 30,
            "maximumSwitchCurrent": None,
            "operatingPoints": [{
                "outputVoltages": [5.0] * n_outputs,
                "outputCurrents": [5.0] * n_outputs,
                "switchingFrequency": 200000,
                "ambientTemperature": 25
            }]
        },
        "advanced": {
            "desiredInductance": None,
            "desiredDutyCycle": None,
            "desiredTurnsRatios": [],
            "deadTime": None,
            "maximumDutyCycle": None,
            "maximumDrainSourceVoltage": None
        },
        "output_file": "om_topology_results_test.json"
    }

    result = compute_topology(config)

    if result.get("status") != "OK":
        print(f"[FAIL] {topology_key}: {result.get('error')}")
        return False

    computed = result.get("computed", {})
    print(f"[OK] {topology_key}:")
    lm_val = computed.get('Lm_uH', 0)
    lm_str = f"{float(lm_val):.2f} uH" if isinstance(lm_val, (int, float)) else "N/A (non-isolated)"
    print(f"  - Lm: {lm_str}")
    print(f"  - Duty (nom/min/max): {computed.get('duty_nom', 0):.3f} / {computed.get('duty_min_vin', 0):.3f} / {computed.get('duty_max_vin', 0):.3f}")
    print(f"  - Windings: {computed.get('n_windings', 'N/A')}")
    print(f"  - Turns ratios: {computed.get('turns_ratios', [])}")

    return True


def main():
    """Run all topology tests."""
    print("=" * 60)
    print("Testing generate_om_topology.py - All 9 Topologies")
    print("=" * 60)

    topologies = [
        ("two_switch_forward", 1),
        ("single_switch_forward", 1),
        ("active_clamp_forward", 1),
        ("flyback", 1),
        ("push_pull", 1),
        ("buck", 1),
        ("boost", 1),
        ("isolated_buck", 1),
        ("isolated_buck_boost", 1),
    ]

    print("\n### Single Output Tests ###\n")
    passed = 0
    for topo_key, n_out in topologies:
        if test_topology(topo_key, n_out):
            passed += 1

    print(f"\n### Multi-Output Test (4 secondaries) ###\n")

    # Test multi-output on isolated topologies
    multi_output_topologies = [
        ("two_switch_forward", 4),
        ("flyback", 4),
        ("isolated_buck", 4),
    ]

    for topo_key, n_out in multi_output_topologies:
        if test_topology(topo_key, n_out):
            passed += 1

    total = len(topologies) + len(multi_output_topologies)
    print(f"\n{'=' * 60}")
    print(f"Results: {passed}/{total} tests passed")
    print("=" * 60)

    if passed == total:
        print("[OK] All tests PASSED")
        return 0
    else:
        print(f"[FAIL] {total - passed} test(s) FAILED")
        return 1


if __name__ == "__main__":
    sys.exit(main())
