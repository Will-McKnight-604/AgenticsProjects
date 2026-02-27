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
from pathlib import Path


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
    import tempfile

    try:
        # Create a temporary config file for generate_om_recommendations.py
        print("[API] Delegating to generate_om_recommendations.py pipeline...", file=sys.stderr)

        # Create temporary files first to get their paths
        config_fh = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
        config_path = config_fh.name
        config_fh.close()

        result_fh = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
        result_path = result_fh.name
        result_fh.close()

        # Transform MAS operating points to the format generate_om_recommendations.py expects
        transformed_op_points = transform_mas_operating_points(mas_inputs['inputs']['operatingPoints'])

        # Build config dict that generate_om_recommendations.py expects
        config = {
            "mode": "recommend",
            "design_requirements": mas_inputs['inputs']['designRequirements'],
            "operating_points": transformed_op_points,
            "max_results": max_results,
            "weights": {"COST": 1.0, "LOSSES": 1.0, "DIMENSIONS": 1.0},
            "cores_in_stock": False,
            "output_file": result_path
        }

        # Write config to temp file
        with open(config_path, 'w') as config_fh:
            json.dump(config, config_fh)

        try:
            # Determine script directory and path to generate_om_recommendations.py
            script_dir = os.path.dirname(os.path.abspath(__file__))
            gen_script = os.path.join(script_dir, 'generate_om_recommendations.py')

            if not os.path.exists(gen_script):
                return {
                    "status": "ERROR",
                    "error": f"generate_om_recommendations.py not found at {gen_script}",
                    "suggestion": "Ensure generate_om_recommendations.py is in the same directory"
                }

            # Run generate_om_recommendations.py
            print(f"[API] Running: python {gen_script} {config_path}", file=sys.stderr)
            result = subprocess.run(
                [sys.executable, gen_script, config_path],
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout
            )

            if result.returncode != 0:
                return {
                    "status": "ERROR",
                    "error": f"generate_om_recommendations.py failed with exit code {result.returncode}",
                    "stdout": result.stdout[:500],
                    "stderr": result.stderr[:500]
                }

            # Load the results from the output file that generate_om_recommendations.py created
            if not os.path.exists(result_path):
                # Try to find where the output was written
                print("[API] Warning: Expected output file not found at default location", file=sys.stderr)
                # Check if the config had output_file specified
                if "output_file" in config:
                    result_path = config["output_file"]

            if os.path.exists(result_path):
                with open(result_path, 'r') as fh:
                    gen_results = json.load(fh)
            else:
                return {
                    "status": "ERROR",
                    "error": f"Could not find output file at {result_path}",
                    "stderr": result.stderr
                }

            print(f"[API] generate_om_recommendations.py returned status: {gen_results.get('status')}", file=sys.stderr)

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

            print(f"[API] Adviser completed: {len(results)} results", file=sys.stderr)

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
                print(f"[API] Warning: Could not clean up temp files: {e}", file=sys.stderr)

    except subprocess.TimeoutExpired:
        return {
            "status": "ERROR",
            "error": "generate_om_recommendations.py timed out after 5 minutes"
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
        print(f"[API] Loading input from {input_file}", file=sys.stderr)
        with open(input_file, 'r') as f:
            mas_inputs = json.load(f)

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
        print(f"[API] Configuration: max_results={max_results}, core_mode={core_mode}", file=sys.stderr)
        result = call_pyopenmagnetics_adviser(
            mas_inputs,
            max_results=max_results,
            core_mode=core_mode
        )

        # Write output JSON
        print(f"[API] Writing results to {output_file}", file=sys.stderr)
        with open(output_file, 'w') as f:
            json.dump(result, f, indent=2, default=str)

        # Print status to stdout for MATLAB to parse
        if result['status'] == 'OK':
            print("OK", file=sys.stdout)
            print(f"[API] Success: {result['count']} results returned", file=sys.stderr)
            return 0
        else:
            print("ERROR", file=sys.stdout)
            print(f"[API] Adviser error: {result.get('error', 'Unknown error')}", file=sys.stderr)
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
