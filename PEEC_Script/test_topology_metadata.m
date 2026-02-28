function test_topology_metadata()
% TEST_TOPOLOGY_METADATA Test script for topology metadata functions
%
% Runs comprehensive tests on all topology metadata getter functions
% Usage: test_topology_metadata()

fprintf('\n========== TOPOLOGY METADATA SYSTEM TEST ==========\n\n');

% Test 1: get_topology_metadata
fprintf('TEST 1: get_topology_metadata()\n');
fprintf('-----------------------------------------\n');
topos_to_test = {'two_switch_forward', 'buck', 'flyback', 'isolated_buck_boost'};
for i = 1:length(topos_to_test)
    topo_key = topos_to_test{i};
    topo = get_topology_metadata(topo_key);
    fprintf('  %-25s -> Display: %-25s | MAS: %-20s | Output: %s\n', ...
        topo_key, topo.display_name, topo.mas_filename, topo.output_type);
    fprintf('    Required: %s\n', strjoin(topo.required_fields, ', '));
    fprintf('    Optional: %s\n', strjoin(topo.optional_fields, ', '));
end

% Test 2: get_field_metadata
fprintf('\n\nTEST 2: get_field_metadata()\n');
fprintf('-----------------------------------------\n');
fields_to_test = {'inputVoltage_minimum', 'diodeVoltageDrop', 'outputVoltages_0', ...
                  'switchingFrequency', 'efficiency'};
for i = 1:length(fields_to_test)
    field_name = fields_to_test{i};
    meta = get_field_metadata(field_name);
    fprintf('  %-30s -> Label: %-30s | Unit: %-6s | Type: %s\n', ...
        field_name, meta.label, meta.unit, meta.data_type);
    fprintf('    Range: [%g, %g] | Default: ', meta.min, meta.max);
    if isempty(meta.default)
        fprintf('[] (empty)');
    else
        fprintf('%g', meta.default);
    end
    fprintf(' | Optional: %d\n', meta.optional);
    fprintf('    MAS Path: %s\n', meta.mas_path);
end

% Test 3: is_field_required
fprintf('\n\nTEST 3: is_field_required()\n');
fprintf('-----------------------------------------\n');
test_cases = {...
    'two_switch_forward', 'diodeVoltageDrop', true; ...
    'buck', 'currentRippleRatio', false; ...
    'flyback', 'efficiency', true; ...
    'isolated_buck', 'maximumSwitchCurrent', false; ...
};
for i = 1:size(test_cases, 1)
    topo_key = test_cases{i, 1};
    field_name = test_cases{i, 2};
    expected = test_cases{i, 3};
    result = is_field_required(topo_key, field_name);
    status = 'PASS';
    if result ~= expected
        status = 'FAIL';
    end
    fprintf('  [%s] is_field_required(''%s'', ''%s'') = %d (expected %d)\n', ...
        status, topo_key, field_name, result, expected);
end

% Test 4: get_visible_fields_for_topology
fprintf('\n\nTEST 4: get_visible_fields_for_topology()\n');
fprintf('-----------------------------------------\n');
topos_to_test = {'two_switch_forward', 'buck', 'push_pull'};
for i = 1:length(topos_to_test)
    topo_key = topos_to_test{i};
    [req, opt] = get_visible_fields_for_topology(topo_key);
    fprintf('  %s:\n', topo_key);
    fprintf('    Required (%d): %s\n', length(req), strjoin(req, ', '));
    fprintf('    Optional (%d): %s\n', length(opt), strjoin(opt, ', '));
end

% Test 5: get_topology_output_type
fprintf('\n\nTEST 5: get_topology_output_type()\n');
fprintf('-----------------------------------------\n');
all_topos = {'two_switch_forward', 'single_switch_forward', 'active_clamp_forward', ...
             'flyback', 'push_pull', 'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'};
fprintf('  Single-output topologies:\n');
for i = 1:length(all_topos)
    topo_key = all_topos{i};
    output_type = get_topology_output_type(topo_key);
    if strcmp(output_type, 'single')
        fprintf('    - %s\n', topo_key);
    end
end
fprintf('  Multi-output topologies:\n');
for i = 1:length(all_topos)
    topo_key = all_topos{i};
    output_type = get_topology_output_type(topo_key);
    if strcmp(output_type, 'multi')
        fprintf('    - %s\n', topo_key);
    end
end

% Test 6: Error handling
fprintf('\n\nTEST 6: Error Handling\n');
fprintf('-----------------------------------------\n');
try
    bad_topo = get_topology_metadata('invalid_topology');
    fprintf('  [FAIL] Should have thrown error for invalid topology\n');
catch ME
    fprintf('  [PASS] Caught expected error for invalid topology:\n');
    fprintf('    %s\n', ME.message);
end

try
    bad_field = get_field_metadata('invalid_field');
    fprintf('  [FAIL] Should have thrown error for invalid field\n');
catch ME
    fprintf('  [PASS] Caught expected error for invalid field:\n');
    fprintf('    %s\n', ME.message);
end

% Test 7: Field metadata completeness
fprintf('\n\nTEST 7: Field Metadata Completeness Check\n');
fprintf('-----------------------------------------\n');
defs = topology_metadata();
FIELD_DEFS = defs.FIELD_METADATA;
field_names = fieldnames(FIELD_DEFS);

fprintf('  Total fields defined: %d\n', length(field_names));
fprintf('  Field structure integrity:\n');

required_meta_fields = {'label', 'unit', 'data_type', 'default', 'min', 'max', ...
                        'tooltip', 'mas_path', 'optional'};

all_good = true;
for i = 1:length(field_names)
    field = field_names{i};
    meta = FIELD_DEFS.(field);
    for j = 1:length(required_meta_fields)
        if ~isfield(meta, required_meta_fields{j})
            fprintf('    [FAIL] Field ''%s'' missing required metadata: %s\n', ...
                field, required_meta_fields{j});
            all_good = false;
        end
    end
end

if all_good
    fprintf('    [PASS] All fields have complete metadata\n');
end

% Test 8: Topology metadata completeness
fprintf('\n\nTEST 8: Topology Metadata Completeness Check\n');
fprintf('-----------------------------------------\n');
TOPO_DEFS = defs.TOPOLOGY_DEFINITIONS;
topo_names = fieldnames(TOPO_DEFS);

fprintf('  Total topologies defined: %d\n', length(topo_names));
fprintf('  Topology structure integrity:\n');

required_topo_fields = {'display_name', 'mas_filename', 'output_type', ...
                        'required_fields', 'optional_fields'};

all_good = true;
for i = 1:length(topo_names)
    topo = topo_names{i};
    meta = TOPO_DEFS.(topo);
    for j = 1:length(required_topo_fields)
        if ~isfield(meta, required_topo_fields{j})
            fprintf('    [FAIL] Topology ''%s'' missing required field: %s\n', ...
                topo, required_topo_fields{j});
            all_good = false;
        end
    end
end

if all_good
    fprintf('    [PASS] All topologies have complete metadata\n');
end

fprintf('\n========== TEST COMPLETE ==========\n\n');

end
