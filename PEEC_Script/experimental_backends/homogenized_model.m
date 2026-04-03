function model = homogenized_model(wire_info, frequency_hz, options)
%HOMOGENIZED_MODEL Placeholder for phase-2 litz anisotropic model.
%
% This scaffold is intentionally non-invasive: it exposes the interface and
% metadata but does not alter the active solver path yet.

    if nargin < 3
        options = struct();
    end

    model = struct();
    model.enabled = false;
    model.status = 'scaffold_only_phase2';
    model.frequency_hz = frequency_hz;
    model.wire_info = wire_info;
    model.effective_sigma_radial = NaN;
    model.effective_sigma_axial = NaN;
    model.notes = 'Litz anisotropic homogenization is deferred to phase 2.';

    if isstruct(options) && isfield(options, 'enable_litz_homogenized_now') ...
            && logical(options.enable_litz_homogenized_now)
        model.status = 'requested_but_not_implemented';
    end
end

