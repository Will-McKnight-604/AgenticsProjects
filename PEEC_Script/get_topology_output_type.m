function output_type = get_topology_output_type(topology_key)
% GET_TOPOLOGY_OUTPUT_TYPE Check if topology supports multi or single output
%
% Usage:
%   output_type = get_topology_output_type(topology_key)
%
% Inputs:
%   topology_key - string, topology identifier
%
% Outputs:
%   output_type - string, either 'multi' or 'single'
%       'multi' - supports multiple outputs (forward, flyback, push-pull, isolated topologies)
%       'single' - supports only single output (buck, boost)
%
% Example:
%   type = get_topology_output_type('buck');  % 'single'
%   type = get_topology_output_type('flyback');  % 'multi'

persistent cached_defs;

if isempty(cached_defs)
    cached_defs = topology_metadata();
end

TOPOLOGY_DEFS = cached_defs.TOPOLOGY_DEFINITIONS;

% Validate input
if ~ischar(topology_key) && ~isstring(topology_key)
    error('get_topology_output_type: topology_key must be a string or char array');
end

topology_key = char(topology_key);

% Check if topology exists
if ~isfield(TOPOLOGY_DEFS, topology_key)
    valid_topos = fieldnames(TOPOLOGY_DEFS);
    error('get_topology_output_type: Unknown topology "%s". Valid options: %s', ...
        topology_key, strjoin(valid_topos, ', '));
end

% Get topology definition and return output_type
topo = TOPOLOGY_DEFS.(topology_key);
output_type = topo.output_type;

end
