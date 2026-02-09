% inspect_cache_to_file.m
% Diagnostic script to inspect cached wire data structure
% Writes output to a text file

output_file = 'cache_inspection_results.txt';
fid = fopen(output_file, 'w');

fprintf(fid, '\n=== WIRE CACHE INSPECTION ===\n\n');

% Load the cache file
cache_file = 'openmagnetics_cache.mat';
if ~exist(cache_file, 'file')
    fprintf(fid, 'ERROR: Cache file not found: %s\n', cache_file);
    fclose(fid);
    return;
end

fprintf(fid, 'Loading cache file: %s\n', cache_file);
try
    cache_data = load(cache_file);
catch ME
    fprintf(fid, 'ERROR loading cache: %s\n', ME.message);
    fclose(fid);
    return;
end

% Check what's in the cache
if ~isfield(cache_data, 'wire_database')
    fprintf(fid, 'ERROR: No wire_database field in cache\n');
    fclose(fid);
    return;
end

wire_db = cache_data.wire_database;
wire_names = fieldnames(wire_db);
fprintf(fid, 'Total wires in cache: %d\n\n', length(wire_names));

% Find foil wires
fprintf(fid, '=== FOIL WIRES ===\n');
foil_wires = {};
for i = 1:length(wire_names)
    name = wire_names{i};
    if ~isempty(strfind(lower(name), 'foil'))
        foil_wires{end+1} = name;
    end
end

fprintf(fid, 'Found %d foil wires:\n', length(foil_wires));
for i = 1:length(foil_wires)
    fprintf(fid, '  %d. %s\n', i, foil_wires{i});
end
fprintf(fid, '\n');

% Inspect foil wires in detail
fprintf(fid, '=== DETAILED INSPECTION OF FOIL WIRES ===\n\n');
num_to_inspect = min(10, length(foil_wires));

for i = 1:num_to_inspect
    wire_name = foil_wires{i};
    wire = wire_db.(wire_name);

    fprintf(fid, '--- Wire %d: %s ---\n', i, wire_name);
    fprintf(fid, 'Fields present: ');
    fields = fieldnames(wire);
    for j = 1:length(fields)
        fprintf(fid, '%s', fields{j});
        if j < length(fields)
            fprintf(fid, ', ');
        end
    end
    fprintf(fid, '\n');

    % Check for dimensional fields
    fprintf(fid, 'Dimensional data:\n');

    if isfield(wire, 'foil_width')
        fprintf(fid, '  foil_width: %.6f m (%.3f mm)\n', wire.foil_width, wire.foil_width*1e3);
    else
        fprintf(fid, '  foil_width: NOT FOUND\n');
    end

    if isfield(wire, 'foil_thickness')
        fprintf(fid, '  foil_thickness: %.6f m (%.3f mm)\n', wire.foil_thickness, wire.foil_thickness*1e3);
    else
        fprintf(fid, '  foil_thickness: NOT FOUND\n');
    end

    if isfield(wire, 'rect_width')
        fprintf(fid, '  rect_width: %.6f m (%.3f mm)\n', wire.rect_width, wire.rect_width*1e3);
    else
        fprintf(fid, '  rect_width: NOT FOUND\n');
    end

    if isfield(wire, 'rect_height')
        fprintf(fid, '  rect_height: %.6f m (%.3f mm)\n', wire.rect_height, wire.rect_height*1e3);
    else
        fprintf(fid, '  rect_height: NOT FOUND\n');
    end

    if isfield(wire, 'width')
        fprintf(fid, '  width: %.6f m (%.3f mm)\n', wire.width, wire.width*1e3);
    else
        fprintf(fid, '  width: NOT FOUND\n');
    end

    if isfield(wire, 'thickness')
        fprintf(fid, '  thickness: %.6f m (%.3f mm)\n', wire.thickness, wire.thickness*1e3);
    else
        fprintf(fid, '  thickness: NOT FOUND\n');
    end

    if isfield(wire, 'conductor_shape')
        fprintf(fid, '  conductor_shape: %s\n', wire.conductor_shape);
    else
        fprintf(fid, '  conductor_shape: NOT FOUND\n');
    end

    if isfield(wire, 'area')
        fprintf(fid, '  area: %.6e m^2\n', wire.area);
    else
        fprintf(fid, '  area: NOT FOUND\n');
    end

    fprintf(fid, '\n');
end

% Look for the specific wires mentioned by the user
fprintf(fid, '=== CHECKING SPECIFIC WIRES MENTIONED ===\n');
test_wires = {'Foil_0_038', 'Foil_0_005'};

for i = 1:length(test_wires)
    wire_name = test_wires{i};
    wire_name_sanitized = strrep(wire_name, '.', '_');

    if isfield(wire_db, wire_name_sanitized)
        fprintf(fid, '\nWire: %s (field: %s) - FOUND\n', wire_name, wire_name_sanitized);
        wire = wire_db.(wire_name_sanitized);

        fprintf(fid, '  All fields: ');
        fields = fieldnames(wire);
        for j = 1:length(fields)
            fprintf(fid, '%s', fields{j});
            if j < length(fields)
                fprintf(fid, ', ');
            end
        end
        fprintf(fid, '\n');

        if isfield(wire, 'foil_width') && isfield(wire, 'foil_thickness')
            fprintf(fid, '  Dimensions: %.3f mm x %.3f mm\n', ...
                wire.foil_width*1e3, wire.foil_thickness*1e3);
        elseif isfield(wire, 'rect_width') && isfield(wire, 'rect_height')
            fprintf(fid, '  Dimensions: %.3f mm x %.3f mm\n', ...
                wire.rect_width*1e3, wire.rect_height*1e3);
        else
            fprintf(fid, '  WARNING: No dimensional data found!\n');
        end
    else
        fprintf(fid, '\nWire: %s (tried field: %s) - NOT FOUND\n', wire_name, wire_name_sanitized);
    end
end

fprintf(fid, '\n=== INSPECTION COMPLETE ===\n');
fclose(fid);

fprintf('Results written to: %s\n', output_file);
