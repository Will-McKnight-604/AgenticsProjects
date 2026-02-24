function clear_phase3_runtime_caches()
%CLEAR_PHASE3_RUNTIME_CACHES Clear persistent PEEC runtime caches.
%
% Used by benchmark workflows to avoid warm-cache bias between mode runs.

    clear peec_build_geometry;
    clear peec_solve_frequency;
    clear adaptive_refine;
end
