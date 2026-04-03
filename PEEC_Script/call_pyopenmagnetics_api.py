#!/usr/bin/env python3
"""
PyOpenMagnetics API Bridge

Receives MAS JSON input, calls PyOpenMagnetics adviser APIs, returns results.
This replaces hand-coded topology calculators with direct API calls to process_inputs()
and calculate_advised_magnetics().

Workflow:
  1. Read MAS JSON from input file
  2. Call pm.process_inputs(mas) to validate and compute harmonics
  3. Call pm.calculate_advised_magnetics(processed, max_results, core_mode)
  4. Format results and write to output JSON
  5. Print status to stdout for MATLAB parsing

Usage:
  python call_pyopenmagnetics_api.py <input_json> [output_json]

Input JSON (from MATLAB build_mas_structure.m):
  {
    "inputs": {
      "designRequirements": {
        "topology": "two-switch-forward",
        "inputVoltage": {"minimum": 100, "nominal": 145, "maximum": 190},
        "diodeVoltageDrop": 0.7,
        "currentRippleRatio": 0.3,
        ...
      },
      "operatingPoints": [
        {
          "switchingFrequency": 200000,
          "ambientTemperature": 25,
          "outputVoltage": 5.0,
          "outputCurrent": 5.0
        }
      ]
    },
    "magnetic": {},
    "outputs": {}
  }

Output JSON:
  {
    "status": "OK|ERROR",
    "data": [
      {
        "index": 1,
        "status": "OK",
        "magnetic": {...},
        "coil": {...},
        "losses": {...},
        "temperature": {...},
        "scoring": {...},
        "core_name": "Ferrite EI 26 Core A"
      },
      ...
    ],
    "count": 5
  }
"""

import json
import sys
import os
import time
from pathlib import Path


def _log(msg):
    """Safe stderr logger — silently drops writes when stderr is closed.

    On Windows, when Octave spawns a Python subprocess via system() in MSYS2
    bash, stderr can be closed before Python finishes writing.  A bare
    ``print(..., file=sys.stderr)`` then raises ``OSError: [Errno 22]
    Invalid argument``, which kills the entire script and prevents the
    result JSON from being written.
    """
    try:
        print(msg, file=sys.stderr)
    except OSError:
        pass


def find_pyopenmagnetics():
    """
    Find PyOpenMagnetics installation.
    Returns True if PyOpenMagnetics can be imported, False otherwise.
    """
    try:
        import PyOpenMagnetics
        return True
    except ImportError:
        return False


def transform_mas_operating_points(mas_op_points):
    """
    Transform MAS operating points format to generate_om_recommendations.py format.

    MAS format (from build_mas_structure.m):
      {switchingFrequency: 200000, ambientTemperature: 25, outputVoltages: 5, outputCurrents: 5}

    Target format (for generate_om_recommendations.py):
      {frequency_hz: 200000, ambient_temperature: 25, duty: 0.4, windings: [...]}

    Note: Without explicit waveform data from the topology calculator, we use defaults.
    """
    if not isinstance(mas_op_points, list):
        return []

    transformed = []
    for op in mas_op_points:
        if not isinstance(op, dict):
            continue

        # Extract frequency (MAS uses switchingFrequency)
        freq_hz = op.get('switchingFrequency', op.get('frequency_hz', 100e3))

        # Extract ambient temperature
        ambient_temp = op.get('ambientTemperature', op.get('ambient_temperature', 25))

        # Use default duty cycle (topology_wizard doesn't provide explicit duty)
        duty = op.get('duty', 0.4)

        # Build a minimal windings array (required by generate_om_recommendations.py)
        # For now, create placeholder windings based on output count
        windings = op.get('windings', [])
        if not windings or not isinstance(windings, list):
            # Create default primary + secondary windings
            windings = [
                {
                    "name": "Primary",
                    "waveform_label": "Rectangular",
                    "i_pp": 1.0,
                    "i_offset": 0.5,
                    "v_pp": 1.0,
                    "v_offset": 0.0
                },
                {
                    "name": "Secondary",
                    "waveform_label": "Rectangular",
                    "i_pp": 1.0,
                    "i_offset": 0.0,
                    "v_pp": 1.0,
                    "v_offset": 0.0
                }
            ]

        transformed.append({
            'frequency_hz': freq_hz,
            'ambient_temperature': ambient_temp,
            'duty': duty,
            'windings': windings,
            'name': op.get('name', 'operating_point')
        })

    return transformed


