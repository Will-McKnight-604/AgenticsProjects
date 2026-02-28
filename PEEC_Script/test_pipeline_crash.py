#!/usr/bin/env python3
"""
Targeted crash diagnosis: tests each step of the PRODUCTION pipeline
in subprocess isolation to find which step causes the ACCESS_VIOLATION.

The standalone adviser test passes (max=3), so the crash is in one of:
  A) Larger pool size (max=10)
  B) compute_losses_for_recommendation (calculate_core_losses / calculate_winding_losses)
  C) resolve_wire_info (find_wire_by_name)
  D) match_wire_in_local_db (get_wire_names + find_wire_by_name loop)
  E) generate_om_recommendations.py run_recommendations() full pipeline

Each test runs in its own subprocess so a segfault doesn't kill the runner.
"""
import subprocess, sys, os, time

PYTHON = r"C:\Users\Will\AppData\Local\Programs\Python\Python311\python.exe"
TIMEOUT = 120
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Common multi-output input (same as standalone test that PASSES)
MULTI_OUTPUT_INPUTS = '''
import json
import PyOpenMagnetics as pm
pm.load_databases({})
inputs = {
    "designRequirements": {
        "topology": "Two Switch Forward Converter",
        "magnetizingInductance": {"nominal": 0.002537593984962406},
        "turnsRatios": [{"nominal": 7.894736842105263}, {"nominal": 7.894736842105263}],
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
processed = sn(pm.process_inputs(inputs))
'''


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
            cwd=SCRIPT_DIR
        )
        elapsed = time.time() - start
        output = (r.stdout + r.stderr).strip()
        if r.returncode == 0:
            print(f"  PASS ({elapsed:.1f}s)")
            # Show last 800 chars of output
            print(output[-800:] if len(output) > 800 else output)
            return True, output
        else:
            print(f"  FAIL ({elapsed:.1f}s) exit={r.returncode}")
            if r.returncode in (3221225477, -1073741819):
                print("  >>> ACCESS_VIOLATION (segfault in C++ code)")
            print(output[-800:] if len(output) > 800 else output)
            return False, output
    except subprocess.TimeoutExpired:
        print(f"  TIMEOUT after {timeout}s")
        return False, "TIMEOUT"


# ============================================================
# TEST A: adviser with max=10 (production pool_size)
# ============================================================
run_test("adviser max=10 (production pool_size)", MULTI_OUTPUT_INPUTS + '''
r = pm.calculate_advised_magnetics(processed, 10, "available cores")
n = len(r) if isinstance(r, list) else "dict"
print(f"OK: {n} results with max=10")
''')

# ============================================================
# TEST B: calculate_core_losses on multi-output result
# ============================================================
run_test("calculate_core_losses on 3-winding result", MULTI_OUTPUT_INPUTS + '''
results = pm.calculate_advised_magnetics(processed, 1, "available cores")
print(f"Got {len(results)} results")
item = results[0] if isinstance(results, list) else results
mas = item.get("mas", item)
magnetic = mas.get("magnetic", {})
core = magnetic.get("core", {})
coil = magnetic.get("coil", {})
inputs_data = mas.get("inputs", {})
print(f"core keys: {list(core.keys())[:5]}")
print(f"coil keys: {list(coil.keys())[:5]}")
print(f"n_func_desc: {len(coil.get('functionalDescription', []))}")
print("Calling calculate_core_losses...")
sys.stdout.flush()
try:
    core_result = pm.calculate_core_losses(core, coil, inputs_data, {})
    print(f"OK: core_losses = {core_result}")
except Exception as e:
    print(f"Exception (not crash): {e}")
print("calculate_core_losses survived")
''')

# ============================================================
# TEST C: calculate_winding_losses on multi-output result
# ============================================================
run_test("calculate_winding_losses on 3-winding result", MULTI_OUTPUT_INPUTS + '''
results = pm.calculate_advised_magnetics(processed, 1, "available cores")
item = results[0] if isinstance(results, list) else results
mas = item.get("mas", item)
magnetic = mas.get("magnetic", {})
inputs_data = mas.get("inputs", {})
ops = inputs_data.get("operatingPoints", [])
print(f"n_ops: {len(ops)}")
if ops:
    op = ops[0]
    temp = op.get("conditions", {}).get("ambientTemperature", 25.0)
    print(f"Calling calculate_winding_losses(temp={temp})...")
    sys.stdout.flush()
    try:
        wl_result = pm.calculate_winding_losses(magnetic, op, temp)
        print(f"OK: winding_losses = {wl_result}")
    except Exception as e:
        print(f"Exception (not crash): {e}")
    print("calculate_winding_losses survived")
''')

