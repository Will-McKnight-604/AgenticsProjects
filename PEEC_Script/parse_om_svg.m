function parse_om_svg(svg_str, ax)
% PARSE_OM_SVG  Render PyOpenMagnetics SVG into MATLAB/Octave axes
%
% parse_om_svg(svg_string, axes_handle)
%
% Parses SVG output from PyOpenMagnetics plot_core/plot_bobbin/plot_magnetic
% and renders polygons (core, bobbin) and circles (wire turns) using native
% MATLAB graphics. Works in both MATLAB and GNU Octave.
%
% SVG elements handled:
%   <polygon class="..." points="x1,y1 x2,y2 ...">
%   <circle class="..." cx="..." cy="..." r="...">
%   <style> CSS block for class -> fill color mapping

    if isempty(svg_str)
        text(0.5, 0.5, 'No SVG data', 'Parent', ax, ...
            'HorizontalAlignment', 'center', 'Units', 'normalized');
        return;
    end

    hold(ax, 'on');

    % --- Parse CSS style block for class -> color mapping ---
    color_map = parse_css_colors(svg_str);

    % --- Parse viewBox for coordinate scaling ---
    vb = parse_viewbox(svg_str);

    % --- Draw polygons (core ferrite + bobbin) ---
    draw_polygons(svg_str, ax, color_map);

    % --- Draw circles (wire turns) - only copper class ---
    draw_circles(svg_str, ax, color_map);

    % --- Configure axes ---
    axis(ax, 'equal');
    set(ax, 'YDir', 'normal');  % SVG y increases downward, but we flip in parsing
    if ~isempty(vb)
        xlim(ax, [vb(1), vb(1) + vb(3)]);
        ylim(ax, [-(vb(2) + vb(4)), -vb(2)]);
    end
    set(ax, 'XTick', [], 'YTick', []);
    set(ax, 'Box', 'off', 'XColor', 'none', 'YColor', 'none');

    hold(ax, 'off');
end


