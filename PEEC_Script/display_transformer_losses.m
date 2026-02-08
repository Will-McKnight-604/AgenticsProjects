%display_transformer_losses
function display_transformer_losses(results, geom, f)
% Display comprehensive transformer loss analysis
%
% Inputs:
%   results - Results structure from peec_solve_frequency
%   geom    - Geometry structure (contains winding_map)
%   f       - Frequency [Hz]

    fprintf('\n========================================\n');
    fprintf('TRANSFORMER LOSS ANALYSIS @ %.1f kHz\n', f/1e3);
    fprintf('========================================\n');

    % ========== WINDING-LEVEL SUMMARY ==========
    if isfield(results, 'winding') && ~isempty(results.winding)
        fprintf('\n--- PER-WINDING SUMMARY ---\n');
        fprintf('%-8s %8s %10s %10s %10s %10s %8s\n', ...
                'Winding', 'N_turns', 'I_rms [A]', 'V_tot [V]', 'P [W]', 'R_ac [mΩ]', 'Fr');
        fprintf('%-8s %8s %10s %10s %10s %10s %8s\n', ...
                '-------', '-------', '---------', '---------', '------', '---------', '----');

        for w = 1:length(results.winding.ids)
            winding_id = results.winding.ids(w);
            N_turns = results.winding.N_turns(w);
            I_rms = abs(results.winding.I(w));
            V_tot = abs(results.winding.V(w));
            P_w = results.winding.P(w);
            R_ac = results.winding.R_ac(w) * 1e3;
            Fr = results.winding.Fr(w);

            fprintf('%-8d %8d %10.3f %10.4f %10.4f %10.4f %8.2f\n', ...
                    winding_id, N_turns, I_rms, V_tot, P_w, R_ac, Fr);
        end

        fprintf('%-8s %8s %10s %10s %10.4f %10s %8s\n', ...
                '-------', '-------', '---------', '---------', '------', '---------', '----');
        fprintf('%-8s %8s %10s %10s %10.4f\n', ...
                'TOTAL', '', '', '', results.P_total);

        % Per-winding impedance breakdown
        fprintf('\n--- WINDING IMPEDANCE BREAKDOWN ---\n');
        fprintf('%-8s %12s %12s %12s %12s\n', ...
                'Winding', 'R_dc [mΩ]', 'R_ac [mΩ]', 'X_ac [mΩ]', 'L_ac [µH]');
        fprintf('%-8s %12s %12s %12s %12s\n', ...
                '-------', '---------', '---------', '---------', '---------');

        for w = 1:length(results.winding.ids)
            winding_id = results.winding.ids(w);
            R_dc = results.winding.R_dc(w) * 1e3;    % mOhm
            R_ac = results.winding.R_ac(w) * 1e3;    % mOhm
            X_ac = results.winding.X_ac(w) * 1e3;    % mOhm
            L_ac = results.winding.L_ac(w) * 1e6;    % µH

            fprintf('%-8d %12.4f %12.4f %12.4f %12.4f\n', ...
                    winding_id, R_dc, R_ac, X_ac, L_ac);
        end
    end

    % ========== PER-TURN/LAYER DETAILS (Optional) ==========
    if isfield(geom, 'winding_map') && ~isempty(geom.winding_map)
        winding_map = geom.winding_map;

        fprintf('\n--- PER-TURN DETAIL ---\n');
        fprintf('%-8s %8s %8s %10s %10s %8s\n', ...
                'Winding', 'Turn', 'Layer', 'P [W]', 'R_ac [mΩ]', 'Fr');
        fprintf('%-8s %8s %8s %10s %10s %8s\n', ...
                '-------', '----', '-----', '------', '---------', '----');

        for k = 1:length(winding_map.winding_id)
            w_id = winding_map.winding_id(k);
            turn = winding_map.turn_num(k);
            layer = winding_map.layer_num(k);
            P_turn = results.conductor.P(k);
            R_ac_turn = results.conductor.R_ac(k) * 1e3;
            Fr_turn = results.conductor.Fr(k);

            fprintf('%-8d %8d %8d %10.4f %10.4f %8.2f\n', ...
                    w_id, turn, layer, P_turn, R_ac_turn, Fr_turn);
        end
    end

    fprintf('\n');
    fprintf('Key metrics:\n');
    fprintf('  N_turns = Number of turns in winding\n');
    fprintf('  V_tot   = Total voltage across winding (sum of turn voltages)\n');
    fprintf('  P       = Total power loss in winding\n');
    fprintf('  R_ac    = Total AC resistance (includes skin & proximity effects)\n');
    fprintf('  Fr      = R_ac/R_dc ratio (>1 indicates AC effects)\n');
    fprintf('  L_ac    = Effective AC inductance of winding\n');
    fprintf('========================================\n\n');
end
