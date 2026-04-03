function backend = build_peec_interaction_backend(filaments_core, mu0, near_floor, solve_options, L_dense)
%BUILD_PEEC_INTERACTION_BACKEND Prepare dense/FFT/FMM interaction metadata.
%
% backend.mode:
%   - 'dense': dense matrix-vector multiplication.
%   - 'fft':   FFT convolution on uniform filament-center grids.
%   - 'fmm':   external FMM matvec provider (optional).

    if nargin < 5
        L_dense = [];
    end

    backend = struct();
    backend.mode = 'dense';
    backend.requested = lower(strtrim(get_opt_string(solve_options, 'interaction_backend', 'auto')));
    backend.reason = 'default_dense';
    backend.near_floor = near_floor;
    backend.mu0 = mu0;
    backend.L_diag = [];
    backend.fft_eligible = false;
    backend.fmm_eligible = false;
    backend.estimated_speedup = NaN;

    if ~isempty(L_dense)
        backend.L_diag = diag(L_dense);
    else
        dx = max(filaments_core(:, 3), 1e-12);
        dy = max(filaments_core(:, 4), 1e-12);
        req = max(0.2235 * (dx + dy), near_floor);
        backend.L_diag = mu0 / (2 * pi) * log(1 ./ req);
    end

    req_backend = backend.requested;
    if isempty(req_backend)
        req_backend = 'auto';
    end
    if ~any(strcmp(req_backend, {'auto', 'dense', 'fft', 'fmm'}))
        req_backend = 'auto';
    end
    if strcmp(req_backend, 'dense')
        backend.reason = 'requested_dense';
        return;
    end

    [fft_backend, fft_ok, fft_reason] = try_build_fft_backend(filaments_core, mu0, near_floor, backend.L_diag);
    [fmm_backend, fmm_ok, fmm_reason] = try_build_fmm_backend(filaments_core, mu0, near_floor, backend.L_diag, solve_options);

    backend.fft_eligible = fft_ok;
    backend.fmm_eligible = fmm_ok;

    if strcmp(req_backend, 'fft')
        if fft_ok
            backend = merge_structs(backend, fft_backend);
            backend.mode = 'fft';
            backend.reason = 'requested_fft';
            return;
        end
        backend.reason = ['fft_fallback_dense:' fft_reason];
        return;
    end

    if strcmp(req_backend, 'fmm')
        if fmm_ok
            backend = merge_structs(backend, fmm_backend);
            backend.mode = 'fmm';
            backend.reason = 'requested_fmm';
            return;
        end
        backend.reason = ['fmm_fallback_dense:' fmm_reason];
        return;
    end

    % Auto policy: select only when estimated gain clears guard.
    fft_accept = false;
    fft_auto_reason = fft_reason;
    fft_speedup = -inf;
    if fft_ok
        [fft_accept, fft_auto_reason, fft_speedup, fft_backend] = passes_fft_auto_policy(fft_backend, filaments_core, solve_options);
    end

    fmm_accept = false;
    fmm_auto_reason = fmm_reason;
    fmm_speedup = -inf;
    if fmm_ok
        [fmm_accept, fmm_auto_reason, fmm_speedup, fmm_backend] = passes_fmm_auto_policy(fmm_backend, filaments_core, solve_options);
    end

    if fft_accept && (~fmm_accept || (fft_speedup >= fmm_speedup))
        backend = merge_structs(backend, fft_backend);
        backend.mode = 'fft';
        backend.reason = ['auto_fft:' fft_auto_reason];
        backend.estimated_speedup = fft_speedup;
        return;
    end

    if fmm_accept
        backend = merge_structs(backend, fmm_backend);
        backend.mode = 'fmm';
        backend.reason = ['auto_fmm:' fmm_auto_reason];
        backend.estimated_speedup = fmm_speedup;
        return;
    end

    backend.reason = ['auto_dense:fft=' fft_auto_reason ';fmm=' fmm_auto_reason];
end

