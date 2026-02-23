function report = run_real_tuning_benchmark(results_dir, overrides)
%RUN_REAL_TUNING_BENCHMARK Run real-pack benchmark with deterministic tuning preset.
%
% Example:
%   report = run_real_tuning_benchmark();
%   report = run_real_tuning_benchmark([], struct('verbose', true));

    if nargin < 1
        results_dir = [];
    end
    if nargin < 2 || ~isstruct(overrides)
        overrides = struct();
    end

    opts = tuning_benchmark_preset();
    opts = merge_structs(opts, overrides);
    report = run_real_accuracy_benchmarks(results_dir, opts);
end

function out = merge_structs(base, extra)
    out = base;
    if ~isstruct(extra)
        return;
    end
    f = fieldnames(extra);
    for i = 1:numel(f)
        out.(f{i}) = extra.(f{i});
    end
end
