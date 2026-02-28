#!/usr/bin/env python3
"""
Test that call_pyopenmagnetics_api.py correctly delegates to generate_om_recommendations.py

This verifies the fix for the API format incompatibility bug.
"""

import json
import os
import sys
import tempfile

# Import the fixed function
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from call_pyopenmagnetics_api import call_pyopenmagnetics_adviser


def test_api_delegation():
    """Test the delegation mechanism."""
    print("\n" + "=" * 70)
    print("TEST: API Delegation to generate_om_recommendations.py")
    print("=" * 70)

    # Create a complete MAS structure (what topology wizard builds)
    mas_input = {
        "inputs": {
            "designRequirements": {
                "topology": "two-switch-forward",
                "inputVoltage": {
                    "minimum": 100.0,
                    "nominal": 145.0,
                    "maximum": 190.0
                },
                "diodeVoltageDrop": 0.7,
                "currentRippleRatio": 0.30,
                "efficiency": 0.92,
                # These are added by topology merge
                "magnetizingInductance": {"nominal": 3500.0},
                "turnsRatios": [{"nominal": 7.9}]
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
                        }
                    ]
                }
            ]
        },
        "magnetic": {},
        "outputs": {}
    }

    print("\n[TEST] Calling adviser with properly merged MAS structure...")
    print("  - Has magnetizingInductance: YES")
    print("  - Has turnsRatios: YES")
    print("  - Has excitationsPerWinding: YES")
    print("  - Topology: two-switch-forward")

    # Call the adviser (now uses delegation)
    result = call_pyopenmagnetics_adviser(mas_input, max_results=5)

    # Check result
    print(f"\n[TEST] Adviser returned status: {result.get('status')}")

    if result['status'] != 'OK':
        print(f"[FAIL] Adviser failed")
        print(f"  Error: {result.get('error')}")
        if 'stderr' in result:
            print(f"  Stderr: {result.get('stderr')[:200]}")
        return False

    # Check for results
    data = result.get('data', [])
    count = result.get('count', 0)

    print(f"[PASS] Adviser returned {count} recommendations")

    if count == 0:
        print(f"[FAIL] No recommendations returned")
        return False

    # Validate first result
    rec = data[0]
    core_name = rec.get('core_name', 'Unknown')
    losses = rec.get('total_losses_w', 0.0)
    lm = rec.get('Lm_uH', 0.0)
    b_peak = rec.get('B_peak_mT', 0.0)

    print(f"\n[TEST] First recommendation:")
    print(f"  - Core: {core_name}")
    print(f"  - Total Losses: {losses:.2f} W")
    print(f"  - Lm: {lm:.2f} uH")
    print(f"  - B peak: {b_peak:.2f} mT")

    # Validate it's realistic
    is_realistic = (
        core_name != 'Unknown' and
        losses > 0.0 and losses < 50.0 and
        lm > 100.0 and lm < 10000.0 and
        b_peak > 0.0 and b_peak < 1000.0
    )

    if is_realistic:
        print(f"\n[PASS] Result is realistic (not a placeholder)")

        # Check diversity
        cores = {d.get('core_name') for d in data}
        print(f"[PASS] Recommendation diversity: {len(cores)} unique cores in {len(data)} results")

        return True
    else:
        print(f"\n[FAIL] Result appears to be a placeholder")
        return False


if __name__ == "__main__":
    try:
        if test_api_delegation():
            print("\n" + "=" * 70)
            print("DELEGATION TEST PASSED - FIX IS WORKING")
            print("=" * 70)
            sys.exit(0)
        else:
            sys.exit(1)
    except Exception as e:
        import traceback
        print(f"\n[FAIL] Unexpected error: {e}")
        print(traceback.format_exc())
        sys.exit(1)
