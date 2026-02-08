%peec_build_geometry
%{
function geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny)

% ======= SAFETY CHECKS =======
if isempty(conductors)
    error('peec_build_geometry: conductors array is empty');
end

if Nx <= 0 || Ny <= 0 || round(Nx) ~= Nx || round(Ny) ~= Ny
    error('peec_build_geometry: Nx and Ny must be positive integers');
end




    % ---- Filament generation ----
    filaments = [];

    for k = 1:size(conductors,1)

        xc = conductors(k,1);
        yc = conductors(k,2);
        w0 = conductors(k,3);
        h0 = conductors(k,4);
        I  = conductors(k,5);
        ph = conductors(k,6)*pi/180;

        dx = w0/Nx;
        dy = h0/Ny;

        for ix = 1:Nx
            for iy = 1:Ny
                xf = xc - w0/2 + dx*(ix-0.5);
                yf = yc - h0/2 + dy*(iy-0.5);
                filaments = [filaments;
                    xf, yf, dx, dy, I*exp(1j*ph)];
            end
        end
    end

    Nf = size(filaments,1);
    Nc = size(conductors,1);

    % ---- Resistance matrix ----
    R = zeros(Nf);
    for i = 1:Nf
        A = filaments(i,3)*filaments(i,4);
        R(i,i) = 1/(sigma*A);
    end

    % ---- Inductance matrix ----
    L = zeros(Nf);

    for i = 1:Nf
        xi = filaments(i,1);
        yi = filaments(i,2);
        ai = sqrt(filaments(i,3)*filaments(i,4))/2;

        for j = 1:Nf
            xj = filaments(j,1);
            yj = filaments(j,2);
            aj = sqrt(filaments(j,3)*filaments(j,4))/2;

            if i == j
                r = ai;
            else
                r = sqrt((xi-xj)^2 + (yi-yj)^2);
            end

            L(i,j) = mu0/(2*pi)*log(1/r);
        end
    end

    % ---- Constraint matrix ----
    C = zeros(Nc, Nf);
    idx = 0;
    for k = 1:Nc
        for n = 1:(Nx*Ny)
            idx = idx + 1;
            C(k,idx) = 1;
        end
    end

    % ---- Store geometry ----
    geom.R = R;
    geom.L = L;
    geom.C = C;
    geom.Nf = Nf;
    geom.Nc = Nc;

    % ======= FINAL GEOMETRY CHECK =======
    if isempty(filaments)
        error('peec_build_geometry: filament list is empty (check Nx, Ny, geometry)');
    end


    % ---- Filament geometry for plotting ----
    geom.filaments = filaments;   % [x y dx dy I_complex]
    geom.Nf = size(filaments,1);
end

%}

%peec_build_geometry
%{
function geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny)

% ======= SAFETY CHECKS =======
if isempty(conductors)
    error('peec_build_geometry: conductors array is empty');
end

if Nx <= 0 || Ny <= 0 || round(Nx) ~= Nx || round(Ny) ~= Ny
    error('peec_build_geometry: Nx and Ny must be positive integers');
end

% ---- Filament generation ----
filaments = [];

for k = 1:size(conductors,1)
    xc = conductors(k,1);
    yc = conductors(k,2);
    w0 = conductors(k,3);
    h0 = conductors(k,4);
    I  = conductors(k,5);
    ph = conductors(k,6)*pi/180;

    dx = w0/Nx;
    dy = h0/Ny;

    for ix = 1:Nx
        for iy = 1:Ny
            xf = xc - w0/2 + dx*(ix-0.5);
            yf = yc - h0/2 + dy*(iy-0.5);
            % Added 6th column: conductor index
            filaments = [filaments;
                xf, yf, dx, dy, I*exp(1j*ph), k];
        end
    end
end

Nf = size(filaments,1);
Nc = size(conductors,1);

% ---- Resistance matrix ----
R = zeros(Nf);
for i = 1:Nf
    A = filaments(i,3)*filaments(i,4);
    R(i,i) = 1/(sigma*A);
