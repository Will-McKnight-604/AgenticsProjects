function report = extract_case_features(case_dir, options)
%EXTRACT_CASE_FEATURES Build lightweight feature vectors for MAS case files.
%
% Example:
%   rep = extract_case_features();
%   rep = extract_case_features([], struct('max_cases', 12));

    ensure_local_paths();

    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(case_dir)
        case_dir = fullfile(here, 'mas_cases_real');
    end
    if nargin < 2 || ~isstruct(options)
        options = struct();
    end
    options = normalize_options(options);

    if ~exist(case_dir, 'dir')
        error('extract_case_features: case directory not found: %s', case_dir);
    end

    files = dir(fullfile(case_dir, '*.json'));
    names = sort({files.name});
    names = select_case_names(names, options);
    if isempty(names)
        error('extract_case_features: no case files selected from %s', case_dir);
    end

    feats = repmat(empty_feature_row(), numel(names), 1);
    for i = 1:numel(names)
        case_path = fullfile(case_dir, names{i});
        case_obj = load_json(case_path);
        feats(i) = extract_case_feature_row(case_obj, names{i}, case_path);
    end

    report = struct();
    report.generated_at = datestr(now, 30);
    report.case_dir = case_dir;
    report.case_count = numel(feats);
    report.features = feats;
    report.summary = summarize_features(feats);

    if options.save_results
        if ~exist(options.results_dir, 'dir')
            mkdir(options.results_dir);
        end
        out_latest = fullfile(options.results_dir, 'case_features_latest.json');
        out_stamp = fullfile(options.results_dir, sprintf('case_features_%s.json', report.generated_at));
        write_json(report, out_latest);
        write_json(report, out_stamp);
    end
end

function options = normalize_options(options)
    def = struct();
    def.case_indices = [];
    def.case_ids = {};
    def.max_cases = inf;
    def.save_results = true;
    def.results_dir = fullfile(fileparts(mfilename('fullpath')), 'results_hyperband');

    f = fieldnames(def);
    for i = 1:numel(f)
        if ~isfield(options, f{i})
            options.(f{i}) = def.(f{i});
        end
    end

    if ~iscell(options.case_ids)
        if is_text_like(options.case_ids)
            options.case_ids = {char(options.case_ids)};
        else
            options.case_ids = {};
        end
    end
    if ~isnumeric(options.case_indices)
        options.case_indices = [];
    end
    if ~isnumeric(options.max_cases) || ~isscalar(options.max_cases) || ~isfinite(options.max_cases) || options.max_cases <= 0
        options.max_cases = inf;
    end
    options.save_results = to_logical(options.save_results, true);
end

