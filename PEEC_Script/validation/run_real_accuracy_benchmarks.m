function report = run_real_accuracy_benchmarks(results_dir, options)
%RUN_REAL_ACCURACY_BENCHMARKS Benchmark solver using validation/mas_cases_real.
%
% Example:
%   opts = struct('modes', {{'fast','standard','high'}}, 'verbose', true);
%   report = run_real_accuracy_benchmarks([], opts);

    here = fileparts(mfilename('fullpath'));
    case_dir = fullfile(here, 'mas_cases_real');

    if nargin < 1 || isempty(results_dir)
        results_dir = fullfile(here, 'results_real');
    end
    if nargin < 2 || ~isstruct(options)
        options = struct();
    end
    if ~isfield(options, 'verbose')
        options.verbose = true;
    end
    if ~isfield(options, 'refresh_cases')
        options.refresh_cases = true;
    end

    if ~exist(case_dir, 'dir')
        mkdir(case_dir);
    end
    case_files = [];
    if options.refresh_cases
        generate_real_mas_cases(case_dir, struct('clean_case_dir', true));
    end
    case_files = dir(fullfile(case_dir, '*.json'));
    if isempty(case_files)
        generate_real_mas_cases(case_dir, struct('clean_case_dir', true));
        case_files = dir(fullfile(case_dir, '*.json'));
    end
    if isempty(case_files)
        error('run_real_accuracy_benchmarks: no cases found in %s', case_dir);
    end

    if options.verbose
        fprintf('[REAL] Running benchmark on %d real-use cases from %s\n', numel(case_files), case_dir);
    end
    report = run_accuracy_benchmarks(case_dir, results_dir, options);

    report.case_pack = 'mas_cases_real';
    report.case_dir = case_dir;
    report.results_dir = results_dir;
    report.generated_at_real_runner = datestr(now, 30);

    real_latest = fullfile(results_dir, 'accuracy_benchmark_real_latest.json');
    write_json(report, real_latest);
    if options.verbose
        fprintf('[REAL] Wrote: %s\n', real_latest);
    end
end

function write_json(payload, out_file)
    fid = fopen(out_file, 'w');
    if fid == -1
        error('run_real_accuracy_benchmarks: cannot write %s', out_file);
    end
    fwrite(fid, jsonencode(payload));
    fclose(fid);
end
