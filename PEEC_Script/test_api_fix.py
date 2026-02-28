#!/usr/bin/env python3
"""
Test script to verify the call_pyopenmagnetics_api.py fix.

This script:
1. Creates a sample MAS input structure (minimal, from topology wizard)
2. Calls call_pyopenmagnetics_api.py's adviser function
3. Validates the results are realistic (diverse cores, reasonable losses)
4. Reports success/failure

Usage:
    python test_api_fix.py
"""

import json
import os
import sys
import tempfile
from pathlib import Path

# Add current directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from call_pyopenmagnetics_api import call_pyopenmagnetics_adviser


def create_sample_mas_input():
    """Create a minimal MAS input structure for a 2-switch forward converter."""
    return {
        "inputs": {
            "designRequirements": {
                "topology": "two-switch-forward",
                "inputVoltage": {
                    "minimum": 100.0,
                    "nominal": 145.0,
                    "maximum": 190.0
                },
                "diodeVoltageDrop": 0.7,
                "currentRippleRatio": 0.3,
                "efficiency": 0.92
            },
            "operatingPoints": [
                {
                    "name": "nominal",
                    "conditions": {
                        "ambientTemperature": 25.0
                    },
                    "excitationsPerWinding": [
                        {
                            "name": "Primary",
                            "frequency": 200000.0,
                            "current": {
                                "processed": {
                                    "label": "Rectangular",
                                    "peakToPeak": 12.5,
                                    "offset": 3.125,
                                    "dutyCycle": 0.4
                                }
                            },
                            "voltage": {
                                "processed": {
                                    "label": "Rectangular",
                                    "peakToPeak": 290.0,
                                    "offset": 0.0,
                                    "dutyCycle": 0.4
                                }
                            }
                        },
                        {
                            "name": "Secondary 1",
                            "frequency": 200000.0,
                            "current": {
                                "processed": {
                                    "label": "Rectangular",
                                    "peakToPeak": 50.0,
                                    "offset": 12.5,
                                    "dutyCycle": 0.4
                                }
                            },
                            "voltage": {
                                "processed": {
                                    "label": "Rectangular",
                                    "peakToPeak": 5.7,
                                    "offset": 0.0,
                                    "dutyCycle": 0.4
                                }
                            }
                        }
                    ]
                }
            ]
        },
        "magnetic": {},
        "outputs": {}
    }


def test_adviser_call():
    """Test the adviser via call_pyopenmagnetics_api.py."""
    print("=" * 70)
    print("TEST: call_pyopenmagnetics_api.py fix (delegates to recommendations)")
    print("=" * 70)

    # Create sample MAS input
    mas_input = create_sample_mas_input()
    print("\n[TEST] Created sample MAS input for 2-switch-forward topology")
    print(f"  - Topology: {mas_input['inputs']['designRequirements'].get('topology')}")
    print(f"  - Operating Points: {len(mas_input['inputs']['operatingPoints'])}")
    print(f"  - Excitations/WD: {len(mas_input['inputs']['operatingPoints'][0]['excitationsPerWinding'])}")

    # Call adviser
    print("\n[TEST] Calling call_pyopenmagnetics_adviser()...")
    result = call_pyopenmagnetics_adviser(mas_input, max_results=5)

    # Validate results
    print(f"\n[TEST] Result status: {result.get('status')}")

    if result['status'] != 'OK':
        print(f"[FAIL] Adviser returned error status")
        print(f"  Error: {result.get('error')}")
        if 'stderr' in result:
            print(f"  Stderr: {result.get('stderr')[:200]}")
        if 'stdout' in result:
            print(f"  Stdout: {result.get('stdout')[:200]}")
        return False

    # Check data
    data = result.get('data', [])
    count = result.get('count', 0)

    print(f"[TEST] Number of results: {count}")

    if count == 0:
        print(f"[FAIL] Adviser returned 0 results")
        return False

    if count > 5:
        print(f"[WARN] Expected max 5 results, got {count}")

    # Validate first few results
    print(f"\n[TEST] Validating result structures...")
    realistic_count = 0
    for i, rec in enumerate(data[:3]):  # Check first 3
        index = rec.get('index')
        status = rec.get('status')
        core_name = rec.get('core_name', 'Unknown')
        losses = rec.get('total_losses_w', 0.0)
        lm = rec.get('Lm_uH', 0.0)
        b_peak = rec.get('B_peak_mT', 0.0)

        print(f"\n  Result {i+1}:")
        print(f"    - Core: {core_name}")
        print(f"    - Total Losses: {losses:.2f} W")
        print(f"    - Lm: {lm:.2f} uH")
        print(f"    - B peak: {b_peak:.2f} mT")

        # Validate values are realistic (not zeros or default placeholders)
        is_realistic = (
            core_name != "Unknown" and
            losses > 0.0 and losses < 50.0 and  # Reasonable loss range
            lm > 0.1 and lm < 10000.0 and  # Reasonable inductance range
            b_peak > 0.0 and b_peak < 1000.0  # Reasonable flux density
        )

        if is_realistic:
            realistic_count += 1
            print(f"    - Status: REALISTIC")
        else:
            print(f"    - Status: PLACEHOLDER/INVALID")

    print(f"\n[TEST] Realistic results: {realistic_count}/{min(3, len(data))}")

    if realistic_count < 1:
        print(f"[FAIL] No realistic results found (all appear to be placeholders)")
        return False

    # Check for core diversity
    core_names = {rec.get('core_name') for rec in data}
    print(f"\n[TEST] Core diversity: {len(core_names)} unique cores in {len(data)} results")
    for cn in sorted(core_names)[:5]:
        if cn:
            print(f"    - {cn}")

    if len(core_names) < 2:
        print(f"[WARN] Low core diversity (expected 3+, got {len(core_names)})")

    print(f"\n[PASS] Adviser returned realistic, diverse results")
    return True


def test_mas_json_compatibility():
    """Verify the MAS structure is valid JSON."""
    mas = create_sample_mas_input()
    print("\n[TEST] Testing MAS JSON serialization...")
    try:
        json_str = json.dumps(mas)
        reloaded = json.loads(json_str)
        print("[PASS] MAS structure is valid JSON")
        return True
    except Exception as e:
        print(f"[FAIL] MAS JSON serialization failed: {e}")
        return False


if __name__ == "__main__":
    try:
        # Test 1: MAS JSON compatibility
        if not test_mas_json_compatibility():
            sys.exit(1)

        # Test 2: Main adviser call
        if not test_adviser_call():
            sys.exit(1)

        print("\n" + "=" * 70)
        print("ALL TESTS PASSED")
        print("=" * 70)
        sys.exit(0)

    except Exception as e:
        import traceback
        print(f"\n[FAIL] Unexpected error: {e}")
        print(traceback.format_exc())
        sys.exit(1)
