#!/usr/bin/env python3
"""
Comprehensive audit of PyOpenMagnetics settings: which keys are actually accepted
vs silently dropped by the C++ set_settings() / get_settings() API.

Run:  python _test_settings_audit.py
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from om_shared import import_pyopenmagnetics
pm = import_pyopenmagnetics()


def main():
    print("=" * 100)
    print("STEP 1: Baseline settings from pm.get_settings()")
    print("=" * 100)

    baseline = pm.get_settings()
    if not isinstance(baseline, dict):
        print(f"  FATAL: get_settings() returned {type(baseline).__name__}: {baseline}")
        return

    for k in sorted(baseline.keys()):
        print(f"  {k} = {baseline[k]!r}  (type: {type(baseline[k]).__name__})")

    print()
    print("=" * 100)
    print("STEP 2: Test each setting key our code tries to use")
    print("=" * 100)

    # All setting keys found across call_converter_api.py, generate_om_recommendations.py,
    # and call_pyopenmagnetics_api.py
    our_settings = {
        # --- These ARE in the C++ get_settings() output ---
        "useOnlyCoresInStock":   (False, "Filter core DB to in-stock only"),

        # --- These are NOT in C++ get_settings() / set_settings() ---
        "useToroidalCores":                          (True,  "Include toroidal core shapes"),
        "useConcentricCores":                        (True,  "Include concentric core shapes"),
        "coreAdviserIncludeStacks":                  (True,  "Allow stacked core combinations"),
        "coreAdviserIncludeDistributedGaps":          (True,  "Allow distributed gap configurations"),
        "coreAdviserMaximumMagneticsAfterFiltering":  (200,   "Max cores to evaluate after filtering"),
        "coilAdviserMaximumNumberWires":              (100,   "Max wire candidates per winding"),
        "wireAdviserIncludeRound":                   (True,  "Include round wire in search"),
        "wireAdviserIncludeLitz":                    (True,  "Include litz wire in search"),
        "wireAdviserIncludeRectangular":              (True,  "Include rectangular wire in search"),
        "wireAdviserIncludeFoil":                    (True,  "Include foil wire in search"),
        "wireAdviserIncludePlanar":                  (True,  "Include planar wire in search"),
    }

    # Also test the names used by the official web frontend (MagneticAdviser.vue)
    frontend_settings = {
        "coreIncludeDistributedGaps":  (True,  "[FRONTEND] Allow distributed gaps"),
        "coreIncludeStacks":           (True,  "[FRONTEND] Allow stacked cores"),
    }

    all_test = {**our_settings, **frontend_settings}

    results = []
    for key, (test_val, purpose) in all_test.items():
        # Start fresh
        pm.set_settings(dict(baseline))

        settings = pm.get_settings()
        original_val = settings.get(key, "<NOT PRESENT>")

        # Make sure test value differs from current
        effective_test = test_val
        if key in settings and settings[key] == test_val:
            if isinstance(test_val, bool):
                effective_test = not test_val
            elif isinstance(test_val, (int, float)):
                effective_test = test_val + 77

        settings[key] = effective_test
        try:
            pm.set_settings(settings)
            readback = pm.get_settings()
            if key in readback:
                actual = readback[key]
                if actual == effective_test:
                    status = "ACCEPTED"
                else:
                    status = f"MODIFIED (set={effective_test!r}, got={actual!r})"
            else:
                status = "SILENTLY DROPPED"
        except Exception as e:
            status = f"ERROR: {e}"

        results.append((key, purpose, original_val, effective_test, status))

    print(f"\n  {'Setting Key':<50} {'Purpose':<45} {'Default':<15} {'Test':<10} {'Result'}")
    print(f"  {'-'*50} {'-'*45} {'-'*15} {'-'*10} {'-'*25}")
    for key, purpose, orig, tval, status in results:
        print(f"  {key:<50} {purpose:<45} {str(orig):<15} {str(tval):<10} {status}")

    # Restore
    pm.set_settings(dict(baseline))

    print()
    print("=" * 100)
    print("STEP 3: All pm.* public methods (look for alternative APIs)")
    print("=" * 100)
    methods = [m for m in dir(pm) if not m.startswith("_")]
    for m in sorted(methods):
        obj = getattr(pm, m)
        kind = "function" if callable(obj) else type(obj).__name__
        print(f"  {m} ({kind})")

    print()
    print("=" * 100)
    print("STEP 4: Check pm.get_defaults() for adviser defaults")
    print("=" * 100)
    try:
        defaults = pm.get_defaults()
        if isinstance(defaults, dict):
            for k in sorted(defaults.keys()):
                print(f"  {k} = {defaults[k]!r}")
        else:
            print(f"  get_defaults() returned: {defaults}")
    except Exception as e:
        print(f"  get_defaults() not available: {e}")

    print()
    print("=" * 100)
    print("STEP 5: Test if arbitrary extra keys are silently dropped")
    print("=" * 100)
    settings = pm.get_settings()
    settings["totallyFakeKey12345"] = True
    settings["wireAdviserMaxParallels"] = 10
    try:
        pm.set_settings(settings)
        readback = pm.get_settings()
        for fk in ["totallyFakeKey12345", "wireAdviserMaxParallels"]:
            if fk in readback:
                print(f"  {fk}: ACCEPTED (found in readback = {readback[fk]!r})")
            else:
                print(f"  {fk}: SILENTLY DROPPED")
    except Exception as e:
        print(f"  ERROR setting fake keys: {e}")

    pm.set_settings(dict(baseline))

    print()
    print("=" * 100)
    print("STEP 6: Check if reset_settings() is available")
    print("=" * 100)
    try:
        pm.reset_settings()
        print("  pm.reset_settings() available and working")
    except AttributeError:
        print("  pm.reset_settings() NOT available")
    except Exception as e:
        print(f"  pm.reset_settings() error: {e}")


if __name__ == "__main__":
    main()