def _to_windows_path(path):
    """
    Convert an MSYS2 Unix-style path to a native Windows path.

    MSYS2 bash mounts Windows drive letters as /<letter>/ (e.g. /c/Users/).
    Native Windows Python processes do not understand these paths.
    This function converts them to <Letter>:\\ form.

    Examples:
      /c/Users/Will/script.py  ->  C:\\Users\\Will\\script.py
      /d/Projects/foo          ->  D:\\Projects\\foo
      C:\\already\\windows     ->  C:\\already\\windows  (unchanged)
      /usr/bin/python          ->  /usr/bin/python       (unchanged, not a drive path)
    """
    import re
    if not isinstance(path, str):
        return path
    # Match MSYS2 drive-letter mount: /X/... where X is a single letter
    m = re.match(r'^/([a-zA-Z])(/.*)$', path)
    if m:
        drive = m.group(1).upper()
        rest = m.group(2).replace('/', '\\')
        return f'{drive}:{rest}'
    # Already a Windows path or a true Unix path — return as-is after normpath
    return os.path.normpath(path)


def _find_python_with_pyopenmagnetics(default_executable):
    """
    Find a Python executable that has PyOpenMagnetics installed.

    On Windows with Octave's MSYS2 shell, sys.executable may be the MSYS2
    Python 3.12 which lacks PyOpenMagnetics.  This function searches for a
    native Windows Python 3.11 installation that has PyOpenMagnetics.

    Strategy:
      1. Check if default_executable itself has PyOpenMagnetics (quick import test).
      2. On Windows, try 'where python' to find all Python executables and test each.
      3. Try the Windows Python Launcher ('py -3.11') if available.
      4. Fall back to default_executable if nothing better is found.

    Returns the path to the best Python executable found.
    """
    import subprocess as _sp

    def _has_pyopenmagnetics(py_path):
        """Return True if py_path can import PyOpenMagnetics."""
        try:
            r = _sp.run(
                [py_path, '-c', 'import PyOpenMagnetics; print("OK")'],
                capture_output=True,
                text=True,
                timeout=15,
                env=os.environ.copy()  # Inherit full Windows env so DLLs can load
            )
            return r.returncode == 0 and 'OK' in r.stdout
        except Exception:
            return False

    # 1. Try current executable first (fast path - avoids shell calls)
    if _has_pyopenmagnetics(default_executable):
        _log(f"[API] Using sys.executable (has PyOpenMagnetics): {default_executable}")
        return default_executable

    _log(f"[API] sys.executable lacks PyOpenMagnetics, searching for alternative...")

    candidates = []

    # 2. Windows / MSYS2: search for native Windows Python executables.
    # MSYS2 Python has sys.platform='msys' and os.name='posix', but we are
    # still running on Windows and can call native Windows tools via subprocess.
    is_windows_host = (sys.platform in ('win32', 'msys', 'cygwin') or os.name == 'nt')
    if is_windows_host:
        # Use Windows 'where' command (available in cmd and MSYS2 bash) to find Python.
        try:
            r = _sp.run(['where', 'python'], capture_output=True, text=True, timeout=10)
            if r.returncode == 0:
                for line in r.stdout.splitlines():
                    p = line.strip()
                    # Convert MSYS2 path if needed
                    p = _to_windows_path(p)
                    if p and os.path.exists(p):
                        # Skip MSYS2 / Octave bundled Python (usually in usr/bin or octave dir)
                        p_lower = p.lower()
                        if 'octave' in p_lower or ('usr' in p_lower and 'bin' in p_lower):
                            continue
                        if p not in candidates:
                            candidates.append(p)
        except Exception as exc:
            _log(f"[API] 'where python' failed: {exc}")

        # 3. Try Windows Python Launcher for Python 3.11 specifically
        for py_ver in ('3.11', '3.10', '3.9'):
            try:
                r = _sp.run(['py', f'-{py_ver}', '-c', 'import sys; print(sys.executable)'],
                            capture_output=True, text=True, timeout=10)
                if r.returncode == 0:
                    p = _to_windows_path(r.stdout.strip())
                    if p and os.path.exists(p) and p not in candidates:
                        candidates.insert(0, p)  # prefer specific version
            except Exception:
                pass

    # Test candidates in order
    for p in candidates:
        if _has_pyopenmagnetics(p):
            _log(f"[API] Found Python with PyOpenMagnetics: {p}")
            return p
        else:
            _log(f"[API] Skipping (no PyOpenMagnetics): {p}")

    # 4. Fall back to default
    _log(f"[API] No better Python found, using default: {default_executable}")
    return default_executable


