function pod = build_pod_basis(snapshot_matrix, options)
%BUILD_POD_BASIS Build POD basis from state snapshots.
%
% Inputs:
%   snapshot_matrix [N x Ns] states (columns are snapshots)
%   options.rank              fixed rank (default: auto by energy)
%   options.energy_threshold  cumulative energy target in [0,1] (default 0.999)
%   options.rank_max          max rank cap (default Ns)
%
% Output struct fields:
%   .V             basis vectors [N x r]
%   .singular_vals singular values
%   .energy_kept   retained cumulative energy ratio
%   .rank          retained rank

    if nargin < 2 || ~isstruct(options)
        options = struct();
    end
    if nargin < 1 || isempty(snapshot_matrix) || ~isnumeric(snapshot_matrix)
        error('build_pod_basis: snapshot_matrix must be a non-empty numeric matrix');
    end

    [n, ns] = size(snapshot_matrix);
    if n < 1 || ns < 1
        error('build_pod_basis: invalid snapshot matrix shape');
    end

    energy_threshold = get_opt_num(options, 'energy_threshold', 0.999);
    energy_threshold = min(max(energy_threshold, 0), 1);
    rank_fixed = max(0, round(get_opt_num(options, 'rank', 0)));
    rank_max = max(1, round(get_opt_num(options, 'rank_max', ns)));
    rank_max = min(rank_max, ns);

    [U, S, ~] = svd(snapshot_matrix, 'econ');
    sval = diag(S);
    if isempty(sval)
        pod = struct('V', zeros(n, 0), 'singular_vals', [], 'energy_kept', 0, 'rank', 0);
        return;
    end

    if rank_fixed > 0
        r = min(rank_fixed, rank_max);
    else
        e = cumsum(sval .^ 2);
        e = e / max(e(end), eps);
        r = find(e >= energy_threshold, 1, 'first');
        if isempty(r)
            r = rank_max;
        end
        r = min(r, rank_max);
    end
    r = max(1, r);

    pod = struct();
    pod.V = U(:, 1:r);
    pod.singular_vals = sval;
    pod.energy_kept = sum(sval(1:r) .^ 2) / max(sum(sval .^ 2), eps);
    pod.rank = r;
end

function out = get_opt_num(options, field_name, default_val)
    out = default_val;
    if isstruct(options) && isfield(options, field_name)
        v = options.(field_name);
        if isnumeric(v) && isscalar(v) && isfinite(v)
            out = double(v);
        end
    end
end
