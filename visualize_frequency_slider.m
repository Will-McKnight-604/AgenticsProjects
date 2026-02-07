%visualize_frequency_slider
%{
%function visualize_frequency_slider(conductors, geom, f_vec, sigma, mu0)
 function visualize_frequency_slider(conductors_A, geom_A, f_sweep, sigma, mu0);

    fig = figure('Name','Frequency Slider','Position',[100 100 900 450]);

    % Slider
    uicontrol('Style','slider',...
        'Min',1,'Max',length(f_sweep),'Value',1,...
        'SliderStep',[1/(length(f_sweep)-1) 0.2],...
        'Position',[200 20 500 20],...
        'Callback',@update_plot);

    freq_text = uicontrol('Style','text',...
        'Position',[380 50 200 20],...
        'String','');

    ax1 = subplot(1,2,1);
    ax2 = subplot(1,2,2);

 %   update_plot();

 %   function update_plot(~,~)
        idx = round(get(gcbo,'Value'));
        f = f_sweep(idx);

        results = peec_solve_frequency(geom_A, conductors_A, f, sigma, mu0);


        % ======= RUNTIME VALIDATION =======
        if isempty(results.I_fil)
            error('Slider callback: solver returned empty current vector');
        end

        axes(ax1); cla;
        plot_current_density(geom_A, results);
        title(sprintf('Current Density @ %.0f kHz',f/1e3));

        axes(ax2); cla;
        plot_loss_density(geom_A, results);
        title('Loss Density');

        set(freq_text,'String',sprintf('f = %.0f kHz',f/1e3));
 %   end

end
%}

%{
function visualize_frequency_slider(conductors_A, geom_A, f_sweep, sigma, mu0)

    fig = figure('Name','Frequency Slider');

    slider = uicontrol('Style','slider', ...
        'Min',1,'Max',length(f_sweep),'Value',1, ...
        'SliderStep',[1/(length(f_sweep)-1) 0.2], ...
        'Units','normalized', ...
        'Position',[0.1 0.05 0.8 0.05]);

    ax1 = subplot(1,2,1);
    ax2 = subplot(1,2,2);

    % Initial draw (Octave-safe)
    update_plot(slider, []);

    function update_plot(src, ~)

    idx = round(get(src,'Value'));
    f   = f_sweep(idx);

    disp(['Updating plot at f = ', num2str(f), ' Hz']);

    results = peec_solve_frequency(geom_A, conductors_A, f, sigma, mu0);

    axes(ax1); cla;
    plot_current_density(geom_A, results);
    axis equal;
    axis tight;
    title(sprintf('Current Density @ %.1f kHz', f/1e3));

    axes(ax2); cla;
    plot_loss_density(geom_A, results);
    axis equal;
    axis tight;
    title('Loss Density');

    drawnow;   % <<< REQUIRED IN OCTAVE
end


    set(slider,'Callback',@update_plot);
end
%}

%visualize_frequency_slider

function visualize_frequency_slider(conductors_A, geom_A, f_sweep, sigma, mu0)

    fig = figure('Name','Frequency Slider', 'Position', [100 100 1000 500]);

    % Create slider
    slider = uicontrol('Style','slider', ...
        'Min',1,'Max',length(f_sweep),'Value',1, ...
        'SliderStep',[1/(length(f_sweep)-1) 0.2], ...
        'Units','normalized', ...
        'Position',[0.2 0.02 0.6 0.04]);

    % Frequency display text
    freq_text = uicontrol('Style','text', ...
        'Units','normalized', ...
        'Position',[0.42 0.07 0.16 0.04], ...
        'String','', ...
        'FontSize', 10, ...
        'BackgroundColor', get(fig, 'Color'));

    % Create subplots
    ax1 = subplot(1,2,1);
    ax2 = subplot(1,2,2);

    % Pre-allocate graphics handles for faster updates
    h_curr = [];
    h_loss = [];

    % Initial plot
    update_plot(slider, []);

    % Set callback AFTER initial plot
    set(slider,'Callback',@update_plot);

    function update_plot(src, ~)
        idx = round(get(src,'Value'));
        f   = f_sweep(idx);

        % Solve for current frequency
        results = peec_solve_frequency(geom_A, conductors_A, f, sigma, mu0);

        % Update current density plot
        axes(ax1);
        if isempty(h_curr)
            h_curr = plot_current_density_fast(geom_A, results);
        else
            update_density_plot(geom_A, results, h_curr, 'current');
        end
        title(sprintf('Current Density @ %.1f kHz', f/1e3));

        % Update loss density plot
        axes(ax2);
        if isempty(h_loss)
            h_loss = plot_loss_density_fast(geom_A, results);
        else
            update_density_plot(geom_A, results, h_loss, 'loss');
        end
        title(sprintf('Loss Density (Total: %.2f W)', results.P_total));

        % Update frequency text
        set(freq_text, 'String', sprintf('Frequency: %.1f kHz', f/1e3));

        drawnow;
    end