def call_pyopenmagnetics_adviser(mas_inputs, max_results=5, core_mode='STANDARD_CORES'):
    """
    Call PyOpenMagnetics adviser APIs via the generate_om_recommendations.py pipeline.

    This function delegates to generate_om_recommendations.py instead of directly calling
    the PyOpenMagnetics adviser APIs. This avoids API incompatibility issues where the
    adviser requires pre-computed fields (magnetizingInductance, turnsRatios, excitationsPerWinding)
    that are not present in the raw MAS structure created by build_mas_structure.m.

    The working pipeline:
      1. generate_om_recommendations.py validates and computes missing fields via process_inputs()
      2. It then calls the adviser with the complete structure
      3. Results are formatted and returned

    Args:
        mas_inputs: dict with structure {inputs: {designRequirements, operatingPoints}, magnetic: {}, outputs: {}}
        max_results: number of recommendations to return
        core_mode: 'STANDARD_CORES' or 'ALL_CORES' (note: currently unused in recommend mode)

    Returns:
        dict with structure {status, data: [...], count}
    """
    import subprocess
    t_adviser_fn_start = time.perf_counter()

    try:
        # Create a temporary config file for generate_om_recommendations.py
        _log("[API] Delegating to generate_om_recommendations.py pipeline...")

        # Determine script directory using Windows-normalised path.
        # __file__ may be an MSYS2 Unix path (e.g. /c/Users/...) when called via
        # Octave's MSYS2 bash shell.  os.path.abspath() on MSYS2 Python returns the
        # same Unix path, but subprocess children that are Windows Python binaries
        # need genuine Windows paths.  We convert MSYS2 paths (/c/foo) to Windows
        # paths (C:\foo) before passing them to subprocess.
        raw_dir = os.path.dirname(os.path.abspath(__file__))
        script_dir = _to_windows_path(raw_dir)
        # Use forward slashes for path joining to keep paths consistent across
        # MSYS2 Python (posixpath) and native Windows Python (ntpath).
        gen_script = script_dir.rstrip('/\\') + '/' + 'generate_om_recommendations.py'

        if not os.path.exists(gen_script):
            return {
                "status": "ERROR",
                "error": f"generate_om_recommendations.py not found at {gen_script}",
                "suggestion": "Ensure generate_om_recommendations.py is in the same directory"
            }

        # Place temp files in script_dir (a Windows-accessible path) rather than the
        # MSYS2 /tmp directory.  /tmp files are inaccessible to native Windows Python
        # processes spawned as subprocesses.
        import uuid
        uid = uuid.uuid4().hex[:8]
        config_path = script_dir.rstrip('/\\') + '/' + f'_api_config_{uid}.json'
        result_path = script_dir.rstrip('/\\') + '/' + f'_api_result_{uid}.json'

        # Check if MAS operating points already have waveform excitation data
        # (produced by generate_om_topology.py's build_operating_points())
        mas_op_points = mas_inputs['inputs']['operatingPoints']
        # MATLAB jsonencode converts single-element arrays to dicts — normalize to list
        if isinstance(mas_op_points, dict):
            mas_op_points = [mas_op_points]
            mas_inputs['inputs']['operatingPoints'] = mas_op_points
        has_excitations = (
            isinstance(mas_op_points, list) and
            len(mas_op_points) > 0 and
            isinstance(mas_op_points[0], dict) and
            'excitationsPerWinding' in mas_op_points[0]
        )

        # Build config dict that generate_om_recommendations.py expects
        config = {
            "mode": "recommend",
            "design_requirements": mas_inputs['inputs']['designRequirements'],
            "max_results": max_results,
            "weights": {"COST": 1.0, "LOSSES": 1.0, "DIMENSIONS": 1.0},
            "cores_in_stock": False,
            "output_file": result_path
        }

        # Forward adviser settings from MATLAB GUI (if present in MAS input)
        adv = mas_inputs.get('adviser_settings', {})
        if isinstance(adv, dict) and adv:
            config['cores_in_stock'] = bool(adv.get('cores_in_stock', False))
            config['include_toroidal_cores'] = bool(adv.get('include_toroidal_cores', True))
            config['include_stacked_cores'] = bool(adv.get('include_stacked_cores', False))
            config['include_distributed_gaps'] = bool(adv.get('include_distributed_gaps', False))
            config['max_cores_after_filtering'] = int(adv.get('max_cores_after_filtering', 100))
            config['max_results'] = int(adv.get('max_results', max_results))
            # Wire type filtering
            wfm = adv.get('wire_family_mode', 'auto_all')
            if wfm == 'foil_planar':
                config['wire_types'] = {'round': False, 'litz': False, 'rectangular': False, 'foil': True, 'planar': True}
            elif wfm == 'round_litz_rect':
                config['wire_types'] = {'round': True, 'litz': True, 'rectangular': True, 'foil': False, 'planar': False}
            # Weights
            weights = adv.get('weights', {})
            if isinstance(weights, dict) and weights:
                config['weights'] = weights
            print(f"[API] Adviser settings from GUI: inStock={config.get('cores_in_stock')}, "
                  f"toroidal={config.get('include_toroidal_cores')}, "
                  f"stacks={config.get('include_stacked_cores')}, "
                  f"maxFilter={config.get('max_cores_after_filtering')}", file=sys.stderr)

        if has_excitations:
            # Pass pre-built MAS operating points directly (waveform data from topology calculator)
            _log("[API] Using pre-built MAS operating points with waveform excitation data")
            config["operating_points_mas"] = mas_op_points
        else:
            # Transform MAS operating points (adds placeholder waveforms when none present)
            _log("[API] No waveform data in operating points; using placeholder excitations")
            config["operating_points"] = transform_mas_operating_points(mas_op_points)

        # Write config to temp file
        with open(config_path, 'w') as config_fh:
            json.dump(config, config_fh)

        try:
            # Find the best Python executable that has PyOpenMagnetics.
            # Priority: (1) sys.executable if it has PyOpenMagnetics,
            #           (2) Windows Python finder via 'where python' / 'py' launcher,
            #           (3) sys.executable as last resort.
            t_find_py_start = time.perf_counter()
            py_exec = _find_python_with_pyopenmagnetics(sys.executable)
            t_find_py = time.perf_counter() - t_find_py_start
            _log(f"[TIMER] Find Python:        {t_find_py:.3f}s")

            _log(f"[API] Running: {py_exec} {gen_script} {config_path}")
            t_subprocess_start = time.perf_counter()
            result = subprocess.run(
                [py_exec, gen_script, config_path],
                capture_output=True,
                text=True,
                timeout=600  # 10 minute timeout (multi-winding designs are slow)
            )
            t_subprocess = time.perf_counter() - t_subprocess_start
            _log(f"[TIMER] Run adviser script: {t_subprocess:.3f}s")

            if result.returncode != 0:
                # Forward subprocess output so MATLAB can see the actual error
                _log(f"[API] generate_om_recommendations.py failed (exit {result.returncode}):")
                if result.stderr:
                    _log(f"[API] stderr: {result.stderr[:1000]}")
                if result.stdout:
                    _log(f"[API] stdout: {result.stdout[:500]}")
                return {
                    "status": "ERROR",
                    "error": f"generate_om_recommendations.py failed with exit code {result.returncode}",
                    "stdout": result.stdout[:500],
                    "stderr": result.stderr[:1000]
                }

            # Load the results from the output file that generate_om_recommendations.py created
            if not os.path.exists(result_path):
                # Try to find where the output was written
                _log("[API] Warning: Expected output file not found at default location")
                # Check if the config had output_file specified
                if "output_file" in config:
                    result_path = config["output_file"]

            t_load_results_start = time.perf_counter()
            if os.path.exists(result_path):
                with open(result_path, 'r') as fh:
                    gen_results = json.load(fh)
            else:
                return {
                    "status": "ERROR",
                    "error": f"Could not find output file at {result_path}",
                    "stderr": result.stderr
                }

            t_load_results = time.perf_counter() - t_load_results_start
            _log(f"[TIMER] Load results:       {t_load_results:.3f}s")

            _log(f"[API] generate_om_recommendations.py returned status: {gen_results.get('status')}")

            # Convert generate_om_recommendations.py output format to this script's format
            if gen_results.get('status') != 'OK':
                return {
                    "status": "ERROR",
                    "error": gen_results.get('error', 'Unknown error from recommendations script'),
                    "details": gen_results
                }

            # Reformat recommendations as data array with index and status
            recommendations = gen_results.get('recommendations', [])
            results = []

            for i, rec in enumerate(recommendations):
                result_item = {
                    "index": i + 1,
                    "status": "OK",
                    "core_shape": rec.get('core_shape', 'Unknown'),
                    "material": rec.get('material', 'Unknown'),
                    "core_name": rec.get('core_shape', 'Unknown'),
                    "core_losses_w": rec.get('core_losses_w', 0.0),
                    "winding_losses_w": rec.get('winding_losses_w', 0.0),
                    "total_losses_w": rec.get('total_losses_w', 0.0),
                    "Lm_uH": rec.get('Lm_uH', 0.0),
                    "Llk_uH": rec.get('Llk_uH', 0.0),
                    "B_peak_mT": rec.get('B_peak_mT', 0.0),
                    "score": rec.get('score', 0.0),
                    "raw_score": rec.get('raw_score', 0.0)
                }

                # Include full recommendation data as well
                result_item['recommendation'] = rec

                results.append(result_item)

            _log(f"[API] Adviser completed: {len(results)} results")

            # Print adviser function internal breakdown
            t_adviser_fn_total = time.perf_counter() - t_adviser_fn_start
            _log(f"[TIMER] --- Adviser Breakdown ---")
            _log(f"[TIMER] Find Python:        {t_find_py:.3f}s")
            _log(f"[TIMER] Run adviser script: {t_subprocess:.3f}s")
            _log(f"[TIMER] Load results:       {t_load_results:.3f}s")
            _log(f"[TIMER] Adviser fn total:   {t_adviser_fn_total:.3f}s")

            return {
                "status": "OK",
                "data": results,
                "count": len(results)
            }

        finally:
            # Cleanup temporary files
            try:
                if os.path.exists(config_path):
                    os.remove(config_path)
                if os.path.exists(result_path):
                    os.remove(result_path)
            except Exception as e:
                _log(f"[API] Warning: Could not clean up temp files: {e}")

    except subprocess.TimeoutExpired:
        return {
            "status": "ERROR",
            "error": "generate_om_recommendations.py timed out after 10 minutes"
        }

    except Exception as e:
        import traceback
        return {
            "status": "ERROR",
            "error": str(e),
            "traceback": traceback.format_exc()
        }


