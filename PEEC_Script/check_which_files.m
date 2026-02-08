% check_which_files.m
% Check which version of files MATLAB is using

fprintf('=== CHECKING FILE VERSIONS ===\n\n');

files_to_check = {
    'peec_build_geometry'
    'peec_solve_frequency'
    'plot_current_density'
    'plot_loss_density'
    'identify_hotspots'
    'build_layered_geometry'
};

for i = 1:length(files_to_check)
    fname = files_to_check{i};

    fprintf('%s:\n', fname);

    fpath = which(fname);
    if isempty(fpath)
        fprintf('  ✗ NOT FOUND in path\n');
    else
        fprintf('  ✓ %s\n', fpath);

        % Try to read first few lines
        try
            fid = fopen(fpath, 'r');
            if fid > 0
                fprintf('    First line: ');
                first_line = fgetl(fid);
                fprintf('%s\n', first_line);

                % Check function signature
                second_line = fgetl(fid);
                if contains(second_line, 'function')
                    fprintf('    Signature: %s\n', strtrim(second_line));
                end

                fclose(fid);
            end
        catch
            % Ignore read errors
        end
    end
    fprintf('\n');
end

fprintf('=== PATH INFORMATION ===\n');
fprintf('Current directory: %s\n', pwd);
fprintf('\nMATLAB path (first 3 entries):\n');
p = strsplit(path, pathsep);
for i = 1:min(3, length(p))
    fprintf('  %d. %s\n', i, p{i});
end