# ============================================================
# TEST D: find_wire_by_name on wire from multi-output result
# ============================================================
run_test("find_wire_by_name from multi-output result", MULTI_OUTPUT_INPUTS + '''
results = pm.calculate_advised_magnetics(processed, 1, "available cores")
item = results[0] if isinstance(results, list) else results
mas = item.get("mas", item)
magnetic = mas.get("magnetic", {})
coil = magnetic.get("coil", {})
func_desc = coil.get("functionalDescription", [])
print(f"n_windings: {len(func_desc)}")
for i, wd in enumerate(func_desc):
    wire = wd.get("wire", "")
    wire_name = wire.get("name", str(wire)) if isinstance(wire, dict) else str(wire)
    print(f"  winding[{i}] wire: {wire_name}")
    try:
        wire_data = pm.find_wire_by_name(wire_name)
        wtype = wire_data.get("type", "?") if isinstance(wire_data, dict) else "?"
        print(f"    find_wire_by_name OK: type={wtype}")
    except Exception as e:
        print(f"    find_wire_by_name exception: {e}")
print("find_wire_by_name survived for all windings")
''')

# ============================================================
# TEST E: get_wire_names (used in match_wire_in_local_db)
# ============================================================
run_test("get_wire_names", '''
import PyOpenMagnetics as pm
pm.load_databases({})
names = pm.get_wire_names()
n = len(names) if isinstance(names, list) else "not a list"
print(f"OK: {n} wire names")
''')

# ============================================================
# TEST F: Full generate_om_recommendations.py pipeline via subprocess
# ============================================================
run_test("full generate_om_recommendations.py pipeline", f'''
import json, subprocess, os
config = {{
    "mode": "recommend",
    "design_requirements": {{
        "topology": "Two Switch Forward Converter",
        "magnetizingInductance": {{"nominal": 0.002537593984962406}},
        "turnsRatios": [{{"nominal": 7.894736842105263}}, {{"nominal": 7.894736842105263}}],
        "inputVoltage": {{"minimum": 100, "maximum": 190, "nominal": 145}},
        "operatingTemperature": {{"maximum": 65}},
    }},
    "operating_points_mas": [{{
        "name": "OP1", "conditions": {{"ambientTemperature": 25}},
        "excitationsPerWinding": [
            {{"name": "Primary", "frequency": 200000,
             "current": {{"processed": {{"label": "Rectangular", "peakToPeak": 0.722, "offset": 0.361, "dutyCycle": 0.31}}}},
             "voltage": {{"processed": {{"label": "Rectangular", "peakToPeak": 145, "offset": 22.5, "dutyCycle": 0.31}}}}}},
            {{"name": "Secondary", "frequency": 200000,
             "current": {{"processed": {{"label": "Rectangular", "peakToPeak": 1.5, "offset": 5.0, "dutyCycle": 0.31}}}},
             "voltage": {{"processed": {{"label": "Rectangular", "peakToPeak": 5.0, "offset": 0.776, "dutyCycle": 0.31}}}}}},
            {{"name": "Secondary 2", "frequency": 200000,
             "current": {{"processed": {{"label": "Rectangular", "peakToPeak": 0.6, "offset": 2.0, "dutyCycle": 0.31}}}},
             "voltage": {{"processed": {{"label": "Rectangular", "peakToPeak": 3.3, "offset": 0.512, "dutyCycle": 0.31}}}}}},
        ]
    }}],
    "max_results": 5,
    "weights": {{"COST": 1.0, "LOSSES": 1.0, "DIMENSIONS": 1.0}},
    "cores_in_stock": False,
    "output_file": "_test_pipeline_result.json"
}}
config_path = "_test_pipeline_config.json"
with open(config_path, "w") as f:
    json.dump(config, f)
print("Config written, running generate_om_recommendations.py...")
import sys
sys.stdout.flush()
r = subprocess.run(
    [r"{PYTHON}", "generate_om_recommendations.py", config_path],
    capture_output=True, text=True, timeout=120,
    cwd=r"{SCRIPT_DIR}"
)
print(f"Exit code: {{r.returncode}}")
if r.stdout: print(f"stdout: {{r.stdout[:500]}}")
if r.stderr: print(f"stderr: {{r.stderr[-1000:]}}")
if r.returncode == 0 and os.path.exists("_test_pipeline_result.json"):
    with open("_test_pipeline_result.json") as f:
        result = json.load(f)
    print(f"Status: {{result.get('status')}}")
    print(f"n_results: {{result.get('n_results')}}")
    recs = result.get("recommendations", [])
    for i, rec in enumerate(recs):
        print(f"  [{{i}}] {{rec.get('core_shape')}} / {{rec.get('material')}} "
              f"core_loss={{rec.get('core_losses_w', 0):.3f}}W "
              f"winding_loss={{rec.get('winding_losses_w', 0):.3f}}W")
''', timeout=180)


# ============================================================
print(f"\n{'='*60}")
print("ALL PIPELINE TESTS COMPLETE")
print(f"{'='*60}")
