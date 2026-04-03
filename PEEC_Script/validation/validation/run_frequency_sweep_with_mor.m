function report = run_frequency_sweep_with_mor(geom, conductors, freq_list_hz, sigma, mu0, options)
%RUN_FREQUENCY_SWEEP_WITH_MOR Frequency sweep with POD-based warm starts.
%
% This is a practical MOR scaffold for Octave workflows:
% 1) Solve a small training subset in full order.
% 2) Build POD basis from state snapshots.
% 3) Reuse basis projection as iterative initial guesses in sweep solves.

    if nargin < 6 || ~isstruct(options)
        options = struct();
    end
    freq_list_hz = reshape(freq_list_hz, [], 1);
    if isempty(freq_list_hz)
        error('run_frequency_sweep_with_mor: empty frequency list');
    end

    ensure_local_subdir('validation');
    ensure_local_subdir(fullfile('validation', 'mor'));

    sweep_opts = get_struct(options, 'solve_options', struct());
    train_opts = get_struct(options, 'train_solve_options', sweep_opts);
    if ~isfield(train_opts, 'linear_solver')
        train_opts.linear_solver = 'direct';
    end

    train_freqs = select_training_freqs(freq_list_hz, options);
    n_train = numel(train_freqs);
    n_f = numel(freq_list_hz);

    snapshots = [];
    train_states = cell(n_train, 1);
    train_results = cell(n_train, 1);
    train_map = zeros(n_train, 1);

    for k = 1:n_train
        tf = train_freqs(k);
        idx = find(abs(freq_list_hz - tf) < 1e-9 * max(abs(tf), 1), 1, 'first');
        if isempty(idx)
            idx = nearest_idx(freq_list_hz, tf);
        end
        train_map(k) = idx;

        r = peec_solve_frequency(geom, conductors, tf, sigma, mu0, train_opts);
        xk = [r.I_fil(:); r.lambda(:)];
        snapshots(:, k) = xk; %#ok<AGROW>
        train_states{k} = xk;
        train_results{k} = summarize_result(r, tf, true);
    end

    pod_opts = get_struct(options, 'pod_options', struct());
    if ~isfield(pod_opts, 'rank')
        pod_opts.rank = max(0, round(get_opt_num(options, 'mor_rank', 0)));
    end
    pod = build_pod_basis(snapshots, pod_opts);

    entries = repmat(struct(), n_f, 1);
    prev_state = [];
    for i = 1:n_f
        f = freq_list_hz(i);
        solve_i = sweep_opts;

        if get_opt_bool(options, 'enable_mor_warmstart', true)
            seed = [];
            tpos = find(train_map == i, 1, 'first');
            if ~isempty(tpos)
                seed = train_states{tpos};
            elseif ~isempty(prev_state)
                seed = prev_state;
            else
                near_t = nearest_idx(train_freqs, f);
                seed = train_states{near_t};
            end
            solve_i.mor_basis = pod.V;
            solve_i.mor_seed_state = seed;
        end

        t = tic;
        r = peec_solve_frequency(geom, conductors, f, sigma, mu0, solve_i);
        elapsed = toc(t);
        prev_state = [r.I_fil(:); r.lambda(:)];
        s_i = summarize_result(r, f, false);
        s_i.wall_runtime_s = elapsed;
        entries(i) = s_i;
    end

    report = struct();
    report.generated_at = datestr(now, 30);
    report.frequency_hz = freq_list_hz;
    report.training_frequency_hz = train_freqs;
    report.training_case_indices = train_map;
    report.training_results = [train_results{:}];
    report.pod = struct('rank', pod.rank, 'energy_kept', pod.energy_kept);
    report.entries = entries;
end

function idx = nearest_idx(v, x)
    [~, idx] = min(abs(v(:) - x));
end

function tfreq = select_training_freqs(freq_list_hz, options)
    if isfield(options, 'mor_training_freqs_hz')
        cand = options.mor_training_freqs_hz;
        if isnumeric(cand) && ~isempty(cand)
            tfreq = unique(cand(:));
            return;
        end
    end

    n = numel(freq_list_hz);
    k = max(2, round(get_opt_num(options, 'training_count', min(5, n))));
    k = min(k, n);
    idx = unique(round(linspace(1, n, k)));
    tfreq = freq_list_hz(idx);
end

function s = summarize_result(r, f, is_training)
    s = struct();
    s.frequency_hz = f;
    s.is_training = logical(is_training);
    s.total_copper_loss_w = get_num(r, 'P_total', NaN);
    s.runtime_s = get_nested_num(r, {'meta', 'runtime_s'}, NaN);
    s.wall_runtime_s = NaN;
    s.linear_solver_used = get_nested_str(r, {'meta', 'linear_solver_used'}, 'unknown');
    s.matrix_mode_used = get_nested_str(r, {'meta', 'matrix_mode_used'}, 'unknown');
    s.stop_reason = get_nested_str(r, {'meta', 'stop_reason'}, 'unknown');
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

function out = get_nested_num(root, path_cells, default_val)
    out = default_val;
    cur = root;
    for i = 1:numel(path_cells)
        if ~isstruct(cur) || ~isfield(cur, path_cells{i})
            return;
        end
        cur = cur.(path_cells{i});
    end
    if isnumeric(cur) && isscalar(cur) && isfinite(cur)
        out = double(cur);
    end
end

function out = get_nested_str(root, path_cells, default_val)
    out = default_val;
    cur = root;
    for i = 1:numel(path_cells)
        if ~isstruct(cur) || ~isfield(cur, path_cells{i})
            return;
        end
        cur = cur.(path_cells{i});
    end
    if ischar(cur)
        out = char(cur);
        return;
    end
    if (exist('isstring', 'builtin') || exist('isstring', 'file')) && isstring(cur)
        out = char(cur);
    end
end

function out = get_struct(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name) && isstruct(s.(field_name))
        out = s.(field_name);
    end
end

function out = get_opt_num(options, field_name, default_val)
    out = default_val;
    if isstruct(options) && isfield(options, field_name)
        v = options.(field_name);
        if isnumeric(v) && isscalar(v) && isfinite(v)
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
