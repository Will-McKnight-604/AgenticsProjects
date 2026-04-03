function report = run_fft_backend_benchmark(case_dir, results_dir)
%RUN_FFT_BACKEND_BENCHMARK Validate FFT routing, accuracy, and matvec speedup.
%
% Example:
%   report = run_fft_backend_benchmark();

    ensure_local_paths();

    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(case_dir)
        case_dir = fullfile(here, 'fft_cases');
    end
    if nargin < 2 || isempty(results_dir)
        results_dir = fullfile(here, 'results_fft');
    end
    if ~exist(results_dir, 'dir')
        mkdir(results_dir);
    end
    if ~exist(case_dir, 'dir') || isempty(dir(fullfile(case_dir, '*.json')))
        generate_fft_eligible_cases(case_dir);
    end

    files = { ...
        fullfile(case_dir, 'fft_case_uniform_large.json'), ...
        fullfile(case_dir, 'fft_case_nonuniform_large.json') ...
    };

    rows = struct([]);
    for i = 1:numel(files)
        rows = [rows; evaluate_fft_case(files{i})]; %#ok<AGROW>
    end

    report = struct();
    report.generated_at = datestr(now, 30);
    report.case_dir = case_dir;
    report.results_dir = results_dir;
    report.rows = rows;
    report.summary = summarize_rows(rows);

    latest = fullfile(results_dir, 'fft_backend_benchmark_latest.json');
    stamp = fullfile(results_dir, ['fft_backend_benchmark_' report.generated_at '.json']);
    write_json(report, latest);
    write_json(report, stamp);

    fprintf('[FFT] Wrote: %s\n', latest);
end

function row = evaluate_fft_case(case_path)
    case_data = load_json(case_path);
    case_id = get_nested_string(case_data, {'meta', 'case_id'}, strip_json_suffix(case_path));
    benchmark = get_nested_struct(case_data, {'benchmark'}, struct());

    sigma = get_nested_numeric(benchmark, {'sigma_s_per_m'}, 5.8e7);
    mu0 = get_nested_numeric(benchmark, {'mu0_h_per_m'}, 4 * pi * 1e-7);
    Nx = max(2, round(get_nested_numeric(benchmark, {'mesh', 'Nx'}, 2)));
    Ny = max(2, round(get_nested_numeric(benchmark, {'mesh', 'Ny'}, 2)));
    f = max(1, get_nested_numeric(benchmark, {'frequency_hz'}, 100e3));
    [conductors, winding_map, wire_shapes] = build_conductors_from_case(benchmark);

    opts_auto = solver_option_profile('fast');
    opts_auto.enable_adaptive_meshing = false;
    opts_auto.linear_solver = 'bicgstab';
    opts_auto.preconditioner = 'jacobi';
    opts_auto.iter_tol = 1e-2;
    opts_auto.iter_maxit = 80;
    opts_auto.matrix_mode = 'auto';
    opts_auto.interaction_backend = 'auto';
    opts_auto.enable_solver_cache = false;
    opts_auto.enable_geometry_cache = false;
    opts_auto.enable_external_krylov = false;

    opts_dense = opts_auto;
    opts_dense.matrix_mode = 'dense';
    opts_dense.interaction_backend = 'dense';

    geom_auto = peec_build_geometry(conductors, sigma, mu0, Nx, Ny, winding_map, wire_shapes, opts_auto);
    geom_dense = peec_build_geometry(conductors, sigma, mu0, Nx, Ny, winding_map, wire_shapes, opts_dense);

    n = geom_dense.Nf;
    try
        rng(17, 'twister');
    catch
        rand('seed', 17); %#ok<RAND>
    end
    v = randn(n, 1) + 1j * randn(n, 1);

    % Warmup to stabilize first-call overhead.
    y_auto = apply_peec_interaction_backend(geom_auto.interaction, v, geom_dense.L); %#ok<NASGU>
    y_dense = geom_dense.L * v; %#ok<NASGU>

    reps = 3;
    t_auto = median_time(@() apply_peec_interaction_backend(geom_auto.interaction, v, geom_dense.L), reps);
    t_dense = median_time(@() (geom_dense.L * v), reps);

    y_auto = apply_peec_interaction_backend(geom_auto.interaction, v, geom_dense.L);
    y_dense = geom_dense.L * v;
    rel_err = norm(y_auto - y_dense) / max(norm(y_dense), 1e-12);

    clear_phase3_runtime_caches();
    r_auto = execute_mas_case(case_path, opts_auto);
    clear_phase3_runtime_caches();
    r_dense = execute_mas_case(case_path, opts_dense);

    row = struct();
    row.case_id = case_id;
    if ~isempty(strfind(lower(case_id), 'nonuniform')) %#ok<STREMP>
        row.case_type = 'nonuniform';
    else
        row.case_type = 'uniform';
    end
    row.case_file = case_path;
    row.fft_eligible = get_struct_bool(geom_auto, 'fft_eligible', false);
    row.fft_used_auto = strcmpi(get_struct_string(geom_auto, 'interaction_backend_used', 'dense'), 'fft');
    row.interaction_backend_used_auto = get_struct_string(geom_auto, 'interaction_backend_used', 'dense');
    row.interaction_backend_reason_auto = get_struct_string(geom_auto, 'interaction_backend_reason', '');
    row.interaction_rel_error = rel_err;
    row.matvec_time_auto_s = t_auto;
    row.matvec_time_dense_s = t_dense;
    row.matvec_speedup_fft_vs_dense = safe_ratio(t_dense, t_auto);
    row.case_runtime_auto_s = get_struct_numeric(r_auto, 'runtime_s', NaN);
    row.case_runtime_dense_s = get_struct_numeric(r_dense, 'runtime_s', NaN);
    row.case_speedup_auto_vs_dense = safe_ratio(row.case_runtime_dense_s, row.case_runtime_auto_s);
    row.loss_error_vs_dense_pct = 100 * relative_error( ...
        get_struct_numeric(r_auto, 'total_copper_loss_w', NaN), ...
        get_struct_numeric(r_dense, 'total_copper_loss_w', NaN));
