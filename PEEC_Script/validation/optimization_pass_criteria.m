function c = optimization_pass_criteria()
%OPTIMIZATION_PASS_CRITERIA Objective gates for optimization-day validation.

    c = struct();
    c.fast_speedup_vs_baseline_min = 1.05;
    c.standard_speedup_vs_baseline_min = 1.00;
    c.tuned_standard_loss_error_median_pct_max = 0.01;
    c.fast_loss_error_target_pct = 10.0;
    c.max_fast_loss_err_pct_max = 15.0;
    c.warning_fraction_max = 0.15;
    c.require_no_iter_quality_reject = true;
    c.require_fft_routed_on_uniform_case = true;
    c.fft_interaction_rel_error_max = 1e-3;
    c.fft_speedup_min = 1.30;
end
