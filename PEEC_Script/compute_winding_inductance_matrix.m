function mag_params = compute_winding_inductance_matrix(geom, MLT, core_params, mu_r, gapping, options)
% COMPUTE_WINDING_INDUCTANCE_MATRIX  Extract Lm and Llk from PEEC + core data.
%
% The PEEC filament inductance matrix is a FREE-SPACE (air-core) partial
% inductance.  It uses only mu_0, NOT mu_r.  Therefore:
%
%   - Llk (leakage inductance) is correctly extracted from the PEEC L matrix,
%     because leakage flux travels through air paths in the winding window.
%     Method: Margueron, Keradec, Magot (IEEE TIA 2007).
%
%   - Lm (magnetizing inductance) CANNOT be extracted from the PEEC L matrix.
%     It must be computed from a reluctance network model:
%       Lm = N^2 / R_total
%     where R_total = R_core + sum(R_gap_i) includes core reluctance and
%     all air gap reluctances with fringing flux correction.
%
% Inputs:
%   geom        - PEEC geometry struct (from peec_build_geometry)
%   MLT         - Mean turn length [m]
%   core_params - (optional) struct with .Ae [m^2], .le [m], and .Ve [m^3]
%   mu_r        - (optional) relative permeability of core material
%   gapping     - (optional) cell array of gap structs from build_gapping_array()
%                 Each struct has fields: .type ('residual','subtractive','additive')
%                                         .length [m]
%
% Outputs:
%   mag_params - struct with fields:
%     .L_winding  - Nw x Nw air-core winding inductance matrix [H]
%     .Lm         - Magnetizing inductance (from reluctance network) [H]
%     .Llk_pri    - Primary leakage inductance (from PEEC) [H]
%     .Llk_sec    - Secondary leakage inductance (from PEEC) [H]
%     .n_eff      - Effective turns ratio (from turn counts)
%     .coupling_k - Coupling coefficient (air-core, for diagnostics)
%     .Lm_source  - 'reluctance_network' or 'unavailable'
%     .R_core     - Core reluctance [H^-1]
%     .R_gap_total- Total gap reluctance [H^-1]
%     .R_total    - Total reluctance [H^-1]

    ensure_local_subdir('corrections');

    if nargin < 6 || isempty(options)
        options = struct();
    end

    mu_0 = 4 * pi * 1e-7;

    Nc = geom.Nc;
    if ~isfield(geom, 'Nx') || ~isfield(geom, 'Ny')
        error('compute_winding_inductance_matrix: geom missing Nx/Ny (legacy geometry?)');
    end
    if ~isfield(geom, 'winding_map') || isempty(geom.winding_map)
        error('compute_winding_inductance_matrix: geom missing winding_map (single-winding mode?)');
    end
    Nfpc = geom.Nx * geom.Ny;  % filaments per conductor (parallel)
    L_fil = ensure_dense_filament_L(geom, mu_0);  % Nf x Nf filament inductance matrix (AIR-CORE)
    winding_map = geom.winding_map;

    % --- Step 1: Conductor-level inductance (average over parallel filaments) ---
    L_cond = zeros(Nc);
    for k = 1:Nc
        fils_k = ((k-1)*Nfpc + 1) : (k*Nfpc);
        for l = k:Nc
            fils_l = ((l-1)*Nfpc + 1) : (l*Nfpc);
            val = mean(mean(L_fil(fils_k, fils_l)));
            L_cond(k, l) = val;
            L_cond(l, k) = val;
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

    % --- Step 3: Count turns per winding for reluctance model ---
    N_turns = zeros(Nw, 1);
    for w = 1:Nw
        N_turns(w) = sum(winding_map == winding_ids(w));
    end

    % --- Step 4: Convert per-unit-length to actual inductance ---
    L_winding = L_winding * MLT;

    % Optional 2.5D end-turn correction (phase-3 upgrade hook).
    end_turn_meta = struct('applied', false);
    try
        [L_winding, end_turn_meta] = end_turn_2p5d(L_winding, N_turns, core_params, MLT, options);
    catch
        end_turn_meta = struct('applied', false);
    end

    mag_params.L_winding = L_winding;
    mag_params.winding_ids = winding_ids;
    mag_params.N_turns = N_turns;
    mag_params.end_turn_correction = end_turn_meta;

    % --- Step 5: Compute Lm from reluctance network model ---
    %
    % R_total = R_core + sum(R_gap_i)
    %
    % R_core = le / (mu_0 * mu_r * Ae)
    %
    % R_gap_i = l_gap_i / (mu_0 * Ae_eff_i)
    %   where Ae_eff_i = Ae * F_fringe_i  accounts for fringing flux
    %
    % Fringing factor (Partridge/classical approximation):
    %   For a rectangular cross-section gap of length lg in a core with
    %   effective area Ae, the fringing factor increases the effective area:
    %     F_fringe = 1 + (lg / sqrt(Ae)) * ln(2 * sqrt(Ae) / lg)
    %   This is the Partridge model (1942), a good balance of accuracy and
    %   simplicity. More sophisticated models (Zhang, Muehlethaler) require
    %   detailed core geometry (leg dimensions) not available here.
    %
    % Lm = N_pri^2 / R_total   (referred to primary)
    %
    has_core = nargin >= 3 && ~isempty(core_params) && ...
               isstruct(core_params) && isfield(core_params, 'Ae') && isfield(core_params, 'le') && ...
               core_params.Ae > 0 && core_params.le > 0;
    has_mu_r = nargin >= 4 && ~isempty(mu_r) && mu_r > 1;
    has_gaps = nargin >= 5 && ~isempty(gapping) && iscell(gapping) && length(gapping) > 0;

    if has_core && has_mu_r
        Ae = core_params.Ae;
        le = core_params.le;
        Npri = N_turns(1);

        % Core reluctance
        R_core = le / (mu_0 * mu_r * Ae);

        % Gap reluctances with fringing correction
        R_gap_total = 0;
        n_gaps_used = 0;
        if has_gaps
            for gi = 1:length(gapping)
                gap = gapping{gi};
                lg = gap.length;
                if lg <= 0
                    continue;
                end

                % Fringing factor (Partridge 1942 approximation)
                % F = 1 + (lg/sqrt(Ae)) * ln(2*sqrt(Ae)/lg)
                sqrt_Ae = sqrt(Ae);
                if lg < 2 * sqrt_Ae
                    F_fringe = 1 + (lg / sqrt_Ae) * log(2 * sqrt_Ae / lg);
                else
                    F_fringe = 1;  % gap too large for fringing model
                end

                Ae_eff = Ae * F_fringe;
                R_gap_i = lg / (mu_0 * Ae_eff);
                R_gap_total = R_gap_total + R_gap_i;
                n_gaps_used = n_gaps_used + 1;
            end
        end

        R_total = R_core + R_gap_total;

        % Lm = N^2 / R_total (referred to primary)
        Lm = Npri^2 / R_total;

        mag_params.Lm = Lm;
        mag_params.Lm_source = 'reluctance_network';
        mag_params.R_core = R_core;
        mag_params.R_gap_total = R_gap_total;
        mag_params.R_total = R_total;
        mag_params.n_gaps_used = n_gaps_used;
    else
        mag_params.Lm = 0;
        mag_params.Lm_source = 'unavailable';
        mag_params.R_core = 0;
        mag_params.R_gap_total = 0;
        mag_params.R_total = 0;
        mag_params.n_gaps_used = 0;
    end

    % --- Step 6: Extract leakage inductance from air-core L matrix ---
    if Nw >= 2
        L11 = L_winding(1,1);
        L22 = L_winding(2,2);
        M   = L_winding(1,2);

        % Turns ratio from actual turn counts (more reliable than sqrt(L11/L22)
        % since L matrix is air-core and doesn't reflect true inductance ratio)
        n_eff = N_turns(1) / N_turns(2);

        % Air-core coupling coefficient (diagnostic only)
        if L11 > 0 && L22 > 0
            coupling_k = M / sqrt(L11 * L22);
        else
            coupling_k = 0;
        end

        % Leakage inductance extraction (Margueron/Keradec 2007):
        % For the air-core L matrix, the decomposition gives leakage directly.
        % Llk_pri = L11 - n * M   (referred to primary)
        % Llk_sec = L22 - M / n   (referred to secondary)
        Llk_pri = L11 - n_eff * M;
        Llk_sec = L22 - M / n_eff;

        % Ensure non-negative (numerical precision)
        Llk_pri = max(Llk_pri, 0);
        Llk_sec = max(Llk_sec, 0);

        mag_params.Llk_pri = Llk_pri;
        mag_params.Llk_sec = Llk_sec;
        mag_params.n_eff = n_eff;
        mag_params.coupling_k = coupling_k;
    else
        % Single winding: no leakage decomposition
        mag_params.Llk_pri = 0;
        mag_params.Llk_sec = 0;
        mag_params.n_eff = 1;
        mag_params.coupling_k = 1;
    end
end

function ensure_local_subdir(subdir_name)
    if nargin < 1 || isempty(subdir_name)
        return;
    end
    here = fileparts(mfilename('fullpath'));
    p = fullfile(here, subdir_name);
    if exist(p, 'dir')
        addpath(p);
    end
end

function L_fil = ensure_dense_filament_L(geom, default_mu0)
    Nf = size(geom.filaments, 1);

    if isfield(geom, 'L') && ~isempty(geom.L)
        L_fil = geom.L;
    else
        filaments_core = geom.filaments(:, 1:4);
        mu0 = get_struct_numeric(geom, 'mu0', default_mu0);
        near_floor = get_struct_numeric(geom, 'near_floor', 1e-12);
        use_exact_rect = get_struct_bool(geom, 'use_exact_rect_kernel', false);
        L_fil = build_partial_inductance_matrix_vectorized_local(filaments_core, mu0, use_exact_rect, near_floor);
    end

    if isempty(L_fil) || any(size(L_fil) ~= [Nf, Nf])
        error('compute_winding_inductance_matrix: L_fil invalid (%dx%d, expected %dx%d)', ...
            size(L_fil, 1), size(L_fil, 2), Nf, Nf);
    end
end

function L = build_partial_inductance_matrix_vectorized_local(filaments_core, mu0, use_exact_rect, near_floor)
    x = filaments_core(:, 1);
    y = filaments_core(:, 2);
    dx = max(filaments_core(:, 3), 1e-12);
    dy = max(filaments_core(:, 4), 1e-12);
    Nf = numel(x);

    dx_all = bsxfun(@minus, x, x.');
    dy_all = bsxfun(@minus, y, y.');
    r2 = dx_all.^2 + dy_all.^2;

    d2 = dx.^2 + dy.^2;
    sigma2 = bsxfun(@plus, d2, d2.') / 12;
    r_eff = sqrt(r2 + sigma2 + near_floor^2);
    L = mu0 / (2 * pi) * log(1 ./ max(r_eff, near_floor));

    if use_exact_rect
        span = dx + dy;
        mean_span = 0.25 * bsxfun(@plus, span, span.');
        closeness = sqrt(r2) ./ max(mean_span, near_floor);
        corr = ones(Nf);
        mask = closeness < 1.5;
        corr(mask) = 1.0 - 0.12 * (1.5 - closeness(mask)) / 1.5;
        corr(mask) = max(0.80, min(1.0, corr(mask)));
        L = corr .* L;
    end

    req = max(0.2235 * (dx + dy), near_floor);
    L(1:Nf+1:end) = mu0 / (2 * pi) * log(1 ./ req);
    L = 0.5 * (L + L.');
end

function out = get_struct_numeric(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if isnumeric(v) && isscalar(v) && isfinite(v)
            out = double(v);
        end
    end
end

function out = get_struct_bool(s, field_name, default_val)
    out = default_val;
    if isstruct(s) && isfield(s, field_name)
        v = s.(field_name);
        if islogical(v) && isscalar(v)
            out = v;
        elseif isnumeric(v) && isscalar(v)
            out = (v ~= 0);
        end
    end
end
