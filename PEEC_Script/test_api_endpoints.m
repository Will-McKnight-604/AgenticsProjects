% test_api_endpoints.m
% Compare /wires vs /wire/{name} endpoints to diagnose dimensional data issue

fprintf('\n=== TESTING OPENMAGNETICS API ENDPOINTS ===\n\n');

% Connect to server
om = om_client();

if ~om.connected
    fprintf('ERROR: Could not connect to OpenMagnetics server\n');
    fprintf('Make sure the server is running: python om_server.py\n');
    return;
end

fprintf('Connected to OpenMagnetics server\n\n');

% Test 1: Get all wires (list endpoint)
fprintf('TEST 1: Fetching all wires from /wires endpoint\n');
fprintf('-----------------------------------------------\n');
all_wires = om.get_wires();
wire_names = fieldnames(all_wires);
fprintf('Total wires returned: %d\n', length(wire_names));

% Find a foil wire in the list
foil_names = {};
for i = 1:length(wire_names)
    if ~isempty(strfind(lower(wire_names{i}), 'foil'))
        foil_names{end+1} = wire_names{i};
        if length(foil_names) >= 3
            break;  % Get first 3 foil wires
        end
    end
end

if isempty(foil_names)
    fprintf('WARNING: No foil wires found in response\n');
    return;
end

fprintf('Found foil wires: %s\n', strjoin(foil_names, ', '));
fprintf('\n');

% Test 2: Examine first foil wire from list
fprintf('TEST 2: Examining foil wire from /wires list\n');
fprintf('---------------------------------------------\n');
test_name = foil_names{1};
fprintf('Wire name: %s\n', test_name);
wire_from_list = all_wires.(test_name);

fprintf('Structure from /wires:\n');
if isstruct(wire_from_list)
    fields = fieldnames(wire_from_list);
    fprintf('  Fields (%d): %s\n', length(fields), strjoin(fields, ', '));

    % Check for dimensional fields
    fprintf('  Dimensional fields:\n');
    dim_fields = {'foil_width', 'foil_thickness', 'rect_width', 'rect_height', ...
                  'width', 'thickness', 'outer_diameter', 'conducting_width', ...
                  'conducting_height', 'conductingWidth', 'conductingHeight'};
    has_dims = false;
    for i = 1:length(dim_fields)
        if isfield(wire_from_list, dim_fields{i})
            val = wire_from_list.(dim_fields{i});
            fprintf('    %s = %.6f\n', dim_fields{i}, val);
            has_dims = true;
        end
    end
    if ~has_dims
        fprintf('    NONE FOUND\n');
    end
else
    fprintf('  ERROR: Response is not a struct\n');
end
fprintf('\n');

% Test 3: Query same wire using detailed endpoint
fprintf('TEST 3: Querying same wire from /wire/{name} endpoint\n');
fprintf('------------------------------------------------------\n');
fprintf('Requesting: %s\n', test_name);

try
    wire_detailed = om.find_wire(test_name);

    fprintf('Structure from /wire/{name}:\n');
    if isstruct(wire_detailed)
        fields = fieldnames(wire_detailed);
        fprintf('  Fields (%d): %s\n', length(fields), strjoin(fields, ', '));

        % Check for dimensional fields
        fprintf('  Dimensional fields:\n');
        has_dims = false;
        for i = 1:length(dim_fields)
            if isfield(wire_detailed, dim_fields{i})
                val = wire_detailed.(dim_fields{i});
                fprintf('    %s = %.6f\n', dim_fields{i}, val);
                has_dims = true;
            end
        end
        if ~has_dims
            fprintf('    NONE FOUND\n');
        end

        % Display full structure
        fprintf('\n  Full structure:\n');
        disp(wire_detailed);
    else
        fprintf('  ERROR: Response is not a struct\n');
    end
catch ME
    fprintf('ERROR querying detailed endpoint: %s\n', ME.message);
end

fprintf('\n');

% Test 4: Compare multiple foil wires
fprintf('TEST 4: Comparing multiple foil wires from /wire/{name}\n');
fprintf('--------------------------------------------------------\n');
for i = 1:min(3, length(foil_names))
    name = foil_names{i};
    fprintf('\nWire %d: %s\n', i, name);

    try
        wire_det = om.find_wire(name);
        if isstruct(wire_det)
            % Check for any dimensional data
            has_any_dim = false;
            for j = 1:length(dim_fields)
                if isfield(wire_det, dim_fields{j})
                    val = wire_det.(dim_fields{j});
                    fprintf('  %s = %.6f\n', dim_fields{j}, val);
                    has_any_dim = true;
                end
            end
            if ~has_any_dim
                fprintf('  No dimensional fields found\n');
            end
        end
    catch ME
        fprintf('  ERROR: %s\n', ME.message);
    end
end

fprintf('\n=== TEST COMPLETE ===\n');
fprintf('\nCONCLUSION:\n');
fprintf('Compare the field lists from TEST 2 vs TEST 3.\n');
fprintf('If /wire/{name} has more fields than /wires, we need to:\n');
fprintf('1. Modify fetch_wires_online() to query each wire individually\n');
fprintf('2. Or check if /wires accepts parameters like ?detailed=true\n');
