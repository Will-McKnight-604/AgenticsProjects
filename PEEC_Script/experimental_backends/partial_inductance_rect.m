function L = partial_inductance_rect(fil_i, fil_j, mu0, options)
%PARTIAL_INDUCTANCE_RECT Stable finite-size partial inductance kernel.
%
% Inputs:
%   fil_i, fil_j: [x y dx dy]
%   mu0: permeability of free-space
%   options: optional solve options

    if nargin < 4
        options = struct();
    end

    near_floor = get_opt(options, 'near_singular_floor_m', 1e-12);

    xi = fil_i(1); yi = fil_i(2);
    wi = max(fil_i(3), 1e-12);
    hi = max(fil_i(4), 1e-12);

    xj = fil_j(1); yj = fil_j(2);
    wj = max(fil_j(3), 1e-12);
    hj = max(fil_j(4), 1e-12);

    same_filament = abs(xi - xj) < 1e-18 && abs(yi - yj) < 1e-18 && ...
                    abs(wi - wj) < 1e-18 && abs(hi - hj) < 1e-18;

    if same_filament
        req = max(0.2235 * (wi + hi), near_floor);
        L = mu0 / (2 * pi) * log(1 / req);
        return;
    end

    r = sqrt((xi - xj)^2 + (yi - yj)^2);
    sigma2 = (wi^2 + hi^2 + wj^2 + hj^2) / 12;
    r_eff = sqrt(r^2 + sigma2 + near_floor^2);

    mean_span = 0.25 * (wi + hi + wj + hj);
    closeness = r / max(mean_span, near_floor);

    % Soft near-singular correction for closely spaced finite rectangles.
    corr = 1.0;
    if closeness < 1.5
        corr = 1.0 - 0.12 * (1.5 - closeness) / 1.5;
        corr = max(0.80, min(1.0, corr));
    end

    L = corr * (mu0 / (2 * pi)) * log(1 / max(r_eff, near_floor));
end

function out = get_opt(options, field_name, default_val)
    out = default_val;
    if isstruct(options) && isfield(options, field_name)
        v = options.(field_name);
        if isnumeric(v) && isfinite(v)
            out = v;
        end
    end
end

