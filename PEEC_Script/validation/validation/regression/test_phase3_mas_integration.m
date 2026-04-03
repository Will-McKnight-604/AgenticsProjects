function ok = test_phase3_mas_integration()
%TEST_PHASE3_MAS_INTEGRATION Smoke-test MAS case ingest -> solve metrics.

    here = fileparts(mfilename('fullpath'));
    val_dir = fileparts(here);
    root = fileparts(val_dir);
    addpath(root);
    addpath(val_dir);

    case_dir = fullfile(val_dir, 'mas_cases');
    if ~exist(case_dir, 'dir') || isempty(dir(fullfile(case_dir, '*.json')))
        generate_default_mas_cases(case_dir);
    end
    case_file = fullfile(case_dir, 'tsf_case_01.json');
    assert(exist(case_file, 'file') == 2, 'MAS case file missing: %s', case_file);

    opts = solver_option_profile('fast');
    opts.max_refine_iters = 1;
    opts.enable_adaptive_meshing = false;
    result = execute_mas_case(case_file, opts);

    req = {'case_id', 'frequency_hz', 'total_copper_loss_w', 'Llk_pri_h', 'runtime_s'};
    for i = 1:numel(req)
        assert(isfield(result, req{i}), 'Missing field in MAS result: %s', req{i});
    end

    ok = true;
    fprintf('[PASS] test_phase3_mas_integration\n');
end
