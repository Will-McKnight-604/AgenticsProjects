function out = demo_roadmap_workflow(case_file)
%DEMO_ROADMAP_WORKFLOW Demonstrate iterative + matrix-free + FFT + MOR flow.
%
% Example:
%   out = demo_roadmap_workflow();

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(root);
    addpath(here);
    addpath(fullfile(here, 'mor'));
    addpath(fullfile(root, 'mesh'));
    addpath(fullfile(root, 'physics'));
    addpath(fullfile(root, 'kernels'));
    addpath(fullfile(root, 'corrections'));

    if nargin < 1 || isempty(case_file)
        case_file = fullfile(here, 'mas_cases', 'tsf_case_01.json');
    end

    opts = solver_option_profile('fast');
    opts.linear_solver = 'gmres';
    opts.matrix_mode = 'matrix_free';
    opts.interaction_backend = 'fft';
    opts.preconditioner = 'jacobi';
    opts.iter_tol = 2e-4;
    opts.iter_maxit = 60;

    r1 = execute_mas_case(case_file, opts);

    sweep = struct();
    sweep.solve_options = opts;
    sweep.train_solve_options = solver_option_profile('high');
    sweep.mor_rank = 8;
    sweep.training_count = 3;
    sweep.enable_mor_warmstart = true;

    case_data = load_case_for_demo(case_file);
    [conductors, winding_map, wire_shapes] = build_demo_conductors(case_data.benchmark);
    geom = peec_build_geometry( ...
        conductors, ...
        case_data.benchmark.sigma_s_per_m, ...
        case_data.benchmark.mu0_h_per_m, ...
        case_data.benchmark.mesh.Nx, ...
        case_data.benchmark.mesh.Ny, ...
        winding_map, wire_shapes, opts);

    f0 = case_data.benchmark.frequency_hz;
    freq_list = f0 * [0.6; 0.8; 1.0; 1.2; 1.5];
    mor_report = run_frequency_sweep_with_mor(geom, conductors, freq_list, ...
        case_data.benchmark.sigma_s_per_m, case_data.benchmark.mu0_h_per_m, sweep);

    out = struct();
    out.single_case = r1;
    out.mor_sweep = mor_report;
end

function case_data = load_case_for_demo(case_file)
    fid = fopen(case_file, 'r');
    if fid == -1
        error('demo_roadmap_workflow: cannot open %s', case_file);
    end
    raw = fread(fid, '*char')';
    fclose(fid);
    case_data = jsondecode(strtrim(raw));
end

function [conductors, winding_map, wire_shapes] = build_demo_conductors(benchmark)
    % Mirror the production case-conductor builder to avoid hidden coupling.
    conductors = [];
    winding_map = [];
    wire_shapes = {};

    windings = benchmark.geometry.windings;
    if ~isstruct(windings) || isempty(windings)
        error('demo_roadmap_workflow: benchmark geometry has no windings');
    end

    gap_layer = get_num(benchmark.geometry.gaps, 'layer_m', 0.08e-3);
    gap_filar = get_num(benchmark.geometry.gaps, 'filar_m', 0.04e-3);
    gap_winding = get_num(benchmark.geometry.gaps, 'winding_m', 0.40e-3);

    x_cursor = 0;
    for w = 1:numel(windings)
        turns = max(1, round(get_num(windings(w), 'turns', 1)));
        n_filar = max(1, round(get_num(windings(w), 'n_filar', 1)));
        I_rms = get_num(windings(w), 'current_a', 1.0);
        ph_deg = get_num(windings(w), 'phase_deg', 0);
        [wire_w, wire_h, shape_name] = read_wire_dims(windings(w).wire);

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

    conductors(:, 1) = conductors(:, 1) - min(conductors(:, 1));
    conductors(:, 2) = conductors(:, 2) - min(conductors(:, 2));
end

function [w, h, shape_name] = read_wire_dims(wire)
    shape_name = lower(get_str(wire, 'shape', get_str(wire, 'kind', 'round')));
    if strcmp(shape_name, 'rectangular')
        w = max(get_num(wire, 'width_m', 0.5e-3), 1e-6);
        h = max(get_num(wire, 'height_m', 0.2e-3), 1e-6);
        return;
    end
    d = max(get_num(wire, 'diameter_m', get_num(wire, 'width_m', 0.5e-3)), 1e-6);
    w = d;
    h = d;
    shape_name = 'round';
end

function out = get_num(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if isnumeric(v) && isscalar(v) && isfinite(v)
            out = double(v);
        end
    end
end

function out = get_str(s, field_name, default_val)
    out = default_val;
    if ~isstruct(s) || ~isfield(s, field_name)
        return;
    end
    v = s.(field_name);
    if ischar(v)
        out = char(v);
        return;
    end
    if (exist('isstring', 'builtin') || exist('isstring', 'file')) && isstring(v)
        out = char(v);
    end
end
