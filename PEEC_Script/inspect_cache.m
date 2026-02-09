% inspect_cache.m
% Diagnostic script to inspect cached wire data structure
% This will help identify why foil wire dimensions aren't updating

fprintf('\n=== WIRE CACHE INSPECTION ===\n\n');

% Load the cache file
cache_file = 'openmagnetics_cache.mat';
if ~exist(cache_file, 'file')
    fprintf('ERROR: Cache file not found: %s\n', cache_file);
    return;
end

fprintf('Loading cache file: %s\n', cache_file);
cache_data = load(cache_file);

% Check what's in the cache
if ~isfield(cache_data, 'wire_database')
    fprintf('ERROR: No wire_database field in cache\n');
    return;
end

wire_db = cache_data.wire_database;
wire_names = fieldnames(wire_db);
fprintf('Total wires in cache: %d\n\n', length(wire_names));

% Find foil wires (look for wires with 'Foil' in the name)
fprintf('=== FOIL WIRES ===\n');
foil_wires = {};
for i = 1:length(wire_names)
    name = wire_names{i};
    if contains(name, 'Foil') || contains(name, 'foil')
        foil_wires{end+1} = name;
    end
end

fprintf('Found %d foil wires:\n', length(foil_wires));
for i = 1:length(foil_wires)
    fprintf('  %d. %s\n', i, foil_wires{i});
end
fprintf('\n');

% Inspect the first few foil wires in detail
fprintf('=== DETAILED INSPECTION OF FOIL WIRES ===\n\n');
num_to_inspect = min(5, length(foil_wires));

for i = 1:num_to_inspect
    wire_name = foil_wires{i};
    wire = wire_db.(wire_name);

    fprintf('--- Wire %d: %s ---\n', i, wire_name);
    fprintf('Fields present: ');
    fields = fieldnames(wire);
    fprintf('%s', strjoin(fields, ', '));
    fprintf('\n');

    % Check for dimensional fields
    fprintf('Dimensional data:\n');

    % Check foil-specific fields
    if isfield(wire, 'foil_width')
        fprintf('  foil_width: %.6f m (%.3f mm)\n', wire.foil_width, wire.foil_width*1e3);
    else
        fprintf('  foil_width: NOT FOUND\n');
    end

    if isfield(wire, 'foil_thickness')
        fprintf('  foil_thickness: %.6f m (%.3f mm)\n', wire.foil_thickness, wire.foil_thickness*1e3);
    else
        fprintf('  foil_thickness: NOT FOUND\n');
    end

    % Check rect fields
    if isfield(wire, 'rect_width')
        fprintf('  rect_width: %.6f m (%.3f mm)\n', wire.rect_width, wire.rect_width*1e3);
    else
        fprintf('  rect_width: NOT FOUND\n');
    end

    if isfield(wire, 'rect_height')
        fprintf('  rect_height: %.6f m (%.3f mm)\n', wire.rect_height, wire.rect_height*1e3);
    else
        fprintf('  rect_height: NOT FOUND\n');
    end

    % Check generic fields
    if isfield(wire, 'width')
        fprintf('  width: %.6f m (%.3f mm)\n', wire.width, wire.width*1e3);
    else
        fprintf('  width: NOT FOUND\n');
    end

    if isfield(wire, 'thickness')
        fprintf('  thickness: %.6f m (%.3f mm)\n', wire.thickness, wire.thickness*1e3);
    else
        fprintf('  thickness: NOT FOUND\n');
    end

    % Check conductor shape
    if isfield(wire, 'conductor_shape')
        fprintf('  conductor_shape: %s\n', wire.conductor_shape);
    else
        fprintf('  conductor_shape: NOT FOUND\n');
    end

    % Check area
    if isfield(wire, 'area')
        fprintf('  area: %.6e m^2\n', wire.area);
    else
        fprintf('  area: NOT FOUND\n');
    end

    fprintf('\n');
end

% Look for the specific wires mentioned by the user
fprintf('=== CHECKING SPECIFIC WIRES MENTIONED ===\n');
test_wires = {'Foil_0_038', 'Foil_0_005'};

for i = 1:length(test_wires)
    wire_name = test_wires{i};
    % Try to find this wire (field names are sanitized)
    wire_name_sanitized = strrep(wire_name, '.', '_');

    if isfield(wire_db, wire_name_sanitized)
        fprintf('\nWire: %s (field: %s) - FOUND\n', wire_name, wire_name_sanitized);
        wire = wire_db.(wire_name_sanitized);

        fprintf('  All fields: %s\n', strjoin(fieldnames(wire), ', '));

        if isfield(wire, 'foil_width') && isfield(wire, 'foil_thickness')
            fprintf('  Dimensions: %.3f mm x %.3f mm\n', ...
                wire.foil_width*1e3, wire.foil_thickness*1e3);
        elseif isfield(wire, 'rect_width') && isfield(wire, 'rect_height')
            fprintf('  Dimensions: %.3f mm x %.3f mm\n', ...
                wire.rect_width*1e3, wire.rect_height*1e3);
        else
            fprintf('  WARNING: No dimensional data found!\n');
        end
    else
        fprintf('\nWire: %s (tried field: %s) - NOT FOUND\n', wire_name, wire_name_sanitized);
    end
end

fprintf('\n=== INSPECTION COMPLETE ===\n');
