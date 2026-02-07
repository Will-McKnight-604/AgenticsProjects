function spacing = calculate_winding_spacing(config)
% Calculate OpenMagnetics-compliant winding spacing
% Based on IEC 60664-1 and UL standards
%
% Inputs:
%   config - Structure with optional fields:
%     .voltage_primary    - Primary winding voltage (V)
%     .voltage_secondary  - Secondary winding voltage (V)
%     .insulation_class   - 'basic', 'supplementary', 'reinforced'
%     .pollution_degree   - 1-4 (IEC 60664-1)
%     .width              - Conductor width (m)
%     .height             - Conductor height (m)
%
% Outputs:
%   spacing - Structure with fields:
%     .gap_filar      - Gap between parallel strands (m)
%     .gap_layer      - Gap between turns (m)
%     .gap_winding    - Gap between different windings (m)

    % Default minimum distances
    MIN_FILAR_GAP = 0.025e-3;     % 25 µm (parallel strands, same potential)
    MIN_TURN_GAP = 0.05e-3;       % 50 µm (turn-to-turn)
    MIN_WINDING_GAP = 1.0e-3;     % 1 mm (winding-to-winding minimum)

    % Voltage-dependent factors
    CREEPAGE_FACTOR = 1.0e-3;     % mm per volt
    CLEARANCE_FACTOR = 0.5e-3;    % mm per volt

    % Initialize with minimums
    spacing.gap_filar = MIN_FILAR_GAP;
    spacing.gap_layer = MIN_TURN_GAP;
    spacing.gap_winding = MIN_WINDING_GAP;

    % Calculate voltage-dependent spacing for inter-winding gap
    if isfield(config, 'voltage_primary') && isfield(config, 'voltage_secondary')
        V1 = abs(config.voltage_primary);
        V2 = abs(config.voltage_secondary);
        V_diff = abs(V1 - V2);

        % Calculate required spacing based on voltage
        creepage_required = V_diff * CREEPAGE_FACTOR;
        clearance_required = V_diff * CLEARANCE_FACTOR;

        voltage_spacing = max(creepage_required, clearance_required);
        spacing.gap_winding = max(spacing.gap_winding, voltage_spacing);

        % Also update turn-to-turn spacing based on per-turn voltage
        if isfield(config, 'n_turns') && config.n_turns > 0
            V_per_turn = V1 / config.n_turns;
            if V_per_turn > 100
                extra_turn_spacing = (V_per_turn - 100) * CREEPAGE_FACTOR;
                spacing.gap_layer = spacing.gap_layer + extra_turn_spacing;
            end
        end
    end

    % Insulation class multiplier
    if isfield(config, 'insulation_class')
        switch lower(config.insulation_class)
            case 'basic'
                insulation_factor = 1.0;
            case 'supplementary'
                insulation_factor = 1.5;
            case 'reinforced'
                insulation_factor = 3.0;  % 3x for reinforced insulation
            otherwise
                insulation_factor = 1.0;
        end

        spacing.gap_layer = spacing.gap_layer * insulation_factor;
        spacing.gap_winding = spacing.gap_winding * insulation_factor;
    end

    % Pollution degree multiplier (environmental conditions)
    if isfield(config, 'pollution_degree')
        switch config.pollution_degree
            case 1  % Clean environment (sealed)
                pollution_factor = 1.0;
            case 2  % Normal environment
                pollution_factor = 1.25;
            case 3  % Industrial environment
                pollution_factor = 1.6;
            case 4  % Severe contamination
                pollution_factor = 2.0;
            otherwise
                pollution_factor = 1.25;
        end

        spacing.gap_winding = spacing.gap_winding * pollution_factor;
    end

    % Ensure minimum practical gaps
    spacing.gap_filar = max(spacing.gap_filar, 0.02e-3);   % At least 20 µm
    spacing.gap_layer = max(spacing.gap_layer, 0.05e-3);   % At least 50 µm
    spacing.gap_winding = max(spacing.gap_winding, 0.5e-3); % At least 0.5 mm

    % If conductor dimensions provided, ensure gaps are not too small relative to conductor
    if isfield(config, 'width') && isfield(config, 'height')
        conductor_size = sqrt(config.width * config.height);

        % Turn gap should be at least 5% of conductor size
        spacing.gap_layer = max(spacing.gap_layer, 0.05 * conductor_size);

        % Winding gap should be at least 50% of conductor size
        spacing.gap_winding = max(spacing.gap_winding, 0.5 * conductor_size);
    end
end
