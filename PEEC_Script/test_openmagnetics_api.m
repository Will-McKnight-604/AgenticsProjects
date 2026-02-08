% test_openmagnetics_api.m
% Test the OpenMagnetics API interface

clear; clc;

fprintf('=== TESTING OPENMAGNETICS API INTERFACE ===\n\n');

% Create API interface object
api = openmagnetics_api_interface();

%% Test 1: Get wire database
fprintf('\n--- Test 1: Wire Database ---\n');
wires = api.get_wires();

if ~isempty(wires)
    fprintf('Success! Retrieved wire data\n');
    api.list_available_wires();
else
    fprintf('Could not retrieve wire data\n');
end

%% Test 2: Get specific wire info
fprintf('\n--- Test 2: Specific Wire Info ---\n');
wire_info = api.get_wire_info('AWG_22');

if ~isempty(wire_info)
    fprintf('Wire: AWG 22\n');
    fprintf('  Diameter: %.3f mm\n', wire_info.diameter*1e3);
    fprintf('  Area: %.3e m²\n', wire_info.area);
    fprintf('  Resistance: %.3f Ω/m\n', wire_info.resistance);
end

%% Test 3: Convert wire to conductor dimensions
fprintf('\n--- Test 3: Wire to Conductor Mapping ---\n');
[width, height] = api.wire_to_conductor_dims('AWG_22');

if ~isempty(width)
    fprintf('Rectangular conductor equivalent:\n');
    fprintf('  Width: %.3f mm\n', width*1e3);
    fprintf('  Height: %.3f mm\n', height*1e3);
    fprintf('  Can use these in your PEEC solver!\n');
end

%% Test 4: Litz wire
fprintf('\n--- Test 4: Litz Wire Info ---\n');
wire_info = api.get_wire_info('Litz_100_38');

if ~isempty(wire_info)
    fprintf('Litz Wire: 100 × 38 AWG\n');
    fprintf('  Strands: %d\n', wire_info.strands);
    fprintf('  Strand diameter: %.3f mm\n', wire_info.strand_diameter*1e3);
    fprintf('  Outer diameter: %.3f mm\n', wire_info.outer_diameter*1e3);
    fprintf('  Total area: %.3e m²\n', wire_info.area);

    % Map to conductor
    [width, height] = api.wire_to_conductor_dims('Litz_100_38');
end

%% Test 5: Core database
fprintf('\n--- Test 5: Core Database ---\n');
cores = api.get_cores();

if ~isempty(cores)
    fprintf('Success! Retrieved core data\n');
    core_list = fieldnames(cores);
    fprintf('Available cores: %d\n', length(core_list));

    % Show first core
    if length(core_list) > 0
        core_name = core_list{1};
        core = cores.(core_name);
        fprintf('\nExample core: %s\n', core_name);
        if isfield(core, 'shape')
            fprintf('  Shape: %s\n', core.shape);
        end
        if isfield(core, 'material')
            fprintf('  Material: %s\n', core.material);
        end
        if isfield(core, 'Ae')
            fprintf('  Effective area: %.1f mm²\n', core.Ae*1e6);
        end
    end
end

%% Test 6: Material database
fprintf('\n--- Test 6: Material Database ---\n');
materials = api.get_materials();

if ~isempty(materials)
    fprintf('Success! Retrieved material data\n');
    mat_list = fieldnames(materials);

    for i = 1:length(mat_list)
        mat = materials.(mat_list{i});
        fprintf('  %s: µᵢ=%d, Bsat=%.2f T\n', ...
            mat_list{i}, mat.mu_initial, mat.Bsat);
    end
end

%% Demo: Use in your transformer design
fprintf('\n=== DEMO: Using Wire Data in Your Design ===\n');

% Choose a wire
wire_choice = 'AWG_22';
[w, h] = api.wire_to_conductor_dims(wire_choice);

% Use in your configuration
config.n_filar = 2;  % Bi-filar
config.n_turns = 10;
config.n_windings = 1;
config.width = w;    % From OpenMagnetics!
config.height = h;   % From OpenMagnetics!
config.gap_layer = 0.2e-3;
config.gap_filar = 0.05e-3;
config.currents = 10;
config.phases = 0;
config.x_offset = 0;

fprintf('\nConfiguration using %s wire:\n', wire_choice);
fprintf('  Conductor: %.3f × %.3f mm\n', config.width*1e3, config.height*1e3);
fprintf('  Turns: %d\n', config.n_turns);
fprintf('  Filar: %d\n', config.n_filar);

fprintf('\n=== TEST COMPLETE ===\n');
fprintf('You can now integrate this into your GUI!\n');