function color_map = parse_css_colors(svg_str)
% Parse CSS <style> block to extract class name -> [R G B] color mapping
    color_map = struct();

    % Extract the CDATA content from <style>
    style_match = regexp(svg_str, '<style[^>]*>\s*<!\[CDATA\[(.*?)\]\]>\s*</style>', 'tokens');
    if isempty(style_match)
        % Try without CDATA wrapper
        style_match = regexp(svg_str, '<style[^>]*>(.*?)</style>', 'tokens');
    end
    if isempty(style_match)
        return;
    end

    css_text = style_match{1}{1};

    % Match CSS rules: .classname { fill: #rrggbb; ... }
    rules = regexp(css_text, '\.([A-Za-z_][A-Za-z0-9_]*)\s*\{([^}]*)\}', 'tokens');

    for i = 1:length(rules)
        class_name = rules{i}{1};
        rule_body = rules{i}{2};

        % Extract fill color
        fill_match = regexp(rule_body, 'fill:\s*#([0-9a-fA-F]{6})', 'tokens');
        if ~isempty(fill_match)
            hex = fill_match{1}{1};
            rgb = [hex2dec(hex(1:2)), hex2dec(hex(3:4)), hex2dec(hex(5:6))] / 255;

            % Check for opacity
            opacity_match = regexp(rule_body, 'opacity:\s*([0-9.]+)', 'tokens');
            alpha = 1.0;
            if ~isempty(opacity_match)
                alpha = str2double(opacity_match{1}{1});
            end

            % Check for stroke-only (fill: none)
            fill_none = regexp(rule_body, 'fill:\s*none', 'match');
            if ~isempty(fill_none)
                % Skip stroke-only classes
                continue;
            end

            safe_name = make_safe_field(class_name);
            color_map.(safe_name) = struct('rgb', rgb, 'alpha', alpha, 'name', class_name);
        end
    end
end


function vb = parse_viewbox(svg_str)
% Extract viewBox="x y w h" from SVG root element
    vb = [];
    vb_match = regexp(svg_str, 'viewBox="([^"]*)"', 'tokens');
    if ~isempty(vb_match)
        vb = sscanf(vb_match{1}{1}, '%f');
        if length(vb) ~= 4
            vb = [];
        end
    end
end


function draw_polygons(svg_str, ax, color_map)
% Parse and draw all <polygon> elements
    % Match: <polygon class="..." points="..." />
    poly_pattern = '<polygon\s+class="([^"]*)"\s+points="([^"]*)"';
    matches = regexp(svg_str, poly_pattern, 'tokens');

    for i = 1:length(matches)
        class_name = matches{i}{1};
        points_str = matches{i}{2};

        % Parse points: "x1,y1 x2,y2 x3,y3 ..."
        coords = sscanf(strrep(points_str, ',', ' '), '%f');
        if length(coords) < 6  % Need at least 3 points
            continue;
        end

        px = coords(1:2:end);
        py = -coords(2:2:end);  % Flip Y axis (SVG y-down -> MATLAB y-up)

        % Look up color
        rgb = get_class_color(class_name, color_map);

        % Draw filled polygon
        h = patch(ax, px, py, rgb, 'EdgeColor', 'none');

        % Apply alpha if available
        alpha = get_class_alpha(class_name, color_map);
        if alpha < 1.0
            try
                set(h, 'FaceAlpha', alpha);
            catch
                % Octave may not support FaceAlpha on patch
            end
        end
    end
end


function draw_circles(svg_str, ax, color_map)
% Parse and draw <circle> elements - only render copper and winding-color circles
    % Match: <circle class="..." cx="..." cy="..." r="...">
    circ_pattern = '<circle\s+class="([^"]*)"\s+cx="([^"]*)"\s+cy="([^"]*)"\s+r="([^"]*)"';
    matches = regexp(svg_str, circ_pattern, 'tokens');

    % Known classes to render (skip stroke-only overlay circles)
    render_classes = {'copper', 'ferrite', 'bobbin', 'insulation', 'fr4', 'spacer'};

    for i = 1:length(matches)
        class_name = matches{i}{1};
        cx = str2double(matches{i}{2});
        cy = -str2double(matches{i}{3});  % Flip Y
        r = str2double(matches{i}{4});

        if isnan(cx) || isnan(cy) || isnan(r) || r <= 0
            continue;
        end

        % Decide whether to render this circle
        safe_name = make_safe_field(class_name);
        is_known = any(strcmp(class_name, render_classes));
        has_fill = isfield(color_map, safe_name) && ...
                   isfield(color_map.(safe_name), 'rgb');

        % Render copper circles and any winding-color circles (non-stroke)
        if is_known || has_fill
            rgb = get_class_color(class_name, color_map);

            % Draw circle using polygon approximation
            theta = linspace(0, 2*pi, 32);
            px = cx + r * cos(theta);
            py = cy + r * sin(theta);
            h = fill(ax, px, py, rgb, 'EdgeColor', 'none');

            alpha = get_class_alpha(class_name, color_map);
            if alpha < 1.0
                try
                    set(h, 'FaceAlpha', alpha);
                catch
                end
            end
        end
    end
end


function rgb = get_class_color(class_name, color_map)
% Look up RGB color for a CSS class, with sensible defaults
    safe_name = make_safe_field(class_name);

    if isfield(color_map, safe_name) && isfield(color_map.(safe_name), 'rgb')
        rgb = color_map.(safe_name).rgb;
        return;
    end

    % Defaults for known classes
    switch class_name
        case 'ferrite'
            rgb = [0.482 0.486 0.490];  % #7b7c7d
        case 'bobbin'
            rgb = [0.325 0.592 0.588];  % #539796
        case 'copper'
            rgb = [0.722 0.451 0.200];  % #b87333
        case 'insulation'
            rgb = [1.000 0.941 0.357];  % #fff05b
        case 'spacer'
            rgb = [0.231 0.231 0.231];  % #3b3b3b
        otherwise
            rgb = [0.776 0.188 0.196];  % #c63032 (default winding color)
    end
end


function alpha = get_class_alpha(class_name, color_map)
% Look up alpha for a CSS class
    safe_name = make_safe_field(class_name);
    if isfield(color_map, safe_name) && isfield(color_map.(safe_name), 'alpha')
        alpha = color_map.(safe_name).alpha;
    else
        alpha = 1.0;
    end
end


function safe = make_safe_field(name)
% Convert CSS class name to valid MATLAB field name
    safe = regexprep(name, '[^a-zA-Z0-9_]', '_');
    if ~isempty(safe) && (safe(1) >= '0' && safe(1) <= '9')
        safe = ['c_' safe];
    end
    if isempty(safe)
        safe = 'unknown';
    end
end
