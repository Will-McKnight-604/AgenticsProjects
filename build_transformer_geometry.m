% build_transformer_geometry.m
% Build transformer geometry with OpenMagnetics-compliant spacing
% Properly handles inter-winding insulation distances

function [conductors, winding_map] = build_transformer_geometry(winding_config, width, height, gap_layer, gap_turn, varargin)
% Build transformer geometry with multiple windings, layers, and turns
% Now includes proper inter-winding spacing based on voltage and insulation
%
% Inputs:
%   winding_config - Cell array defining each winding:
%                    {winding_id, N_turns, N_layers, I_rms, phase_deg, voltage_peak}
%                    Example: {1, 10, 2, 5.0, 0, 325} = Primary with 10 turns, 325V peak
%                             {2, 20, 4, 2.5, 180, 48} = Secondary with 20 turns, 48V peak
%   width         - Conductor width [m]
%   height        - Conductor height [m]
%   gap_layer     - Gap between layers [m]
%   gap_turn      - Gap between turns within a layer [m]
%   varargin{1}   - (optional) Insulation config structure with fields:
%                   .insulation_class - 'basic', 'supplementary', 'reinforced'
%                   .pollution_degree - 1-4
%
% Outputs:
%   conductors    - [N_conductors x 6] array: [x, y, width, height, I, phase]
%   winding_map   - Structure mapping conductors to windings and turns

    % Parse optional insulation config
    if nargin > 5 && ~isempty(varargin{1})
        insulation_config = varargin{1};
    else
        insulation_config = struct();
        insulation_config.insulation_class = 'basic';
        insulation_config.pollution_degree = 2;
    end

    N_windings = length(winding_config);
    conductors = [];

    % Initialize winding map
    winding_map.winding_id = [];      % Which winding (e.g., primary=1, secondary=2)
    winding_map.turn_num = [];        % Which turn within that winding
    winding_map.layer_num = [];       % Which layer
    winding_map.conductor_idx = [];   % Index in conductors array

    conductor_idx = 0;
    y_position = 0;  % Start position

    fprintf('=== Building Transformer with OpenMagnetics Spacing ===\n');

    for w = 1:N_windings
        winding_id = winding_config{w}{1};
        N_turns    = winding_config{w}{2};
        N_layers   = winding_config{w}{3};
        I_rms      = winding_config{w}{4};
        phase_deg  = winding_config{w}{5};

        % Get voltage if provided (6th element)
        if length(winding_config{w}) >= 6
            V_peak = winding_config{w}{6};
        else
            V_peak = 0;  % Unknown voltage
        end

        fprintf('\nWinding %d: %d turns, %d layers, %.1f A, %.1f deg', ...
            winding_id, N_turns, N_layers, I_rms, phase_deg);
        if V_peak > 0
            fprintf(', %.1f V peak', V_peak);
        end
        fprintf('\n');

        % Distribute turns across layers
        % Strategy: round-robin distribution
        turns_per_layer = floor(N_turns / N_layers);
        extra_turns = mod(N_turns, N_layers);

        turn_counter = 0;

        % Track start position of this winding
        winding_start_y = y_position;

        for layer = 1:N_layers
            % How many turns in this layer?
            if layer <= extra_turns
                turns_this_layer = turns_per_layer + 1;
            else
                turns_this_layer = turns_per_layer;
            end

            for turn = 1:turns_this_layer
                turn_counter = turn_counter + 1;
                conductor_idx = conductor_idx + 1;

                % Position: stack turns vertically within each layer
                x_pos = 0;  % All conductors aligned (can modify for interleaving)
                y_pos = y_position;

                % Add conductor
                conductors = [conductors;
                             x_pos, y_pos, width, height, I_rms, phase_deg];

                % Map this conductor
                winding_map.winding_id(conductor_idx) = winding_id;
                winding_map.turn_num(conductor_idx) = turn_counter;
                winding_map.layer_num(conductor_idx) = layer;
                winding_map.conductor_idx(conductor_idx) = conductor_idx;

                % Move to next turn position
                y_position = y_position + height + gap_turn;
            end

            % Add layer gap between layers
            if layer < N_layers
                y_position = y_position - gap_turn + gap_layer;
            end
        end

        % Calculate winding height
        winding_height = y_position - winding_start_y;
        fprintf('  Winding height: %.3f mm\n', winding_height * 1e3);

        % Add inter-winding spacing (if not last winding)
        if w < N_windings
            % Calculate proper inter-winding gap using OpenMagnetics rules
            inter_winding_gap = calculate_inter_winding_gap(winding_config{w}, ...
                winding_config{w+1}, width, height, insulation_config);

            fprintf('  Inter-winding gap to next: %.3f mm\n', inter_winding_gap * 1e3);

            % Remove the turn gap and add proper inter-winding gap
            y_position = y_position - gap_turn + inter_winding_gap;
        else
            % Last winding - remove trailing turn gap
            y_position = y_position - gap_turn;
        end
    end

    % Convert to column vectors for consistency
    winding_map.winding_id = winding_map.winding_id(:);
    winding_map.turn_num = winding_map.turn_num(:);
    winding_map.layer_num = winding_map.layer_num(:);
    winding_map.conductor_idx = winding_map.conductor_idx(:);

    % Store configuration for reference
    winding_map.config = winding_config;
    winding_map.insulation_config = insulation_config;

    % Summary
    total_height = y_position;
    fprintf('\n=== Transformer Build Summary ===\n');
    fprintf('Total conductors: %d\n', size(conductors, 1));
    fprintf('Total height: %.3f mm\n', total_height * 1e3);
    fprintf('Windings: %d\n', N_windings);
