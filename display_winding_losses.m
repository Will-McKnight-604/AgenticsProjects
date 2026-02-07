%display_winding_losses

%display_winding_losses
function display_winding_losses(results, conductors, f)
% Display per-winding loss summary (PEEC-compliant)
%
% Inputs:
%   results    - Results structure from peec_solve_frequency
%   conductors - Conductor array
%   f          - Frequency [Hz]

    Nc = length(results.P_winding);

    fprintf('\n========================================\n');
    fprintf('WINDING LOSS SUMMARY @ %.1f kHz\n', f/1e3);
    fprintf('========================================\n\n');

    fprintf('%-8s %10s %10s %10s %10s %8s\n', ...
            'Winding', 'I_rms [A]', 'V [V]', 'P [W]', 'R_ac [mΩ]', 'Fr');
    fprintf('%-8s %10s %10s %10s %10s %8s\n', ...
            '-------', '---------', '------', '------', '---------', '----');

    for k = 1:Nc
        I_rms = abs(conductors(k,5));
        V_mag = abs(results.lambda(k));
        P_w   = results.P_winding(k);
        R_ac  = results.R_ac_winding(k) * 1e3;  % Convert to mOhm
        Fr    = results.Fr(k);

        fprintf('%-8d %10.3f %10.4f %10.4f %10.4f %8.2f\n', ...
                k, I_rms, V_mag, P_w, R_ac, Fr);
    end

    fprintf('%-8s %10s %10s %10.4f %10s %8s\n', ...
            '-------', '---------', '------', '------', '---------', '----');
    fprintf('%-8s %10s %10s %10.4f\n', ...
            'TOTAL', '', '', results.P_total);

    fprintf('\n');
    fprintf('Impedance breakdown:\n');
    fprintf('%-8s %12s %12s %12s\n', ...
            'Winding', 'R_ac [mΩ]', 'X_ac [mΩ]', 'L_ac [nH]');
    fprintf('%-8s %12s %12s %12s\n', ...
            '-------', '---------', '---------', '---------');

    for k = 1:Nc
        R_ac = results.R_ac_winding(k) * 1e3;    % mOhm
        X_ac = results.X_ac_winding(k) * 1e3;    % mOhm
        L_ac = results.L_ac_winding(k) * 1e9;    % nH

        fprintf('%-8d %12.4f %12.4f %12.2f\n', ...
                k, R_ac, X_ac, L_ac);
    end

    fprintf('\n');
    fprintf('Notes:\n');
    fprintf('  I_rms  = RMS current in winding\n');
    fprintf('  V      = Voltage drop across winding (from PEEC Lagrange multiplier)\n');
    fprintf('  P      = Power loss: P = 0.5*Re(V*conj(I)) = 0.5*R_ac*|I|^2\n');
    fprintf('  R_ac   = Re(Z_ac) - AC resistance (includes skin & proximity)\n');
    fprintf('  X_ac   = Im(Z_ac) - AC reactance\n');
    fprintf('  L_ac   = X_ac/(2*pi*f) - Effective AC inductance\n');
    fprintf('  Fr     = R_ac/R_dc ratio (proximity factor)\n');
    fprintf('           Fr > 1.0 indicates significant AC effects\n');
    fprintf('           Fr = 1.0 would be uniform DC current distribution\n');
    fprintf('========================================\n\n');
end