end

% ---- Inductance matrix (optimized) ----
L = zeros(Nf);

for i = 1:Nf
    xi = filaments(i,1);
    yi = filaments(i,2);
    ai = sqrt(filaments(i,3)*filaments(i,4))/2;

    % Self-inductance
    L(i,i) = mu0/(2*pi)*log(1/ai);

    % Mutual inductance (only upper triangle, then symmetrize)
    for j = (i+1):Nf
        xj = filaments(j,1);
        yj = filaments(j,2);

        r = sqrt((xi-xj)^2 + (yi-yj)^2);
        L(i,j) = mu0/(2*pi)*log(1/r);
        L(j,i) = L(i,j);  % Symmetric
    end
end

% ---- Constraint matrix ----
C = zeros(Nc, Nf);
idx = 0;
for k = 1:Nc
    for n = 1:(Nx*Ny)
        idx = idx + 1;
        C(k,idx) = 1;
    end
end

% ---- Store geometry ----
geom.R = R;
geom.L = L;
geom.C = C;
geom.Nf = Nf;
geom.Nc = Nc;

% ======= FINAL GEOMETRY CHECK =======
if isempty(filaments)
    error('peec_build_geometry: filament list is empty (check Nx, Ny, geometry)');
end

% ---- Filament geometry for plotting ----
geom.filaments = filaments;   % [x y dx dy I_complex conductor_idx]
geom.Nf = size(filaments,1);
end

%}


%peec_build_geometry
%{
function geom = peec_build_geometry(conductors, winding_map, sigma, mu0, Nx, Ny)

% ======= SAFETY CHECKS =======
if isempty(conductors)
    error('peec_build_geometry: conductors array is empty');
end

if Nx <= 0 || Ny <= 0 || round(Nx) ~= Nx || round(Ny) ~= Ny
    error('peec_build_geometry: Nx and Ny must be positive integers');
end

% ---- Filament generation ----
filaments = [];

for k = 1:size(conductors,1)
    xc = conductors(k,1);
    yc = conductors(k,2);
    w0 = conductors(k,3);
    h0 = conductors(k,4);
    I  = conductors(k,5);
    ph = conductors(k,6)*pi/180;

    dx = w0/Nx;
    dy = h0/Ny;

    for ix = 1:Nx
        for iy = 1:Ny
            xf = xc - w0/2 + dx*(ix-0.5);
            yf = yc - h0/2 + dy*(iy-0.5);
            % Columns: [x, y, dx, dy, I_complex, conductor_idx]
            filaments = [filaments;
                xf, yf, dx, dy, I*exp(1j*ph), k];
        end
    end
end

Nf = size(filaments,1);
Nc = size(conductors,1);

% ---- Resistance matrix ----
R = zeros(Nf);
for i = 1:Nf
    A = filaments(i,3)*filaments(i,4);
    R(i,i) = 1/(sigma*A);
end

% ---- Inductance matrix (optimized) ----
L = zeros(Nf);

for i = 1:Nf
    xi = filaments(i,1);
    yi = filaments(i,2);
    ai = sqrt(filaments(i,3)*filaments(i,4))/2;

    % Self-inductance
    L(i,i) = mu0/(2*pi)*log(1/ai);

    % Mutual inductance (only upper triangle, then symmetrize)
    for j = (i+1):Nf
        xj = filaments(j,1);
        yj = filaments(j,2);

        r = sqrt((xi-xj)^2 + (yi-yj)^2);
        L(i,j) = mu0/(2*pi)*log(1/r);
        L(j,i) = L(i,j);  % Symmetric
    end
end

% ---- Constraint matrix ----
C = zeros(Nc, Nf);
idx = 0;
for k = 1:Nc
    for n = 1:(Nx*Ny)
        idx = idx + 1;
        C(k,idx) = 1;
    end
end

% ---- Store geometry ----
geom.R = R;
geom.L = L;
geom.C = C;
geom.Nf = Nf;
geom.Nc = Nc;

% ======= FINAL GEOMETRY CHECK =======
if isempty(filaments)
    error('peec_build_geometry: filament list is empty (check Nx, Ny, geometry)');
end

% ---- Filament geometry for plotting ----
geom.filaments = filaments;   % [x y dx dy I_complex conductor_idx]
geom.Nf = size(filaments,1);

% ---- Store winding mapping ----
if nargin >= 2 && ~isempty(winding_map)
    geom.winding_map = winding_map;
else
    % Legacy mode: no winding map provided
    geom.winding_map = [];
end

end

%}

