% Simple cache check - just load and display basic info
try
    load('openmagnetics_cache.mat');
    disp('Cache loaded successfully');
    disp(['Wire database has ', num2str(length(fieldnames(wire_database))), ' wires']);

    % List all wire names
    names = fieldnames(wire_database);
    foils = {};
    for i = 1:length(names)
        if ~isempty(strfind(names{i}, 'Foil')) || ~isempty(strfind(names{i}, 'foil'))
            foils{end+1} = names{i};
        end
    end

    disp(['Found ', num2str(length(foils)), ' foil wires']);

    % Check first foil
    if ~isempty(foils)
        disp(' ');
        disp(['First foil wire: ', foils{1}]);
        wire = wire_database.(foils{1});
        disp('Fields:');
        disp(fieldnames(wire));

        if isfield(wire, 'foil_width')
            disp(['  foil_width = ', num2str(wire.foil_width*1e3), ' mm']);
        end
        if isfield(wire, 'foil_thickness')
            disp(['  foil_thickness = ', num2str(wire.foil_thickness*1e3), ' mm']);
        end
    end
catch ME
    disp(['ERROR: ', ME.message]);
end
