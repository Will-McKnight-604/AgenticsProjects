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

    # 1) Direct name from OM DB
    if wire_name:
        try:
            wire = ensure_dict(pm.get_wire_data_by_name(wire_name))
            if is_valid_wire(wire):
                return wire
        except Exception:
            pass

    # 2) Try to resolve AWG style labels
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

    # 3) Dimension-based resolution (closest available)
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

    # 4) Final fallback
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


def generate_visualization(config):
    """Build magnetic from config and generate SVG."""

    core_shape_name = config['core_shape']
    material_name = config['material']
    gapping = config.get('gapping', [])
    windings = config.get('windings', [])
    plot_type = config.get('plot_type', 'magnetic')
    output_svg = config.get('output_svg', 'om_visualization.svg')

    # 1. Get shape and material as full dict objects
    shape = pm.find_core_shape_by_name(core_shape_name)
    material = pm.find_core_material_by_name(material_name)

    # 2. Build core functional description
    core_data = {
        'functionalDescription': {
            'name': 'gui_core',
            'type': 'two-piece set',
            'shape': shape,
            'material': material,
            'gapping': gapping if gapping else [],
            'numberStacks': 1
        }
    }

    # 3. Calculate full core data
    core_full = ensure_dict(pm.calculate_core_data(core_data, True))

    # 4. Create bobbin
    bobbin = ensure_dict(pm.create_basic_bobbin(core_full, False))

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
        is_default = section_order == list(range(len(coil_func)))
        tape_thickness = float(config.get('tape_thickness', 0.0) or 0.0)
        tape_layers = int(config.get('tape_layers', 0) or 0)
        insulation_thickness = tape_thickness * max(tape_layers, 0)
        use_sections = (section_order and not is_default) or (insulation_thickness > 0)

        if use_sections:
            if not section_order:
                section_order = list(range(len(coil_func)))
            total_turns = sum([w.get('num_turns', 0) * max(1, w.get('num_parallels', 1)) for w in windings]) or 1
            proportions = [(w.get('num_turns', 0) * max(1, w.get('num_parallels', 1)) / total_turns) for w in windings]
            coil_tmp = {
                'bobbin': bobbin,
                'functionalDescription': coil_func,
                'layersOrientation': 'overlapping',
                'turnsAlignment': 'centered'
            }
            margin_pairs = []
            if insulation_thickness > 0:
                margin_pad = insulation_thickness * 0.5
                margin_pairs = [[margin_pad, margin_pad]]

            coil_tmp = ensure_dict(pm.wind(coil_tmp, 1, proportions, section_order, margin_pairs))
            if isinstance(coil_tmp, str):
                raise RuntimeError(coil_tmp)
            if isinstance(coil_tmp, dict) and coil_tmp.get('errorMessage'):
                raise RuntimeError(coil_tmp.get('errorMessage'))
            if not coil_tmp.get('turnsDescription'):
                coil_tmp = ensure_dict(pm.wind_by_turns(coil_tmp))
            mag_complete['coil'] = coil_tmp
    except Exception as e:
        print(f'WARNING: Failed to generate turns: {e}', file=sys.stderr)

    # 8. Generate SVG
    if plot_type == 'core':
        result = pm.plot_core(mag_complete)
    elif plot_type == 'bobbin':
        result = pm.plot_bobbin(mag_complete)
    else:
        result = pm.plot_magnetic(mag_complete)

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
    if config.get('packing_pattern', '') == 'Orthocyclic':
        svg_content = apply_orthocyclic(svg_content)
    with open(output_svg, 'w') as f:
        f.write(svg_content)

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
