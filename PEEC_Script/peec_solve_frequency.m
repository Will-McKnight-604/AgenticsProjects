%peec_solve_frequency
%{
function results = peec_solve_frequency(geom, conductors, f, sigma, mu0)

% ================= HARD FAIL CHECKS =================
if nargin < 5
    error('peec_solve_frequency: must be called as peec_solve_frequency(geom, conductors, f, sigma, mu0)');
end

if isempty(sigma) || ~isscalar(sigma)
    error('peec_solve_frequency: sigma is empty or not scalar');
end

if isempty(mu0) || ~isscalar(mu0)
    error('peec_solve_frequency: mu0 is empty or not scalar');
end

if isempty(geom) || ~isfield(geom,'filaments')
    error('peec_solve_frequency: invalid geometry struct');
end

filaments = geom.filaments;
Nf = size(filaments,1);

if Nf == 0
    error('peec_solve_frequency: zero filaments');
end

Nc = size(conductors,1);
if Nc == 0
    error('peec_solve_frequency: zero conductors');
end

    % ======= SAFETY CHECKS =======
    if ~isfield(geom,'filaments') || isempty(geom.filaments)
        error('peec_solve_frequency: geom.filaments is missing or empty');
    end

    if isempty(conductors)
        error('peec_solve_frequency: conductors array is empty');
    end


    w = 2*pi*f;

    R = geom.R;
    L = geom.L;
    C = geom.C;
    Nf = geom.Nf;
    Nc = geom.Nc;

   % ================= IMPEDANCE =================
R = zeros(Nf);
for i = 1:Nf
    A = filaments(i,3) * filaments(i,4);
    R(i,i) = 1 / (sigma * A);
end

L = geom.L;   % MUST be precomputed in geometry

if isempty(L) || any(size(L) ~= [Nf Nf])
    error('peec_solve_frequency: inductance matrix L invalid');
end

Z = R + 1j * w * L;

% ================= CONNECTIVITY CHECK =================
if ~isfield(geom,'C') || isempty(geom.C)
    error('peec_solve_frequency: Connectivity matrix C is empty. Geometry is invalid or was built without conductors.');
end

C = geom.C;

if size(C,1) == 0 || size(C,2) == 0
    error('peec_solve_frequency: C matrix is 0x0. Check peec_build_geometry and conductor assignment.');
end


    I_target = conductors(:,5).*exp(1j*conductors(:,6)*pi/180);

    A = [Z, C.'; C, zeros(Nc)];
    b = [zeros(Nf,1); I_target];


    % ======= MATRIX SANITY CHECK =======
    if size(Z,1) == 0 || size(Z,2) == 0
        error('peec_solve_frequency: impedance matrix Z is empty');
    end

    if size(Z,1) ~= size(Z,2)
        error('peec_solve_frequency: impedance matrix Z is not square');
    end

    if size(C,2) ~= size(Z,1)
        error('peec_solve_frequency: constraint matrix C incompatible with Z');
    end

disp(['DEBUG: size(Z)=', mat2str(size(Z)), ...
      ', size(C)=', mat2str(size(C)), ...
      ', mu0=', num2str(mu0), ...
      ', sigma=', num2str(sigma)]);


    x = A\b;
    I_fil = x(1:Nf);

    % ---- Power loss ----
    P_fil = zeros(Nf,1);
    for i = 1:Nf
        P_fil(i) = 0.5*real(conj(I_fil(i))*R(i,i)*I_fil(i));
    end

    results.I_fil   = I_fil;
    results.P_fil   = P_fil;
    results.P_total = sum(P_fil);

end



%peec_solve_frequency
function results = peec_solve_frequency(geom, conductors, f, sigma, mu0)

% ================= HARD FAIL CHECKS =================
if nargin < 5
    error('peec_solve_frequency: must be called as peec_solve_frequency(geom, conductors, f, sigma, mu0)');
end

if isempty(sigma) || ~isscalar(sigma)
    error('peec_solve_frequency: sigma is empty or not scalar');
end

if isempty(mu0) || ~isscalar(mu0)
    error('peec_solve_frequency: mu0 is empty or not scalar');
end

if isempty(geom) || ~isfield(geom,'filaments')
    error('peec_solve_frequency: invalid geometry struct');
end

filaments = geom.filaments;
Nf = size(filaments,1);

if Nf == 0
    error('peec_solve_frequency: zero filaments');
end

Nc = size(conductors,1);
if Nc == 0
    error('peec_solve_frequency: zero conductors');
end

if ~isfield(geom,'filaments') || isempty(geom.filaments)
    error('peec_solve_frequency: geom.filaments is missing or empty');
end

w = 2*pi*f;

% Use precomputed R and L from geometry
R = geom.R;
L = geom.L;

if isempty(L) || any(size(L) ~= [Nf Nf])
    error('peec_solve_frequency: inductance matrix L invalid');
end

% Impedance matrix
Z = R + 1j * w * L;

% ================= CONNECTIVITY CHECK =================
if ~isfield(geom,'C') || isempty(geom.C)
    error('peec_solve_frequency: Connectivity matrix C is empty. Geometry is invalid or was built without conductors.');
end

C = geom.C;

if size(C,1) == 0 || size(C,2) == 0
    error('peec_solve_frequency: C matrix is 0x0. Check peec_build_geometry and conductor assignment.');
end

% Target currents
I_target = conductors(:,5).*exp(1j*conductors(:,6)*pi/180);

% Build system matrix
A = [Z, C.'; C, zeros(Nc)];
b = [zeros(Nf,1); I_target];

% ======= MATRIX SANITY CHECK =======
if size(Z,1) == 0 || size(Z,2) == 0
    error('peec_solve_frequency: impedance matrix Z is empty');
end

if size(Z,1) ~= size(Z,2)
    error('peec_solve_frequency: impedance matrix Z is not square');
end

if size(C,2) ~= size(Z,1)
    error('peec_solve_frequency: constraint matrix C incompatible with Z');
end

% Solve system
x = A\b;
I_fil = x(1:Nf);

% ---- Power loss ----
P_fil = zeros(Nf,1);
for i = 1:Nf
    P_fil(i) = 0.5*real(conj(I_fil(i))*R(i,i)*I_fil(i));
end

results.I_fil   = I_fil;
results.P_fil   = P_fil;
results.P_total = sum(P_fil);

end

%}
%{
%peec_solve_frequency
function results = peec_solve_frequency(geom, conductors, f, sigma, mu0)

% ================= HARD FAIL CHECKS =================
if nargin < 5
    error('peec_solve_frequency: must be called as peec_solve_frequency(geom, conductors, f, sigma, mu0)');
end

if isempty(sigma) || ~isscalar(sigma)
    error('peec_solve_frequency: sigma is empty or not scalar');
end

if isempty(mu0) || ~isscalar(mu0)
    error('peec_solve_frequency: mu0 is empty or not scalar');
end

if isempty(geom) || ~isfield(geom,'filaments')
    error('peec_solve_frequency: invalid geometry struct');
end

filaments = geom.filaments;
Nf = size(filaments,1);

if Nf == 0
    error('peec_solve_frequency: zero filaments');
end

Nc = size(conductors,1);
if Nc == 0
    error('peec_solve_frequency: zero conductors');
end

if ~isfield(geom,'filaments') || isempty(geom.filaments)
    error('peec_solve_frequency: geom.filaments is missing or empty');
end

w = 2*pi*f;

% Use precomputed R and L from geometry
R = geom.R;
L = geom.L;

if isempty(L) || any(size(L) ~= [Nf Nf])
    error('peec_solve_frequency: inductance matrix L invalid');
end

% Impedance matrix
Z = R + 1j * w * L;

% ================= CONNECTIVITY CHECK =================
if ~isfield(geom,'C') || isempty(geom.C)
    error('peec_solve_frequency: Connectivity matrix C is empty. Geometry is invalid or was built without conductors.');
end

C = geom.C;

if size(C,1) == 0 || size(C,2) == 0
    error('peec_solve_frequency: C matrix is 0x0. Check peec_build_geometry and conductor assignment.');
end

% Target currents
I_target = conductors(:,5).*exp(1j*conductors(:,6)*pi/180);

% Build system matrix
A = [Z, C.'; C, zeros(Nc)];
b = [zeros(Nf,1); I_target];

% ======= MATRIX SANITY CHECK =======
if size(Z,1) == 0 || size(Z,2) == 0
    error('peec_solve_frequency: impedance matrix Z is empty');
end

if size(Z,1) ~= size(Z,2)
    error('peec_solve_frequency: impedance matrix Z is not square');
end

if size(C,2) ~= size(Z,1)
    error('peec_solve_frequency: constraint matrix C incompatible with Z');
end

% Solve system
x = A\b;
I_fil = x(1:Nf);
lambda = x(Nf+1:end);  % Lagrange multipliers (conductor voltages)

% ---- Power loss per filament ----
P_fil = zeros(Nf,1);
for i = 1:Nf
    P_fil(i) = 0.5*real(conj(I_fil(i))*R(i,i)*I_fil(i));
end

% ========================================================
% PEEC-COMPLIANT PER-WINDING ANALYSIS
% ========================================================

% ---- Method 1: Direct summation (energy conservation) ----
P_winding = zeros(Nc,1);
for k = 1:Nc
    fil_indices = find(filaments(:,6) == k);
    P_winding(k) = sum(P_fil(fil_indices));
end

% ---- Method 2: From complex power (using Lagrange multipliers) ----
% The Lagrange multipliers represent the voltage drop across each conductor
% P = 0.5 * Re(V * conj(I))
P_winding_alt = zeros(Nc,1);
for k = 1:Nc
    P_winding_alt(k) = 0.5 * real(lambda(k) * conj(I_target(k)));
end

% Both methods should give identical results (verify)
P_diff = abs(P_winding - P_winding_alt);
if max(P_diff) > 1e-6 * max(P_winding)
    warning('Power calculation mismatch between methods: max diff = %.2e', max(P_diff));
end

% ---- AC impedance per winding (from V-I relationship) ----
% Z_ac = V / I  where V is the voltage drop (lambda)
Z_ac_winding = zeros(Nc,1);
for k = 1:Nc
    if abs(I_target(k)) > 0
        Z_ac_winding(k) = lambda(k) / I_target(k);
    else
        Z_ac_winding(k) = 0;
    end
end

% AC resistance (real part of impedance)
R_ac_winding = real(Z_ac_winding);

% AC reactance (imaginary part)
X_ac_winding = imag(Z_ac_winding);

% ---- DC resistance (geometric calculation) ----
% For a 2D conductor: R_dc = rho * length / (width * height)
% Since this is 2D cross-section, we assume unit length (1 meter)
R_dc_winding = zeros(Nc,1);
for k = 1:Nc
    width_cond  = conductors(k,3);
    height_cond = conductors(k,4);
    A_total = width_cond * height_cond;  % Cross-sectional area

    % For unit length conductor: R = rho * L / A = L / (sigma * A)
    % Assuming L = 1 meter for 2D cross-section analysis
    R_dc_winding(k) = 1 / (sigma * A_total);
end

% ---- AC/DC resistance ratio (proximity/skin effect factor) ----
Fr = R_ac_winding ./ R_dc_winding;

% ---- Effective AC inductance per winding ----
L_ac_winding = X_ac_winding / w;

% Store results
results.I_fil   = I_fil;
results.P_fil   = P_fil;
results.P_total = sum(P_fil);
results.lambda  = lambda;  % Lagrange multipliers (conductor voltages)

% Per-winding results (PEEC-compliant)
results.P_winding      = P_winding;       % Loss per winding [W]
results.Z_ac_winding   = Z_ac_winding;    % Complex AC impedance [Ohm]
results.R_ac_winding   = R_ac_winding;    % AC resistance [Ohm]
results.X_ac_winding   = X_ac_winding;    % AC reactance [Ohm]
results.L_ac_winding   = L_ac_winding;    % AC inductance [H]
results.R_dc_winding   = R_dc_winding;    % DC resistance [Ohm]
results.Fr             = Fr;              % AC/DC resistance ratio

end



%peec_solve_frequency
function results = peec_solve_frequency(geom, conductors, f, sigma, mu0)

% ================= HARD FAIL CHECKS =================
if nargin < 5
    error('peec_solve_frequency: must be called as peec_solve_frequency(geom, conductors, f, sigma, mu0)');
end

if isempty(sigma) || ~isscalar(sigma)
    error('peec_solve_frequency: sigma is empty or not scalar');
end

if isempty(mu0) || ~isscalar(mu0)
    error('peec_solve_frequency: mu0 is empty or not scalar');
end

if isempty(geom) || ~isfield(geom,'filaments')
    error('peec_solve_frequency: invalid geometry struct');
end

filaments = geom.filaments;
Nf = size(filaments,1);

if Nf == 0
    error('peec_solve_frequency: zero filaments');
end

Nc = size(conductors,1);
if Nc == 0
    error('peec_solve_frequency: zero conductors');
end

if ~isfield(geom,'filaments') || isempty(geom.filaments)
    error('peec_solve_frequency: geom.filaments is missing or empty');
end

w = 2*pi*f;

% Use precomputed R and L from geometry
R = geom.R;
L = geom.L;

if isempty(L) || any(size(L) ~= [Nf Nf])
    error('peec_solve_frequency: inductance matrix L invalid');
end

% Impedance matrix
Z = R + 1j * w * L;

% ================= CONNECTIVITY CHECK =================
if ~isfield(geom,'C') || isempty(geom.C)
    error('peec_solve_frequency: Connectivity matrix C is empty. Geometry is invalid or was built without conductors.');
end

C = geom.C;

if size(C,1) == 0 || size(C,2) == 0
    error('peec_solve_frequency: C matrix is 0x0. Check peec_build_geometry and conductor assignment.');
end

% Target currents
I_target = conductors(:,5).*exp(1j*conductors(:,6)*pi/180);

% Build system matrix
A = [Z, C.'; C, zeros(Nc)];
b = [zeros(Nf,1); I_target];

% ======= MATRIX SANITY CHECK =======
if size(Z,1) == 0 || size(Z,2) == 0
    error('peec_solve_frequency: impedance matrix Z is empty');
end

if size(Z,1) ~= size(Z,2)
    error('peec_solve_frequency: impedance matrix Z is not square');
end

if size(C,2) ~= size(Z,1)
    error('peec_solve_frequency: constraint matrix C incompatible with Z');
end

% Solve system
x = A\b;
I_fil = x(1:Nf);
lambda = x(Nf+1:end);  % Lagrange multipliers (conductor voltages)

% ---- Power loss per filament ----
P_fil = zeros(Nf,1);
for i = 1:Nf
    P_fil(i) = 0.5*real(conj(I_fil(i))*R(i,i)*I_fil(i));
end

% ========================================================
% PER-CONDUCTOR ANALYSIS (Each turn/layer)
% ========================================================

% ---- Method 1: Direct summation (energy conservation) ----
P_conductor = zeros(Nc,1);
for k = 1:Nc
    fil_indices = find(filaments(:,6) == k);
    P_conductor(k) = sum(P_fil(fil_indices));
end

% ---- Method 2: From complex power (using Lagrange multipliers) ----
P_conductor_alt = zeros(Nc,1);
for k = 1:Nc
    P_conductor_alt(k) = 0.5 * real(lambda(k) * conj(I_target(k)));
end

% ---- AC impedance per conductor ----
Z_ac_conductor = zeros(Nc,1);
for k = 1:Nc
    if abs(I_target(k)) > 0
        Z_ac_conductor(k) = lambda(k) / I_target(k);
    else
        Z_ac_conductor(k) = 0;
    end
end

R_ac_conductor = real(Z_ac_conductor);
X_ac_conductor = imag(Z_ac_conductor);

% ---- DC resistance per conductor (geometric) ----
R_dc_conductor = zeros(Nc,1);
for k = 1:Nc
    width_cond  = conductors(k,3);
    height_cond = conductors(k,4);
    A_total = width_cond * height_cond;
    R_dc_conductor(k) = 1 / (sigma * A_total);
end

Fr_conductor = R_ac_conductor ./ R_dc_conductor;
L_ac_conductor = X_ac_conductor / w;

% ========================================================
% PER-WINDING ANALYSIS (Sum over all turns in winding)
% ========================================================

if isfield(geom, 'winding_map') && ~isempty(geom.winding_map)
    winding_map = geom.winding_map;
    unique_windings = unique(winding_map.winding_id);
    N_windings = length(unique_windings);

    % Initialize winding results
    P_winding = zeros(N_windings, 1);
    V_winding = zeros(N_windings, 1);
    I_winding = zeros(N_windings, 1);
    Z_ac_winding = zeros(N_windings, 1);
    R_ac_winding = zeros(N_windings, 1);
    X_ac_winding = zeros(N_windings, 1);
    L_ac_winding = zeros(N_windings, 1);
    R_dc_winding = zeros(N_windings, 1);
    Fr_winding = zeros(N_windings, 1);
    N_turns_winding = zeros(N_windings, 1);

    for w_idx = 1:N_windings
        winding_id = unique_windings(w_idx);

        % Find all conductors belonging to this winding
        conductor_indices = find(winding_map.winding_id == winding_id);
        N_turns_winding(w_idx) = length(conductor_indices);

        % Sum power losses (all turns contribute to total winding loss)
        P_winding(w_idx) = sum(P_conductor(conductor_indices));

        % For series windings: Total voltage is sum of voltages across each turn
        V_winding(w_idx) = sum(lambda(conductor_indices));

        % Current through winding (same for all turns in series)
        I_winding(w_idx) = I_target(conductor_indices(1));

        % Winding impedance: Z = V_total / I
        if abs(I_winding(w_idx)) > 0
            Z_ac_winding(w_idx) = V_winding(w_idx) / I_winding(w_idx);
        else
            Z_ac_winding(w_idx) = 0;
        end

        R_ac_winding(w_idx) = real(Z_ac_winding(w_idx));
        X_ac_winding(w_idx) = imag(Z_ac_winding(w_idx));
        L_ac_winding(w_idx) = X_ac_winding(w_idx) / w;

        % DC resistance: sum of resistances in series
        R_dc_winding(w_idx) = sum(R_dc_conductor(conductor_indices));

        % Proximity factor for entire winding
        Fr_winding(w_idx) = R_ac_winding(w_idx) / R_dc_winding(w_idx);
    end

    % Store winding-level results
    results.winding.P = P_winding;
    results.winding.V = V_winding;
    results.winding.I = I_winding;
    results.winding.Z_ac = Z_ac_winding;
    results.winding.R_ac = R_ac_winding;
    results.winding.X_ac = X_ac_winding;
    results.winding.L_ac = L_ac_winding;
    results.winding.R_dc = R_dc_winding;
    results.winding.Fr = Fr_winding;
    results.winding.N_turns = N_turns_winding;
    results.winding.ids = unique_windings;
else
    results.winding = [];
end

% Store basic results
results.I_fil   = I_fil;
results.P_fil   = P_fil;
results.P_total = sum(P_fil);
results.lambda  = lambda;

% Per-conductor results (per turn/layer)
results.conductor.P = P_conductor;
results.conductor.Z_ac = Z_ac_conductor;
results.conductor.R_ac = R_ac_conductor;
results.conductor.X_ac = X_ac_conductor;
results.conductor.L_ac = L_ac_conductor;
results.conductor.R_dc = R_dc_conductor;
results.conductor.Fr = Fr_conductor;

% Legacy field names for backward compatibility
results.P_winding = P_conductor;  % Actually per-conductor
results.Z_ac_winding = Z_ac_conductor;
results.R_ac_winding = R_ac_conductor;
results.X_ac_winding = X_ac_conductor;
results.L_ac_winding = L_ac_conductor;
results.R_dc_winding = R_dc_conductor;
results.Fr = Fr_conductor;

end

%}

% peec_solve_frequency.m - Accepts optional solve_options (6th arg) for solver control
function results = peec_solve_frequency(geom, conductors, f, sigma, mu0, solve_options)

    % ================= HARD FAIL CHECKS =================
    if nargin < 5
        error('peec_solve_frequency: must be called as peec_solve_frequency(geom, conductors, f, sigma, mu0)');
    end

    if nargin < 6 || isempty(solve_options)
        solve_options = struct();
    end

    if isempty(sigma) || ~isscalar(sigma)
        error('peec_solve_frequency: sigma is empty or not scalar');
    end

    if isempty(mu0) || ~isscalar(mu0)
        error('peec_solve_frequency: mu0 is empty or not scalar');
    end

    if isempty(geom) || ~isfield(geom,'filaments')
        error('peec_solve_frequency: invalid geometry struct');
    end

    filaments = geom.filaments;
    Nf = size(filaments,1);

    if Nf == 0
        error('peec_solve_frequency: zero filaments');
    end

    Nc = size(conductors,1);
    if Nc == 0
        error('peec_solve_frequency: zero conductors');
    end

    % ======= SAFETY CHECKS =======
    if ~isfield(geom,'filaments') || isempty(geom.filaments)
        error('peec_solve_frequency: geom.filaments is missing or empty');
    end

    if isempty(conductors)
        error('peec_solve_frequency: conductors array is empty');
    end

    % ================= PARSE SOLVE OPTIONS =================
    lin_solver        = psf_get_str(solve_options, 'linear_solver', 'auto');
    iter_min_nf       = psf_get_num(solve_options, 'iter_min_size_for_use', 2200);
    iter_tol          = psf_get_num(solve_options, 'iter_tol', 5e-7);
    iter_maxit        = max(1, round(psf_get_num(solve_options, 'iter_maxit', 80)));
    iter_restart      = max(1, round(psf_get_num(solve_options, 'iter_restart', 30)));
    precond_type      = psf_get_str(solve_options, 'preconditioner', 'jacobi');
    relres_max        = psf_get_num(solve_options, 'iter_accept_relres_max_standard', 5e-4);
    enable_retry      = psf_get_bool(solve_options, 'enable_iterative_retry', true);
    retry_max         = max(0, round(psf_get_num(solve_options, 'iterative_retry_max', 2)));
    retry_relax       = max(1.0, psf_get_num(solve_options, 'iterative_retry_relax_tol', 4.0));
    retry_maxit_scale = max(1.0, psf_get_num(solve_options, 'iterative_retry_maxit_scale', 1.8));

    % ================= ANGULAR FREQUENCY =================
    w = 2*pi*f;

    % ================= GET GEOMETRY MATRICES =================
    if isfield(geom, 'Nf')
        Nf = geom.Nf;
    else
        Nf = size(geom.filaments, 1);
    end

    if isfield(geom, 'Nc')
        Nc = geom.Nc;
    else
        Nc = size(conductors, 1);
    end

    % ================= RESISTANCE MATRIX =================
    % Recalculate R from filament dimensions for consistency
    R_diag = zeros(Nf, 1);
    for i = 1:Nf
        A_fil = filaments(i,3) * filaments(i,4);
        R_diag(i) = 1 / (sigma * A_fil);
    end
    R = diag(R_diag);

    % ================= INDUCTANCE MATRIX =================
    L = geom.L;   % MUST be precomputed in geometry

    if isempty(L) || any(size(L) ~= [Nf Nf])
        error('peec_solve_frequency: inductance matrix L invalid');
    end

    % ================= IMPEDANCE MATRIX =================
    Z = R + 1j * w * L;

    % ================= CONNECTIVITY CHECK =================
    if ~isfield(geom,'C') || isempty(geom.C)
        error('peec_solve_frequency: Connectivity matrix C is empty. Geometry is invalid or was built without conductors.');
    end

    C = geom.C;

    if size(C,1) == 0 || size(C,2) == 0
        error('peec_solve_frequency: C matrix is 0x0. Check peec_build_geometry and conductor assignment.');
    end

    % ================= TARGET CURRENTS =================
    I_target = conductors(:,5).*exp(1j*conductors(:,6)*pi/180);

    % ================= BUILD SYSTEM MATRIX =================
    A_sys = [Z, C.'; C, zeros(Nc)];
    b_sys = [zeros(Nf,1); I_target];
    N_sys = Nf + Nc;

    % ================= SOLVER SELECTION =================
    use_iterative    = false;
    iter_solver_name = 'bicgstab';
    if strcmp(lin_solver, 'direct')
        use_iterative = false;
    elseif any(strcmp(lin_solver, {'bicgstab', 'gmres'}))
        use_iterative    = true;
        iter_solver_name = lin_solver;
    else  % 'auto' or unknown
        use_iterative = (N_sys >= iter_min_nf);
    end

    x = [];
    solved_iterative = false;
    if use_iterative
        [x, solved_iterative] = psf_iterative_solve(A_sys, b_sys, iter_solver_name, ...
            iter_tol, iter_maxit, iter_restart, precond_type, relres_max, ...
            enable_retry, retry_max, retry_relax, retry_maxit_scale);
    end

    if ~solved_iterative
        x = A_sys \ b_sys;
    end

    I_fil = x(1:Nf);

    if isempty(I_fil)
        error('peec_solve_frequency: solver returned empty current vector');
    end

    % ================= POWER LOSS (vectorized) =================
    P_fil = 0.5 * R_diag .* abs(I_fil).^2;

    % ================= RETURN RESULTS =================
    results.I_fil   = I_fil;
    results.P_fil   = P_fil;
    results.P_total = sum(P_fil);
    results.f       = f;
    results.R       = R;
    results.L       = L;
    results.Z       = Z;
end

% ---- Local helpers (prefixed psf_ to avoid path conflicts) ----

function [x, ok] = psf_iterative_solve(A, b, solver_name, tol, maxit, restart, ...
        precond_type, relres_max, enable_retry, retry_max, retry_relax, retry_maxit_scale)
    x  = [];
    ok = false;
    M_pre = psf_build_preconditioner(A, precond_type);
    [x_try, flag, relres] = psf_call_solver(A, b, solver_name, tol, maxit, restart, M_pre);
    if flag == 0 && relres <= relres_max
        x  = x_try;
        ok = true;
        return;
    end
    if enable_retry
        for r = 1:retry_max
            tol_r   = tol   * retry_relax^r;
            maxit_r = round(maxit * retry_maxit_scale^r);
            [x_try, flag, relres] = psf_call_solver(A, b, solver_name, tol_r, maxit_r, restart, M_pre);
            if flag == 0 && relres <= relres_max * retry_relax^r
                x  = x_try;
                ok = true;
                return;
            end
        end
    end
end

function [x, flag, relres] = psf_call_solver(A, b, solver_name, tol, maxit, restart, M_pre)
    x = zeros(size(b)); flag = 1; relres = inf;
    try
        if strcmp(solver_name, 'gmres')
            gmres_outer = max(1, ceil(maxit / max(1, restart)));
            if isempty(M_pre)
                [x, flag, relres] = gmres(A, b, restart, tol, gmres_outer);
            else
                [x, flag, relres] = gmres(A, b, restart, tol, gmres_outer, M_pre);
            end
        else  % bicgstab (default)
            if isempty(M_pre)
                [x, flag, relres] = bicgstab(A, b, tol, maxit);
            else
                [x, flag, relres] = bicgstab(A, b, tol, maxit, M_pre);
            end
        end
    catch
        flag   = -1;
        relres = inf;
    end
end

function M = psf_build_preconditioner(A, precond_type)
    M = [];
    if ~strcmp(precond_type, 'jacobi'), return; end
    try
        d     = diag(A);
        d_abs = abs(d);
        d(d_abs < 1e-30 * max(d_abs(:))) = 1;  % leave near-zero rows unscaled
        inv_d = 1 ./ d;
        M = @(r) inv_d .* r;  % function handle: M\r = diag(1/d)*r
    catch
        M = [];
    end
end

function out = psf_get_str(s, field, default_val)
    out = default_val;
    if ~isstruct(s) || ~isfield(s, field), return; end
    v = s.(field);
    if ischar(v)
        out = lower(strtrim(v));
    elseif (exist('isstring', 'builtin') || exist('isstring', 'file')) && isstring(v)
        out = lower(strtrim(char(v)));
    end
end

function out = psf_get_num(s, field, default_val)
    out = default_val;
    if ~isstruct(s) || ~isfield(s, field), return; end
    v = s.(field);
    if isnumeric(v) && isscalar(v) && isfinite(v), out = double(v); end
end

function out = psf_get_bool(s, field, default_val)
    out = default_val;
    if ~isstruct(s) || ~isfield(s, field), return; end
    v = s.(field);
    if islogical(v) && isscalar(v)
        out = v;
    elseif isnumeric(v) && isscalar(v)
        out = (v ~= 0);
    end
end

% NOTE: compute_winding_inductance_matrix() moved to separate file:
%       compute_winding_inductance_matrix.m

%{
function mag_params = compute_winding_inductance_matrix(geom, MLT)
% COMPUTE_WINDING_INDUCTANCE_MATRIX  Extract Lm and Llk from PEEC geometry.
%
% Aggregates the filament-level partial inductance matrix into a winding-level
% Nw x Nw inductance matrix, then decomposes into magnetizing and leakage.
%
% Reference: Margueron, Keradec, Magot - "Analytical Calculation of Static
%            Leakage Inductances of HF Transformers Using PEEC Formulas"
%            IEEE Trans. Industry Applications, 2007.
%
% Inputs:
%   geom - PEEC geometry struct (from peec_build_geometry)
%   MLT  - Mean turn length [m] (converts per-unit-length to Henries)
%
% Outputs:
%   mag_params - struct with fields:
%     .L_winding  - Nw x Nw winding inductance matrix [H]
%     .Lm         - Magnetizing inductance referred to primary [H]
%     .Llk_pri    - Primary leakage inductance [H]
%     .Llk_sec    - Secondary leakage inductance [H] (if 2+ windings)
%     .n_eff      - Effective turns ratio from inductance matrix
%     .coupling_k - Coupling coefficient

    Nc = geom.Nc;
    Nfpc = geom.Nx * geom.Ny;  % filaments per conductor (parallel)
    L_fil = geom.L;             % Nf x Nf filament inductance matrix
    winding_map = geom.winding_map;

    % --- Step 1: Conductor-level inductance (average over parallel filaments) ---
    L_cond = zeros(Nc);
    for k = 1:Nc
        fils_k = ((k-1)*Nfpc + 1) : (k*Nfpc);
        for l = k:Nc
            fils_l = ((l-1)*Nfpc + 1) : (l*Nfpc);
            % Mean of mutual inductances between all filament pairs
            val = mean(mean(L_fil(fils_k, fils_l)));
            L_cond(k, l) = val;
            L_cond(l, k) = val;  % symmetric
        end
    end

    % --- Step 2: Winding-level inductance (sum over series turns) ---
    winding_ids = unique(winding_map);
    Nw = length(winding_ids);
    L_winding = zeros(Nw);

    for w1 = 1:Nw
        conds_w1 = find(winding_map == winding_ids(w1));
        for w2 = w1:Nw
            conds_w2 = find(winding_map == winding_ids(w2));
            val = sum(sum(L_cond(conds_w1, conds_w2)));
            L_winding(w1, w2) = val;
            L_winding(w2, w1) = val;
        end
    end

    % --- Step 3: Convert per-unit-length to actual inductance ---
    L_winding = L_winding * MLT;

    % --- Step 4: Extract Lm and Llk ---
    mag_params.L_winding = L_winding;
    mag_params.winding_ids = winding_ids;

    if Nw >= 2
        L11 = L_winding(1,1);
        L22 = L_winding(2,2);
        M   = L_winding(1,2);

        % Turns ratio from inductance (n = N1/N2)
        n_eff = sqrt(L11 / L22);

        % Coupling coefficient
        coupling_k = M / sqrt(L11 * L22);

        % Magnetizing inductance referred to primary
        Lm = M * n_eff;

        % Leakage inductances
        Llk_pri = L11 - M * n_eff;
        Llk_sec = L22 - M / n_eff;

        % Ensure non-negative (numerical precision)
        Llk_pri = max(Llk_pri, 0);
        Llk_sec = max(Llk_sec, 0);

        mag_params.Lm = Lm;
        mag_params.Llk_pri = Llk_pri;
        mag_params.Llk_sec = Llk_sec;
        mag_params.n_eff = n_eff;
        mag_params.coupling_k = coupling_k;
    else
        % Single winding: self-inductance only
        mag_params.Lm = L_winding(1,1);
        mag_params.Llk_pri = 0;
        mag_params.Llk_sec = 0;
        mag_params.n_eff = 1;
        mag_params.coupling_k = 1;
    end
end
%}
