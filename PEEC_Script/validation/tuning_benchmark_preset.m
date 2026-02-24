function opts = tuning_benchmark_preset()
%TUNING_BENCHMARK_PRESET Deterministic options for tuning benchmarks.
%
% Use this preset when comparing configuration changes to avoid ordering,
% cache, and resume bias during tuning sweeps.

    opts = struct();
    opts.modes = {'fast', 'standard', 'high'};
    opts.reference_mode = 'high';
    opts.mode_order_policy = 'fixed';
    opts.clear_persistent_between_modes = true;
    opts.warmup_runs = 1;
    opts.resume = false;
    opts.save_partial = true;
    opts.verbose = true;
    opts.record_timing_breakdown = true;
    opts.random_seed = 17;
end