function selected = select_case_names(names, options)
    selected = names;
    if ~isempty(options.case_indices)
        idx = unique(max(1, min(numel(names), round(options.case_indices(:)'))));
        selected = names(idx);
    end
    if ~isempty(options.case_ids)
        wanted = cell(1, numel(options.case_ids));
        for i = 1:numel(options.case_ids)
            wanted{i} = lower(strip_json_suffix(char(options.case_ids{i})));
        end
        keep = false(1, numel(selected));
        for i = 1:numel(selected)
            keep(i) = any(strcmp(lower(strip_json_suffix(selected{i})), wanted));
        end
        selected = selected(keep);
    end
    if isfinite(options.max_cases)
        selected = selected(1:min(numel(selected), floor(options.max_cases)));
    end
end

function row = extract_case_feature_row(case_obj, file_name, case_path)
    row = empty_feature_row();
    row.case_file = file_name;
    row.case_path = case_path;
    row.case_id = get_nested_string(case_obj, {'meta', 'case_id'}, strip_json_suffix(file_name));

    bench = get_nested_struct(case_obj, {'benchmark'}, struct());
    Nx = max(1, round(get_nested_numeric(bench, {'mesh', 'Nx'}, 1)));
    Ny = max(1, round(get_nested_numeric(bench, {'mesh', 'Ny'}, 1)));
    f_hz = max(1, get_nested_numeric(bench, {'frequency_hz'}, 100e3));

    geom = get_nested_struct(bench, {'geometry'}, struct());
    windings = get_struct_field(geom, 'windings', struct([]));
    if iscell(windings)
        try
            windings = [windings{:}];
        catch
            windings = struct([]);
        end
    end

    winding_count = numel(windings);
    turns_total = 0;
    cond_est = 0;
    filar_total = 0;
    mixed_shapes = false;
    shape_ref = '';
    for w = 1:winding_count
        t = max(1, round(get_struct_numeric(windings(w), 'turns', 1)));
        nf = max(1, round(get_struct_numeric(windings(w), 'n_filar', 1)));
        turns_total = turns_total + t;
        filar_total = filar_total + nf;
        cond_est = cond_est + t * nf;

        wire = get_struct_field(windings(w), 'wire', struct());
        s = lower(strtrim(get_struct_string(wire, 'shape', get_struct_string(wire, 'kind', 'round'))));
        if isempty(shape_ref)
            shape_ref = s;
        elseif ~strcmp(shape_ref, s)
            mixed_shapes = true;
        end
    end

    mesh_cells_est = cond_est * Nx * Ny;
    complexity_score = mesh_cells_est * log10(max(f_hz, 10));

    row.frequency_hz = f_hz;
    row.mesh_Nx = Nx;
    row.mesh_Ny = Ny;
    row.mesh_cells_per_conductor = Nx * Ny;
    row.winding_count = winding_count;
    row.turns_total = turns_total;
    row.n_filar_total = filar_total;
    row.conductors_est = cond_est;
    row.mesh_cells_est = mesh_cells_est;
    row.mixed_wire_shapes = mixed_shapes;
    row.complexity_score = complexity_score;
    row.fft_eligible_hint = estimate_fft_eligibility_hint(row);
end

function tf = estimate_fft_eligibility_hint(row)
    tf = false;
    if row.mesh_Nx < 2 || row.mesh_Ny < 2
        return;
    end
    if row.mixed_wire_shapes
        return;
    end
    if row.conductors_est < 200
        return;
    end
    tf = true;
end

function s = summarize_features(feats)
    s = struct();
    if isempty(feats)
        s.note = 'No feature rows';
        return;
    end
    mesh_cells = [feats.mesh_cells_est];
    complexity = [feats.complexity_score];
    freqs = [feats.frequency_hz];
    fft_hint = [feats.fft_eligible_hint];

    s.case_count = numel(feats);
    s.mesh_cells_est_median = median(mesh_cells);
    s.mesh_cells_est_max = max(mesh_cells);
    s.complexity_score_median = median(complexity);
    s.complexity_score_max = max(complexity);
    s.frequency_hz_min = min(freqs);
    s.frequency_hz_max = max(freqs);
    s.fft_eligible_hint_fraction = mean(double(fft_hint));
end

function row = empty_feature_row()
    row = struct();
    row.case_id = '';
    row.case_file = '';
    row.case_path = '';
    row.frequency_hz = NaN;
    row.mesh_Nx = NaN;
    row.mesh_Ny = NaN;
    row.mesh_cells_per_conductor = NaN;
    row.winding_count = NaN;
    row.turns_total = NaN;
    row.n_filar_total = NaN;
    row.conductors_est = NaN;
    row.mesh_cells_est = NaN;
    row.mixed_wire_shapes = false;
    row.complexity_score = NaN;
    row.fft_eligible_hint = false;
end

function obj = load_json(in_file)
    fid = fopen(in_file, 'r');
    if fid == -1
        error('extract_case_features: cannot open %s', in_file);
    end
    txt = fread(fid, '*char')';
    fclose(fid);
    txt = sanitize_json_text(txt);
    obj = jsondecode(txt);
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

function write_json(payload, out_file)
    fid = fopen(out_file, 'w');
    if fid == -1
        error('extract_case_features: cannot write %s', out_file);
    end
    fwrite(fid, jsonencode(payload));
    fclose(fid);
end

function out = get_nested_struct(s, keys, default_val)
    out = default_val;
    cur = s;
    for i = 1:numel(keys)
        k = keys{i};
        if ~isstruct(cur) || ~isfield(cur, k)
            return;
        end
        cur = cur.(k);
    end
    out = cur;
end

function out = get_nested_numeric(s, keys, default_val)
    out = default_val;
    v = get_nested_struct(s, keys, []);
    if isnumeric(v) && isscalar(v) && isfinite(v)
        out = double(v);
    end
end

function out = get_nested_string(s, keys, default_val)
    out = default_val;
    v = get_nested_struct(s, keys, []);
    if ischar(v)
        out = char(v);
    elseif (exist('isstring', 'builtin') || exist('isstring', 'file')) && isstring(v)
        out = char(v);
    end
end

function out = get_struct_field(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        out = s.(field_name);
    end
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
        if ischar(v)
            out = char(v);
        elseif (exist('isstring', 'builtin') || exist('isstring', 'file')) && isstring(v)
            out = char(v);
        end
    end
end

function s = strip_json_suffix(name_in)
    s = char(name_in);
    if numel(s) > 5 && strcmpi(s(end-4:end), '.json')
        s = s(1:end-5);
    end
end

function tf = to_logical(v, default_val)
    tf = default_val;
    if islogical(v) && isscalar(v)
        tf = v;
    elseif isnumeric(v) && isscalar(v)
        tf = (v ~= 0);
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

function ensure_local_paths()
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(root);
    addpath(here);
    addpath(fullfile(root, 'mesh'));
    addpath(fullfile(root, 'physics'));
    addpath(fullfile(root, 'corrections'));
    addpath(fullfile(root, 'kernels'));
    addpath(fullfile(root, 'kernels', 'native'));
    addpath(fullfile(root, 'litz'));
end
