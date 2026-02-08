% test_section_layout.m
% Test the fixed multi-winding section layout
%
% Run this to verify that:
%   1. Winding sections are tight-packed (no giant gaps)
%   2. IEC insulation gaps are reasonable (1-2mm for basic, not 346mm)
%   3. Bobbin width/height swap protection works
%   4. Windings sit inside the bobbin window

fprintf('=== TEST: Multi-Winding Section Layout ===\n\n');

% --- Create a minimal mock API ---
api = struct();

% Wire database - AWG_22 round wire
api.wire_database.AWG_22.type = 'round';
api.wire_database.AWG_22.outer_diameter = 0.69e-3;  % 0.69mm with insulation
api.wire_database.AWG_22.diameter = 0.644e-3;       % bare copper

% Wire database - AWG_16 round wire (larger)
api.wire_database.AWG_16.type = 'round';
api.wire_database.AWG_16.outer_diameter = 1.35e-3;
api.wire_database.AWG_16.diameter = 1.29e-3;

% Core database - ETD29 with CORRECT E-core window (narrow x tall)
api.core_database.ETD_29_16_10.bobbin.width  = 7.13e-3;  % 7.13mm (narrow)
api.core_database.ETD_29_16_10.bobbin.height = 20.5e-3;  % 20.5mm (tall)

% Core database - ETD29 with SWAPPED dimensions (bug scenario)
api.core_database.ETD29_SWAPPED.bobbin.width  = 20.5e-3;  % WRONG: too wide
api.core_database.ETD29_SWAPPED.bobbin.height = 7.13e-3;  % WRONG: too short

% Core database - ETD49
api.core_database.ETD_49_25_16.bobbin.width  = 11.2e-3;
api.core_database.ETD_49_25_16.bobbin.height = 35.5e-3;

% --- Create layout calculator ---
calc = openmagnetics_winding_layout(api);

%% ===== TEST 1: Correct ETD29, AWG_22, basic insulation =====
fprintf('\n--- TEST 1: ETD29 correct dimensions, AWG_22 ---\n');
defs = cell(2,1);
defs{1} = struct('wire_type','AWG_22', 'n_turns',10, 'name','Primary', ...
    'voltage', 325, 'insulation', 'basic');
defs{2} = struct('wire_type','AWG_22', 'n_turns',5, 'name','Secondary', ...
    'voltage', 48, 'insulation', 'basic');

layouts = calc.calculate_multi_winding_layout('ETD_29_16_10', defs, 'layered');

% Verify
pri_xmin = min(layouts{1}.turn_positions(:,1)) - layouts{1}.wire_od/2;
pri_xmax = max(layouts{1}.turn_positions(:,1)) + layouts{1}.wire_od/2;
sec_xmin = min(layouts{2}.turn_positions(:,1)) - layouts{2}.wire_od/2;
sec_xmax = max(layouts{2}.turn_positions(:,1)) + layouts{2}.wire_od/2;

winding_gap = sec_xmin - pri_xmax;
total_used = sec_xmax;

fprintf('\n  RESULTS:\n');
fprintf('  Primary:   x = [%.2f - %.2f] mm\n', pri_xmin*1e3, pri_xmax*1e3);
fprintf('  Secondary: x = [%.2f - %.2f] mm\n', sec_xmin*1e3, sec_xmax*1e3);
fprintf('  Winding-to-winding gap: %.2f mm\n', winding_gap*1e3);
fprintf('  Total width used: %.2f mm (bobbin: 7.13 mm)\n', total_used*1e3);

assert(winding_gap > 0.5e-3, 'Gap too small for basic insulation');
assert(winding_gap < 10e-3,  'Gap too large - section bug still present');
assert(layouts{1}.all_fit, 'Should fit in ETD29');

fprintf('  --> PASS: Gap is reasonable (%.1f mm for 325V<->48V basic)\n', winding_gap*1e3);

