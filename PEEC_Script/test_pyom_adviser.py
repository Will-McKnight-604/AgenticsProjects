#!/usr/bin/env python3
"""
Standalone test script for PyOpenMagnetics adviser API.
Tests various input configurations to isolate what causes the ACCESS_VIOLATION crash.

Usage:
    python test_pyom_adviser.py
"""

import json
import sys
import traceback

try:
    import PyOpenMagnetics as pm
    print(f"PyOpenMagnetics loaded OK")
except ImportError as e:
    print(f"FAIL: Cannot import PyOpenMagnetics: {e}")
    sys.exit(1)

# Load databases
if pm.is_core_shape_database_empty() or pm.is_core_material_database_empty():
    pm.load_databases({})
    n_shapes = len(pm.get_available_core_shapes())
    print(f"Loaded databases: {n_shapes} core shapes")


def test_adviser(label, inputs, max_results=3, core_mode="available cores"):
    """Run process_inputs + calculate_advised_magnetics and report result."""
    print(f"\n{'='*60}")
    print(f"TEST: {label}")
    print(f"{'='*60}")

    # Dump inputs
    print(f"  topology: {inputs.get('designRequirements', {}).get('topology')}")
    print(f"  turnsRatios: {inputs.get('designRequirements', {}).get('turnsRatios')}")
    print(f"  Lm: {inputs.get('designRequirements', {}).get('magnetizingInductance')}")
    ops = inputs.get("operatingPoints", [])
    print(f"  n_operatingPoints: {len(ops)}")
    if ops:
        epw = ops[0].get("excitationsPerWinding", [])
        print(f"  n_excitations: {len(epw)}")
        for i, ex in enumerate(epw):
            print(f"    [{i}] name='{ex.get('name')}' freq={ex.get('frequency')}")

    # Step 1: process_inputs
    try:
        print(f"\n  Calling pm.process_inputs()...")
        sys.stdout.flush()
        processed = pm.process_inputs(inputs)
        print(f"  process_inputs() OK")
    except Exception as e:
        print(f"  FAIL process_inputs: {e}")
        traceback.print_exc()
        return False

    # Check for errors
    if isinstance(processed, dict) and "data" in processed:
        data_val = processed["data"]
        if isinstance(data_val, str) and "Exception" in data_val:
            print(f"  FAIL process_inputs returned error: {data_val}")
            return False

    # Strip nulls
    def strip_nulls(obj):
        if isinstance(obj, dict):
            return {k: strip_nulls(v) for k, v in obj.items() if v is not None}
        elif isinstance(obj, list):
            return [strip_nulls(v) for v in obj]
        return obj

    if isinstance(processed, dict):
        processed = strip_nulls(processed)

    # Dump processed structure summary
    if isinstance(processed, dict):
        p_dr = processed.get("designRequirements", {})
        p_ops = processed.get("operatingPoints", [])
        print(f"  processed topology: '{p_dr.get('topology')}'")
        print(f"  processed turnsRatios: {p_dr.get('turnsRatios')}")
        if p_ops:
            p_epw = p_ops[0].get("excitationsPerWinding", [])
            print(f"  processed n_excitations: {len(p_epw)}")

    # Dump full processed to file for inspection
    try:
        with open(f"_debug_test_{label.replace(' ', '_')}.json", "w") as f:
            json.dump(processed, f, indent=2, default=str)
    except Exception:
        pass

    # Step 2: calculate_advised_magnetics
    try:
        print(f"\n  Calling pm.calculate_advised_magnetics(max={max_results}, mode='{core_mode}')...")
        sys.stdout.flush()
        results = pm.calculate_advised_magnetics(processed, max_results, core_mode)
        print(f"  calculate_advised_magnetics() OK")

        # Count results
        if isinstance(results, list):
            print(f"  Got {len(results)} results")
        elif isinstance(results, dict):
            data = results.get("data", [])
            if isinstance(data, str):
                data = json.loads(data)
            print(f"  Got {len(data)} results")
        return True
    except Exception as e:
        print(f"  FAIL calculate_advised_magnetics: {e}")
        traceback.print_exc()
        return False


# ==============================================================================
# Test 1: Simple single-output Two Switch Forward (KNOWN WORKING from web tool)
# ==============================================================================
test1_inputs = {
    "designRequirements": {
        "topology": "Two Switch Forward Converter",
        "magnetizingInductance": {"nominal": 0.002537},
        "turnsRatios": [{"nominal": 7.89}],
        "inputVoltage": {"minimum": 100, "maximum": 190, "nominal": 145},
        "operatingTemperature": {"maximum": 65},
    },
    "operatingPoints": [
        {
            "name": "Operating Point 1",
            "conditions": {"ambientTemperature": 25},
            "excitationsPerWinding": [
                {
                    "name": "Primary",
                    "frequency": 200000,
                    "current": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 0.722,
                            "offset": 0.361,
                            "dutyCycle": 0.31,
                        }
                    },
                    "voltage": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 145,
                            "offset": 22.5,
                            "dutyCycle": 0.31,
                        }
                    },
                },
                {
                    "name": "Secondary",
                    "frequency": 200000,
                    "current": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 1.5,
                            "offset": 5.0,
                            "dutyCycle": 0.31,
                        }
                    },
                    "voltage": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 5.0,
                            "offset": 0.776,
                            "dutyCycle": 0.31,
                        }
                    },
                },
            ],
        }
    ],
}
test_adviser("single_output_forward", test1_inputs)