def main():
    """Main entry point."""
    t_main_start = time.perf_counter()

    # Parse command line arguments
    if len(sys.argv) < 2:
        usage = """
Usage: python call_pyopenmagnetics_api.py <input_json_file> [output_json_file] [max_results] [core_mode]

Arguments:
  input_json_file: Path to MAS JSON input (created by MATLAB build_mas_structure())
  output_json_file: Path to output JSON (default: input_file + '_result.json')
  max_results: Number of recommendations (default: 5)
  core_mode: 'STANDARD_CORES' or 'ALL_CORES' (default: STANDARD_CORES)

Example:
  python call_pyopenmagnetics_api.py config.json results.json 5 STANDARD_CORES
"""
        print(json.dumps({
            "status": "ERROR",
            "error": "Insufficient arguments",
            "usage": usage
        }))
        print("ERROR", file=sys.stdout)
        return 1

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else input_file.replace('.json', '_result.json')
    max_results = int(sys.argv[3]) if len(sys.argv) > 3 else 5
    core_mode = sys.argv[4] if len(sys.argv) > 4 else 'STANDARD_CORES'

    try:
        # Validate input file exists
        if not os.path.exists(input_file):
            result = {
                "status": "ERROR",
                "error": f"Input file not found: {input_file}"
            }
            with open(output_file, 'w') as f:
                json.dump(result, f, indent=2, default=str)
            print("ERROR", file=sys.stdout)
            return 1

        # Read input JSON
        _log(f"[API] Loading input from {input_file}")
        t_load_config_start = time.perf_counter()
        with open(input_file, 'r') as f:
            mas_inputs = json.load(f)
        t_load_config = time.perf_counter() - t_load_config_start
        _log(f"[TIMER] Load config:        {t_load_config:.3f}s")

        # Validate structure
        if 'inputs' not in mas_inputs:
            result = {
                "status": "ERROR",
                "error": "Input JSON missing 'inputs' field"
            }
            with open(output_file, 'w') as f:
                json.dump(result, f, indent=2, default=str)
            print("ERROR", file=sys.stdout)
            return 1

        # Call adviser
        _log(f"[API] Configuration: max_results={max_results}, core_mode={core_mode}")
        t_adviser_start = time.perf_counter()
        result = call_pyopenmagnetics_adviser(
            mas_inputs,
            max_results=max_results,
            core_mode=core_mode
        )
        t_adviser = time.perf_counter() - t_adviser_start
        _log(f"[TIMER] Adviser total:      {t_adviser:.3f}s")

        # Write output JSON
        _log(f"[API] Writing results to {output_file}")
        t_write_start = time.perf_counter()
        with open(output_file, 'w') as f:
            json.dump(result, f, indent=2, default=str)
        t_write = time.perf_counter() - t_write_start
        _log(f"[TIMER] Write output:       {t_write:.3f}s")

        # Print timing summary
        t_total = time.perf_counter() - t_main_start
        _log(f"[TIMER] === API Bridge Summary ===")
        _log(f"[TIMER] Load config:        {t_load_config:.3f}s")
        _log(f"[TIMER] Adviser total:      {t_adviser:.3f}s")
        _log(f"[TIMER] Write output:       {t_write:.3f}s")
        _log(f"[TIMER] Total bridge:       {t_total:.3f}s")

        # Print status to stdout for MATLAB to parse
        if result['status'] == 'OK':
            print("OK", file=sys.stdout)
            _log(f"[API] Success: {result['count']} results returned")
            return 0
        else:
            print("ERROR", file=sys.stdout)
            _log(f"[API] Adviser error: {result.get('error', 'Unknown error')}")
            return 1

    except json.JSONDecodeError as e:
        result = {
            "status": "ERROR",
            "error": f"Invalid JSON in input file: {str(e)}",
            "file": input_file
        }
        try:
            with open(output_file, 'w') as f:
                json.dump(result, f, indent=2, default=str)
        except Exception:
            pass
        print("ERROR", file=sys.stdout)
        return 1

    except Exception as e:
        import traceback
        result = {
            "status": "ERROR",
            "error": str(e),
            "traceback": traceback.format_exc()
        }
        try:
            with open(output_file, 'w') as f:
                json.dump(result, f, indent=2, default=str)
        except Exception:
            pass
        print("ERROR", file=sys.stdout)
        return 1


if __name__ == '__main__':
    sys.exit(main())