end

% Fast plotting using patch instead of individual rectangles
function h = plot_current_density_fast(geom, results)
    fil = geom.filaments;
    I   = results.I_fil;

    cla; hold on;
    axis equal;
    box on;
    xlabel('x (m)');
    ylabel('y (m)');

    Jmag = abs(I) ./ (fil(:,3).*fil(:,4));

    % Create patch vertices and faces for all rectangles at once
    [vertices, faces, colors] = create_patch_data(fil, Jmag);

    h = patch('Vertices', vertices, 'Faces', faces, ...
              'FaceVertexCData', colors, ...
              'FaceColor', 'flat', ...
              'EdgeColor', 'none');

    colormap(jet);
    colorbar;
end

function h = plot_loss_density_fast(geom, results)
    fil = geom.filaments;
    P   = results.P_fil;

    cla; hold on;
    axis equal;
    box on;
    xlabel('x (m)');
    ylabel('y (m)');

    pdens = P ./ (fil(:,3) .* fil(:,4));

    % Create patch vertices and faces for all rectangles at once
    [vertices, faces, colors] = create_patch_data(fil, pdens);

    h = patch('Vertices', vertices, 'Faces', faces, ...
              'FaceVertexCData', colors, ...
              'FaceColor', 'flat', ...
              'EdgeColor', 'none');

    colormap(hot);
    colorbar;

    % Add hotspots
    hs = identify_hotspots(geom, results, 5);
    for k = 1:length(hs)
        plot(hs(k).x, hs(k).y, 'rx', ...
            'MarkerSize', 12, 'LineWidth', 2);
    end
end

function update_density_plot(geom, results, h, type)
    fil = geom.filaments;

    if strcmp(type, 'current')
        I = results.I_fil;
        density = abs(I) ./ (fil(:,3).*fil(:,4));
    else
        P = results.P_fil;
        density = P ./ (fil(:,3) .* fil(:,4));
    end

    % Normalize colors
    density_norm = density / max(density);

    % Update only the color data (much faster than redrawing)
    set(h, 'FaceVertexCData', density_norm);
end

function [vertices, faces, colors] = create_patch_data(fil, density)
    Nf = size(fil, 1);

    % Pre-allocate arrays
    vertices = zeros(4*Nf, 2);
    faces = zeros(Nf, 4);

    % Normalize density for colormap
    density_norm = density / max(density);
    colors = density_norm;

    % Build vertices and faces
    for i = 1:Nf
        x_center = fil(i,1);
        y_center = fil(i,2);
        dx = fil(i,3);
        dy = fil(i,4);

        % Four corners of rectangle
        v_idx = (i-1)*4 + 1;
        vertices(v_idx:v_idx+3, :) = [
            x_center - dx/2, y_center - dy/2;
            x_center + dx/2, y_center - dy/2;
            x_center + dx/2, y_center + dy/2;
            x_center - dx/2, y_center + dy/2
        ];

        % Face connectivity
        faces(i, :) = v_idx:v_idx+3;
    end
end
