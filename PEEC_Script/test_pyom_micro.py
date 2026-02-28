#!/usr/bin/env python3
"""
Micro diagnostic tests for PyOpenMagnetics adviser.
Each test runs in its own SUBPROCESS so a segfault doesn't kill the runner.
"""
import json, sys, os, subprocess, time

PYTHON = r"C:\Users\Will\AppData\Local\Programs\Python\Python311\python.exe"
TIMEOUT = 60  # seconds per test

def run_test(label, code, timeout=TIMEOUT):
    """Run a snippet in a subprocess. Returns (passed, output)."""
    print(f"\n{'='*60}")
    print(f"TEST: {label}")
    print(f"{'='*60}")
    sys.stdout.flush()

    start = time.time()
    try:
        r = subprocess.run(
            [PYTHON, "-c", code],
            capture_output=True, text=True, timeout=timeout,
            cwd=os.path.dirname(os.path.abspath(__file__))
        )
        elapsed = time.time() - start
        output = (r.stdout + r.stderr).strip()
        if r.returncode == 0:
            print(f"PASS ({elapsed:.1f}s) exit=0")
            print(output[-500:] if len(output) > 500 else output)
            return True, output
        else:
            print(f"FAIL ({elapsed:.1f}s) exit={r.returncode}")
            # 3221225477 = 0xC0000005 = ACCESS_VIOLATION
            if r.returncode == 3221225477 or r.returncode == -1073741819:
                print("  >>> ACCESS_VIOLATION (segfault in C++ code)")
            print(output[-500:] if len(output) > 500 else output)
            return False, output
    except subprocess.TimeoutExpired:
        elapsed = time.time() - start
        print(f"TIMEOUT ({elapsed:.1f}s) - killed after {timeout}s")
        return False, "TIMEOUT"

# ============================================================
# TEST 0: Can we import PyOpenMagnetics?
# ============================================================
run_test("Import PyOpenMagnetics", """
import PyOpenMagnetics as pm
print(f"OK: PyOpenMagnetics imported")
""")

# ============================================================
# TEST 1: Load databases
# ============================================================
run_test("Load databases", """
import PyOpenMagnetics as pm
pm.load_databases({})
n = len(pm.get_available_core_shapes())
print(f"OK: {n} core shapes loaded")
""")

# ============================================================
# TEST 2: process_inputs - single output (2 windings)
# ============================================================
run_test("process_inputs single output", """
import json
import PyOpenMagnetics as pm
pm.load_databases({})
inputs = {
    "designRequirements": {
        "topology": "Two Switch Forward Converter",
        "magnetizingInductance": {"nominal": 0.002537},
        "turnsRatios": [{"nominal": 7.89}],
        "inputVoltage": {"minimum": 100, "maximum": 190, "nominal": 145},
        "operatingTemperature": {"maximum": 65},
    },
    "operatingPoints": [{
        "name": "OP1", "conditions": {"ambientTemperature": 25},
        "excitationsPerWinding": [
            {"name": "Primary", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 0.722, "offset": 0.361, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 145, "offset": 22.5, "dutyCycle": 0.31}}},
            {"name": "Secondary", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 1.5, "offset": 5.0, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 5.0, "offset": 0.776, "dutyCycle": 0.31}}},
        ]
    }]
}
r = pm.process_inputs(inputs)
print(f"OK: process_inputs returned {type(r).__name__}")
""")

# ============================================================
# TEST 3: adviser - single output, max=1
# ============================================================
run_test("adviser single output max=1", """
import json
import PyOpenMagnetics as pm
pm.load_databases({})
inputs = {
    "designRequirements": {
        "topology": "Two Switch Forward Converter",
        "magnetizingInductance": {"nominal": 0.002537},
        "turnsRatios": [{"nominal": 7.89}],
        "inputVoltage": {"minimum": 100, "maximum": 190, "nominal": 145},
        "operatingTemperature": {"maximum": 65},
    },
    "operatingPoints": [{
        "name": "OP1", "conditions": {"ambientTemperature": 25},
        "excitationsPerWinding": [
            {"name": "Primary", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 0.722, "offset": 0.361, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 145, "offset": 22.5, "dutyCycle": 0.31}}},
            {"name": "Secondary", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 1.5, "offset": 5.0, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 5.0, "offset": 0.776, "dutyCycle": 0.31}}},
        ]
    }]
}
def sn(o):
    if isinstance(o, dict): return {k: sn(v) for k, v in o.items() if v is not None}
    elif isinstance(o, list): return [sn(v) for v in o]
    return o
p = sn(pm.process_inputs(inputs))
r = pm.calculate_advised_magnetics(p, 1, "available cores")
n = len(r) if isinstance(r, list) else 'dict'
print(f"OK: {n} results")
""")

