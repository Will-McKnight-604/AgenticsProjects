function [required_fields, optional_fields] = get_visible_fields_for_topology(topology_key)
% GET_VISIBLE_FIELDS_FOR_TOPOLOGY Get all fields for a topology (required + optional)
%
% Usage:
%   [required_fields, optional_fields] = get_visible_fields_for_topology(topology_key)
%
% Inputs:
%   topology_key - string, topology identifier
%
% Outputs:
%   required_fields - cell array of required field names
%   optional_fields - cell array of optional field names
%
% Example:
%   [req, opt] = get_visible_fields_for_topology('two_switch_forward');
%   disp(req);  % {'inputVoltage_minimum', 'inputVoltage_maximum', ...}
%   disp(opt);  % {'inputVoltage_nominal', 'efficiency', ...}

persistent cached_defs;

if isempty(cached_defs)
    cached_defs = topology_metadata();
end

TOPOLOGY_DEFS = cached_defs.TOPOLOGY_DEFINITIONS;

% Validate input
if ~ischar(topology_key) && ~isstring(topology_key)
    error('get_visible_fields_for_topology: topology_key must be a string or char array');
end

topology_key = char(topology_key);

% Check if topology exists
if ~isfield(TOPOLOGY_DEFS, topology_key)
    valid_topos = fieldnames(TOPOLOGY_DEFS);
    error('get_visible_fields_for_topology: Unknown topology "%s". Valid options: %s', ...
        topology_key, strjoin(valid_topos, ', '));
end

% Get topology definition
topo = TOPOLOGY_DEFS.(topology_key);

% Return both required and optional fields
required_fields = topo.required_fields;
optional_fields = topo.optional_fields;

end
