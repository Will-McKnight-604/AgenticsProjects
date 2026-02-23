function report = run_gui_cache_ab_test(fig_handle)
%RUN_GUI_CACHE_AB_TEST Controlled GUI A/B cache benchmark.
% Runs three passes against the currently loaded GUI design:
%   A: caches OFF (cold)
%   B: caches ON  (cold)
%   C: caches ON  (warm, immediate rerun)
%
% Returns a report struct with runtime and metric deltas.

    normalize_phase3_paths_for_gui_ab();

    if nargin < 1 || isempty(fig_handle)
        fig_handle = resolve_or_launch_designer();
    else
        if numel(fig_handle) > 1
            fig_handle = fig_handle(1);
        end
        if ~ishandle(fig_handle)
            fig_handle = resolve_or_launch_designer();
        end
    end

    run_btn = findobj(fig_handle, 'Style', 'pushbutton', 'String', 'Run Analysis');
    if isempty(run_btn)
        error('run_gui_cache_ab_test: Run Analysis button not found');
    end
    run_btn = run_btn(1);

    fprintf('[GUI-AB] Starting controlled cache comparison...\n');

    state_A = do_one_run(fig_handle, run_btn, false, false, true);
    state_B = do_one_run(fig_handle, run_btn, true, true, true);
    state_C = do_one_run(fig_handle, run_btn, true, true, false);

    A = extract_metrics(state_A);
    B = extract_metrics(state_B);
    C = extract_metrics(state_C);

    report = struct();
    report.generated_at = datestr(now, 30);
    report.scenario_A = A;
    report.scenario_B = B;
    report.scenario_C = C;
    report.speedup_cold_cache_on_vs_off = safe_ratio(A.runtime_s, B.runtime_s);
    report.speedup_warm_cache_on_vs_off = safe_ratio(A.runtime_s, C.runtime_s);
    report.speedup_warm_vs_cold_cache_on = safe_ratio(B.runtime_s, C.runtime_s);
    report.rel_delta_B_vs_A = compute_rel_delta(A, B);
    report.rel_delta_C_vs_A = compute_rel_delta(A, C);

    fprintf('[GUI-AB] A (no-cache, cold): runtime %.3f s\n', A.runtime_s);
    fprintf('[GUI-AB] B (cache-on, cold): runtime %.3f s\n', B.runtime_s);
    fprintf('[GUI-AB] C (cache-on, warm): runtime %.3f s\n', C.runtime_s);
    fprintf('[GUI-AB] Speedup (A/B): %.3fx\n', report.speedup_cold_cache_on_vs_off);
    fprintf('[GUI-AB] Speedup (A/C): %.3fx\n', report.speedup_warm_cache_on_vs_off);
    fprintf('[GUI-AB] Delta B vs A: loss=%.3g, Lm=%.3g, Llk=%.3g\n', ...
        report.rel_delta_B_vs_A.loss, report.rel_delta_B_vs_A.Lm, report.rel_delta_B_vs_A.Llk_pri);
    fprintf('[GUI-AB] Delta C vs A: loss=%.3g, Lm=%.3g, Llk=%.3g\n', ...
        report.rel_delta_C_vs_A.loss, report.rel_delta_C_vs_A.Lm, report.rel_delta_C_vs_A.Llk_pri);
end

function fig_handle = resolve_or_launch_designer()
    figs = findall(0, 'Type', 'figure', 'Name', 'Interactive Transformer Design Tool');
    if isempty(figs)
        if exist('interactive_winding_designer', 'file') == 2
            fprintf('[GUI-AB] Designer not open. Launching interactive_winding_designer...\n');
            interactive_winding_designer();
            drawnow();
            pause(0.1);
            figs = findall(0, 'Type', 'figure', 'Name', 'Interactive Transformer Design Tool');
        end
    end
    if isempty(figs)
        error('run_gui_cache_ab_test: interactive designer figure not found');
    end
    fig_handle = figs(1);
end