% peec_build_geometry.m - Fixed to ensure all fields are set properly
%{
function geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny)

    % ======= SAFETY CHECKS =======
    if isempty(conductors)
        error('peec_build_geometry: conductors array is empty');
    end

    if Nx <= 0 || Ny <= 0 || round(Nx) ~= Nx || round(Ny) ~= Ny
        error('peec_build_geometry: Nx and Ny must be positive integers');
    end

    % ---- Filament generation ----
    filaments = [];

    for k = 1:size(conductors,1)

        xc = conductors(k,1);
        yc = conductors(k,2);
        w0 = conductors(k,3);
        h0 = conductors(k,4);
        I  = conductors(k,5);
        ph = conductors(k,6)*pi/180;

        dx = w0/Nx;
        dy = h0/Ny;

        for ix = 1:Nx
            for iy = 1:Ny
                xf = xc - w0/2 + dx*(ix-0.5);
                yf = yc - h0/2 + dy*(iy-0.5);
                filaments = [filaments;
                    xf, yf, dx, dy, I*exp(1j*ph)];
            end
        end
    end

    % ======= FINAL GEOMETRY CHECK =======
    if isempty(filaments)
        error('peec_build_geometry: filament list is empty (check Nx, Ny, geometry)');
    end

    Nf = size(filaments,1);
    Nc = size(conductors,1);

    % ---- Resistance matrix ----
    R = zeros(Nf);
    for i = 1:Nf
        A = filaments(i,3)*filaments(i,4);
        R(i,i) = 1/(sigma*A);
    end

    % ---- Inductance matrix ----
    L = zeros(Nf);

    for i = 1:Nf
        xi = filaments(i,1);
        yi = filaments(i,2);
        ai = sqrt(filaments(i,3)*filaments(i,4))/2;

        for j = 1:Nf
            xj = filaments(j,1);
            yj = filaments(j,2);
            aj = sqrt(filaments(j,3)*filaments(j,4))/2;

            if i == j
                r = ai;
            else
                r = sqrt((xi-xj)^2 + (yi-yj)^2);
            end

            L(i,j) = mu0/(2*pi)*log(1/r);
        end
    end

    % ---- Constraint matrix ----
    C = zeros(Nc, Nf);
    idx = 0;
    for k = 1:Nc
        for n = 1:(Nx*Ny)
            idx = idx + 1;
            C(k,idx) = 1;
        end
    end

    % ---- Store geometry (IMPORTANT: set all fields) ----
    geom.filaments = filaments;   % [x y dx dy I_complex]
    geom.Nf = Nf;                 % Number of filaments
    geom.Nc = Nc;                 % Number of conductors
    geom.R = R;                   % Resistance matrix
    geom.L = L;                   % Inductance matrix
    geom.C = C;                   % Constraint matrix
    geom.Nx = Nx;                 % Filaments per conductor in x
    geom.Ny = Ny;                 % Filaments per conductor in y

    % Verify all critical fields are present
    required_fields = {'filaments', 'Nf', 'Nc', 'R', 'L', 'C'};
    for i = 1:length(required_fields)
        if ~isfield(geom, required_fields{i})
            error('peec_build_geometry: failed to set field %s', required_fields{i});
        end
    end
end


% peec_build_geometry.m - Fixed to ensure all fields are set properly

function geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny)

    % ======= SAFETY CHECKS =======
    if isempty(conductors)
        error('peec_build_geometry: conductors array is empty');
    end

    if Nx <= 0 || Ny <= 0 || round(Nx) ~= Nx || round(Ny) ~= Ny
        error('peec_build_geometry: Nx and Ny must be positive integers');
    end

    % ---- Filament generation ----
    filaments = [];

    for k = 1:size(conductors,1)

        xc = conductors(k,1);
        yc = conductors(k,2);
        w0 = conductors(k,3);
        h0 = conductors(k,4);
        I  = conductors(k,5);
        ph = conductors(k,6)*pi/180;

        dx = w0/Nx;
        dy = h0/Ny;

        for ix = 1:Nx
            for iy = 1:Ny
                xf = xc - w0/2 + dx*(ix-0.5);
                yf = yc - h0/2 + dy*(iy-0.5);
                filaments = [filaments;
                    xf, yf, dx, dy, k, I*exp(1j*ph)];  % Added conductor index k
            end
        end
    end

    % ======= FINAL GEOMETRY CHECK =======
    if isempty(filaments)
        error('peec_build_geometry: filament list is empty (check Nx, Ny, geometry)');
    end

    Nf = size(filaments,1);
    Nc = size(conductors,1);

    % ---- Resistance matrix ----
    R = zeros(Nf);
    for i = 1:Nf
        A = filaments(i,3)*filaments(i,4);
        R(i,i) = 1/(sigma*A);
    end

    % ---- Inductance matrix ----
    L = zeros(Nf);

    for i = 1:Nf
        xi = filaments(i,1);
        yi = filaments(i,2);
        ai = sqrt(filaments(i,3)*filaments(i,4))/2;

        for j = 1:Nf
            xj = filaments(j,1);
            yj = filaments(j,2);
            aj = sqrt(filaments(j,3)*filaments(j,4))/2;

            if i == j
                r = ai;
            else
                r = sqrt((xi-xj)^2 + (yi-yj)^2);
            end

            L(i,j) = mu0/(2*pi)*log(1/r);
        end
    end

    % ---- Constraint matrix ----
    C = zeros(Nc, Nf);
    idx = 0;
    for k = 1:Nc
        for n = 1:(Nx*Ny)
            idx = idx + 1;
            C(k,idx) = 1;
        end
    end

    % ---- Store geometry (IMPORTANT: set all fields) ----
    geom.filaments = filaments;   % [x y dx dy conductor_idx I_complex]
    geom.Nf = Nf;                 % Number of filaments
    geom.Nc = Nc;                 % Number of conductors
    geom.R = R;                   % Resistance matrix
    geom.L = L;                   % Inductance matrix
    geom.C = C;                   % Constraint matrix
    geom.Nx = Nx;                 % Filaments per conductor in x
    geom.Ny = Ny;                 % Filaments per conductor in y

    % Verify all critical fields are present
    required_fields = {'filaments', 'Nf', 'Nc', 'R', 'L', 'C'};
    for i = 1:length(required_fields)
        if ~isfield(geom, required_fields{i})
            error('peec_build_geometry: failed to set field %s', required_fields{i});
        end
    end
end


% peec_build_geometry.m - Fixed to ensure all fields are set properly

% peec_build_geometry.m - Fixed to ensure all fields are set properly

function geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny, varargin)

    % ======= PARSE INPUTS =======
    % Handle optional winding_map argument for multi-winding transformers
    if nargin > 5 && ~isempty(varargin{1})
        winding_map = varargin{1};
    else
        % Single winding - all conductors belong to winding 1
        winding_map = ones(size(conductors, 1), 1);
    end

    % ======= SAFETY CHECKS =======
    if isempty(conductors)
        error('peec_build_geometry: conductors array is empty');
    end

    if Nx <= 0 || Ny <= 0 || round(Nx) ~= Nx || round(Ny) ~= Ny
        error('peec_build_geometry: Nx and Ny must be positive integers');
    end

    % ---- Filament generation ----
    filaments = [];

    for k = 1:size(conductors,1)

        xc = conductors(k,1);
        yc = conductors(k,2);
        w0 = conductors(k,3);
        h0 = conductors(k,4);
        I  = conductors(k,5);
        ph = conductors(k,6)*pi/180;

        dx = w0/Nx;
        dy = h0/Ny;

        for ix = 1:Nx
            for iy = 1:Ny
                xf = xc - w0/2 + dx*(ix-0.5);
                yf = yc - h0/2 + dy*(iy-0.5);
                filaments = [filaments;
                    xf, yf, dx, dy, k, winding_map(k), I*exp(1j*ph)];  % Added conductor idx and winding idx
            end
        end
    end

    % ======= FINAL GEOMETRY CHECK =======
    if isempty(filaments)
        error('peec_build_geometry: filament list is empty (check Nx, Ny, geometry)');
    end

    Nf = size(filaments,1);
    Nc = size(conductors,1);

    % ---- Resistance matrix ----
    R = zeros(Nf);
    for i = 1:Nf
        A = filaments(i,3)*filaments(i,4);
        R(i,i) = 1/(sigma*A);
    end

    % ---- Inductance matrix ----
    L = zeros(Nf);

    for i = 1:Nf
        xi = filaments(i,1);
        yi = filaments(i,2);
        ai = sqrt(filaments(i,3)*filaments(i,4))/2;

        for j = 1:Nf
            xj = filaments(j,1);
            yj = filaments(j,2);
            aj = sqrt(filaments(j,3)*filaments(j,4))/2;

            if i == j
                r = ai;
            else
                r = sqrt((xi-xj)^2 + (yi-yj)^2);
            end

            L(i,j) = mu0/(2*pi)*log(1/r);
        end
    end

    % ---- Constraint matrix ----
    C = zeros(Nc, Nf);
    idx = 0;
    for k = 1:Nc
        for n = 1:(Nx*Ny)
            idx = idx + 1;
            C(k,idx) = 1;
        end
    end

    % ---- Store geometry (IMPORTANT: set all fields) ----
    geom.filaments = filaments;   % [x y dx dy conductor_idx winding_idx I_complex]
    geom.Nf = Nf;                 % Number of filaments
    geom.Nc = Nc;                 % Number of conductors
    geom.R = R;                   % Resistance matrix
    geom.L = L;                   % Inductance matrix
    geom.C = C;                   % Constraint matrix
    geom.Nx = Nx;                 % Filaments per conductor in x
    geom.Ny = Ny;                 % Filaments per conductor in y
    geom.winding_map = winding_map;  % Winding assignment for each conductor

    % Verify all critical fields are present
    required_fields = {'filaments', 'Nf', 'Nc', 'R', 'L', 'C'};
    for i = 1:length(required_fields)
        if ~isfield(geom, required_fields{i})
            error('peec_build_geometry: failed to set field %s', required_fields{i});
        end
    end
end

%}

% peec_build_geometry.m - with wire shape support
% Build PEEC geometry from conductor array and optional wire shapes

function geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny, varargin)
% Build PEEC geometry with optional multi-winding and wire shape support
%
% Usage:
%   geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny)
%   geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny, winding_map)
%   geom = peec_build_geometry(conductors, sigma, mu0, Nx, Ny, winding_map, wire_shapes)
%
% Inputs:
%   conductors  - [N×6] array: [x, y, width, height, current, phase]
%   sigma       - Conductivity [S/m]
%   mu0         - Permeability [H/m]
%   Nx, Ny      - Number of filaments per conductor in x and y
%   winding_map - (optional) [N×1] array: winding ID for each conductor
%   wire_shapes - (optional) Cell array: 'round' or 'rectangular' for each conductor
%
% Outputs:
%   geom        - Structure containing filaments, matrices, and metadata

    % ======= PARSE INPUTS =======
    % Handle optional winding_map argument
    if nargin > 5 && ~isempty(varargin{1})
        winding_map = varargin{1};
    else
        % Single winding - all conductors belong to winding 1
        winding_map = ones(size(conductors, 1), 1);
    end

    % Handle optional wire_shapes argument
    if nargin > 6 && ~isempty(varargin{2})
        wire_shapes = varargin{2};
    else
        % Default to round wire
        wire_shapes = cell(size(conductors, 1), 1);
        for i = 1:size(conductors, 1)
            wire_shapes{i} = 'round';
        end
    end

    % ======= SAFETY CHECKS =======
    if isempty(conductors)
        error('peec_build_geometry: conductors array is empty');
    end

    if Nx <= 0 || Ny <= 0 || round(Nx) ~= Nx || round(Ny) ~= Ny
        error('peec_build_geometry: Nx and Ny must be positive integers');
    end

    % Ensure wire_shapes is correct length
    if length(wire_shapes) ~= size(conductors, 1)
        warning('wire_shapes length mismatch, using default (round)');
        wire_shapes = cell(size(conductors, 1), 1);
        for i = 1:size(conductors, 1)
            wire_shapes{i} = 'round';
        end
    end

    % ======= FILAMENT GENERATION =======
    filaments = [];

    for k = 1:size(conductors,1)

        xc = conductors(k,1);
        yc = conductors(k,2);
        w0 = conductors(k,3);
        h0 = conductors(k,4);
        I  = conductors(k,5);
        ph = conductors(k,6)*pi/180;

        dx = w0/Nx;
        dy = h0/Ny;

        for ix = 1:Nx
            for iy = 1:Ny
                xf = xc - w0/2 + dx*(ix-0.5);
                yf = yc - h0/2 + dy*(iy-0.5);
                filaments = [filaments;
                    xf, yf, dx, dy, k, winding_map(k), I*exp(1j*ph)];
            end
        end
    end

    % ======= FINAL GEOMETRY CHECK =======
    if isempty(filaments)
        error('peec_build_geometry: filament list is empty (check Nx, Ny, geometry)');
    end

    Nf = size(filaments,1);
    Nc = size(conductors,1);

    % ======= RESISTANCE MATRIX =======
    R = zeros(Nf);
    for i = 1:Nf
        A = filaments(i,3)*filaments(i,4);
        R(i,i) = 1/(sigma*A);
    end

    % ======= INDUCTANCE MATRIX =======
    L = zeros(Nf);

    for i = 1:Nf
        xi = filaments(i,1);
        yi = filaments(i,2);
        ai = sqrt(filaments(i,3)*filaments(i,4))/2;

        for j = 1:Nf
            xj = filaments(j,1);
            yj = filaments(j,2);
            aj = sqrt(filaments(j,3)*filaments(j,4))/2;

            if i == j
                r = ai;
            else
                r = sqrt((xi-xj)^2 + (yi-yj)^2);
            end

            L(i,j) = mu0/(2*pi)*log(1/r);
        end
    end

    % ======= CONSTRAINT MATRIX =======
    C = zeros(Nc, Nf);
    idx = 0;
    for k = 1:Nc
        for n = 1:(Nx*Ny)
            idx = idx + 1;
            C(k,idx) = 1;
        end
    end

    % ======= STORE GEOMETRY =======
    geom.filaments = filaments;       % [x y dx dy conductor_idx winding_idx I_complex]
    geom.Nf = Nf;                     % Number of filaments
    geom.Nc = Nc;                     % Number of conductors
    geom.R = R;                       % Resistance matrix
    geom.L = L;                       % Inductance matrix
    geom.C = C;                       % Constraint matrix
    geom.Nx = Nx;                     % Filaments per conductor in x
    geom.Ny = Ny;                     % Filaments per conductor in y
    geom.winding_map = winding_map;   % Winding assignment for each conductor
    geom.wire_shapes = wire_shapes;   % Wire shape for each conductor ('round' or 'rectangular')
    geom.conductors = conductors;     % Store original conductor geometry

    % ======= VERIFY ALL FIELDS =======
    required_fields = {'filaments', 'Nf', 'Nc', 'R', 'L', 'C', 'wire_shapes'};
    for i = 1:length(required_fields)
        if ~isfield(geom, required_fields{i})
            error('peec_build_geometry: failed to set field %s', required_fields{i});
        end
    end
end
