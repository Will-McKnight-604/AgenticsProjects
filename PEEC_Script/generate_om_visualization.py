#!/usr/bin/env python3
"""
Generate OpenMagnetics 2D cross-section SVG visualization.
Called from MATLAB/Octave via system() command.

Usage:
    python generate_om_visualization.py config.json

Config JSON format:
{
    "core_shape": "ETD 34/17/11",
    "material": "3C95",
    "gapping": [{"type": "subtractive", "length": 0.001}],
    "windings": [
        {"wire_name": "Round 0.5 - Grade 1", "num_turns": 10, "num_parallels": 1, "isolation_side": "primary"},
        {"wire_name": "Round 0.5 - Grade 1", "num_turns": 5, "num_parallels": 1, "isolation_side": "secondary"}
    ],
    "output_svg": "om_visualization.svg",
    "plot_type": "magnetic"
}

Requires: pip install PyMKF
"""

import json
import sys
import os
import re

try:
    import PyOpenMagnetics as pm
except ImportError as e:
    print(f"ImportError: {e}", file=sys.stderr)
    print(f"Python executable: {sys.executable}", file=sys.stderr)
    print(f"Python path: {sys.path}", file=sys.stderr)
    sys.exit(1)

def ensure_dict(obj):
    if isinstance(obj, str):
        try:
            return json.loads(obj)
        except Exception:
            return obj
    return obj


def is_exception_payload(obj):
    if isinstance(obj, str):
        return ('Exception:' in obj) or ('error' in obj.lower())
    if isinstance(obj, dict):
        for key in ('errorMessage', 'error'):
            val = obj.get(key)
            if isinstance(val, str) and val:
                return True
        data_val = obj.get('data')
        if isinstance(data_val, str) and 'Exception:' in data_val:
            return True
    return False


def raise_if_invalid(obj, label):
    obj = ensure_dict(obj)
    if is_exception_payload(obj):
        if isinstance(obj, dict):
            msg = obj.get('errorMessage') or obj.get('error') or obj.get('data')
        else:
            msg = str(obj)
        raise RuntimeError(f'{label} failed: {msg}')
    if not isinstance(obj, dict):
        raise RuntimeError(f'{label} failed: unexpected payload type {type(obj).__name__}')
    return obj


def make_valid_name(raw):
    if raw is None:
        raw = ''
    raw = str(raw)
    name = re.sub(r'[^a-zA-Z0-9_]', '_', raw)
    if not name:
        name = 'Unknown'
    if not name[0].isalpha():
        name = 'W_' + name
    return name


def _as_string_list(value):
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, (list, tuple)):
        out = []
        for v in value:
            if isinstance(v, str) and v:
                out.append(v)
        return out
    return []


def _dedupe_keep_order(items):
    seen = set()
    out = []
    for item in items:
        if not item:
            continue
        key = item.strip()
        if not key:
            continue
        key_l = key.lower()
        if key_l in seen:
            continue
        seen.add(key_l)
        out.append(key)
    return out


def _iter_available_shape_names():
    names = []
    try:
        raw = ensure_dict(pm.get_available_core_shapes())
        if isinstance(raw, list):
            for entry in raw:
                if isinstance(entry, str):
                    names.append(entry)
                elif isinstance(entry, dict):
                    if isinstance(entry.get('name'), str):
                        names.append(entry['name'])
                    fd = entry.get('functionalDescription', {})
                    if isinstance(fd, dict) and isinstance(fd.get('shape'), dict):
                        nm = fd['shape'].get('name')
                        if isinstance(nm, str):
                            names.append(nm)
        elif isinstance(raw, dict):
            for k, v in raw.items():
                if isinstance(k, str):
                    names.append(k)
                if isinstance(v, dict) and isinstance(v.get('name'), str):
                    names.append(v['name'])
    except Exception:
        return []
    return _dedupe_keep_order(names)