end

function s = summarize_rows(rows)
    s = struct();
    s.case_count = numel(rows);
    if isempty(rows)
        s.pass = false;
        return;
    end

    idx_u = find(arrayfun(@(r) strcmpi(get_struct_string(r, 'case_type', ''), 'uniform'), rows), 1, 'first');
    idx_n = find(arrayfun(@(r) strcmpi(get_struct_string(r, 'case_type', ''), 'nonuniform'), rows), 1, 'first');
    if isempty(idx_u), idx_u = 1; end
    if isempty(idx_n), idx_n = min(2, numel(rows)); end

    u = rows(idx_u);
    n = rows(idx_n);
    s.uniform_case_id = u.case_id;
    s.nonuniform_case_id = n.case_id;
    s.uniform_fft_used = u.fft_used_auto;
    s.nonuniform_fft_used = n.fft_used_auto;
    s.uniform_interaction_rel_error = u.interaction_rel_error;
    s.uniform_fft_speedup_vs_dense = u.matvec_speedup_fft_vs_dense;
    s.uniform_case_speedup_vs_dense = u.case_speedup_auto_vs_dense;

    c = optimization_pass_criteria();
    s.pass = u.fft_used_auto && (~n.fft_used_auto) && ...
        isfinite(u.interaction_rel_error) && (u.interaction_rel_error <= c.fft_interaction_rel_error_max) && ...
        isfinite(u.matvec_speedup_fft_vs_dense) && (u.matvec_speedup_fft_vs_dense >= c.fft_speedup_min);
end

function t = median_time(fn, reps)
    x = NaN(1, reps);
    for i = 1:reps
        t0 = tic;
        fn();
        x(i) = toc(t0);
    end
    t = median(x(isfinite(x)));
end

