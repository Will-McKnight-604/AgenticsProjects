function [L_corr, meta] = end_turn_2p5d(L_winding, N_turns, core_params, MLT, options)
%END_TURN_2P5D Apply lightweight 2.5D end-turn correction.
%
% L_winding is assumed to contain the window (2D) contribution. This
% function adds a geometry-scaled correction to self and mutual terms so
% end-turn effects are represented without a full 3D solve.

    if nargin < 5
        options = struct();
    end

    L_corr = L_winding;
    meta = struct();
    meta.applied = false;
    meta.k_self = 0;
    meta.k_mutual = 0;

    if isempty(L_winding)
        return;
    end

    enable_corr = get_opt_bool(options, 'enable_end_turn_correction', false);
    if ~enable_corr
        return;
    end

    base_factor = get_opt_num(options, 'end_turn_base_factor', 0.06);
    if base_factor <= 0
        return;
    end

    bobbin_w = 0;
    bobbin_h = 0;
    if isstruct(core_params)
        if isfield(core_params, 'bobbin_w'), bobbin_w = core_params.bobbin_w; end
        if isfield(core_params, 'bobbin_h'), bobbin_h = core_params.bobbin_h; end
    end

    geom_ratio = (bobbin_w + bobbin_h) / max(MLT, 1e-12);
    geom_ratio = max(0, min(1.5, geom_ratio));

    k_self = base_factor * (1 + geom_ratio);
    k_self = max(0.01, min(0.25, k_self));
    k_mutual = max(0.005, min(0.15, 0.5 * k_self));

    Nw = size(L_winding, 1);
    for i = 1:Nw
        turn_scale = 1.0;
        if i <= numel(N_turns) && N_turns(i) > 0
            turn_scale = 1 + 0.05 * log(max(N_turns(i), 1));
            turn_scale = min(1.30, max(0.90, turn_scale));
        end
        L_corr(i, i) = L_corr(i, i) * (1 + k_self * turn_scale);
    end

    for i = 1:Nw
        for j = i+1:Nw
            Lm = L_corr(i, j) * (1 + k_mutual);
            L_corr(i, j) = Lm;
            L_corr(j, i) = Lm;
        end
    end

    meta.applied = true;
    meta.k_self = k_self;
    meta.k_mutual = k_mutual;
    meta.geom_ratio = geom_ratio;
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

