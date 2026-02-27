% Verification script for Bug Fixes 1 & 5
% Tests unit conversion and field name handling

clear all; close all;

fprintf('\n===== Unit Conversion Verification Test =====\n\n');

% Create simulated GUI data (as if from collect_gui_field_values)
gui_data = struct();
gui_data.converter = struct();
gui_data.converter.vin_min = 100;
gui_data.converter.vin_max = 190;
gui_data.converter.vin_nom = 145;
gui_data.converter.vout = 5.0;
gui_data.converter.iout = 5.0;
gui_data.converter.fsw_khz = 200;
gui_data.converter.vd = 0.7;

% BUG 1 FIX: Now efficiency and ripple stay as percentages in collect_gui_field_values
% (they are no longer divided by 100 at collection time)
gui_data.converter.efficiency = 90;      % PERCENT (not 0.90)
gui_data.converter.max_ripple = 30;      % PERCENT (not 0.30)
gui_data.converter.max_switch_current = [];

gui_data.thermal = struct();
gui_data.thermal.ambient_temp = 25;

gui_data.insulation = struct();
gui_data.insulation.class = 'Basic';
gui_data.insulation.standard = 'IEC 62368-1';
gui_data.insulation.pollution_degree = 2;
gui_data.insulation.overvoltage_cat = 'II';
gui_data.insulation.cti = 'Group II';
gui_data.insulation.altitude_max = 2000;

fprintf('Input GUI data:\n');
fprintf('  Efficiency: %.1f (PERCENT)\n', gui_data.converter.efficiency);
fprintf('  Max Ripple: %.1f (PERCENT)\n\n', gui_data.converter.max_ripple);

% Build MAS structure (should convert percentage to decimal)
mas = build_mas_structure(gui_data, 'two_switch_forward');

fprintf('Output MAS structure:\n');
fprintf('  Efficiency: %.4f (DECIMAL - should be 0.9000)\n', mas.inputs.designRequirements.efficiency);
fprintf('  Current Ripple: %.4f (DECIMAL - should be 0.3000)\n\n', mas.inputs.designRequirements.currentRippleRatio);

% Verify values are correct
eff_expected = 0.9;
ripple_expected = 0.3;
tolerance = 1e-6;

if abs(mas.inputs.designRequirements.efficiency - eff_expected) < tolerance
    fprintf('✓ BUG 1 FIX VERIFIED: Efficiency correctly converted to 0.9 (not 0.009 or 90)\n');
else
    fprintf('✗ BUG 1 FAILED: Efficiency is %.4f (expected 0.9000)\n', mas.inputs.designRequirements.efficiency);
end

if abs(mas.inputs.designRequirements.currentRippleRatio - ripple_expected) < tolerance
    fprintf('✓ BUG 1 FIX VERIFIED: Ripple correctly converted to 0.3 (not 0.003 or 30)\n\n');
else
    fprintf('✗ BUG 1 FAILED: Ripple is %.4f (expected 0.3000)\n\n', mas.inputs.designRequirements.currentRippleRatio);
end

% BUG 5 FIX: Two-switch-forward uses outputVoltages (plural, array)
fprintf('Output field names (Multi-output topology):\n');
if isfield(mas.inputs.operatingPoints{1}, 'outputVoltages')
    fprintf('✓ BUG 5 FIX VERIFIED: Multi-output topology uses outputVoltages (plural)\n');
    fprintf('  outputVoltages: [%.1f] V\n', mas.inputs.operatingPoints{1}.outputVoltages);
    fprintf('  outputCurrents: [%.1f] A\n\n', mas.inputs.operatingPoints{1}.outputCurrents);
else
    fprintf('✗ BUG 5 FAILED: Expected outputVoltages field\n\n');
end

% Test single-output topology for comparison
fprintf('Testing Buck converter (Single-output topology):\n');
gui_data_buck = struct();
gui_data_buck.converter = struct();
gui_data_buck.converter.vin_min = 12;
gui_data_buck.converter.vin_max = 24;
gui_data_buck.converter.vout = 5.0;
gui_data_buck.converter.iout = 10.0;
gui_data_buck.converter.fsw_khz = 100;
gui_data_buck.thermal = struct();
gui_data_buck.thermal.ambient_temp = 25;

mas_buck = build_mas_structure(gui_data_buck, 'buck');

if isfield(mas_buck.inputs.operatingPoints{1}, 'outputVoltage')
    fprintf('✓ Single-output topology uses outputVoltage (singular)\n');
    fprintf('  outputVoltage: %.1f V\n', mas_buck.inputs.operatingPoints{1}.outputVoltage);
    fprintf('  outputCurrent: %.1f A\n\n', mas_buck.inputs.operatingPoints{1}.outputCurrent);
else
    fprintf('✗ Single-output topology field error\n\n');
end

fprintf('===== Verification Complete =====\n\n');
