function comparison = compare_mas_case(case_result_input, reference_input, out_file)
%COMPARE_MAS_CASE Compare one solver result against MAS reference metrics.
%
% Reference schema fields:
%   case_id, source_solver, frequency_hz, total_copper_loss_w, winding_losses_w,
%   L_self_h, Lm_h, Llk_pri_h, Llk_sec_h

    if nargin < 2 || isempty(reference_input)
        here = fileparts(mfilename('fullpath'));
        reference_input = fullfile(here, 'references', 'external_solver_references.json');
    end
    if nargin < 3
        out_file = '';
    end

    case_result = load_json_or_struct(case_result_input);
    references = load_json_or_struct(reference_input);
    ref_entry = pick_reference_entry(references, case_result);
    if isempty(ref_entry)
        error('compare_mas_case: no matching reference for case_id "%s"', ...
            get_struct_string(case_result, 'case_id', 'unknown'));
    end

    comparison = struct();
    comparison.case_id = get_struct_string(case_result, 'case_id', 'unknown');
    comparison.source_solver = get_struct_string(case_result, 'source_solver', 'candidate');
    comparison.reference_solver = get_struct_string(ref_entry, 'source_solver', 'reference');
    comparison.frequency_hz = get_struct_numeric(case_result, 'frequency_hz', NaN);
    comparison.metrics = struct();
    comparison.metrics.total_copper_loss_w = compare_scalar(case_result, ref_entry, 'total_copper_loss_w');
    comparison.metrics.Lm_h = compare_scalar(case_result, ref_entry, 'Lm_h');
    comparison.metrics.Llk_pri_h = compare_scalar(case_result, ref_entry, 'Llk_pri_h');
    comparison.metrics.Llk_sec_h = compare_scalar(case_result, ref_entry, 'Llk_sec_h');
    comparison.metrics.L_self_h = compare_vector(case_result, ref_entry, 'L_self_h');
    comparison.metrics.winding_losses_w = compare_vector(case_result, ref_entry, 'winding_losses_w');

    if ~isempty(out_file)
        write_json(comparison, out_file);
    end
end

function metric = compare_scalar(candidate, ref_entry, field_name)
    cand = get_struct_numeric(candidate, field_name, NaN);
    ref = get_struct_numeric(ref_entry, field_name, NaN);
    metric = struct();
    metric.candidate = cand;
    metric.reference = ref;
    metric.delta = cand - ref;
    metric.rel = relative_error(cand, ref);
end

function metric = compare_vector(candidate, ref_entry, field_name)
    cand = get_numeric_vector(candidate, field_name);
    ref = get_numeric_vector(ref_entry, field_name);
    n = max(numel(cand), numel(ref));
    c = NaN(1, n);
    r = NaN(1, n);
    c(1:numel(cand)) = cand;
    r(1:numel(ref)) = ref;
    delta = c - r;
    rel = NaN(1, n);
    for i = 1:n
        rel(i) = relative_error(c(i), r(i));
    end
    metric = struct();
    metric.candidate = c;
    metric.reference = r;
    metric.delta = delta;
    metric.rel = rel;
    metric.rel_l2 = relative_l2(c, r);
end

function ref_entry = pick_reference_entry(references, case_result)
    ref_entry = [];
    case_id = get_struct_string(case_result, 'case_id', '');
    f_hz = get_struct_numeric(case_result, 'frequency_hz', NaN);

    entries = references;
    if isstruct(references) && isfield(references, 'references')
        entries = references.references;
    end
    if iscell(entries)
        try
            entries = [entries{:}];
        catch
            entries = struct([]);
        end
    end
    if ~isstruct(entries) || isempty(entries)
        return;
    end

    for i = 1:numel(entries)
        id_i = get_struct_string(entries(i), 'case_id', '');
        f_i = get_struct_numeric(entries(i), 'frequency_hz', NaN);
        if strcmp(id_i, case_id)
            if ~isfinite(f_hz) || ~isfinite(f_i) || abs(f_i - f_hz) <= max(1.0, 1e-6 * f_hz)
                ref_entry = entries(i);
                return;
            end
        end
    end
end

function obj = load_json_or_struct(input_obj)
    if isstruct(input_obj)
        obj = input_obj;
        return;
    end
    if ~is_text_like(input_obj)
        error('compare_mas_case: expected struct or JSON file path');
    end
    f = char(input_obj);
    if ~exist(f, 'file')
        error('compare_mas_case: file not found: %s', f);
    end
    fid = fopen(f, 'r');
    if fid == -1
        error('compare_mas_case: cannot read file: %s', f);
    end
    raw = fread(fid, '*char')';
    fclose(fid);
    raw = sanitize_json_text(raw);
    obj = jsondecode(raw);
end

function v = get_numeric_vector(s, field_name)
    v = [];
    if ~isstruct(s) || ~isfield(s, field_name)
        return;
    end
    x = s.(field_name);
    if isnumeric(x)
        v = double(x(:)');
    elseif iscell(x)
        tmp = zeros(1, numel(x));
        ok = true;
        for i = 1:numel(x)
            if isnumeric(x{i}) && isscalar(x{i}) && isfinite(x{i})
                tmp(i) = double(x{i});
            else
                ok = false;
                break;
            end
        end
        if ok
            v = tmp;
        end
    end
end

function e = relative_error(v, ref)
    e = NaN;
    if ~isfinite(v) || ~isfinite(ref)
        return;
    end
    e = abs(v - ref) / max(abs(ref), 1e-12);
end

function e = relative_l2(v, ref)
    e = NaN;
    mask = isfinite(v) & isfinite(ref);
    if ~any(mask)
        return;
    end
    dv = v(mask) - ref(mask);
    rn = norm(ref(mask), 2);
    if rn <= 0
        rn = 1e-12;
    end
    e = norm(dv, 2) / rn;
end

function out = get_struct_numeric(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if isnumeric(v) && isscalar(v) && isfinite(v)
            out = double(v);
        end
    end
end

function out = get_struct_string(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if is_text_like(v)
            out = char(v);
        end
    end
end

function tf = is_text_like(v)
    tf = ischar(v);
    if tf
        return;
    end
    if exist('isstring', 'builtin') || exist('isstring', 'file')
        tf = isstring(v);
    else
        tf = false;
    end
end

function write_json(payload, out_file)
    fid = fopen(out_file, 'w');
    if fid == -1
        error('compare_mas_case: cannot write file: %s', out_file);
    end
    fwrite(fid, jsonencode(payload));
    fclose(fid);
end

function txt = sanitize_json_text(txt)
    if isempty(txt)
        return;
    end
    if double(txt(1)) == 65279
        txt = txt(2:end);
    end
    txt = strtrim(txt);
end
