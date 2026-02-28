% Test script to verify the double conversion bug is fixed
% This script checks that efficiency and ripple are converted correctly

% Create a test GUI data structure
gui_data = struct();
gui_data.converter = struct();

% Simulate values that have already been converted by collect_gui_field_values()
gui_data.converter.efficiency = 0.90;      % Already converted from 90% to 0.90
gui_data.converter.max_ripple = 0.20;      % Already converted from 20% to 0.20
gui_data.converter.max_duty = 0.45;        % Already converted from 45% to 0.45
gui_data.converter.vin_min = 24;
gui_data.converter.vin_max = 48;
gui_data.converter.vin_nom = 36;
gui_data.converter.vd = 0.7;
gui_data.converter.vout = 12;
gui_data.converter.iout = 5;
gui_data.converter.fsw_khz = 100;

% Test with flyback topology (includes all three percentage conversions)
topology_key = 'flyback';

% Call build_mas_structure
mas_struct = build_mas_structure(gui_data, topology_key);

% Verify the results
fprintf('=== CONVERSION FIX VERIFICATION ===\n');
fprintf('Input GUI values:\n');
fprintf('  efficiency: %.2f (should be 0.90 = 90%%)\n', gui_data.converter.efficiency);
fprintf('  max_ripple: %.2f (should be 0.20 = 20%%)\n', gui_data.converter.max_ripple);
fprintf('  max_duty: %.2f (should be 0.45 = 45%%)\n', gui_data.converter.max_duty);

fprintf('\nOutput MAS values:\n');
fprintf('  efficiency: %.4f (should be 0.9000, NOT 0.0090)\n', mas_struct.inputs.designRequirements.efficiency);
fprintf('  currentRippleRatio: %.4f (should be 0.2000, NOT 0.0020)\n', mas_struct.inputs.designRequirements.currentRippleRatio);
fprintf('  maximumDutyCycle: %.4f (should be 0.4500, NOT 0.0045)\n', mas_struct.inputs.designRequirements.maximumDutyCycle);

% Check for double conversion bug
fprintf('\n=== BUG CHECK ===\n');
if abs(mas_struct.inputs.designRequirements.efficiency - 0.9) < 1e-6
    fprintf('✓ PASS: Efficiency is correct (0.9)\n');
else
    fprintf('✗ FAIL: Efficiency is WRONG (%.4f)\n', mas_struct.inputs.designRequirements.efficiency);
end

if abs(mas_struct.inputs.designRequirements.currentRippleRatio - 0.2) < 1e-6
    fprintf('✓ PASS: Current ripple ratio is correct (0.2)\n');
else
    fprintf('✗ FAIL: Current ripple ratio is WRONG (%.4f)\n', mas_struct.inputs.designRequirements.currentRippleRatio);
end

if abs(mas_struct.inputs.designRequirements.maximumDutyCycle - 0.45) < 1e-6
    fprintf('✓ PASS: Maximum duty cycle is correct (0.45)\n');
else
    fprintf('✗ FAIL: Maximum duty cycle is WRONG (%.4f)\n', mas_struct.inputs.designRequirements.maximumDutyCycle);
end

fprintf('\n=== FULL MAS STRUCTURE (JSON Preview) ===\n');
% Show the efficiency field to confirm it's reasonable
fprintf('Design Requirements:\n');
fprintf('  Topology: %s\n', mas_struct.inputs.designRequirements.topology);
fprintf('  Efficiency: %f (for API, should be ~0.9 not ~0.009)\n', mas_struct.inputs.designRequirements.efficiency);
fprintf('  Current Ripple Ratio: %f (for API, should be ~0.2 not ~0.002)\n', mas_struct.inputs.designRequirements.currentRippleRatio);
fprintf('  Maximum Duty Cycle: %f (for API, should be ~0.45 not ~0.0045)\n', mas_struct.inputs.designRequirements.maximumDutyCycle);