function [conductors, winding_map, wire_shapes] = build_conductors_from_case(benchmark)
    conductors = [];
    winding_map = [];
    wire_shapes = {};

    geom = get_nested_struct(benchmark, {'geometry'}, struct());
    windings = get_struct_field(geom, 'windings', struct([]));
    if iscell(windings)
        try
            windings = [windings{:}];
        catch
            windings = struct([]);
        end
    end
    if isempty(windings)
        return;
    end

    gaps = get_struct_field(geom, 'gaps', struct());
    gap_layer = get_struct_numeric(gaps, 'layer_m', 0.08e-3);
    gap_filar = get_struct_numeric(gaps, 'filar_m', 0.04e-3);
    gap_winding = get_struct_numeric(gaps, 'winding_m', 0.40e-3);

    x_cursor = 0;
    for w = 1:numel(windings)
        turns = max(1, round(get_struct_numeric(windings(w), 'turns', 1)));
        n_filar = max(1, round(get_struct_numeric(windings(w), 'n_filar', 1)));
        I_rms = get_struct_numeric(windings(w), 'current_a', 1.0);
        ph_deg = get_struct_numeric(windings(w), 'phase_deg', 0);
        wire = get_struct_field(windings(w), 'wire', struct());
        [wire_w, wire_h, shape_name] = read_wire_dims(wire);

        turns_per_layer = max(3, ceil(sqrt(turns)));
        x_pitch = wire_w + gap_filar;
        y_pitch = wire_h + gap_layer;

        for t = 1:turns
            col = mod(t - 1, turns_per_layer);
            row = floor((t - 1) / turns_per_layer);
            y_turn = row * y_pitch;
            for p = 1:n_filar
                x_turn = x_cursor + col * x_pitch + (p - 1) * (wire_w + gap_filar);
                conductors(end+1, :) = [x_turn, y_turn, wire_w, wire_h, I_rms, ph_deg]; %#ok<AGROW>
                winding_map(end+1, 1) = w; %#ok<AGROW>
                wire_shapes{end+1, 1} = shape_name; %#ok<AGROW>
            end
        end

        x_span = turns_per_layer * x_pitch + max(0, n_filar - 1) * (wire_w + gap_filar);
        x_cursor = x_cursor + x_span + gap_winding;
    end

    if ~isempty(conductors)
        conductors(:, 1) = conductors(:, 1) - min(conductors(:, 1));
        conductors(:, 2) = conductors(:, 2) - min(conductors(:, 2));
    end
end

function [w, h, shape_name] = read_wire_dims(wire)
    shape_name = get_struct_string(wire, 'shape', get_struct_string(wire, 'kind', 'round'));
    shape_name = lower(strtrim(shape_name));
    if strcmp(shape_name, 'rectangular')
        w = max(get_struct_numeric(wire, 'width_m', 0.5e-3), 1e-6);
        h = max(get_struct_numeric(wire, 'height_m', 0.2e-3), 1e-6);
        return;
    end
    d = get_struct_numeric(wire, 'diameter_m', get_struct_numeric(wire, 'width_m', 0.5e-3));
    d = max(d, 1e-6);
    w = d;
    h = d;
    shape_name = 'round';
end

function obj = load_json(in_file)
    fid = fopen(in_file, 'r');
    if fid == -1
        error('run_fft_backend_benchmark: cannot open %s', in_file);
    end
    txt = fread(fid, '*char')';
    fclose(fid);
    obj = jsondecode(sanitize_json_text(txt));
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
        error('run_fft_backend_benchmark: cannot write %s', out_file);
    end
    fwrite(fid, jsonencode(payload));
    fclose(fid);
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

function out = get_struct_bool(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if islogical(v) && isscalar(v)
            out = v;
        elseif isnumeric(v) && isscalar(v)
            out = (v ~= 0);
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

function r = safe_ratio(a, b)
    r = NaN;
    if ~isfinite(a) || ~isfinite(b) || b == 0
        return;
    end
    r = a / b;
end

function s = strip_json_suffix(path_in)
    [~, s, ~] = fileparts(path_in);
end
