function report = check_native_backend(options)
%CHECK_NATIVE_BACKEND Smoke test for peec_external_krylov_solve_impl.
%
% Example:
%   report = check_native_backend();
%   report = check_native_backend(struct('auto_build', true));

    if nargin < 1 || ~isstruct(options)
        options = struct();
    end

    auto_build = get_opt_bool(options, 'auto_build', true);
    verbose = get_opt_bool(options, 'verbose', true);
    solver_kind = get_opt_string(options, 'solver_kind', 'bicgstab');

    report = struct();
    report.generated_at = datestr(now, 30);
    report.auto_build = auto_build;
    report.backend_found = false;
    report.backend_path = '';
    report.build = struct();
    report.solve = struct();
    report.pass = false;

    native_dir = fileparts(mfilename('fullpath'));
    addpath(native_dir);

    backend_name = 'peec_external_krylov_solve_impl';
    backend_path = which(backend_name);
    if isempty(backend_path) && auto_build
        report.build = build_peec_native_backend(struct('force', false, 'openmp', true, 'verbose', verbose));
        backend_path = which(backend_name);
    end

    report.backend_found = ~isempty(backend_path);
    report.backend_path = backend_path;
    if ~report.backend_found
        if verbose
            fprintf('[NATIVE] Backend not found after build attempt.\n');
        end
        return;
    end

    n = max(32, round(get_opt_num(options, 'test_size', 96)));
    rng_seed = round(get_opt_num(options, 'rng_seed', 17));
    try
        rng(rng_seed, 'twister');
    catch
        rand('seed', rng_seed); %#ok<RAND>
    end

    d = 2.0 + rand(n, 1);
    A = spdiags(d, 0, n, n);
    A = A + 0.02 * sprandn(n, n, 0.01);
    A = A + A';
    A = A + 0.5 * speye(n);
    b = randn(n, 1) + 1j * randn(n, 1);
    x0 = zeros(n, 1);

    opts = struct('tol', 1e-8, 'maxit', 300, 'restart', 30, 'matrix_mode', 'dense');
    pre = struct('M1', spdiags(diag(A), 0, n, n), 'M2', []);

    t0 = tic;
    [x, info] = feval(backend_name, A, b, solver_kind, opts, pre, x0);
    dt = toc(t0);

    res = norm(A * x - b) / max(norm(b), 1e-12);
    flag = get_struct_numeric(info, 'flag', 99);
    relres = get_struct_numeric(info, 'relres', NaN);
    iters = get_struct_numeric(info, 'iter_count', NaN);
    stop_reason = get_struct_string(info, 'stop_reason', '');

    report.solve.runtime_s = dt;
    report.solve.flag = flag;
    report.solve.relres = relres;
    report.solve.iter_count = iters;
    report.solve.stop_reason = stop_reason;
    report.solve.residual_norm_rel = res;
    report.solve.preconditioner_kind = get_struct_string(info, 'preconditioner_kind', '');
    report.pass = (flag == 0) && isfinite(res) && (res <= 1e-6);

    if verbose
        fprintf('[NATIVE] Solve flag=%d relres=%.3e residual=%.3e iter=%.0f pass=%d\n', ...
            flag, relres, res, iters, double(report.pass));
    end
end

function out = get_opt_bool(s, field_name, default_val)
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

function out = get_opt_num(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if isnumeric(v) && isscalar(v) && isfinite(v)
            out = double(v);
        end
    end
end

function out = get_opt_string(s, field_name, default_val)
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
