#!/usr/bin/env python3
"""Stress test for generate_om_waveforms.py — find edge cases that break."""

import json
import subprocess
import sys
import os
import math

PY = sys.executable
SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'generate_om_waveforms.py')
CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), '_stress_config.json')
RESULTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '_stress_results.json')


def run_test(name, config):
    with open(CONFIG, 'w') as f:
        json.dump(config, f)
    try:
        r = subprocess.run([PY, SCRIPT, CONFIG], capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        print(f'  TOUT | {name:50s} | Timed out after 30s')
        return 'TOUT'

    if r.returncode == 0:
        try:
            with open(RESULTS, 'r') as f:
                res = json.load(f)
        except Exception as e:
            print(f'  FAIL | {name:50s} | JSON read error: {e}')
            return 'FAIL'

        n_ops = len(res.get('operatingPoints', []))
        n_w = 0
        if n_ops > 0:
            n_w = len(res['operatingPoints'][0].get('excitationsPerWinding', []))

        # Check for NaN/Inf in waveform data
        bad_count = 0
        for op in res.get('operatingPoints', []):
            for exc in op.get('excitationsPerWinding', []):
                for sig_key in ('voltage', 'current'):
                    sig = exc.get(sig_key, {})
                    wf = sig.get('waveform', {})
                    for arr_key in ('time', 'data'):
                        arr = wf.get(arr_key, [])
                        for v in arr:
                            if isinstance(v, (int, float)):
                                if math.isnan(v) or math.isinf(v):
                                    bad_count += 1

        detail = f'{n_ops} ops, {n_w} windings'
        if bad_count > 0:
            detail += f' [NaN/Inf x{bad_count}!]'
            print(f'  WARN | {name:50s} | {detail}')
            return 'WARN'
        print(f'  PASS | {name:50s} | {detail}')
        return 'PASS'
    else:
        # Expected failures (unknown topology, etc.) are OK
        stdout = r.stdout.strip()[:60] if r.stdout else ''
        stderr_last = r.stderr.strip().split('\n')[-1][:60] if r.stderr else ''
        detail = stdout or stderr_last
        print(f'  FAIL | {name:50s} | exit={r.returncode} {detail}')
        return 'FAIL'


def main():
    base = {
        'vin_min': 100, 'vin_max': 400, 'vin_nom': 200,
        'vd': 0.5, 'fsw_khz': 100,
        'output_voltages': [12], 'output_currents': [5],
        'efficiency': 90, 'max_ripple': 30
    }

    counts = {'PASS': 0, 'FAIL': 0, 'WARN': 0, 'TOUT': 0}

    print('=' * 100)
    print('STRESS TEST: Python Waveform Generator')
    print('=' * 100)

    # --- Normal topologies ---
    for topo in ['flyback', 'buck', 'boost', 'push_pull', 'isolated_buck', 'isolated_buck_boost']:
        s = run_test(f'{topo} (defaults)',
                     {'topology': topo, 'converter': base, 'mode': 'analytical', 'output_file': RESULTS})
        counts[s] += 1

    # --- Edge cases: boundary values ---
    tests = [
        ('flyback zero Vout',
         {'topology': 'flyback', 'converter': {**base, 'output_voltages': [0], 'output_currents': [5]},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('flyback zero Iout',
         {'topology': 'flyback', 'converter': {**base, 'output_voltages': [12], 'output_currents': [0]},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('flyback vin_min == vin_max',
         {'topology': 'flyback', 'converter': {**base, 'vin_min': 200, 'vin_max': 200, 'vin_nom': 200},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('buck 10MHz fsw',
         {'topology': 'buck', 'converter': {**base, 'fsw_khz': 10000},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('buck 1Hz fsw',
         {'topology': 'buck', 'converter': {**base, 'fsw_khz': 0.001},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('buck extreme ratio 1000:0.5',
         {'topology': 'buck', 'converter': {**base, 'vin_min': 1, 'vin_max': 1000, 'output_voltages': [0.5]},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('flyback 4 outputs',
         {'topology': 'flyback',
          'converter': {**base, 'output_voltages': [12, 5, 3.3, 1.8], 'output_currents': [5, 3, 2, 1]},
          'topology_results': {'Lm_uH': 200, 'turns_ratios': [10, 24, 36, 66]},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('flyback empty converter',
         {'topology': 'flyback', 'converter': {},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('flyback negative Vout',
         {'topology': 'flyback', 'converter': {**base, 'output_voltages': [-12]},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('unknown topology',
         {'topology': 'magic_converter', 'converter': base,
          'mode': 'analytical', 'output_file': RESULTS}),

        ('unknown mode',
         {'topology': 'flyback', 'converter': base,
          'mode': 'simulated', 'output_file': RESULTS}),

        ('flyback efficiency=0',
         {'topology': 'flyback', 'converter': {**base, 'efficiency': 0},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('buck fsw=0',
         {'topology': 'buck', 'converter': {**base, 'fsw_khz': 0},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('flyback vin swapped (min>max)',
         {'topology': 'flyback', 'converter': {**base, 'vin_min': 400, 'vin_max': 100},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('flyback non-numeric vin',
         {'topology': 'flyback', 'converter': {**base, 'vin_min': 'abc', 'vin_max': None},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('boost Vout < Vin (impossible)',
         {'topology': 'boost', 'converter': {**base, 'vin_min': 100, 'vin_max': 400, 'output_voltages': [5]},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('flyback huge inductance 100H',
         {'topology': 'flyback', 'converter': base,
          'topology_results': {'Lm_uH': 1e8, 'turns_ratios': [10]},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('flyback tiny inductance 1nH',
         {'topology': 'flyback', 'converter': base,
          'topology_results': {'Lm_uH': 0.001, 'turns_ratios': [10]},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('buck negative current',
         {'topology': 'buck', 'converter': {**base, 'output_currents': [-5]},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('flyback turns_ratio=0',
         {'topology': 'flyback', 'converter': base,
          'topology_results': {'Lm_uH': 200, 'turns_ratios': [0]},
          'mode': 'analytical', 'output_file': RESULTS}),

        ('push_pull single output',
         {'topology': 'push_pull', 'converter': base,
          'mode': 'analytical', 'output_file': RESULTS}),

        ('isolated_buck 3 outputs',
         {'topology': 'isolated_buck',
          'converter': {**base, 'output_voltages': [12, 5, 3.3], 'output_currents': [5, 3, 2]},
          'topology_results': {'Lm_uH': 80, 'turns_ratios': [10, 24, 36]},
          'mode': 'analytical', 'output_file': RESULTS}),
    ]

    for name, config in tests:
        s = run_test(name, config)
        counts[s] += 1

    print('=' * 100)
    total = sum(counts.values())
    print(f'RESULTS: {counts["PASS"]} PASS, {counts["WARN"]} WARN, '
          f'{counts["FAIL"]} FAIL, {counts["TOUT"]} TIMEOUT  (total: {total})')
    print('=' * 100)

    # Cleanup
    for f in [CONFIG, RESULTS]:
        if os.path.exists(f):
            os.remove(f)

    sys.exit(0 if counts['WARN'] == 0 and counts['TOUT'] == 0 else 1)


if __name__ == '__main__':
    main()
