% test_openmagnetics_spacing.m
% Quick test to verify OpenMagnetics spacing functions work correctly

fprintf('Running OpenMagnetics Spacing Tests...\n\n');

%% Test 1: Spacing Calculator
fprintf('Test 1: Spacing Calculator\n');
fprintf('─────────────────────────────\n');

config = struct();
config.voltage_primary = 230 * sqrt(2);
config.voltage_secondary = 48;
config.width = 0.65e-3;
config.height = 0.65e-3;
config.n_turns = 40;
config.insulation_class = 'basic';
config.pollution_degree = 2;

spacing = calculate_winding_spacing(config);

fprintf('Input: 325V to 48V, basic insulation\n');
fprintf('Results:\n');
fprintf('  Filar gap:   %.3f mm\n', spacing.gap_filar * 1e3);
fprintf('  Turn gap:    %.3f mm\n', spacing.gap_layer * 1e3);
fprintf('  Winding gap: %.3f mm\n', spacing.gap_winding * 1e3);

% Verify reasonable values
assert(spacing.gap_filar > 0 && spacing.gap_filar < 1e-3, 'Filar gap unreasonable');
assert(spacing.gap_layer > 0 && spacing.gap_layer < 2e-3, 'Turn gap unreasonable');
assert(spacing.gap_winding > 0 && spacing.gap_winding < 10e-3, 'Winding gap unreasonable');

fprintf('âœ" Test 1 PASSED\n\n');

%% Test 2: Transformer Geometry Builder
fprintf('Test 2: Transformer Geometry Builder\n');
fprintf('─────────────────────────────────────\n');

winding_config = {
    {1, 20, 2, 2.0, 0, 325};
    {2, 10, 1, 8.0, 180, 48}
};

wire_width = 0.65e-3;
wire_height = 0.65e-3;
gap_layer = 0.1e-3;
gap_turn = 0.05e-3;

insulation = struct();
insulation.insulation_class = 'reinforced';
insulation.pollution_degree = 2;

[conductors, winding_map] = build_transformer_geometry(winding_config, ...
    wire_width, wire_height, gap_layer, gap_turn, insulation);

fprintf('Built transformer:\n');
fprintf('  Windings: %d\n', max(winding_map.winding_id));
fprintf('  Total conductors: %d\n', size(conductors, 1));
fprintf('  Height: %.3f mm\n', (max(conductors(:,2)) - min(conductors(:,2)) + wire_height) * 1e3);

% Verify structure
assert(size(conductors, 2) == 6, 'Conductor array wrong size');
assert(~isempty(winding_map.winding_id), 'Winding map empty');
assert(max(winding_map.winding_id) == 2, 'Wrong number of windings');

fprintf('âœ" Test 2 PASSED\n\n');

%% Test 3: Multi-filar Winding
fprintf('Test 3: Multi-filar Winding Builder\n');
fprintf('────────────────────────────────────\n');

config_mf = struct();
config_mf.n_filar = 2;
config_mf.n_turns = 10;
config_mf.n_windings = 2;
config_mf.width = wire_width;
config_mf.height = wire_height;
config_mf.gap_layer = 0.1e-3;
config_mf.currents = [2.0; 8.0];
config_mf.phases = [0; 180];
config_mf.voltages = [325; 48];
config_mf.insulation_class = 'basic';

[cond_mf, map_mf, shapes_mf] = build_multifilar_winding_improved(config_mf);

fprintf('Built bifilar winding:\n');
fprintf('  Filars: %d\n', config_mf.n_filar);
fprintf('  Windings: %d\n', config_mf.n_windings);
fprintf('  Total conductors: %d\n', size(cond_mf, 1));
fprintf('  Expected: %d\n', config_mf.n_filar * config_mf.n_turns * config_mf.n_windings);

% Verify
expected_cond = config_mf.n_filar * config_mf.n_turns * config_mf.n_windings;
assert(size(cond_mf, 1) == expected_cond, 'Wrong number of conductors');
assert(length(map_mf) == expected_cond, 'Winding map size mismatch');
assert(length(shapes_mf) == expected_cond, 'Wire shapes size mismatch');

fprintf('âœ" Test 3 PASSED\n\n');

%% Test 4: Insulation Class Effects
fprintf('Test 4: Insulation Class Scaling\n');
fprintf('─────────────────────────────────\n');

config_basic = config;
config_basic.insulation_class = 'basic';
spacing_basic = calculate_winding_spacing(config_basic);

config_reinforced = config;
config_reinforced.insulation_class = 'reinforced';
spacing_reinforced = calculate_winding_spacing(config_reinforced);

fprintf('Basic vs Reinforced:\n');
fprintf('  Basic winding gap:      %.3f mm\n', spacing_basic.gap_winding * 1e3);
fprintf('  Reinforced winding gap: %.3f mm\n', spacing_reinforced.gap_winding * 1e3);
fprintf('  Multiplier:             %.2fx\n', ...
    spacing_reinforced.gap_winding / spacing_basic.gap_winding);

% Verify reinforced is larger
assert(spacing_reinforced.gap_winding > spacing_basic.gap_winding, ...
    'Reinforced should be larger than basic');
assert(spacing_reinforced.gap_winding >= 2.5 * spacing_basic.gap_winding, ...
    'Reinforced should be at least 2.5x basic');

fprintf('âœ" Test 4 PASSED\n\n');

%% Test 5: Voltage Scaling
fprintf('Test 5: Voltage-Dependent Spacing\n');
fprintf('──────────────────────────────────\n');

voltages = [50, 100, 250, 500, 1000];
gaps = zeros(size(voltages));

for i = 1:length(voltages)
    cfg = struct();
    cfg.voltage_primary = voltages(i);
    cfg.voltage_secondary = 48;
    cfg.width = wire_width;
    cfg.height = wire_height;
    cfg.insulation_class = 'basic';

    sp = calculate_winding_spacing(cfg);
    gaps(i) = sp.gap_winding;
end

fprintf('Voltage vs Spacing:\n');
for i = 1:length(voltages)
    fprintf('  %4d V: %.3f mm\n', voltages(i), gaps(i) * 1e3);
end

% Verify monotonic increase
for i = 2:length(gaps)
    assert(gaps(i) >= gaps(i-1), 'Spacing should increase with voltage');
end

fprintf('âœ" Test 5 PASSED\n\n');

%% Summary
fprintf('═══════════════════════════════════════════════════════════\n');
fprintf('   All Tests PASSED âœ"\n');
fprintf('═══════════════════════════════════════════════════════════\n\n');

fprintf('The OpenMagnetics spacing functions are working correctly.\n');
fprintf('You can now run:\n');
fprintf('  >> install_openmagnetics_spacing\n\n');
fprintf('to install them to your project directory.\n\n');
