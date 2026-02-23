function snap = freeze_baseline_snapshot(ab_summary_json, out_dir)
%FREEZE_BASELINE_SNAPSHOT Archive baseline/tuned summary with timestamp.
%
% Example:
%   snap = freeze_baseline_snapshot();

    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(ab_summary_json)
        ab_summary_json = fullfile(here, 'results_real_ab', 'ab_summary_latest.json');
    end
    if nargin < 2 || isempty(out_dir)
        out_dir = fullfile(here, 'results_real_ab', 'frozen_baselines');
    end
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

    if ~exist(ab_summary_json, 'file')
        if exist('run_real_ab_benchmark', 'file') == 2 || exist('run_real_ab_benchmark', 'builtin') == 5
            fprintf('[BASELINE] Missing A/B summary. Running run_real_ab_benchmark(3) to generate baseline snapshot.\n');
            run_real_ab_benchmark(3);
        end
    end
    if ~exist(ab_summary_json, 'file')
        error('freeze_baseline_snapshot: missing file after generation attempt: %s', ab_summary_json);
    end

    src_txt = read_text_file(ab_summary_json);
    obj = jsondecode(src_txt);

    stamp = datestr(now, 30);
    out_file = fullfile(out_dir, ['ab_summary_' stamp '.json']);
    latest_file = fullfile(out_dir, 'ab_summary_latest_frozen.json');
    write_text_file(out_file, src_txt);
    write_text_file(latest_file, src_txt);

    crit = optimization_pass_criteria();
    crit_file = fullfile(out_dir, ['pass_criteria_' stamp '.json']);
    write_text_file(crit_file, jsonencode(crit));

    snap = struct();
    snap.generated_at = stamp;
    snap.source_json = ab_summary_json;
    snap.snapshot_json = out_file;
    snap.latest_json = latest_file;
    snap.pass_criteria_json = crit_file;
    snap.summary = get_struct_field(obj, 'summary', struct());
end

function txt = read_text_file(in_file)
    fid = fopen(in_file, 'r');
    if fid == -1
        error('freeze_baseline_snapshot: cannot open %s', in_file);
    end
    txt = fread(fid, '*char')';
    fclose(fid);
end

function write_text_file(out_file, txt)
    fid = fopen(out_file, 'w');
    if fid == -1
        error('freeze_baseline_snapshot: cannot write %s', out_file);
    end
    fwrite(fid, txt);
    fclose(fid);
end

function out = get_struct_field(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        out = s.(field_name);
    end
end
