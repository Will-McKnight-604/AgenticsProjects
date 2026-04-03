function profile = profile_runtime(report_input)
%PROFILE_RUNTIME Summarize runtime telemetry from benchmark report.

    if nargin < 1 || isempty(report_input)
        here = fileparts(mfilename('fullpath'));
        report_input = fullfile(here, 'results', 'accuracy_benchmark_latest.json');
    end

    report = load_report(report_input);
    entries = get_struct_field(report, 'entries', struct([]));
    if isempty(entries)
        profile = struct('status', 'empty_report');
        return;
    end

    std_runtime = zeros(numel(entries), 1);
    fast_runtime = zeros(numel(entries), 1);
    ref_runtime = zeros(numel(entries), 1);
    std_unc = zeros(numel(entries), 1);
    std_converged = false(numel(entries), 1);

    for i = 1:numel(entries)
        std_runtime(i) = get_nested_numeric(entries(i), {'standard', 'runtime_s'}, NaN);
        fast_runtime(i) = get_nested_numeric(entries(i), {'fast', 'runtime_s'}, NaN);
        ref_runtime(i) = get_nested_numeric(entries(i), {'reference', 'runtime_s'}, NaN);
        std_unc(i) = get_nested_numeric(entries(i), {'standard', 'uncertainty_pct'}, NaN);
        std_converged(i) = logical(get_nested_numeric(entries(i), {'standard', 'converged'}, 0));
    end

    profile = struct();
    profile.generated_at = datestr(now, 30);
    profile.case_count = numel(entries);
    profile.runtime = struct();
    profile.runtime.fast_median_s = median_no_nan(fast_runtime);
    profile.runtime.standard_median_s = median_no_nan(std_runtime);
    profile.runtime.reference_median_s = median_no_nan(ref_runtime);
    profile.runtime.standard_p95_s = percentile_no_nan(std_runtime, 95);
    profile.runtime.standard_vs_fast_ratio = safe_ratio( ...
        profile.runtime.standard_median_s, max(profile.runtime.fast_median_s, 1e-9));
    profile.telemetry = struct();
    profile.telemetry.standard_converged_fraction = mean(double(std_converged));
    profile.telemetry.standard_uncertainty_median_pct = median_no_nan(std_unc);
    profile.telemetry.standard_uncertainty_p95_pct = percentile_no_nan(std_unc, 95);
end

function report = load_report(report_input)
    if isstruct(report_input)
        report = report_input;
        return;
    end
    if ~is_text_like(report_input)
        error('profile_runtime: report_input must be struct or file path');
    end
    report_file = char(report_input);
    if ~exist(report_file, 'file')
        error('profile_runtime: file not found: %s', report_file);
    end
    fid = fopen(report_file, 'r');
    if fid == -1
        error('profile_runtime: cannot read file: %s', report_file);
    end
    raw = fread(fid, '*char')';
    fclose(fid);
    raw = sanitize_json_text(raw);
    report = jsondecode(raw);
end

function p = percentile_no_nan(v, pct)
    p = NaN;
    x = sort(v(isfinite(v)));
    if isempty(x)
        return;
    end
    idx = 1 + (numel(x) - 1) * (pct / 100);
    lo = floor(idx);
    hi = ceil(idx);
    if lo == hi
        p = x(lo);
    else
        alpha = idx - lo;
        p = (1 - alpha) * x(lo) + alpha * x(hi);
    end
end

function m = median_no_nan(v)
    m = NaN;
    x = v(isfinite(v));
    if isempty(x)
        return;
    end
    m = median(x);
end

function r = safe_ratio(a, b)
    r = NaN;
    if ~isfinite(a) || ~isfinite(b) || b == 0
        return;
    end
    r = a / b;
end

function out = get_nested_numeric(root, path_cells, default_val)
    out = default_val;
    cur = root;
    for i = 1:numel(path_cells)
        key = path_cells{i};
        if ~isstruct(cur) || ~isfield(cur, key)
            return;
        end
        cur = cur.(key);
    end
    if isnumeric(cur) && isscalar(cur) && isfinite(cur)
        out = double(cur);
    elseif islogical(cur) && isscalar(cur)
        out = double(cur);
    end
end

function out = get_struct_field(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        out = s.(field_name);
    end
end

function txt = sanitize_json_text(txt)
    if isempty(txt)
        return;
    end
    if double(txt(1)) == 65279
        txt = txt(2:end);
    end
    txt = strtrim(txt);
end

function tf = is_text_like(v)
    tf = ischar(v);
    if tf
        return;
    end
    if exist('isstring', 'builtin') || exist('isstring', 'file')
        tf = isstring(v);
    else
        tf = false;
    end
end
