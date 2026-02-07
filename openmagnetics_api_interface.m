% openmagnetics_api_interface.m
% Interface to OpenMagnetics data following the MAS (Magnetic Agnostic Structure)
%
% Provides offline fallback databases for:
%   - Wire specifications (round, litz, rectangular, foil)
%   - Core shapes with bobbin/winding window geometry
%   - Core materials with magnetic properties
%
% Based on the OpenMagnetics MAS schema:
%   https://github.com/OpenMagnetics/MAS
%
% Wire data follows MAS wire definitions with conductingDiameter,
% outerDiameter, numberConductors, etc.
%
% Core data follows MAS core definitions with processedDescription
% containing effectiveParameters (Ae, le, Ve) and windingWindows.

classdef openmagnetics_api_interface < handle

    properties
        wire_database       % Struct of wire specs keyed by name
        core_database       % Struct of core specs keyed by name
        material_database   % Struct of material specs keyed by name
        api_available       % Whether online API is reachable
    end

    methods

        function obj = openmagnetics_api_interface()
            % Constructor - initialize with offline databases
            obj.api_available = false;
            obj.wire_database = obj.build_wire_database();
            obj.core_database = obj.build_core_database();
            obj.material_database = obj.build_material_database();
            fprintf('OpenMagnetics API interface initialized (offline mode)\n');
            fprintf('  Wires: %d | Cores: %d | Materials: %d\n', ...
                length(fieldnames(obj.wire_database)), ...
                length(fieldnames(obj.core_database)), ...
                length(fieldnames(obj.material_database)));
        end

        %% ============================================================
        %  PUBLIC DATABASE ACCESS
        %  ============================================================

        function wires = get_wires(obj)
            wires = obj.wire_database;
        end

        function cores = get_cores(obj)
            cores = obj.core_database;
        end

        function materials = get_materials(obj)
            materials = obj.material_database;
        end

        function info = get_wire_info(obj, wire_name)
            % Return wire specification struct for a given wire name
            if isfield(obj.wire_database, wire_name)
                info = obj.wire_database.(wire_name);
            else
                warning('Wire "%s" not found in database', wire_name);
                info = [];
            end
        end

        function info = get_core_info(obj, core_name)
            % Return core specification struct for a given core name
            if isfield(obj.core_database, core_name)
                info = obj.core_database.(core_name);
            else
                warning('Core "%s" not found in database', core_name);
                info = [];
            end
        end

        function [width, height, shape] = wire_to_conductor_dims(obj, wire_name)
            % Convert wire specification to equivalent rectangular conductor
            % dimensions for PEEC analysis.
            %
            % For round wire: width = height = diameter (area-equivalent square)
            % For litz wire:  width = height = outer_diameter equivalent
            % For rectangular: width and height directly from spec
            % For foil:       width (thin) x height (wide)
            %
            % Returns:
            %   width  - Conductor width in meters (radial direction)
            %   height - Conductor height in meters (axial direction)
            %   shape  - 'round', 'rectangular', 'foil', or 'litz'

            if ~isfield(obj.wire_database, wire_name)
                warning('Wire "%s" not in database, using defaults', wire_name);
                width  = 0.644e-3;
                height = 0.644e-3;
                shape  = 'round';
                return;
            end

            wire = obj.wire_database.(wire_name);

            switch wire.type
                case 'round'
                    % MAS: conductingDiameter -> area-equivalent square
                    d = wire.diameter;
                    equiv = d * sqrt(pi/4);  % Area-equivalent square side
                    width  = equiv;
                    height = equiv;
                    shape  = 'round';

                case 'litz'
                    % MAS: bundle treated as single round conductor
                    d = wire.outer_diameter;
                    equiv = d * sqrt(pi/4);
                    width  = equiv;
                    height = equiv;
                    shape  = 'round';

                case 'rectangular'
                    % MAS: conductingWidth x conductingHeight
                    width  = wire.width;
                    height = wire.height;
                    shape  = 'rectangular';

                case 'foil'
                    % MAS: foil thickness (thin) x foil width (wide)
                    width  = wire.thickness;   % radial (thin dimension)
                    height = wire.foil_width;  % axial (wide dimension)
                    shape  = 'foil';

                otherwise
                    d = wire.diameter;
                    equiv = d * sqrt(pi/4);
                    width  = equiv;
                    height = equiv;
                    shape  = 'round';
            end
        end

        function od = get_wire_outer_diameter(obj, wire_name)
            % Get wire outer diameter including insulation
            % Follows MAS outerDiameter field
            wire = obj.wire_database.(wire_name);

            if isfield(wire, 'outer_diameter')
                od = wire.outer_diameter;
            elseif isfield(wire, 'diameter')
                od = wire.diameter * 1.12;  % ~12% insulation buildup
            else
                od = 1e-3;  % fallback
            end
        end

        function list_available_wires(obj)
            % Print all available wires
            names = fieldnames(obj.wire_database);
            fprintf('\nAvailable wires (%d):\n', length(names));
            for i = 1:length(names)
                w = obj.wire_database.(names{i});
                switch w.type
                    case 'round'
                        fprintf('  %-20s  Round  d=%.3f mm  R=%.3f Ohm/m\n', ...
                            names{i}, w.diameter*1e3, w.resistance);
                    case 'litz'
                        fprintf('  %-20s  Litz   %dx%.3fmm  OD=%.3f mm\n', ...
                            names{i}, w.strands, w.strand_diameter*1e3, w.outer_diameter*1e3);
                    case 'rectangular'
                        fprintf('  %-20s  Rect   %.2fx%.2f mm\n', ...
                            names{i}, w.width*1e3, w.height*1e3);
                    case 'foil'
                        fprintf('  %-20s  Foil   t=%.3f mm  w=%.1f mm\n', ...
                            names{i}, w.thickness*1e3, w.foil_width*1e3);
                end
            end
        end

        function list_available_cores(obj)
            % Print all available cores
            names = fieldnames(obj.core_database);
            fprintf('\nAvailable cores (%d):\n', length(names));
            for i = 1:length(names)
                c = obj.core_database.(names{i});
                fprintf('  %-20s  %s  Ae=%.1f mm^2  le=%.1f mm\n', ...
                    names{i}, c.shape, c.Ae*1e6, c.le*1e3);
            end
        end

        %% ============================================================
        %  OFFLINE WIRE DATABASE
        %  Following MAS wire schema with type, conductingDiameter,
        %  outerDiameter, material, numberConductors, etc.
        %  ============================================================

        function db = build_wire_database(obj)
            db = struct();

            % --- Round solid wires (AWG series) ---
            % Data: [AWG, bare_diameter_mm, resistance_ohm_per_m]
            awg_data = {
                'AWG_10', 2.588, 0.00328;
                'AWG_12', 2.053, 0.00521;
                'AWG_14', 1.628, 0.00829;
                'AWG_16', 1.291, 0.01317;
                'AWG_18', 1.024, 0.02095;
                'AWG_20', 0.812, 0.03331;
                'AWG_22', 0.644, 0.05296;
                'AWG_24', 0.511, 0.08420;
                'AWG_26', 0.405, 0.13385;
                'AWG_28', 0.321, 0.21266;
                'AWG_30', 0.255, 0.33799;
                'AWG_32', 0.202, 0.53735;
                'AWG_34', 0.160, 0.85429;
                'AWG_36', 0.127, 1.35825;
                'AWG_38', 0.101, 2.15885;
                'AWG_40', 0.080, 3.43124;
                'AWG_42', 0.063, 5.45455;
                'AWG_44', 0.050, 8.67200;
            };

            insulation_buildup = 1.12;  % Grade 2 ~12%

            for i = 1:size(awg_data, 1)
                name = awg_data{i, 1};
                d_bare = awg_data{i, 2} * 1e-3;  % Convert to meters
                R = awg_data{i, 3};

                w = struct();
                w.type = 'round';
                w.diameter = d_bare;
                w.outer_diameter = d_bare * insulation_buildup;
                w.area = pi/4 * d_bare^2;
                w.resistance = R;
                w.material = 'copper';

                db.(name) = w;
            end

            % --- Litz wires ---
            % Format: name, n_strands, strand_awg, strand_diameter_mm
            litz_data = {
                'Litz_7_40',    7,   40, 0.080;
                'Litz_20_38',   20,  38, 0.101;
                'Litz_40_38',   40,  38, 0.101;
                'Litz_50_40',   50,  40, 0.080;
                'Litz_100_38',  100, 38, 0.101;
                'Litz_100_40',  100, 40, 0.080;
                'Litz_200_40',  200, 40, 0.080;
                'Litz_300_38',  300, 38, 0.101;
                'Litz_400_40',  400, 40, 0.080;
                'Litz_600_40',  600, 40, 0.080;
                'Litz_800_40',  800, 40, 0.080;
                'Litz_1000_44', 1000, 44, 0.050;
            };

            for i = 1:size(litz_data, 1)
                name = litz_data{i, 1};
                n = litz_data{i, 2};
                strand_d = litz_data{i, 4} * 1e-3;

                w = struct();
                w.type = 'litz';
                w.strands = n;
                w.strand_diameter = strand_d;
                w.strand_area = pi/4 * strand_d^2;
                w.area = n * w.strand_area;
                % Bundle OD estimate: packing factor ~0.55-0.65
                w.outer_diameter = strand_d * insulation_buildup * sqrt(n / 0.58) * 1.15;
                w.resistance = 1 / (5.8e7 * w.area);
                w.material = 'copper';

                db.(name) = w;
            end

            % --- Rectangular / planar wires ---
            rect_data = {
                'Rect_2x0_5',  2.0e-3, 0.5e-3;
                'Rect_3x0_5',  3.0e-3, 0.5e-3;
                'Rect_5x0_5',  5.0e-3, 0.5e-3;
                'Rect_3x1',    3.0e-3, 1.0e-3;
                'Rect_5x1',    5.0e-3, 1.0e-3;
                'Rect_8x1',    8.0e-3, 1.0e-3;
                'Rect_10x1',  10.0e-3, 1.0e-3;
                'Rect_5x2',    5.0e-3, 2.0e-3;
                'Rect_10x2',  10.0e-3, 2.0e-3;
            };

            for i = 1:size(rect_data, 1)
                name = rect_data{i, 1};
                h = rect_data{i, 2};  % height (axial, tall)
                t = rect_data{i, 3};  % width (radial, thin)

                w = struct();
                w.type = 'rectangular';
                w.height = h;      % axial dimension
                w.width  = t;      % radial dimension
                w.area = h * t;
                w.outer_diameter = sqrt(h^2 + t^2);  % diagonal for reference
                w.resistance = 1 / (5.8e7 * w.area);
                w.material = 'copper';

                db.(name) = w;
            end

            % --- Foil wires ---
            foil_data = {
                'Foil_0_05x10',  0.05e-3, 10e-3;
                'Foil_0_05x20',  0.05e-3, 20e-3;
                'Foil_0_1x10',   0.10e-3, 10e-3;
                'Foil_0_1x20',   0.10e-3, 20e-3;
                'Foil_0_1x30',   0.10e-3, 30e-3;
                'Foil_0_2x20',   0.20e-3, 20e-3;
                'Foil_0_2x30',   0.20e-3, 30e-3;
                'Foil_0_5x20',   0.50e-3, 20e-3;
                'Foil_0_5x30',   0.50e-3, 30e-3;
            };

            for i = 1:size(foil_data, 1)
                name = foil_data{i, 1};
                t = foil_data{i, 2};  % thickness (radial)
                fw = foil_data{i, 3}; % foil width (axial)

                w = struct();
                w.type = 'foil';
                w.thickness = t;
                w.foil_width = fw;
                w.area = t * fw;
                w.outer_diameter = fw;  % For fit check: axial extent
                w.resistance = 1 / (5.8e7 * w.area);
                w.material = 'copper';

                db.(name) = w;
            end
        end

        %% ============================================================
        %  OFFLINE CORE DATABASE
        %  Following MAS processedDescription with effectiveParameters
        %  and windingWindows.
        %  ============================================================

        function db = build_core_database(obj)
            db = struct();

            % Core data format:
            %   shape, Ae(m^2), le(m), Ve(m^3), material,
            %   winding_window_width(m), winding_window_height(m)
            %
            % Winding window follows MAS windingWindows definition:
            %   width  = radial depth available for winding
            %   height = axial height available for winding

            core_entries = {
                % E-cores (ETD series)
                'ETD_29_16_10',  'ETD', 76e-6,  72e-3,  5.47e-6, 'N87', 10.3e-3, 11.2e-3;
                'ETD_34_17_11',  'ETD', 97e-6,  79e-3,  7.64e-6, 'N87', 11.0e-3, 12.5e-3;
                'ETD_39_20_13',  'ETD', 125e-6, 92e-3, 11.5e-6,  'N87', 13.1e-3, 14.2e-3;
                'ETD_44_22_15',  'ETD', 173e-6, 103e-3, 17.8e-6, 'N87', 14.5e-3, 16.0e-3;
                'ETD_49_25_16',  'ETD', 211e-6, 114e-3, 24.0e-6, 'N87', 16.3e-3, 18.0e-3;
                'ETD_54_28_19',  'ETD', 280e-6, 127e-3, 35.6e-6, 'N87', 18.0e-3, 20.0e-3;
                'ETD_59_31_22',  'ETD', 368e-6, 139e-3, 51.2e-6, 'N87', 20.2e-3, 22.5e-3;
                % E-cores (standard)
                'E_25_13_7',     'E',   52e-6,  57e-3,  2.96e-6, 'N87',  7.6e-3,  9.5e-3;
                'E_30_15_7',     'E',   60e-6,  67e-3,  4.02e-6, 'N87',  8.2e-3, 10.6e-3;
                'E_36_18_11',    'E',  120e-6,  74e-3,  8.88e-6, 'N87', 10.5e-3, 12.5e-3;
                'E_42_21_15',    'E',  178e-6,  97e-3, 17.3e-6,  'N87', 13.0e-3, 15.0e-3;
                'E_42_21_20',    'E',  234e-6,  97e-3, 22.7e-6,  'N87', 13.0e-3, 15.0e-3;
                'E_55_28_21',    'E',  354e-6, 124e-3, 43.9e-6,  'N87', 17.5e-3, 20.0e-3;
                'E_65_32_27',    'E',  540e-6, 147e-3, 79.4e-6,  'N87', 21.0e-3, 24.0e-3;
                'E_70_33_32',    'E',  680e-6, 149e-3, 101e-6,   'N87', 22.0e-3, 25.0e-3;
                'E_80_38_20',    'E',  395e-6, 184e-3, 72.7e-6,  'N87', 23.5e-3, 27.0e-3;
                % PQ cores
                'PQ_20_16',      'PQ',  62e-6,  46e-3,  2.85e-6, 'N87',  7.7e-3, 10.5e-3;
                'PQ_26_25',      'PQ', 121e-6,  58e-3,  6.53e-6, 'N87', 10.2e-3, 14.0e-3;
                'PQ_32_30',      'PQ', 167e-6,  76e-3, 12.7e-6,  'N87', 11.8e-3, 17.0e-3;
                'PQ_35_35',      'PQ', 196e-6,  87e-3, 17.0e-6,  'N87', 12.8e-3, 19.5e-3;
                'PQ_40_40',      'PQ', 201e-6, 102e-3, 20.5e-6,  'N87', 13.5e-3, 23.0e-3;
                'PQ_50_50',      'PQ', 328e-6, 113e-3, 37.1e-6,  'N87', 17.5e-3, 28.0e-3;
                % RM cores
                'RM_6',          'RM',  37e-6,  28e-3,  1.04e-6, 'N87',  4.6e-3,  6.3e-3;
                'RM_8',          'RM',  64e-6,  38e-3,  2.43e-6, 'N87',  6.2e-3,  8.0e-3;
                'RM_10',         'RM',  98e-6,  44e-3,  4.31e-6, 'N87',  7.8e-3, 10.0e-3;
                'RM_12',         'RM', 146e-6,  52e-3,  7.59e-6, 'N87',  9.5e-3, 12.0e-3;
                'RM_14',         'RM', 200e-6,  60e-3, 12.0e-6,  'N87', 11.0e-3, 14.0e-3;
                % EFD (low-profile)
                'EFD_15',        'EFD', 22e-6,  33e-3,  0.73e-6, 'N87',  4.3e-3,  8.5e-3;
                'EFD_20',        'EFD', 31e-6,  47e-3,  1.46e-6, 'N87',  5.4e-3, 11.2e-3;
                'EFD_25',        'EFD', 58e-6,  57e-3,  3.31e-6, 'N87',  7.2e-3, 14.5e-3;
                'EFD_30',        'EFD', 69e-6,  68e-3,  4.69e-6, 'N87',  8.0e-3, 17.0e-3;
                % Toroid (approximate rectangular window)
                'T_25_15_10',    'T',   49e-6,  55e-3,  2.69e-6, 'N87',  5.0e-3,  7.5e-3;
                'T_36_23_15',    'T',   96e-6,  78e-3,  7.49e-6, 'N87',  6.5e-3, 11.5e-3;
                'T_50_30_19',    'T',  173e-6, 107e-3, 18.5e-6,  'N87', 10.0e-3, 15.0e-3;
            };

            for i = 1:size(core_entries, 1)
                name = core_entries{i, 1};

                c = struct();
                c.shape        = core_entries{i, 2};
                c.Ae           = core_entries{i, 3};   % Effective area [m^2]
                c.le           = core_entries{i, 4};   % Effective path length [m]
                c.Ve           = core_entries{i, 5};   % Effective volume [m^3]
                c.material     = core_entries{i, 6};

                % MAS windingWindows: the available space for winding
                c.bobbin.width  = core_entries{i, 7};  % Radial depth [m]
                c.bobbin.height = core_entries{i, 8};  % Axial height [m]

                % Dimensional metadata
                c.manufacturer = 'TDK/EPCOS';

                db.(name) = c;
            end
        end

        %% ============================================================
        %  OFFLINE MATERIAL DATABASE
        %  Following MAS coreMaterial definitions
        %  ============================================================

        function db = build_material_database(obj)
            db = struct();

            % TDK/EPCOS ferrites
            mat_entries = {
                'N27',  'TDK',  2000, 0.41, 'MnZn', 1e5;
                'N30',  'TDK',  4300, 0.38, 'MnZn', 2e5;
                'N49',  'TDK',  1500, 0.40, 'MnZn', 5e5;
                'N87',  'TDK',  2200, 0.39, 'MnZn', 5e5;
                'N92',  'TDK',  1500, 0.41, 'MnZn', 3e5;
                'N95',  'TDK',  3000, 0.41, 'MnZn', 5e5;
                'N97',  'TDK',  2300, 0.41, 'MnZn', 5e5;
                '3C90', 'Ferroxcube', 2300, 0.38, 'MnZn', 2e5;
                '3C92', 'Ferroxcube', 1500, 0.40, 'MnZn', 3e5;
                '3C95', 'Ferroxcube', 3000, 0.41, 'MnZn', 5e5;
                '3C97', 'Ferroxcube', 3000, 0.41, 'MnZn', 5e5;
                '3F35', 'Ferroxcube', 1400, 0.39, 'MnZn', 1e6;
                '3F36', 'Ferroxcube', 1100, 0.38, 'MnZn', 2e6;
                'PC40', 'TDK',  2300, 0.39, 'MnZn', 5e5;
                'PC44', 'TDK',  2400, 0.39, 'MnZn', 3e5;
                'PC95', 'TDK',  3300, 0.41, 'MnZn', 5e5;
            };

            for i = 1:size(mat_entries, 1)
                name = mat_entries{i, 1};

                m = struct();
                m.manufacturer = mat_entries{i, 2};
                m.mu_initial   = mat_entries{i, 3};
                m.Bsat         = mat_entries{i, 4};   % Saturation flux density [T]
                m.family       = mat_entries{i, 5};
                m.max_freq     = mat_entries{i, 6};   % Recommended max frequency [Hz]

                db.(name) = m;
            end
        end

    end  % methods
end  % classdef