%% ===== TEST 2: SWAPPED bobbin dimensions (auto-correction) =====
fprintf('\n--- TEST 2: Swapped bobbin dimensions (should auto-correct) ---\n');
layouts_swap = calc.calculate_multi_winding_layout('ETD29_SWAPPED', defs, 'layered');

bob_swap = layouts_swap{1}.bobbin;
fprintf('  Bobbin after correction: %.2f x %.2f mm (should be ~7 x ~20)\n', ...
    bob_swap.width*1e3, bob_swap.height*1e3);
assert(bob_swap.width < bob_swap.height, 'Swap correction failed');
fprintf('  --> PASS: Dimensions auto-corrected\n');

%% ===== TEST 3: Insulation gap varies with voltage =====
fprintf('\n--- TEST 3: Insulation gap vs. voltage ---\n');

test_voltages = [12, 48, 150, 325, 600];
for v = test_voltages
    d_low = struct('wire_type','AWG_22','n_turns',5,'name','Pri','voltage',v,'insulation','basic');
    d_sec = struct('wire_type','AWG_22','n_turns',5,'name','Sec','voltage',0,'insulation','basic');
    gap = calc.calculate_insulation_gap(d_low, d_sec);
    fprintf('  %4dV basic: %.2f mm\n', v, gap*1e3);
end

%% ===== TEST 4: Insulation types =====
fprintf('\n--- TEST 4: Insulation types at 325V ---\n');
ins_types = {'functional', 'basic', 'supplementary', 'reinforced'};
for i = 1:length(ins_types)
    d1 = struct('wire_type','AWG_22','n_turns',5,'name','A','voltage',325,'insulation',ins_types{i});
    d2 = struct('wire_type','AWG_22','n_turns',5,'name','B','voltage',0,'insulation',ins_types{i});
    gap = calc.calculate_insulation_gap(d1, d2);
    fprintf('  325V %s: %.2f mm\n', ins_types{i}, gap*1e3);
end

%% ===== TEST 5: Larger core ETD49 with mixed wire =====
fprintf('\n--- TEST 5: ETD49 with primary AWG_16, secondary AWG_22 ---\n');
defs49 = cell(2,1);
defs49{1} = struct('wire_type','AWG_16', 'n_turns',20, 'name','Primary', ...
    'voltage', 400, 'insulation', 'reinforced');
defs49{2} = struct('wire_type','AWG_22', 'n_turns',40, 'name','Secondary', ...
    'voltage', 12, 'insulation', 'reinforced');

layouts49 = calc.calculate_multi_winding_layout('ETD_49_25_16', defs49, 'layered');

pri49_w = max(layouts49{1}.turn_positions(:,1)) - min(layouts49{1}.turn_positions(:,1)) + layouts49{1}.wire_od;
sec49_w = max(layouts49{2}.turn_positions(:,1)) - min(layouts49{2}.turn_positions(:,1)) + layouts49{2}.wire_od;
gap49 = min(layouts49{2}.turn_positions(:,1)) - max(layouts49{1}.turn_positions(:,1));

fprintf('  Primary width:   %.2f mm (%d turns AWG_16)\n', pri49_w*1e3, 20);
fprintf('  Secondary width: %.2f mm (%d turns AWG_22)\n', sec49_w*1e3, 40);
fprintf('  Gap (reinforced): %.2f mm\n', gap49*1e3);
fprintf('  Fits: %d\n', layouts49{1}.all_fit);

%% ===== VISUALIZATION =====
fprintf('\n--- Visualizing Test 1 layout ---\n');
try
    figure('Name', 'Multi-Winding Section Layout Test', 'Position', [100 100 800 500]);
    ax = gca;
    calc.visualize_multi_layout(layouts, ax, {[0.2 0.4 0.8], [0.8 0.2 0.2]});
    title(ax, sprintf('ETD29: layered, basic insulation @ 325V/48V (gap=%.1fmm)', winding_gap*1e3));
    fprintf('  Plot created successfully\n');
catch e
    fprintf('  [WARN] Plot failed: %s (expected in non-GUI mode)\n', e.message);
end

fprintf('\n=== ALL TESTS PASSED ===\n');
