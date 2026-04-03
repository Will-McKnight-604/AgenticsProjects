"""Binary search for segfault cause - uses 1 op point base (fast)."""
import json, copy, subprocess, sys

PYEXE = r"C:\Users\Will\AppData\Local\Programs\Python\Python311\python.exe"
BASE = r"C:\Users\Will\proximity_loss\Claude\.claude\worktrees\mag_advisor_opt\PEEC_Script"

def run_test(label, code):
    print(f"{label}... ", end="", flush=True)
    try:
        r = subprocess.run(
            [PYEXE, "-c", code],
            capture_output=True, text=True, timeout=180, cwd=BASE
        )
        out = (r.stdout + r.stderr).strip()
        if r.returncode < 0:
            print(f"SEGFAULT (signal {-r.returncode})")
            return False
        elif r.returncode != 0:
            print(f"ERROR (rc={r.returncode}): {out[:150]}")
            return False
        else:
            print(f"OK: {out[:150]}")
            return True
    except subprocess.TimeoutExpired:
        print("TIMEOUT")
        return False

# All tests use MKF with 1 op point as base (fast - takes ~30s)
PREAMBLE = """
import json, copy
import PyOpenMagnetics as pm

with open('_debug_mkf_122_processed.json') as f:
    mkf = json.load(f)
with open('_debug_processed_converter.json') as f:
    ours = json.load(f)

# Patch null peaks
for op in ours['operatingPoints']:
    for exc in op['excitationsPerWinding']:
        for sn in ('current', 'voltage'):
            sig = exc.get(sn, {})
            proc = sig.get('processed', {})
            if proc and proc.get('peak') is None:
                wave = sig.get('waveform', {}).get('data', [])
                if wave:
                    proc['peak'] = max(wave)
                    proc['positivePeak'] = max(wave)
                    proc['negativePeak'] = min(wave)

# Use MKF with 1 op point as base
mkf['operatingPoints'] = [mkf['operatingPoints'][0]]
mkf_op0 = mkf['operatingPoints'][0]
our_op0 = ours['operatingPoints'][0]
"""

RESULT_CHECK = """
result = pm.calculate_advised_magnetics(test, 1, 'available cores')
data = result.get('data', [])
if isinstance(data, list): print(f'{len(data)} results')
elif isinstance(data, str): print(f'Error: {data[:100]}')
"""

# Baseline
run_test("Test 0: MKF 1-op baseline", PREAMBLE + "test = mkf\n" + RESULT_CHECK)

# Full operating point swap
run_test("Test 1: our full op0", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'] = [copy.deepcopy(our_op0)]
""" + RESULT_CHECK)

# Swap individual excitations
run_test("Test 2: our W0 excitation", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'][0]['excitationsPerWinding'][0] = copy.deepcopy(our_op0['excitationsPerWinding'][0])
""" + RESULT_CHECK)

run_test("Test 3: our W1 excitation", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'][0]['excitationsPerWinding'][1] = copy.deepcopy(our_op0['excitationsPerWinding'][1])
""" + RESULT_CHECK)

# Swap individual signals within winding 0
run_test("Test 4: our W0 current", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'][0]['excitationsPerWinding'][0]['current'] = copy.deepcopy(our_op0['excitationsPerWinding'][0]['current'])
""" + RESULT_CHECK)

run_test("Test 5: our W0 voltage", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'][0]['excitationsPerWinding'][0]['voltage'] = copy.deepcopy(our_op0['excitationsPerWinding'][0]['voltage'])
""" + RESULT_CHECK)

run_test("Test 6: our W0 magCurrent", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'][0]['excitationsPerWinding'][0]['magnetizingCurrent'] = copy.deepcopy(our_op0['excitationsPerWinding'][0]['magnetizingCurrent'])
""" + RESULT_CHECK)

run_test("Test 7: our W0 frequency", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'][0]['excitationsPerWinding'][0]['frequency'] = our_op0['excitationsPerWinding'][0]['frequency']
""" + RESULT_CHECK)

# Swap individual signals within winding 1
run_test("Test 8: our W1 current", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'][0]['excitationsPerWinding'][1]['current'] = copy.deepcopy(our_op0['excitationsPerWinding'][1]['current'])
""" + RESULT_CHECK)

run_test("Test 9: our W1 voltage", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'][0]['excitationsPerWinding'][1]['voltage'] = copy.deepcopy(our_op0['excitationsPerWinding'][1]['voltage'])
""" + RESULT_CHECK)

run_test("Test 10: our W1 magCurrent", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'][0]['excitationsPerWinding'][1]['magnetizingCurrent'] = copy.deepcopy(our_op0['excitationsPerWinding'][1]['magnetizingCurrent'])
""" + RESULT_CHECK)

# Swap sub-fields within crashing signal(s) - current.processed fields
run_test("Test 11: our W0 current.processed only", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'][0]['excitationsPerWinding'][0]['current']['processed'] = copy.deepcopy(our_op0['excitationsPerWinding'][0]['current']['processed'])
""" + RESULT_CHECK)

run_test("Test 12: our W0 current.waveform only", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'][0]['excitationsPerWinding'][0]['current']['waveform'] = copy.deepcopy(our_op0['excitationsPerWinding'][0]['current']['waveform'])
""" + RESULT_CHECK)

run_test("Test 13: our W0 current.harmonics only", PREAMBLE + """
test = copy.deepcopy(mkf)
test['operatingPoints'][0]['excitationsPerWinding'][0]['current']['harmonics'] = copy.deepcopy(our_op0['excitationsPerWinding'][0]['current']['harmonics'])
""" + RESULT_CHECK)