def resolve_core_shape(core_shape_name, aliases=None, core_shape_key=None):
    candidates = []
    candidates.extend(_as_string_list(core_shape_name))
    candidates.extend(_as_string_list(aliases))
    candidates.extend(_as_string_list(core_shape_key))

    # Helpful transformations for sanitized keys and alias variants.
    transformed = []
    for c in list(candidates):
        transformed.append(c.replace('_', ' '))
        transformed.append(c.replace('_', '/'))
        transformed.append(c.replace('_', '-'))
    candidates.extend(transformed)
    candidates = _dedupe_keep_order(candidates)

    for cand in candidates:
        try:
            shape = ensure_dict(pm.find_core_shape_by_name(cand))
            if not is_exception_payload(shape):
                return raise_if_invalid(shape, f'find_core_shape_by_name("{cand}")')
        except Exception:
            pass

    # Fallback: match by the same sanitizer used in MATLAB/OM API bridge.
    target_keys = set(make_valid_name(c) for c in candidates if c)
    avail_names = _iter_available_shape_names()
    for nm in avail_names:
        if make_valid_name(nm) in target_keys:
            shape = ensure_dict(pm.find_core_shape_by_name(nm))
            return raise_if_invalid(shape, f'find_core_shape_by_name("{nm}")')

    raise RuntimeError(f'Could not resolve core shape "{core_shape_name}" (aliases={aliases}, key={core_shape_key})')


def resolve_material(material_name):
    candidates = _dedupe_keep_order(_as_string_list(material_name))
    for cand in candidates:
        try:
            mat = ensure_dict(pm.find_core_material_by_name(cand))
            if not is_exception_payload(mat):
                return raise_if_invalid(mat, f'find_core_material_by_name("{cand}")')
        except Exception:
            pass
    raise RuntimeError(f'Could not resolve core material "{material_name}"')


def infer_core_type(shape_obj):
    family = str(shape_obj.get('family', '') or '').lower()
    if family in ('t', 'r', 'toroid', 'toroid'):
        return 'toroidal'
    if family in ('p', 'pot'):
        return 'closed shape'
    return 'two-piece set'


def is_valid_wire(wire_obj):
    if not isinstance(wire_obj, dict):
        return False
    if wire_obj.get('errorMessage'):
        return False
    return True


def guess_standard(std_text):
    s = str(std_text or '').lower()
    if 'nema' in s:
        return 'NEMA MW 1000 C'
    return 'IEC 60317'


def resolve_wire_data(winding_cfg):
    wire_name = str(winding_cfg.get('wire_name', '') or '')
    wire_std = guess_standard(winding_cfg.get('wire_standard', ''))
    wire_shape = str(winding_cfg.get('wire_shape', 'round') or 'round').lower()
    cond_w = float(winding_cfg.get('wire_cond_w', 0.0) or 0.0)
    cond_h = float(winding_cfg.get('wire_cond_h', 0.0) or 0.0)

    def build_custom_wire_from_dims():
        # Keep OM view dimensions aligned with GUI/Core Window Fit by honoring
        # explicit conductor dimensions sent by the MATLAB side.
        if cond_w <= 0 and cond_h <= 0:
            return None

        if 'rect' in wire_shape or 'foil' in wire_shape:
            w = cond_w if cond_w > 0 else cond_h
            h = cond_h if cond_h > 0 else cond_w
            if w <= 0 or h <= 0:
                return None
            return {
                'name': wire_name or f'Custom rectangular {w*1e3:.3f}x{h*1e3:.3f} mm',
                'type': 'rectangular',
                'material': 'copper',
                'standard': wire_std,
                'conductingWidth': {'nominal': w},
                'conductingHeight': {'nominal': h},
                'outerWidth': {'nominal': w},
                'outerHeight': {'nominal': h},
                'coating': {'type': 'enamelled', 'grade': 1}
            }

        d = max(cond_w, cond_h)
        if d <= 0:
            return None
        return {
            'name': wire_name or f'Custom round {d*1e3:.3f} mm',
            'type': 'round',
            'material': 'copper',
            'standard': wire_std,
            'conductingDiameter': {'nominal': d},
            'outerDiameter': {'nominal': d},
            'coating': {'type': 'enamelled', 'grade': 1}
        }

    # 1) Direct name from OM DB
    if wire_name:
        try:
            wire = ensure_dict(pm.get_wire_data_by_name(wire_name))
            if is_valid_wire(wire):
                return wire
        except Exception:
            pass

    # 2) Prefer explicit dimensions from GUI before heuristic lookups.
    #    This avoids wire size drift (e.g. AWG mapping mismatches) that can
    #    break turn placement and produce inconsistent spacing.
    custom_wire = build_custom_wire_from_dims()
    if custom_wire:
        return custom_wire

    # 3) Try to resolve AWG style labels
    if wire_name:
        awg_match = re.search(r'AWG[_\s-]*(\d+)', wire_name, flags=re.IGNORECASE)
        if awg_match:
            awg_num = awg_match.group(1)
            for awg_label in [f'AWG {awg_num}', f'{awg_num} AWG']:
                try:
                    wire = ensure_dict(pm.get_wire_data_by_standard_name(awg_label))
                    if is_valid_wire(wire):
                        return wire
                except Exception:
                    pass

    # 4) Dimension-based resolution (closest available)
    dim = 0.0
    if cond_w > 0 and cond_h > 0:
        dim = max(cond_w, cond_h)
    elif wire_name:
        m = re.search(r'(\d+(?:[_\.]\d+)?)', wire_name)
        if m:
            try:
                dim = float(m.group(1).replace('_', '.')) * 1e-3
            except Exception:
                dim = 0.0

    if dim > 0:
        type_candidates = ['round']
        if 'rect' in wire_shape or 'foil' in wire_shape:
            type_candidates = ['rectangular', 'round']

        std_candidates = [wire_std, 'IEC 60317', 'NEMA MW 1000 C']
        seen = set()
        for wt in type_candidates:
            for std in std_candidates:
                key = (wt, std)
                if key in seen:
                    continue
                seen.add(key)
                try:
                    wire = ensure_dict(pm.find_wire_by_dimension(dim, wt, std))
                    if is_valid_wire(wire):
                        return wire
                except Exception:
                    pass

    # 5) Final fallback
    return ensure_dict(pm.get_wire_data_by_name('Round 0.5 - Grade 1'))


