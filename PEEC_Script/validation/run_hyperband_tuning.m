function report = run_hyperband_tuning(options)
%RUN_HYPERBAND_TUNING Convenience runner for multi-fidelity constrained tuning.
%
% Example:
%   report = run_hyperband_tuning();
%   report = run_hyperband_tuning(struct('initial_candidates', 12, 'stage_case_counts', [4 8]));

    if nargin < 1 || ~isstruct(options)
        options = struct();
    end
    report = tune_solver_hyperband(options);
end
