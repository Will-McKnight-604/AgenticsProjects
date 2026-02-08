% build_multifilar_winding.m
% Build multi-filar winding configurations for PEEC analysis
% PARALLEL STRANDS STACK VERTICALLY (not horizontally)
%
% Follows MAS (Magnetic Agnostic Structure) winding representation:
%   Each physical turn is a conductor element positioned in (x, y) space.
%   Multi-filar strands are stacked vertically at each turn position.

function [conductors, winding_map, wire_shapes] = build_multifilar_winding(config)
% Build multi-filar winding configuration with VERTICAL stacking
%
% LAYOUT: Parallel strands stack vertically at each turn
%   Turn 1: [Strand 1]
%           [Strand 2]  <- stacked vertically with small gap
%           [Strand 3]
%           (gap_layer)
%   Turn 2: [Strand 1]
%           [Strand 2]
%           [Strand 3]
%   etc.
%
% All conductors are in ONE column (same X position)
%
% Returns:
%   conductors   - [N x 6] array: [x, y, width, height, current, phase]
%   winding_map  - [N x 1] array: which winding each conductor belongs to
%   wire_shapes  - Cell array of 'round' or 'rectangular' for each conductor

    % ========== VALIDATE INPUTS ==========
    required_fields = {'n_filar', 'n_turns', 'n_windings', 'width', 'height', ...
                       'gap_layer', 'currents', 'phases'};

    for i = 1:length(required_fields)
        if ~isfield(config, required_fields{i})
            error('Missing required field: %s', required_fields{i});
        end
    end

    % Set defaults
    if ~isfield(config, 'gap_filar')
        config.gap_filar = 0.05e-3;  % 50 um gap between parallel strands
    end

    if ~isfield(config, 'gap_winding')
        config.gap_winding = config.width + 1e-3;
    end

    if ~isfield(config, 'x_offset')
        config.x_offset = zeros(config.n_windings, 1);
    end

    % Validate n_filar
    if config.n_filar < 1 || config.n_filar > 4
        error('n_filar must be 1, 2, 3, or 4');
    end

    % Get wire shape information if available
    if isfield(config, 'wire_shape')
        wire_shape = config.wire_shape;
    else
        wire_shape = 'round';  % Default assumption
    end

    % ========== BUILD CONDUCTORS (VERTICAL STACKING) ==========
    conductors = [];
    winding_map = [];
    wire_shapes = {};

    for w = 1:config.n_windings

        % X position is constant for all conductors (vertical stacking)
        x_pos = config.x_offset(w);

        I_mag = config.currents(w);
        phase = config.phases(w);

        % Current is divided equally among all parallel strands
        I_per_strand = I_mag / config.n_filar;

        % Track vertical position
        y_current = 0;

        % For each turn
        for turn = 1:config.n_turns

            % Stack parallel strands vertically for this turn
            for strand = 1:config.n_filar

                % Y position for this strand
                y_pos = y_current + (strand - 1) * (config.height + config.gap_filar);

                % Add conductor (all at same X position!)
                conductors = [conductors; ...
                    x_pos, y_pos, config.width, config.height, I_per_strand, phase];

                winding_map = [winding_map; w];
                wire_shapes{end+1} = wire_shape;
            end

            % Move to next turn position
            % Height consumed = all parallel strands + gaps between them + gap to next turn
            turn_height = config.n_filar * config.height + ...
                         (config.n_filar - 1) * config.gap_filar + ...
                         config.gap_layer;
            y_current = y_current + turn_height;
        end
    end

    % ========== SUMMARY ==========
    fprintf('Multi-filar winding configuration:\n');
    fprintf('  Configuration: %d-filar (parallel strands STACK VERTICALLY)\n', config.n_filar);
    fprintf('  Number of windings: %d\n', config.n_windings);
    fprintf('  Turns per winding: %d\n', config.n_turns);
    fprintf('  Wire shape: %s\n', wire_shape);
    fprintf('  Layout: SINGLE COLUMN, vertical stacking\n');
    fprintf('  Total conductors: %d\n', size(conductors, 1));

    % Verify vertical stacking
    unique_x = unique(conductors(:,1));
    if length(unique_x) > config.n_windings
        warning('ERROR: Multiple X positions detected! Should be %d, got %d', ...
            config.n_windings, length(unique_x));
    end

    for w = 1:config.n_windings
        n_cond_in_winding = sum(winding_map == w);
        fprintf('  Winding %d: %d conductors, %.2f A total (%.2f A per strand)\n', ...
            w, n_cond_in_winding, config.currents(w), I_per_strand);

        % Show X positions for this winding
        winding_cond = conductors(winding_map == w, :);
        unique_x_winding = unique(winding_cond(:,1));
        fprintf('    X positions: ');
        for i = 1:length(unique_x_winding)
            fprintf('%.3f mm ', unique_x_winding(i)*1e3);
        end
        fprintf('(count: %d, should be 1)\n', length(unique_x_winding));
    end
end
