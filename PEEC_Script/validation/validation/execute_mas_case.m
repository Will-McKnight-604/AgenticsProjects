function result = execute_mas_case(case_input, solve_options)
%EXECUTE_MAS_CASE Run one MAS-style benchmark case through the PEEC solver.

    ensure_phase3_paths();

    if nargin < 2 || isempty(solve_options)
        solve_options = solver_option_profile('standard');
    elseif is_text_like(solve_options)
        solve_options = solver_option_profile(char(solve_options));
    end

    case_data = load_case_data(case_input);
    case_id = get_nested_string(case_data, {'meta', 'case_id'}, 'unknown_case');
    source_solver = get_nested_string(case_data, {'meta', 'source_solver'}, 'unknown');

    benchmark = get_nested_struct(case_data, {'benchmark'}, struct());
    freq_hz = get_nested_numeric(benchmark, {'frequency_hz'}, 100e3);
    sigma = get_nested_numeric(benchmark, {'sigma_s_per_m'}, 5.8e7);
    mu0 = get_nested_numeric(benchmark, {'mu0_h_per_m'}, 4 * pi * 1e-7);
    Nx = max(2, round(get_nested_numeric(benchmark, {'mesh', 'Nx'}, 6)));
    Ny = max(2, round(get_nested_numeric(benchmark, {'mesh', 'Ny'}, 6)));

    [conductors, winding_map, wire_shapes] = build_conductors_from_case(benchmark);
    if isempty(conductors)
        error('execute_mas_case: case "%s" produced empty conductor set', case_id);
    end

    data = struct();
    data.sigma = sigma;
    data.mu0 = mu0;
    data.f = freq_hz;
    data.Nx = Nx;
    data.Ny = Ny;

    t_case = tic;
    t_geom = tic;
    mesh_meta = struct();
    try
        [geom, mesh_meta] = adaptive_refine(data, conductors, winding_map, wire_shapes, solve_options);
    catch
        geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny, winding_map, wire_shapes, solve_options);
        mesh_meta = struct('converged', false, 'stop_reason', 'adaptive_error_fallback', ...
            'runtime_s', NaN, 'rel_error_loss', NaN, 'rel_error_llk', NaN, 'uncertainty_pct', NaN);
    end
    t_geom_s = toc(t_geom);

    t_lin = tic;
    res = peec_solve_frequency(geom, conductors, freq_hz, sigma, mu0, solve_options);
    t_lin_s = toc(t_lin);

    core = get_nested_struct(benchmark, {'core'}, struct());
    core_params = struct();
    core_params.Ae = max(get_struct_numeric(core, 'Ae', 1e-9), 1e-12);
    core_params.le = max(get_struct_numeric(core, 'le', 1e-3), 1e-6);
    core_params.Ve = max(get_struct_numeric(core, 'Ve', 1e-9), 1e-12);
    core_params.bobbin_w = get_struct_numeric(core, 'bobbin_w', 0);
    core_params.bobbin_h = get_struct_numeric(core, 'bobbin_h', 0);
    MLT = max(get_struct_numeric(core, 'MLT', 1e-2), 1e-5);
    mu_r = max(get_struct_numeric(core, 'mu_r', 2200), 2);
    gap_total = max(get_struct_numeric(core, 'gap_total_m', 0), 0);
    gapping = {};
    if gap_total > 0
        gapping = {struct('type', 'subtractive', 'length', gap_total)};
    end

    t_mag = tic;
    mp = compute_winding_inductance_matrix(geom, MLT, core_params, mu_r, gapping, solve_options);
    t_mag_s = toc(t_mag);

    winding_losses = [];
    if isfield(res, 'P_winding') && ~isempty(res.P_winding)
        winding_losses = real(res.P_winding(:)');
    else
        winding_losses = aggregate_winding_losses(res.P_fil, winding_map, geom.Nx, geom.Ny);
    end

    L_self = [];
    if isfield(mp, 'L_winding') && ~isempty(mp.L_winding)
        L_self = real(diag(mp.L_winding(:,:))).';
    end

    solve_meta = struct();
    if isfield(res, 'meta') && isstruct(res.meta)
        solve_meta = res.meta;
    end

    result = struct();
    result.case_id = case_id;
    result.source_solver = source_solver;
    result.frequency_hz = freq_hz;
    result.total_copper_loss_w = real(res.P_total);
    result.winding_losses_w = winding_losses;
    result.L_self_h = L_self;
    result.Lm_h = get_struct_numeric(mp, 'Lm', 0);
    result.Llk_pri_h = get_struct_numeric(mp, 'Llk_pri', 0);
    result.Llk_sec_h = get_struct_numeric(mp, 'Llk_sec', 0);
    result.runtime_s = toc(t_case);
    result.mesh_cells = geom.Nf;
    result.mesh_Nx = geom.Nx;
    result.mesh_Ny = geom.Ny;
    result.mode = get_struct_string(solve_options, 'mode', 'standard');
    result.converged = get_struct_bool(mesh_meta, 'converged', false);
    result.stop_reason = get_struct_string(mesh_meta, 'stop_reason', 'unknown');
    result.rel_error_loss = get_struct_numeric(mesh_meta, 'rel_error_loss', NaN);
    result.rel_error_llk = get_struct_numeric(mesh_meta, 'rel_error_llk', NaN);
    result.uncertainty_pct = get_struct_numeric(mesh_meta, 'uncertainty_pct', NaN);
    result.mesh_meta = mesh_meta;
    result.solve_meta = solve_meta;
    result.time_mesh_build_s = t_geom_s;
    result.time_linear_solve_s = t_lin_s;
    result.time_magnetic_extract_s = t_mag_s;
    result.time_total_s = result.runtime_s;
    result.linear_solver_used = get_struct_string(solve_meta, 'linear_solver_used', 'direct');
    result.preconditioner_used = get_struct_string(solve_meta, 'preconditioner_used', 'none');
    result.iter_backend_used = get_struct_string(solve_meta, 'iter_backend_used', 'octave');
    result.matrix_mode_used = get_struct_string(solve_meta, 'matrix_mode_used', 'dense');
    result.interaction_backend_used = get_struct_string(solve_meta, 'interaction_backend_used', 'dense');
    result.iter_relres = get_struct_numeric(solve_meta, 'iter_relres', NaN);
    result.iter_count = get_struct_numeric(solve_meta, 'iter_count', NaN);
    result.fallback_to_direct = get_struct_bool(solve_meta, 'fallback_to_direct', false);
    result.iterative_attempts = get_struct_numeric(solve_meta, 'iterative_attempts', NaN);
    result.iterative_retry_used = get_struct_bool(solve_meta, 'iterative_retry_used', false);
    result.iter_quality_gate_passed = get_struct_bool(solve_meta, 'iter_quality_gate_passed', true);
    result.iter_rejected_reason = get_struct_string(solve_meta, 'iter_rejected_reason', '');
    result.had_solver_warning = get_struct_bool(solve_meta, 'had_solver_warning', false);
    result.warning_kind = get_struct_string(solve_meta, 'warning_kind', '');
    result.mesh_refine_iterations = get_struct_numeric(mesh_meta, 'mesh_refine_iterations', get_struct_numeric(mesh_meta, 'iterations', NaN));
    result.fft_eligible = get_struct_bool(geom, 'fft_eligible', false);
    result.fft_used = strcmpi(result.interaction_backend_used, 'fft') || get_struct_bool(geom, 'fft_used', false);
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
        x_min = min(conductors(:, 1));
        y_min = min(conductors(:, 2));
        conductors(:, 1) = conductors(:, 1) - x_min;
        conductors(:, 2) = conductors(:, 2) - y_min;
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

    if isfield(wire, 'diameter_m')
        d = max(get_struct_numeric(wire, 'diameter_m', 0.5e-3), 1e-6);
    else
        d = max(get_struct_numeric(wire, 'width_m', 0.5e-3), 1e-6);
    end
    w = d;
    h = d;
    shape_name = 'round';
end

function losses = aggregate_winding_losses(P_fil, winding_map, Nx, Ny)
    n_w = max(1, max(winding_map));
    losses = zeros(1, n_w);
    fils_per_cond = max(1, Nx * Ny);
    for c = 1:numel(winding_map)
        w = winding_map(c);
        if w < 1 || w > n_w
            continue;
        end
        idx1 = (c - 1) * fils_per_cond + 1;
        idx2 = min(c * fils_per_cond, numel(P_fil));
        if idx1 <= idx2
            losses(w) = losses(w) + sum(P_fil(idx1:idx2));
        end
    end
end

function case_data = load_case_data(case_input)
    if isstruct(case_input)
        case_data = case_input;
        return;
    end
    if ~is_text_like(case_input)
        error('execute_mas_case: case_input must be struct or file path');
    end
    case_path = char(case_input);
    if ~exist(case_path, 'file')
        error('execute_mas_case: case file not found: %s', case_path);
    end
    fid = fopen(case_path, 'r');
    if fid == -1
        error('execute_mas_case: cannot read case file: %s', case_path);
    end
    raw = fread(fid, '*char')';
    fclose(fid);
    raw = sanitize_json_text(raw);
    case_data = jsondecode(raw);
end

function txt = sanitize_json_text(txt)
    if isempty(txt)
        return;
    end
    % Strip UTF-8 BOM if present (jsondecode in some MATLAB/Octave builds rejects it).
    if double(txt(1)) == 65279
        txt = txt(2:end);
    end
    txt = strtrim(txt);
end

function s = get_nested_struct(root, path_cells, default_val)
    s = default_val;
    cur = root;
    for i = 1:numel(path_cells)
        key = path_cells{i};
        if ~isstruct(cur) || ~isfield(cur, key)
            return;
        end
        cur = cur.(key);
    end
    if isstruct(cur)
        s = cur;
    end
end

function out = get_nested_numeric(root, path_cells, default_val)
    out = default_val;
    cur = root;
    for i = 1:numel(path_cells)
        key = path_cells{i};
        if ~isstruct(cur) || ~isfield(cur, key)
            return;
        end
        cur = cur.(key);
    end
    if isnumeric(cur) && isscalar(cur) && isfinite(cur)
        out = double(cur);
    end
end

function out = get_nested_string(root, path_cells, default_val)
    out = default_val;
    cur = root;
    for i = 1:numel(path_cells)
        key = path_cells{i};
        if ~isstruct(cur) || ~isfield(cur, key)
            return;
        end
        cur = cur.(key);
    end
    if is_text_like(cur)
        out = char(cur);
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

function out = get_struct_field(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        out = s.(field_name);
    end
end

function ensure_phase3_paths()
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(root);
    addpath(here);
    subdirs = {'mesh', 'corrections', 'physics', 'kernels', 'litz'};
    for i = 1:numel(subdirs)
        p = fullfile(root, subdirs{i});
        if exist(p, 'dir')
            addpath(p);
        end
    end
    native_dir = fullfile(root, 'kernels', 'native');
    if exist(native_dir, 'dir')
        addpath(native_dir);
    end
end
