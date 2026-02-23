function files_written = generate_default_mas_cases(case_dir)
%GENERATE_DEFAULT_MAS_CASES Create synthetic two-switch-forward MAS cases.

    if nargin < 1 || isempty(case_dir)
        here = fileparts(mfilename('fullpath'));
        case_dir = fullfile(here, 'mas_cases');
    end
    if ~exist(case_dir, 'dir')
        mkdir(case_dir);
    end

    freq_list = [50e3, 75e3, 100e3, 120e3, 150e3, 180e3, ...
                 220e3, 260e3, 320e3, 400e3, 500e3, 650e3];
    pri_turns = [16, 14, 12, 12, 10, 10, 9, 8, 8, 7, 7, 6];
    sec_turns = [8, 7, 6, 6, 5, 5, 4, 4, 4, 3, 3, 3];
    pri_curr = [3.5, 4.0, 4.8, 5.2, 5.8, 6.1, 6.5, 6.8, 7.2, 7.5, 7.8, 8.0];
    sec_curr = [7.0, 7.8, 9.5, 10.3, 11.4, 12.0, 12.8, 13.5, 14.3, 15.0, 15.8, 16.2];
    shape_cycle = {'round', 'round', 'rectangular', 'round'};
    mesh_cycle = [4, 6, 8];

    files_written = {};
    for i = 1:12
        shape = shape_cycle{mod(i - 1, numel(shape_cycle)) + 1};
        mesh_n = mesh_cycle(mod(i - 1, numel(mesh_cycle)) + 1);

        wire_p = make_wire(shape, i, true);
        wire_s = make_wire(shape, i, false);

        case_data = struct();
        case_data.meta = struct( ...
            'case_id', sprintf('tsf_case_%02d', i), ...
            'source_solver', 'internal_synthetic', ...
            'description', sprintf('Synthetic two-switch-forward benchmark case %02d', i));

        case_data.inputs = struct();
        case_data.inputs.designRequirements = struct( ...
            'topology', 'two_switch_forward', ...
            'magnetizingInductance', struct('nominal', 150e-6), ...
            'turnsRatios', {{struct('nominal', pri_turns(i) / sec_turns(i))}} ...
        );
        op = struct();
        op.name = 'nominal';
        op.frequency_hz = freq_list(i);
        op.conditions = struct('ambientTemperature', 25);
        case_data.inputs.operatingPoints = op;

        benchmark = struct();
        benchmark.frequency_hz = freq_list(i);
        benchmark.sigma_s_per_m = 5.8e7;
        benchmark.mu0_h_per_m = 4 * pi * 1e-7;
        benchmark.mesh = struct('Nx', mesh_n, 'Ny', mesh_n);
        benchmark.core = struct('Ae', 52e-6, 'le', 62e-3, 'Ve', 3.2e-6, ...
                                'MLT', 78e-3, 'mu_r', 2200, ...
                                'bobbin_w', 11e-3, 'bobbin_h', 8e-3, ...
                                'gap_total_m', 120e-6);

        windings = repmat(struct(), 2, 1);
        windings(1) = struct( ...
            'name', 'Primary', ...
            'turns', pri_turns(i), ...
            'n_filar', 1 + mod(i, 2), ...
            'current_a', pri_curr(i), ...
            'phase_deg', 0, ...
            'wire', wire_p ...
        );
        windings(2) = struct( ...
            'name', 'Secondary', ...
            'turns', sec_turns(i), ...
            'n_filar', 1, ...
            'current_a', sec_curr(i), ...
            'phase_deg', 180, ...
            'wire', wire_s ...
        );

        benchmark.geometry = struct();
        benchmark.geometry.windings = windings;
        benchmark.geometry.gaps = struct('layer_m', 0.08e-3, 'filar_m', 0.04e-3, 'winding_m', 0.45e-3);
        case_data.benchmark = benchmark;

        out_file = fullfile(case_dir, sprintf('tsf_case_%02d.json', i));
        fid = fopen(out_file, 'w');
        if fid ~= -1
            fwrite(fid, jsonencode(case_data));
            fclose(fid);
            files_written{end+1} = out_file; %#ok<AGROW>
        end
    end
end

function wire = make_wire(shape, idx, is_primary)
    wire = struct();
    wire.shape = shape;
    wire.kind = shape;

    if strcmp(shape, 'rectangular')
        if is_primary
            wire.width_m = (0.65 + 0.02 * mod(idx, 3)) * 1e-3;
            wire.height_m = (0.22 + 0.02 * mod(idx, 2)) * 1e-3;
        else
            wire.width_m = (0.75 + 0.03 * mod(idx, 3)) * 1e-3;
            wire.height_m = (0.24 + 0.01 * mod(idx, 2)) * 1e-3;
        end
    else
        if is_primary
            d = (0.52 + 0.02 * mod(idx, 4)) * 1e-3;
        else
            d = (0.60 + 0.02 * mod(idx, 4)) * 1e-3;
        end
        wire.width_m = d;
        wire.height_m = d;
        if idx >= 9
            wire.kind = 'litz_scaffold';
            wire.strands = 80;
            wire.strand_diameter_m = 0.07e-3;
        end
    end
end