function [b, ok, reason] = try_build_fft_backend(filaments_core, mu0, near_floor, L_diag)
    b = struct();
    ok = false;
    reason = 'unknown';

    if isempty(filaments_core) || size(filaments_core, 2) < 4
        reason = 'invalid_filament_core';
        return;
    end

    x = filaments_core(:, 1);
    y = filaments_core(:, 2);
    dx = max(filaments_core(:, 3), 1e-12);
    dy = max(filaments_core(:, 4), 1e-12);
    Nf = size(filaments_core, 1);

    if Nf < 16
        reason = 'too_few_filaments';
        return;
    end

    ux = unique(sort(x));
    uy = unique(sort(y));
    nx = numel(ux);
    ny = numel(uy);
    if nx < 2 || ny < 2
        reason = 'insufficient_grid_extent';
        return;
    end

    dxg = diff(ux);
    dyg = diff(uy);
    hx = median(dxg);
    hy = median(dyg);
    tol_x = max(1e-12, abs(hx) * 1e-6);
    tol_y = max(1e-12, abs(hy) * 1e-6);
    if any(abs(dxg - hx) > tol_x) || any(abs(dyg - hy) > tol_y) || hx <= 0 || hy <= 0
        reason = 'nonuniform_grid_spacing';
        return;
    end

    col_idx = round((x - ux(1)) / hx) + 1;
    row_idx = round((y - uy(1)) / hy) + 1;
    if any(col_idx < 1) || any(col_idx > nx) || any(row_idx < 1) || any(row_idx > ny)
        reason = 'index_out_of_bounds';
        return;
    end

    x_back = ux(1) + (col_idx - 1) * hx;
    y_back = uy(1) + (row_idx - 1) * hy;
    if max(abs(x - x_back)) > max(1e-11, abs(hx) * 1e-5) || ...
       max(abs(y - y_back)) > max(1e-11, abs(hy) * 1e-5)
        reason = 'point_mapping_tolerance_fail';
        return;
    end

    kx = 2 * nx - 1;
    ky = 2 * ny - 1;
    gx = ((1:kx) - nx) * hx;
    gy = ((1:ky) - ny) * hy;
    [GX, GY] = meshgrid(gx, gy);
    sigma2 = mean((dx.^2 + dy.^2) / 6);
    r_eff = sqrt(GX.^2 + GY.^2 + sigma2 + near_floor^2);
    kernel = mu0 / (2 * pi) * log(1 ./ max(r_eff, near_floor));

    self_mean = mean(L_diag);
    kernel(ny, nx) = self_mean;

    pad_nx = 2 ^ nextpow2(nx + kx - 1);
    pad_ny = 2 ^ nextpow2(ny + ky - 1);

    b = struct();
    b.nx = nx;
    b.ny = ny;
    b.hx = hx;
    b.hy = hy;
    b.ux0 = ux(1);
    b.uy0 = uy(1);
    b.row_idx = row_idx(:);
    b.col_idx = col_idx(:);
    b.lin_idx = sub2ind([ny, nx], b.row_idx, b.col_idx);
    b.pad_nx = pad_nx;
    b.pad_ny = pad_ny;
    b.kernel_fft = fft2(kernel, pad_ny, pad_nx);
    b.same_row_start = floor(ky / 2) + 1;
    b.same_row_end = b.same_row_start + ny - 1;
    b.same_col_start = floor(kx / 2) + 1;
    b.same_col_end = b.same_col_start + nx - 1;
    b.kernel_self_mean = self_mean;
    b.self_diag = L_diag(:);
    b.estimated_speedup = NaN;
    ok = true;
    reason = 'fft_uniform_grid';
end

