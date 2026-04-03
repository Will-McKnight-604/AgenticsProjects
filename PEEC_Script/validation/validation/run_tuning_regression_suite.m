function report = run_tuning_regression_suite(case_dir)
%RUN_TUNING_REGRESSION_SUITE Targeted regression checks for tuning changes.
%
% Checks:
%   1) Outlier accuracy guard for real_case_11 and real_case_12
%   2) Iterative solver quality-gate path engages on case_03
%   3) FFT eligibility telemetry is present on synthetic geometries

    ensure_local_paths();

    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(case_dir)
        case_dir = fullfile(here, 'mas_cases_real');
    end

    report = struct();
    report.generated_at = datestr(now, 30);
    report.case_dir = case_dir;

    outlier_cases = { ...
        'real_case_11_tsf_case_11.json', ...
        'real_case_12_tsf_case_12.json' ...
    };

    fast_opts = solver_option_profile('fast');
    high_opts = solver_option_profile('high');

    outlier_rows = struct([]);
    for i = 1:numel(outlier_cases)
        case_path = fullfile(case_dir, outlier_cases{i});
        clear_phase3_runtime_caches();
        r_high = execute_mas_case(case_path, high_opts);
        clear_phase3_runtime_caches();
        r_fast = execute_mas_case(case_path, fast_opts);

        loss_err_pct = 100 * abs(r_fast.total_copper_loss_w - r_high.total_copper_loss_w) / max(abs(r_high.total_copper_loss_w), 1e-12);
        row = struct();
        row.case_id = r_fast.case_id;
        row.loss_error_pct = loss_err_pct;
        row.pass = (loss_err_pct <= 30.0);
        row.fast_solver = r_fast.linear_solver_used;
        row.fast_iter_relres = r_fast.iter_relres;
        row.fast_quality_gate_passed = get_struct_bool(r_fast, 'iter_quality_gate_passed', true);
        outlier_rows = [outlier_rows; row]; %#ok<AGROW>
    end
    report.outlier_rows = outlier_rows;

    case03 = fullfile(case_dir, 'real_case_03_tsf_case_03.json');
    iter_opts = solver_option_profile('fast');
    iter_opts.linear_solver = 'bicgstab';
    iter_opts.matrix_mode = 'dense';
    iter_opts.interaction_backend = 'dense';
    iter_opts.enable_solver_cache = false;
    iter_opts.preconditioner = 'ilu_sparse_drop';
    iter_opts.iter_tol = 1e-2;
    iter_opts.iter_maxit = 300;
    clear_phase3_runtime_caches();
    r_iter = execute_mas_case(case03, iter_opts);

    report.iterative_path = struct();
    report.iterative_path.case_id = r_iter.case_id;
    report.iterative_path.linear_solver_used = r_iter.linear_solver_used;
    report.iterative_path.iter_relres = r_iter.iter_relres;
    report.iterative_path.iter_quality_gate_passed = get_struct_bool(r_iter, 'iter_quality_gate_passed', false);
    report.iterative_path.stop_reason = get_struct_string(get_struct_field(r_iter, 'solve_meta', struct()), 'stop_reason', 'unknown');

    fft_report = run_fft_backend_benchmark();
    report.backend_checks = get_struct_field(fft_report, 'summary', struct());

    outlier_pass = all(arrayfun(@(r) r.pass, outlier_rows));
    iter_pass = report.iterative_path.iter_quality_gate_passed;
    backend_pass = get_struct_bool(report.backend_checks, 'pass', false);
    report.pass = outlier_pass && iter_pass && backend_pass;

    fprintf('[REG] Outlier checks pass: %d | Iterative-path pass: %d | FFT pass: %d | Overall pass: %d\n', ...
        double(outlier_pass), double(iter_pass), double(backend_pass), double(report.pass));
end

function ensure_local_paths()
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(root);
    addpath(here);
    addpath(fullfile(root, 'mesh'));
    addpath(fullfile(root, 'physics'));
    addpath(fullfile(root, 'corrections'));
    addpath(fullfile(root, 'kernels'));
    addpath(fullfile(root, 'kernels', 'native'));
    addpath(fullfile(root, 'litz'));
end

function out = get_struct_field(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        out = s.(field_name);
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
