%identify_hotspots
%{
function hotspots = identify_hotspots(geom, results, topN)

    if nargin < 3
        topN = 5;
    end

    [~, idx] = sort(results.P_fil,'descend');

    hotspots = struct([]);
    for k = 1:topN
        i = idx(k);
        hotspots(k).x = geom.filaments(i,1);
        hotspots(k).y = geom.filaments(i,2);
        hotspots(k).loss = results.P_fil(i);
        hotspots(k).conductor = geom.filaments(i,4);
    end
end

% identify_hotspots.m - Fixed for correct filament array format
function hotspots = identify_hotspots(geom, results, topN)

    if nargin < 3
        topN = 5;
    end

    [~, idx] = sort(results.P_fil,'descend');

    hotspots = struct([]);

    % fil columns: [x, y, dx, dy, conductor_idx, I_complex]
    for k = 1:min(topN, length(idx))
        i = idx(k);
        hotspots(k).x = geom.filaments(i,1);
        hotspots(k).y = geom.filaments(i,2);
        hotspots(k).loss = results.P_fil(i);
        hotspots(k).conductor = geom.filaments(i,5);  % Conductor index
    end
end

%}
% identify_hotspots.m - Fixed for correct filament array format
function hotspots = identify_hotspots(geom, results, topN)

    if nargin < 3
        topN = 5;
    end

    [~, idx] = sort(results.P_fil,'descend');

    hotspots = struct([]);

    % fil columns: [x, y, dx, dy, conductor_idx, winding_idx, I_complex]
    for k = 1:min(topN, length(idx))
        i = idx(k);
        hotspots(k).x = geom.filaments(i,1);
        hotspots(k).y = geom.filaments(i,2);
        hotspots(k).loss = results.P_fil(i);
        hotspots(k).conductor = geom.filaments(i,5);  % Conductor index

        % Add winding info if available
        if size(geom.filaments, 2) >= 6
            hotspots(k).winding = geom.filaments(i,6);  % Winding index
        end
    end
end
