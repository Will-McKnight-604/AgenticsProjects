import os, sys, time, shutil, tempfile, threading, json

temp = tempfile.gettempdir()
capture_dir = os.path.join(os.path.dirname(__file__), '_ngspice_capture')
os.makedirs(capture_dir, exist_ok=True)

stop_event = threading.Event()
captured = []

def monitor():
    """Watch for ngspice_* dirs in temp and copy their contents"""
    seen = set()
    while not stop_event.is_set():
        try:
            for item in os.listdir(temp):
                if item.startswith('ngspice_') and item not in seen:
                    seen.add(item)
                    src = os.path.join(temp, item)
                    if os.path.isdir(src):
                        dst = os.path.join(capture_dir, item)
                        try:
                            shutil.copytree(src, dst)
                            captured.append(item)
                            print(f'  [monitor] Captured: {item} -> {dst}', file=sys.stderr)
                            # List contents
                            for f in os.listdir(dst):
                                fpath = os.path.join(dst, f)
                                print(f'    {f} ({os.path.getsize(fpath)} bytes)', file=sys.stderr)
                        except Exception as e:
                            print(f'  [monitor] Copy failed for {item}: {e}', file=sys.stderr)
        except Exception:
            pass
        time.sleep(0.05)  # Check every 50ms

# Start monitor thread
t = threading.Thread(target=monitor, daemon=True)
t.start()

# Now run the PyOM call
sys.path.insert(0, os.path.dirname(__file__))
from om_shared import import_pyopenmagnetics
pm = import_pyopenmagnetics()

with open('om_converter_api_config.json') as f:
    cfg = json.load(f)

converter_a = {
    'inputVoltage': cfg['converter']['inputVoltage'],
    'diodeVoltageDrop': cfg['converter']['diodeVoltageDrop'],
    'currentRippleRatio': cfg['converter']['currentRippleRatio'],
    'efficiency': cfg['converter']['efficiency'],
    'operatingPoints': cfg['converter']['operatingPoints']
}

print('Calling design_magnetics_from_converter...')
sys.stdout.flush()

result = pm.design_magnetics_from_converter(
    'two_switch_forward', converter_a, 1, 'standard cores', True, None
)

stop_event.set()
t.join(timeout=1)

if isinstance(result, dict) and 'error' in result:
    print(f'ERROR: {result["error"]}')
elif isinstance(result, dict) and 'data' in result:
    print(f'SUCCESS: {len(result["data"])} results')
else:
    print(f'Result: {str(result)[:300]}')

print(f'\nCaptured {len(captured)} ngspice temp dirs')
for c in captured:
    d = os.path.join(capture_dir, c)
    if os.path.exists(d):
        print(f'  {c}:')
        for f in os.listdir(d):
            fpath = os.path.join(d, f)
            print(f'    {f} ({os.path.getsize(fpath)} bytes)')
            if f.endswith('.cir') or f.endswith('.sp'):
                with open(fpath) as fp:
                    content = fp.read()
                print(f'    --- Content ---')
                print(content[:2000])
                print(f'    --- End ---')