def strip_elements_by_class(svg_content, class_names):
    if not class_names:
        return svg_content
    for cls in class_names:
        svg_content = re.sub(
            rf'<(rect|polygon|circle)[^>]*\bclass="{cls}"[^>]*/?>',
            '',
            svg_content
        )
        svg_content = re.sub(
            rf'\.{cls}\s*\{{[^}}]*\}}\s*',
            '',
            svg_content
        )
    return svg_content


def add_gap_overlays(svg_content, core_full, config):
    gapping = core_full.get('functionalDescription', {}).get('gapping', [])
    gap_type_hint = str(config.get('core_gap_type', '') or '')
    if gap_type_hint.lower() != 'spacer':
        return svg_content
    if not gapping:
        return svg_content

    vb_match = re.search(r'viewBox="([^"]+)"', svg_content)
    if not vb_match:
        return svg_content
    try:
        vb = [float(x) for x in vb_match.group(1).split()]
    except Exception:
        return svg_content
    if len(vb) != 4:
        return svg_content

    proc = core_full.get('processedDescription', {})
    width_m = proc.get('width', None)
    height_m = proc.get('height', None)
    if not width_m or not height_m:
        return svg_content

    svg_x, svg_y, svg_w, svg_h = vb
    scale_x = svg_w / width_m
    scale_y = svg_h / (2.0 * height_m)
    if scale_x <= 0 or scale_y <= 0:
        return svg_content

    cx = svg_x + svg_w / 2.0
    cy = svg_y + svg_h / 2.0

    num_gaps_hint = int(config.get('core_num_gaps', 1) or 1)
    gap_len_hint = config.get('core_gap_length', None)

    rects = []

    def add_rect(x_m, y_m, w_m, h_m, gap_type):
        if w_m <= 0 or h_m <= 0:
            return
        w_svg = w_m * scale_x
        h_svg = h_m * scale_y
        x_svg = cx + x_m * scale_x - w_svg / 2.0
        y_svg = cy + y_m * scale_y - h_svg / 2.0
        cls = 'gap_additive' if gap_type == 'additive' else 'gap_subtractive'
        rects.append(
            f'<rect class="{cls}" x="{x_svg:.3f}" y="{y_svg:.3f}" '
            f'width="{w_svg:.3f}" height="{h_svg:.3f}" />'
        )

    # Spacer: only show additive gaps
    for gap in gapping:
        gap_type = gap.get('type', '')
        if gap_type != 'additive':
            continue
        length = gap.get('length', None)
        coords = gap.get('coordinates', None)
        dims = gap.get('sectionDimensions', None)
        if length is None or not coords or not dims:
            continue
        try:
            x_m = float(coords[0])
            y_m = float(coords[1])
            w_m = float(dims[0])
            h_m = float(length)
        except Exception:
            continue
        add_rect(x_m, y_m, w_m, h_m, gap_type)

    if not rects:
        return svg_content

    if 'gap_subtractive' not in svg_content:
        style_inset = (
            ".gap_subtractive { fill: #ffffff; opacity: 0.35; stroke: #d0b45a; stroke-width: 0.8; }\n"
            "\t\t\t.gap_additive { fill: #3b3b3b; opacity: 0.60; stroke: #1a1a1a; stroke-width: 0.6; }\n"
        )
        if ']]>' in svg_content:
            svg_content = svg_content.replace(']]>', style_inset + ']]>', 1)
        elif '</style>' in svg_content:
            svg_content = svg_content.replace('</style>', style_inset + '</style>', 1)
        else:
            svg_content = re.sub(
                r'(<svg[^>]*>)',
                r'\\1\\n\\t<style type="text/css"><![CDATA[' + style_inset + ']]></style>',
                svg_content,
                count=1
            )

    gap_group = '<g class="gap_overlays">\\n\\t' + '\\n\\t'.join(rects) + '\\n</g>\\n'
    if '</svg>' in svg_content:
        svg_content = svg_content.replace('</svg>', gap_group + '</svg>', 1)
    else:
        svg_content += gap_group

    return svg_content


