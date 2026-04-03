function diag = extract_benchmark_diagnostics(baseline_json, candidate_json, out_csv)
%EXTRACT_BENCHMARK_DIAGNOSTICS Compare case-level benchmark diagnostics.
%
% Inputs:
%   baseline_json  : path to baseline benchmark report JSON
%   candidate_json : path to candidate benchmark report JSON
%   out_csv        : optional CSV output path
%
% Output:
%   diag struct containing rows + summary metrics

    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(baseline_json)
        baseline_json = fullfile(here, 'results_real', 'accuracy_benchmark_20260220_172052.json');
    end
    if nargin < 2 || isempty(candidate_json)
        candidate_json = fullfile(here, 'results_real', 'accuracy_benchmark_real_latest.json');
    end
    if nargin < 3
        out_csv = '';
    end

    b = load_json_file(baseline_json);
    c = load_json_file(candidate_json);

    rows = build_rows(b, c);
    diag = struct();
    diag.generated_at = datestr(now, 30);
    diag.baseline_json = baseline_json;
    diag.candidate_json = candidate_json;
    diag.rows = rows;
    diag.summary = build_summary(rows);

    print_rows(rows);
    print_summary(diag.summary);

    if ~isempty(out_csv)
        write_rows_csv(rows, out_csv);
        fprintf('[DIAG] Wrote CSV: %s\n', out_csv);
    end
end

function rows = build_rows(base_report, cand_report)
    rows = struct([]);
    if ~isfield(base_report, 'entries') || ~isfield(cand_report, 'entries')
        return;
    end

    b_entries = base_report.entries;
    c_entries = cand_report.entries;
    for i = 1:numel(c_entries)
        cid = get_struct_string(c_entries(i), 'case_id', '');
        j = find_entry_by_case_id(b_entries, cid);
        if j <= 0
            continue;
        end

        b_fast = get_struct_field(b_entries(j), 'fast', struct());
        c_fast = get_struct_field(c_entries(i), 'fast', struct());
        c_fast_t = get_struct_field(c_fast, 'timing_breakdown', struct());

        r = struct();
        r.case_id = cid;
        r.fast_runtime_baseline_s = get_struct_numeric(b_fast, 'runtime_s', NaN);
        r.fast_runtime_candidate_s = get_struct_numeric(c_fast, 'runtime_s', NaN);
        r.fast_runtime_delta_pct = 100 * safe_rel_delta(r.fast_runtime_baseline_s, r.fast_runtime_candidate_s);
        r.fast_solver = get_struct_string(c_fast, 'linear_solver_used', 'unknown');
        r.fast_preconditioner = get_struct_string(c_fast, 'preconditioner_used', 'none');
        r.fast_stop_reason = get_struct_string(c_fast, 'stop_reason', 'unknown');
        r.fast_iter_relres = get_struct_numeric(c_fast, 'iter_relres', NaN);
        r.fast_iter_count = get_struct_numeric(c_fast, 'iter_count', NaN);
        r.fast_warning = to_logical(get_struct_numeric(c_fast, 'had_solver_warning', 0), false);
        r.fast_warning_kind = get_struct_string(c_fast, 'warning_kind', '');
        r.fast_quality_gate_passed = to_logical(get_struct_numeric(c_fast, 'iter_quality_gate_passed', 1), true);
        r.fast_iter_rejected_reason = get_struct_string(c_fast, 'iter_rejected_reason', '');
        r.fast_mesh_s = get_struct_numeric(c_fast_t, 'mesh_build_s', NaN);
        r.fast_solve_s = get_struct_numeric(c_fast_t, 'linear_solve_s', NaN);
        r.fast_fft_used = to_logical(get_struct_numeric(c_fast, 'fft_used', 0), false);

        c_err_fast = get_struct_field(c_entries(i), 'error_fast', struct());
        r.fast_loss_err_pct = 100 * get_struct_numeric(c_err_fast, 'loss_rel', NaN);

        rows = [rows; r]; %#ok<AGROW>
    end
end

function summary = build_summary(rows)
    summary = struct();
    if isempty(rows)
        summary.note = 'No matching cases between reports';
        return;
    end

    d = [rows.fast_runtime_delta_pct];
    e = [rows.fast_loss_err_pct];
    warn = [rows.fast_warning];
    qpass = [rows.fast_quality_gate_passed];
    fftu = [rows.fast_fft_used];

    summary.case_count = numel(rows);
    summary.median_fast_runtime_delta_pct = median_no_nan(d);
    summary.mean_fast_runtime_delta_pct = mean_no_nan(d);
    summary.max_fast_loss_err_pct = max_no_nan(e);
    summary.warning_fraction = mean(double(warn));
    summary.quality_reject_fraction = mean(double(~qpass));
    summary.fft_used_fraction = mean(double(fftu));
end

