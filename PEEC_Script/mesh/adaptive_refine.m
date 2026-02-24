function [geom_best, meta] = adaptive_refine(data, conductors, winding_map, wire_shapes, solve_options)
%ADAPTIVE_REFINE Goal-based mesh refinement for PEEC geometry.
%
% Convergence indicators:
%   - relative change in total copper loss
%   - relative change in air-core leakage indicator

    ensure_local_subdir('validation');

    if nargin < 5 || isempty(solve_options)
        if exist('solver_option_profile', 'file') == 2
            solve_options = solver_option_profile('standard');
        else
            solve_options = default_solve_options();
        end
    end

    if isempty(conductors)
        error('adaptive_refine: empty conductors');
    end

    enable_adapt = get_opt_bool(solve_options, 'enable_adaptive_meshing', true);
    Nx0 = max(2, round(get_opt_num(data, 'Nx', 6)));
    Ny0 = max(2, round(get_opt_num(data, 'Ny', 6)));

    meta = struct();
    meta.converged = true;
    meta.stop_reason = 'adaptive_disabled';
    meta.runtime_s = 0;
    meta.iterations = 1;
    meta.rel_error_loss = NaN;
    meta.rel_error_llk = NaN;
    meta.history = struct([]);
    meta.Nx_final = Nx0;
    meta.Ny_final = Ny0;
    meta.uncertainty_pct = NaN;

    local_opts = solve_options;
    local_opts.enable_adaptive_meshing = false;

    t_global = tic;
    if ~enable_adapt
        geom_best = peec_build_geometry(conductors, data.sigma, data.mu0, Nx0, Ny0, ...
            winding_map, wire_shapes, local_opts);
        meta.runtime_s = toc(t_global);
        meta.uncertainty_pct = max(100 / max(Nx0 * Ny0, 1), 5);
        return;
    end

    target_loss = get_opt_num(solve_options, 'target_rel_error_loss', 0.025);
    target_llk = get_opt_num(solve_options, 'target_rel_error_llk', 0.025);
    runtime_cap = get_opt_num(solve_options, 'runtime_cap_s', 8.0);
    max_iters = max(1, round(get_opt_num(solve_options, 'max_refine_iters', 5)));
    refine_step = max(1, round(get_opt_num(solve_options, 'refine_step', 1)));
    adaptive_step_auto = get_opt_bool(solve_options, 'adaptive_step_auto', true);
    adaptive_step_max = max(refine_step, round(get_opt_num(solve_options, 'adaptive_step_max', 3)));
    adaptive_step_gain = get_opt_num(solve_options, 'adaptive_step_gain', 0.85);
    adaptive_step_relax = get_opt_num(solve_options, 'adaptive_step_relax', 0.45);
    refine_stagnation_window = max(1, round(get_opt_num(solve_options, 'refine_stagnation_window', 2)));
    refine_stagnation_tol = max(0, get_opt_num(solve_options, 'refine_stagnation_tol', 0.05));
    loss_jump_guard_pct = max(0, get_opt_num(solve_options, 'iter_quality_guard_loss_jump_pct', 120));
    max_Nx = max(Nx0, round(get_opt_num(solve_options, 'max_mesh_Nx', 16)));
    max_Ny = max(Ny0, round(get_opt_num(solve_options, 'max_mesh_Ny', 16)));

    Nx = Nx0;
    Ny = Ny0;

    best_score = inf;
    geom_best = [];
    prev_loss = NaN;
    prev_llk = NaN;
    prev_error_score = NaN;
    last_step = refine_step;
    stagnation_hits = 0;
    loss_jump_guard_hits = 0;

    for it = 1:max_iters
        if toc(t_global) > runtime_cap && it > 1
            meta.converged = false;
            meta.stop_reason = 'runtime_cap';
            break;
        end

        t_geom_start = tic;
        geom_i = peec_build_geometry(conductors, data.sigma, data.mu0, Nx, Ny, ...
            winding_map, wire_shapes, local_opts);
        t_geom_s = toc(t_geom_start);

        t_solve_start = tic;
        res_i = peec_solve_frequency(geom_i, conductors, data.f, data.sigma, data.mu0, local_opts);
        t_solve_s = toc(t_solve_start);

        llk_i = estimate_aircore_llk_indicator(geom_i, winding_map);

        loss_jump_pct = NaN;
        loss_jump_guard_triggered = false;
        if it > 1
            loss_jump_pct = 100 * abs(res_i.P_total - prev_loss) / max(abs(prev_loss), 1e-12);
            if isfinite(loss_jump_pct) && (loss_jump_guard_pct > 0) && (loss_jump_pct > loss_jump_guard_pct)
                guard_opts = local_opts;
                guard_opts.linear_solver = 'direct';
                guard_opts.matrix_mode = 'dense';
                guard_opts.interaction_backend = 'dense';
                guard_opts.enable_solver_cache = false;
                try
                    t_guard_start = tic;
                    res_guard = peec_solve_frequency(geom_i, conductors, data.f, data.sigma, data.mu0, guard_opts);
                    t_solve_s = t_solve_s + toc(t_guard_start);
                    if isstruct(res_guard) && isfield(res_guard, 'P_total') && isfinite(res_guard.P_total)
                        res_i = res_guard;
                        loss_jump_pct = 100 * abs(res_i.P_total - prev_loss) / max(abs(prev_loss), 1e-12);
                        loss_jump_guard_triggered = true;
                        loss_jump_guard_hits = loss_jump_guard_hits + 1;
                    end
                catch
                    % If guard rerun fails, keep original solve result.
                end
            end
        end

        rel_loss = NaN;
        rel_llk = NaN;
        if it > 1
            rel_loss = abs(res_i.P_total - prev_loss) / max(abs(res_i.P_total), 1e-12);
            rel_llk = abs(llk_i - prev_llk) / max(abs(llk_i), 1e-12);
        end

        h = struct();
        h.iteration = it;
        h.Nx = Nx;
        h.Ny = Ny;
        h.P_total = res_i.P_total;
        h.Llk_indicator = llk_i;
        h.rel_error_loss = rel_loss;
        h.rel_error_llk = rel_llk;
        h.loss_jump_pct = loss_jump_pct;
        h.loss_jump_guard_triggered = loss_jump_guard_triggered;
        h.refine_step = last_step;
        h.t_geom_s = t_geom_s;
        h.t_solve_s = t_solve_s;
        h.elapsed_s = toc(t_global);
        meta.history = [meta.history; h]; %#ok<AGROW>

        score = 0;
        if it > 1
            score = rel_loss + rel_llk;
        end
        if isempty(geom_best) || score <= best_score || it == 1
            geom_best = geom_i;
            best_score = score;
            meta.rel_error_loss = rel_loss;
            meta.rel_error_llk = rel_llk;
            meta.Nx_final = Nx;
            meta.Ny_final = Ny;
        end

        if it > 1 && rel_loss <= target_loss && rel_llk <= target_llk
            meta.converged = true;
            meta.stop_reason = 'target_reached';
            break;
        end

        prev_loss = res_i.P_total;
        prev_llk = llk_i;

        step_now = refine_step;
        if adaptive_step_auto && it > 1 && isfinite(rel_loss) && isfinite(rel_llk)
            curr_error_score = rel_loss + rel_llk;
            if isfinite(prev_error_score) && prev_error_score > 0
                progress_ratio = curr_error_score / prev_error_score;
                improvement = (prev_error_score - curr_error_score) / max(prev_error_score, 1e-12);
                if progress_ratio > adaptive_step_gain
                    step_now = min(adaptive_step_max, refine_step + 1);
                elseif progress_ratio < adaptive_step_relax
                    step_now = 1;
                end
                if improvement < refine_stagnation_tol
                    stagnation_hits = stagnation_hits + 1;
                else
                    stagnation_hits = 0;
                end
            else
                stagnation_hits = 0;
            end
            prev_error_score = curr_error_score;
        end
        last_step = step_now;

        if it > 1 && stagnation_hits >= refine_stagnation_window
            meta.converged = false;
            meta.stop_reason = 'stagnation';
            break;
        end

        Nx_next = min(max_Nx, Nx + step_now);
        Ny_next = min(max_Ny, Ny + step_now);
        if Nx_next == Nx && Ny_next == Ny
            meta.converged = false;
            meta.stop_reason = 'mesh_limit';
            break;
        end
        Nx = Nx_next;
        Ny = Ny_next;

        if it == max_iters
            meta.converged = false;
            meta.stop_reason = 'max_iters';
        end
    end

    meta.runtime_s = toc(t_global);
    meta.iterations = numel(meta.history);
    meta.adaptive_step_auto = adaptive_step_auto;
    meta.adaptive_step_max = adaptive_step_max;
    meta.refine_step_last = last_step;
    meta.refine_stagnation_hits = stagnation_hits;
    meta.loss_jump_guard_trigger_count = loss_jump_guard_hits;
    meta.mesh_refine_iterations = numel(meta.history);
    if isnan(meta.rel_error_loss), meta.rel_error_loss = target_loss; end
    if isnan(meta.rel_error_llk), meta.rel_error_llk = target_llk; end
    meta.uncertainty_pct = 100 * max([target_loss, target_llk, meta.rel_error_loss, meta.rel_error_llk]);

    % Timing breakdown: sum per-iteration geometry and solve times
    if ~isempty(meta.history) && isfield(meta.history, 't_geom_s')
        meta.t_geom_total_s  = sum([meta.history.t_geom_s]);
        meta.t_solve_total_s = sum([meta.history.t_solve_s]);
    else
        meta.t_geom_total_s  = NaN;
        meta.t_solve_total_s = NaN;
    end

    if ~isempty(geom_best)
        geom_best.mesh_meta = meta;
    end
