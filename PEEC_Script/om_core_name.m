% om_core_name.m
% Convert internal core names to MAS (Magnetic Component Analysis Standard) names
% Used when communicating with PyOpenMagnetics / MKF winding engine
%
% Usage:
%   mas_name = om_core_name('ETD_29_16_10');  % Returns 'ETD 29/16/10'
%   mas_name = om_core_name('E_65_32_27');    % Returns 'E 65/32/27'
%   mas_name = om_core_name('PQ_26_25');      % Returns 'PQ 26/25'
%   mas_name = om_core_name('RM_10');         % Returns 'RM 10'

function mas_name = om_core_name(internal_name)

    parts = strsplit(internal_name, '_');

    if length(parts) >= 4
        % ETD_29_16_10 -> 'ETD 29/16/10'
        mas_name = sprintf('%s %s/%s/%s', parts{1}, parts{2}, parts{3}, parts{4});
    elseif length(parts) == 3
        % PQ_26_25 -> 'PQ 26/25'
        mas_name = sprintf('%s %s/%s', parts{1}, parts{2}, parts{3});
    elseif length(parts) == 2
        % RM_10 -> 'RM 10'
        mas_name = sprintf('%s %s', parts{1}, parts{2});
    else
        % Fallback: just replace underscores with spaces
        mas_name = strrep(internal_name, '_', ' ');
    end

end
