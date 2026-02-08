% debug_geometry_structure.m
% Diagnostic function to check geometry structure

function debug_geometry_structure(geom, verbose)

    if nargin < 2
        verbose = true;
    end

    fprintf('\n=== GEOMETRY STRUCTURE DIAGNOSTIC ===\n');

    % Check if geom exists and is a struct
    if ~exist('geom', 'var')
        error('Geometry variable does not exist');
    end

    if ~isstruct(geom)
        error('Geometry is not a structure (type: %s)', class(geom));
    end

    % List all fields
    field_names = fieldnames(geom);
    fprintf('Number of fields: %d\n', length(field_names));
    fprintf('Fields present:\n');
    for i = 1:length(field_names)
        fprintf('  - %s\n', field_names{i});
    end
    fprintf('\n');

    % Check critical fields
    critical_fields = {'filaments', 'Nf', 'Nc', 'R', 'L', 'C'};
    fprintf('Critical field check:\n');
    all_present = true;

    for i = 1:length(critical_fields)
        field = critical_fields{i};
        if isfield(geom, field)
            fprintf('  ✓ %s: ', field);

            % Get size info
            val = geom.(field);
            if isnumeric(val)
                if isscalar(val)
                    fprintf('scalar = %g\n', val);
                else
                    fprintf('matrix %s\n', mat2str(size(val)));
                end
            else
                fprintf('%s\n', class(val));
            end
        else
            fprintf('  ✗ %s: MISSING!\n', field);
            all_present = false;
        end
    end

    fprintf('\n');

    % Detailed info if verbose
    if verbose && all_present
        fprintf('Detailed Information:\n');

        if isfield(geom, 'Nf')
            fprintf('  Number of filaments (Nf): %d\n', geom.Nf);
        end

        if isfield(geom, 'Nc')
            fprintf('  Number of conductors (Nc): %d\n', geom.Nc);
        end

        if isfield(geom, 'filaments')
            fprintf('  Filaments array: %d rows x %d cols\n', ...
                size(geom.filaments, 1), size(geom.filaments, 2));

            % Check if Nf matches filaments size
            if isfield(geom, 'Nf')
                if geom.Nf == size(geom.filaments, 1)
                    fprintf('    ✓ Nf matches filaments size\n');
                else
                    fprintf('    ✗ WARNING: Nf (%d) != filaments rows (%d)\n', ...
                        geom.Nf, size(geom.filaments, 1));
                end
            end
        end

        if isfield(geom, 'R')
            fprintf('  Resistance matrix (R): %d x %d\n', size(geom.R, 1), size(geom.R, 2));
            if ~issymmetric(diag(diag(geom.R)))
                fprintf('    Note: R should be diagonal\n');
            end
        end

        if isfield(geom, 'L')
            fprintf('  Inductance matrix (L): %d x %d\n', size(geom.L, 1), size(geom.L, 2));
        end

        if isfield(geom, 'C')
            fprintf('  Constraint matrix (C): %d x %d\n', size(geom.C, 1), size(geom.C, 2));

            % Check if C is compatible
            if isfield(geom, 'Nc') && isfield(geom, 'Nf')
                if size(geom.C, 1) == geom.Nc && size(geom.C, 2) == geom.Nf
                    fprintf('    ✓ C dimensions compatible with Nc and Nf\n');
                else
                    fprintf('    ✗ WARNING: C dimensions [%d x %d] != [Nc=%d x Nf=%d]\n', ...
                        size(geom.C, 1), size(geom.C, 2), geom.Nc, geom.Nf);
                end
            end
        end
    end

    fprintf('\n');

    if all_present
        fprintf('Status: ✓ All critical fields present\n');
    else
        fprintf('Status: ✗ Missing critical fields - geometry is incomplete\n');
    end

    fprintf('=====================================\n\n');
end


% Helper function to test geometry creation
function test_geometry_creation()

    fprintf('Testing geometry creation...\n\n');

    % Test parameters
    sigma = 5.8e7;
    mu0 = 4*pi*1e-7;
    Nx = 5;
    Ny = 5;

    % Simple 2-conductor geometry
    conductors = [
        0,    0,      2e-3, 1e-3, 1, 0;   % x, y, w, h, I, phase
        0,    1.2e-3, 2e-3, 1e-3, 1, 0;
    ];

    % Build geometry
    geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny);

    % Debug it
    debug_geometry_structure(geom, true);

    fprintf('Test complete!\n');
end
