function summary = run_phase3_regression()
%RUN_PHASE3_REGRESSION Run phase-3 compatibility and safety checks.

    here = fileparts(mfilename('fullpath'));
    addpath(here);

    tests = { ...
        @test_phase3_solver_options, ...
        @test_phase3_kernel_symmetry, ...
        @test_phase3_cap_behavior, ...
        @test_phase3_nonnegative_losses, ...
        @test_phase3_mas_integration, ...
        @test_phase3_compatibility ...
    };

    summary = struct();
    summary.generated_at = datestr(now, 30);
    summary.total = numel(tests);
    summary.passed = 0;
    summary.failed = 0;
    summary.results = repmat(struct('name', '', 'ok', false, 'message', ''), 1, numel(tests));

    for i = 1:numel(tests)
        fn = tests{i};
        name = func2str(fn);
        entry = struct('name', name, 'ok', false, 'message', '');
        try
            out = fn();
            entry.ok = logical(out);
            if entry.ok
                summary.passed = summary.passed + 1;
                entry.message = 'PASS';
            else
                summary.failed = summary.failed + 1;
                entry.message = 'Returned false';
            end
        catch ME
            summary.failed = summary.failed + 1;
            entry.ok = false;
            entry.message = ME.message;
        end
        summary.results(i) = entry;
    end
end
