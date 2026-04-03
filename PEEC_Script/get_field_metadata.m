function field_meta = get_field_metadata(field_name)
% GET_FIELD_METADATA Returns metadata for a specific field
%
% Usage:
%   field_meta = get_field_metadata(field_name)
%
% Inputs:
%   field_name - string, e.g. 'diodeVoltageDrop', 'currentRippleRatio'
%
% Outputs:
%   field_meta - struct with fields:
%       - label: Display label for GUI
%       - unit: Unit string (V, A, %, Hz, etc.)
%       - data_type: 'number', 'categorical', etc.
%       - default: Default value
%       - min/max: Valid range
%       - tooltip: Help text
%       - mas_path: JSON path in MAS structure
%       - optional: boolean
%
% Example:
%   meta = get_field_metadata('diodeVoltageDrop');
%   disp(meta.label);  % 'Diode Voltage Drop'
%   disp(meta.default);  % 0.7

persistent cached_defs;

if isempty(cached_defs)
    cached_defs = topology_metadata();
end

FIELD_DEFS = cached_defs.FIELD_METADATA;

% Validate input
if ~ischar(field_name) && ~isstring(field_name)
    error('get_field_metadata: field_name must be a string or char array');
end

field_name = char(field_name);

% Check if field exists
if ~isfield(FIELD_DEFS, field_name)
    valid_fields = fieldnames(FIELD_DEFS);
    error('get_field_metadata: Unknown field "%s". Valid options: %s', ...
        field_name, strjoin(valid_fields, ', '));
end

% Return the field metadata
field_meta = FIELD_DEFS.(field_name);

end
