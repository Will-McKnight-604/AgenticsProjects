function topo_meta = get_topology_metadata(topology_key)
% GET_TOPOLOGY_METADATA Returns complete metadata for a specific topology
%
% Usage:
%   topo_meta = get_topology_metadata(topology_key)
%
% Inputs:
%   topology_key - string, one of:
%       'two_switch_forward', 'single_switch_forward', 'active_clamp_forward',
%       'flyback', 'push_pull', 'buck', 'boost', 'isolated_buck', 'isolated_buck_boost'
%
% Outputs:
%   topo_meta - struct with fields:
%       - display_name: Human-readable name
%       - mas_filename: MAS JSON template filename
%       - output_type: 'multi' or 'single'
%       - required_fields: cell array of required field names
%       - optional_fields: cell array of optional field names
%
% Example:
%   topo = get_topology_metadata('two_switch_forward');
%   disp(topo.display_name);  % 'Two-Switch Forward'
%   disp(topo.required_fields);

persistent cached_defs;

if isempty(cached_defs)
    cached_defs = topology_metadata();
end

TOPOLOGY_DEFS = cached_defs.TOPOLOGY_DEFINITIONS;

% Validate input
if ~ischar(topology_key) && ~isstring(topology_key)
    error('get_topology_metadata: topology_key must be a string or char array');
end

topology_key = char(topology_key);

% Check if topology exists
if ~isfield(TOPOLOGY_DEFS, topology_key)
    valid_topos = fieldnames(TOPOLOGY_DEFS);
    error('get_topology_metadata: Unknown topology "%s". Valid options: %s', ...
        topology_key, strjoin(valid_topos, ', '));
end

% Return the topology metadata
topo_meta = TOPOLOGY_DEFS.(topology_key);

end