# ============================================================
# TEST 4: process_inputs - multi output (3 windings)
# ============================================================
run_test("process_inputs multi output", """
import json
import PyOpenMagnetics as pm
pm.load_databases({})
inputs = {
    "designRequirements": {
        "topology": "Two Switch Forward Converter",
        "magnetizingInductance": {"nominal": 0.002537},
        "turnsRatios": [{"nominal": 7.89}, {"nominal": 7.89}],
        "inputVoltage": {"minimum": 100, "maximum": 190, "nominal": 145},
        "operatingTemperature": {"maximum": 65},
    },
    "operatingPoints": [{
        "name": "OP1", "conditions": {"ambientTemperature": 25},
        "excitationsPerWinding": [
            {"name": "Primary", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 0.722, "offset": 0.361, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 145, "offset": 22.5, "dutyCycle": 0.31}}},
            {"name": "Secondary", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 1.5, "offset": 5.0, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 5.0, "offset": 0.776, "dutyCycle": 0.31}}},
            {"name": "Secondary 2", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 0.6, "offset": 2.0, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 3.3, "offset": 0.512, "dutyCycle": 0.31}}},
        ]
    }]
}
r = pm.process_inputs(inputs)
print(f"OK: process_inputs returned {type(r).__name__}")
""")

# ============================================================
# TEST 5: adviser - multi output, max=1 (THE CRASH TEST)
# ============================================================
run_test("adviser multi output max=1", """
import json
import PyOpenMagnetics as pm
pm.load_databases({})
inputs = {
    "designRequirements": {
        "topology": "Two Switch Forward Converter",
        "magnetizingInductance": {"nominal": 0.002537},
        "turnsRatios": [{"nominal": 7.89}, {"nominal": 7.89}],
        "inputVoltage": {"minimum": 100, "maximum": 190, "nominal": 145},
        "operatingTemperature": {"maximum": 65},
    },
    "operatingPoints": [{
        "name": "OP1", "conditions": {"ambientTemperature": 25},
        "excitationsPerWinding": [
            {"name": "Primary", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 0.722, "offset": 0.361, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 145, "offset": 22.5, "dutyCycle": 0.31}}},
            {"name": "Secondary", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 1.5, "offset": 5.0, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 5.0, "offset": 0.776, "dutyCycle": 0.31}}},
            {"name": "Secondary 2", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 0.6, "offset": 2.0, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 3.3, "offset": 0.512, "dutyCycle": 0.31}}},
        ]
    }]
}
def sn(o):
    if isinstance(o, dict): return {k: sn(v) for k, v in o.items() if v is not None}
    elif isinstance(o, list): return [sn(v) for v in o]
    return o
p = sn(pm.process_inputs(inputs))
r = pm.calculate_advised_magnetics(p, 1, "available cores")
n = len(r) if isinstance(r, list) else 'dict'
print(f"OK: {n} results")
""")

# ============================================================
# TEST 6: adviser - multi output + insulation
# ============================================================
run_test("adviser multi output + insulation", """
import json
import PyOpenMagnetics as pm
pm.load_databases({})
inputs = {
    "designRequirements": {
        "topology": "Two Switch Forward Converter",
        "magnetizingInductance": {"nominal": 0.002537},
        "turnsRatios": [{"nominal": 7.89}, {"nominal": 7.89}],
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
    "operatingPoints": [{
        "name": "OP1", "conditions": {"ambientTemperature": 25},
        "excitationsPerWinding": [
            {"name": "Primary", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 0.722, "offset": 0.361, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 145, "offset": 22.5, "dutyCycle": 0.31}}},
            {"name": "Secondary", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 1.5, "offset": 5.0, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 5.0, "offset": 0.776, "dutyCycle": 0.31}}},
            {"name": "Secondary 2", "frequency": 200000,
             "current": {"processed": {"label": "Rectangular", "peakToPeak": 0.6, "offset": 2.0, "dutyCycle": 0.31}},
             "voltage": {"processed": {"label": "Rectangular", "peakToPeak": 3.3, "offset": 0.512, "dutyCycle": 0.31}}},
        ]
    }]
}
def sn(o):
    if isinstance(o, dict): return {k: sn(v) for k, v in o.items() if v is not None}
    elif isinstance(o, list): return [sn(v) for v in o]
    return o
p = sn(pm.process_inputs(inputs))
r = pm.calculate_advised_magnetics(p, 1, "available cores")
n = len(r) if isinstance(r, list) else 'dict'
print(f"OK: {n} results")
""")

# ============================================================
# TEST 7: Exact om_topology_api_config.json
# ============================================================
run_test("exact config file", f"""
import json
import PyOpenMagnetics as pm
pm.load_databases({{}})
with open("om_topology_api_config.json") as f:
    cfg = json.load(f)
inputs = cfg.get("inputs", cfg)
def sn(o):
    if isinstance(o, dict): return {{k: sn(v) for k, v in o.items() if v is not None}}
    elif isinstance(o, list): return [sn(v) for v in o]
    return o
p = sn(pm.process_inputs(inputs))
r = pm.calculate_advised_magnetics(p, 1, "available cores")
n = len(r) if isinstance(r, list) else 'dict'
print(f"OK: {{n}} results")
""")

# ============================================================
print(f"\n{'='*60}")
print("ALL TESTS COMPLETE")
print(f"{'='*60}")
