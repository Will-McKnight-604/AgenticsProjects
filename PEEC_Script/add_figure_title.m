% compatibility_utils.m
% Compatibility functions for older MATLAB/Octave versions

function add_figure_title(fig_handle, title_text)
    % Alternative to sgtitle that works in older versions
    % Usage: add_figure_title(gcf, 'My Figure Title')

    if nargin < 2
        error('Usage: add_figure_title(fig_handle, title_text)');
    end

    % Use annotation to add title at top of figure
    annotation(fig_handle, 'textbox', [0 0.96 1 0.04], ...
               'String', title_text, ...
               'EdgeColor', 'none', ...
               'HorizontalAlignment', 'center', ...
               'FontSize', 14, ...
               'FontWeight', 'bold', ...
               'Interpreter', 'none');
end


function add_figure_subtitle(fig_handle, subtitle_text)
    % Add a subtitle below the main title
    % Usage: add_figure_subtitle(gcf, 'Subtitle text')

    if nargin < 2
        error('Usage: add_figure_subtitle(fig_handle, subtitle_text)');
    end

    annotation(fig_handle, 'textbox', [0 0.92 1 0.04], ...
               'String', subtitle_text, ...
               'EdgeColor', 'none', ...
               'HorizontalAlignment', 'center', ...
               'FontSize', 11, ...
               'FontStyle', 'italic', ...
               'Interpreter', 'none');
end


function compatible_colormap(cmap_name, n_colors)
    % Ensures colormap compatibility
    % Usage: compatible_colormap('jet', 256)

    if nargin < 2
        n_colors = 256;
    end

    % Try to use built-in colormap
    try
        if nargin < 2
            colormap(cmap_name);
        else
            colormap(feval(cmap_name, n_colors));
        end
    catch
        % Fallback to basic colormaps
        warning('Colormap %s not available, using jet instead', cmap_name);
        colormap(jet(n_colors));
    end
end


function save_figure_compatible(fig_handle, filename, format)
    % Save figure in a compatible way
    % Usage: save_figure_compatible(gcf, 'myplot', 'png')

    if nargin < 3
        format = 'png';
    end

    if nargin < 2
        error('Usage: save_figure_compatible(fig_handle, filename, [format])');
    end

    % Add extension if not present
    [~, ~, ext] = fileparts(filename);
    if isempty(ext)
        filename = [filename '.' format];
    end

    % Try modern saveas, fall back to print
    try
        saveas(fig_handle, filename);
    catch
        print(fig_handle, filename, ['-d' format]);
    end

    fprintf('Figure saved to: %s\n', filename);
end


function results = check_matlab_version()
    % Check MATLAB/Octave version and available features
    % Usage: results = check_matlab_version()

    results = struct();

    % Detect environment
    results.is_octave = exist('OCTAVE_VERSION', 'builtin') ~= 0;

    if results.is_octave
        results.version_string = version;
        results.environment = 'Octave';
    else
        v = ver('MATLAB');
        if ~isempty(v)
            results.version_string = v.Version;
            results.environment = 'MATLAB';
        else
            results.version_string = 'Unknown';
            results.environment = 'Unknown';
        end
    end

    % Check for specific functions
    results.has_sgtitle = exist('sgtitle', 'builtin') || exist('sgtitle', 'file');
    results.has_tiledlayout = exist('tiledlayout', 'builtin') || exist('tiledlayout', 'file');
    results.has_stackedplot = exist('stackedplot', 'builtin') || exist('stackedplot', 'file');

    % Display summary
    fprintf('=== Environment Information ===\n');
    fprintf('Platform: %s\n', results.environment);
    fprintf('Version: %s\n', results.version_string);
    fprintf('sgtitle available: %s\n', bool2str(results.has_sgtitle));
    fprintf('tiledlayout available: %s\n', bool2str(results.has_tiledlayout));
    fprintf('stackedplot available: %s\n', bool2str(results.has_stackedplot));
    fprintf('==============================\n\n');

    function s = bool2str(b)
        if b
            s = 'Yes';
        else
            s = 'No';
        end
    end
end
