%build_layered_geometry

function conductors = build_layered_geometry(N_layers, width, height, gap)

    conductors = zeros(N_layers,6);

    for k = 1:N_layers
        y = (k-1)*(height+gap);
        conductors(k,:) = [0, y, width, height, 1, 0];
    end
end

