% om_client.m
% HTTP client for PyOpenMagnetics server (om_server.py)
% Connects to localhost:8484 and provides access to the full MKF database
% Designed for graceful fallback - all methods are try/catch safe
%
% Usage:
%   om = om_client();             % Attempts connection
%   if om.connected
%       wires = om.get_wires();   % Real MKF wire database
%       result = om.wind_simple(core, material, windings);
%   end

classdef om_client < handle

    properties
        base_url   = 'http://localhost:8484'  % PyOpenMagnetics server URL
        connected  = false                     % Connection status flag
        timeout    = 5                         % HTTP request timeout (seconds)
    end

    methods

        function obj = om_client(url)
            % Constructor: attempt connection to om_server.py
            %
            % Optional input:
            %   url - Server URL (default: 'http://localhost:8484')

            if nargin >= 1 && ~isempty(url)
                obj.base_url = url;
            end

            % Test connection with a health check
            try
                resp = obj.http_get('/health');
                if obj.is_status_ok(resp)
                    obj.connected = true;
                    fprintf('om_client: Connected to PyOpenMagnetics server at %s\n', obj.base_url);
                    if isfield(resp, 'version')
                        fprintf('  Server version: %s\n', resp.version);
                    end
                else
                    obj.connected = false;
                    fprintf('om_client: Server responded but health check failed\n');
                end
            catch e
                obj.connected = false;
                fprintf('om_client: Could not connect to %s (offline mode)\n', obj.base_url);
                fprintf('  Start the server with: python om_server.py\n');
            end
        end

        % ============================================================
        % DATABASE ACCESS METHODS
        % ============================================================

        function wires = get_wires(obj)
            % Get all wires from MKF database
            % Returns struct with wire names as fields
            resp = obj.http_get('/wires');

            % DEBUG: Log sample wire structure
            fprintf('\n[DEBUG get_wires] API Response Structure:\n');
            wire_names = fieldnames(resp);
            if ~isempty(wire_names)
                sample_name = wire_names{1};
                fprintf('  Sample wire: %s\n', sample_name);
                sample_wire = resp.(sample_name);
                if isstruct(sample_wire)
                    fprintf('  Fields: %s\n', strjoin(fieldnames(sample_wire), ', '));
                end
            end

            wires = resp;
        end

        function cores = get_core_shapes(obj)
            % Get all core shapes from MKF database
            % Returns struct with core names as fields
            resp = obj.http_get('/core_shapes');
            cores = resp;
        end

        function materials = get_materials(obj)
            % Get all materials from MKF database
            % Returns struct with material names as fields
            resp = obj.http_get('/materials');
            materials = resp;
        end

        function wire = find_wire(obj, name)
            % Find a specific wire by name
            % Input: name - e.g. 'Round 0.64 - Grade 1'
            encoded_name = obj.url_encode(name);
            resp = obj.http_get(sprintf('/wire/%s', encoded_name));

            % DEBUG: Log detailed wire structure
            fprintf('\n[DEBUG find_wire] Detailed wire data for: %s\n', name);
            if isstruct(resp)
                fprintf('  Fields: %s\n', strjoin(fieldnames(resp), ', '));
                % Log dimensional fields if present
                dim_fields = {'foil_width', 'foil_thickness', 'rect_width', 'rect_height', 'width', 'thickness', 'outer_diameter'};
                for i = 1:length(dim_fields)
                    if isfield(resp, dim_fields{i})
                        val = resp.(dim_fields{i});
                        fprintf('  %s = %s\n', dim_fields{i}, mat2str(val));
                    end
                end
            end

            wire = resp;
        end

        function core = find_core(obj, name)
            % Find a specific core by name
            % Input: name - e.g. 'ETD 29/16/10'
            encoded_name = obj.url_encode(name);
            resp = obj.http_get(sprintf('/core/%s', encoded_name));
            core = resp;
        end

        % ============================================================
        % WINDING ENGINE METHODS
        % ============================================================

        function result = wind_simple(obj, core_name, material_name, winding_defs)
            % Call MKF winding engine with simplified interface
            %
            % Inputs:
            %   core_name     - MAS core name, e.g. 'ETD 29/16/10'
            %   material_name - Material name, e.g. 'N87'
            %   winding_defs  - Struct array with fields:
            %                   .name     - Winding name (e.g. 'Primary')
            %                   .turns    - Number of turns
            %                   .wire     - MAS wire name (e.g. 'Round 0.64 - Grade 1')
            %                   .parallels - (optional) Number of parallel strands
            %
            % Output:
            %   result - MKF winding result with coil description

            % Build request body
            body = struct();
            body.core = core_name;
            body.material = material_name;

            % Convert winding_defs struct array to cell array for JSON
            windings_cell = {};
            for i = 1:length(winding_defs)
                w = struct();
                w.name = winding_defs(i).name;
                w.turns = winding_defs(i).turns;
                w.wire = winding_defs(i).wire;
                if isfield(winding_defs(i), 'parallels')
                    w.parallels = winding_defs(i).parallels;
                else
                    w.parallels = 1;
                end
                windings_cell{end+1} = w;
            end
            body.windings = windings_cell;

            result = obj.http_post('/wind', body);
        end

        % ============================================================
        % VISUALIZATION METHODS
        % ============================================================

        function svg = plot_turns(obj, wind_result)
            % Get SVG turn layout visualization from MKF
            % Input: wind_result - result from wind_simple()
            resp = obj.http_post('/plot/turns', wind_result);
            if isfield(resp, 'svg')
                svg = resp.svg;
            else
                svg = '';
            end
        end

        function svg = plot_sections(obj, wind_result)
            % Get SVG section layout visualization from MKF
            resp = obj.http_post('/plot/sections', wind_result);
            if isfield(resp, 'svg')
                svg = resp.svg;
            else
                svg = '';
            end
        end

        function svg = plot_core(obj, wind_result)
            % Get SVG core visualization from MKF
            resp = obj.http_post('/plot/core', wind_result);
            if isfield(resp, 'svg')
                svg = resp.svg;
            else
                svg = '';
            end
        end

        function show_svg(obj, svg_string, ax)
            % Render SVG string in an Octave axes
            % This is a best-effort renderer for basic SVG paths and shapes
            %
            % Inputs:
            %   svg_string - SVG markup string
            %   ax         - Axes handle to render into

            if isempty(svg_string)
                text(ax, 0.5, 0.5, 'No SVG data available', ...
                    'HorizontalAlignment', 'center', 'FontSize', 10);
                return;
            end

            % Save SVG to temp file and display as image if possible
            % For Octave, we do a simplified text-based display
            cla(ax);
            hold(ax, 'on');

            % Try to extract basic shapes from SVG for visualization
            % This is a simplified parser - complex SVGs need the full server
            obj.parse_svg_basic(svg_string, ax);

            hold(ax, 'off');
            axis(ax, 'equal');
            title(ax, 'OpenMagnetics Visualization');
        end

        % ============================================================
        % LOSS CALCULATION METHODS
        % ============================================================

        function losses = winding_losses(obj, wind_result, operating_point, model)
            % Calculate winding losses using MKF models
            %
            % Inputs:
            %   wind_result     - Result from wind_simple()
            %   operating_point - Struct with excitation conditions
            %   model          - Loss model: 'Dowell', 'Albach', 'Ferreira', etc.
            %
            % Output:
            %   losses - Struct with loss breakdown

            if nargin < 4
                model = 'Dowell';
            end

            body = struct();
            body.magnetic = wind_result;
            body.operatingPoint = operating_point;
            body.model = model;

            losses = obj.http_post('/winding_losses', body);
        end

    end % methods (public)

    methods (Access = private)

        % ============================================================
        % HTTP TRANSPORT
        % ============================================================

        function resp = http_get(obj, endpoint)
            % Perform HTTP GET request
            % Returns parsed JSON response as struct

            url = [obj.base_url, endpoint];

            % Use Octave's urlread or webread
            try
                if exist('webread', 'file')
                    options = weboptions('Timeout', obj.timeout, ...
                        'ContentType', 'json');
                    resp = webread(url, options);
                    if ischar(resp) || isstring(resp)
                        resp = obj.parse_json(resp);
                    end
                else
                    % Fallback for older Octave: use urlread + jsonparse
                    [json_str, success] = urlread(url, 'Timeout', obj.timeout);
                    if success
                        resp = obj.parse_json(json_str);
                    else
                        error('HTTP GET failed for %s', url);
                    end
                end
            catch e
                % Try curl as ultimate fallback
                try
                    [status, output] = system(sprintf( ...
                        'curl -s --connect-timeout %d "%s"', obj.timeout, url));
                    if status == 0 && ~isempty(output)
                        resp = obj.parse_json(output);
                    else
                        error('curl failed for %s', url);
                    end
                catch
                    rethrow(e);
                end
            end
        end

        function resp = http_post(obj, endpoint, body)
            % Perform HTTP POST request with JSON body
            % Returns parsed JSON response as struct

            url = [obj.base_url, endpoint];

            % Convert body to JSON
            json_body = obj.to_json(body);

            try
                if exist('webwrite', 'file')
                    options = weboptions('Timeout', obj.timeout, ...
                        'ContentType', 'json', ...
                        'MediaType', 'application/json');
                    resp = webwrite(url, body, options);
                    if ischar(resp) || isstring(resp)
                        resp = obj.parse_json(resp);
                    end
                else
                    % Fallback: use curl for POST
                    % Escape JSON for shell
                    json_escaped = strrep(json_body, '''', '\''');
                    cmd = sprintf('curl -s --connect-timeout %d -X POST -H "Content-Type: application/json" -d ''%s'' "%s"', ...
                        obj.timeout, json_escaped, url);
                    [status, output] = system(cmd);
                    if status == 0 && ~isempty(output)
                        resp = obj.parse_json(output);
                    else
                        error('curl POST failed for %s', url);
                    end
                end
            catch e
                rethrow(e);
            end
        end

        function result = parse_json(obj, json_str)
            % Parse JSON string to Octave struct
            % Uses jsondecode if available, otherwise basic parser

            if isstruct(json_str)
                result = json_str;
                return;
            end
            if isstring(json_str)
                json_str = char(json_str);
            elseif isnumeric(json_str)
                json_str = char(json_str(:).');
            end
            if exist('jsondecode', 'builtin') || exist('jsondecode', 'file')
                result = jsondecode(json_str);
            elseif exist('loadjson', 'file')
                result = loadjson(json_str);
            else
                % Fallback: return raw string to avoid unsafe eval
                result = struct('raw', json_str);
            end
        end

        function ok = is_status_ok(obj, resp)
            % Robust status check for health endpoint
            ok = false;
            if isempty(resp) || ~isstruct(resp) || ~isfield(resp, 'status')
                return;
            end
            status = resp.status;
            if iscell(status) && ~isempty(status)
                status = status{1};
            end
            if isstring(status)
                status = char(status);
            end
            if ischar(status)
                ok = strcmpi(strtrim(status), 'ok');
            elseif isnumeric(status)
                ok = (status == 1);
            end
        end

        function json = to_json(obj, data)
            % Convert Octave struct to JSON string
            % Uses jsonencode if available, otherwise basic converter

            if exist('jsonencode', 'file')
                json = jsonencode(data);
            else
                json = obj.struct_to_json(data);
            end
        end

        function json = struct_to_json(obj, data)
            % Basic struct-to-JSON converter for older Octave
            if isstruct(data)
                fields = fieldnames(data);
                parts = {};
                for i = 1:length(fields)
                    key = fields{i};
                    val = data.(key);
                    parts{end+1} = sprintf('"%s":%s', key, obj.struct_to_json(val));
                end
                json = ['{', strjoin(parts, ','), '}'];
            elseif iscell(data)
                parts = {};
                for i = 1:length(data)
                    parts{end+1} = obj.struct_to_json(data{i});
                end
                json = ['[', strjoin(parts, ','), ']'];
            elseif ischar(data)
                json = sprintf('"%s"', strrep(data, '"', '\"'));
            elseif isnumeric(data)
                if isscalar(data)
                    if data == round(data)
                        json = sprintf('%d', data);
                    else
                        json = sprintf('%.6g', data);
                    end
                else
                    parts = {};
                    for i = 1:numel(data)
                        parts{end+1} = sprintf('%.6g', data(i));
                    end
                    json = ['[', strjoin(parts, ','), ']'];
                end
            elseif islogical(data)
                if data
                    json = 'true';
                else
                    json = 'false';
                end
            else
                json = 'null';
            end
        end

        function encoded = url_encode(obj, str)
            % Simple URL encoding for wire names
            % Replaces spaces and special characters with percent-encoded values
            encoded = str;
            encoded = strrep(encoded, ' ', '%20');
            encoded = strrep(encoded, '/', '%2F');
            encoded = strrep(encoded, '?', '%3F');
            encoded = strrep(encoded, '#', '%23');
            encoded = strrep(encoded, '&', '%26');
            encoded = strrep(encoded, '=', '%3D');
            encoded = strrep(encoded, '+', '%2B');
            encoded = strrep(encoded, ':', '%3A');
            encoded = strrep(encoded, ';', '%3B');
            encoded = strrep(encoded, ',', '%2C');
        end

        function parse_svg_basic(obj, svg_str, ax)
            % Basic SVG parser for Octave - renders circles and rectangles
            % This provides a simplified view; full rendering requires the server

            % Extract viewBox for coordinate mapping
            vb_match = regexp(svg_str, 'viewBox="([^"]*)"', 'tokens');
            if ~isempty(vb_match)
                vb = sscanf(vb_match{1}{1}, '%f %f %f %f');
                if length(vb) == 4
                    xlim(ax, [vb(1), vb(1) + vb(3)]);
                    ylim(ax, [vb(2), vb(2) + vb(4)]);
                end
            end

            % Extract and draw circles (wire cross-sections)
            circle_pattern = '<circle[^>]*cx="([^"]*)"[^>]*cy="([^"]*)"[^>]*r="([^"]*)"[^>]*/>';
            circles = regexp(svg_str, circle_pattern, 'tokens');

            for i = 1:length(circles)
                cx = str2double(circles{i}{1});
                cy = str2double(circles{i}{2});
                r = str2double(circles{i}{3});

                if ~isnan(cx) && ~isnan(cy) && ~isnan(r)
                    theta = linspace(0, 2*pi, 30);
                    fill(ax, cx + r*cos(theta), cy + r*sin(theta), ...
                        [0.6 0.8 1.0], 'EdgeColor', [0.2 0.4 0.8], 'LineWidth', 0.5);
                end
            end

            % Extract and draw rectangles (bobbin window, sections)
            rect_pattern = '<rect[^>]*x="([^"]*)"[^>]*y="([^"]*)"[^>]*width="([^"]*)"[^>]*height="([^"]*)"[^>]*/>';
            rects = regexp(svg_str, rect_pattern, 'tokens');

            for i = 1:length(rects)
                rx = str2double(rects{i}{1});
                ry = str2double(rects{i}{2});
                rw = str2double(rects{i}{3});
                rh = str2double(rects{i}{4});

                if ~isnan(rx) && ~isnan(ry) && ~isnan(rw) && ~isnan(rh)
                    rectangle('Parent', ax, 'Position', [rx, ry, rw, rh], ...
                        'EdgeColor', 'k', 'LineWidth', 1);
                end
            end

            % If no shapes found, show a message
            if isempty(circles) && isempty(rects)
                text(ax, 0.5, 0.5, ...
                    sprintf('SVG contains %d bytes\n(Complex SVG - save to file to view)', ...
                    length(svg_str)), ...
                    'Units', 'normalized', ...
                    'HorizontalAlignment', 'center', 'FontSize', 9);
            end
        end

    end % methods (private)

end
