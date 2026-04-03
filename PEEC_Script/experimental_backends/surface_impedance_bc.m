function [R_eff, meta] = surface_impedance_bc(geom, f, sigma, mu0, solve_options, R_base)
%SURFACE_IMPEDANCE_BC Apply high-frequency surface impedance correction.
%
% This is an optional diagonal correction that boosts filament resistance
% when skin depth becomes small compared to filament thickness.

    if nargin < 6 || isempty(R_base)
        R_base = geom.R;
    end
    if nargin < 5 || isempty(solve_options)
        solve_options = struct();
    end

    R_eff = R_base;
    meta = struct();
    meta.mode = 'volumetric';
    meta.mean_factor = 1.0;
    meta.max_factor = 1.0;
    meta.max_ratio = 0.0;
    meta.delta_min_m = inf;

    enable_auto = get_opt_bool(solve_options, 'enable_surface_impedance_auto', false);
    if ~enable_auto || f <= 0
        return;
    end

    omega = 2 * pi * f;
    delta = sqrt(2 / max(omega * mu0 * sigma, 1e-24));

    min_ratio = get_opt_num(solve_options, 'surface_impedance_min_ratio', 0.75);
    factor_cap = get_opt_num(solve_options, 'surface_impedance_factor_cap', 25.0);

    fil = geom.filaments;
    Nf = size(fil, 1);
    factors = ones(Nf, 1);
    max_ratio = 0;

    for i = 1:Nf
        t = max(min(fil(i, 3), fil(i, 4)), 1e-12);
        ratio = t / (2 * max(delta, 1e-18));
        max_ratio = max(max_ratio, ratio);

        if ratio < 0.25
            fac = 1 + (ratio^4) / 45;
        else
            fac = ratio * safe_coth(ratio);
        end
        factors(i) = max(1.0, min(fac, factor_cap));
    end

    meta.max_ratio = max_ratio;
    meta.delta_min_m = delta;

    if max_ratio < min_ratio
        return;
    end

    d = diag(R_base);
    d_eff = d .* factors;
    R_eff = R_base;
    for i = 1:Nf
        R_eff(i, i) = d_eff(i);
    end

    meta.mode = 'surface_impedance';
    meta.mean_factor = mean(factors);
    meta.max_factor = max(factors);
end

function y = safe_coth(x)
    if abs(x) < 1e-6
        y = 1 / max(x, 1e-12);
        return;
    end
    y = cosh(x) / sinh(x);
end

function out = get_opt_num(options, field_name, default_val)
    out = default_val;
    if isstruct(options) && isfield(options, field_name)
        v = options.(field_name);
        if isnumeric(v) && isfinite(v)
            out = v;
        end
    end
end

function out = get_opt_bool(options, field_name, default_val)
    out = default_val;
    if isstruct(options) && isfield(options, field_name)
        out = logical(options.(field_name));
    end
end