# ==============================================================================
# Test 2: Multi-output Two Switch Forward (2 secondaries = 3 windings)
# This is what our topology wizard produces and what crashes
# ==============================================================================
test2_inputs = {
    "designRequirements": {
        "topology": "Two Switch Forward Converter",
        "magnetizingInductance": {"nominal": 0.002537593984962406},
        "turnsRatios": [
            {"nominal": 7.894736842105263},
            {"nominal": 7.894736842105263},
        ],
        "inputVoltage": {"minimum": 100, "maximum": 190, "nominal": 145},
        "operatingTemperature": {"maximum": 65},
    },
    "operatingPoints": [
        {
            "name": "Operating Point 1",
            "conditions": {"ambientTemperature": 25},
            "excitationsPerWinding": [
                {
                    "name": "Primary",
                    "frequency": 200000,
                    "current": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 0.7220000000000001,
                            "offset": 0.361,
                            "dutyCycle": 0.3103448275862069,
                        }
                    },
                    "voltage": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 145,
                            "offset": 22.5,
                            "dutyCycle": 0.3103448275862069,
                        }
                    },
                },
                {
                    "name": "Secondary",
                    "frequency": 200000,
                    "current": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 1.5,
                            "offset": 5,
                            "dutyCycle": 0.3103448275862069,
                        }
                    },
                    "voltage": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 5,
                            "offset": 0.7758620689655172,
                            "dutyCycle": 0.3103448275862069,
                        }
                    },
                },
                {
                    "name": "Secondary 2",
                    "frequency": 200000,
                    "current": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 0.6,
                            "offset": 2,
                            "dutyCycle": 0.3103448275862069,
                        }
                    },
                    "voltage": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 3.3,
                            "offset": 0.5120689655172414,
                            "dutyCycle": 0.3103448275862069,
                        }
                    },
                },
            ],
        }
    ],
}
test_adviser("multi_output_forward", test2_inputs)

# ==============================================================================
# Test 3: Multi-output but with insulation (matches exact om_topology_api_config.json)
# ==============================================================================
test3_inputs = json.loads(json.dumps(test2_inputs))  # deep copy
test3_inputs["designRequirements"]["insulation"] = {
    "insulationType": "Basic",
    "standards": ["IEC 62368-1"],
    "pollutionDegree": "P2",
    "overvoltageCategory": "OVC-II",
    "cti": "Group II",
    "altitude": {"nominal": 2000, "minimum": 0, "maximum": 2000},
    "mainSupplyVoltage": {"nominal": 145, "minimum": 100, "maximum": 190},
    "wiringTechnology": "Wound",
}
test3_inputs["designRequirements"]["diodeVoltageDrop"] = 0.7
test3_inputs["designRequirements"]["currentRippleRatio"] = 0.3
test3_inputs["designRequirements"]["efficiency"] = 0.9
test_adviser("multi_output_with_insulation", test3_inputs)

# ==============================================================================
# Test 4: Multi-output but WITHOUT extra designRequirements fields
# (diodeVoltageDrop, currentRippleRatio, efficiency might not be MAS fields)
# ==============================================================================
test4_inputs = {
    "designRequirements": {
        "topology": "Two Switch Forward Converter",
        "magnetizingInductance": {"nominal": 0.002537593984962406},
        "turnsRatios": [
            {"nominal": 7.894736842105263},
            {"nominal": 7.894736842105263},
        ],
        "inputVoltage": {"minimum": 100, "maximum": 190, "nominal": 145},
        "operatingTemperature": {"maximum": 65},
        "insulation": {
            "insulationType": "Basic",
            "standards": ["IEC 62368-1"],
            "pollutionDegree": "P2",
            "overvoltageCategory": "OVC-II",
            "cti": "Group II",
            "altitude": {"nominal": 2000, "minimum": 0, "maximum": 2000},
            "mainSupplyVoltage": {"nominal": 145, "minimum": 100, "maximum": 190},
            "wiringTechnology": "Wound",
        },
    },
    "operatingPoints": [
        {
            "name": "Operating Point 1",
            "conditions": {"ambientTemperature": 25},
            "excitationsPerWinding": [
                {
                    "name": "Primary",
                    "frequency": 200000,
                    "current": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 0.722,
                            "offset": 0.361,
                            "dutyCycle": 0.31,
                        }
                    },
                    "voltage": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 145,
                            "offset": 22.5,
                            "dutyCycle": 0.31,
                        }
                    },
                },
                {
                    "name": "Secondary",
                    "frequency": 200000,
                    "current": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 1.5,
                            "offset": 5.0,
                            "dutyCycle": 0.31,
                        }
                    },
                    "voltage": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 5.0,
                            "offset": 0.776,
                            "dutyCycle": 0.31,
                        }
                    },
                },
                {
                    "name": "Secondary 2",
                    "frequency": 200000,
                    "current": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 0.6,
                            "offset": 2.0,
                            "dutyCycle": 0.31,
                        }
                    },
                    "voltage": {
                        "processed": {
                            "label": "Rectangular",
                            "peakToPeak": 3.3,
                            "offset": 0.512,
                            "dutyCycle": 0.31,
                        }
                    },
                },
            ],
        }
    ],
}
test_adviser("multi_output_clean_designreq", test4_inputs)

# ==============================================================================
# Test 5: Load exact om_topology_api_config.json if it exists
# ==============================================================================
import os
config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "om_topology_api_config.json")
if os.path.exists(config_path):
    with open(config_path) as f:
        exact_config = json.load(f)
    # The config has {inputs: {designRequirements, operatingPoints}, magnetic: {}, outputs: {}}
    # process_inputs expects {designRequirements, operatingPoints} directly
    exact_inputs = exact_config.get("inputs", exact_config)
    test_adviser("exact_config_file", exact_inputs)

print(f"\n{'='*60}")
print("ALL TESTS COMPLETED")
print(f"{'='*60}")