function [accept, reason, est_speedup, b] = passes_fft_auto_policy(b, filaments_core, solve_options)
    accept = false;
    reason = 'fft_policy_reject';
    Nf = size(filaments_core, 1);

    min_nf = max(1, round(get_opt_num(solve_options, 'fft_auto_min_nf', 900)));
    if Nf < min_nf
        reason = 'nf_below_fft_min';
        est_speedup = 0;
        b.estimated_speedup = est_speedup;
        return;
    end

    pad = double(b.pad_nx) * double(b.pad_ny);
    pad_ratio = pad / max(1, double(Nf));
    max_pad_ratio = max(1.0, get_opt_num(solve_options, 'fft_auto_max_pad_ratio', 16.0));
    if pad_ratio > max_pad_ratio
        reason = 'fft_padding_overhead_too_high';
        est_speedup = 0;
        b.estimated_speedup = est_speedup;
        return;
    end

    ops_dense = double(Nf) * double(Nf);
    ops_fft = pad * max(1.0, log2(max(pad, 2.0)));
    est_speedup = ops_dense / max(ops_fft, 1.0);

    min_speedup = max(1.0, get_opt_num(solve_options, 'fft_auto_min_estimated_speedup', 1.15));
    if est_speedup < min_speedup
        reason = 'fft_estimated_speedup_below_gate';
        b.estimated_speedup = est_speedup;
        return;
    end

    accept = true;
    reason = 'fft_policy_accept';
    b.estimated_speedup = est_speedup;
end

function [b, ok, reason] = try_build_fmm_backend(filaments_core, mu0, near_floor, L_diag, solve_options)
    b = struct();
    ok = false;
    reason = 'fmm_provider_unavailable';

    provider = lower(strtrim(get_opt_string(solve_options, 'fmm_provider', 'auto')));
    fn = [];
    fn_name = '';

    if isstruct(solve_options) && isfield(solve_options, 'fmm_matvec_handle') && isa(solve_options.fmm_matvec_handle, 'function_handle')
        fn = solve_options.fmm_matvec_handle;
        fn_name = 'fmm_matvec_handle';
    end

    if isempty(fn)
        if ~isempty(provider) && ~strcmp(provider, 'auto') && is_function_available(provider)
            fn = str2func(provider);
            fn_name = provider;
        elseif is_function_available('peec_fmm_matvec')
            fn = @peec_fmm_matvec;
            fn_name = 'peec_fmm_matvec';
        end
    end

    if isempty(fn)
        return;
    end

    b = struct();
    b.mode = 'fmm';
    b.provider_name = fn_name;
    b.matvec_handle = fn;
    b.filaments_core = filaments_core;
    b.mu0 = mu0;
    b.near_floor = near_floor;
    b.self_diag = L_diag(:);
    b.kernel_self_mean = mean(L_diag);
    b.external = true;
    b.estimated_speedup = NaN;
    ok = true;
    reason = 'fmm_external_provider';
end

function [accept, reason, est_speedup, b] = passes_fmm_auto_policy(b, filaments_core, solve_options)
    accept = false;
    reason = 'fmm_policy_reject';
    Nf = size(filaments_core, 1);

    min_nf = max(1, round(get_opt_num(solve_options, 'fmm_auto_min_nf', 2500)));
    if Nf < min_nf
        reason = 'nf_below_fmm_min';
        est_speedup = 0;
        b.estimated_speedup = est_speedup;
        return;
    end

    % Conservative estimate: O(N log N) FMM vs O(N^2) dense.
    est_speedup = double(Nf) / max(log2(max(double(Nf), 2.0)), 1.0);
    accept = true;
    reason = 'fmm_policy_accept';
    b.estimated_speedup = est_speedup;
end

function out = get_opt_string(options, field_name, default_val)
    out = default_val;
    if ~isstruct(options) || ~isfield(options, field_name)
        return;
    end
    v = options.(field_name);
    if ischar(v)
        out = char(v);
        return;
    end
    if (exist('isstring', 'builtin') || exist('isstring', 'file')) && isstring(v)
        out = char(v);
    end
end

function out = get_opt_num(options, field_name, default_val)
    out = default_val;
    if ~isstruct(options) || ~isfield(options, field_name)
        return;
    end
    v = options.(field_name);
    if isnumeric(v) && isscalar(v) && isfinite(v)
        out = double(v);
    end
end

function out = merge_structs(a, b)
    out = a;
    if ~isstruct(b)
        return;
    end
    f = fieldnames(b);
    for i = 1:numel(f)
        out.(f{i}) = b.(f{i});
    end
end

function tf = is_function_available(name_in)
    tf = false;
    if nargin < 1 || isempty(name_in)
        return;
    end
    e_file = exist(name_in, 'file');
    e_builtin = exist(name_in, 'builtin');
    tf = (e_file == 2) || (e_file == 3) || (e_builtin == 5);
end
