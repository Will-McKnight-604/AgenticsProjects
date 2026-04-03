function [x, info] = peec_external_krylov_solve(A_op, b, solver_kind, options, precond, x0)
%PEEC_EXTERNAL_KRYLOV_SOLVE Optional bridge to an external Krylov backend.
%
% Default behavior:
%   - If user provides options.external_impl_name and function exists, call it.
%   - Else if peec_external_krylov_solve_impl exists, call it.
%   - Else throw an error so caller can safely fall back to Octave solvers.
%
% Expected external signature:
%   [x, info] = external_fn(A_op, b, solver_kind, options, precond, x0)
%
% info fields (optional):
%   .flag, .relres, .iter_count, .stop_reason

    x = [];
    info = struct();

    impl_name = '';
    if isstruct(options) && isfield(options, 'external_impl_name')
        v = options.external_impl_name;
        if ischar(v)
            impl_name = strtrim(char(v));
        elseif (exist('isstring', 'builtin') || exist('isstring', 'file')) && isstring(v)
            impl_name = strtrim(char(v));
        end
    end

    if ~isempty(impl_name) && is_function_available(impl_name)
        fn = str2func(impl_name);
        [x, info] = fn(A_op, b, solver_kind, options, precond, x0);
        return;
    end

    if is_function_available('peec_external_krylov_solve_impl')
        [x, info] = peec_external_krylov_solve_impl(A_op, b, solver_kind, options, precond, x0);
        return;
    end

    error('peec_external_krylov_solve:no_backend', ...
        ['No external Krylov backend configured. Provide options.external_impl_name ' ...
         'or add peec_external_krylov_solve_impl.m']);
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