end

function opts = default_solve_options()
    opts = struct();
    opts.mode = 'standard';
    opts.target_rel_error_loss = 0.03;
    opts.target_rel_error_llk = 0.03;
    opts.runtime_cap_s = 8.0;
    opts.max_refine_iters = 4;
    opts.refine_step = 1;
    opts.max_mesh_Nx = 16;
    opts.max_mesh_Ny = 16;
    opts.enable_adaptive_meshing = true;
    opts.adaptive_step_auto = true;
    opts.adaptive_step_max = 3;
    opts.adaptive_step_gain = 0.85;
    opts.adaptive_step_relax = 0.45;
end

function ensure_local_subdir(subdir_name)
    if nargin < 1 || isempty(subdir_name)
        return;
    end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    p = fullfile(root, subdir_name);
    if exist(p, 'dir')
        addpath(p);
    end
end

function Llk = estimate_aircore_llk_indicator(geom, winding_map)
    Llk = 0;
    if isempty(winding_map)
        return;
    end
    L_dense = ensure_dense_filament_L_for_indicator(geom);

    winding_ids = unique(winding_map(:));
    if numel(winding_ids) < 2
        Llk = trace(L_dense);
        return;
    end

    Nc = numel(winding_map);
    Nfpc = max(1, geom.Nx * geom.Ny);
    L_cond = zeros(Nc);
    for c1 = 1:Nc
        i1 = (c1 - 1) * Nfpc + 1;
        i2 = min(c1 * Nfpc, geom.Nf);
        for c2 = c1:Nc
            j1 = (c2 - 1) * Nfpc + 1;
            j2 = min(c2 * Nfpc, geom.Nf);
            block = L_dense(i1:i2, j1:j2);
            v = mean(block(:));
            L_cond(c1, c2) = v;
            L_cond(c2, c1) = v;
        end
    end

    w1 = find(winding_map == winding_ids(1));
    w2 = find(winding_map == winding_ids(2));
    if isempty(w1) || isempty(w2)
        return;
    end

    L11 = sum(sum(L_cond(w1, w1)));
    L22 = sum(sum(L_cond(w2, w2)));
    M = sum(sum(L_cond(w1, w2)));
    n_eff = numel(w1) / max(numel(w2), 1);
    Llk = max(L11 - n_eff * M, 0);
    if ~isfinite(Llk)
        Llk = 0;
    end
