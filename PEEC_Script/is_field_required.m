function required = is_field_required(topology_key, field_name)
% IS_FIELD_REQUIRED Check if a field is required for a given topology
%
% Usage:
%   required = is_field_required(topology_key, field_name)
%
% Inputs:
%   topology_key - string, topology identifier
%   field_name - string, field identifier
%
% Outputs:
%   required - boolean, true if field is required, false if optional
%
% Example:
%   required = is_field_required('flyback', 'efficiency');  % true
%   required = is_field_required('buck', 'efficiency');  % false

persistent cached_defs;

if isempty(cached_defs)
    cached_defs = topology_metadata();
end

TOPOLOGY_DEFS = cached_defs.TOPOLOGY_DEFINITIONS;

% Validate inputs
if ~ischar(topology_key) && ~isstring(topology_key)
    error('is_field_required: topology_key must be a string or char array');
end
if ~ischar(field_name) && ~isstring(field_name)
    error('is_field_required: field_name must be a string or char array');
end

topology_key = char(topology_key);
field_name = char(field_name);

% Check if topology exists
if ~isfield(TOPOLOGY_DEFS, topology_key)
    valid_topos = fieldnames(TOPOLOGY_DEFS);
    error('is_field_required: Unknown topology "%s". Valid options: %s', ...
        topology_key, strjoin(valid_topos, ', '));
end

% Get topology definition
topo = TOPOLOGY_DEFS.(topology_key);

% Check if field is in required list
required = any(strcmp(topo.required_fields, field_name));

end
