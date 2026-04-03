function test_mas_api_workflow()
% TEST: Demonstrates complete workflow of build_mas_structure.m + call_pyopenmagnetics_api.py
% This script can be run from MATLAB/Octave to validate the integration.
%
% Expected flow:
%   1. Build sample GUI data struct (simulating topology_wizard.m inputs)
%   2. Call build_mas_structure() to create MAS-formatted JSON
%   3. Call Python API bridge to get recommendations
%   4. Display results

    close all; clear all;
    fprintf('\n===== MAS Structure + PyOpenMagnetics API Workflow Test =====\n\n');

    % ===== TEST 1: Two-Switch Forward Converter =====
    fprintf('TEST 1: Two-Switch Forward Converter\n');
    fprintf('-------------------------------------\n\n');

    gui_data = struct();

    % Converter specs
    gui_data.converter = struct();
    gui_data.converter.vin_min = 100;
    gui_data.converter.vin_max = 190;
    gui_data.converter.vin_nom = 145;  % Optional
    gui_data.converter.vout = 5.0;
    gui_data.converter.iout = 5.0;
    gui_data.converter.fsw_khz = 200;
    gui_data.converter.vd = 0.7;
    gui_data.converter.efficiency = 90;  % percent
    gui_data.converter.max_ripple = 30;  % percent
    gui_data.converter.max_switch_current = [];  % Optional

    % Thermal
    gui_data.thermal = struct();
    gui_data.thermal.ambient_temp = 25;

    % Insulation
    gui_data.insulation = struct();
    gui_data.insulation.class = 'Basic';
    gui_data.insulation.standard = 'IEC 62368-1';
    gui_data.insulation.pollution_degree = 2;
    gui_data.insulation.overvoltage_cat = 'II';
    gui_data.insulation.cti = 'Group II';
    gui_data.insulation.altitude_max = 2000;

    % Build MAS structure
    try
        mas = build_mas_structure(gui_data, 'two_switch_forward');
        fprintf('✓ build_mas_structure() succeeded\n\n');

        % Display structure
        fprintf('MAS Structure Created:\n');
        fprintf('  Topology: %s\n', mas.inputs.designRequirements.topology);
        fprintf('  Input Voltage: [%.0f, %.0f, %.0f] V\n', ...
            mas.inputs.designRequirements.inputVoltage.minimum, ...
            mas.inputs.designRequirements.inputVoltage.nominal, ...
            mas.inputs.designRequirements.inputVoltage.maximum);
        fprintf('  Diode Voltage Drop: %.2f V\n', mas.inputs.designRequirements.diodeVoltageDrop);
        fprintf('  Current Ripple: %.1f %%\n', mas.inputs.designRequirements.currentRippleRatio * 100);
        fprintf('  Efficiency: %.1f %%\n', mas.inputs.designRequirements.efficiency * 100);
        % Handle both single-output and multi-output topologies
        if isfield(mas.inputs.operatingPoints{1}, 'outputVoltages')
            fprintf('  Output: %.1f V @ %.1f A\n', ...
                mas.inputs.operatingPoints{1}.outputVoltages(1), ...
                mas.inputs.operatingPoints{1}.outputCurrents(1));
        else
            fprintf('  Output: %.1f V @ %.1f A\n', ...
                mas.inputs.operatingPoints{1}.outputVoltage, ...
                mas.inputs.operatingPoints{1}.outputCurrent);
        end
        fprintf('  Freq: %.0f kHz\n\n', mas.inputs.operatingPoints{1}.switchingFrequency / 1000);

        % Save to JSON for API call
        script_dir = pwd();
        config_file = fullfile(script_dir, 'test_mas_config.json');
        result_file = fullfile(script_dir, 'test_mas_results.json');

        fid = fopen(config_file, 'w', 'n', 'UTF-8');
        fprintf(fid, '%s', jsonencode(mas));
        fclose(fid);
        fprintf('✓ MAS JSON saved to: %s\n\n', config_file);

    catch err
        fprintf('✗ Error in build_mas_structure():\n%s\n\n', err.message);
        return;
    end

    % ===== TEST 2: Call PyOpenMagnetics API =====
    fprintf('TEST 2: Calling PyOpenMagnetics API\n');
    fprintf('------------------------------------\n\n');

    try
        % Find Python
        python_cmd = 'python';
        venv_python = fullfile(script_dir, '.venv', 'Scripts', 'python.exe');
        if exist(venv_python, 'file')
            python_cmd = ['"' strrep(venv_python, '\', '/') '"'];
        end

        % Run API script
        cmd = sprintf('%s call_pyopenmagnetics_api.py "%s" "%s" 3 STANDARD_CORES', ...
            python_cmd, config_file, result_file);

        fprintf('Running: %s\n', cmd);
        [status, output] = system(cmd);

        fprintf('Python exit status: %d\n', status);
        fprintf('Python output:\n%s\n\n', strtrim(output));

        if status ~= 0
            fprintf('✗ Python script failed\n\n');
            return;
        end

        % Load results
        if ~exist(result_file, 'file')
            fprintf('✗ Result file not found: %s\n\n', result_file);
            return;
        end

        fid = fopen(result_file, 'r', 'n', 'UTF-8');
        raw = fread(fid, '*char')';
        fclose(fid);
        results = jsondecode(raw);

        fprintf('✓ API call succeeded\n\n');

        % Display results
        if strcmp(results.status, 'OK')
            fprintf('Results: %d designs recommended\n\n', results.count);
            for i = 1:min(3, results.count)
                rec = results.data(i);
                fprintf('Recommendation %d:\n', rec.index);
                if isfield(rec, 'core_name')
                    fprintf('  Core: %s\n', rec.core_name);
                end
                if isfield(rec, 'losses_total')
                    fprintf('  Total Loss: %.2f W\n', rec.losses_total);
                end
                if isfield(rec, 'temperature_winding')
                    fprintf('  Winding Temp: %.1f C\n', rec.temperature_winding);
                end
                fprintf('\n');
            end
        else
            fprintf('✗ API Error: %s\n\n', results.error);
        end

    catch err
        fprintf('✗ Error in API call:\n%s\n\n', err.message);
    end

    % ===== TEST 3: Flyback Converter =====
    fprintf('TEST 3: Flyback Converter (Multi-output)\n');
    fprintf('----------------------------------------\n\n');

    gui_data2 = struct();

    % Converter specs
    gui_data2.converter = struct();
    gui_data2.converter.vin_min = 85;
    gui_data2.converter.vin_max = 264;
    gui_data2.converter.vin_nom = 174;
    gui_data2.converter.vout = 12.0;
    gui_data2.converter.iout = 1.0;
    gui_data2.converter.fsw_khz = 65;
    gui_data2.converter.vd = 0.8;
    gui_data2.converter.efficiency = 85;
    gui_data2.converter.max_ripple = 40;
    gui_data2.converter.max_duty = 60;  % Flyback-specific
    gui_data2.converter.max_drain_source_voltage = 400;  % Flyback-specific

    % Thermal
    gui_data2.thermal = struct();
    gui_data2.thermal.ambient_temp = 25;

    % Insulation
    gui_data2.insulation = struct();
    gui_data2.insulation.class = 'Basic';
    gui_data2.insulation.standard = 'IEC 62368-1';
    gui_data2.insulation.pollution_degree = 2;
    gui_data2.insulation.overvoltage_cat = 'II';
    gui_data2.insulation.cti = 'Group II';
    gui_data2.insulation.altitude_max = 2000;

    % Build MAS structure
    try
        mas2 = build_mas_structure(gui_data2, 'flyback');
        fprintf('✓ Flyback MAS structure created\n');
        fprintf('  Topology: %s\n', mas2.inputs.designRequirements.topology);
        fprintf('  Max Duty: %.1f %%\n', mas2.inputs.designRequirements.maximumDutyCycle * 100);
        fprintf('  Max Drain-Source: %.0f V\n\n', mas2.inputs.designRequirements.maximumDrainSourceVoltage);

    catch err
        fprintf('✗ Error: %s\n\n', err.message);
    end

    % ===== TEST 4: Buck Converter (Non-isolated, single-output) =====
    fprintf('TEST 4: Buck Converter (Single-output)\n');
    fprintf('--------------------------------------\n\n');

    gui_data3 = struct();

    % Converter specs
    gui_data3.converter = struct();
    gui_data3.converter.vin_min = 12.0;
    gui_data3.converter.vin_max = 24.0;
    gui_data3.converter.vin_nom = 18.0;
    gui_data3.converter.vout = 5.0;
    gui_data3.converter.iout = 10.0;
    gui_data3.converter.fsw_khz = 100;
    gui_data3.converter.max_ripple = 20;
    gui_data3.converter.efficiency = 92;

    % Thermal
    gui_data3.thermal = struct();
    gui_data3.thermal.ambient_temp = 25;

    % Build MAS structure
    try
        mas3 = build_mas_structure(gui_data3, 'buck');
        fprintf('✓ Buck MAS structure created\n');
        fprintf('  Topology: %s\n', mas3.inputs.designRequirements.topology);
        fprintf('  Output: %.1f V @ %.1f A\n', ...
            mas3.inputs.operatingPoints{1}.outputVoltage, ...
            mas3.inputs.operatingPoints{1}.outputCurrent);
        fprintf('  Freq: %.0f kHz\n\n', mas3.inputs.operatingPoints{1}.switchingFrequency / 1000);

    catch err
        fprintf('✗ Error: %s\n\n', err.message);
    end

    fprintf('===== All Tests Complete =====\n\n');

end