end

function L = ensure_dense_filament_L_for_indicator(geom)
    Nf = get_struct_numeric(geom, 'Nf', size(geom.filaments, 1));
    if isfield(geom, 'L') && ~isempty(geom.L)
        L = geom.L;
    else
        filaments_core = geom.filaments(:, 1:4);
        mu0 = get_struct_numeric(geom, 'mu0', 4 * pi * 1e-7);
        near_floor = get_struct_numeric(geom, 'near_floor', 1e-12);
        use_exact_rect = get_struct_bool(geom, 'use_exact_rect_kernel', false);
        L = build_partial_inductance_matrix_vectorized_local(filaments_core, mu0, use_exact_rect, near_floor);
    end
    if isempty(L) || any(size(L) ~= [Nf, Nf])
        error('adaptive_refine: dense L unavailable for llk indicator');
    end
end

function L = build_partial_inductance_matrix_vectorized_local(filaments_core, mu0, use_exact_rect, near_floor)
    x = filaments_core(:, 1);
    y = filaments_core(:, 2);
    dx = max(filaments_core(:, 3), 1e-12);
    dy = max(filaments_core(:, 4), 1e-12);
    Nf = numel(x);

    dx_all = bsxfun(@minus, x, x.');
    dy_all = bsxfun(@minus, y, y.');
    r2 = dx_all.^2 + dy_all.^2;

    d2 = dx.^2 + dy.^2;
    sigma2 = bsxfun(@plus, d2, d2.') / 12;
    r_eff = sqrt(r2 + sigma2 + near_floor^2);
    L = mu0 / (2 * pi) * log(1 ./ max(r_eff, near_floor));

    if use_exact_rect
        span = dx + dy;
        mean_span = 0.25 * bsxfun(@plus, span, span.');
        closeness = sqrt(r2) ./ max(mean_span, near_floor);
        corr = ones(Nf);
        mask = closeness < 1.5;
        corr(mask) = 1.0 - 0.12 * (1.5 - closeness(mask)) / 1.5;
        corr(mask) = max(0.80, min(1.0, corr(mask)));
        L = corr .* L;
    end

    req = max(0.2235 * (dx + dy), near_floor);
    L(1:Nf+1:end) = mu0 / (2 * pi) * log(1 ./ req);
    L = 0.5 * (L + L.');
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

function out = get_opt_num(options, field_name, default_val)
    out = default_val;
    if isstruct(options) && isfield(options, field_name)
        v = options.(field_name);
        if isnumeric(v) && isfinite(v)
            out = double(v);
        end
    end
end

function out = get_opt_bool(options, field_name, default_val)
    out = default_val;
    if isstruct(options) && isfield(options, field_name)
        out = logical(options.(field_name));
    end
end
