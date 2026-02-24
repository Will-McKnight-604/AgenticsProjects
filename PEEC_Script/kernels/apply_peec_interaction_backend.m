function y = apply_peec_interaction_backend(backend, v, L_dense)
%APPLY_PEEC_INTERACTION_BACKEND Apply inductive interaction matrix to vector.

    if nargin < 3
        L_dense = [];
    end
    if isempty(v)
        y = v;
        return;
    end
    if ~isstruct(backend) || ~isfield(backend, 'mode')
        y = apply_dense_fallback(L_dense, v);
        return;
    end

    mode_name = lower(strtrim(char(backend.mode)));
    if strcmp(mode_name, 'fft')
        y = apply_fft_backend(backend, v, L_dense);
        return;
    end
    if strcmp(mode_name, 'fmm')
        y = apply_fmm_backend(backend, v, L_dense);
        return;
    end

    y = apply_dense_fallback(L_dense, v);
end

function y = apply_fft_backend(backend, v, L_dense)
    if ~isfield(backend, 'lin_idx') || isempty(backend.lin_idx)
        y = apply_dense_fallback(L_dense, v);
        return;
    end
    if ~isfield(backend, 'nx') || ~isfield(backend, 'ny')
        y = apply_dense_fallback(L_dense, v);
        return;
    end

    nx = backend.nx;
    ny = backend.ny;
    lin = backend.lin_idx(:);
    n_cells = nx * ny;

    try
        acc = accumarray(lin, v(:), [n_cells, 1], @sum, 0);
    catch
        % Fallback loop keeps behavior stable if accumarray is limited.
        acc = complex(zeros(n_cells, 1));
        for k = 1:numel(v)
            acc(lin(k)) = acc(lin(k)) + v(k);
        end
    end
    I_grid = reshape(acc, ny, nx);

    F = ifft2(fft2(I_grid, backend.pad_ny, backend.pad_nx) .* backend.kernel_fft);
    S = F(backend.same_row_start:backend.same_row_end, backend.same_col_start:backend.same_col_end);
    y = S(lin);

    if isfield(backend, 'kernel_self_mean') && isfield(backend, 'self_diag') && ~isempty(backend.self_diag)
        y = y - backend.kernel_self_mean * v(:) + backend.self_diag(:) .* v(:);
    end
end

function y = apply_dense_fallback(L_dense, v)
    if isempty(L_dense)
        error('apply_peec_interaction_backend: dense fallback requested but L_dense is empty');
    end
    y = L_dense * v;
end

function y = apply_fmm_backend(backend, v, L_dense)
    y = [];
    fn = [];

    if isfield(backend, 'matvec_handle') && isa(backend.matvec_handle, 'function_handle')
        fn = backend.matvec_handle;
    elseif isfield(backend, 'provider_name') && ischar(backend.provider_name) && ...
            is_function_available(backend.provider_name)
        fn = str2func(backend.provider_name);
    elseif is_function_available('peec_fmm_matvec')
        fn = @peec_fmm_matvec;
    end

    if isempty(fn)
        y = apply_dense_fallback(L_dense, v);
        return;
    end

    try
        y_try = fn(v(:), backend);
    catch
        y = apply_dense_fallback(L_dense, v);
        return;
    end

    if ~isnumeric(y_try) || numel(y_try) ~= numel(v)
        y = apply_dense_fallback(L_dense, v);
        return;
    end
    y_try = reshape(y_try, [], 1);
    if any(~isfinite(real(y_try))) || any(~isfinite(imag(y_try)))
        y = apply_dense_fallback(L_dense, v);
        return;
    end
    y = y_try;
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