end

function gap = calculate_inter_winding_gap(winding1_config, winding2_config, ...
    width, height, insulation_config)
% Calculate OpenMagnetics-compliant inter-winding spacing
%
% Inputs:
%   winding1_config - Config cell for first winding
%   winding2_config - Config cell for second winding
%   width, height   - Conductor dimensions
%   insulation_config - Insulation requirements
%
% Output:
%   gap - Required spacing between windings [m]

    % Constants
    MIN_WINDING_GAP = 1.0e-3;     % 1 mm minimum
    CREEPAGE_FACTOR = 1.0e-3;     % mm per volt
    CLEARANCE_FACTOR = 0.5e-3;    % mm per volt

    % Start with minimum
    gap = MIN_WINDING_GAP;

    % Get voltages if available
    if length(winding1_config) >= 6 && length(winding2_config) >= 6
        V1 = abs(winding1_config{6});
        V2 = abs(winding2_config{6});
        V_diff = abs(V1 - V2);

        % Calculate voltage-dependent spacing
        creepage_required = V_diff * CREEPAGE_FACTOR;
        clearance_required = V_diff * CLEARANCE_FACTOR;

        voltage_spacing = max(creepage_required, clearance_required);
        gap = max(gap, voltage_spacing);
    end

    % Apply insulation class multiplier
    if isfield(insulation_config, 'insulation_class')
        switch lower(insulation_config.insulation_class)
            case 'basic'
                factor = 1.0;
            case 'supplementary'
                factor = 1.5;
            case 'reinforced'
                factor = 3.0;
            otherwise
                factor = 1.0;
        end
        gap = gap * factor;
    end

    % Apply pollution degree multiplier
    if isfield(insulation_config, 'pollution_degree')
        degree = insulation_config.pollution_degree;
        pollution_factors = [1.0, 1.25, 1.6, 2.0];  % For degrees 1-4
        if degree >= 1 && degree <= 4
            gap = gap * pollution_factors(degree);
        end
    end

    % Ensure practical minimum based on conductor size
    conductor_size = sqrt(width * height);
    gap = max(gap, 0.5 * conductor_size);

    % Absolute minimum
    gap = max(gap, 0.5e-3);  % At least 0.5 mm
end