function st = do_one_run(fig_handle, run_btn, geom_cache_on, solver_cache_on, clear_functions)
    if clear_functions
        clear peec_build_geometry peec_solve_frequency
    end

    data = guidata(fig_handle);
    if ~isstruct(data)
        error('run_gui_cache_ab_test: guidata is not a struct');
    end
    if ~isfield(data, 'solve_options') || ~isstruct(data.solve_options)
        data.solve_options = struct();
    end
    data.solve_options.enable_geometry_cache = logical(geom_cache_on);
    data.solve_options.enable_solver_cache = logical(solver_cache_on);
    data.solve_options.lock_standard_targets = true;
    guidata(fig_handle, data);

    close_results_figures();
    invoke_run_callback(run_btn);
    drawnow();

    rf = findall(0, 'Type', 'figure', 'Name', 'Analysis Results');
    if isempty(rf)
        error('run_gui_cache_ab_test: analysis results figure not found after run');
    end
    rf = rf(1);
    st = getappdata(rf, 'results_replot_state');
    if isempty(st) || ~isstruct(st)
        error('run_gui_cache_ab_test: results_replot_state missing');
    end
end

function invoke_run_callback(run_btn)
    cb = get(run_btn, 'Callback');
    if isa(cb, 'function_handle')
        cb(run_btn, []);
        return;
    end
    if ischar(cb)
        eval(cb);
        return;
    end
    error('run_gui_cache_ab_test: unsupported callback type for Run Analysis button');
end

function close_results_figures()
    figs = findall(0, 'Type', 'figure', 'Name', 'Analysis Results');
    for i = 1:numel(figs)
        if ishandle(figs(i))
            close(figs(i));
        end
    end
end

function m = extract_metrics(st)
    m = struct();
    m.runtime_s = get_nested_num(st, {'analysis_meta', 'runtime_s'}, NaN);
    m.total_loss = get_nested_num(st, {'analysis_run', 'total_loss'}, NaN);
    m.Lm_h = get_nested_num(st, {'analysis_run', 'mag_results', 'Lm_H'}, NaN);
    m.Llk_pri_h = get_nested_num(st, {'analysis_run', 'mag_results', 'Llk_pri_H'}, NaN);
    m.stop_reason = get_nested_str(st, {'analysis_meta', 'stop_reason'}, '');
    m.cap_hit = logical(get_nested_num(st, {'analysis_meta', 'cap_hit'}, 0));
    m.mesh_cells = get_nested_num(st, {'analysis_meta', 'mesh_cells'}, NaN);
end

function d = compute_rel_delta(base, other)
    d = struct();
    d.loss = rel_delta(other.total_loss, base.total_loss);
    d.Lm = rel_delta(other.Lm_h, base.Lm_h);
    d.Llk_pri = rel_delta(other.Llk_pri_h, base.Llk_pri_h);
end

function r = rel_delta(x, ref)
    if ~isfinite(x) || ~isfinite(ref)
        r = NaN;
        return;
    end
    r = abs(x - ref) / max(abs(ref), 1e-12);
end

function out = get_nested_num(s, keys, default_val)
    out = default_val;
    cur = s;
    for i = 1:numel(keys)
        k = keys{i};
        if ~isstruct(cur) || ~isfield(cur, k)
            return;
        end
        cur = cur.(k);
    end
    if isnumeric(cur) && isscalar(cur) && isfinite(cur)
        out = double(cur);
    end
end

function out = get_nested_str(s, keys, default_val)
    out = default_val;
    cur = s;
    for i = 1:numel(keys)
        k = keys{i};
        if ~isstruct(cur) || ~isfield(cur, k)
            return;
        end
        cur = cur.(k);
    end
    if ischar(cur)
        out = cur;
        return;
    end
    if exist('isstring', 'builtin') || exist('isstring', 'file')
        if isstring(cur)
            out = char(cur);
        end
    end
end

function r = safe_ratio(a, b)
    if ~isfinite(a) || ~isfinite(b) || b <= 0
        r = NaN;
        return;
    end
    r = a / b;
end

function normalize_phase3_paths_for_gui_ab()
    % Replace common relative addpath entries with absolute ones so
    % temporary cwd changes during python calls do not invalidate load_path.
    here = fileparts(mfilename('fullpath'));           % .../PEEC_Script/validation
    root = fileparts(here);                            % .../PEEC_Script
    val = here;
    reg = fullfile(here, 'regression');

    warn_state = warning('query', 'all');
    warning('off', 'all');
    cleaner = onCleanup(@() warning(warn_state)); %#ok<NASGU>

    rel = { ...
        'PEEC_Script', ...
        'PEEC_Script/validation', ...
        'PEEC_Script\validation', ...
        'PEEC_Script/validation/regression', ...
        'PEEC_Script\validation\regression' ...
    };
    for i = 1:numel(rel)
        try
            rmpath(rel{i});
        catch
        end
    end

    addpath(root);
    if exist(val, 'dir')
        addpath(val);
    end
    if exist(reg, 'dir')
        addpath(reg);
    end
end