def parse_section_order(order_str, n_windings):
    if not order_str:
        return []
    s = str(order_str)
    if n_windings <= 9 and re.fullmatch(r'[0-9]+', s):
        tokens = list(s)
    else:
        tokens = re.findall(r'\d+', s)
    order = []
    for tok in tokens:
        try:
            v = int(tok)
        except Exception:
            continue
        if 1 <= v <= n_windings:
            order.append(v - 1)  # zero-based for PyOpenMagnetics
    return order


def compute_turns_width(turns):
    if not turns:
        return 0.0
    xs = []
    for t in turns:
        try:
            x = float(t['coordinates'][0])
            r = float(t['dimensions'][0]) / 2.0
        except Exception:
            continue
        xs.append(x - r)
        xs.append(x + r)
    if not xs:
        return 0.0
    return max(xs) - min(xs)


def compute_turns_bounds(turns):
    if not turns:
        return None
    xs = []
    for t in turns:
        try:
            x = float(t['coordinates'][0])
            r = float(t['dimensions'][0]) / 2.0
        except Exception:
            continue
        xs.append(x - r)
        xs.append(x + r)
    if not xs:
        return None
    return (min(xs), max(xs))


def scale_turns_to_width(coil, target_width):
    if target_width <= 0:
        return coil
    turns = coil.get('turnsDescription', [])
    bounds = compute_turns_bounds(turns)
    if not bounds:
        return coil
    x_min, x_max = bounds
    current_width = x_max - x_min
    if current_width <= 0:
        return coil

    scale = target_width / current_width
    center = 0.5 * (x_min + x_max)

    for t in turns:
        try:
            x = float(t['coordinates'][0])
            t['coordinates'][0] = center + (x - center) * scale
        except Exception:
            pass

    coil['turnsDescription'] = turns
    return coil


