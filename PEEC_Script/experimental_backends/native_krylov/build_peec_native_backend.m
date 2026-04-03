function out = build_peec_native_backend(options)
%BUILD_PEEC_NATIVE_BACKEND Build native Octave .oct Krylov backend.
%
% Example:
%   out = build_peec_native_backend();
%   out = build_peec_native_backend(struct('force', true, 'openmp', true));

    if nargin < 1 || ~isstruct(options)
        options = struct();
    end

    force_rebuild = get_opt_bool(options, 'force', false);
    want_openmp = get_opt_bool(options, 'openmp', true);
    verbose = get_opt_bool(options, 'verbose', true);

    native_dir = fileparts(mfilename('fullpath'));
    src_file = fullfile(native_dir, 'peec_external_krylov_solve_impl.cc');
    out_file = fullfile(native_dir, 'peec_external_krylov_solve_impl.oct');
    eigen_dir = fullfile(native_dir, 'third_party', 'eigen');

    out = struct();
    out.success = false;
    out.built = false;
    out.openmp_enabled = false;
    out.command = '';
    out.command_log = '';
    out.src_file = src_file;
    out.out_file = out_file;
    out.eigen_dir = eigen_dir;

    if ~exist(src_file, 'file')
        error('build_peec_native_backend: source file not found: %s', src_file);
    end
    if ~exist(eigen_dir, 'dir')
        error('build_peec_native_backend: Eigen include dir not found: %s', eigen_dir);
    end

    if exist(out_file, 'file') && ~force_rebuild
        out.success = true;
        out.built = false;
        if verbose
            fprintf('[NATIVE] Reusing existing backend: %s\n', out_file);
        end
        return;
    end

    if ~has_mkoctfile()
        error(['build_peec_native_backend: mkoctfile not available in this Octave session. ' ...
               'Install Octave development tooling.']);
    end

    cmd_base = sprintf('mkoctfile -std=c++17 -O3 -I"%s" -o "%s" "%s"', ...
        normalize_path(eigen_dir), normalize_path(out_file), normalize_path(src_file));
    cmd_omp = sprintf('mkoctfile -std=c++17 -O3 -fopenmp -I"%s" -o "%s" "%s"', ...
        normalize_path(eigen_dir), normalize_path(out_file), normalize_path(src_file));

    if want_openmp
        [st, log_txt] = system(cmd_omp);
        out.command = cmd_omp;
        out.command_log = log_txt;
        if st == 0
            out.success = true;
            out.built = true;
            out.openmp_enabled = true;
            if verbose
                fprintf('[NATIVE] Built with OpenMP: %s\n', out_file);
            end
            return;
        end
        if verbose
            fprintf('[NATIVE] OpenMP build failed, retrying without OpenMP.\n');
        end
    end

    [st, log_txt] = system(cmd_base);
    out.command = cmd_base;
    out.command_log = log_txt;
    out.openmp_enabled = false;
    out.success = (st == 0);
    out.built = out.success;

    if ~out.success
        error('build_peec_native_backend: build failed.\n%s', log_txt);
    end

    if verbose
        fprintf('[NATIVE] Built (no OpenMP): %s\n', out_file);
    end
end

function tf = has_mkoctfile()
    tf = false;
    [st, ~] = system('mkoctfile --version');
    if st == 0
        tf = true;
        return;
    end
    if (exist('mkoctfile', 'file') == 2) || (exist('mkoctfile', 'builtin') == 5)
        tf = true;
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

function p = normalize_path(p)
    p = strrep(char(p), '\', '/');
end
