% om_wire_name.m
% Map internal wire names (AWG_22) to MAS wire names ('Round 0.64 - Grade 1')
% Used when communicating with PyOpenMagnetics / MKF winding engine
%
% Usage:
%   mas_name = om_wire_name('AWG_22');  % Returns 'Round 0.64 - Grade 1'
%   mas_name = om_wire_name('Litz_100_38');  % Returns 'Litz 100x38AWG'

function mas_name = om_wire_name(internal_name)

    % AWG round wire mapping: AWG gauge -> MAS bare diameter-based name
    % Format: 'Round <diameter_mm> - Grade 1'
    persistent wire_map;

    if isempty(wire_map)
        wire_map = struct();
        wire_map.AWG_10 = 'Round 2.59 - Grade 1';
        wire_map.AWG_12 = 'Round 2.05 - Grade 1';
        wire_map.AWG_14 = 'Round 1.63 - Grade 1';
        wire_map.AWG_16 = 'Round 1.29 - Grade 1';
        wire_map.AWG_18 = 'Round 1.02 - Grade 1';
        wire_map.AWG_20 = 'Round 0.81 - Grade 1';
        wire_map.AWG_22 = 'Round 0.64 - Grade 1';
        wire_map.AWG_24 = 'Round 0.51 - Grade 1';
        wire_map.AWG_26 = 'Round 0.40 - Grade 1';
        wire_map.AWG_28 = 'Round 0.32 - Grade 1';
        wire_map.AWG_30 = 'Round 0.25 - Grade 1';
        wire_map.AWG_32 = 'Round 0.20 - Grade 1';
        wire_map.AWG_34 = 'Round 0.16 - Grade 1';
        wire_map.AWG_36 = 'Round 0.127 - Grade 1';
        wire_map.AWG_38 = 'Round 0.101 - Grade 1';
        wire_map.AWG_40 = 'Round 0.079 - Grade 1';
    end

    if isfield(wire_map, internal_name)
        mas_name = wire_map.(internal_name);
    elseif strncmp(internal_name, 'Litz_', 5)
        % Convert Litz_100_38 -> 'Litz 100x38AWG' (approximate MAS name)
        parts = strsplit(internal_name, '_');
        if length(parts) >= 3
            mas_name = sprintf('Litz %sx%sAWG', parts{2}, parts{3});
        else
            mas_name = strrep(internal_name, '_', ' ');
        end
    elseif strncmp(internal_name, 'Foil_', 5)
        % Convert Foil_25mm_0p1 -> 'Foil 25mm 0.1mm' (approximate)
        name_clean = strrep(internal_name, 'Foil_', '');
        name_clean = strrep(name_clean, 'p', '.');
        name_clean = strrep(name_clean, '_', ' x ');
        mas_name = ['Foil ', name_clean];
    else
        % Try using the name directly (user might already be using MAS names)
        mas_name = strrep(internal_name, '_', ' ');
    end

end