def apply_orthocyclic(svg_content):
    circ_re = re.compile(r'<circle([^>]*?)cx="([^"]+)"([^>]*?)cy="([^"]+)"([^>]*?)r="([^"]+)"([^>]*)>')
    circles = []
    for m in circ_re.finditer(svg_content):
        try:
            cx = float(m.group(2))
            cy = float(m.group(4))
            r = float(m.group(6))
        except Exception:
            continue
        circles.append((cy, cx, r))
    if not circles:
        return svg_content

    # Use copper circles as row reference when available
    row_keys = []
    for m in re.finditer(r'<circle[^>]*class="copper"[^>]*cx="([^"]+)"[^>]*cy="([^"]+)"[^>]*r="([^"]+)"', svg_content):
        try:
            cy = float(m.group(2))
            r = float(m.group(3))
        except Exception:
            continue
        row_keys.append((cy, r))
    if not row_keys:
        row_keys = [(c[0], c[2]) for c in circles]

    # Cluster rows by rounded y
    rows = {}
    for cy, r in row_keys:
        key = round(cy, 3)
        if key not in rows:
            rows[key] = []
        rows[key].append(r)
    row_list = sorted(rows.keys())
    if not row_list:
        return svg_content
    if len(row_list) < 2:
        return svg_content

    # Assign row index
    row_index = {k: i for i, k in enumerate(row_list)}
    row_shift = {}
    diffs = [abs(row_list[i + 1] - row_list[i]) for i in range(len(row_list) - 1)]
    row_pitch = sorted(diffs)[len(diffs) // 2] if diffs else 0.0
    for k, rs in rows.items():
        r_mean = sum(rs) / len(rs) if rs else 0.0
        base_shift = r_mean if r_mean > 0 else (row_pitch * 0.5 if row_pitch > 0 else 0.0)
        if base_shift <= 0:
            shift = 0.0
        else:
            shift = base_shift * 0.5
            if row_index[k] % 2 == 0:
                shift = -shift
        row_shift[k] = shift

    def replace_circle(match):
        attrs1 = match.group(1)
        cx = float(match.group(2))
        attrs2 = match.group(3)
        cy = float(match.group(4))
        attrs3 = match.group(5)
        r = match.group(6)
        attrs4 = match.group(7)
        key = round(cy, 3)
        shift = row_shift.get(key, 0.0)
        new_cx = cx + shift
        return f'<circle{attrs1}cx="{new_cx:.3f}"{attrs2}cy="{cy:.3f}"{attrs3}r="{r}"{attrs4}>'

    return circ_re.sub(replace_circle, svg_content)


def apply_section_spacing(coil, insulation_thickness):
    try:
        sections = coil.get('sectionsDescription', [])
        turns = coil.get('turnsDescription', [])
    except Exception:
        return coil
    if not sections or not turns or insulation_thickness <= 0:
        return coil

    # Build ordered section list by x-position
    ordered = []
    for s in sections:
        try:
            name = s.get('name', '')
            cx = float(s.get('coordinates', [0])[0])
            w = float(s.get('dimensions', [0])[0])
        except Exception:
            continue
        left = cx - w / 2.0
        ordered.append((left, name))
    if not ordered:
        return coil
    ordered.sort(key=lambda x: x[0])

    shift_map = {}
    for idx, (_, name) in enumerate(ordered):
        if not name:
            continue
        shift_map[name] = idx * insulation_thickness

    # Shift sections
    for s in sections:
        name = s.get('name', '')
        if name in shift_map:
            try:
                s['coordinates'][0] = float(s['coordinates'][0]) + shift_map[name]
            except Exception:
                pass

    # Shift layers if present
    for layer in coil.get('layersDescription', []) or []:
        sec = layer.get('section', '')
        if sec in shift_map:
            try:
                layer['coordinates'][0] = float(layer['coordinates'][0]) + shift_map[sec]
            except Exception:
                pass

    # Shift turns
    for t in turns:
        sec = t.get('section', '')
        if sec in shift_map:
            try:
                t['coordinates'][0] = float(t['coordinates'][0]) + shift_map[sec]
            except Exception:
                pass

    coil['sectionsDescription'] = sections
    coil['turnsDescription'] = turns
    return coil


def get_bobbin_window_dims(bobbin):
    try:
        proc = bobbin.get('processedDescription', {})
        windows = proc.get('windingWindows', [])
        if windows:
            ww = windows[0]
            w = float(ww.get('width', 0.0) or 0.0)
            h = float(ww.get('height', 0.0) or 0.0)
            return w, h
    except Exception:
        pass
    return 0.0, 0.0


def parse_svg_viewbox(svg_content):
    m = re.search(r'viewBox="([^"]+)"', svg_content or '')
    if not m:
        return None
    try:
        parts = [float(x) for x in m.group(1).split()]
        if len(parts) != 4:
            return None
        return parts
    except Exception:
        return None


def build_magnetic_from_config(config):
    """Build full OpenMagnetics magnetic object from GUI config."""

    core_shape_name = config['core_shape']
    core_shape_key = config.get('core_shape_key', '')
    core_shape_aliases = config.get('core_shape_aliases', [])
    material_name = config['material']
    gapping = config.get('gapping', [])
    windings = config.get('windings', [])

    # OM-native winding layout parameters (from GUI winding options dialog)
    # Fall back to legacy packing_pattern if new fields are missing
    layers_orientation = str(config.get('winding_orientation', '') or '').strip()
    section_alignment = str(config.get('section_alignment', '') or '').strip()

    if not layers_orientation or not section_alignment:
        # Legacy fallback: map old packing_pattern to OM-native values
        packing_pattern = str(config.get('packing_pattern', 'Layered') or 'Layered')
        packing_key = packing_pattern.strip().lower()
        if packing_key == 'orthocyclic':
            layers_orientation = layers_orientation or 'overlapping'
            section_alignment = section_alignment or 'inner or top'
        elif packing_key == 'random':
            layers_orientation = layers_orientation or 'overlapping'
            section_alignment = section_alignment or 'centered'
        else:
            layers_orientation = layers_orientation or 'contiguous'
            section_alignment = section_alignment or 'inner or top'

    # Map OM web-style alignment names to API-compatible keys
    alignment_map = {
        'inner or top': 'inner or top',
        'inner_or_top': 'inner or top',
        'outer or bottom': 'outer or bottom',
        'outer_or_bottom': 'outer or bottom',
        'centered': 'centered',
        'spread': 'spread',
    }
    section_alignment = alignment_map.get(section_alignment, section_alignment)

    # Per-winding turns alignment (list, one per winding)
    turns_alignment_per_winding = config.get('turns_alignment_per_winding', [])
    if not turns_alignment_per_winding:
        turns_alignment_per_winding = ['spread'] * len(windings)

    # Per-winding proportions (list of floats summing to ~1.0)
    proportions_per_winding = config.get('proportions_per_winding', [])
    if not proportions_per_winding:
        n_w = len(windings) or 1
        proportions_per_winding = [1.0 / n_w] * n_w

    # Use the first winding's turns alignment as the global default for the coil
    turns_alignment = alignment_map.get(
        str(turns_alignment_per_winding[0] if turns_alignment_per_winding else 'spread'),
        'spread'
    )

    wind_meta = {
        'layers_orientation': layers_orientation,
        'section_alignment': section_alignment,
        'turns_alignment': turns_alignment,
        'turns_alignment_per_winding': turns_alignment_per_winding,
        'proportions_per_winding': proportions_per_winding,
        'used_api_wind': False,
        'api_wind_success': False,
        'winding_mode': 'wind_by_turns',
        'wind_error': ''
    }

    # 1. Resolve shape and material as full dict objects
    shape = resolve_core_shape(core_shape_name, core_shape_aliases, core_shape_key)
    material = resolve_material(material_name)

    # 2. Build core functional description
    core_type = infer_core_type(shape)
    gapping_use = gapping if isinstance(gapping, list) else []
    if core_type == 'toroidal':
        # Toroids cannot be gapped in OM core model.
        if gapping_use:
            gapping_use = []
        # PyOpenMagnetics requires overlapping layers for toroids.
        if layers_orientation != 'overlapping':
            print(f'NOTE: Forcing overlapping orientation for toroidal core '
                  f'(was: {layers_orientation!r})', file=sys.stderr)
            layers_orientation = 'overlapping'

    core_data = {
        'functionalDescription': {
            'name': 'gui_core',
            'type': core_type,
            'shape': shape,
            'material': material,
            'gapping': gapping_use,
            'numberStacks': 1
        }
    }

    # 3. Calculate full core data
    core_full = raise_if_invalid(pm.calculate_core_data(core_data, True), 'calculate_core_data')

    # 4. Create bobbin
    bobbin = raise_if_invalid(pm.create_basic_bobbin(core_full, False), 'create_basic_bobbin')

    # 5. Build coil functional description
    coil_func = []
    for i, w in enumerate(windings):
        wire = resolve_wire_data(w)
        winding_entry = {
            'name': w.get('name', f'winding_{i}'),
            'numberTurns': w.get('num_turns', 10),
            'numberParallels': w.get('num_parallels', 1),
            'wire': wire,
            'isolationSide': w.get('isolation_side', 'primary')
        }
        coil_func.append(winding_entry)

    # 6. Assemble magnetic
    magnetic = {
        'core': core_full,
        'coil': {
            'bobbin': bobbin,
            'functionalDescription': coil_func
        }
    }

    # 7. Autocomplete to fill in sections/layers (turns may still be missing)
    mag_complete = ensure_dict(pm.magnetic_autocomplete(magnetic, {}))
    try:
        coil = mag_complete.get('coil', {})
        if coil.get('turnsDescription') is None:
            coil = ensure_dict(pm.wind_by_turns(coil))
        mag_complete['coil'] = coil

        section_order = parse_section_order(config.get('section_order', ''), len(coil_func))
        tape_thickness = float(config.get('tape_thickness', 0.0) or 0.0)
        tape_layers = int(config.get('tape_layers', 0) or 0)
        insulation_thickness = tape_thickness * max(tape_layers, 0)

        # Always use API wind with explicit OM-native parameters
        wind_meta['used_api_wind'] = True

        if True:
            if not section_order:
                section_order = list(range(len(coil_func)))

            # Use per-winding proportions from GUI (already normalized to sum ~1.0)
            proportions = list(proportions_per_winding)
            if len(proportions) != len(coil_func):
                # Fallback: compute from turns if proportions don't match winding count
                total_turns = sum([w.get('num_turns', 0) * max(1, w.get('num_parallels', 1)) for w in windings]) or 1
                proportions = [(w.get('num_turns', 0) * max(1, w.get('num_parallels', 1)) / total_turns) for w in windings]

            # For interleaving patterns (e.g. 121), a winding can appear multiple
            # times. Compensate the per-winding proportion by the number of
            # occurrences, otherwise repeated windings over-expand their section
            # allocation in orthocyclic/contiguous placement.
            if section_order:
                counts = [max(1, section_order.count(i)) for i in range(len(proportions))]
                proportions = [proportions[i] / counts[i] for i in range(len(proportions))]

            # Build per-section turnsAlignment array from per-winding values.
            # section_order maps sections to winding indices, so expand
            # turns_alignment_per_winding through section_order.
            per_section_turns_alignment = []
            for sec_idx in section_order:
                if sec_idx < len(turns_alignment_per_winding):
                    ta = alignment_map.get(
                        str(turns_alignment_per_winding[sec_idx]),
                        turns_alignment_per_winding[sec_idx]
                    )
                    per_section_turns_alignment.append(ta)
                else:
                    per_section_turns_alignment.append(turns_alignment)

            base_coil = {
                'bobbin': bobbin,
                'functionalDescription': coil_func,
                'layersOrientation': layers_orientation,
                'sectionAlignment': section_alignment,
                'turnsAlignment': turns_alignment
            }

            # Use three-step winding: wind_by_sections → wind_by_layers → wind_by_turns
            # This ensures sectionAlignment is applied (pm.wind() ignores it).
            insul_thick_val = insulation_thickness if insulation_thickness > 0 else 0.0

            def sections_once(insul):
                out = ensure_dict(pm.wind_by_sections(
                    base_coil, 1, proportions, section_order, insul
                ))
                if isinstance(out, str):
                    raise RuntimeError(out)
                if isinstance(out, dict) and out.get('errorMessage'):
                    raise RuntimeError(out.get('errorMessage'))
                return out

            try:
                coil_tmp = sections_once(insul_thick_val)
            except Exception:
                if insul_thick_val > 0:
                    coil_tmp = sections_once(0.0)
                else:
                    raise

            # Apply per-section turnsAlignment before wind_by_layers
            # The coil now has sectionsDescription — set turnsAlignment as array
            if per_section_turns_alignment:
                coil_tmp['turnsAlignment'] = per_section_turns_alignment
            coil_tmp['layersOrientation'] = layers_orientation
            coil_tmp['sectionAlignment'] = section_alignment

            try:
                coil_tmp = ensure_dict(pm.wind_by_layers(coil_tmp, {}, 0.0))
                if isinstance(coil_tmp, str):
                    raise RuntimeError(coil_tmp)
            except Exception as e:
                print(f'NOTE: wind_by_layers failed ({e}), '
                      f'falling back to pm.wind()', file=sys.stderr)
                # Fallback to pm.wind() which does all steps internally
                coil_tmp = ensure_dict(pm.wind(
                    base_coil, 1, proportions, section_order, []
                ))
                if isinstance(coil_tmp, str):
                    raise RuntimeError(coil_tmp)

            if not coil_tmp.get('turnsDescription'):
                coil_tmp['turnsAlignment'] = per_section_turns_alignment or turns_alignment
                coil_tmp['layersOrientation'] = layers_orientation
                coil_tmp['sectionAlignment'] = section_alignment
                coil_tmp = ensure_dict(pm.wind_by_turns(coil_tmp))
            mag_complete['coil'] = coil_tmp
            wind_meta['api_wind_success'] = True
            wind_meta['winding_mode'] = 'api_wind'
    except Exception as e:
        wind_meta['wind_error'] = str(e)
        wind_meta['winding_mode'] = 'fallback_magnetic_autocomplete'
        print(f'WARNING: Failed to generate turns: {e}', file=sys.stderr)

    return mag_complete, wind_meta, core_full, bobbin


def generate_visualization(config):
    """Build magnetic from config and generate SVG."""

    core_shape_name = config['core_shape']
    material_name = config['material']
    windings = config.get('windings', [])
    plot_type = config.get('plot_type', 'magnetic')
    output_svg = config.get('output_svg', 'om_visualization.svg')
    output_meta = config.get('output_meta', '')

    # Build magnetic using the shared builder so analysis pre-screen and
    # visualization always use the same winding generation path.
    mag_complete, wind_meta, core_full, bobbin = build_magnetic_from_config(config)

    # 8. Generate SVG
    if plot_type == 'core':
        result = pm.plot_core(mag_complete)
    elif plot_type == 'bobbin':
        result = pm.plot_bobbin(mag_complete)
    else:
        result = pm.plot_magnetic(mag_complete)
        # If winding failed, plot_magnetic will fail with COIL_NOT_PROCESSED.
        # Fall back to plot_bobbin so the user still sees the core outline.
        if not result.get('success', False) and wind_meta.get('wind_error'):
            print(f'WARNING: plot_magnetic failed after winding error, '
                  f'falling back to plot_bobbin', file=sys.stderr)
            result = pm.plot_bobbin(mag_complete)

    if not result.get('success', False):
        error_msg = result.get('error', 'Unknown error')
        print(f'ERROR: {error_msg}', file=sys.stderr)
        return False

    # 9. Write SVG to file
    svg_content = result['svg']
    svg_content = add_gap_overlays(svg_content, core_full, config)
    gap_type_hint = str(config.get('core_gap_type', '') or '')
    if gap_type_hint.lower() != 'spacer':
        svg_content = strip_elements_by_class(svg_content, ['spacer', 'gap_additive'])
    with open(output_svg, 'w') as f:
        f.write(svg_content)

    if output_meta:
        core_proc = core_full.get('processedDescription', {}) if isinstance(core_full, dict) else {}
        core_width_m = float(core_proc.get('width', 0.0) or 0.0)
        core_half_height_m = float(core_proc.get('height', 0.0) or 0.0)
        bobbin_w_m, bobbin_h_m = get_bobbin_window_dims(bobbin)
        vb = parse_svg_viewbox(svg_content)
        turns_meta = []
        try:
            turns = mag_complete.get('coil', {}).get('turnsDescription', []) or []
            for t in turns:
                coords = t.get('coordinates', [0, 0, 0]) or [0, 0, 0]
                dims = t.get('dimensions', [0, 0]) or [0, 0]
                try:
                    x_m = float(coords[0]) if len(coords) > 0 else 0.0
                    y_m = float(coords[1]) if len(coords) > 1 else 0.0
                    w_m = float(dims[0]) if len(dims) > 0 else 0.0
                    h_m = float(dims[1]) if len(dims) > 1 else w_m
                    if h_m <= 0:
                        h_m = w_m
                    r_m = 0.5 * max(0.0, min(w_m, h_m))
                except Exception:
                    continue
                turns_meta.append({
                    'winding': str(t.get('winding', '')),
                    'x_m': x_m,
                    'y_m': y_m,
                    'r_m': r_m,
                    'width_m': w_m,
                    'height_m': h_m,
                    'shape': str(t.get('crossSectionalShape', '')),
                    'section': str(t.get('section', '')),
                    'layer': str(t.get('layer', '')),
                    'name': str(t.get('name', ''))
                })
        except Exception:
            turns_meta = []
        meta = {
            'core_shape': core_shape_name,
            'material': material_name,
            'plot_type': plot_type,
            'viewbox': vb,
            'core_width_m': core_width_m,
            'core_half_height_m': core_half_height_m,
            'core_total_height_m': 2.0 * core_half_height_m,
            'bobbin_window_width_m': bobbin_w_m,
            'bobbin_window_height_m': bobbin_h_m,
            'bobbin_window_area_m2': bobbin_w_m * bobbin_h_m,
            'windings': len(windings),
            'winding_names': [w.get('name', f'winding_{i}') for i, w in enumerate(windings)],
            'section_order': str(config.get('section_order', '') or ''),
            'turns': turns_meta,
            'winding': wind_meta
        }
        try:
            with open(output_meta, 'w') as f:
                json.dump(meta, f)
        except Exception as e:
            print(f'WARNING: Failed to write meta file: {e}', file=sys.stderr)

    print('OK')
    return True


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: python generate_om_visualization.py config.json', file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]
    if not os.path.exists(config_path):
        print(f'ERROR: Config file not found: {config_path}', file=sys.stderr)
        sys.exit(1)

    with open(config_path, 'r') as f:
        config = json.load(f)

    success = generate_visualization(config)
    sys.exit(0 if success else 1)
