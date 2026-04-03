#!/usr/bin/env python3
"""
Shared helpers for PEEC_Script Python modules.

Provides common utilities used across the OpenMagnetics pipeline scripts.
Import from this module instead of duplicating these functions.

Usage:
    from om_shared import as_float, clamp, as_list, _log, sanitize_local_key
    from om_shared import import_pyopenmagnetics
"""

import re
import sys


def _log(msg):
    """Safe stderr print that won't crash on Windows/Octave closed handles.

    On Windows, when Octave spawns a Python subprocess via system() in MSYS2
    bash, stderr can be closed before Python finishes writing.  A bare
    ``print(..., file=sys.stderr)`` then raises ``OSError: [Errno 22]
    Invalid argument``, which kills the entire script and prevents the
    result JSON from being written.
    """
    try:
        print(msg, file=sys.stderr)
    except (OSError, IOError):
        pass


def as_float(value, default=0.0):
    """Convert to float, return default on failure.

    Handles int, float, str, and None gracefully.
    """
    try:
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, str):
            return float(value)
        return float(default)
    except Exception:
        return float(default)


def clamp(value, lo, hi):
    """Clamp value between lo and hi."""
    return max(lo, min(hi, value))


def as_list(value):
    """Ensure value is a list. Wrap scalars, parse numeric strings."""
    if isinstance(value, list):
        return value
    if isinstance(value, (int, float)):
        return [value]
    if isinstance(value, str):
        try:
            return [float(value)]
        except Exception:
            return []
    return []


def sanitize_local_key(raw):
    """Match MATLAB make_valid_name/sanitize_field_name behavior.

    Replaces non-alphanumeric characters with underscores and ensures
    the result starts with a letter (prefixing with 'W_' if needed).
    """
    if raw is None:
        raw = "Unknown"
    if not isinstance(raw, str):
        raw = str(raw)
    name = re.sub(r"[^a-zA-Z0-9_]", "_", raw)
    if not name:
        name = "Unknown"
    if not name[0].isalpha():
        name = f"W_{name}"
    return name


# Topology key mapping: GUI underscore keys → MAS formal names
TOPOLOGY_MAP = {
    "two_switch_forward": "Two Switch Forward Converter",
    "single_switch_forward": "Single Switch Forward Converter",
    "active_clamp_forward": "Active Clamp Forward Converter",
    "flyback": "Flyback Converter",
    "push_pull": "Push Pull Converter",
    "buck": "Buck Converter",
    "boost": "Boost Converter",
    "isolated_buck": "Isolated Buck Converter",
    "isolated_buck_boost": "Isolated Buck Boost Converter",
}


def strip_nulls(obj):
    """Recursively remove None values from dicts and lists.

    C++ pybind11 bindings crash on unexpected None values, so this must be
    called on any dict before passing it to PyOpenMagnetics functions.
    """
    if isinstance(obj, dict):
        return {k: strip_nulls(v) for k, v in obj.items() if v is not None}
    elif isinstance(obj, list):
        return [strip_nulls(v) for v in obj]
    return obj


def import_pyopenmagnetics():
    """Import and return PyOpenMagnetics module.

    Handles the dual-path import needed because the package structure
    changed between versions:
      - Newer: from PyOpenMagnetics import PyOpenMagnetics
      - Older: import PyOpenMagnetics

    Returns:
        The PyOpenMagnetics module object (usable as pm.some_function()).

    Raises:
        ImportError: If PyOpenMagnetics is not installed.
    """
    try:
        from PyOpenMagnetics import PyOpenMagnetics as pm
        return pm
    except ImportError:
        import PyOpenMagnetics as pm
        return pm