function print_rows(rows)
    if isempty(rows)
        fprintf('[DIAG] No rows to display.\n');
        return;
    end
    fprintf('[DIAG] Case-level runtime delta (fast):\n');
    for i = 1:numel(rows)
        fprintf('  - %s | delta=%+.2f%% | solver=%s | stop=%s | relres=%.3g | loss_err=%.3f%%\n', ...
            rows(i).case_id, rows(i).fast_runtime_delta_pct, rows(i).fast_solver, ...
            rows(i).fast_stop_reason, rows(i).fast_iter_relres, rows(i).fast_loss_err_pct);
    end
end

function print_summary(s)
    if ~isstruct(s) || isfield(s, 'note')
        fprintf('[DIAG] %s\n', get_struct_string(s, 'note', 'No summary'));
        return;
    end
    fprintf('[DIAG] Summary: cases=%d | median_delta=%+.2f%% | mean_delta=%+.2f%% | max_loss_err=%.3f%% | warning_frac=%.2f | reject_frac=%.2f | fft_used_frac=%.2f\n', ...
        s.case_count, s.median_fast_runtime_delta_pct, s.mean_fast_runtime_delta_pct, ...
        s.max_fast_loss_err_pct, s.warning_fraction, s.quality_reject_fraction, s.fft_used_fraction);
end

function write_rows_csv(rows, out_csv)
    fid = fopen(out_csv, 'w');
    if fid == -1
        error('extract_benchmark_diagnostics: cannot write %s', out_csv);
    end
    cleaner = @(x) regexprep(char(x), '[,\"]', '_');
    fprintf(fid, 'case_id,fast_runtime_baseline_s,fast_runtime_candidate_s,fast_runtime_delta_pct,fast_solver,fast_preconditioner,fast_stop_reason,fast_iter_relres,fast_iter_count,fast_warning,fast_warning_kind,fast_quality_gate_passed,fast_iter_rejected_reason,fast_mesh_s,fast_solve_s,fast_fft_used,fast_loss_err_pct\n');
    for i = 1:numel(rows)
        fprintf(fid, '%s,%.9g,%.9g,%.9g,%s,%s,%s,%.9g,%.9g,%d,%s,%d,%s,%.9g,%.9g,%d,%.9g\n', ...
            cleaner(rows(i).case_id), rows(i).fast_runtime_baseline_s, rows(i).fast_runtime_candidate_s, rows(i).fast_runtime_delta_pct, ...
            cleaner(rows(i).fast_solver), cleaner(rows(i).fast_preconditioner), cleaner(rows(i).fast_stop_reason), ...
            rows(i).fast_iter_relres, rows(i).fast_iter_count, double(rows(i).fast_warning), cleaner(rows(i).fast_warning_kind), ...
            double(rows(i).fast_quality_gate_passed), cleaner(rows(i).fast_iter_rejected_reason), ...
            rows(i).fast_mesh_s, rows(i).fast_solve_s, double(rows(i).fast_fft_used), rows(i).fast_loss_err_pct);
    end
    fclose(fid);
end

function idx = find_entry_by_case_id(entries, case_id)
    idx = 0;
    for i = 1:numel(entries)
        if strcmp(get_struct_string(entries(i), 'case_id', ''), case_id)
            idx = i;
            return;
        end
    end
end

function obj = load_json_file(in_file)
    fid = fopen(in_file, 'r');
    if fid == -1
        error('extract_benchmark_diagnostics: cannot open %s', in_file);
    end
    raw = fread(fid, '*char')';
    fclose(fid);
    if ~isempty(raw) && double(raw(1)) == 65279
        raw = raw(2:end);
    end
    obj = jsondecode(strtrim(raw));
end

function r = safe_rel_delta(old_v, new_v)
    r = NaN;
    if ~isfinite(old_v) || ~isfinite(new_v) || old_v == 0
        return;
    end
    r = (new_v - old_v) / old_v;
end

function m = median_no_nan(v)
    m = NaN;
    x = v(isfinite(v));
    if isempty(x)
        return;
    end
    m = median(x);
end

function m = mean_no_nan(v)
    m = NaN;
    x = v(isfinite(v));
    if isempty(x)
        return;
    end
    m = mean(x);
end

function m = max_no_nan(v)
    m = NaN;
    x = v(isfinite(v));
    if isempty(x)
        return;
    end
    m = max(x);
end

function out = get_struct_numeric(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if isnumeric(v) && isscalar(v) && isfinite(v)
            out = double(v);
        elseif islogical(v) && isscalar(v)
            out = double(v);
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

function out = get_struct_field(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        out = s.(field_name);
    end
end

function tf = to_logical(v, default_val)
    tf = default_val;
    if islogical(v) && isscalar(v)
        tf = v;
    elseif isnumeric(v) && isscalar(v)
        tf = (v ~= 0);
    end
end
