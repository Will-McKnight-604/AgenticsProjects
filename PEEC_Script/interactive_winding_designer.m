% interactive_winding_designer.m
% Interactive GUI for designing multi-filar transformer windings
% Layout: Core (left) | Windings (center) | Visualization (right)
% Fixes: Layout-matched analysis, rect wire viz, OM wire info, supplier cascade

function interactive_winding_designer(design_spec)

    if nargin < 1
        design_spec = [];
    end

    close all;

    % Initialize global data structure
    data = struct();
    data.design_spec = design_spec;

    % Initialize OpenMagnetics API
    data.api = openmagnetics_api_interface();

    % Initialize layout calculator
    data.layout_calc = openmagnetics_winding_layout(data.api);

    % Load databases
    data.wires = data.api.get_wires();
    data.cores = data.api.get_cores();
    data.materials = data.api.get_materials();
    data.suppliers = data.api.get_suppliers();
    data.wire_options = build_wire_option_lists(data.wires);

    % Default transformer configuration
    data.n_windings = 2;
    data.winding_names = {'Primary', 'Secondary'};
    data.winding_colors = {[0.2 0.4 0.8], [0.8 0.2 0.2]};
    data.section_order = '12';
    data.om_window_cache = struct();

    % OM winding layout defaults (matches OpenMagnetics native controls)
    data.om_winding_orientation = 'contiguous';   % 'contiguous' or 'overlapping'
    data.om_section_alignment = 'inner or top';    % 'centered','inner or top','outer or bottom','spread'
    data.om_turns_alignment = {};                  % per-winding: cell array of alignment strings
    data.om_proportions = {};                      % per-winding: cell array of proportion values (0-1)

    % Default winding parameters
    data.windings(1).name = 'Primary';
    data.windings(1).n_turns = 10;
    data.windings(1).n_filar = 1;
    data.windings(1).current = 10;
    data.windings(1).phase = 0;
    data.windings(1).wire_type = 'AWG_22';
    data.windings(1).wire_shape = 'round';
    data.windings(1).voltage = 0;
    data.windings(1).wire_insulation = 'standard';

    data.windings(2).name = 'Secondary';
    data.windings(2).n_turns = 5;
    data.windings(2).n_filar = 1;
    data.windings(2).current = 5;
    data.windings(2).phase = 180;
    data.windings(2).wire_type = 'AWG_22';
    data.windings(2).wire_shape = 'round';
    data.windings(2).voltage = 0;
    data.windings(2).wire_insulation = 'standard';

    % Initialize per-winding OM alignment defaults
    data.om_turns_alignment = cell(1, data.n_windings);
    data.om_proportions = cell(1, data.n_windings);
    for ww = 1:data.n_windings
        data.om_turns_alignment{ww} = 'spread';
        data.om_proportions{ww} = 1.0 / data.n_windings;
    end

    % Default supplier & core selection
    if ~isempty(data.suppliers)
        data.selected_supplier = data.suppliers{1};
    else
        data.selected_supplier = 'TDK';
    end

    % Get cores for default supplier
    supplier_cores = data.api.get_cores_by_supplier(data.selected_supplier);
    if ~isempty(supplier_cores)
        data.selected_core = supplier_cores{1};
    else
        core_list = fieldnames(data.cores);
        if ~isempty(core_list)
            data.selected_core = core_list{1};
        else
            data.selected_core = 'None';
        end
    end

    % Default material for this supplier
    supplier_mats = data.api.get_materials_by_supplier(data.selected_supplier);
    if ~isempty(supplier_mats)
        data.selected_material = supplier_mats{1};
    else
        mat_list = fieldnames(data.materials);
        if ~isempty(mat_list)
            data.selected_material = mat_list{1};
        else
            data.selected_material = 'N87';
        end
    end

    % Geometry parameters
    [w, h, shape] = data.api.wire_to_conductor_dims(data.windings(1).wire_type);
    data.width = w;
    data.height = h;
    data.windings(1).wire_shape = shape;
    data.windings(2).wire_shape = shape;
    data.gap_layer = 0.2e-3;
    data.gap_filar = 0.05e-3;
    data.gap_winding = 0.0e-3;

    % Core air gap parameters
    data.core_gap_type = 'Ungapped';   % Ungapped, Ground, Spacer, Distributed
    data.core_gap_length = 0;          % Gap length in meters (0 = ungapped)
    data.core_num_gaps = 1;            % Number of gaps
    data.insulation_class = 'basic';
    data.insulation_standard = 'IEC 60664-1';
    data.overvoltage_category = 'OVC-II';
    data.pollution_degree = 2;
    data.cti_group = 'Group II';
    data.altitude_m = 0;
    data.wiring_technology = 'Wound';
    data.allow_margin_tape = true;
    data.allow_insulated_wire = true;
    data.tape_thickness = 0.05e-3;
    data.tape_layers = 1;
    data.tape_kv_per_mm = 120;  % user-adjustable estimate
    data.edge_margin = 0.0e-3;
    data.tiw_kv = 3.0;

    % Analysis parameters
    data.sigma = 5.8e7;
    data.mu0 = 4*pi*1e-7;
    data.f = 100e3;
    data.Nx = 6;
    data.Ny = 6;

    % Core loss model parameters
    data.core_loss_method = 'iGSE';        % 'iGSE' or 'i2GSE'
    data.steinmetz.k = [];                  % auto-filled from material DB
    data.steinmetz.alpha = [];
    data.steinmetz.beta = [];

    % Excitation model parameters
    data.excitation = struct();
    data.excitation.source = 'converter';              % 'manual' | 'converter'
    data.excitation.topology = 'two_switch_forward';   % fixed for now
    data.excitation.conduction_mode = 'ccm+dcm';       % 'ccm' | 'dcm' | 'ccm+dcm'
    data.excitation.sweep_mode = 'grid';               % 'nominal' | 'corners' | 'grid'
    data.excitation.duty_mode = 'derived';             % 'derived' | 'manual'
    data.excitation.manual_duty = 0.40;
    data.excitation.line_scales = [0.90, 1.00, 1.10];
    data.excitation.load_scales = [0.50, 0.75, 1.00];
    data.excitation.harmonic_energy_pct = 99.5;
    data.excitation.harmonic_max_order = 60;
    data.excitation.small_harmonic_pct = 1.0;
    data.excitation.small_harmonic_consecutive = 5;
    data.excitation.analysis_mode = 'hybrid';          % 'peec_only' | 'hybrid' | 'om_only'
    data.excitation.quality_preset = 'standard';       % 'fast' | 'standard' | 'high'
    data.excitation.peec_refine_top_n = 6;             % worst ranked OM points to refine in PEEC
    data.excitation.peec_harmonic_cap = 24;            % 0 = no cap
    data.excitation.prescreen_waveform_samples = 128;  % OM pre-screen waveform samples
    data.excitation.prescreen_temperature_c = 25;
    data.excitation.use_cache = true;
    data.excitation.use_import = false;
    data.excitation.profile_file = fullfile(pwd(), 'om_excitation_profile.json');
    data.excitation.cache_file = fullfile(pwd(), 'om_excitation_cache.json');

    % Apply design_spec if provided (from topology_wizard)
    if ~isempty(design_spec) && isstruct(design_spec)
        data = apply_design_spec(data, design_spec);
    end

    % Create main GUI figure
    scr = get(0, 'ScreenSize');
    fig_w = min(1800, max(1200, scr(3) - 100));
    fig_h = min(900, max(700, scr(4) - 120));
    fig_w = min(fig_w, max(900, scr(3) - 40));
    fig_h = min(fig_h, max(650, scr(4) - 80));
    fig_x = max(20, floor((scr(3) - fig_w) / 2));
    fig_y = max(20, floor((scr(4) - fig_h) / 2));
    data.fig_gui = figure('Name', 'Interactive Transformer Design Tool', ...
                          'Position', [fig_x fig_y fig_w fig_h], ...
                          'NumberTitle', 'off', ...
                          'MenuBar', 'none', ...
                          'Resize', 'on');

    data.fig_results = [];

    % Build GUI layout
    build_gui(data);

    % Default to OM view when launched from topology wizard
    if ~isempty(design_spec) && isstruct(design_spec)
        vis_ctrl = findobj(data.fig_gui, 'Tag', 'vis_mode');
        if ~isempty(vis_ctrl)
            set(vis_ctrl, 'Value', 3);  % OpenMagnetics View
        end
    end

    % Initial visualization
    update_visualization(data);
end


% ===============================================================
% APPLY DESIGN SPEC (from topology_wizard)
% ===============================================================

function data = apply_design_spec(data, spec)
    % Apply design_spec struct to pre-populate the data structure.
    % Called when interactive_winding_designer is launched from topology_wizard.

    fprintf('Applying design_spec (source: %s)\n', spec.source);

    % --- Frequency ---
    if isfield(spec, 'requirements') && isfield(spec.requirements, 'fsw_hz')
        data.f = spec.requirements.fsw_hz;
    elseif isfield(spec, 'converter') && isfield(spec.converter, 'fsw_hz')
        data.f = spec.converter.fsw_hz;
    end

    % --- Topology / Excitation ---
    if isfield(spec, 'topology') && ~isempty(spec.topology)
        data.excitation.topology = spec.topology;
    end

    % If wizard source, set excitation to converter mode
    if strcmp(spec.source, 'wizard')
        data.excitation.source = 'converter';
    end

    % --- Winding parameters from computed requirements ---
    if isfield(spec, 'requirements')
        r = spec.requirements;

        % Turns ratio -> set winding turns
        if isfield(r, 'turns_ratio') && r.turns_ratio > 0
            np_ns = r.turns_ratio;
            % Choose reasonable turn counts
            if np_ns >= 1
                ns = max(1, round(10 / np_ns));  % target ~10 secondary turns
                np = round(ns * np_ns);
            else
                np = max(1, round(10 * np_ns));
                ns = round(np / np_ns);
            end
            np = max(1, np);
            ns = max(1, ns);
            data.windings(1).n_turns = np;
            if data.n_windings >= 2
                data.windings(2).n_turns = ns;
            end
        end

        % RMS currents
        if isfield(r, 'i_pri_rms') && r.i_pri_rms > 0
            data.windings(1).current = r.i_pri_rms;
        end
        if isfield(r, 'i_sec_rms') && r.i_sec_rms > 0 && data.n_windings >= 2
            data.windings(2).current = r.i_sec_rms;
        end

        % Voltage (store converter voltages for excitation generation)
        if isfield(spec, 'converter')
            c = spec.converter;
            if isfield(c, 'vin_min') && isfield(c, 'vin_max')
                vin_nom = (c.vin_min + c.vin_max) / 2;
                if isfield(spec.requirements, 'vin_nom')
                    vin_nom = spec.requirements.vin_nom;
                end
                data.windings(1).voltage = vin_nom;
            end
            if isfield(c, 'vout') && data.n_windings >= 2
                data.windings(2).voltage = c.vout;
            end
        end
    end

    % --- Insulation ---
    if isfield(spec, 'insulation')
        ins = spec.insulation;
        if isfield(ins, 'class')
            data.insulation_class = lower(ins.class);
        end
        if isfield(ins, 'pollution_degree')
            data.pollution_degree = ins.pollution_degree;
        end
        if isfield(ins, 'overvoltage_cat')
            ovc_map = struct('I', 'OVC-I', 'II', 'OVC-II', 'III', 'OVC-III', 'IV', 'OVC-IV');
            ovc_key = strrep(ins.overvoltage_cat, ' ', '');
            if isfield(ovc_map, ovc_key)
                data.overvoltage_category = ovc_map.(ovc_key);
            end
        end
    end

    % --- Recommendation (pre-populate core/wire selection) ---
    if isfield(spec, 'recommendation') && isstruct(spec.recommendation)
        rec = spec.recommendation;
        core_applied = false;
        supplier_applied = false;
        material_applied = false;
        pri_wire_applied = false;
        sec_wire_applied = false;

        % Core shape (prefer explicit local key from recommendation payload)
        if isfield(rec, 'core_shape_local_key') && ~isempty(rec.core_shape_local_key) ...
                && isfield(data.cores, rec.core_shape_local_key)
            data.selected_core = rec.core_shape_local_key;
            core_applied = true;
            fprintf('[DESIGN_SPEC] Core applied via local key: "%s"\n', rec.core_shape_local_key);
        elseif isfield(rec, 'core_shape') && ~isempty(rec.core_shape)
            % Try to find matching core in database
            core_name = sanitize_field_name(rec.core_shape);
            if isfield(data.cores, core_name)
                data.selected_core = core_name;
                core_applied = true;
            else
                % Try exact name match
                core_list = fieldnames(data.cores);
                for k = 1:numel(core_list)
                    if strcmpi(core_list{k}, core_name)
                        data.selected_core = core_list{k};
                        core_applied = true;
                        break;
                    end
                end
                if ~core_applied
                    fprintf('[DESIGN_SPEC] Core not found in local DB: "%s" (key: %s)\n', rec.core_shape, core_name);
                end
            end
        end

        % Material (support both legacy and advisor output field names)
        rec_material = '';
        if isfield(rec, 'core_material') && ~isempty(rec.core_material)
            rec_material = rec.core_material;
        elseif isfield(rec, 'material') && ~isempty(rec.material)
            rec_material = rec.material;
        end
        if isfield(rec, 'material_local_key') && ~isempty(rec.material_local_key) ...
                && isfield(data.materials, rec.material_local_key)
            data.selected_material = rec.material_local_key;
            material_applied = true;
            fprintf('[DESIGN_SPEC] Material applied via local key: "%s"\n', rec.material_local_key);
        elseif ~isempty(rec_material)
            mat_name = sanitize_field_name(rec_material);
            if isfield(data.materials, mat_name)
                data.selected_material = mat_name;
                material_applied = true;
            else
                fprintf('[DESIGN_SPEC] Material not found in local DB: "%s" (key: %s)\n', rec_material, mat_name);
            end
        end

        % Supplier (explicit from recommendation, else inferred from material/core)
        rec_supplier = '';
        if isfield(rec, 'supplier') && ~isempty(rec.supplier)
            rec_supplier = rec.supplier;
        elseif material_applied && isfield(data.materials, data.selected_material)
            mat_tmp = data.materials.(data.selected_material);
            if isfield(mat_tmp, 'manufacturer') && ~isempty(mat_tmp.manufacturer)
                rec_supplier = mat_tmp.manufacturer;
            end
        elseif core_applied && isfield(data.cores, data.selected_core)
            core_tmp = data.cores.(data.selected_core);
            if isfield(core_tmp, 'manufacturer') && ~isempty(core_tmp.manufacturer)
                rec_supplier = core_tmp.manufacturer;
            end
        end
        if ~isempty(rec_supplier)
            for k = 1:numel(data.suppliers)
                if strcmpi(data.suppliers{k}, rec_supplier)
                    data.selected_supplier = data.suppliers{k};
                    supplier_applied = true;
                    break;
                end
            end
            if ~supplier_applied
                fprintf('[DESIGN_SPEC] Supplier not found in local DB: "%s"\n', rec_supplier);
            end
        end

        % Wire and turns from recommendation
        % Strategy: (1) try direct name match, (2) try Python-resolved match,
        % (3) show picker dialog as fallback.
        if (isfield(rec, 'primary_wire') && ~isempty(rec.primary_wire)) || ...
           (isfield(rec, 'primary_wire_local_key') && ~isempty(rec.primary_wire_local_key))
            [pri_wire_applied, data] = apply_wire_from_rec(data, rec, 'primary', 1);
        end
        if ((isfield(rec, 'secondary_wire') && ~isempty(rec.secondary_wire)) || ...
            (isfield(rec, 'secondary_wire_local_key') && ~isempty(rec.secondary_wire_local_key))) && data.n_windings >= 2
            [sec_wire_applied, data] = apply_wire_from_rec(data, rec, 'secondary', 2);
        end

        % Turns from recommendation override computed turns
        if isfield(rec, 'primary_turns') && rec.primary_turns > 0
            data.windings(1).n_turns = rec.primary_turns;
        end
        if isfield(rec, 'secondary_turns') && rec.secondary_turns > 0 && data.n_windings >= 2
            data.windings(2).n_turns = rec.secondary_turns;
        end

        % Parallels
        if isfield(rec, 'primary_parallels') && rec.primary_parallels > 0
            data.windings(1).n_filar = rec.primary_parallels;
        end
        if isfield(rec, 'secondary_parallels') && rec.secondary_parallels > 0 && data.n_windings >= 2
            data.windings(2).n_filar = rec.secondary_parallels;
        end

        % Gapping
        if isfield(rec, 'gapping') && ~isempty(rec.gapping)
            gaps = rec.gapping;
            if isstruct(gaps)
                n_gaps = numel(gaps);
                if n_gaps > 0
                    gap_type = gaps(1).type;
                    if local_contains(gap_type, 'residual')
                        data.core_gap_type = 'Ungapped';
                        data.core_gap_length = 0;
                    elseif local_contains(gap_type, 'subtractive')
                        data.core_gap_type = 'Ground';
                        if isfield(gaps(1), 'length')
                            data.core_gap_length = gaps(1).length;
                        end
                    elseif local_contains(gap_type, 'additive')
                        data.core_gap_type = 'Spacer';
                        if isfield(gaps(1), 'length')
                            data.core_gap_length = gaps(1).length;
                        end
                    end
                    data.core_num_gaps = n_gaps;
                end
            end
        end

        fprintf('[DESIGN_SPEC] Applied recommendation fields: supplier=%d core=%d material=%d wireP=%d wireS=%d turns=%d/%d\n', ...
            supplier_applied, core_applied, material_applied, pri_wire_applied, sec_wire_applied, ...
            data.windings(1).n_turns, data.windings(min(2,data.n_windings)).n_turns);
    end

    % --- MAS import: store full content for later reference ---
    if isfield(spec, 'mas_content')
        data.mas_content = spec.mas_content;
    end

    % --- Store the full design_spec for export ---
    data.design_spec = spec;

    fprintf('Design spec applied. Turns: %d/%d, f=%g Hz\n', ...
            data.windings(1).n_turns, ...
            data.windings(min(2,data.n_windings)).n_turns, ...
            data.f);
end


function name = sanitize_field_name(raw)
    % Convert raw string to the same key style as openmagnetics_api_interface.make_valid_name
    if ~ischar(raw)
        if isa(raw, 'string')
            raw = char(raw);
        else
            raw = 'Unknown';
        end
    end
    name = regexprep(raw, '[^a-zA-Z0-9_]', '_');
    if isempty(name)
        name = 'Unknown';
    end
    if ~isletter(name(1))
        name = ['W_' name];
    end
end


function [applied, data] = apply_wire_from_rec(data, rec, prefix, winding_idx)
    % Try to apply a wire from a recommendation to a winding.
    % prefix: 'primary' or 'secondary'
    % winding_idx: 1 or 2
    %
    % Strategy:
    %   1. Direct name match in local DB (sanitize advisor wire name)
    %   2. Python-resolved match (prefix_wire_matched field)
    %   3. Fallback: show wire picker dialog

    applied = false;

    % Prefer explicit local key from recommendation payload
    local_key_field = [prefix '_wire_local_key'];
    if isfield(rec, local_key_field) && ~isempty(rec.(local_key_field))
        local_key = rec.(local_key_field);
        if isfield(data.wires, local_key)
            data = set_winding_wire(data, winding_idx, local_key);
            applied = true;
            fprintf('[DESIGN_SPEC] %s wire applied via local key: "%s"\n', prefix, local_key);
            return;
        end
    end

    raw_wire = '';
    raw_field = [prefix '_wire'];
    raw_field_alt = [prefix '_wire_raw'];
    if isfield(rec, raw_field) && ~isempty(rec.(raw_field))
        raw_wire = rec.(raw_field);
    elseif isfield(rec, raw_field_alt) && ~isempty(rec.(raw_field_alt))
        raw_wire = rec.(raw_field_alt);
    end
    if isempty(raw_wire)
        fprintf('[DESIGN_SPEC] %s wire missing from recommendation payload\n', prefix);
        return;
    end

    % --- Attempt 1: direct match ---
    wire_key = sanitize_field_name(raw_wire);
    if isfield(data.wires, wire_key)
        data = set_winding_wire(data, winding_idx, wire_key);
        applied = true;
        fprintf('[DESIGN_SPEC] %s wire matched directly: "%s"\n', prefix, wire_key);
        return;
    end

    % --- Attempt 2: Python-resolved match ---
    matched_field = [prefix '_wire_matched'];
    if isfield(rec, matched_field) && ~isempty(rec.(matched_field))
        matched_key = sanitize_field_name(rec.(matched_field));
        if isfield(data.wires, matched_key)
            data = set_winding_wire(data, winding_idx, matched_key);
            applied = true;
            fprintf('[DESIGN_SPEC] %s wire auto-matched: "%s" -> "%s"\n', ...
                    prefix, raw_wire, matched_key);
            return;
        end
    end

    % --- Attempt 3: dialog fallback ---
    fprintf('[DESIGN_SPEC] %s wire not found in local DB: "%s"\n', prefix, raw_wire);

    % Determine wire type hint from wire_info if available
    type_hint = '';
    info_field = [prefix '_wire_info'];
    if isfield(rec, info_field) && isstruct(rec.(info_field))
        wi = rec.(info_field);
        if isfield(wi, 'wire_type')
            type_hint = wi.wire_type;
        end
    end

    picked = pick_wire_dialog(data, raw_wire, type_hint);
    if ~isempty(picked) && isfield(data.wires, picked)
        data = set_winding_wire(data, winding_idx, picked);
        applied = true;
        fprintf('[DESIGN_SPEC] %s wire selected by user: "%s"\n', prefix, picked);
    else
        fprintf('[DESIGN_SPEC] %s wire: user cancelled or no selection\n', prefix);
    end
end


function data = set_winding_wire(data, winding_idx, wire_key)
    % Apply a wire key to a winding index, updating conductor dimensions.
    data.windings(winding_idx).wire_type = wire_key;
    [w, h, shape] = data.api.wire_to_conductor_dims(wire_key);
    if winding_idx == 1
        data.width = w;
        data.height = h;
    end
    data.windings(winding_idx).wire_shape = shape;
end


function picked = pick_wire_dialog(data, original_name, type_hint)
    % Show a wire picker dialog when automatic matching fails.
    % Filters wire list by type_hint if available.
    % Returns the selected wire key, or '' if cancelled.

    picked = '';
    all_wires = fieldnames(data.wires);
    if isempty(all_wires)
        return;
    end

    % Filter by type hint if provided
    filtered = all_wires;
    if ~isempty(type_hint)
        type_lower = lower(type_hint);
        match_idx = false(size(all_wires));
        for k = 1:numel(all_wires)
            if ~isempty(strfind(lower(all_wires{k}), type_lower))
                match_idx(k) = true;
            end
        end
        if any(match_idx)
            filtered = all_wires(match_idx);
        end
    end

    prompt_str = sprintf('Advisor wire "%s" not found.\nSelect a %s wire from the local database:', ...
                         original_name, type_hint);
    [sel, ok] = listdlg('ListString', filtered, ...
                         'SelectionMode', 'single', ...
                         'Name', 'Wire Selection', ...
                         'ListSize', [600, 400], ...
                         'PromptString', prompt_str);

    if ok && ~isempty(sel)
        picked = filtered{sel};
    end
end


% ===============================================================
% BUILD GUI
% ===============================================================

function build_gui(data)

    fig = data.fig_gui;

    % Main title
    uicontrol('Parent', fig, 'Style', 'text', ...
              'String', 'Interactive Transformer Design Tool', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.94 0.96 0.045], ...
              'FontSize', 17, 'FontWeight', 'bold', ...
              'HorizontalAlignment', 'center', ...
              'Tag', 'main_title');

    % ========== LEFT PANEL: CORE SELECTION (with supplier cascade) ==========
    core_panel = uipanel('Parent', fig, ...
                        'Position', [0.02 0.06 0.29 0.86], ...
                        'Title', 'Core Selection (OpenMagnetics)', ...
                        'FontSize', 11, 'FontWeight', 'bold');

    % --- Supplier dropdown ---
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Supplier:', ...
              'Position', [20 530 120 20], ...
              'FontWeight', 'bold', 'HorizontalAlignment', 'left');

    supplier_list = data.suppliers;
    if isempty(supplier_list)
        supplier_list = {'TDK'};
    end
    sup_idx = find(strcmp(supplier_list, data.selected_supplier), 1);
    if isempty(sup_idx)
        if ~isempty(data.selected_supplier)
            supplier_list = [{data.selected_supplier}; supplier_list(:)];
            sup_idx = 1;
        else
            sup_idx = 1;
            data.selected_supplier = supplier_list{1};
        end
    else
        data.selected_supplier = supplier_list{sup_idx};
    end

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', supplier_list, ...
              'Position', [20 508 380 25], ...
              'Value', sup_idx, ...
              'Tag', 'supplier_dropdown', ...
              'Callback', @select_supplier);

    % --- Core Shape dropdown (filtered by supplier) ---
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Core Shape:', ...
              'Position', [20 480 120 20], ...
              'HorizontalAlignment', 'left');

    supplier_cores = data.api.get_cores_by_supplier(data.selected_supplier);
    if isempty(supplier_cores)
        supplier_cores = fieldnames(data.cores);
    end
    if isempty(supplier_cores)
        supplier_cores = {'None'};
    end
    core_idx = find(strcmp(supplier_cores, data.selected_core), 1);
    if isempty(core_idx)
        if isfield(data.cores, data.selected_core)
            supplier_cores = [{data.selected_core}; supplier_cores(:)];
            core_idx = 1;
        else
            core_idx = 1;
            data.selected_core = supplier_cores{1};
        end
    else
        data.selected_core = supplier_cores{core_idx};
    end

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', supplier_cores, ...
              'Position', [20 458 380 25], ...
              'Value', core_idx, ...
              'Tag', 'core_dropdown', ...
              'Callback', @select_core);

    % Core information display
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Core Information:', ...
              'Position', [20 430 150 20], ...
              'FontWeight', 'bold', 'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', get_core_info_text(data), ...
              'Position', [20 345 380 85], ...
              'HorizontalAlignment', 'left', ...
              'BackgroundColor', [0.95 0.95 0.95], ...
              'Tag', 'core_info');

    % --- Material dropdown (filtered by supplier) ---
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Core Material:', ...
              'Position', [20 318 120 20], ...
              'HorizontalAlignment', 'left');

    supplier_mats = data.api.get_materials_by_supplier(data.selected_supplier);
    if isempty(supplier_mats)
        supplier_mats = fieldnames(data.materials);
    end
    if isempty(supplier_mats)
        supplier_mats = {'N87'};
    end
    mat_idx = find(strcmp(supplier_mats, data.selected_material), 1);
    if isempty(mat_idx)
        if isfield(data.materials, data.selected_material)
            supplier_mats = [{data.selected_material}; supplier_mats(:)];
            mat_idx = 1;
        else
            mat_idx = 1;
            data.selected_material = supplier_mats{1};
        end
    else
        data.selected_material = supplier_mats{mat_idx};
    end

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', supplier_mats, ...
              'Position', [20 296 380 25], ...
              'Value', mat_idx, ...
              'Tag', 'material_dropdown', ...
              'Callback', @select_material);

    % Material info
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', get_material_info_text(data), ...
              'Position', [20 240 380 55], ...
              'HorizontalAlignment', 'left', ...
              'BackgroundColor', [0.95 0.95 0.95], ...
              'Tag', 'material_info');

    % --- Gap Configuration ---
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Gap Configuration:', ...
              'Position', [20 212 180 20], ...
              'FontWeight', 'bold', 'HorizontalAlignment', 'left');

    % Gap Type
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Type:', ...
              'Position', [30 190 50 20], ...
              'HorizontalAlignment', 'left');

    gap_types = {'Ungapped', 'Ground', 'Spacer', 'Distributed'};
    gap_idx = find(strcmp(gap_types, data.core_gap_type), 1);
    if isempty(gap_idx); gap_idx = 1; end

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', gap_types, ...
              'Position', [130 190 200 25], ...
              'Value', gap_idx, ...
              'Tag', 'gap_type_dropdown', ...
              'TooltipString', 'Gap type: Ground=subtractive, Spacer=additive, Distributed=multiple gaps', ...
              'Callback', @update_gap_type);

    % Gap Length
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Length:', ...
              'Position', [30 165 50 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.core_gap_length * 1e3), ...
              'Position', [130 165 80 25], ...
              'Tag', 'gap_length', ...
              'Enable', 'off', ...
              'Callback', @update_gap_length);

    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'mm', ...
              'Position', [215 165 30 20], ...
              'HorizontalAlignment', 'left', ...
              'Tag', 'gap_length_unit');

    % Number of Gaps
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'No. Gaps:', ...
              'Position', [260 165 60 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.core_num_gaps), ...
              'Position', [330 165 60 25], ...
              'Tag', 'gap_num', ...
              'Enable', 'off', ...
              'Callback', @update_num_gaps);

    % Frequency input
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Operating Frequency (kHz):', ...
              'Position', [20 132 180 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.f/1e3), ...
              'Position', [210 132 80 25], ...
              'Tag', 'frequency', ...
              'Callback', @update_frequency);

    % Insulation class dropdown
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Insulation Class:', ...
              'Position', [20 105 180 20], ...
              'HorizontalAlignment', 'left');

    insulation_list = {'functional', 'basic', 'supplementary', 'reinforced'};
    ins_idx = find(strcmp(insulation_list, data.insulation_class), 1);
    if isempty(ins_idx); ins_idx = 2; end

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', insulation_list, ...
              'Position', [210 105 180 25], ...
              'Value', ins_idx, ...
              'Tag', 'insulation_class', ...
              'Callback', @update_insulation_class);

    % Tape thickness + layers
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Tape Thickness (mm):', ...
              'Position', [20 78 180 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.tape_thickness * 1e3), ...
              'Position', [210 78 60 25], ...
              'Tag', 'tape_thickness', ...
              'Callback', @update_tape_thickness);

    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Layers:', ...
              'Position', [280 78 60 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.tape_layers), ...
              'Position', [340 78 60 25], ...
              'Tag', 'tape_layers', ...
              'Callback', @update_tape_layers);

    % Tape strength + TIW rating
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Tape Strength (kV/mm):', ...
              'Position', [20 51 180 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.tape_kv_per_mm), ...
              'Position', [210 51 60 25], ...
              'Tag', 'tape_strength', ...
              'Callback', @update_tape_strength);

    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'TIW kV:', ...
              'Position', [280 51 60 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.tiw_kv), ...
              'Position', [340 51 60 25], ...
              'Tag', 'tiw_kv', ...
              'Callback', @update_tiw_kv);

    % Edge margin (mm)
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Edge Margin (mm):', ...
              'Position', [20 24 180 20], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', num2str(data.edge_margin * 1e3), ...
              'Position', [210 24 80 25], ...
              'Tag', 'edge_margin', ...
              'Callback', @update_edge_margin);

    % --- Core Loss Model ---
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Core Loss Model:', ...
              'Position', [20 35 180 16], ...
              'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
              'FontSize', 8);

    % Try to auto-fill Steinmetz params from selected material
    try
        [sk, sa, sb] = data.api.get_steinmetz_coefficients(data.selected_material, data.f);
        if ~isempty(sk)
            data.steinmetz.k = sk;
            data.steinmetz.alpha = sa;
            data.steinmetz.beta = sb;
        end
    catch
    end

    steinmetz_k_str = '';
    steinmetz_a_str = '';
    steinmetz_b_str = '';
    if ~isempty(data.steinmetz.k)
        steinmetz_k_str = num2str(data.steinmetz.k, '%.4g');
        steinmetz_a_str = num2str(data.steinmetz.alpha, '%.4g');
        steinmetz_b_str = num2str(data.steinmetz.beta, '%.4g');
    end

    % Core loss method dropdown
    loss_methods = {'iGSE', 'i2GSE'};
    loss_idx = find(strcmp(loss_methods, data.core_loss_method), 1);
    if isempty(loss_idx); loss_idx = 1; end

    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'Method:', ...
              'Position', [20 14 50 18], ...
              'HorizontalAlignment', 'left', 'FontSize', 8);

    uicontrol('Parent', core_panel, 'Style', 'popupmenu', ...
              'String', loss_methods, ...
              'Position', [75 14 70 22], ...
              'Value', loss_idx, ...
              'Tag', 'core_loss_method', ...
              'FontSize', 8, ...
              'Callback', @update_core_loss_method);

    % Steinmetz k, alpha, beta fields
    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'k:', ...
              'Position', [150 14 15 18], ...
              'HorizontalAlignment', 'right', 'FontSize', 8);

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', steinmetz_k_str, ...
              'Position', [168 14 62 22], ...
              'Tag', 'steinmetz_k', ...
              'FontSize', 8, ...
              'Callback', @update_steinmetz_k);

    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'a:', ...
              'Position', [235 14 15 18], ...
              'HorizontalAlignment', 'right', 'FontSize', 8);

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', steinmetz_a_str, ...
              'Position', [253 14 45 22], ...
              'Tag', 'steinmetz_alpha', ...
              'FontSize', 8, ...
              'Callback', @update_steinmetz_alpha);

    uicontrol('Parent', core_panel, 'Style', 'text', ...
              'String', 'b:', ...
              'Position', [303 14 15 18], ...
              'HorizontalAlignment', 'right', 'FontSize', 8);

    uicontrol('Parent', core_panel, 'Style', 'edit', ...
              'String', steinmetz_b_str, ...
              'Position', [321 14 45 22], ...
              'Tag', 'steinmetz_beta', ...
              'FontSize', 8, ...
              'Callback', @update_steinmetz_beta);

    % ========== CENTER PANEL: WINDING CONFIGURATION ==========
    winding_panel = uipanel('Parent', fig, ...
                           'Position', [0.33 0.10 0.34 0.82], ...
                           'Title', 'Winding Configuration', ...
                           'FontSize', 11, 'FontWeight', 'bold');

    % Tab buttons
    tab_group = uibuttongroup('Parent', winding_panel, ...
                              'Position', [0.02 0.90 0.96 0.08], ...
                              'BorderType', 'none');

    for w = 1:data.n_windings
        uicontrol('Parent', tab_group, 'Style', 'togglebutton', ...
                  'String', data.windings(w).name, ...
                  'Position', [10 + (w-1)*130, 6, 120, 28], ...
                  'FontSize', 10, ...
                  'Tag', sprintf('tab%d', w), ...
                  'Callback', {@switch_tab, w});
    end
    set(findobj(tab_group, 'Tag', 'tab1'), 'Value', 1);

    % Content panels for each winding
    for w = 1:data.n_windings
        panel = uipanel('Parent', winding_panel, ...
                        'Position', [0.02 0.02 0.96 0.86], ...
                        'Visible', 'off', ...
                        'Tag', sprintf('content%d', w));

        % Winding name header
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', sprintf('%s Winding', data.windings(w).name), ...
                  'Position', [20 480 300 25], ...
                  'FontSize', 12, 'FontWeight', 'bold', ...
                  'HorizontalAlignment', 'left');

        % --- Wire Type dropdown ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Wire Type:', ...
                  'Position', [20 430 100 20], ...
                  'FontWeight', 'bold', 'HorizontalAlignment', 'left');

        wire_list = fieldnames(data.wires);
        if isempty(wire_list); wire_list = {'AWG_22'}; end
        wire_idx = find(strcmp(wire_list, data.windings(w).wire_type), 1);
        if isempty(wire_idx); wire_idx = 1; end

        uicontrol('Parent', panel, 'Style', 'popupmenu', ...
                  'String', wire_list, ...
                  'Position', [130 430 230 25], ...
                  'Value', wire_idx, ...
                  'Tag', sprintf('wire_type_%d', w), ...
                  'Callback', {@select_wire, w});

        % --- Wire Standard dropdown ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Standard:', ...
                  'Position', [20 395 100 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'popupmenu', ...
                  'String', data.wire_options.standards, ...
                  'Position', [130 395 230 25], ...
                  'Tag', sprintf('wire_std_%d', w), ...
                  'Callback', {@select_wire_attribute, w, 'standard'});

        % --- Conductor diameter dropdown ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Cond. diameter:', ...
                  'Position', [20 360 120 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'popupmenu', ...
                  'String', data.wire_options.cond_diameters, ...
                  'Position', [130 360 230 25], ...
                  'Tag', sprintf('wire_diam_%d', w), ...
                  'Callback', {@select_wire_attribute, w, 'cond_diameter'});

        % --- Coating dropdown ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Coating:', ...
                  'Position', [20 325 100 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'popupmenu', ...
                  'String', data.wire_options.coatings, ...
                  'Position', [130 325 230 25], ...
                  'Tag', sprintf('wire_coat_%d', w), ...
                  'Callback', {@select_wire_attribute, w, 'coating'});

        % --- Wire insulation type ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Wire Insulation:', ...
                  'Position', [20 290 120 20], ...
                  'HorizontalAlignment', 'left');

        insulation_opts = {'Standard', 'TIW'};
        if isfield(data.windings(w), 'wire_insulation') && strcmpi(data.windings(w).wire_insulation, 'tiw')
            ins_val = 2;
        else
            ins_val = 1;
        end

        uicontrol('Parent', panel, 'Style', 'popupmenu', ...
                  'String', insulation_opts, ...
                  'Position', [130 290 230 25], ...
                  'Value', ins_val, ...
                  'Tag', sprintf('wire_insulation_%d', w), ...
                  'Callback', {@update_wire_insulation, w});

        % --- No. Turns ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'No. Turns:', ...
                  'Position', [20 255 120 20], ...
                  'FontWeight', 'bold', 'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                  'String', '-', ...
                  'Position', [180 255 30 25], ...
                  'FontSize', 14, ...
                  'Callback', {@adjust_turns, w, -1});

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).n_turns), ...
                  'Position', [215 255 60 25], ...
                  'FontSize', 11, 'HorizontalAlignment', 'center', ...
                  'Tag', sprintf('turns_val_%d', w), ...
                  'Callback', {@update_turns_manual, w});

        uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                  'String', '+', ...
                  'Position', [280 255 30 25], ...
                  'FontSize', 14, ...
                  'Callback', {@adjust_turns, w, 1});

        % --- No. Parallels (Filar) ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'No. Parallels:', ...
                  'Position', [20 220 120 20], ...
                  'FontWeight', 'bold', 'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                  'String', '-', ...
                  'Position', [180 220 30 25], ...
                  'FontSize', 14, ...
                  'Callback', {@adjust_filar, w, -1});

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).n_filar), ...
                  'Position', [215 220 60 25], ...
                  'FontSize', 11, 'HorizontalAlignment', 'center', ...
                  'Tag', sprintf('filar_val_%d', w), ...
                  'Callback', {@update_filar_manual, w});

        uicontrol('Parent', panel, 'Style', 'pushbutton', ...
                  'String', '+', ...
                  'Position', [280 220 30 25], ...
                  'FontSize', 14, ...
                  'Callback', {@adjust_filar, w, 1});

        % Filar type label
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', get_filar_name(data.windings(w).n_filar), ...
                  'Position', [305 220 80 25], ...
                  'FontSize', 9, 'FontWeight', 'bold', ...
                  'HorizontalAlignment', 'left', ...
                  'ForegroundColor', [0.2 0.6 0.2], ...
                  'Tag', sprintf('filar_name_%d', w));

        % --- RMS Current ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'RMS Current (A):', ...
                  'Position', [20 180 150 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).current), ...
                  'Position', [180 180 80 25], ...
                  'Tag', sprintf('current_%d', w), ...
                  'Callback', {@update_current, w});

        % --- Voltage ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Voltage (V):', ...
                  'Position', [20 150 150 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).voltage), ...
                  'Position', [180 150 80 25], ...
                  'Tag', sprintf('voltage_%d', w), ...
                  'Callback', {@update_voltage, w});

        % --- Phase ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Phase (degrees):', ...
                  'Position', [20 120 150 20], ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'edit', ...
                  'String', num2str(data.windings(w).phase), ...
                  'Position', [180 120 80 25], ...
                  'Tag', sprintf('phase_%d', w), ...
                  'Callback', {@update_phase, w});

        % --- Configuration Summary ---
        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', 'Configuration Summary:', ...
                  'Position', [20 90 300 20], ...
                  'FontSize', 10, 'FontWeight', 'bold', ...
                  'HorizontalAlignment', 'left');

        uicontrol('Parent', panel, 'Style', 'text', ...
                  'String', get_winding_summary(data, w), ...
                  'Position', [20 5 360 80], ...
                  'HorizontalAlignment', 'left', ...
                  'VerticalAlignment', 'top', ...
                  'Tag', sprintf('summary_%d', w));
    end

    % Show first panel
    set(findobj(winding_panel, 'Tag', 'content1'), 'Visible', 'on');

    % Initial wire info update
    for w = 1:data.n_windings
        update_wire_info_fields(fig, data, w);
    end

    % ========== RIGHT PANEL: VISUALIZATION ==========
    vis_panel = uipanel('Parent', fig, ...
                        'Position', [0.69 0.10 0.29 0.82], ...
                        'Title', 'Winding Layout in Core Window', ...
                        'FontSize', 11, 'FontWeight', 'bold');

    uicontrol('Parent', vis_panel, 'Style', 'text', ...
              'String', 'View Mode:', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.92 0.18 0.05], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', vis_panel, 'Style', 'popupmenu', ...
              'String', {'Schematic (2D)', 'Core Window Fit', 'OpenMagnetics View', 'Loss Analysis'}, ...
              'Units', 'normalized', ...
              'Position', [0.20 0.92 0.40 0.06], ...
              'Value', 2, ...
              'Tag', 'vis_mode', ...
              'Callback', @change_vis_mode);

    uicontrol('Parent', vis_panel, 'Style', 'pushbutton', ...
              'String', 'Winding Options...', ...
              'Units', 'normalized', ...
              'Position', [0.62 0.92 0.36 0.06], ...
              'FontSize', 9, ...
              'Tag', 'btn_winding_options', ...
              'Callback', @cb_open_winding_options);

    uicontrol('Parent', vis_panel, 'Style', 'text', ...
              'String', 'Section Interl. Order:', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.84 0.30 0.05], ...
              'HorizontalAlignment', 'left');

    uicontrol('Parent', vis_panel, 'Style', 'edit', ...
              'String', data.section_order, ...
              'Units', 'normalized', ...
              'Position', [0.32 0.84 0.24 0.06], ...
              'Tag', 'section_order', ...
              'Callback', @update_section_order);

    uicontrol('Parent', vis_panel, 'Style', 'text', ...
              'String', '', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.74 0.96 0.08], ...
              'HorizontalAlignment', 'left', ...
              'BackgroundColor', get(vis_panel, 'BackgroundColor'), ...
              'FontSize', 8, ...
              'Tag', 'vis_metrics');

    axes('Parent', vis_panel, ...
         'Position', [0.08 0.08 0.88 0.60], ...
         'Tag', 'vis_axes');

    uicontrol('Parent', vis_panel, 'Style', 'text', ...
              'String', '', ...
              'Units', 'normalized', ...
              'Position', [0.02 0.01 0.96 0.06], ...
              'HorizontalAlignment', 'left', ...
              'BackgroundColor', [0.95 0.95 1.0], ...
              'FontSize', 8, ...
              'Tag', 'vis_info');

    % ========== BOTTOM BUTTONS ==========
    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
              'String', 'Run Analysis', ...
              'Units', 'normalized', ...
              'Position', [0.68 0.03 0.11 0.05], ...
              'FontSize', 12, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.2 0.7 0.3], ...
              'ForegroundColor', 'w', ...
              'Callback', @run_analysis);

    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
              'String', 'Reset to Defaults', ...
              'Units', 'normalized', ...
              'Position', [0.80 0.03 0.11 0.05], ...
              'FontSize', 11, ...
              'Callback', @reset_defaults);

    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
              'String', 'Export MAS', ...
              'Units', 'normalized', ...
              'Position', [0.92 0.03 0.07 0.05], ...
              'FontSize', 10, ...
              'BackgroundColor', [0.5 0.3 0.7], ...
              'ForegroundColor', 'w', ...
              'TooltipString', 'Export current design as MAS JSON file', ...
              'Callback', @export_mas_file);

    guidata(fig, data);
end

% ===============================================================
% WIRE INFO FIELD UPDATER (Issue #3)
% ===============================================================

function update_wire_info_fields(fig, data, w)
    wire_type = data.windings(w).wire_type;
    wire = data.api.get_wire_info(wire_type);

    % Keep wire type dropdown in sync
    wire_dd = findobj(fig, 'Tag', sprintf('wire_type_%d', w));
    set_popup_value(wire_dd, wire_type);

    % Standard dropdown
    if isfield(wire, 'standard')
        set_popup_value(findobj(fig, 'Tag', sprintf('wire_std_%d', w)), wire.standard);
    end

    % Conductor diameter dropdown
    if isfield(wire, 'cond_diameter')
        set_popup_value(findobj(fig, 'Tag', sprintf('wire_diam_%d', w)), wire.cond_diameter);
    end

    % Coating dropdown
    if isfield(wire, 'coating')
        set_popup_value(findobj(fig, 'Tag', sprintf('wire_coat_%d', w)), wire.coating);
    end

    % Wire insulation dropdown
    ins_dd = findobj(fig, 'Tag', sprintf('wire_insulation_%d', w));
    if ~isempty(ins_dd) && ishandle(ins_dd)
        if isfield(data.windings(w), 'wire_insulation') && strcmpi(data.windings(w).wire_insulation, 'tiw')
            set(ins_dd, 'Value', 2);
        else
            set(ins_dd, 'Value', 1);
        end
    end
end

% ===============================================================
% INFO TEXT GENERATORS
% ===============================================================

function str = get_core_info_text(data)
    if strcmp(data.selected_core, 'None')
        str = 'No core selected';
        return;
    end

    core = data.cores.(data.selected_core);
    str = sprintf('Shape: %s\n', core.shape);
    if isfield(core, 'manufacturer')
        str = [str sprintf('Manufacturer: %s\n', core.manufacturer)];
    end
    if isfield(core, 'material')
        str = [str sprintf('Material: %s\n', core.material)];
    end
    if isfield(core, 'Ae')
        str = [str sprintf('Ae: %.1f mm^2\n', core.Ae*1e6)];
    end
    if isfield(core, 'le')
        str = [str sprintf('le: %.1f mm\n', core.le*1e3)];
    end
    if isfield(core, 'Ve')
        str = [str sprintf('Ve: %.1f mm^3\n', core.Ve*1e9)];
    end
    if isfield(core, 'bobbin')
        str = [str sprintf('Bobbin: %.1f x %.1f mm', ...
            core.bobbin.width*1e3, core.bobbin.height*1e3)];
    end
end

function str = get_material_info_text(data)
    mat_name = data.selected_material;
    if ~isfield(data.materials, mat_name)
        str = 'No material data';
        return;
    end

    mat = data.materials.(mat_name);
    str = sprintf('Material: %s\n', mat_name);
    if isfield(mat, 'manufacturer')
        str = [str sprintf('Mfg: %s\n', mat.manufacturer)];
    end
    if isfield(mat, 'mu_initial')
        str = [str sprintf('ui: %d\n', mat.mu_initial)];
    end
    if isfield(mat, 'Bsat')
        str = [str sprintf('Bsat: %.2f T\n', mat.Bsat)];
    end
end

function str = get_winding_summary(data, winding)
    n_cond = data.windings(winding).n_turns * data.windings(winding).n_filar;
    I_per_strand = data.windings(winding).current / data.windings(winding).n_filar;

    wire_type = data.windings(winding).wire_type;
    wire = data.api.get_wire_info(wire_type);
    [w, h, shape] = data.api.wire_to_conductor_dims(wire_type);

    if isfield(wire, 'area') && wire.area > 0
        J_eff = I_per_strand / (wire.area * 1e6);  % A/mm^2
        j_str = sprintf('Eff. current density: %.2f A/mm^2', J_eff);
    else
        j_str = 'Eff. current density: n/a';
    end

    iso_str = get_isolation_summary(data, winding);

    str = sprintf('Total conductors: %d\nCurrent per strand: %.2f A\nConductor size: %.3f x %.3f mm\nShape: %s | %s\n%s', ...
        n_cond, I_per_strand, w*1e3, h*1e3, shape, iso_str, j_str);
end

function iso_str = get_isolation_summary(data, winding)
    if winding >= data.n_windings
        iso_str = 'Iso: n/a';
        return;
    end

    req = compute_insulation_requirements(data, winding, winding+1);

    tape_layers = 0;
    tape_gap_mm = 0;
    if isfield(data, 'tape_thickness') && isfield(data, 'tape_layers')
        tape_layers = max(0, data.tape_layers);
        tape_gap_mm = data.tape_thickness * tape_layers * 1e3;
    end

    edge_margin_mm = 0;
    if isfield(data, 'edge_margin')
        edge_margin_mm = max(0, data.edge_margin) * 1e3;
    end

    req_layers = req.tape_layers_required;
    req_gap_mm = req.tape_thickness * req_layers * 1e3;
    req_edge_mm = req.margin_distance * 0.5 * 1e3;

    tape_ok = (req_layers == 0) || (tape_layers >= req_layers);
    edge_ok = (req.margin_distance <= 0) || (edge_margin_mm >= req_edge_mm);

    status = 'OK';
    if ~(tape_ok && edge_ok)
        status = 'Need';
    end

    iso_str = sprintf(['Iso req: dV=%.0fV %s | withstand %.0fV | ' ...
                       'tape %dL (%.2fmm), edge >= %.2fmm\n' ...
                       'Iso act: tape %dL (%.2fmm), edge %.2fmm [%s]'], ...
                       req.Vdiff, req.insulation_class, req.withstand_voltage, ...
                       req_layers, req_gap_mm, req_edge_mm, ...
                       tape_layers, tape_gap_mm, edge_margin_mm, status);
end

function iso_str = get_isolation_summary_legacy(data, winding)
    if winding >= data.n_windings
        iso_str = 'Iso: n/a';
        return;
    end

    V1 = 0;
    V2 = 0;
    if isfield(data.windings(winding), 'voltage')
        V1 = data.windings(winding).voltage;
    end
    if isfield(data.windings(winding+1), 'voltage')
        V2 = data.windings(winding+1).voltage;
    end
    Vdiff = abs(V1 - V2);

    class = data.insulation_class;
    req_mult = get_insulation_multiplier(class);
    req_v = Vdiff * req_mult;

    tape_gap_mm = 0;
    tape_layers = 0;
    if isfield(data, 'tape_thickness') && isfield(data, 'tape_layers')
        tape_layers = max(0, data.tape_layers);
        tape_gap_mm = data.tape_thickness * tape_layers * 1e3;
    end

    layer_v = get_tape_layer_breakdown_v(data);
    tape_v = tape_layers * layer_v;

    tiw_v = 0;
    if is_tiw_used(data, winding, winding+1) && isfield(data, 'tiw_kv')
        tiw_v = data.tiw_kv * 1e3;
    end

    available_v = max(tape_v, tiw_v);
    if layer_v <= 0 && tiw_v <= 0
        avail_str = 'avail=n/a';
    else
        status = 'OK';
        if available_v < req_v
            status = 'Need';
        end
        avail_str = sprintf('avail=%.0fV %s', available_v, status);
    end

    iso_str = sprintf('Iso: ΔV=%.0fV %s, tape %dL (%.2fmm), %s', ...
        Vdiff, class, tape_layers, tape_gap_mm, avail_str);
end

function mult = get_insulation_multiplier(class)
    if ~ischar(class)
        mult = 1.0;
        return;
    end
    switch lower(class)
        case 'functional'
            mult = 1.0;
        case 'basic'
            mult = 1.0;
        case 'supplementary'
            mult = 2.0;
        case 'reinforced'
            mult = 3.0;
        otherwise
            mult = 1.0;
    end
end

function req = compute_insulation_requirements(data, winding_a, winding_b)
    req = struct();
    req.Vdiff = 0;
    req.withstand_voltage = 0;
    req.clearance = 0;
    req.creepage = 0;
    req.margin_distance = 0;
    req.distance_through_insulation = 0;
    req.tape_layers_required = 0;
    req.tape_thickness = 0;
    req.insulation_class = data.insulation_class;

    V1 = 0;
    V2 = 0;
    if winding_a >= 1 && winding_a <= data.n_windings && isfield(data.windings(winding_a), 'voltage')
        V1 = data.windings(winding_a).voltage;
    end
    if winding_b >= 1 && winding_b <= data.n_windings && isfield(data.windings(winding_b), 'voltage')
        V2 = data.windings(winding_b).voltage;
    end
    Vdiff = abs(V1 - V2);
    req.Vdiff = Vdiff;

    std_name = 'IEC 60664-1';
    if isfield(data, 'insulation_standard')
        std_name = data.insulation_standard;
    end

    if local_contains(std_name, '60664')
        req = iec60664_requirements(data, Vdiff, data.insulation_class);
    else
        req.insulation_class = data.insulation_class;
        req.Vdiff = Vdiff;
        req.withstand_voltage = Vdiff * get_insulation_multiplier(data.insulation_class);
        req.clearance = 0;
        req.creepage = 0;
        req.margin_distance = 0;
        req.distance_through_insulation = 0;
    end

    tape_thickness = 0;
    if isfield(data, 'tape_thickness')
        tape_thickness = max(0, data.tape_thickness);
    end
    req.tape_thickness = tape_thickness;

    layer_v = get_tape_layer_breakdown_v(data);
    req_layers = 0;
    if tape_thickness > 0 && layer_v > 0 && req.withstand_voltage > 0
        req_layers = max(1, ceil(req.withstand_voltage / layer_v));
    end

    if req.distance_through_insulation > 0 && tape_thickness > 0
        req_layers = max(req_layers, ceil(req.distance_through_insulation / tape_thickness));
    end

    if is_tiw_used(data, winding_a, winding_b) && isfield(data, 'allow_insulated_wire') && data.allow_insulated_wire
        req_layers = max(1, req_layers);
        req.margin_distance = 0;
    end

    req.tape_layers_required = req_layers;
end

function req = iec60664_requirements(data, Vdiff, insulation_class)
    req = struct();
    req.Vdiff = Vdiff;
    req.insulation_class = insulation_class;
    req.withstand_voltage = 0;
    req.clearance = 0;
    req.creepage = 0;
    req.margin_distance = 0;
    req.distance_through_insulation = 0;
    req.tape_layers_required = 0;
    req.tape_thickness = 0;

    tables = iec60664_tables();
    if isempty(tables)
        req.withstand_voltage = Vdiff * get_insulation_multiplier(insulation_class);
        return;
    end

    Vrms = abs(Vdiff);
    Vpeak = Vrms * sqrt(2);
    freq = data.f;
    altitude = 0;
    if isfield(data, 'altitude_m')
        altitude = max(0, data.altitude_m);
    end

    pd = 2;
    if isfield(data, 'pollution_degree')
        pd = data.pollution_degree;
    end
    pd_key = sprintf('P%d', max(1, min(3, round(pd))));

    ovc = 'OVC-II';
    if isfield(data, 'overvoltage_category')
        ovc = data.overvoltage_category;
    end
    ovc_key = strrep(upper(ovc), '-', '_');

    cti = 'Group II';
    if isfield(data, 'cti_group')
        cti = data.cti_group;
    end
    cti_key = strrep(cti, ' ', '_');

    wiring = 'Wound';
    if isfield(data, 'wiring_technology')
        wiring = data.wiring_technology;
    end
    wiring_key = wiring;

    is_reinforced = any(strcmpi(insulation_class, {'reinforced', 'double'}));

    rated_impulse = iec60664_get_rated_impulse_withstand_voltage(tables, ovc_key, Vrms, is_reinforced);
    req.withstand_voltage = iec60664_calculate_withstand_voltage(Vrms, Vpeak, rated_impulse, is_reinforced);

    clearance_transient = iec60664_get_clearance_f2(tables, pd_key, rated_impulse);
    steady_peak = Vpeak;
    if is_reinforced
        steady_peak = steady_peak * 1.6;
    end
    clearance_steady = iec60664_get_clearance_f8(tables, steady_peak);
    if freq > 30000
        clearance_steady = iec60664_get_clearance_over_30kHz(tables, steady_peak, freq, clearance_steady);
    end
    clearance = max(clearance_transient, clearance_steady);
    if altitude > 2000
        clearance = clearance * iec60664_get_altitude_factor(tables, altitude);
    end
    req.clearance = clearance;

    rated_insulation = iec60664_get_rated_insulation_voltage(tables, Vrms);
    voltage_rms = max(Vrms, rated_insulation);
    creepage = iec60664_get_creepage_f5(tables, wiring_key, pd_key, cti_key, voltage_rms);
    if freq > 30000
        creepage_over = iec60664_get_creepage_over_30kHz(tables, Vpeak, freq);
        switch pd_key
            case 'P2'
                creepage_over = creepage_over * 1.2;
            case 'P3'
                creepage_over = creepage_over * 1.4;
        end
        creepage = max(creepage, creepage_over);
    end
    if is_reinforced
        creepage = creepage * 2;
    end
    creepage = max(creepage, clearance);
    req.creepage = creepage;

    req.margin_distance = max(clearance, creepage);

    if freq > 30000
        req.distance_through_insulation = iec60664_distance_through_insulation_over_30kHz(Vrms);
    end
end

function tables = iec60664_tables()
    persistent cache
    if ~isempty(cache)
        tables = cache;
        return;
    end

    tables = struct();

    base_paths = {};
    try
        here = fileparts(mfilename('fullpath'));
        base_paths{end+1} = fullfile(here, 'insulation_standards'); %#ok<AGROW>
    catch
    end
    base_paths{end+1} = 'C:\Users\Will\Downloads\MKF-main\src\data\insulation_standards';

    path_60664_1 = '';
    path_60664_4 = '';
    for i = 1:numel(base_paths)
        p1 = fullfile(base_paths{i}, 'IEC_60664-1.json');
        p4 = fullfile(base_paths{i}, 'IEC_60664-4.json');
        if exist(p1, 'file')
            path_60664_1 = p1;
        end
        if exist(p4, 'file')
            path_60664_4 = p4;
        end
    end

    if isempty(path_60664_1)
        tables = [];
        return;
    end

    data1 = jsondecode(fileread(path_60664_1));
    tables.part1 = data1;

    if ~isempty(path_60664_4) && exist(path_60664_4, 'file')
        data4 = jsondecode(fileread(path_60664_4));
        tables.part4 = data4;
    else
        tables.part4 = struct();
    end

    cache = tables;
end

function rated = iec60664_get_rated_impulse_withstand_voltage(tables, ovc_key, rated_voltage, is_reinforced)
    ovc_field = pick_fieldname(tables.part1.F_1, ovc_key);
    if isempty(ovc_field)
        rated = rated_voltage;
        return;
    end
    table = ensure_table_array(tables.part1.F_1.(ovc_field));
    rated = lookup_step(table, rated_voltage);
    if is_reinforced
        idx = find(table(:,1) >= rated_voltage, 1);
        if ~isempty(idx) && idx < size(table, 1)
            rated = table(idx+1, 2);
        else
            rated = rated * 1.6;
        end
    end
end

function clearance = iec60664_get_clearance_f2(tables, pd_key, rated_impulse)
    pd_field = pick_fieldname(tables.part1.F_2.InhomogeneusField, pd_key);
    if isempty(pd_field)
        clearance = 0;
        return;
    end
    table = ensure_table_array(tables.part1.F_2.InhomogeneusField.(pd_field));
    clearance = lookup_step(table, rated_impulse);
end

function clearance = iec60664_get_clearance_f8(tables, rated_peak)
    table = ensure_table_array(tables.part1.F_8.InhomogeneusField);
    clearance = lookup_step(table, rated_peak);
end

function rated = iec60664_get_rated_insulation_voltage(tables, main_supply)
    table = ensure_table_array(tables.part1.F_3);
    rated = lookup_step(table, main_supply);
end

function creepage = iec60664_get_creepage_f5(tables, wiring_key, pd_key, cti_key, voltage_rms)
    wiring_field = pick_fieldname(tables.part1.F_5, wiring_key);
    if isempty(wiring_field)
        wiring_field = pick_fieldname(tables.part1.F_5, 'Wound');
    end
    if isempty(wiring_field)
        creepage = 0;
        return;
    end
    pd_field = pick_fieldname(tables.part1.F_5.(wiring_field), pd_key);
    if isempty(pd_field)
        creepage = 0;
        return;
    end
    cti_field = pick_fieldname(tables.part1.F_5.(wiring_field).(pd_field), cti_key);
    if isempty(cti_field)
        creepage = 0;
        return;
    end
    table = ensure_table_array(tables.part1.F_5.(wiring_field).(pd_field).(cti_field));
    creepage = lookup_step(table, voltage_rms);
end

function factor = iec60664_get_altitude_factor(tables, altitude)
    table = ensure_table_array(tables.part1.A_2);
    factor = linear_table_interpolation(table, altitude);
end

function clearance = iec60664_get_clearance_over_30kHz(tables, rated_peak, freq, current_clearance)
    if ~isfield(tables, 'part4') || ~isfield(tables.part4, 'Table_1')
        clearance = current_clearance;
        return;
    end
    skin = skin_depth_copper(freq);
    is_homogeneous = skin >= current_clearance * 0.2;
    if is_homogeneous
        freq_mhz = freq / 1e6;
        crit_mhz = 0.2 / current_clearance;
        min_mhz = 3;
        if freq_mhz < crit_mhz
            clearance = current_clearance;
        elseif freq_mhz > min_mhz
            clearance = current_clearance * 1.25;
        else
            factor = 1 + (freq_mhz - crit_mhz) / (min_mhz - crit_mhz) * 0.25;
            clearance = current_clearance * factor;
        end
    else
        table = ensure_table_array(tables.part4.Table_1);
        clearance = linear_table_interpolation(table, rated_peak);
    end
end

function creepage = iec60664_get_creepage_over_30kHz(tables, voltage_peak, freq)
    creepage = 0;
    if ~isfield(tables, 'part4') || ~isfield(tables.part4, 'Table_2')
        return;
    end
    table2 = tables.part4.Table_2;
    freq_fields = fieldnames(table2);
    freqs = zeros(numel(freq_fields), 1);
    for i = 1:numel(freq_fields)
        freqs(i) = str2double(freq_fields{i});
    end
    [freqs, idx] = sort(freqs);
    tables_sorted = cell(numel(freqs), 1);
    for i = 1:numel(freqs)
        tables_sorted{i} = ensure_table_array(table2.(freq_fields{idx(i)}));
    end

    prev_freq = 30000;
    prev_table = [];
    for i = 1:numel(freqs)
        f = freqs(i);
        if freq >= prev_freq && freq <= f
            top_val = linear_table_interpolation(tables_sorted{i}, voltage_peak);
            if isempty(prev_table)
                creepage = top_val;
            else
                bottom_val = linear_table_interpolation(prev_table, voltage_peak);
                prop = (freq - prev_freq) / (f - prev_freq);
                creepage = bottom_val + (top_val - bottom_val) * prop;
            end
            return;
        end
        prev_freq = f;
        prev_table = tables_sorted{i};
    end
end

function withstand = iec60664_calculate_withstand_voltage(Vrms, Vpeak, rated_impulse, is_reinforced)
    voltage_temp = Vrms + 1200;
    if is_reinforced
        voltage_temp = voltage_temp * 2;
    end
    F1 = 1.2;
    F3 = 1.25;
    F4 = 1.1;
    voltage_recurring = F1 * F4 * sqrt(2) * Vrms;
    if is_reinforced
        voltage_recurring = voltage_recurring * F3;
    end
    withstand = max([rated_impulse, voltage_temp, voltage_recurring, Vpeak]);
end

function dti = iec60664_distance_through_insulation_over_30kHz(working_voltage)
    dti = 0;
    max_iter = 5000;
    for i = 1:max_iter
        if electric_field_strength_is_valid(dti, working_voltage)
            return;
        end
        dti = dti + 1e-6;
    end
end

function ok = electric_field_strength_is_valid(dti, voltage)
    if dti == 0
        ok = false;
    elseif dti < 30e-6
        ok = (voltage / dti) < 10e6;
    elseif dti > 0.00075
        ok = (voltage / dti) < 2e6;
    else
        ok = (voltage / dti) < (0.25 / (dti * 1000) + 1.667) * 1e6;
    end
end

function delta = skin_depth_copper(freq)
    mu0 = 4*pi*1e-7;
    sigma = 5.8e7;
    omega = 2*pi*freq;
    delta = sqrt(2 / (omega * mu0 * sigma));
end

function table = ensure_table_array(table)
    if iscell(table)
        table = cell2mat(table);
    end
end

function y = lookup_step(table, x)
    if isempty(table)
        y = 0;
        return;
    end
    for i = 1:size(table, 1)
        if x <= table(i, 1)
            y = table(i, 2);
            return;
        end
    end
    y = table(end, 2);
end

function y = linear_table_interpolation(table, x)
    if isempty(table)
        y = 0;
        return;
    end
    if x <= table(1, 1)
        if size(table, 1) > 1
            slope = (table(2, 2) - table(1, 2)) / (table(2, 1) - table(1, 1));
            y = table(1, 2) + (x - table(1, 1)) * slope;
        else
            y = table(1, 2);
        end
        return;
    end
    if x >= table(end, 1)
        if size(table, 1) > 1
            slope = (table(end, 2) - table(end-1, 2)) / (table(end, 1) - table(end-1, 1));
            y = table(end, 2) + (x - table(end, 1)) * slope;
        else
            y = table(end, 2);
        end
        return;
    end
    for i = 1:size(table, 1) - 1
        if table(i, 1) <= x && x <= table(i+1, 1)
            proportion = (x - table(i, 1)) / (table(i+1, 1) - table(i, 1));
            y = table(i, 2) + proportion * (table(i+1, 2) - table(i, 2));
            return;
        end
    end
    y = table(end, 2);
end

function name = pick_fieldname(s, desired)
    name = '';
    if isempty(s) || ~isstruct(s)
        return;
    end
    fields = fieldnames(s);
    if isempty(fields)
        return;
    end
    desired_norm = normalize_key(desired);
    for i = 1:numel(fields)
        if strcmp(normalize_key(fields{i}), desired_norm)
            name = fields{i};
            return;
        end
    end
end

function norm = normalize_key(s)
    if ~ischar(s)
        if local_isstring(s)
            s = char(s);
        else
            norm = '';
            return;
        end
    end
    s = lower(s);
    norm = regexprep(s, '[^a-z0-9]', '');
end

function tf = local_contains(str, pattern)
    if ~ischar(str)
        if local_isstring(str)
            str = char(str);
        else
            tf = false;
            return;
        end
    end
    if ~ischar(pattern)
        if local_isstring(pattern)
            pattern = char(pattern);
        else
            tf = false;
            return;
        end
    end
    tf = ~isempty(strfind(lower(str), lower(pattern)));
end

function tf = local_isstring(val)
    tf = false;
    try
        tf = isa(val, 'string');
    catch
        tf = false;
    end
end

function order = parse_section_order(data)
    order = [];
    s = '';
    if isfield(data, 'section_order')
        s = data.section_order;
    end
    if local_isstring(s)
        s = char(s);
    end
    if ~ischar(s)
        s = '';
    end

    if data.n_windings <= 9 && ~isempty(regexp(s, '^[0-9]+$', 'once'))
        tokens = regexp(s, '\d', 'match');
    else
        tokens = regexp(s, '\d+', 'match');
    end
    for i = 1:length(tokens)
        v = str2double(tokens{i});
        if ~isnan(v) && v >= 1 && v <= data.n_windings
            order(end+1) = v; %#ok<AGROW>
        end
    end

    if isempty(order)
        order = 1:data.n_windings;
    end

    % Ensure all windings appear at least once
    for w = 1:data.n_windings
        if ~any(order == w)
            order(end+1) = w; %#ok<AGROW>
        end
    end
end

function [section_turns, section_windings] = build_section_plan(data, order)
    n_w = data.n_windings;
    counts = zeros(1, n_w);
    for i = 1:length(order)
        counts(order(i)) = counts(order(i)) + 1;
    end

    allocations = cell(1, n_w);
    indices = ones(1, n_w);

    for w = 1:n_w
        n_turns = data.windings(w).n_turns;
        c = counts(w);
        if c <= 0
            c = 1;
        end
        base = floor(n_turns / c);
        rem = mod(n_turns, c);
        arr = base * ones(1, c);
        if rem > 0
            arr(1:rem) = arr(1:rem) + 1;
        end
        allocations{w} = arr;
    end

    section_windings = order;
    section_turns = zeros(1, length(order));
    for i = 1:length(order)
        w = order(i);
        idx = indices(w);
        if idx <= length(allocations{w})
            section_turns(i) = allocations{w}(idx);
        else
            section_turns(i) = 0;
        end
        indices(w) = idx + 1;
    end
end

function v = get_tape_layer_breakdown_v(data)
    v = 0;
    if ~isfield(data, 'tape_kv_per_mm') || ~isfield(data, 'tape_thickness')
        return;
    end
    if data.tape_kv_per_mm <= 0 || data.tape_thickness <= 0
        return;
    end
    thickness_mm = data.tape_thickness * 1e3;
    v = data.tape_kv_per_mm * thickness_mm * 1e3;
end

function used = is_tiw_used(data, winding_a, winding_b)
    used = false;
    if winding_a >= 1 && winding_a <= data.n_windings
        if isfield(data.windings(winding_a), 'wire_insulation') && ...
                strcmpi(data.windings(winding_a).wire_insulation, 'tiw')
            used = true;
        end
    end
    if winding_b >= 1 && winding_b <= data.n_windings
        if isfield(data.windings(winding_b), 'wire_insulation') && ...
                strcmpi(data.windings(winding_b).wire_insulation, 'tiw')
            used = true;
        end
    end
end

function options = build_wire_option_lists(wires)
    wire_names = fieldnames(wires);
    standards = {};
    diameters = {};
    coatings = {};

    for i = 1:length(wire_names)
        winfo = wires.(wire_names{i});
        if isfield(winfo, 'standard')
            standards{end+1} = winfo.standard; %#ok<AGROW>
        end
        if isfield(winfo, 'cond_diameter')
            diameters{end+1} = winfo.cond_diameter; %#ok<AGROW>
        end
        if isfield(winfo, 'coating')
            coatings{end+1} = winfo.coating; %#ok<AGROW>
        end
    end

    standards = normalize_option_list(standards);
    diameters = normalize_option_list(diameters);
    coatings = normalize_option_list(coatings);

    options.standards = standards;
    options.cond_diameters = diameters;
    options.coatings = coatings;
end

function list = normalize_option_list(list)
    if isempty(list)
        list = {'-'};
        return;
    end
    out = {};
    for i = 1:length(list)
        v = list{i};
        if iscell(v)
            for j = 1:length(v)
                s = normalize_option_value(v{j});
                if ~isempty(s)
                    out{end+1} = s; %#ok<AGROW>
                end
            end
        else
            s = normalize_option_value(v);
            if ~isempty(s)
                out{end+1} = s; %#ok<AGROW>
            end
        end
    end
    if isempty(out)
        list = {'-'};
    else
        list = unique(out, 'stable');
    end
end

function s = normalize_option_value(v)
    if isempty(v)
        s = '';
    elseif ischar(v)
        s = strtrim(v);
    elseif isstring(v)
        s = strtrim(char(v));
    elseif isnumeric(v)
        s = strtrim(num2str(v));
    else
        s = '';
    end
end

function set_popup_value(handle, value)
    if isempty(handle) || ~ishandle(handle)
        return;
    end
    list = get(handle, 'String');
    if ischar(list)
        list = cellstr(list);
    end
    idx = find(strcmp(list, value), 1);
    if isempty(idx)
        idx = 1;
    end
    set(handle, 'Value', idx);
end

function gap = get_inter_winding_gap(data, winding_a, winding_b)
    gap = data.gap_winding;
    if winding_a < 1 || winding_b > data.n_windings
        return;
    end
    % Physical inter-winding gap is set by tape stack only
    if isfield(data, 'tape_thickness') && isfield(data, 'tape_layers')
        gap = data.tape_thickness * max(0, data.tape_layers);
    end
end

function is_foil = is_foil_wire(data, wire_type)
    wire = data.api.get_wire_info(wire_type);
    if isfield(wire, 'conductor_shape')
        is_rect = strcmp(wire.conductor_shape, 'rectangular');
    else
        is_rect = false;
    end
    [vis_w, vis_h] = data.api.get_wire_visual_dims(wire_type);
    bobbin_height = 0;
    if isfield(data, 'selected_core') && isfield(data.cores, data.selected_core)
        core = data.cores.(data.selected_core);
        bobbin = data.layout_calc.get_bobbin_dimensions(core);
        bobbin_height = bobbin.height;
    end
    is_foil = is_rect && (vis_w > 5 * vis_h) && (bobbin_height <= 0 || vis_w > bobbin_height * 0.3);
end

function layout = calculate_layout(data, wire_type, n_turns, pattern, n_filar)
    if nargin < 5 || isempty(n_filar)
        n_filar = 1;
    end

    edge_margin = 0;
    if isfield(data, 'edge_margin')
        edge_margin = data.edge_margin;
    end

    try
        layout = data.layout_calc.calculate_winding_layout(...
            data.selected_core, wire_type, n_turns, pattern, n_filar, edge_margin);
        return;
    catch err
        if local_contains(err.message, 'too many inputs') || local_contains(err.message, 'Too many input')
            % Legacy classdef without n_filar/edge_margin support
            n_turns_eff = n_turns * max(1, n_filar);
            layout = data.layout_calc.calculate_winding_layout(...
                data.selected_core, wire_type, n_turns_eff, pattern);
            layout.legacy_no_filar = true;
            layout.edge_margin = edge_margin;
            return;
        end
        rethrow(err);
    end
end

% ===============================================================
% CALLBACK: SUPPLIER CASCADE (Issue #4)
% ===============================================================

function select_supplier(src, ~)
    fig = gcbf;
    data = guidata(fig);

    sup_list = get(src, 'String');
    idx = get(src, 'Value');
    data.selected_supplier = sup_list{idx};

    % Update core shapes dropdown for this supplier
    new_cores = data.api.get_cores_by_supplier(data.selected_supplier);
    if isempty(new_cores)
        new_cores = fieldnames(data.cores);
    end

    core_dd = findobj(fig, 'Tag', 'core_dropdown');
    set(core_dd, 'String', new_cores, 'Value', 1);

    if ~isempty(new_cores)
        data.selected_core = new_cores{1};
    end

    % Update materials dropdown for this supplier
    new_mats = data.api.get_materials_by_supplier(data.selected_supplier);
    if isempty(new_mats)
        new_mats = fieldnames(data.materials);
    end

    mat_dd = findobj(fig, 'Tag', 'material_dropdown');
    set(mat_dd, 'String', new_mats, 'Value', 1);

    if ~isempty(new_mats)
        data.selected_material = new_mats{1};
    end

    % Update info displays
    set(findobj(fig, 'Tag', 'core_info'), 'String', get_core_info_text(data));
    set(findobj(fig, 'Tag', 'material_info'), 'String', get_material_info_text(data));

    guidata(fig, data);
    update_visualization(data);
end

function select_core(src, ~)
    fig = gcbf;
    data = guidata(fig);

    core_list = get(src, 'String');
    idx = get(src, 'Value');
    data.selected_core = core_list{idx};

    set(findobj(fig, 'Tag', 'core_info'), 'String', get_core_info_text(data));
    guidata(fig, data);
    update_visualization(data);
end

function select_material(src, ~)
    fig = gcbf;
    data = guidata(fig);

    mat_list = get(src, 'String');
    idx = get(src, 'Value');
    data.selected_material = mat_list{idx};

    set(findobj(fig, 'Tag', 'material_info'), 'String', get_material_info_text(data));

    % Auto-fill Steinmetz coefficients for new material
    try
        [sk, sa, sb] = data.api.get_steinmetz_coefficients(data.selected_material, data.f);
        if ~isempty(sk)
            data.steinmetz.k = sk;
            data.steinmetz.alpha = sa;
            data.steinmetz.beta = sb;
            set(findobj(fig, 'Tag', 'steinmetz_k'), 'String', num2str(sk, '%.4g'));
            set(findobj(fig, 'Tag', 'steinmetz_alpha'), 'String', num2str(sa, '%.4g'));
            set(findobj(fig, 'Tag', 'steinmetz_beta'), 'String', num2str(sb, '%.4g'));
        else
            data.steinmetz.k = [];
            data.steinmetz.alpha = [];
            data.steinmetz.beta = [];
            set(findobj(fig, 'Tag', 'steinmetz_k'), 'String', '');
            set(findobj(fig, 'Tag', 'steinmetz_alpha'), 'String', '');
            set(findobj(fig, 'Tag', 'steinmetz_beta'), 'String', '');
        end
    catch
    end

    guidata(fig, data);
end

function update_frequency(src, ~)
    fig = gcbf;
    data = guidata(fig);
    data.f = str2double(get(src, 'String')) * 1e3;
    guidata(fig, data);
end

function update_gap_type(src, ~)
    fig = gcbf;
    data = guidata(fig);
    gap_types = get(src, 'String');
    idx = get(src, 'Value');
    data.core_gap_type = gap_types{idx};

    % Enable/disable length and num_gaps based on type
    gap_len_ctrl = findobj(fig, 'Tag', 'gap_length');
    gap_num_ctrl = findobj(fig, 'Tag', 'gap_num');

    switch data.core_gap_type
        case 'Ungapped'
            data.core_gap_length = 0;
            data.core_num_gaps = 1;
            set(gap_len_ctrl, 'String', '0', 'Enable', 'off');
            set(gap_num_ctrl, 'String', '1', 'Enable', 'off');
        case {'Ground', 'Spacer'}
            set(gap_len_ctrl, 'Enable', 'on');
            set(gap_num_ctrl, 'String', '1', 'Enable', 'off');
            data.core_num_gaps = 1;
            if data.core_gap_length == 0
                data.core_gap_length = 1e-3;
                set(gap_len_ctrl, 'String', '1');
            end
        case 'Distributed'
            set(gap_len_ctrl, 'Enable', 'on');
            set(gap_num_ctrl, 'Enable', 'on');
            if data.core_gap_length == 0
                data.core_gap_length = 1e-3;
                set(gap_len_ctrl, 'String', '1');
            end
            if data.core_num_gaps < 2
                data.core_num_gaps = 3;
                set(gap_num_ctrl, 'String', '3');
            end
        otherwise
            data.core_gap_type = 'Ungapped';
            data.core_gap_length = 0;
            data.core_num_gaps = 1;
            set(gap_len_ctrl, 'String', '0', 'Enable', 'off');
            set(gap_num_ctrl, 'String', '1', 'Enable', 'off');
    end

    guidata(fig, data);
    update_visualization(data);
end

function update_gap_length(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val >= 0
        data.core_gap_length = val * 1e-3;  % Convert mm to meters
    end
    guidata(fig, data);
    update_visualization(data);
end

function update_num_gaps(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = round(str2double(get(src, 'String')));
    if ~isnan(val) && val >= 1
        data.core_num_gaps = val;
        set(src, 'String', num2str(val));
    end
    guidata(fig, data);
    update_visualization(data);
end

function select_wire(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);

    wire_list = get(src, 'String');
    idx = get(src, 'Value');
    wire_type = wire_list{idx};

    data.windings(winding).wire_type = wire_type;

    % Update wire dimensions and shape
    [w, h, shape] = data.api.wire_to_conductor_dims(wire_type);
    data.width = w;
    data.height = h;
    data.windings(winding).wire_shape = shape;

    % Update wire info fields (Issue #3)
    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);

    guidata(fig, data);
    update_visualization(data);
end

function select_wire_attribute(src, ~, winding, field)
    fig = gcbf;
    data = guidata(fig);

    list = get(src, 'String');
    if ischar(list)
        list = cellstr(list);
    end
    idx = get(src, 'Value');
    if isempty(idx) || idx < 1 || idx > numel(list)
        return;
    end
    selected_value = list{idx};

    % Find wires matching this attribute
    wire_names = fieldnames(data.wires);
    matches = {};
    for i = 1:length(wire_names)
        wname = wire_names{i};
        winfo = data.wires.(wname);
        if isfield(winfo, field) && strcmp(winfo.(field), selected_value)
            matches{end+1} = wname; %#ok<AGROW>
        end
    end

    if isempty(matches)
        update_wire_info_fields(fig, data, winding);
        return;
    end

    current = data.windings(winding).wire_type;
    if ~any(strcmp(matches, current))
        data.windings(winding).wire_type = matches{1};
        [w_dim, h_dim, shape] = data.api.wire_to_conductor_dims(data.windings(winding).wire_type);
        data.width = w_dim;
        data.height = h_dim;
        data.windings(winding).wire_shape = shape;
    end

    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);
    guidata(fig, data);
    update_visualization(data);
end

function switch_tab(~, ~, tab_num)
    fig = gcbf;
    data = guidata(fig);
    for w = 1:data.n_windings
        set(findobj(fig, 'Tag', sprintf('content%d', w)), 'Visible', 'off');
    end
    set(findobj(fig, 'Tag', sprintf('content%d', tab_num)), 'Visible', 'on');
end

function adjust_turns(~, ~, winding, delta)
    fig = gcbf;
    data = guidata(fig);
    new_val = max(1, data.windings(winding).n_turns + delta);
    data.windings(winding).n_turns = new_val;
    set(findobj(fig, 'Tag', sprintf('turns_val_%d', winding)), 'String', num2str(new_val));
    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);
    guidata(fig, data);
    update_visualization(data);
end

function adjust_filar(~, ~, winding, delta)
    fig = gcbf;
    data = guidata(fig);
    new_val = max(1, min(4, data.windings(winding).n_filar + delta));
    data.windings(winding).n_filar = new_val;
    set(findobj(fig, 'Tag', sprintf('filar_val_%d', winding)), 'String', num2str(new_val));
    set(findobj(fig, 'Tag', sprintf('filar_name_%d', winding)), 'String', get_filar_name(new_val));
    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);
    guidata(fig, data);
    update_visualization(data);
end

function update_turns_manual(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);
    new_val = max(1, round(str2double(get(src, 'String'))));
    data.windings(winding).n_turns = new_val;
    set(src, 'String', num2str(new_val));
    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);
    guidata(fig, data);
    update_visualization(data);
end

function update_filar_manual(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);
    new_val = max(1, min(4, round(str2double(get(src, 'String')))));
    data.windings(winding).n_filar = new_val;
    set(src, 'String', num2str(new_val));
    set(findobj(fig, 'Tag', sprintf('filar_name_%d', winding)), 'String', get_filar_name(new_val));
    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);
    guidata(fig, data);
    update_visualization(data);
end

function update_current(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);
    data.windings(winding).current = str2double(get(src, 'String'));
    update_wire_info_fields(fig, data, winding);
    update_summary(fig, data, winding);
    guidata(fig, data);
end

function update_voltage(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);
    data.windings(winding).voltage = str2double(get(src, 'String'));
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_phase(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);
    data.windings(winding).phase = str2double(get(src, 'String'));
    guidata(fig, data);
end

function update_insulation_class(src, ~)
    fig = gcbf;
    data = guidata(fig);
    list = get(src, 'String');
    idx = get(src, 'Value');
    if ischar(list)
        list = cellstr(list);
    end
    if idx >= 1 && idx <= numel(list)
        data.insulation_class = list{idx};
    end
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_tape_thickness(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val_mm = str2double(get(src, 'String'));
    if isnan(val_mm) || val_mm < 0
        val_mm = 0;
    end
    data.tape_thickness = val_mm * 1e-3;
    set(src, 'String', num2str(val_mm));
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_tape_layers(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = round(str2double(get(src, 'String')));
    if isnan(val) || val < 0
        val = 0;
    end
    data.tape_layers = val;
    set(src, 'String', num2str(val));
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_tape_strength(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if isnan(val) || val < 0
        val = 0;
    end
    data.tape_kv_per_mm = val;
    set(src, 'String', num2str(val));
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_tiw_kv(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if isnan(val) || val < 0
        val = 0;
    end
    data.tiw_kv = val;
    set(src, 'String', num2str(val));
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_edge_margin(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val_mm = str2double(get(src, 'String'));
    if isnan(val_mm) || val_mm < 0
        val_mm = 0;
    end
    data.edge_margin = val_mm * 1e-3;
    set(src, 'String', num2str(val_mm));
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_core_loss_method(src, ~)
    fig = gcbf;
    data = guidata(fig);
    items = get(src, 'String');
    data.core_loss_method = items{get(src, 'Value')};
    guidata(fig, data);
end

function update_steinmetz_k(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.steinmetz.k = val;
    end
    guidata(fig, data);
end

function update_steinmetz_alpha(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.steinmetz.alpha = val;
    end
    guidata(fig, data);
end

function update_steinmetz_beta(src, ~)
    fig = gcbf;
    data = guidata(fig);
    val = str2double(get(src, 'String'));
    if ~isnan(val) && val > 0
        data.steinmetz.beta = val;
    end
    guidata(fig, data);
end

function update_wire_insulation(src, ~, winding)
    fig = gcbf;
    data = guidata(fig);
    list = get(src, 'String');
    idx = get(src, 'Value');
    if ischar(list)
        list = cellstr(list);
    end
    if idx >= 1 && idx <= numel(list)
        if strcmpi(list{idx}, 'TIW')
            data.windings(winding).wire_insulation = 'tiw';
        else
            data.windings(winding).wire_insulation = 'standard';
        end
    end
    update_all_summaries(fig, data);
    guidata(fig, data);
    update_visualization(data);
end

function update_summary(fig, data, winding)
    set(findobj(fig, 'Tag', sprintf('summary_%d', winding)), ...
        'String', get_winding_summary(data, winding));
end

function update_all_summaries(fig, data)
    for w = 1:data.n_windings
        update_summary(fig, data, w);
    end
end

function change_vis_mode(~, ~)
    fig = gcbf;
    data = guidata(fig);
    update_visualization(data);
end

function cb_open_winding_options(~, ~)
    fig = gcbf;
    data = guidata(fig);
    open_winding_options_dialog(data);
end

function update_section_order(src, ~)
    fig = gcbf;
    data = guidata(fig);
    data.section_order = get(src, 'String');
    guidata(fig, data);
    update_visualization(data);
end

% ===============================================================
% WINDING OPTIONS DIALOG (OM-native controls)
% ===============================================================

function open_winding_options_dialog(data)
% Opens a popup window with OpenMagnetics-native winding layout controls.
% Global: Windings Orientation, Section Alignment, Interleave Order, Proportions
% Per-winding: Turns Alignment
% Layout mirrors the OpenMagnetics web tool.

    parent_fig = data.fig_gui;
    n_w = data.n_windings;

    % Calculate dialog size
    row_h = 32;          % height per row of controls
    hdr_h = 28;          % height for winding header bar
    global_rows = 3 + n_w;  % orientation, section alignment, interleave order + proportions
    per_w_rows = 1;      % turns alignment only (proportions moved to global)
    per_w_block = hdr_h + per_w_rows * row_h + 12;

    top_pad = 20;
    bot_pad = 60;        % space for Apply button
    sep = 12;            % gap between sections

    dlg_h = top_pad + global_rows * row_h + sep + n_w * per_w_block + bot_pad;
    dlg_w = 460;

    % Position dialog centered on parent
    parent_pos = get(parent_fig, 'Position');
    dlg_x = parent_pos(1) + (parent_pos(3) - dlg_w) / 2;
    dlg_y = parent_pos(2) + (parent_pos(4) - dlg_h) / 2;

    dlg = figure('Name', 'Winding Layout Options', ...
                 'Position', [dlg_x dlg_y dlg_w dlg_h], ...
                 'NumberTitle', 'off', ...
                 'MenuBar', 'none', ...
                 'Resize', 'off');

    % Store handles for retrieval on Apply
    h = struct();
    h.parent_fig = parent_fig;
    h.n_windings = n_w;

    lbl_x = 15;
    ctrl_x = 210;
    ctrl_w = 220;

    % ---- Global Controls ----
    y = dlg_h - top_pad - 5;

    uicontrol('Parent', dlg, 'Style', 'text', ...
              'String', 'Windings Orientation:', ...
              'Position', [lbl_x y 180 20], ...
              'HorizontalAlignment', 'left', 'FontSize', 9);
    orient_opts = {'contiguous', 'overlapping'};
    orient_val = 1;
    for k = 1:numel(orient_opts)
        if strcmp(orient_opts{k}, data.om_winding_orientation)
            orient_val = k;
        end
    end
    h.pop_orientation = uicontrol('Parent', dlg, 'Style', 'popupmenu', ...
              'String', orient_opts, ...
              'Position', [ctrl_x y-2 ctrl_w 25], ...
              'Value', orient_val, 'FontSize', 9);

    y = y - row_h;
    uicontrol('Parent', dlg, 'Style', 'text', ...
              'String', 'Section Alignment:', ...
              'Position', [lbl_x y 180 20], ...
              'HorizontalAlignment', 'left', 'FontSize', 9);
    align_opts = {'centered', 'inner or top', 'outer or bottom', 'spread'};
    align_val = 1;
    for k = 1:numel(align_opts)
        if strcmp(align_opts{k}, data.om_section_alignment)
            align_val = k;
        end
    end
    h.pop_section_align = uicontrol('Parent', dlg, 'Style', 'popupmenu', ...
              'String', align_opts, ...
              'Position', [ctrl_x y-2 ctrl_w 25], ...
              'Value', align_val, 'FontSize', 9);

    y = y - row_h;
    uicontrol('Parent', dlg, 'Style', 'text', ...
              'String', 'Section Interleave Order:', ...
              'Position', [lbl_x y 180 20], ...
              'HorizontalAlignment', 'left', 'FontSize', 9);
    h.edit_section_order = uicontrol('Parent', dlg, 'Style', 'edit', ...
              'String', data.section_order, ...
              'Position', [ctrl_x y-2 ctrl_w 25], ...
              'FontSize', 9);

    % ---- Global Proportions (one row per winding) ----
    h.edit_proportion = cell(1, n_w);
    for p = 1:n_w
        y = y - row_h;
        wname = 'Primary';
        if p == 2; wname = 'Secondary';
        elseif p > 2; wname = sprintf('Winding %d', p);
        end
        if p <= numel(data.windings)
            wname = data.windings(p).name;
        end
        uicontrol('Parent', dlg, 'Style', 'text', ...
                  'String', sprintf('%s Proportion:', wname), ...
                  'Position', [lbl_x y 180 20], ...
                  'HorizontalAlignment', 'left', 'FontSize', 9);
        prop_val = 100.0 / n_w;
        if numel(data.om_proportions) >= p
            prop_val = data.om_proportions{p} * 100;
        end
        h.edit_proportion{p} = uicontrol('Parent', dlg, 'Style', 'edit', ...
                  'String', sprintf('%.1f', prop_val), ...
                  'Position', [ctrl_x y-2 80 25], ...
                  'FontSize', 9);
        uicontrol('Parent', dlg, 'Style', 'text', ...
                  'String', '%', ...
                  'Position', [ctrl_x+85 y 20 20], ...
                  'HorizontalAlignment', 'left', 'FontSize', 9);
    end

    y = y - sep;

    % ---- Per-Winding Controls (turns alignment only) ----
    turns_align_opts = {'centered', 'inner or top', 'outer or bottom', 'spread'};
    h.pop_turns_align = cell(1, n_w);

    % Winding header colors (cycle through for >2 windings)
    hdr_colors = {[0.2 0.4 0.8], [0.8 0.2 0.2], [0.1 0.6 0.3], [0.6 0.3 0.7]};

    for w = 1:n_w
        % Winding header bar
        y = y - hdr_h;
        wname = data.windings(w).name;
        cidx = mod(w - 1, numel(hdr_colors)) + 1;
        uicontrol('Parent', dlg, 'Style', 'text', ...
                  'String', sprintf('  %s', wname), ...
                  'Position', [lbl_x y dlg_w-30 hdr_h-4], ...
                  'HorizontalAlignment', 'left', 'FontSize', 9, ...
                  'FontWeight', 'bold', ...
                  'BackgroundColor', hdr_colors{cidx}, ...
                  'ForegroundColor', [1 1 1]);

        % Turns Alignment
        y = y - row_h;
        uicontrol('Parent', dlg, 'Style', 'text', ...
                  'String', 'Turns Alignment:', ...
                  'Position', [30 y 160 20], ...
                  'HorizontalAlignment', 'left', 'FontSize', 9);
        ta_val = 4;  % default: spread
        if numel(data.om_turns_alignment) >= w
            for k = 1:numel(turns_align_opts)
                if strcmp(turns_align_opts{k}, data.om_turns_alignment{w})
                    ta_val = k;
                end
            end
        end
        h.pop_turns_align{w} = uicontrol('Parent', dlg, 'Style', 'popupmenu', ...
                  'String', turns_align_opts, ...
                  'Position', [ctrl_x y-2 ctrl_w 25], ...
                  'Value', ta_val, 'FontSize', 9);

        y = y - 4;  % small gap before next winding block
    end

    % ---- Apply Button (user closes dialog manually) ----
    uicontrol('Parent', dlg, 'Style', 'pushbutton', ...
              'String', 'Apply', ...
              'Position', [dlg_w/2 - 70 12 140 38], ...
              'FontSize', 11, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.2 0.7 0.3], ...
              'ForegroundColor', 'w', ...
              'Callback', {@cb_winding_opts_apply, h});
end

function cb_winding_opts_apply(~, ~, h)
% Read all controls from winding options dialog and apply to data struct.
% Does NOT close the dialog — user closes it manually.
    parent_fig = h.parent_fig;
    data = guidata(parent_fig);
    n_w = h.n_windings;

    % Global controls
    orient_opts = get(h.pop_orientation, 'String');
    data.om_winding_orientation = orient_opts{get(h.pop_orientation, 'Value')};

    align_opts = get(h.pop_section_align, 'String');
    data.om_section_alignment = align_opts{get(h.pop_section_align, 'Value')};

    new_order = strtrim(get(h.edit_section_order, 'String'));
    if ~isempty(new_order)
        data.section_order = new_order;
        order_ctrl = findobj(parent_fig, 'Tag', 'section_order');
        if ~isempty(order_ctrl)
            set(order_ctrl, 'String', new_order);
        end
    end

    % Per-winding turns alignment
    turns_align_opts = {'centered', 'inner or top', 'outer or bottom', 'spread'};
    for w = 1:n_w
        if numel(h.pop_turns_align) >= w && ~isempty(h.pop_turns_align{w})
            data.om_turns_alignment{w} = turns_align_opts{get(h.pop_turns_align{w}, 'Value')};
        end
    end

    % Read global proportions
    raw_props = zeros(1, n_w);
    for p = 1:n_w
        if numel(h.edit_proportion) >= p && ~isempty(h.edit_proportion{p})
            raw_props(p) = str2double(get(h.edit_proportion{p}, 'String'));
            if isnan(raw_props(p)) || raw_props(p) < 0
                raw_props(p) = 100.0 / n_w;
            end
        end
    end

    % Normalize proportions to sum to 1.0
    prop_sum = sum(raw_props);
    if prop_sum < 0.01
        prop_sum = 100.0;
        raw_props = ones(1, n_w) * (100.0 / n_w);
    end
    for w = 1:n_w
        data.om_proportions{w} = raw_props(w) / prop_sum;
    end

    % Update proportion fields to show normalized values
    for p = 1:n_w
        if numel(h.edit_proportion) >= p && ~isempty(h.edit_proportion{p})
            set(h.edit_proportion{p}, 'String', ...
                sprintf('%.1f', data.om_proportions{p} * 100));
        end
    end

    guidata(parent_fig, data);

    % Refresh visualization in main GUI
    update_visualization(data);
end

% ===============================================================
% VISUALIZATION
% ===============================================================

function update_visualization(data)
    fig = data.fig_gui;
    ax = findobj(fig, 'Tag', 'vis_axes');
    vis_mode = get(findobj(fig, 'Tag', 'vis_mode'), 'Value');
    metrics_ctrl = findobj(fig, 'Tag', 'vis_metrics');

    cla(ax);
    if ~isempty(metrics_ctrl)
        set(metrics_ctrl, 'String', '');
    end

    switch vis_mode
        case 1
            visualize_schematic_2d(data, ax);
        case 2
            visualize_core_window(data, ax);
        case 3
            visualize_openmagnetics(data, ax);
        case 4
            text(ax, 0.5, 0.5, 'Run Analysis to see loss distribution', ...
                'HorizontalAlignment', 'center', 'FontSize', 10, ...
                'Units', 'normalized');
    end
end

function visualize_openmagnetics(data, ax)
% Render PyOpenMagnetics 2D cross-section (core + bobbin + turns)
% Calls Python script to generate SVG, then parses and renders it

    fig = data.fig_gui;
    info_ctrl = findobj(fig, 'Tag', 'vis_info');

    % Show generating status
    set(info_ctrl, 'String', 'Generating OpenMagnetics view...', ...
        'BackgroundColor', [0.95 0.95 0.8]);
    drawnow;

    try
        % Build the visualization config
        fprintf('[OM_VIZ] Building config...\n');
        config = build_om_viz_config(data);
        fprintf('[OM_VIZ] Config built: core=%s, material=%s, windings=%d\n', ...
            config.core_shape, config.material, length(config.windings));

        % Write config to temp JSON file
        % Use pwd for paths - avoids MSYS/Windows path mangling in Octave
        script_dir = pwd();
        config_file = fullfile(script_dir, 'om_viz_config.json');
        svg_file = fullfile(script_dir, 'om_visualization.svg');
        meta_file = fullfile(script_dir, 'om_visualization_meta.json');
        config.output_svg = strrep(svg_file, '\', '/');
        config.output_meta = strrep(meta_file, '\', '/');

        % Write JSON config
        fprintf('[OM_VIZ] Encoding JSON...\n');
        json_str = jsonencode(config);
        fprintf('[OM_VIZ] JSON length: %d chars\n', length(json_str));
        fid = fopen(config_file, 'w');
        if fid == -1
            error('Cannot write config file: %s', config_file);
        end
        fwrite(fid, json_str);
        fclose(fid);
        fprintf('[OM_VIZ] Config written to: %s\n', config_file);

        % Call Python script - use relative paths to avoid MSYS/Windows path mangling
        py_script_name = 'generate_om_visualization.py';
        config_file_name = 'om_viz_config.json';
        
        if ~exist(fullfile(script_dir, py_script_name), 'file')
             error('Python script "%s" not found in %s', py_script_name, script_dir);
        end

        % Check for local venv python (recommended setup)
        python_cmd = 'python';
        venv_python = fullfile(script_dir, '.venv', 'Scripts', 'python.exe');
        if exist(venv_python, 'file')
            python_cmd = ['"' strrep(venv_python, '\', '/') '"'];
        end

        % Add stderr redirection (2>&1) to capture ModuleNotFoundError
        cmd = sprintf('%s "%s" "%s" 2>&1', python_cmd, py_script_name, config_file_name);
        fprintf('[OM_VIZ] Running: %s\n', cmd);
        
        % Debug: check which python is being used if not venv
        if strcmp(python_cmd, 'python')
            [~, py_path] = system('where python');
            if ~isempty(py_path)
                fprintf('[OM_VIZ] Resolved python:\n%s\n', strtrim(py_path));
            end
        end

        [status, output] = system(cmd);
        
        % Check for module errors (ImportError, ModuleNotFoundError, or "No module named")
        is_module_error = ~isempty(strfind(output, 'ModuleNotFoundError')) || ...
                          ~isempty(strfind(output, 'ImportError')) || ...
                          ~isempty(strfind(output, 'No module named'));

        % Fallback: If python failed with ModuleNotFoundError, try 'py' launcher (Windows)
        if status ~= 0 && is_module_error && ispc
            fprintf('[OM_VIZ] Standard python failed. Trying Windows Python Launcher (py)...\n');
            cmd_fallback = sprintf('py "%s" "%s" 2>&1', py_script_name, config_file_name);
            [status_fb, output_fb] = system(cmd_fallback);
            if status_fb == 0 && ~isempty(strfind(output_fb, 'OK'))
                status = status_fb;
                output = output_fb;
                fprintf('[OM_VIZ] Success using ''py'' launcher.\n');
            end
        end

        % Fallback 2: Try specific python paths from 'where python' if they look like system installs
        if status ~= 0 && is_module_error && ispc
             [~, py_paths_str] = system('where python');
             % Split by newlines
             py_paths = strsplit(strtrim(py_paths_str), char(10));
             found_non_module_error = false;
             for i = 1:length(py_paths)
                 p = strtrim(py_paths{i});
                 if isempty(p); continue; end
                 % Skip Octave bundled python or the one we just tried (if it was 'python')
                 if ~isempty(strfind(lower(p), 'octave')) || ...
                         ~isempty(strfind(lower(p), 'usr\bin')) || ...
                         ~isempty(strfind(lower(p), 'usr/bin'))
                     continue;
                 end
                 % Convert backslashes for MSYS shell compatibility
                 p = strrep(p, '\', '/');
                  
                 fprintf('[OM_VIZ] Trying alternative python: %s\n', p);
                 cmd_alt = sprintf('"%s" "%s" "%s" 2>&1', p, py_script_name, config_file_name);
                 [status_alt, output_alt] = system(cmd_alt);
                 if status_alt == 0 && ~isempty(strfind(output_alt, 'OK'))
                     status = status_alt;
                     output = output_alt;
                     fprintf('[OM_VIZ] Success using alternative python.\n');
                     break;
                 else
                     alt_module_error = ~isempty(strfind(output_alt, 'ModuleNotFoundError')) || ...
                                       ~isempty(strfind(output_alt, 'ImportError')) || ...
                                       ~isempty(strfind(output_alt, 'No module named'));
                     if ~alt_module_error
                         status = status_alt;
                         output = output_alt;
                         found_non_module_error = true;
                     end
                     fprintf('[OM_VIZ] Alternative python failed (exit=%d): %s\n', status_alt, strtrim(output_alt));
                     if found_non_module_error
                         break;
                     end
                 end
             end
         end

        fprintf('[OM_VIZ] Python exit code: %d\n', status);
        fprintf('[OM_VIZ] Python output: "%s"\n', strtrim(output));

        if status ~= 0 || isempty(strfind(strtrim(output), 'OK'))
            if is_module_error
                fprintf('[OM_VIZ] Hint: PyOpenMagnetics module missing in the python environment used.\n');
                fprintf('[OM_VIZ] If you installed it globally, try running Octave from a terminal where ''python'' works.\n');
                fprintf('[OM_VIZ] Or create a .venv in this folder: %s\n', script_dir);
            elseif status < 0 && isempty(strtrim(output))
                % Negative exit codes with no output indicate a native crash
                % (e.g., access violation in PyMKF C++ for very small toroids).
                fprintf('[OM_VIZ] Hint: Python crashed (segfault) — this core shape may be too small\n');
                fprintf('[OM_VIZ] or unsupported by the PyOpenMagnetics native library.\n');
                fprintf('[OM_VIZ] Try selecting a different/larger core shape.\n');
            end
            error('Python script failed (exit=%d): %s', status, strtrim(output));
        end

        % Read SVG file
        fprintf('[OM_VIZ] Reading SVG: %s\n', svg_file);
        fid = fopen(svg_file, 'r');
        if fid == -1
            error('Cannot read SVG file: %s', svg_file);
        end
        svg_str = fread(fid, '*char')';
        fclose(fid);
        fprintf('[OM_VIZ] SVG loaded: %d chars\n', length(svg_str));

        om_meta = struct();
        if exist(meta_file, 'file')
            try
                fidm = fopen(meta_file, 'r');
                if fidm ~= -1
                    meta_raw = fread(fidm, '*char')';
                    fclose(fidm);
                    om_meta = jsondecode(meta_raw);
                end
            catch
                om_meta = struct();
            end
        end

        % Parse and render SVG
        parse_om_svg(svg_str, ax, om_meta, data);

        om = get_om_window_metrics(om_meta);
        if om.area_m2 > 0
            data.om_window_cache = set_om_window_cache_entry(data.om_window_cache, data.selected_core, om);
            guidata(fig, data);
        end
        cwf = get_cwf_window_metrics(data);

        % Check for overflow and overlap in OM turns
        winding_warnings = check_om_turn_issues(om_meta);
        warn_suffix = '';
        if ~isempty(winding_warnings)
            warn_suffix = ['\n' winding_warnings];
        end

        if om.area_m2 > 0
            set_vis_metrics_text(data, sprintf( ...
                ['Window area [mm^2]  CWF gross: %.2f\nOM: %.2f\nusable: %.2f' warn_suffix], ...
                cwf.area_m2*1e6, om.area_m2*1e6, cwf.usable_area_m2*1e6));
        else
            set_vis_metrics_text(data, sprintf( ...
                ['Window area [mm^2]  CWF gross: %.2f\nOM: n/a (no bobbin window)\nusable: %.2f' warn_suffix], ...
                cwf.area_m2*1e6, cwf.usable_area_m2*1e6));
        end

        % Update status
        core_name = config.core_shape;
        gap_str = '';
        if isfield(data, 'core_gap_type') && ~strcmp(data.core_gap_type, 'Ungapped')
            gap_str = sprintf(' | Gap: %s %.2fmm', data.core_gap_type, data.core_gap_length*1e3);
        end
        wind_mode = '';
        try
            if isfield(om_meta, 'winding') && isfield(om_meta.winding, 'winding_mode')
                wind_mode = sprintf(' | Mode: %s', om_meta.winding.winding_mode);
            end
        catch
        end
        om_area_str = 'n/a';
        if om.area_m2 > 0
            om_area_str = sprintf('%.2f mm^2', om.area_m2*1e6);
        end
        set(info_ctrl, 'String', ...
            sprintf('OpenMagnetics: %s%s | OM window: %s%s', ...
                core_name, gap_str, om_area_str, wind_mode), ...
            'BackgroundColor', [0.85 0.95 0.85]);

    catch ME
        % Fallback: show error and use basic visualization
        fprintf('[OM_VIZ] ERROR: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf('[OM_VIZ]   at %s line %d\n', ME.stack(1).name, ME.stack(1).line);
        end
        cla(ax);
        visualize_core_window(data, ax);
        vis_mode_ctrl = findobj(fig, 'Tag', 'vis_mode');
        if ~isempty(vis_mode_ctrl)
            try
                set(vis_mode_ctrl, 'Value', 2);
            catch
            end
        end
        set(info_ctrl, 'String', ...
            sprintf('OM View failed (showing Core Window Fit): %s', ME.message), ...
            'BackgroundColor', [1.0 0.9 0.8]);
        set_vis_metrics_text(data, '');
    end
end


function config = build_om_viz_config(data)
% Build JSON config struct for generate_om_visualization.py

    % Get original core shape name (with spaces/slashes)
    core_name = data.selected_core;
    core_aliases = {};
    if isfield(data.cores, core_name) && isfield(data.cores.(core_name), 'name')
        core_name = data.cores.(core_name).name;
    end
    if isfield(data.cores, data.selected_core) && isfield(data.cores.(data.selected_core), 'aliases')
        aliases = data.cores.(data.selected_core).aliases;
        if ischar(aliases)
            core_aliases = {aliases};
        elseif iscell(aliases)
            core_aliases = aliases;
        end
    end

    % Get original material name
    mat_name = data.selected_material;
    if isfield(data.materials, mat_name) && isfield(data.materials.(mat_name), 'name')
        mat_name = data.materials.(mat_name).name;
    end

    % Build gapping array
    gapping = {};
    if isfield(data, 'core_gap_type')
        gapping_cells = data.api.build_gapping_array( ...
            data.core_gap_type, data.core_gap_length, data.core_num_gaps);
        % Convert cell array of structs to cell array for JSON
        for i = 1:length(gapping_cells)
            gapping{i} = gapping_cells{i};
        end
    end
    if isempty(gapping)
        gapping = {struct('type', 'residual', 'length', 10e-6)};
    end

    % Build winding descriptions
    windings = {};
    for w = 1:data.n_windings
        winding = data.windings(w);

        % Get original wire name
        wire_key = winding.wire_type;
        wire_name = wire_key;
        if isfield(data.wires, wire_key) && isfield(data.wires.(wire_key), 'name')
            wire_name = data.wires.(wire_key).name;
        end

        if w == 1
            iso_side = 'primary';
        else
            iso_side = 'secondary';
        end

        wire_std = '';
        wire_shape = 'round';
        cond_w = 0;
        cond_h = 0;
        try
            wire_info = data.api.get_wire_info(wire_key);
            if isfield(wire_info, 'standard')
                wire_std = wire_info.standard;
            end
        catch
        end
        try
            [cond_w, cond_h, wire_shape] = data.api.wire_to_conductor_dims(wire_key);
        catch
        end

        windings{w} = struct( ...
            'name', winding.name, ...
            'wire_name', wire_name, ...
            'wire_standard', wire_std, ...
            'wire_shape', wire_shape, ...
            'wire_cond_w', cond_w, ...
            'wire_cond_h', cond_h, ...
            'num_turns', winding.n_turns, ...
            'num_parallels', winding.n_filar, ...
            'isolation_side', iso_side ...
        );
    end

    config = struct();
    config.core_shape = core_name;
    config.core_shape_key = data.selected_core;
    config.core_shape_aliases = core_aliases;
    config.material = mat_name;
    config.gapping = gapping;
    config.windings = windings;
    config.section_order = data.section_order;
    if isfield(data, 'core_gap_type'); config.core_gap_type = data.core_gap_type; end
    if isfield(data, 'core_gap_length'); config.core_gap_length = data.core_gap_length; end
    if isfield(data, 'core_num_gaps'); config.core_num_gaps = data.core_num_gaps; end
    % OM-native winding layout parameters
    config.winding_orientation = data.om_winding_orientation;
    config.section_alignment = data.om_section_alignment;
    config.turns_alignment_per_winding = data.om_turns_alignment;
    config.proportions_per_winding = data.om_proportions;
    if isfield(data, 'tape_thickness'); config.tape_thickness = data.tape_thickness; end
    if isfield(data, 'tape_layers'); config.tape_layers = data.tape_layers; end
    config.plot_type = 'magnetic';
end


function visualize_schematic_2d(data, ax)
    hold(ax, 'on');
    axis(ax, 'equal');
    grid(ax, 'on');

    x_offset = 0;
    max_y_all = 0;

    for w = 1:data.n_windings
        n_turns = data.windings(w).n_turns;
        n_filar = data.windings(w).n_filar;
        wire_type = data.windings(w).wire_type;

        [w_dim, h_dim, shape] = data.api.wire_to_conductor_dims(wire_type);
        [vis_w, vis_h] = data.api.get_wire_visual_dims(wire_type);
        if is_foil_wire(data, wire_type)
            tmp = w_dim; w_dim = h_dim; h_dim = tmp;
            tmp = vis_w; vis_w = vis_h; vis_h = tmp;
        end

        x_pos = x_offset;
        y_offset = 0;

        for turn = 1:n_turns
            for strand = 1:n_filar
                y_pos = y_offset + (strand - 1) * (h_dim + data.gap_filar);

                if strcmp(shape, 'round')
                    r = vis_w / 2;
                    theta = linspace(0, 2*pi, 50);
                    fill(ax, x_pos + r*cos(theta), y_pos + vis_h/2 + r*sin(theta), ...
                        data.winding_colors{w}, 'EdgeColor', 'k', 'LineWidth', 0.5);
                else
                    rectangle('Parent', ax, ...
                        'Position', [x_pos - vis_w/2, y_pos, vis_w, vis_h], ...
                        'FaceColor', data.winding_colors{w}, ...
                        'EdgeColor', 'k', 'LineWidth', 0.5);
                end
            end

            turn_height = n_filar * h_dim + (n_filar - 1) * data.gap_filar + data.gap_layer;
            y_offset = y_offset + turn_height;
        end

        max_y_all = max(max_y_all, y_offset);

        text(x_pos, y_offset + 0.5e-3, data.windings(w).name, 'Parent', ax, ...
            'HorizontalAlignment', 'center', 'FontWeight', 'bold', ...
            'FontSize', 10, 'Color', data.winding_colors{w});

        if w < data.n_windings
            gap_winding = get_inter_winding_gap(data, w, w+1);
            x_offset = x_offset + max(vis_w, w_dim)/2 + gap_winding + max(vis_w, w_dim)/2;
        end
    end

    ylim(ax, [-2e-3, max_y_all * 1.3]);
    xlabel(ax, 'X Position (m)');
    ylabel(ax, 'Y Position (m)');
    title(ax, 'Winding Schematic');
    hold(ax, 'off');

    set(findobj(data.fig_gui, 'Tag', 'vis_info'), 'String', ...
        'Schematic view showing winding arrangement');
end

function visualize_core_window(data, ax)
    % ISSUE #2 FIX: Draw correct shapes for foil/rect wire

    if strcmp(data.selected_core, 'None')
        text(ax, 0.5, 0.5, 'No core selected', ...
            'HorizontalAlignment', 'center', 'FontSize', 12, ...
            'Units', 'normalized');
        return;
    end

    % Map OM-native winding orientation to CWF packing pattern
    if strcmp(data.om_winding_orientation, 'overlapping')
        pattern = 'orthocyclic';
    else
        pattern = 'layered';
    end

    hold(ax, 'on');
    axis(ax, 'equal');

    core = data.cores.(data.selected_core);
    bobbin = data.layout_calc.get_bobbin_dimensions(core);
    om_ref = get_cached_om_window_metrics(data);
    if om_ref.area_m2 > 0
        bobbin.width = om_ref.width_m;
        bobbin.height = om_ref.height_m;
    end

    edge_margin = 0;
    if isfield(data, 'edge_margin')
        edge_margin = data.edge_margin;
    end

    % Draw bobbin window
    rectangle('Parent', ax, 'Position', [0, 0, bobbin.width, bobbin.height], ...
        'EdgeColor', 'k', 'LineWidth', 2, 'LineStyle', '--');
    if edge_margin > 0
        rectangle('Parent', ax, ...
            'Position', [edge_margin, edge_margin, ...
                         max(1e-6, bobbin.width - 2*edge_margin), ...
                         max(1e-6, bobbin.height - 2*edge_margin)], ...
            'EdgeColor', [0.5 0.5 0.5], 'LineStyle', ':', 'LineWidth', 1);
    end
    text(bobbin.width/2, bobbin.height + 0.001, 'Bobbin Window', ...
        'Parent', ax, 'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');

    x_start = 0;
    total_fits = true;
    x_origin = edge_margin;
    available_width = bobbin.width - 2*edge_margin;

    section_order = parse_section_order(data);
    [section_turns, section_windings] = build_section_plan(data, section_order);

    for s = 1:length(section_windings)
        w = section_windings(s);
        n_turns = section_turns(s);
        if n_turns <= 0
            continue;
        end

        wire_type = data.windings(w).wire_type;
        n_filar = data.windings(w).n_filar;

        layout = calculate_layout(data, wire_type, n_turns, pattern, n_filar);

        if ~layout.fits
            total_fits = false;
        end
        if (x_start + layout.required_width) > max(1e-9, available_width)
            total_fits = false;
        end

        % Determine wire shape for drawing
        is_rect = isfield(layout, 'wire_shape') && strcmp(layout.wire_shape, 'rectangular');

        % Draw turns with correct shapes
        for i = 1:size(layout.turn_positions, 1)
            x = x_origin + x_start + layout.turn_positions(i, 1);
            y = edge_margin + layout.turn_positions(i, 2);

            if is_rect
                % ISSUE #2 FIX: Draw rectangles for foil/rect
                if isfield(layout, 'draw_w')
                    vw = layout.draw_w;
                    vh = layout.draw_h;
                else
                    vw = layout.wire_vis_w;
                    vh = layout.wire_vis_h;
                end
                rectangle('Parent', ax, ...
                    'Position', [x - vw/2, y - vh/2, vw, vh], ...
                    'FaceColor', data.winding_colors{w}, ...
                    'EdgeColor', 'k', 'LineWidth', 0.3);
            else
                % Draw circles for round/litz wire
                r = layout.wire_od / 2;
                theta = linspace(0, 2*pi, 30);
                fill(ax, x + r*cos(theta), y + r*sin(theta), ...
                    data.winding_colors{w}, 'EdgeColor', 'k', 'LineWidth', 0.3);
            end
        end

        % Label winding section
        text(x_origin + x_start + layout.required_width/2, -0.0005, data.windings(w).name, ...
            'Parent', ax, 'HorizontalAlignment', 'center', 'FontSize', 8, ...
            'Color', data.winding_colors{w}, 'FontWeight', 'bold');

        gap_winding = 0;
        if s < length(section_windings)
            if section_windings(s+1) ~= w
                gap_winding = get_inter_winding_gap(data, w, section_windings(s+1));
            end
        end

        if gap_winding > 0
            tape_y = edge_margin;
            tape_h = max(1e-6, bobbin.height - 2*edge_margin);
            rect = rectangle('Parent', ax, ...
                'Position', [x_origin + x_start + layout.required_width, tape_y, ...
                             gap_winding, tape_h], ...
                'FaceColor', [0.95 0.85 0.4], 'EdgeColor', 'none');
            if isprop(rect, 'FaceAlpha')
                set(rect, 'FaceAlpha', 0.35);
            end
        end

        x_start = x_start + layout.required_width + gap_winding;
    end

    xpad = max(0.0005, 0.06 * bobbin.width);
    ypad = max(0.0008, 0.08 * bobbin.height);
    xlim(ax, [-xpad, bobbin.width + xpad]);
    ylim(ax, [-ypad, bobbin.height + ypad]);
    apply_window_axes_mm(ax, bobbin.width, bobbin.height, true);
    title(ax, '');
    hold(ax, 'off');

    cwf = get_cwf_window_metrics(data);
    set_vis_metrics_text(data, sprintf( ...
        'CWF window [mm^2] gross: %.2f  |  usable: %.2f (edge margin: %.2f mm)', ...
        cwf.area_m2*1e6, cwf.usable_area_m2*1e6, cwf.edge_margin_m*1e3));

    if total_fits
        info_str = sprintf('All windings FIT in core\nPattern: %s | CWF usable window: %.2f mm^2', ...
            pattern, cwf.usable_area_m2*1e6);
        color = [0.8 1.0 0.8];
    else
        info_str = sprintf('Windings DO NOT FIT\nTry smaller wire or fewer turns');
        color = [1.0 0.8 0.8];
    end

    set(findobj(data.fig_gui, 'Tag', 'vis_info'), 'String', info_str, 'BackgroundColor', color);
end

% ===============================================================
% RUN ANALYSIS (Issue #1 FIX: use layout positions)
% ===============================================================

function run_analysis(~, ~)
    fig = gcbf;
    data = guidata(fig);

    fprintf('\n=== RUNNING ANALYSIS ===\n');

    % Map OM-native winding orientation to analysis pattern
    if strcmp(data.om_winding_orientation, 'overlapping')
        pattern = 'orthocyclic';
    else
        pattern = 'layered';
    end

    ex_cfg = resolve_excitation_config(data);
    [ex_cfg, quality_meta] = apply_excitation_quality_preset(ex_cfg);

    analysis_meta = struct();
    if strcmp(ex_cfg.source, 'converter')
        % Converter excitation is locked to OM geometry by design.
        analysis_meta.requested_source = 'om';
    else
        analysis_meta.requested_source = resolve_analysis_source(data);
    end
    analysis_meta.used_source = analysis_meta.requested_source;
    analysis_meta.fallback_used = false;
    analysis_meta.fallback_reason = '';
    analysis_meta.pattern = pattern;
    analysis_meta.section_order = data.section_order;
    analysis_meta.om_winding_mode = '';
    analysis_meta.om_api_wind_success = false;
    analysis_meta.debug_dump_path = '';
    analysis_meta.excitation_source = ex_cfg.source;
    analysis_meta.excitation_sweep = ex_cfg.sweep_mode;
    analysis_meta.excitation_mode = ex_cfg.conduction_mode;
    analysis_meta.excitation_fallback_used = false;
    analysis_meta.excitation_fallback_reason = '';
    analysis_meta.excitation_profile_path = ex_cfg.profile_file;
    analysis_meta.analysis_mode = ex_cfg.analysis_mode;
    analysis_meta.quality_preset = ex_cfg.quality_preset;
    analysis_meta.quality_summary = quality_meta.summary;
    analysis_meta.prescreen_used = false;
    analysis_meta.prescreen_fallback_used = false;
    analysis_meta.prescreen_fallback_reason = '';
    analysis_meta.prescreen_summary = '';
    analysis_meta.prescreen_scored_points = 0;
    analysis_meta.prescreen_selected_points = 0;
    analysis_meta.peec_refine_top_n = ex_cfg.peec_refine_top_n;
    analysis_meta.peec_harmonic_cap = ex_cfg.peec_harmonic_cap;

    if strcmp(analysis_meta.requested_source, 'om')
        try
            [om_meta, om_err] = generate_om_meta_for_analysis(data);
            if ~isempty(om_err)
                error(om_err);
            end
            [all_conductors, all_winding_map, all_wire_shapes, geom_meta] = ...
                build_om_geometry_from_meta(data, om_meta);
            analysis_meta.used_source = 'om';
            analysis_meta.geometry_meta = geom_meta;
            if isfield(om_meta, 'winding') && isstruct(om_meta.winding)
                if isfield(om_meta.winding, 'winding_mode')
                    analysis_meta.om_winding_mode = char(om_meta.winding.winding_mode);
                end
                if isfield(om_meta.winding, 'api_wind_success')
                    analysis_meta.om_api_wind_success = logical(om_meta.winding.api_wind_success);
                end
            end
            fprintf('[ANALYSIS] Geometry source: OpenMagnetics turns metadata\n');
        catch ME
            fprintf('[ANALYSIS] OM geometry failed, falling back to CWF: %s\n', ME.message);
            analysis_meta.used_source = 'cwf';
            analysis_meta.fallback_used = true;
            analysis_meta.fallback_reason = ME.message;
            [all_conductors, all_winding_map, all_wire_shapes, geom_meta] = ...
                build_cwf_geometry_for_analysis(data, pattern);
            analysis_meta.geometry_meta = geom_meta;
        end
    else
        [all_conductors, all_winding_map, all_wire_shapes, geom_meta] = ...
            build_cwf_geometry_for_analysis(data, pattern);
        analysis_meta.geometry_meta = geom_meta;
        fprintf('[ANALYSIS] Geometry source: Core Window Fit layout\n');
    end

    try
        analysis_meta.debug_dump_path = write_analysis_geometry_dump( ...
            data, all_conductors, all_winding_map, all_wire_shapes, analysis_meta);
    catch
        analysis_meta.debug_dump_path = '';
    end

    fprintf('\nBuilding PEEC geometry with wire shapes...\n');
    fprintf('  Total conductors: %d\n', size(all_conductors, 1));

    geom = peec_build_geometry(all_conductors, data.sigma, data.mu0, ...
        data.Nx, data.Ny, all_winding_map, all_wire_shapes);

    fprintf('  Wire shapes: %d conductors\n', length(geom.wire_shapes));
    for i = 1:min(3, length(geom.wire_shapes))
        fprintf('    Conductor %d: %s\n', i, geom.wire_shapes{i});
    end

    excitation_profile = [];
    if strcmp(ex_cfg.source, 'converter')
        try
            [excitation_profile, ex_meta] = generate_converter_excitation_profile(data, ex_cfg);
            analysis_meta.excitation_generation = ex_meta;
            fprintf('[ANALYSIS] Excitation source: converter profile (%d operating points)\n', ...
                numel(excitation_profile.operating_points));
        catch ME
            analysis_meta.excitation_fallback_used = true;
            analysis_meta.excitation_fallback_reason = ME.message;
            fprintf('[ANALYSIS] Converter excitation failed, using manual RMS/phase: %s\n', ME.message);
            excitation_profile = build_manual_excitation_profile(data);
        end
    else
        excitation_profile = build_manual_excitation_profile(data);
        fprintf('[ANALYSIS] Excitation source: manual RMS/phase\n');
    end

    if ~isstruct(excitation_profile) || ~isfield(excitation_profile, 'operating_points') || isempty(excitation_profile.operating_points)
        analysis_meta.excitation_fallback_used = true;
        analysis_meta.excitation_fallback_reason = 'Excitation profile was empty.';
        excitation_profile = build_manual_excitation_profile(data);
    end

    run_opts = struct();
    run_opts.max_harmonics = ex_cfg.peec_harmonic_cap;
    run_opts.selected_indices = [];
    run_opts.analysis_mode = ex_cfg.analysis_mode;
    run_opts.quality_preset = ex_cfg.quality_preset;

    use_prescreen = strcmp(ex_cfg.source, 'converter') && strcmp(analysis_meta.used_source, 'om') ...
        && ~strcmp(ex_cfg.analysis_mode, 'peec_only');
    if use_prescreen
        try
            [ranked_indices, pres_meta] = run_om_prescreen_for_profile(data, ex_cfg, excitation_profile);
            top_n = min(max(1, ex_cfg.peec_refine_top_n), numel(ranked_indices));
            run_opts.selected_indices = ranked_indices(1:top_n);
            analysis_meta.prescreen_used = true;
            analysis_meta.prescreen_summary = pres_meta.summary;
            analysis_meta.prescreen_scored_points = pres_meta.scored_points;
            analysis_meta.prescreen_selected_points = numel(run_opts.selected_indices);
            fprintf('[ANALYSIS] OM pre-screen selected %d/%d operating points for PEEC refine\n', ...
                numel(run_opts.selected_indices), pres_meta.scored_points);

            if strcmp(ex_cfg.analysis_mode, 'om_only')
                % OM-only mode is represented as a top-1 PEEC refine so result plots
                % remain available while runtime is minimized.
                run_opts.selected_indices = run_opts.selected_indices(1);
                analysis_meta.analysis_mode = 'om_only(top1_peec)';
            end
        catch ME
            analysis_meta.prescreen_fallback_used = true;
            analysis_meta.prescreen_fallback_reason = ME.message;
            fprintf('[ANALYSIS] OM pre-screen failed, running PEEC on full set: %s\n', ME.message);
        end
    end

    analysis_run = run_peec_with_excitation_profile( ...
        data, geom, all_conductors, all_winding_map, excitation_profile, run_opts);
    analysis_meta.excitation_summary = analysis_run.excitation_summary;
    analysis_meta.excitation_operating_points = numel(excitation_profile.operating_points);
    if isfield(analysis_run, 'evaluated_operating_points')
        analysis_meta.evaluated_operating_points = analysis_run.evaluated_operating_points;
    end
    if isfield(analysis_run, 'total_operating_points')
        analysis_meta.total_operating_points = analysis_run.total_operating_points;
    end
    if isfield(analysis_run, 'selected_operating_indices')
        analysis_meta.selected_operating_indices = analysis_run.selected_operating_indices;
    end
    if isfield(analysis_run, 'worst_source_index')
        analysis_meta.worst_source_index = analysis_run.worst_source_index;
    end
    if isfield(analysis_run, 'best_source_index')
        analysis_meta.best_source_index = analysis_run.best_source_index;
    end
    if isfield(analysis_run, 'worst_name')
        analysis_meta.worst_operating_point_name = analysis_run.worst_name;
    end
    if isfield(analysis_run, 'best_name')
        analysis_meta.best_operating_point_name = analysis_run.best_name;
    end
    if isfield(analysis_run, 'total_loss')
        analysis_meta.worst_total_loss_w = analysis_run.total_loss;
    end
    if isfield(analysis_run, 'best_total_loss')
        analysis_meta.best_total_loss_w = analysis_run.best_total_loss;
    end

    % Re-write dump with final operating-point selection and case metadata.
    try
        analysis_meta.debug_dump_path = write_analysis_geometry_dump( ...
            data, all_conductors, all_winding_map, all_wire_shapes, analysis_meta, analysis_run);
    catch
    end

    % --- Compute magnetic parameters (Lm, Llk, Bpk, core loss) ---
    try
        fprintf('\n[ANALYSIS] Computing magnetic parameters (Lm, Llk, Bpk, core loss)...\n');
        mag_results = compute_magnetic_params(data, geom);
        analysis_run.mag_results = mag_results;
        if mag_results.valid
            fprintf('  Lm = %.2f uH (%s), Llk_pri = %.3f uH (PEEC), k = %.4f\n', ...
                mag_results.Lm_H*1e6, mag_results.Lm_source, ...
                mag_results.Llk_pri_H*1e6, mag_results.coupling_k);
            if isfield(mag_results, 'R_core') && mag_results.R_core > 0
                R_pct = mag_results.R_gap_total / mag_results.R_total * 100;
                fprintf('  Reluctance: R_core=%.0f, R_gap=%.0f (%.1f%%), R_total=%.0f [H^-1]\n', ...
                    mag_results.R_core, mag_results.R_gap_total, R_pct, mag_results.R_total);
            end
            fprintf('  Bpk = %.1f mT, deltaB = %.1f mT\n', ...
                mag_results.Bpk_T*1e3, mag_results.deltaB_T*1e3);
            fprintf('  Core loss (%s) = %.3f W\n', mag_results.method, mag_results.Pcore_W);
        else
            fprintf('  Magnetic parameter computation did not complete.\n');
        end
    catch ME
        fprintf('  Magnetic parameter computation failed: %s\n', ME.message);
        analysis_run.mag_results = struct('valid', false);
    end

    % --- Attach MKF reference values from topology wizard recommendation ---
    analysis_run.mkf_ref = struct('valid', false);
    if isfield(data, 'design_spec') && ~isempty(data.design_spec)
        spec = data.design_spec;
        if isfield(spec, 'recommendation') && isstruct(spec.recommendation)
            rec = spec.recommendation;
            mkf = struct('valid', true);
            if isfield(rec, 'Lm_uH'), mkf.Lm_uH = rec.Lm_uH; else mkf.Lm_uH = 0; end
            if isfield(rec, 'Llk_uH'), mkf.Llk_uH = rec.Llk_uH; else mkf.Llk_uH = 0; end
            if isfield(rec, 'B_peak_mT'), mkf.B_peak_mT = rec.B_peak_mT; else mkf.B_peak_mT = 0; end
            if isfield(rec, 'B_pp_mT'), mkf.B_pp_mT = rec.B_pp_mT; else mkf.B_pp_mT = 0; end
            if isfield(rec, 'core_loss_W'), mkf.core_loss_W = rec.core_loss_W; else mkf.core_loss_W = 0; end
            if isfield(rec, 'winding_loss_W'), mkf.winding_loss_W = rec.winding_loss_W; else mkf.winding_loss_W = 0; end
            analysis_run.mkf_ref = mkf;
        end
    end

    display_results(data, geom, analysis_run.plot_conductors, all_winding_map, ...
        analysis_run.plot_results, analysis_meta, analysis_run);
end

function source = resolve_analysis_source(data)
    % Default analysis source: active view.
    source = 'cwf';
    try
        vis_mode = get(findobj(data.fig_gui, 'Tag', 'vis_mode'), 'Value');
        if vis_mode == 3
            source = 'om';
        else
            source = 'cwf';
        end
    catch
        source = 'cwf';
    end
end

function ex_cfg = resolve_excitation_config(data)
    ex_cfg = struct();
    ex_cfg.source = 'manual';
    ex_cfg.topology = 'two_switch_forward';
    ex_cfg.conduction_mode = 'ccm+dcm';
    ex_cfg.sweep_mode = 'grid';
    ex_cfg.duty_mode = 'derived';
    ex_cfg.manual_duty = 0.40;
    ex_cfg.line_scales = [0.90, 1.00, 1.10];
    ex_cfg.load_scales = [0.50, 0.75, 1.00];
    ex_cfg.harmonic_energy_pct = 99.5;
    ex_cfg.harmonic_max_order = 60;
    ex_cfg.small_harmonic_pct = 1.0;
    ex_cfg.small_harmonic_consecutive = 5;
    ex_cfg.analysis_mode = 'hybrid';
    ex_cfg.quality_preset = 'standard';
    ex_cfg.peec_refine_top_n = 6;
    ex_cfg.peec_harmonic_cap = 24;
    ex_cfg.prescreen_waveform_samples = 128;
    ex_cfg.prescreen_temperature_c = 25;
    ex_cfg.use_cache = true;
    ex_cfg.use_import = false;
    ex_cfg.profile_file = fullfile(pwd(), 'om_excitation_profile.json');
    ex_cfg.cache_file = fullfile(pwd(), 'om_excitation_cache.json');

    if isfield(data, 'excitation') && isstruct(data.excitation)
        ex_user = data.excitation;
        fields = fieldnames(ex_cfg);
        for i = 1:numel(fields)
            f = fields{i};
            if isfield(ex_user, f)
                ex_cfg.(f) = ex_user.(f);
            end
        end
    end

    if ~ischar(ex_cfg.source) && ~isstring(ex_cfg.source)
        ex_cfg.source = 'manual';
    end
    if ~ischar(ex_cfg.profile_file) && ~isstring(ex_cfg.profile_file)
        ex_cfg.profile_file = fullfile(pwd(), 'om_excitation_profile.json');
    end
    if ~ischar(ex_cfg.cache_file) && ~isstring(ex_cfg.cache_file)
        ex_cfg.cache_file = fullfile(pwd(), 'om_excitation_cache.json');
    end

    if ~ischar(ex_cfg.analysis_mode) && ~isstring(ex_cfg.analysis_mode)
        ex_cfg.analysis_mode = 'hybrid';
    end
    ex_cfg.analysis_mode = lower(strtrim(char(ex_cfg.analysis_mode)));
    if ~any(strcmp(ex_cfg.analysis_mode, {'peec_only', 'hybrid', 'om_only'}))
        ex_cfg.analysis_mode = 'hybrid';
    end

    if ~ischar(ex_cfg.quality_preset) && ~isstring(ex_cfg.quality_preset)
        ex_cfg.quality_preset = 'standard';
    end
    ex_cfg.quality_preset = lower(strtrim(char(ex_cfg.quality_preset)));
    if ~any(strcmp(ex_cfg.quality_preset, {'fast', 'standard', 'high'}))
        ex_cfg.quality_preset = 'standard';
    end

    ex_cfg.peec_refine_top_n = max(1, round(double(ex_cfg.peec_refine_top_n)));
    ex_cfg.peec_harmonic_cap = max(0, round(double(ex_cfg.peec_harmonic_cap)));
    ex_cfg.prescreen_waveform_samples = max(64, round(double(ex_cfg.prescreen_waveform_samples)));
    ex_cfg.prescreen_temperature_c = double(ex_cfg.prescreen_temperature_c);
    if isnan(ex_cfg.prescreen_temperature_c)
        ex_cfg.prescreen_temperature_c = 25;
    end
end

function [ex_cfg, preset_meta] = apply_excitation_quality_preset(ex_cfg)
    preset = lower(strtrim(char(ex_cfg.quality_preset)));
    preset_meta = struct();
    preset_meta.name = preset;
    preset_meta.summary = '';

    switch preset
        case 'fast'
            ex_cfg.harmonic_energy_pct = 97.0;
            ex_cfg.harmonic_max_order = 24;
            ex_cfg.small_harmonic_pct = 2.0;
            ex_cfg.small_harmonic_consecutive = 3;
            ex_cfg.peec_refine_top_n = min(ex_cfg.peec_refine_top_n, 3);
            if ex_cfg.peec_harmonic_cap <= 0 || ex_cfg.peec_harmonic_cap > 12
                ex_cfg.peec_harmonic_cap = 12;
            end
            ex_cfg.prescreen_waveform_samples = min(max(ex_cfg.prescreen_waveform_samples, 64), 96);
            preset_meta.summary = 'Fast preset: top-3 PEEC refine, harmonic cap 12';

        case 'high'
            ex_cfg.harmonic_energy_pct = 99.8;
            ex_cfg.harmonic_max_order = 100;
            ex_cfg.small_harmonic_pct = 0.5;
            ex_cfg.small_harmonic_consecutive = 8;
            ex_cfg.peec_refine_top_n = max(ex_cfg.peec_refine_top_n, 10);
            if ex_cfg.peec_harmonic_cap <= 0
                ex_cfg.peec_harmonic_cap = 0;
            else
                ex_cfg.peec_harmonic_cap = max(ex_cfg.peec_harmonic_cap, 40);
            end
            ex_cfg.prescreen_waveform_samples = max(ex_cfg.prescreen_waveform_samples, 192);
            preset_meta.summary = 'High preset: top-10 PEEC refine, dense harmonics';

        otherwise
            ex_cfg.quality_preset = 'standard';
            ex_cfg.harmonic_energy_pct = 99.5;
            ex_cfg.harmonic_max_order = 60;
            ex_cfg.small_harmonic_pct = 1.0;
            ex_cfg.small_harmonic_consecutive = 5;
            ex_cfg.peec_refine_top_n = min(max(ex_cfg.peec_refine_top_n, 4), 8);
            if ex_cfg.peec_harmonic_cap <= 0 || ex_cfg.peec_harmonic_cap > 24
                ex_cfg.peec_harmonic_cap = 24;
            end
            ex_cfg.prescreen_waveform_samples = min(max(ex_cfg.prescreen_waveform_samples, 96), 160);
            preset_meta.summary = 'Standard preset: top-6 PEEC refine, harmonic cap 24';
    end
end

function profile = build_manual_excitation_profile(data)
    n_w = data.n_windings;
    i_re = zeros(1, n_w);
    i_im = zeros(1, n_w);
    v_re = zeros(1, n_w);
    v_im = zeros(1, n_w);
    rms_i = zeros(1, n_w);
    rms_v = zeros(1, n_w);
    for w = 1:n_w
        i_mag = data.windings(w).current;
        i_ph = data.windings(w).phase;
        v_mag = 0;
        if isfield(data.windings(w), 'voltage')
            v_mag = data.windings(w).voltage;
        end
        i_complex = i_mag * exp(1j * i_ph * pi / 180);
        v_complex = v_mag * exp(1j * i_ph * pi / 180);
        i_re(w) = real(i_complex);
        i_im(w) = imag(i_complex);
        v_re(w) = real(v_complex);
        v_im(w) = imag(v_complex);
        rms_i(w) = abs(i_mag);
        rms_v(w) = abs(v_mag);
    end

    harmonic = struct();
    harmonic.order = 1;
    harmonic.frequency_hz = data.f;
    harmonic.currents_real_a = i_re;
    harmonic.currents_imag_a = i_im;
    harmonic.voltages_real_v = v_re;
    harmonic.voltages_imag_v = v_im;

    op = struct();
    op.name = 'manual_nominal';
    op.line_scale = 1.0;
    op.load_scale = 1.0;
    op.conduction_mode = 'manual';
    op.frequency_hz = data.f;
    op.duty = NaN;
    op.rms_currents_a = rms_i;
    op.rms_voltages_v = rms_v;
    op.harmonic_count = 1;
    op.harmonics = harmonic;
    op.processed_summary = struct('ok', false, 'error', 'manual excitation');

    profile = struct();
    profile.status = 'OK';
    profile.source = 'manual_rms_phase';
    profile.topology = 'manual';
    profile.sweep_mode = 'nominal';
    profile.conduction_mode = 'manual';
    profile.frequency_hz = data.f;
    profile.operating_points = op;
end

function [profile, meta] = generate_converter_excitation_profile(data, ex_cfg)
    profile = struct();
    meta = struct();

    script_dir = pwd();
    profile_path = char(ex_cfg.profile_file);
    if isempty(profile_path)
        profile_path = fullfile(script_dir, 'om_excitation_profile.json');
    elseif isempty(fileparts(profile_path))
        profile_path = fullfile(script_dir, profile_path);
    end
    cache_path = char(ex_cfg.cache_file);
    if isempty(cache_path)
        cache_path = fullfile(script_dir, 'om_excitation_cache.json');
    elseif isempty(fileparts(cache_path))
        cache_path = fullfile(script_dir, cache_path);
    end

    if logical(ex_cfg.use_import) && exist(profile_path, 'file')
        fid = fopen(profile_path, 'r');
        if fid ~= -1
            raw = fread(fid, '*char')';
            fclose(fid);
            profile = jsondecode(raw);
            meta.loaded_from_import = true;
            meta.profile_path = profile_path;
            if isfield(profile, 'status') && strcmpi(char(profile.status), 'OK')
                return;
            end
        end
    end

    cfg = struct();
    cfg.source_mode = 'converter';
    cfg.topology = ex_cfg.topology;
    cfg.frequency_hz = data.f;
    cfg.conduction_mode = ex_cfg.conduction_mode;
    cfg.sweep_mode = ex_cfg.sweep_mode;
    cfg.duty_mode = ex_cfg.duty_mode;
    cfg.manual_duty = ex_cfg.manual_duty;
    cfg.line_scales = ex_cfg.line_scales;
    cfg.load_scales = ex_cfg.load_scales;
    cfg.harmonic_energy_pct = ex_cfg.harmonic_energy_pct;
    cfg.harmonic_max_order = ex_cfg.harmonic_max_order;
    cfg.small_harmonic_pct = ex_cfg.small_harmonic_pct;
    cfg.small_harmonic_consecutive = ex_cfg.small_harmonic_consecutive;
    cfg.use_cache = logical(ex_cfg.use_cache);
    cfg.use_import = false;
    cfg.import_file = profile_path;
    cfg.output_file = profile_path;
    cfg.cache_file = cache_path;
    cfg.samples_per_period = 1024;

    windings = cell(1, data.n_windings);
    for w = 1:data.n_windings
        winding = struct();
        winding.name = data.windings(w).name;
        winding.n_turns = data.windings(w).n_turns;
        winding.n_parallels = data.windings(w).n_filar;
        winding.rms_current_a = data.windings(w).current;
        winding.phase_deg = data.windings(w).phase;
        v = 0;
        if isfield(data.windings(w), 'voltage')
            v = data.windings(w).voltage;
        end
        winding.rms_voltage_v = abs(v);
        if w == 1
            winding.isolation_side = 'primary';
        else
            winding.isolation_side = 'secondary';
        end
        windings{w} = winding;
    end
    cfg.windings = windings;

    cfg_file = fullfile(script_dir, 'om_excitation_config.json');
    fid = fopen(cfg_file, 'w');
    if fid == -1
        error('Cannot write excitation config file: %s', cfg_file);
    end
    fwrite(fid, jsonencode(cfg));
    fclose(fid);

    py_script_name = 'generate_om_excitation.py';
    if ~exist(fullfile(script_dir, py_script_name), 'file')
        error('Python script "%s" not found in %s', py_script_name, script_dir);
    end

    python_cmd = 'python';
    venv_python = fullfile(script_dir, '.venv', 'Scripts', 'python.exe');
    if exist(venv_python, 'file')
        python_cmd = ['"' venv_python '"'];
    end

    cmd = sprintf('%s "%s" "%s" 2>&1', python_cmd, py_script_name, 'om_excitation_config.json');
    [status, output] = system(cmd);
    is_module_error = ~isempty(strfind(output, 'ModuleNotFoundError')) || ...
                      ~isempty(strfind(output, 'ImportError')) || ...
                      ~isempty(strfind(output, 'No module named'));

    if status ~= 0 && is_module_error && ispc
        cmd_fb = sprintf('py "%s" "%s" 2>&1', py_script_name, 'om_excitation_config.json');
        [status_fb, output_fb] = system(cmd_fb);
        if status_fb == 0 && ~isempty(strfind(output_fb, 'OK'))
            status = status_fb;
            output = output_fb;
        end
    end

    if status ~= 0 && is_module_error && ispc
        [~, py_paths_str] = system('where python');
        py_paths = strsplit(strtrim(py_paths_str), char(10));
        for i = 1:length(py_paths)
            p = strtrim(py_paths{i});
            if isempty(p); continue; end
            if ~isempty(strfind(lower(p), 'octave')) || ~isempty(strfind(lower(p), 'usr\bin'))
                continue;
            end
            cmd_alt = sprintf('"%s" "%s" "%s" 2>&1', p, py_script_name, 'om_excitation_config.json');
            [status_alt, output_alt] = system(cmd_alt);
            if status_alt == 0 && ~isempty(strfind(output_alt, 'OK'))
                status = status_alt;
                output = output_alt;
                break;
            end
        end
    end

    if status ~= 0 || isempty(strfind(strtrim(output), 'OK'))
        error('Excitation python failed (exit=%d): %s', status, strtrim(output));
    end

    if ~exist(profile_path, 'file')
        error('Excitation profile file not found: %s', profile_path);
    end

    fidr = fopen(profile_path, 'r');
    if fidr == -1
        error('Cannot read excitation profile file: %s', profile_path);
    end
    raw = fread(fidr, '*char')';
    fclose(fidr);
    profile = jsondecode(raw);

    if ~isfield(profile, 'status') || ~strcmpi(char(profile.status), 'OK')
        err_msg = 'unknown excitation generation error';
        if isfield(profile, 'error')
            err_msg = char(profile.error);
        end
        error('Excitation profile status not OK: %s', err_msg);
    end
    if ~isfield(profile, 'operating_points') || isempty(profile.operating_points)
        error('Excitation profile has no operating points');
    end

    meta.loaded_from_import = false;
    meta.profile_path = profile_path;
end

function [ranked_indices, pres_meta] = run_om_prescreen_for_profile(data, ex_cfg, profile)
    ranked_indices = [];
    pres_meta = struct();
    pres_meta.scored_points = 0;
    pres_meta.summary = '';

    ops = profile.operating_points;
    if iscell(ops)
        try
            ops = [ops{:}];
        catch
            ops = struct([]);
        end
    end
    if isempty(ops)
        error('Excitation profile has no operating points to pre-screen');
    end

    script_dir = pwd();
    om_cfg_file = fullfile(script_dir, 'om_viz_config_prescreen.json');
    ex_profile_file = fullfile(script_dir, 'om_excitation_profile_for_prescreen.json');
    pres_cfg_file = fullfile(script_dir, 'om_prescreen_config.json');
    pres_out_file = fullfile(script_dir, 'om_prescreen_losses.json');

    om_cfg = build_om_viz_config(data);
    if isfield(om_cfg, 'output_svg')
        om_cfg = rmfield(om_cfg, 'output_svg');
    end
    if isfield(om_cfg, 'output_meta')
        om_cfg = rmfield(om_cfg, 'output_meta');
    end

    fid = fopen(om_cfg_file, 'w');
    if fid == -1
        error('Cannot write OM pre-screen config: %s', om_cfg_file);
    end
    fwrite(fid, jsonencode(om_cfg));
    fclose(fid);

    fid = fopen(ex_profile_file, 'w');
    if fid == -1
        error('Cannot write excitation profile for pre-screen: %s', ex_profile_file);
    end
    fwrite(fid, jsonencode(profile));
    fclose(fid);

    pres_cfg = struct();
    pres_cfg.om_config_file = strrep(om_cfg_file, '\', '/');
    pres_cfg.excitation_profile_file = strrep(ex_profile_file, '\', '/');
    pres_cfg.output_file = strrep(pres_out_file, '\', '/');
    pres_cfg.waveform_samples = ex_cfg.prescreen_waveform_samples;
    pres_cfg.temperature_c = ex_cfg.prescreen_temperature_c;
    pres_cfg.max_harmonics_for_waveform = ex_cfg.peec_harmonic_cap;
    pres_cfg.default_frequency_hz = data.f;
    pres_cfg.topology = '2-switch forward';

    fid = fopen(pres_cfg_file, 'w');
    if fid == -1
        error('Cannot write pre-screen request file: %s', pres_cfg_file);
    end
    fwrite(fid, jsonencode(pres_cfg));
    fclose(fid);

    py_script_name = 'generate_om_prescreen_losses.py';
    if ~exist(fullfile(script_dir, py_script_name), 'file')
        error('Pre-screen python script "%s" not found in %s', py_script_name, script_dir);
    end

    python_cmd = 'python';
    venv_python = fullfile(script_dir, '.venv', 'Scripts', 'python.exe');
    if exist(venv_python, 'file')
        python_cmd = ['"' venv_python '"'];
    end

    cfg_arg = strrep(pres_cfg_file, '\', '/');
    cmd = sprintf('%s "%s" "%s" 2>&1', python_cmd, py_script_name, cfg_arg);
    [status, output] = system(cmd);
    is_module_error = ~isempty(strfind(output, 'ModuleNotFoundError')) || ...
                      ~isempty(strfind(output, 'ImportError')) || ...
                      ~isempty(strfind(output, 'No module named'));

    if status ~= 0 && is_module_error && ispc
        cmd_fb = sprintf('py "%s" "%s" 2>&1', py_script_name, cfg_arg);
        [status_fb, output_fb] = system(cmd_fb);
        if status_fb == 0 && ~isempty(strfind(output_fb, 'OK'))
            status = status_fb;
            output = output_fb;
        end
    end

    if status ~= 0 && is_module_error && ispc
        [~, py_paths_str] = system('where python');
        py_paths = strsplit(strtrim(py_paths_str), char(10));
        for i = 1:length(py_paths)
            p = strtrim(py_paths{i});
            if isempty(p); continue; end
            if ~isempty(strfind(lower(p), 'octave')) || ~isempty(strfind(lower(p), 'usr\bin'))
                continue;
            end
            cmd_alt = sprintf('"%s" "%s" "%s" 2>&1', p, py_script_name, cfg_arg);
            [status_alt, output_alt] = system(cmd_alt);
            if status_alt == 0 && ~isempty(strfind(output_alt, 'OK'))
                status = status_alt;
                output = output_alt;
                break;
            end
        end
    end

    if status ~= 0 || isempty(strfind(strtrim(output), 'OK'))
        error('OM pre-screen python failed (exit=%d): %s', status, strtrim(output));
    end

    if ~exist(pres_out_file, 'file')
        error('OM pre-screen output file not found: %s', pres_out_file);
    end
    fid = fopen(pres_out_file, 'r');
    if fid == -1
        error('Cannot read OM pre-screen output file: %s', pres_out_file);
    end
    raw = fread(fid, '*char')';
    fclose(fid);
    pres_out = jsondecode(raw);

    if ~isfield(pres_out, 'status') || ~strcmpi(char(pres_out.status), 'OK')
        err_msg = 'unknown OM pre-screen error';
        if isfield(pres_out, 'error')
            err_msg = char(pres_out.error);
        end
        error('OM pre-screen status not OK: %s', err_msg);
    end
    if ~isfield(pres_out, 'ranked_indices') || isempty(pres_out.ranked_indices)
        error('OM pre-screen returned no ranked operating points');
    end

    ranked = pres_out.ranked_indices;
    if iscell(ranked)
        tmp = zeros(1, numel(ranked));
        for i = 1:numel(ranked)
            if isnumeric(ranked{i})
                tmp(i) = double(ranked{i});
            else
                tmp(i) = str2double(char(ranked{i}));
            end
            if isnan(tmp(i))
                tmp(i) = 0;
            end
        end
        ranked = tmp;
    end
    ranked = double(ranked(:)');
    ranked = ranked(ranked >= 1 & ranked <= numel(ops));
    ranked = unique(round(ranked), 'stable');
    if isempty(ranked)
        error('OM pre-screen ranking was empty after validation');
    end

    ranked_indices = ranked;
    pres_meta.scored_points = numel(ops);
    if isfield(pres_out, 'scored_operating_points')
        pres_meta.scored_points = double(pres_out.scored_operating_points);
        if isnan(pres_meta.scored_points) || pres_meta.scored_points <= 0
            pres_meta.scored_points = numel(ops);
        end
    end
    fallback_count = 0;
    if isfield(pres_out, 'fallback_count')
        fallback_count = double(pres_out.fallback_count);
    end
    pres_meta.summary = sprintf('OM pre-screen ranked %d points (fallback=%d)', ...
        pres_meta.scored_points, fallback_count);
end

function analysis_run = run_peec_with_excitation_profile(data, geom, conductors_template, winding_map, profile, run_opts)
    n_w = data.n_windings;
    winding_rdc = compute_winding_rdc_from_geometry(data, conductors_template, winding_map);

    ops = profile.operating_points;
    if iscell(ops)
        try
            ops = [ops{:}];
        catch
            ops = struct([]);
        end
    end
    if isempty(ops)
        error('Excitation profile has no valid operating points');
    end

    if nargin < 6 || ~isstruct(run_opts)
        run_opts = struct();
    end
    selected_indices = 1:numel(ops);
    if isfield(run_opts, 'selected_indices') && ~isempty(run_opts.selected_indices)
        sel = double(run_opts.selected_indices(:)');
        sel = sel(sel >= 1 & sel <= numel(ops));
        if ~isempty(sel)
            selected_indices = unique(round(sel), 'stable');
        end
    end
    max_harmonics = 0;
    if isfield(run_opts, 'max_harmonics')
        max_harmonics = max(0, round(double(run_opts.max_harmonics)));
    end

    op_runs = repmat(struct(), 1, numel(selected_indices));
    for oi = 1:numel(selected_indices)
        op_idx = selected_indices(oi);
        op = ops(op_idx);
        op_name = sprintf('op_%d', op_idx);
        if isfield(op, 'name') && ~isempty(op.name)
            op_name = char(op.name);
        end
        h_list = [];
        if isfield(op, 'harmonics')
            h_list = op.harmonics;
        end
        if iscell(h_list)
            try
                h_list = [h_list{:}];
            catch
                h_list = struct([]);
            end
        end
        if isempty(h_list)
            error('Operating point "%s" has no harmonics', op_name);
        end
        if max_harmonics > 0 && numel(h_list) > max_harmonics
            h_list = h_list(1:max_harmonics);
        end

        op_ac_loss = zeros(n_w, 1);
        op_total_loss = 0;
        solved_harmonics = 0;
        plot_results = [];
        plot_conductors = conductors_template;

        for hi = 1:numel(h_list)
            harmonic = h_list(hi);
            f_h = data.f;
            if isfield(harmonic, 'frequency_hz')
                f_h = double(harmonic.frequency_hz);
            end
            if f_h <= 0
                continue;
            end

            cond_h = apply_harmonic_to_conductors(data, conductors_template, winding_map, harmonic);
            if isempty(cond_h) || max(cond_h(:,5)) <= 0
                continue;
            end

            results_h = peec_solve_frequency(geom, cond_h, f_h, data.sigma, data.mu0);
            op_total_loss = op_total_loss + results_h.P_total;
            op_ac_loss = op_ac_loss + accumulate_winding_losses(results_h.P_fil, winding_map, data.Nx, data.Ny, n_w);
            solved_harmonics = solved_harmonics + 1;

            ord = hi;
            if isfield(harmonic, 'order')
                ord = double(harmonic.order);
            end
            if isempty(plot_results) || ord == 1
                plot_results = results_h;
                plot_conductors = cond_h;
            end
        end

        if solved_harmonics == 0
            error('Operating point "%s" produced no solvable harmonics', op_name);
        end

        rms_currents = extract_op_rms_currents(op, h_list, data);
        op_dc_loss = 0.5 * (rms_currents .^ 2) .* winding_rdc;
        rac_rdc = op_ac_loss ./ max(op_dc_loss, 1e-12);

        op_runs(oi).name = op_name;
        op_runs(oi).total_loss = op_total_loss;
        op_runs(oi).ac_loss = op_ac_loss;
        op_runs(oi).dc_loss = op_dc_loss;
        op_runs(oi).rac_rdc = rac_rdc;
        op_runs(oi).harmonic_count = solved_harmonics;
        op_runs(oi).source_index = op_idx;
        op_runs(oi).plot_results = plot_results;
        op_runs(oi).plot_conductors = plot_conductors;
        % Keep operating-point context for result reporting (best/worst case details).
        op_runs(oi).line_scale = get_struct_numeric(op, 'line_scale', NaN);
        op_runs(oi).load_scale = get_struct_numeric(op, 'load_scale', NaN);
        op_runs(oi).duty = get_struct_numeric(op, 'duty', NaN);
        op_runs(oi).frequency_hz = get_struct_numeric(op, 'frequency_hz', data.f);
        op_runs(oi).conduction_mode = get_struct_string(op, 'conduction_mode', 'n/a');
        op_runs(oi).rms_currents_a = to_numeric_vector(get_struct_field(op, 'rms_currents_a', []), n_w, zeros(n_w, 1));
        op_runs(oi).rms_voltages_v = to_numeric_vector(get_struct_field(op, 'rms_voltages_v', []), n_w, zeros(n_w, 1));
    end

    losses = zeros(1, numel(op_runs));
    for i = 1:numel(op_runs)
        losses(i) = op_runs(i).total_loss;
    end
    [~, worst_idx] = max(losses);
    worst = op_runs(worst_idx);
    [~, best_idx] = min(losses);
    best = op_runs(best_idx);

    analysis_run = struct();
    analysis_run.mode = 'harmonic_sweep';
    analysis_run.operating_points = op_runs;
    analysis_run.worst_index = worst_idx;
    analysis_run.worst_name = worst.name;
    analysis_run.best_index = best_idx;
    analysis_run.best_name = best.name;
    analysis_run.winding_ac_loss = worst.ac_loss;
    analysis_run.winding_dc_loss = worst.dc_loss;
    analysis_run.winding_rdc = winding_rdc;
    analysis_run.winding_rac_rdc = worst.rac_rdc;
    analysis_run.total_loss = worst.total_loss;
    analysis_run.best_total_loss = best.total_loss;
    analysis_run.worst_source_index = worst.source_index;
    analysis_run.best_source_index = best.source_index;
    analysis_run.worst_harmonic_count = worst.harmonic_count;
    analysis_run.best_harmonic_count = best.harmonic_count;
    analysis_run.best_winding_ac_loss = best.ac_loss;
    analysis_run.best_winding_dc_loss = best.dc_loss;
    analysis_run.best_winding_rac_rdc = best.rac_rdc;
    analysis_run.best_plot_results = best.plot_results;
    analysis_run.best_plot_conductors = best.plot_conductors;
    analysis_run.plot_results = worst.plot_results;
    analysis_run.plot_conductors = worst.plot_conductors;
    analysis_run.selected_operating_indices = selected_indices;
    analysis_run.total_operating_points = numel(ops);
    analysis_run.evaluated_operating_points = numel(selected_indices);
    analysis_run.max_harmonics = max_harmonics;
    src_name = 'UNKNOWN';
    if isfield(profile, 'source') && ~isempty(profile.source)
        src_name = upper(char(profile.source));
    end
    summary = sprintf( ...
        'Excitation: %s | Operating points: %d/%d | Plotted(worst): %s | Best: %s', ...
        src_name, numel(op_runs), numel(ops), worst.name, best.name);
    if max_harmonics > 0
        summary = sprintf('%s | Harmonic cap: %d', summary, max_harmonics);
    end
    analysis_run.excitation_summary = summary;
end

function winding_rdc = compute_winding_rdc_from_geometry(data, conductors, winding_map)
    n_w = data.n_windings;
    winding_rdc = zeros(n_w, 1);
    for w = 1:n_w
        cond_idx = find(winding_map == w);
        if isempty(cond_idx)
            [w_dim, h_dim] = data.api.wire_to_conductor_dims(data.windings(w).wire_type);
            area = max(1e-12, w_dim * h_dim);
        else
            area = max(1e-12, mean(conductors(cond_idx, 3) .* conductors(cond_idx, 4)));
        end
        winding_rdc(w) = (data.windings(w).n_turns / max(1, data.windings(w).n_filar)) / (data.sigma * area);
    end
end

function losses = accumulate_winding_losses(P_fil, winding_map, Nx, Ny, n_w)
    losses = zeros(n_w, 1);
    fils_per_cond = Nx * Ny;
    n_cond = numel(winding_map);
    for c = 1:n_cond
        w = winding_map(c);
        if w < 1 || w > n_w
            continue;
        end
        idx_start = (c - 1) * fils_per_cond + 1;
        idx_end = c * fils_per_cond;
        if idx_end <= numel(P_fil)
            losses(w) = losses(w) + sum(P_fil(idx_start:idx_end));
        end
    end
end

function cond_out = apply_harmonic_to_conductors(data, cond_in, winding_map, harmonic)
    cond_out = cond_in;
    n_w = data.n_windings;
    i_re = zeros(n_w, 1);
    i_im = zeros(n_w, 1);
    if isfield(harmonic, 'currents_real_a')
        i_re = to_numeric_vector(harmonic.currents_real_a, n_w, zeros(n_w, 1));
    end
    if isfield(harmonic, 'currents_imag_a')
        i_im = to_numeric_vector(harmonic.currents_imag_a, n_w, zeros(n_w, 1));
    end

    for c = 1:size(cond_out, 1)
        if c <= numel(winding_map)
            w = winding_map(c);
        else
            w = 1;
        end
        if w < 1 || w > n_w
            continue;
        end
        Iw = complex(i_re(w), i_im(w));
        n_filar = max(1, data.windings(w).n_filar);
        Istrand = Iw / n_filar;
        cond_out(c, 5) = abs(Istrand);
        cond_out(c, 6) = angle(Istrand) * 180 / pi;
    end
end

function vec = to_numeric_vector(value, n, default_vec)
    vec = default_vec(:);
    if nargin < 3 || isempty(default_vec)
        vec = zeros(n, 1);
    end
    vals = [];
    if isnumeric(value)
        vals = value(:);
    elseif iscell(value)
        vals = zeros(numel(value), 1);
        for i = 1:numel(value)
            if isnumeric(value{i})
                vals(i) = value{i};
            else
                vals(i) = str2double(char(value{i}));
            end
            if isnan(vals(i))
                vals(i) = 0;
            end
        end
    end
    m = min(n, numel(vals));
    if m > 0
        vec(1:m) = vals(1:m);
    end
end

function val = get_struct_field(s, field_name, default_val)
    val = default_val;
    if isstruct(s) && isfield(s, field_name)
        val = s.(field_name);
    end
end

function v = get_struct_numeric(s, field_name, default_val)
    v = default_val;
    if ~(isstruct(s) && isfield(s, field_name))
        return;
    end
    raw = s.(field_name);
    if isnumeric(raw)
        if isempty(raw)
            return;
        end
        v = double(raw(1));
        return;
    end
    if ischar(raw) || isstring(raw)
        tmp = str2double(char(raw));
        if ~isnan(tmp)
            v = tmp;
        end
    end
end

function txt = get_struct_string(s, field_name, default_val)
    txt = default_val;
    if ~(isstruct(s) && isfield(s, field_name))
        return;
    end
    raw = s.(field_name);
    if ischar(raw)
        txt = raw;
    elseif isstring(raw)
        txt = char(raw);
    end
end

function txt = format_numeric_or_na(v, fmt)
    if isnumeric(v) && isfinite(v)
        txt = sprintf(fmt, v);
    else
        txt = 'n/a';
    end
end

function rms_currents = extract_op_rms_currents(op, harmonics, data)
    n_w = data.n_windings;
    rms_currents = zeros(n_w, 1);
    if isfield(op, 'rms_currents_a')
        rms_currents = to_numeric_vector(op.rms_currents_a, n_w, rms_currents);
    end

    if all(rms_currents <= 0) && ~isempty(harmonics)
        if iscell(harmonics)
            try
                harmonics = [harmonics{:}];
            catch
                harmonics = struct([]);
            end
        end
        for hi = 1:numel(harmonics)
            h = harmonics(hi);
            i_re = zeros(n_w, 1);
            i_im = zeros(n_w, 1);
            if isfield(h, 'currents_real_a')
                i_re = to_numeric_vector(h.currents_real_a, n_w, i_re);
            end
            if isfield(h, 'currents_imag_a')
                i_im = to_numeric_vector(h.currents_imag_a, n_w, i_im);
            end
            rms_currents = sqrt(rms_currents .^ 2 + (i_re .^ 2 + i_im .^ 2));
        end
    end

    for w = 1:n_w
        if rms_currents(w) <= 0
            rms_currents(w) = max(0, data.windings(w).current);
        end
    end
end

function [all_conductors, all_winding_map, all_wire_shapes, meta] = build_cwf_geometry_for_analysis(data, pattern)
    % Build PEEC conductors from CWF layout engine.
    all_conductors = [];
    all_winding_map = [];
    all_wire_shapes = {};
    x_start = 0;
    edge_margin = 0;
    if isfield(data, 'edge_margin')
        edge_margin = data.edge_margin;
    end

    section_order = parse_section_order(data);
    [section_turns, section_windings] = build_section_plan(data, section_order);

    for s = 1:length(section_windings)
        w = section_windings(s);
        n_turns = section_turns(s);
        if n_turns <= 0
            continue;
        end

        wire_type = data.windings(w).wire_type;
        [w_dim, h_dim, shape] = data.api.wire_to_conductor_dims(wire_type);
        cond_w = w_dim;
        cond_h = h_dim;

        n_filar = data.windings(w).n_filar;
        total_conds = n_turns * n_filar;

        fprintf('Building winding %d (%s): %s wire (%s), %d turns x %d filar\n', ...
            w, data.windings(w).name, wire_type, shape, n_turns, n_filar);

        if ~strcmp(data.selected_core, 'None')
            layout = calculate_layout(data, wire_type, n_turns, pattern, n_filar);
        else
            layout = struct();
            positions = zeros(total_conds, 2);
            for t = 1:total_conds
                positions(t, :) = [0, (t-0.5) * max(w_dim, h_dim)];
            end
            layout.turn_positions = positions;
            layout.required_width = max(w_dim, h_dim);
        end

        if strcmp(shape, 'rectangular')
            if isfield(layout, 'draw_w') && isfield(layout, 'draw_h')
                cond_w = max(1e-12, layout.draw_w);
                cond_h = max(1e-12, layout.draw_h);
            elseif isfield(layout, 'wire_vis_w') && isfield(layout, 'wire_vis_h')
                cond_w = max(1e-12, layout.wire_vis_w);
                cond_h = max(1e-12, layout.wire_vis_h);
            end
        end

        I_per_strand = data.windings(w).current / max(1, n_filar);
        phase = data.windings(w).phase;

        for t = 1:total_conds
            x = edge_margin + x_start + layout.turn_positions(t, 1);
            y = edge_margin + layout.turn_positions(t, 2);
            all_conductors = [all_conductors; x, y, cond_w, cond_h, I_per_strand, phase];
            all_winding_map = [all_winding_map; w];
            all_wire_shapes{end+1} = shape;
        end

        fprintf('  %d conductors at layout positions (pattern: %s, cond=%.3f x %.3f mm)\n', ...
            total_conds, pattern, cond_w*1e3, cond_h*1e3);

        gap_winding = 0;
        if s < length(section_windings)
            if section_windings(s+1) ~= w
                gap_winding = get_inter_winding_gap(data, w, section_windings(s+1));
            end
        end
        x_start = x_start + layout.required_width + gap_winding;
    end

    meta = struct();
    meta.source = 'cwf';
    meta.pattern = pattern;
    meta.envelope = compute_geometry_envelope(all_conductors);
end

function [om_meta, err_msg] = generate_om_meta_for_analysis(data)
    % Generate OM visualization artifacts and read metadata for analysis.
    om_meta = struct();
    err_msg = '';
    try
        config = build_om_viz_config(data);
        script_dir = pwd();
        config_file = fullfile(script_dir, 'om_viz_config.json');
        svg_file = fullfile(script_dir, 'om_visualization.svg');
        meta_file = fullfile(script_dir, 'om_visualization_meta.json');
        config.output_svg = strrep(svg_file, '\', '/');
        config.output_meta = strrep(meta_file, '\', '/');

        fid = fopen(config_file, 'w');
        if fid == -1
            error('Cannot write config file: %s', config_file);
        end
        fwrite(fid, jsonencode(config));
        fclose(fid);

        py_script_name = 'generate_om_visualization.py';
        config_file_name = 'om_viz_config.json';
        if ~exist(fullfile(script_dir, py_script_name), 'file')
            error('Python script "%s" not found in %s', py_script_name, script_dir);
        end

        python_cmd = 'python';
        venv_python = fullfile(script_dir, '.venv', 'Scripts', 'python.exe');
        if exist(venv_python, 'file')
            python_cmd = ['"' venv_python '"'];
        end

        cmd = sprintf('%s "%s" "%s" 2>&1', python_cmd, py_script_name, config_file_name);
        [status, output] = system(cmd);

        is_module_error = ~isempty(strfind(output, 'ModuleNotFoundError')) || ...
                          ~isempty(strfind(output, 'ImportError')) || ...
                          ~isempty(strfind(output, 'No module named'));
        if status ~= 0 && is_module_error && ispc
            cmd_fallback = sprintf('py "%s" "%s" 2>&1', py_script_name, config_file_name);
            [status_fb, output_fb] = system(cmd_fallback);
            if status_fb == 0 && ~isempty(strfind(output_fb, 'OK'))
                status = status_fb;
                output = output_fb;
            end
        end
        if status ~= 0 && is_module_error && ispc
            [~, py_paths_str] = system('where python');
            py_paths = strsplit(strtrim(py_paths_str), char(10));
            for i = 1:length(py_paths)
                p = strtrim(py_paths{i});
                if isempty(p); continue; end
                if ~isempty(strfind(lower(p), 'octave')) || ~isempty(strfind(lower(p), 'usr\bin'))
                    continue;
                end
                cmd_alt = sprintf('"%s" "%s" "%s" 2>&1', p, py_script_name, config_file_name);
                [status_alt, output_alt] = system(cmd_alt);
                if status_alt == 0 && ~isempty(strfind(output_alt, 'OK'))
                    status = status_alt;
                    output = output_alt;
                    break;
                end
            end
        end
        if status ~= 0 || isempty(strfind(strtrim(output), 'OK'))
            error('OM python failed (exit=%d): %s', status, strtrim(output));
        end

        if ~exist(meta_file, 'file')
            error('OM metadata file not found: %s', meta_file);
        end
        fidm = fopen(meta_file, 'r');
        if fidm == -1
            error('Cannot read OM metadata file: %s', meta_file);
        end
        meta_raw = fread(fidm, '*char')';
        fclose(fidm);
        om_meta = jsondecode(meta_raw);
    catch ME
        err_msg = ME.message;
    end
end

function [all_conductors, all_winding_map, all_wire_shapes, meta] = build_om_geometry_from_meta(data, om_meta)
    % Build PEEC conductors directly from OM turn geometry (Choice A).
    all_conductors = [];
    all_winding_map = [];
    all_wire_shapes = {};

    if ~isstruct(om_meta) || ~isfield(om_meta, 'turns') || isempty(om_meta.turns)
        error('OM metadata has no turns');
    end

    turns = om_meta.turns;
    if ~isstruct(turns)
        try
            turns = [turns{:}];
        catch
            turns = struct([]);
        end
    end
    if isempty(turns)
        error('OM metadata turns are empty');
    end

    bobbin_w = 0;
    bobbin_h = 0;
    if isfield(om_meta, 'bobbin_window_width_m')
        bobbin_w = om_meta.bobbin_window_width_m;
    end
    if isfield(om_meta, 'bobbin_window_height_m')
        bobbin_h = om_meta.bobbin_window_height_m;
    end
    if bobbin_w <= 0 || bobbin_h <= 0
        cwf = get_cwf_window_metrics(data);
        bobbin_w = max(1e-9, cwf.width_m);
        bobbin_h = max(1e-9, cwf.height_m);
    end

    % Pass 1: collect valid turns and bounding box.
    valid_turns = struct('x', {}, 'y', {}, 'w', {}, 'h', {}, 'shape', {}, 'winding_idx', {});
    xmin = inf; xmax = -inf; ymin = inf; ymax = -inf;
    for i = 1:numel(turns)
        t = turns(i);
        if ~isstruct(t) || ~isfield(t, 'x_m') || ~isfield(t, 'y_m')
            continue;
        end
        x = double(t.x_m);
        y = double(t.y_m);

        w = 0; h = 0;
        if isfield(t, 'width_m');  w = double(t.width_m); end
        if isfield(t, 'height_m'); h = double(t.height_m); end
        if w <= 0 && isfield(t, 'r_m'); w = 2 * double(t.r_m); end
        if h <= 0 && isfield(t, 'r_m'); h = 2 * double(t.r_m); end
        if w <= 0 || h <= 0
            continue;
        end

        shape = 'rectangular';
        if isfield(t, 'shape')
            shape_name = lower(strtrim(char(t.shape)));
            if ~isempty(strfind(shape_name, 'round')) || ~isempty(strfind(shape_name, 'circle'))
                shape = 'round';
            end
        end
        if strcmp(shape, 'rectangular')
            if abs(w - h) <= 0.05 * max(w, h)
                shape = 'round';
            end
        end

        winding_name = '';
        if isfield(t, 'winding')
            winding_name = strtrim(char(t.winding));
        end
        winding_idx = map_winding_name_to_index(data, winding_name);
        if winding_idx < 1 || winding_idx > data.n_windings
            continue;
        end

        vt = struct();
        vt.x = x;
        vt.y = y;
        vt.w = w;
        vt.h = h;
        vt.shape = shape;
        vt.winding_idx = winding_idx;
        valid_turns(end+1) = vt; %#ok<AGROW>

        xmin = min(xmin, x - w/2);
        xmax = max(xmax, x + w/2);
        ymin = min(ymin, y - h/2);
        ymax = max(ymax, y + h/2);
    end

    if isempty(valid_turns)
        error('No usable OM turns after parsing metadata');
    end

    cx = 0.5 * (xmin + xmax);
    cy = 0.5 * (ymin + ymax);
    target_cx = bobbin_w / 2;
    target_cy = bobbin_h / 2;

    % Pass 2: convert to local bobbin coordinates and assign currents/phases.
    for i = 1:numel(valid_turns)
        t = valid_turns(i);
        x_local = t.x - cx + target_cx;
        y_local = t.y - cy + target_cy;
        w = max(1e-12, t.w);
        h = max(1e-12, t.h);
        widx = t.winding_idx;
        n_filar = max(1, data.windings(widx).n_filar);
        I_per_strand = data.windings(widx).current / n_filar;
        phase = data.windings(widx).phase;

        all_conductors = [all_conductors; x_local, y_local, w, h, I_per_strand, phase];
        all_winding_map = [all_winding_map; widx];
        all_wire_shapes{end+1} = t.shape;
    end

    meta = struct();
    meta.source = 'om';
    meta.window_w_m = bobbin_w;
    meta.window_h_m = bobbin_h;
    meta.raw_bbox_m = [xmin, ymin, xmax, ymax];
    meta.local_bbox_m = compute_geometry_envelope(all_conductors);

    % --- Overflow detection: check if turns exceed bobbin window ---
    n_overflow = 0;
    for i = 1:numel(valid_turns)
        t = valid_turns(i);
        xl = (t.x - cx + target_cx) - t.w/2;
        xr = (t.x - cx + target_cx) + t.w/2;
        yb = (t.y - cy + target_cy) - t.h/2;
        yt_val = (t.y - cy + target_cy) + t.h/2;
        if xl < -1e-6 || xr > bobbin_w + 1e-6 || yb < -1e-6 || yt_val > bobbin_h + 1e-6
            n_overflow = n_overflow + 1;
        end
    end
    if n_overflow > 0
        fprintf('[WARNING] %d of %d turns extend outside the bobbin window (%.2f x %.2f mm)\n', ...
            n_overflow, numel(valid_turns), bobbin_w*1e3, bobbin_h*1e3);
        fprintf('  The OM winding engine placed conductors that do not fit.\n');
        fprintf('  Consider using a larger core or smaller wire.\n');
    end
    meta.n_overflow = n_overflow;

    % --- Overlap detection: check if any same-winding turns physically overlap ---
    n_overlap = 0;
    for i = 1:numel(valid_turns)
        for j = (i+1):numel(valid_turns)
            ti = valid_turns(i);
            tj = valid_turns(j);
            dist = sqrt((ti.x - tj.x)^2 + (ti.y - tj.y)^2);
            min_dist = 0.5 * (sqrt(ti.w * ti.h) + sqrt(tj.w * tj.h));
            if dist < min_dist * 0.95
                n_overlap = n_overlap + 1;
                if n_overlap <= 3
                    fprintf('[WARNING] Turns %d and %d overlap: distance=%.3fmm, min_clearance=%.3fmm\n', ...
                        i, j, dist*1e3, min_dist*1e3);
                end
            end
        end
    end
    if n_overlap > 0
        fprintf('[WARNING] %d turn pair(s) physically overlap. The OM winding layout has placement errors.\n', n_overlap);
    end
    meta.n_overlap = n_overlap;
end

function idx = map_winding_name_to_index(data, winding_name)
    idx = 0;
    q = lower(strtrim(char(winding_name)));
    if isempty(q)
        return;
    end
    for w = 1:data.n_windings
        n = lower(strtrim(char(data.windings(w).name)));
        if strcmp(n, q)
            idx = w;
            return;
        end
    end
    for w = 1:data.n_windings
        n = lower(strtrim(char(data.windings(w).name)));
        if ~isempty(strfind(q, n)) || ~isempty(strfind(n, q))
            idx = w;
            return;
        end
    end
end

function env = compute_geometry_envelope(conductors)
    env = struct('x_min', 0, 'x_max', 0, 'y_min', 0, 'y_max', 0, 'width', 0, 'height', 0);
    if isempty(conductors)
        return;
    end
    x_min = min(conductors(:,1) - conductors(:,3)/2);
    x_max = max(conductors(:,1) + conductors(:,3)/2);
    y_min = min(conductors(:,2) - conductors(:,4)/2);
    y_max = max(conductors(:,2) + conductors(:,4)/2);
    env.x_min = x_min;
    env.x_max = x_max;
    env.y_min = y_min;
    env.y_max = y_max;
    env.width = x_max - x_min;
    env.height = y_max - y_min;
end

function dump_path = write_analysis_geometry_dump(data, conductors, winding_map, wire_shapes, analysis_meta, analysis_run)
    dump_path = '';
    if nargin < 6 || ~isstruct(analysis_run)
        analysis_run = struct();
    end
    try
        dump = struct();
        dump.generated_at = datestr(now, 30);
        dump.core = data.selected_core;
        dump.material = data.selected_material;
        dump.section_order = data.section_order;
        dump.analysis_meta = analysis_meta;
        dump.conductors = conductors;
        dump.winding_map = winding_map;
        dump.wire_shapes = wire_shapes;
        dump.envelope = compute_geometry_envelope(conductors);
        dump.analysis_run = build_analysis_run_dump_meta(analysis_run);
        dump_path = fullfile(pwd(), 'analysis_geometry_dump.json');
        fid = fopen(dump_path, 'w');
        if fid ~= -1
            fwrite(fid, jsonencode(dump));
            fclose(fid);
        else
            dump_path = '';
        end
    catch
        dump_path = '';
    end
end

function run_meta = build_analysis_run_dump_meta(analysis_run)
    run_meta = struct();
    if ~isstruct(analysis_run) || isempty(fieldnames(analysis_run))
        return;
    end

    keep_fields = { ...
        'mode', ...
        'selected_operating_indices', ...
        'total_operating_points', ...
        'evaluated_operating_points', ...
        'max_harmonics', ...
        'worst_index', ...
        'worst_name', ...
        'worst_source_index', ...
        'worst_harmonic_count', ...
        'total_loss', ...
        'best_index', ...
        'best_name', ...
        'best_source_index', ...
        'best_harmonic_count', ...
        'best_total_loss', ...
        'excitation_summary' ...
    };
    for i = 1:numel(keep_fields)
        field_name = keep_fields{i};
        if isfield(analysis_run, field_name)
            run_meta.(field_name) = analysis_run.(field_name);
        end
    end

    if isfield(analysis_run, 'operating_points') && isstruct(analysis_run.operating_points)
        ops = analysis_run.operating_points;
        op_meta = repmat(struct( ...
            'name', '', ...
            'source_index', 0, ...
            'total_loss', NaN, ...
            'harmonic_count', 0, ...
            'line_scale', NaN, ...
            'load_scale', NaN, ...
            'duty', NaN, ...
            'frequency_hz', NaN, ...
            'conduction_mode', 'n/a'), 1, numel(ops));
        for i = 1:numel(ops)
            op_meta(i).name = get_struct_string(ops(i), 'name', sprintf('op_%d', i));
            op_meta(i).source_index = get_struct_numeric(ops(i), 'source_index', i);
            op_meta(i).total_loss = get_struct_numeric(ops(i), 'total_loss', NaN);
            op_meta(i).harmonic_count = get_struct_numeric(ops(i), 'harmonic_count', 0);
            op_meta(i).line_scale = get_struct_numeric(ops(i), 'line_scale', NaN);
            op_meta(i).load_scale = get_struct_numeric(ops(i), 'load_scale', NaN);
            op_meta(i).duty = get_struct_numeric(ops(i), 'duty', NaN);
            op_meta(i).frequency_hz = get_struct_numeric(ops(i), 'frequency_hz', NaN);
            op_meta(i).conduction_mode = get_struct_string(ops(i), 'conduction_mode', 'n/a');
        end
        run_meta.operating_points = op_meta;
    end
end

% ===============================================================
% DISPLAY RESULTS
% ===============================================================

function display_results(data, geom, conductors, winding_map, results, analysis_meta, analysis_run)
    if nargin < 6 || isempty(analysis_meta)
        analysis_meta = struct();
        analysis_meta.requested_source = 'cwf';
        analysis_meta.used_source = 'cwf';
        analysis_meta.fallback_used = false;
        analysis_meta.fallback_reason = '';
        analysis_meta.debug_dump_path = '';
    end
    if nargin < 7
        analysis_run = struct();
    end

    selected_case = 1; % 1=worst, 2=best
    if ~isempty(data.fig_results) && ishandle(data.fig_results)
        prev_state = getappdata(data.fig_results, 'results_replot_state');
        if isstruct(prev_state) && isfield(prev_state, 'selected_case')
            selected_case = max(1, round(double(prev_state.selected_case)));
        end
    end

    if isempty(data.fig_results) || ~ishandle(data.fig_results)
        data.fig_results = figure('Name', 'Analysis Results', 'Position', [100 50 1400 900]);
    else
        figure(data.fig_results);
        clf;
    end

    % Calculate per-winding losses
    has_best_case = isstruct(analysis_run) && isfield(analysis_run, 'best_winding_ac_loss') ...
        && ~isempty(analysis_run.best_winding_ac_loss);
    case_items = {'Worst Case'};
    if has_best_case
        case_items = {'Worst Case', 'Best Case'};
    else
        selected_case = 1;
    end
    selected_case = min(max(1, selected_case), numel(case_items));

    current_case_label = 'Worst';
    op_eval_count = 0;
    op_total_count = 0;
    current_op_name = 'n/a';
    current_op_idx = 0;
    worst_op_name = 'n/a';
    worst_op_idx = 0;
    best_op_name = 'n/a';
    best_op_idx = 0;
    worst_total_loss_display = NaN;
    best_total_loss_display = NaN;
    selected_op_run = struct();
    worst_op_run = struct();
    best_op_run = struct();
    if isstruct(analysis_run) && isfield(analysis_run, 'winding_ac_loss') && ~isempty(analysis_run.winding_ac_loss)
        worst_winding_losses = analysis_run.winding_ac_loss(:);
        worst_winding_Pdc = analysis_run.winding_dc_loss(:);
        worst_rac_rdc = worst_winding_losses ./ max(worst_winding_Pdc, 1e-12);
        if isfield(analysis_run, 'winding_rac_rdc')
            worst_rac_rdc = analysis_run.winding_rac_rdc(:);
        end

        best_winding_losses = worst_winding_losses;
        best_winding_Pdc = worst_winding_Pdc;
        best_rac_rdc = worst_rac_rdc;
        if has_best_case
            best_winding_losses = analysis_run.best_winding_ac_loss(:);
            best_winding_Pdc = analysis_run.best_winding_dc_loss(:);
            best_rac_rdc = best_winding_losses ./ max(best_winding_Pdc, 1e-12);
            if isfield(analysis_run, 'best_winding_rac_rdc') && ~isempty(analysis_run.best_winding_rac_rdc)
                best_rac_rdc = analysis_run.best_winding_rac_rdc(:);
            end
        end

        winding_Rdc = analysis_run.winding_rdc(:);
        if selected_case == 2 && has_best_case
            winding_losses = best_winding_losses;
            winding_Pdc = best_winding_Pdc;
            rac_rdc = best_rac_rdc;
            current_case_label = 'Best';
            total_loss_display = analysis_run.best_total_loss;
            if isfield(analysis_run, 'best_name')
                current_op_name = char(analysis_run.best_name);
            end
            if isfield(analysis_run, 'best_source_index')
                current_op_idx = analysis_run.best_source_index;
            end
        else
            winding_losses = worst_winding_losses;
            winding_Pdc = worst_winding_Pdc;
            rac_rdc = worst_rac_rdc;
            current_case_label = 'Worst';
            total_loss_display = analysis_run.total_loss;
            if isfield(analysis_run, 'worst_name')
                current_op_name = char(analysis_run.worst_name);
            end
            if isfield(analysis_run, 'worst_source_index')
                current_op_idx = analysis_run.worst_source_index;
            end
        end

        if isfield(analysis_run, 'evaluated_operating_points')
            op_eval_count = analysis_run.evaluated_operating_points;
        end
        if isfield(analysis_run, 'total_operating_points')
            op_total_count = analysis_run.total_operating_points;
        end
        if isfield(analysis_run, 'worst_name')
            worst_op_name = char(analysis_run.worst_name);
        end
        if isfield(analysis_run, 'worst_source_index')
            worst_op_idx = analysis_run.worst_source_index;
        end
        if isfield(analysis_run, 'best_name')
            best_op_name = char(analysis_run.best_name);
        end
        if isfield(analysis_run, 'best_source_index')
            best_op_idx = analysis_run.best_source_index;
        end
        if isfield(analysis_run, 'total_loss')
            worst_total_loss_display = analysis_run.total_loss;
        end
        if isfield(analysis_run, 'best_total_loss')
            best_total_loss_display = analysis_run.best_total_loss;
        end
    else
        fils_per_cond = data.Nx * data.Ny;
        winding_losses = zeros(data.n_windings, 1);
        winding_Rdc = zeros(data.n_windings, 1);
        winding_Pdc = zeros(data.n_windings, 1);
        n_cond_total = size(conductors, 1);
        for c = 1:n_cond_total
            if c <= numel(winding_map)
                w = winding_map(c);
            else
                w = 1;
            end
            if w < 1 || w > data.n_windings
                continue;
            end
            idx_start = (c - 1) * fils_per_cond + 1;
            idx_end = c * fils_per_cond;
            if idx_end <= length(results.P_fil)
                winding_losses(w) = winding_losses(w) + sum(results.P_fil(idx_start:idx_end));
            end
        end

        for w = 1:data.n_windings
            cond_idx = find(winding_map == w);
            if isempty(cond_idx)
                [w_dim, h_dim] = data.api.wire_to_conductor_dims(data.windings(w).wire_type);
                A = max(1e-12, w_dim * h_dim);
            else
                A = max(1e-12, mean(conductors(cond_idx,3) .* conductors(cond_idx,4)));
            end
            winding_Rdc(w) = (data.windings(w).n_turns / max(1, data.windings(w).n_filar)) / (data.sigma * A);
            winding_Pdc(w) = 0.5 * data.windings(w).current^2 * winding_Rdc(w);
        end
        rac_rdc = winding_losses ./ max(winding_Pdc, 1e-12);
        total_loss_display = results.P_total;
        worst_total_loss_display = total_loss_display;
        current_op_name = 'single_run';
        current_op_idx = 1;
        worst_op_name = current_op_name;
        worst_op_idx = current_op_idx;
        best_op_name = current_op_name;
        best_op_idx = current_op_idx;
        best_total_loss_display = total_loss_display;
    end

    if isstruct(analysis_run) && isfield(analysis_run, 'operating_points') && ~isempty(analysis_run.operating_points)
        op_runs_all = analysis_run.operating_points;
        if iscell(op_runs_all)
            try
                op_runs_all = [op_runs_all{:}];
            catch
                op_runs_all = struct([]);
            end
        end
        if isstruct(op_runs_all) && ~isempty(op_runs_all)
            worst_idx_run = 1;
            best_idx_run = 1;
            if isfield(analysis_run, 'worst_index')
                worst_idx_run = max(1, min(numel(op_runs_all), round(double(analysis_run.worst_index))));
            end
            if isfield(analysis_run, 'best_index')
                best_idx_run = max(1, min(numel(op_runs_all), round(double(analysis_run.best_index))));
            end
            worst_op_run = op_runs_all(worst_idx_run);
            best_op_run = op_runs_all(best_idx_run);
            if selected_case == 2 && has_best_case
                selected_op_run = best_op_run;
            else
                selected_op_run = worst_op_run;
            end
        end
    end

    annotation('textbox', [0 0.96 1 0.04], ...
        'String', sprintf('Analysis Results @ %.0f kHz', data.f/1e3), ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
        'FontSize', 14, 'FontWeight', 'bold');
    src_msg = sprintf('Source: %s', upper(char(analysis_meta.used_source)));
    src_color = [0.10 0.45 0.10];
    if isfield(analysis_meta, 'fallback_used') && analysis_meta.fallback_used
        src_msg = sprintf('Source: CWF (fallback from OM)');
        src_color = [0.70 0.10 0.10];
    end
    annotation('textbox', [0.02 0.93 0.96 0.025], ...
        'String', src_msg, 'EdgeColor', 'none', ...
        'HorizontalAlignment', 'left', 'FontSize', 10, ...
        'FontWeight', 'bold', 'Color', src_color);

    if numel(case_items) > 1
        uicontrol('Parent', data.fig_results, 'Style', 'text', ...
            'Units', 'normalized', ...
            'Position', [0.74 0.955 0.08 0.02], ...
            'String', 'Plot Case:', ...
            'HorizontalAlignment', 'right', ...
            'FontSize', 9, 'FontWeight', 'bold');
        uicontrol('Parent', data.fig_results, 'Style', 'popupmenu', ...
            'Units', 'normalized', ...
            'Position', [0.82 0.952 0.16 0.03], ...
            'String', case_items, ...
            'Value', selected_case, ...
            'Tag', 'results_case_dropdown', ...
            'Callback', @results_case_dropdown_callback);
    end

    % Operating-point details are shown in the "Core & Configuration" panel
    % to avoid overlap with the top-left plots.

    plot_results = results;
    if isstruct(analysis_run)
        if selected_case == 2 && isfield(analysis_run, 'best_plot_results') && ~isempty(analysis_run.best_plot_results)
            plot_results = analysis_run.best_plot_results;
        elseif isfield(analysis_run, 'plot_results') && ~isempty(analysis_run.plot_results)
            plot_results = analysis_run.plot_results;
        end
    end

    ax1 = axes('Position', [0.06 0.53 0.27 0.30]);
    axes(ax1); %#ok<LAXES>
    plot_current_density(geom, plot_results);
    title(sprintf('Current Density (%s Case)', current_case_label));

    ax2 = axes('Position', [0.37 0.53 0.27 0.30]);
    axes(ax2); %#ok<LAXES>
    plot_loss_density(geom, plot_results);
    title(sprintf('Loss Density (%s Case)', current_case_label));

    ax3 = axes('Position', [0.68 0.53 0.27 0.30]);
    axes(ax3); %#ok<LAXES>
    bar([winding_Pdc, winding_losses]*1e3);
    set(gca, 'XTickLabel', {data.windings.name});
    ylabel('Loss (mW)');
    legend('DC Loss', 'AC Loss', 'Location', 'best');
    title(sprintf('Winding Loss Comparison (%s Case)', current_case_label));
    grid on;

    ax4 = axes('Position', [0.06 0.08 0.27 0.30]);
    axes(ax4); %#ok<LAXES>
    bar(rac_rdc);
    set(gca, 'XTickLabel', {data.windings.name});
    ylabel('R_{AC}/R_{DC}');
    title(sprintf('AC Resistance Factor (%s Case)', current_case_label));
    grid on;

    ax5 = axes('Position', [0.37 0.08 0.27 0.30]);
    axes(ax5); %#ok<LAXES>
    axis off;
    text(0.05, 0.95, sprintf('Loss Summary (%s Case)', current_case_label), 'FontSize', 12, 'FontWeight', 'bold');
    y_pos = 0.85;

    for w = 1:data.n_windings
        text(0.05, y_pos, sprintf('%s:', data.windings(w).name), ...
            'FontSize', 10, 'FontWeight', 'bold', 'Color', data.winding_colors{w});
        y_pos = y_pos - 0.08;

        text(0.05, y_pos, sprintf('  Wire: %s', data.windings(w).wire_type), 'FontSize', 9);
        y_pos = y_pos - 0.07;

        text(0.05, y_pos, sprintf('  Config: %d turns, %s', ...
            data.windings(w).n_turns, get_filar_name(data.windings(w).n_filar)), 'FontSize', 9);
        y_pos = y_pos - 0.07;

        text(0.05, y_pos, sprintf('  DC Loss: %.4f W', winding_Pdc(w)), 'FontSize', 9);
        y_pos = y_pos - 0.07;

        text(0.05, y_pos, sprintf('  AC Loss: %.4f W', winding_losses(w)), 'FontSize', 9);
        y_pos = y_pos - 0.07;

        text(0.05, y_pos, sprintf('  Rac/Rdc: %.2f', rac_rdc(w)), 'FontSize', 9);
        y_pos = y_pos - 0.12;
    end

    text(0.05, y_pos, sprintf('PEEC Total Loss: %.4f W', total_loss_display), ...
        'FontSize', 11, 'FontWeight', 'bold');

    ax6 = axes('Position', [0.68 0.08 0.27 0.30]);
    axes(ax6); %#ok<LAXES>
    axis off;
    text(0.05, 0.95, 'Core & Configuration', 'FontSize', 12, 'FontWeight', 'bold');
    y_cfg = 0.87;

    text(0.05, y_cfg, sprintf('Core: %s', data.selected_core), 'FontSize', 9); y_cfg = y_cfg - 0.08;
    text(0.05, y_cfg, sprintf('Frequency: %.0f kHz', data.f/1e3), 'FontSize', 9); y_cfg = y_cfg - 0.08;
    if isfield(analysis_meta, 'requested_source')
        text(0.05, y_cfg, sprintf('Requested source: %s', upper(char(analysis_meta.requested_source))), 'FontSize', 9);
        y_cfg = y_cfg - 0.06;
    end
    if isfield(analysis_meta, 'used_source')
        text(0.05, y_cfg, sprintf('Used source: %s', upper(char(analysis_meta.used_source))), 'FontSize', 9);
        y_cfg = y_cfg - 0.08;
    end

    if op_total_count > 0
        text(0.05, y_cfg, sprintf('Operating points: %d/%d evaluated', op_eval_count, op_total_count), ...
            'FontSize', 9, 'FontWeight', 'bold');
        y_cfg = y_cfg - 0.07;
    end
    text(0.05, y_cfg, sprintf('%s-case plot: %s [idx %d]', current_case_label, current_op_name, current_op_idx), ...
        'FontSize', 9, 'Color', [0.10 0.35 0.10]);
    y_cfg = y_cfg - 0.07;

    if ~isnan(worst_total_loss_display) && ~isnan(best_total_loss_display)
        text(0.05, y_cfg, sprintf('Worst: %.4f W | Best: %.4f W', ...
            worst_total_loss_display, best_total_loss_display), ...
            'FontSize', 9);
        y_cfg = y_cfg - 0.07;
        text(0.05, y_cfg, sprintf('Worst OP: %s [idx %d] | Best OP: %s [idx %d]', ...
            worst_op_name, worst_op_idx, best_op_name, best_op_idx), 'FontSize', 8);
        y_cfg = y_cfg - 0.06;
    end

    if ~isempty(fieldnames(selected_op_run))
        op_i = to_numeric_vector(get_struct_field(selected_op_run, 'rms_currents_a', []), data.n_windings, zeros(data.n_windings, 1));
        op_v = to_numeric_vector(get_struct_field(selected_op_run, 'rms_voltages_v', []), data.n_windings, zeros(data.n_windings, 1));
        op_duty = get_struct_numeric(selected_op_run, 'duty', NaN);
        op_line = get_struct_numeric(selected_op_run, 'line_scale', NaN);
        op_load = get_struct_numeric(selected_op_run, 'load_scale', NaN);
        op_mode = get_struct_string(selected_op_run, 'conduction_mode', 'n/a');

        text(0.05, y_cfg, 'Selected Operating Point:', 'FontSize', 9, 'FontWeight', 'bold');
        y_cfg = y_cfg - 0.06;
        text(0.05, y_cfg, sprintf('  Duty: %s | Mode: %s', format_numeric_or_na(op_duty, '%.3f'), op_mode), 'FontSize', 8);
        y_cfg = y_cfg - 0.05;
        text(0.05, y_cfg, sprintf('  Line scale: %s | Load scale: %s', ...
            format_numeric_or_na(op_line, '%.2f'), format_numeric_or_na(op_load, '%.2f')), 'FontSize', 8);
        y_cfg = y_cfg - 0.05;
        if data.n_windings >= 1
            text(0.05, y_cfg, sprintf('  Input V/I (RMS): %.2f V, %.3f A', op_v(1), op_i(1)), 'FontSize', 8);
            y_cfg = y_cfg - 0.05;
        end
        if data.n_windings >= 2
            text(0.05, y_cfg, sprintf('  Output V/I (RMS): %.2f V, %.3f A', op_v(2), op_i(2)), 'FontSize', 8);
            y_cfg = y_cfg - 0.05;
        end
    end

    if isfield(analysis_meta, 'fallback_used') && analysis_meta.fallback_used
        text(0.05, y_cfg, 'Fallback: OM -> CWF', 'FontSize', 8, ...
            'Color', [0.70 0.10 0.10], 'FontWeight', 'bold');
        y_cfg = y_cfg - 0.05;
    end

    % --- Magnetic Parameters: PEEC vs MKF Comparison ---
    has_mag = isstruct(analysis_run) && isfield(analysis_run, 'mag_results') ...
              && isstruct(analysis_run.mag_results) && analysis_run.mag_results.valid;
    has_mkf = isstruct(analysis_run) && isfield(analysis_run, 'mkf_ref') ...
              && isstruct(analysis_run.mkf_ref) && analysis_run.mkf_ref.valid;

    if has_mag || has_mkf
        y_cfg = y_cfg - 0.02;
        text(0.05, y_cfg, 'Magnetic Parameters:', 'FontSize', 9, 'FontWeight', 'bold', ...
             'Color', [0.0 0.2 0.6]);
        y_cfg = y_cfg - 0.06;

        % Header
        text(0.05, y_cfg, '                    PEEC       MKF', 'FontSize', 8, ...
             'FontName', 'FixedWidth', 'Color', [0.3 0.3 0.3]);
        y_cfg = y_cfg - 0.05;

        if has_mag
            mr = analysis_run.mag_results;
        end
        if has_mkf
            mk = analysis_run.mkf_ref;
        end

        % Lm
        peec_str = '  ---';
        mkf_str = '  ---';
        if has_mag, peec_str = sprintf('%7.1f', mr.Lm_H*1e6); end
        if has_mkf && mk.Lm_uH > 0, mkf_str = sprintf('%7.1f', mk.Lm_uH); end
        text(0.05, y_cfg, sprintf('Lm (uH)       %s    %s', peec_str, mkf_str), ...
             'FontSize', 8, 'FontName', 'FixedWidth');
        y_cfg = y_cfg - 0.045;

        % Llk
        peec_str = '  ---';
        mkf_str = '  ---';
        if has_mag, peec_str = sprintf('%7.2f', mr.Llk_pri_H*1e6); end
        if has_mkf && mk.Llk_uH > 0, mkf_str = sprintf('%7.2f', mk.Llk_uH); end
        text(0.05, y_cfg, sprintf('Llk,pri (uH)  %s    %s', peec_str, mkf_str), ...
             'FontSize', 8, 'FontName', 'FixedWidth');
        y_cfg = y_cfg - 0.045;

        % Bpk
        peec_str = '  ---';
        mkf_str = '  ---';
        if has_mag, peec_str = sprintf('%7.1f', mr.Bpk_T*1e3); end
        if has_mkf && mk.B_peak_mT > 0, mkf_str = sprintf('%7.1f', mk.B_peak_mT); end
        text(0.05, y_cfg, sprintf('Bpk (mT)      %s    %s', peec_str, mkf_str), ...
             'FontSize', 8, 'FontName', 'FixedWidth');
        y_cfg = y_cfg - 0.045;

        % deltaB
        peec_str = '  ---';
        mkf_str = '  ---';
        if has_mag, peec_str = sprintf('%7.1f', mr.deltaB_T*1e3); end
        if has_mkf && mk.B_pp_mT > 0, mkf_str = sprintf('%7.1f', mk.B_pp_mT); end
        text(0.05, y_cfg, sprintf('dB (mT)       %s    %s', peec_str, mkf_str), ...
             'FontSize', 8, 'FontName', 'FixedWidth');
        y_cfg = y_cfg - 0.045;

        % Core loss
        peec_str = '  ---';
        mkf_str = '  ---';
        if has_mag && mr.Pcore_W > 0
            peec_str = sprintf('%7.3f', mr.Pcore_W);
        end
        if has_mkf && mk.core_loss_W > 0
            mkf_str = sprintf('%7.3f', mk.core_loss_W);
        end
        method_label = '';
        if has_mag, method_label = sprintf(' (%s)', mr.method); end
        text(0.05, y_cfg, sprintf('Pcore (W)%s %s    %s', method_label, peec_str, mkf_str), ...
             'FontSize', 8, 'FontName', 'FixedWidth');
        y_cfg = y_cfg - 0.045;

        % Total loss (PEEC winding + PEEC core)
        peec_str = '  ---';
        mkf_str = '  ---';
        if has_mag && mr.Pcore_W > 0
            peec_total = total_loss_display + mr.Pcore_W;
            peec_str = sprintf('%7.3f', peec_total);
        end
        if has_mkf && mk.core_loss_W > 0 && mk.winding_loss_W > 0
            mkf_str = sprintf('%7.3f', mk.core_loss_W + mk.winding_loss_W);
        end
        text(0.05, y_cfg, sprintf('Total (W)     %s    %s', peec_str, mkf_str), ...
             'FontSize', 8, 'FontName', 'FixedWidth', 'FontWeight', 'bold');
        y_cfg = y_cfg - 0.045;

        % Coupling coefficient, Lm source, and reluctance breakdown
        info_parts = {};
        if has_mag
            info_parts{end+1} = sprintf('k: %.4f', mr.coupling_k);
            if isfield(mr, 'Lm_source') && ~isempty(mr.Lm_source)
                info_parts{end+1} = sprintf('Lm: %s', mr.Lm_source);
            end
            if isfield(mr, 'R_core') && mr.R_core > 0 && isfield(mr, 'R_total') && mr.R_total > 0
                gap_pct = mr.R_gap_total / mr.R_total * 100;
                info_parts{end+1} = sprintf('R_gap: %.1f%%', gap_pct);
            end
        end
        if ~isempty(info_parts)
            text(0.05, y_cfg, strjoin(info_parts, '  |  '), ...
                 'FontSize', 7, 'FontName', 'FixedWidth', 'Color', [0.4 0.4 0.4]);
        end
    end

    replot_state = struct();
    replot_state.data = data;
    replot_state.geom = geom;
    replot_state.conductors = conductors;
    replot_state.winding_map = winding_map;
    replot_state.results = results;
    replot_state.analysis_meta = analysis_meta;
    replot_state.analysis_run = analysis_run;
    replot_state.selected_case = selected_case;
    setappdata(data.fig_results, 'results_replot_state', replot_state);

    fprintf('\n=== ANALYSIS COMPLETE ===\n');

    % Store results figure handle
    data.fig_results = gcf;
    guidata(data.fig_gui, data);
end

function results_case_dropdown_callback(src, ~)
    fig = ancestor(src, 'figure');
    if isempty(fig) || ~ishandle(fig)
        return;
    end
    state = getappdata(fig, 'results_replot_state');
    if ~isstruct(state)
        return;
    end
    val = get(src, 'Value');
    if isempty(val) || ~isnumeric(val)
        val = 1;
    end
    state.selected_case = max(1, round(double(val)));
    setappdata(fig, 'results_replot_state', state);
    display_results(state.data, state.geom, state.conductors, state.winding_map, ...
        state.results, state.analysis_meta, state.analysis_run);
end

% ===============================================================
% UTILITY
% ===============================================================

function reset_defaults(~, ~)
    close all;
    interactive_winding_designer();
end


function export_mas_file(~, ~)
    % Export current design as a MAS-compliant JSON file
    % Follows the OpenMagnetics MAS (Magnetic Agnostic Structure) schema
    fig = gcbf();
    data = guidata(fig);

    % Build MAS structure
    mas = struct();

    % =====================================================================
    % INPUTS section
    % =====================================================================
    mas.inputs = struct();
    mas.inputs.designRequirements = struct();

    % Topology
    if isfield(data, 'excitation') && isfield(data.excitation, 'topology')
        mas.inputs.designRequirements.topology = data.excitation.topology;
    end

    % Magnetizing inductance
    if isfield(data, 'design_spec') && isstruct(data.design_spec) ...
            && isfield(data.design_spec, 'requirements') ...
            && isfield(data.design_spec.requirements, 'Lm_uH')
        lm_h = data.design_spec.requirements.Lm_uH * 1e-6;
        mas.inputs.designRequirements.magnetizingInductance = struct('nominal', lm_h);
    end

    % Turns ratios (array of structs per MAS schema)
    if data.n_windings >= 2
        ratio = data.windings(1).n_turns / max(1, data.windings(2).n_turns);
        mas.inputs.designRequirements.turnsRatios = {struct('nominal', ratio)};
    end

    % Operating point
    op = struct();
    op.name = 'nominal';
    op.conditions = struct('ambientTemperature', 25);
    op.excitationsPerWinding = {};
    for w = 1:data.n_windings
        ex = struct();
        ex.name = data.windings(w).name;
        ex.frequency = data.f;
        % Current excitation
        cur_proc = struct();
        cur_proc.rms = data.windings(w).current;
        if isfield(data, 'excitation') && isfield(data.excitation, 'waveform_label')
            cur_proc.label = data.excitation.waveform_label;
        end
        ex.current = struct('processed', cur_proc);
        % Voltage excitation
        if isfield(data.windings(w), 'voltage') && data.windings(w).voltage > 0
            vol_proc = struct('rms', data.windings(w).voltage);
            ex.voltage = struct('processed', vol_proc);
        end
        op.excitationsPerWinding{end+1} = ex;
    end
    mas.inputs.operatingPoints = {op};

    % =====================================================================
    % MAGNETIC section
    % =====================================================================
    mas.magnetic = struct();

    % --- Core ---
    mas.magnetic.core = struct();
    core_fd = struct();

    % Core type (required by schema)
    core_fd.type = 'two-piece set';

    % Shape: use original OM name (e.g. "E 42/21/15"), not sanitized key
    core_shape_name = data.selected_core;
    if isfield(data.cores, data.selected_core) && isfield(data.cores.(data.selected_core), 'name')
        core_shape_name = data.cores.(data.selected_core).name;
    end
    core_fd.shape = core_shape_name;

    % Material: use original OM name
    mat_name = data.selected_material;
    if isfield(data.materials, mat_name) && isfield(data.materials.(mat_name), 'name')
        mat_name = data.materials.(mat_name).name;
    end
    core_fd.material = mat_name;

    % Gapping: use build_gapping_array() for proper OM type mapping
    if isfield(data, 'core_gap_type')
        gapping_cells = data.api.build_gapping_array( ...
            data.core_gap_type, data.core_gap_length, data.core_num_gaps);
    else
        gapping_cells = {struct('type', 'residual', 'length', 10e-6)};
    end
    core_fd.gapping = gapping_cells;

    % Number of stacks
    core_fd.numberStacks = 1;

    mas.magnetic.core.functionalDescription = core_fd;

    % Core name (optional but helpful)
    mas.magnetic.core.name = sprintf('%s %s', core_shape_name, mat_name);

    % --- Coil ---
    mas.magnetic.coil = struct();

    % Bobbin: use shape name string (schema accepts name or object)
    mas.magnetic.coil.bobbin = core_shape_name;

    % Functional description (winding definitions)
    winding_desc = {};
    for w = 1:data.n_windings
        wd = struct();
        wd.name = data.windings(w).name;
        wd.numberTurns = data.windings(w).n_turns;
        wd.numberParallels = data.windings(w).n_filar;

        % Isolation side (required by schema)
        if w == 1
            wd.isolationSide = 'primary';
        else
            wd.isolationSide = 'secondary';
        end

        % Wire: build full wire object per MAS schema
        wire_key = data.windings(w).wire_type;
        wd.wire = build_mas_wire_object(data, wire_key);

        winding_desc{end+1} = wd;
    end
    mas.magnetic.coil.functionalDescription = winding_desc;

    % =====================================================================
    % OUTPUTS section (required by schema, can be empty)
    % =====================================================================
    mas.outputs = {};

    % =====================================================================
    % Save to file
    % =====================================================================
    [fname, fpath] = uiputfile({'*.json', 'MAS JSON Files (*.json)'}, ...
                               'Export MAS File', 'design_export.json');
    if isequal(fname, 0)
        return;  % user cancelled
    end

    full_path = fullfile(fpath, fname);
    try
        json_str = jsonencode(mas);
        % Pretty-print: add newlines after commas/braces for readability
        json_str = strrep(json_str, ',"', sprintf(',\n  "'));
        json_str = strrep(json_str, '{', sprintf('{\n  '));
        json_str = strrep(json_str, '}', sprintf('\n}'));
        fid = fopen(full_path, 'w', 'n', 'UTF-8');
        fprintf(fid, '%s', json_str);
        fclose(fid);
        msgbox(sprintf('MAS file exported to:\n%s', full_path), 'Export Complete');
    catch err
        errordlg(sprintf('Export failed:\n%s', err.message), 'Error');
    end
end


function wire_obj = build_mas_wire_object(data, wire_key)
    % Build a full MAS-compliant wire object from our internal wire database.
    % The MAS schema accepts either a name string or a full wire object.
    % The web app needs the full object to display wire details properly.
    %
    % Schema requirements by type:
    %   round: type, conductingDiameter {nominal}, outerDiameter {nominal}
    %   litz:  type, numberConductors, strand (round object or name), outerDiameter {nominal}
    %   foil:  type, conductingWidth {nominal}
    %   rectangular: type, conductingWidth {nominal}, conductingHeight {nominal}

    wire_obj = struct();

    % Get the original OM name
    wire_om_name = wire_key;
    if isfield(data.wires, wire_key) && isfield(data.wires.(wire_key), 'name')
        wire_om_name = data.wires.(wire_key).name;
    end
    wire_obj.name = wire_om_name;

    % Get wire info from database
    wire_info = data.api.get_wire_info(wire_key);

    % Determine wire type
    wire_type = 'round';  % default
    if isfield(wire_info, 'type') && ~isempty(wire_info.type)
        wire_type = wire_info.type;
    elseif isfield(wire_info, 'conductor_shape')
        if strcmp(wire_info.conductor_shape, 'rectangular')
            wire_type = 'foil';
        end
    end
    wire_obj.type = wire_type;

    % Material (only set when known; litz wires often have null material in PyMKF)
    if isfield(wire_info, 'material') && ~isempty(wire_info.material) && ischar(wire_info.material)
        wire_obj.material = wire_info.material;
    elseif ~strcmp(wire_type, 'litz')
        wire_obj.material = 'copper';
    end

    % Number of conductors (must be integer per schema)
    if isfield(wire_info, 'numberConductors') && ~isempty(wire_info.numberConductors) ...
            && isnumeric(wire_info.numberConductors) && wire_info.numberConductors > 0
        wire_obj.numberConductors = int32(wire_info.numberConductors);
    else
        wire_obj.numberConductors = int32(1);
    end

    % Standard (must be one of: "IEC 60317", "NEMA MW 1000 C", "IPC-6012")
    if isfield(wire_info, 'standard') && ~isempty(wire_info.standard) && ischar(wire_info.standard)
        wire_obj.standard = wire_info.standard;
    end

    % Build type-specific fields with dimensionWithTolerance format {nominal: value}
    switch wire_type
        case 'round'
            if isfield(wire_info, 'diameter') && wire_info.diameter > 0
                wire_obj.conductingDiameter = struct('nominal', wire_info.diameter);
            end
            if isfield(wire_info, 'outer_diameter') && wire_info.outer_diameter > 0
                wire_obj.outerDiameter = struct('nominal', wire_info.outer_diameter);
            end

        case 'litz'
            % Litz requires: strand, outerDiameter, numberConductors
            % Use min/max for outerDiameter (matches PyMKF ndjson format)
            if isfield(wire_info, 'outer_diameter') && wire_info.outer_diameter > 0
                od = wire_info.outer_diameter;
                % Approximate min/max from nominal (±3% typical for litz)
                wire_obj.outerDiameter = struct('minimum', od * 0.97, 'maximum', od * 1.03);
            end

            % Strand: prefer name string reference (matches PyMKF ndjson format
            % exactly, e.g. "strand": "Round 0.1 - Grade 1")
            % MKF resolves this via find_wire_by_name() internally
            if isfield(wire_info, 'strand_name') && ~isempty(wire_info.strand_name)
                wire_obj.strand = wire_info.strand_name;
            else
                % Fallback: parse from wire name and build strand name
                % e.g. "Litz 75x0.1 - Grade 1 - Double Served" -> "Round 0.1 - Grade 1"
                strand_name = build_strand_name_from_litz(wire_om_name);
                if ~isempty(strand_name)
                    wire_obj.strand = strand_name;
                elseif isfield(wire_info, 'strand_conductingDiameter') ...
                        && ~isempty(wire_info.strand_conductingDiameter) ...
                        && isnumeric(wire_info.strand_conductingDiameter) ...
                        && wire_info.strand_conductingDiameter > 0
                    % Build minimal strand object as last resort
                    strand = struct();
                    strand.type = 'round';
                    strand.material = 'copper';
                    strand.numberConductors = 1;
                    strand.conductingDiameter = struct('nominal', wire_info.strand_conductingDiameter);
                    wire_obj.strand = strand;
                end
            end

        case 'foil'
            % Foil: conductingWidth = thickness (OM convention)
            if isfield(wire_info, 'foil_thickness') && wire_info.foil_thickness > 0
                wire_obj.conductingWidth = struct('nominal', wire_info.foil_thickness);
            elseif isfield(wire_info, 'thickness') && wire_info.thickness > 0
                wire_obj.conductingWidth = struct('nominal', wire_info.thickness);
            end
            if isfield(wire_info, 'foil_width') && wire_info.foil_width > 0
                wire_obj.conductingHeight = struct('nominal', wire_info.foil_width);
            end

        case 'rectangular'
            if isfield(wire_info, 'rect_width') && wire_info.rect_width > 0
                wire_obj.conductingWidth = struct('nominal', wire_info.rect_width);
            end
            if isfield(wire_info, 'rect_height') && wire_info.rect_height > 0
                wire_obj.conductingHeight = struct('nominal', wire_info.rect_height);
            end
    end

    % Coating info
    if isfield(wire_info, 'coating') && isstruct(wire_info.coating)
        wire_obj.coating = wire_info.coating;
    elseif isfield(wire_info, 'coating_type') && ~isempty(wire_info.coating_type)
        coat = struct('type', wire_info.coating_type);
        if isfield(wire_info, 'coating_grade') && ~isempty(wire_info.coating_grade)
            coat.grade = wire_info.coating_grade;
        end
        wire_obj.coating = coat;
    end
end


function strand_d_m = parse_litz_strand_diameter(wire_name)
    % Parse strand diameter from litz wire name.
    % e.g. "Litz 1000x0.02 - Grade 1" -> 0.02 mm -> 2e-5 m
    % e.g. "Litz 30x0.1 - Grade 1"    -> 0.1 mm  -> 1e-4 m
    strand_d_m = 0;
    tok = regexp(wire_name, 'Litz\s+\d+x(\d+\.?\d*)', 'tokens');
    if ~isempty(tok)
        strand_d_mm = str2double(tok{1}{1});
        if ~isnan(strand_d_mm) && strand_d_mm > 0
            strand_d_m = strand_d_mm * 1e-3;  % mm to m
        end
    end
end


function strand_name = build_strand_name_from_litz(litz_name)
    % Build a strand wire name from a litz wire name.
    % e.g. "Litz 75x0.1 - Grade 1 - Double Served" -> "Round 0.1 - Grade 1"
    % e.g. "Litz 1000x0.02 - Grade 2 - Single Served" -> "Round 0.02 - Grade 2"
    strand_name = '';
    tok = regexp(litz_name, 'Litz\s+\d+x(\d+\.?\d*)\s*-\s*(Grade\s+\d+)', 'tokens');
    if ~isempty(tok)
        strand_d_str = tok{1}{1};
        grade_str = tok{1}{2};
        strand_name = sprintf('Round %s - %s', strand_d_str, grade_str);
    end
end


function name = get_filar_name(n)
    names = {'Single-filar', 'Bi-filar', 'Tri-filar', 'Quad-filar'};
    if n >= 1 && n <= 4
        name = names{n};
    else
        name = sprintf('%d-filar', n);
    end
end

function parse_om_svg(svg_str, ax, om_meta, data)
    % Robust SVG parser for Octave - renders circles, rectangles, polygons, and paths
    if nargin < 3
        om_meta = struct();
    end
    if nargin < 4
        data = struct();
    end
    cla(ax);
    hold(ax, 'on');
    color_map = parse_css_colors(svg_str);
    vb = [];
    
    % Extract viewBox for coordinate mapping
    % Allow spaces around = and quotes
    vb_match = regexp(svg_str, 'viewBox\s*=\s*["'']([^"'']*)["'']', 'tokens', 'once');
    if ~isempty(vb_match)
        vb = sscanf(vb_match{1}, '%f %f %f %f');
        if length(vb) == 4
            pad = 0.05;
            x0 = vb(1); y0 = vb(2); w = vb(3); h = vb(4);
            xlim(ax, [x0 - pad*w, x0 + w*(1+pad)]);
            ylim(ax, [y0 - pad*h, y0 + h*(1+pad)]);
            % SVG Y is down, plot Y is up. OpenMagnetics usually handles this,
            % but if needed we could flip. For now assume standard Cartesian.
        else
            vb = [];
        end
    end

    % --- Helper to extract numeric attribute ---
    function val = get_attr(tag, attr)
        val = NaN;
        % Allow spaces around = and quotes
        pat = [attr '\s*=\s*["'']?([0-9\.\-eE]+)["'']?'];
        tok = regexp(tag, pat, 'tokens', 'once');
        if ~isempty(tok)
            val = str2double(tok{1});
        end
    end

    % --- Helper to extract string attribute ---
    function str_val = get_attr_str(tag, attr)
        str_val = '';
        pat = [attr '\s*=\s*["'']([^"'']*)["'']'];
        tok = regexp(tag, pat, 'tokens', 'once');
        if ~isempty(tok)
            str_val = tok{1};
        end
    end

    % --- Draw Paths (Core shapes) ---
    path_tags = regexp(svg_str, '<path[^>]*>', 'match');
    for i = 1:length(path_tags)
        tag = path_tags{i};
        d = get_attr_str(tag, 'd');
        class_name = get_attr_str(tag, 'class');
        style = get_attr_str(tag, 'style');
        [rgb, alpha, has_fill, known] = get_class_style(class_name, color_map);
        
        if ~isempty(d)
            % Heuristic: extract all numbers and plot as polygon
            % Handle "10-10" case by putting space before minus
            d_spaced = regexprep(d, '([0-9])-', '$1 -');
            % Remove commands
            d_clean = regexprep(d_spaced, '[a-zA-Z,]', ' ');
            nums = sscanf(d_clean, '%f');
            
            if length(nums) >= 4 && mod(length(nums), 2) == 0
                px = nums(1:2:end);
                py = nums(2:2:end);
                
                if tag_has_fill_none(tag) || contains(style, 'fill:none') || (known && ~has_fill)
                    line(px, py, 'Parent', ax, 'Color', 'k', 'LineWidth', 1);
                else
                    if ~(known && has_fill)
                        rgb = get_default_color(class_name);
                        alpha = 1.0;
                    end
                    h = patch(ax, px, py, rgb, 'EdgeColor', 'k', 'FaceAlpha', 0.5);
                    if alpha < 1.0
                        try
                            set(h, 'FaceAlpha', alpha);
                        catch
                        end
                    end
                end
            end
        end
    end

    % --- Draw Polygons ---
    poly_tags = regexp(svg_str, '<polygon[^>]*>', 'match');
    for i = 1:length(poly_tags)
        tag = poly_tags{i};
        pts_str = get_attr_str(tag, 'points');
        class_name = get_attr_str(tag, 'class');
        [rgb, alpha, has_fill, known] = get_class_style(class_name, color_map);
        if ~isempty(pts_str)
            if tag_has_fill_none(tag) || (known && ~has_fill)
                continue;
            end
            % Replace commas with spaces
            nums = sscanf(regexprep(pts_str, '[,]', ' '), '%f');
            if length(nums) >= 4 && mod(length(nums), 2) == 0
                px = nums(1:2:end);
                py = nums(2:2:end);
                if ~(known && has_fill)
                    rgb = get_default_color(class_name);
                    alpha = 1.0;
                end
                h = patch(ax, px, py, rgb, 'EdgeColor', 'k', 'FaceAlpha', 0.5);
                if alpha < 1.0
                    try
                        set(h, 'FaceAlpha', alpha);
                    catch
                    end
                end
            end
        end
    end

    % --- Draw Rectangles ---
    rect_tags = regexp(svg_str, '<rect[^>]*>', 'match');
    for i = 1:length(rect_tags)
        tag = rect_tags{i};
        x = get_attr(tag, 'x');
        y = get_attr(tag, 'y');
        w = get_attr(tag, 'width');
        h = get_attr(tag, 'height');
        class_name = get_attr_str(tag, 'class');
        [rgb, alpha, has_fill, known] = get_class_style(class_name, color_map);
        
        if ~isnan(x) && ~isnan(y) && ~isnan(w) && ~isnan(h)
            if tag_has_fill_none(tag) || (known && ~has_fill)
                continue;
            end
            if ~(known && has_fill)
                rgb = get_default_color(class_name);
                alpha = 1.0;
            end
            hrect = rectangle('Parent', ax, 'Position', [x, y, w, h], ...
                'EdgeColor', 'k', 'FaceColor', rgb);
            if alpha < 1.0
                try
                    set(hrect, 'FaceAlpha', alpha);
                catch
                end
            end
        end
    end

    % --- Draw turns from metadata when available (preserves winding identity) ---
    % Keep disabled by default: PM SVG already contains authoritative turn
    % geometry and this remap can drift turns outside the bobbin for some cores.
    use_meta_turns = false;
    render_meta_turns = false;
    if render_meta_turns && ~isempty(vb) && isstruct(om_meta) && isfield(om_meta, 'turns') && ...
            isfield(om_meta, 'core_width_m') && isfield(om_meta, 'core_half_height_m')
        core_w = om_meta.core_width_m;
        core_h_half = om_meta.core_half_height_m;
        turns = om_meta.turns;
        if core_w > 0 && core_h_half > 0 && ~isempty(turns)
            cx_vb = vb(1) + vb(3) / 2;
            cy_vb = vb(2) + vb(4) / 2;
            sx = core_w / vb(3);
            sy = (2 * core_h_half) / vb(4);
            if sx > 0 && sy > 0
                r_scale = 0.5 * (1 / sx + 1 / sy);
                if ~isstruct(turns)
                    try
                        turns = [turns{:}];
                    catch
                        turns = struct([]);
                    end
                end
                for i = 1:numel(turns)
                    t = turns(i);
                    if ~isstruct(t) || ~isfield(t, 'x_m') || ~isfield(t, 'y_m') || ~isfield(t, 'r_m')
                        continue;
                    end
                    x_svg = cx_vb + t.x_m / sx;
                    y_svg = cy_vb - t.y_m / sy;
                    r_svg = max(0.05, t.r_m * r_scale);
                    winding_name = '';
                    if isfield(t, 'winding')
                        winding_name = t.winding;
                    end
                    rgb = get_winding_color_local(winding_name, data);
                    theta = linspace(0, 2*pi, 30);
                    fill(ax, x_svg + r_svg*cos(theta), y_svg + r_svg*sin(theta), ...
                        rgb, 'EdgeColor', 'none');
                end
                use_meta_turns = true;
            end
        end
    end

    % --- Draw circles from SVG when metadata is not available ---
    if ~use_meta_turns
        circle_tags = regexp(svg_str, '<circle[^>]*>', 'match');
        for i = 1:length(circle_tags)
            tag = circle_tags{i};
            cx = get_attr(tag, 'cx');
            cy = get_attr(tag, 'cy');
            r = get_attr(tag, 'r');
        class_name = get_attr_str(tag, 'class');
        [rgb, alpha, has_fill, known, stroke_rgb, stroke_w, has_stroke] = get_class_style(class_name, color_map);

        if ~isnan(cx) && ~isnan(cy) && ~isnan(r)
            is_no_fill = tag_has_fill_none(tag) || (known && ~has_fill);
            if is_no_fill
                if has_stroke
                    draw_stroke_circle_local(cx, cy, r, stroke_rgb, stroke_w, alpha);
                end
                continue;
            end
            if ~(known && has_fill)
                rgb = get_default_color(class_name);
                alpha = 1.0;
            end
            theta = linspace(0, 2*pi, 30);
            edge_color = 'none';
            edge_w = 0.1;
            if has_stroke
                edge_color = stroke_rgb;
                edge_w = max(0.1, min(stroke_w, 2.0));
            end
            h = fill(ax, cx + r*cos(theta), cy + r*sin(theta), ...
                rgb, 'EdgeColor', edge_color, 'LineWidth', edge_w);
            if alpha < 1.0
                try
                    set(h, 'FaceAlpha', alpha);
                catch
                end
            end
        end
    end
    end

    axis(ax, 'equal');
    apply_om_axes_mm(ax, vb, om_meta);
    title(ax, '');
    hold(ax, 'off');

    function rgb = get_winding_color_local(winding_name, data_local)
        rgb = [0.722 0.451 0.200];
        try
            if ~isstruct(data_local) || ~isfield(data_local, 'windings') || ~isfield(data_local, 'winding_colors')
                return;
            end
            n = min(numel(data_local.windings), numel(data_local.winding_colors));
            wq = strtrim(lower(char(winding_name)));
            if isempty(wq)
                return;
            end
            for wi = 1:n
                wn = '';
                if isfield(data_local.windings(wi), 'name')
                    wn = data_local.windings(wi).name;
                end
                if strcmpi(strtrim(char(wn)), wq)
                    c = data_local.winding_colors{wi};
                    if numel(c) == 3
                        rgb = c;
                    end
                    return;
                end
            end
        catch
        end
    end

    function draw_stroke_circle_local(cx, cy, r, stroke_rgb, stroke_w, alpha_val)
        if isempty(stroke_rgb)
            stroke_rgb = [0 0 0];
        end
        if ~isfinite(stroke_w) || stroke_w <= 0
            stroke_w = max(0.3, 0.05 * r);
        end
        if ~isfinite(alpha_val) || alpha_val <= 0
            alpha_val = 1.0;
        end

        theta = linspace(0, 2*pi, 80);
        r_outer = max(r + 0.5 * stroke_w, r);
        r_inner = max(r - 0.5 * stroke_w, 0);
        if r_inner > 0
            xo = cx + r_outer * cos(theta);
            yo = cy + r_outer * sin(theta);
            xi = cx + r_inner * cos(theta(end:-1:1));
            yi = cy + r_inner * sin(theta(end:-1:1));
            hs = patch(ax, [xo, xi], [yo, yi], stroke_rgb, 'EdgeColor', 'none');
        else
            hs = fill(ax, cx + r_outer*cos(theta), cy + r_outer*sin(theta), ...
                stroke_rgb, 'EdgeColor', 'none');
        end
        if alpha_val < 1.0
            try
                set(hs, 'FaceAlpha', alpha_val);
            catch
            end
        end
    end

end

function apply_axes_mm(ax, top_axis)
    if nargin < 2
        top_axis = false;
    end
    xlim_v = xlim(ax);
    ylim_v = ylim(ax);
    if any(~isfinite([xlim_v, ylim_v])) || diff(xlim_v) <= 0 || diff(ylim_v) <= 0
        return;
    end

    xt = linspace(xlim_v(1), xlim_v(2), 6);
    yt = linspace(ylim_v(1), ylim_v(2), 7);
    xlbl = arrayfun(@(v) sprintf('%.1f', v * 1e3), xt, 'UniformOutput', false);
    ylbl = arrayfun(@(v) sprintf('%.1f', v * 1e3), yt, 'UniformOutput', false);

    set(ax, 'Box', 'on', ...
        'XColor', [0.15 0.15 0.15], ...
        'YColor', [0.15 0.15 0.15], ...
        'FontSize', 8, ...
        'XTick', xt, 'YTick', yt, ...
        'XTickLabel', xlbl, 'YTickLabel', ylbl);
    if top_axis
        try
            set(ax, 'XAxisLocation', 'top');
        catch
        end
    end
    xlabel(ax, 'Width (mm)');
    ylabel(ax, 'Height (mm)');
end

function apply_window_axes_mm(ax, window_w_m, window_h_m, top_axis)
    if nargin < 4
        top_axis = false;
    end
    if window_w_m <= 0 || window_h_m <= 0
        apply_axes_mm(ax, top_axis);
        return;
    end

    xt = [0, 0.25*window_w_m, 0.5*window_w_m, 0.75*window_w_m, window_w_m];
    yt = [0, 0.25*window_h_m, 0.5*window_h_m, 0.75*window_h_m, window_h_m];
    xlbl = arrayfun(@(v) sprintf('%.1f', v * 1e3), xt, 'UniformOutput', false);
    ylbl = arrayfun(@(v) sprintf('%.1f', v * 1e3), yt, 'UniformOutput', false);

    set(ax, 'Box', 'on', ...
        'XColor', [0.15 0.15 0.15], ...
        'YColor', [0.15 0.15 0.15], ...
        'FontSize', 8, ...
        'XTick', xt, 'YTick', yt, ...
        'XTickLabel', xlbl, 'YTickLabel', ylbl);
    if top_axis
        try
            set(ax, 'XAxisLocation', 'top');
        catch
        end
    end
    xlabel(ax, 'Width (mm)');
    ylabel(ax, 'Height (mm)');
end

function apply_om_axes_mm(ax, vb, om_meta)
    % Map SVG coordinates to physical millimeters using OM processed dimensions.
    if isempty(vb) || numel(vb) ~= 4
        apply_axes_mm(ax, true);
        return;
    end

    core_w = 0;
    core_h_half = 0;
    if isstruct(om_meta)
        if isfield(om_meta, 'core_width_m')
            core_w = om_meta.core_width_m;
        end
        if isfield(om_meta, 'core_half_height_m')
            core_h_half = om_meta.core_half_height_m;
        end
    end

    if core_w <= 0 || core_h_half <= 0
        apply_axes_mm(ax, true);
        return;
    end

    x0 = vb(1); y0 = vb(2); vw = vb(3); vh = vb(4);
    if vw <= 0 || vh <= 0
        apply_axes_mm(ax, true);
        return;
    end

    cx = x0 + vw / 2;
    cy = y0 + vh / 2;
    sx = core_w / vw;
    sy = (2 * core_h_half) / vh;

    x_ticks_m = [-0.5*core_w, -0.25*core_w, 0, 0.25*core_w, 0.5*core_w];
    y_ticks_m = [-core_h_half, -0.5*core_h_half, 0, 0.5*core_h_half, core_h_half];
    xt = cx + (x_ticks_m ./ sx);
    yt = cy - (y_ticks_m ./ sy);
    xlbl = arrayfun(@(v) sprintf('%.1f', v * 1e3), x_ticks_m, 'UniformOutput', false);
    ylbl = arrayfun(@(v) sprintf('%.1f', v * 1e3), y_ticks_m, 'UniformOutput', false);
    % MATLAB/Octave sorts YTick ascending, so sort yt+ylbl together to keep labels aligned
    [yt, sort_idx] = sort(yt);
    ylbl = ylbl(sort_idx);

    set(ax, 'Box', 'on', ...
        'XColor', [0.15 0.15 0.15], ...
        'YColor', [0.15 0.15 0.15], ...
        'FontSize', 8, ...
        'XTick', xt, 'YTick', yt, ...
        'XTickLabel', xlbl, 'YTickLabel', ylbl);
    try
        set(ax, 'XAxisLocation', 'top');
    catch
    end
    xlabel(ax, 'Width (mm)');
    ylabel(ax, 'Height (mm)');
end

function set_vis_metrics_text(data, txt)
    ctrl = findobj(data.fig_gui, 'Tag', 'vis_metrics');
    if ~isempty(ctrl)
        set(ctrl, 'String', txt);
    end
end

function warn_str = check_om_turn_issues(om_meta)
    % Check OM turns metadata for overflow and overlap issues.
    % Returns a warning string (empty if no issues).
    warn_str = '';
    if ~isstruct(om_meta) || ~isfield(om_meta, 'turns') || isempty(om_meta.turns)
        return;
    end
    turns = om_meta.turns;
    if ~isstruct(turns)
        try turns = [turns{:}]; catch; return; end
    end

    bw = 0; bh = 0;
    if isfield(om_meta, 'bobbin_window_width_m')
        bw = om_meta.bobbin_window_width_m;
    end
    if isfield(om_meta, 'bobbin_window_height_m')
        bh = om_meta.bobbin_window_height_m;
    end
    if bw <= 0 || bh <= 0; return; end

    % Collect turn centers and radii in physical coords relative to bobbin
    n = numel(turns);
    tx = zeros(n,1); ty = zeros(n,1); tr = zeros(n,1);
    xmin = inf; xmax = -inf; ymin = inf; ymax = -inf;
    valid = false(n,1);
    for i = 1:n
        t = turns(i);
        if ~isfield(t,'x_m') || ~isfield(t,'y_m'); continue; end
        r = 0;
        if isfield(t,'r_m'); r = double(t.r_m); end
        if isfield(t,'width_m'); r = max(r, double(t.width_m)/2); end
        if r <= 0; continue; end
        tx(i) = double(t.x_m); ty(i) = double(t.y_m); tr(i) = r;
        valid(i) = true;
        xmin = min(xmin, tx(i)-r); xmax = max(xmax, tx(i)+r);
        ymin = min(ymin, ty(i)-r); ymax = max(ymax, ty(i)+r);
    end
    if ~any(valid); return; end

    % Center turns to bobbin local frame
    cx = 0.5*(xmin+xmax); cy = 0.5*(ymin+ymax);
    tcx = bw/2; tcy = bh/2;
    lx = tx - cx + tcx;
    ly = ty - cy + tcy;

    n_overflow = 0;
    for i = 1:n
        if ~valid(i); continue; end
        if lx(i)-tr(i) < -1e-6 || lx(i)+tr(i) > bw+1e-6 || ...
           ly(i)-tr(i) < -1e-6 || ly(i)+tr(i) > bh+1e-6
            n_overflow = n_overflow + 1;
        end
    end

    n_overlap = 0;
    for i = 1:n
        if ~valid(i); continue; end
        for j = (i+1):n
            if ~valid(j); continue; end
            dist = sqrt((tx(i)-tx(j))^2 + (ty(i)-ty(j))^2);
            min_dist = tr(i) + tr(j);
            if dist < min_dist * 0.95
                n_overlap = n_overlap + 1;
            end
        end
    end

    parts = {};
    if n_overflow > 0
        parts{end+1} = sprintf('WARNING: %d turn(s) outside bobbin', n_overflow);
    end
    if n_overlap > 0
        parts{end+1} = sprintf('WARNING: %d turn pair(s) overlap', n_overlap);
    end
    if ~isempty(parts)
        warn_str = strjoin(parts, ' | ');
    end
end

function metrics = get_cwf_window_metrics(data)
    metrics = struct( ...
        'width_m', 0, 'height_m', 0, 'area_m2', 0, ...
        'usable_width_m', 0, 'usable_height_m', 0, 'usable_area_m2', 0, ...
        'edge_margin_m', 0);
    try
        if strcmp(data.selected_core, 'None')
            return;
        end
        core = data.cores.(data.selected_core);
        bobbin = data.layout_calc.get_bobbin_dimensions(core);
        om_ref = get_cached_om_window_metrics(data);
        edge_margin = 0;
        if isfield(data, 'edge_margin')
            edge_margin = max(0, data.edge_margin);
        end
        if om_ref.area_m2 > 0
            bw = max(1e-12, om_ref.width_m);
            bh = max(1e-12, om_ref.height_m);
        else
            bw = max(1e-12, bobbin.width);
            bh = max(1e-12, bobbin.height);
        end
        ubw = max(1e-12, bobbin.width - 2 * edge_margin);
        ubh = max(1e-12, bobbin.height - 2 * edge_margin);
        if om_ref.area_m2 > 0
            ubw = max(1e-12, bw - 2 * edge_margin);
            ubh = max(1e-12, bh - 2 * edge_margin);
        end
        metrics.width_m = bw;
        metrics.height_m = bh;
        metrics.area_m2 = bw * bh;
        metrics.usable_width_m = ubw;
        metrics.usable_height_m = ubh;
        metrics.usable_area_m2 = ubw * ubh;
        metrics.edge_margin_m = edge_margin;
    catch
    end
end

function metrics = get_cached_om_window_metrics(data)
    metrics = struct('width_m', 0, 'height_m', 0, 'area_m2', 0);
    if ~isfield(data, 'om_window_cache') || ~isstruct(data.om_window_cache)
        return;
    end
    if ~isfield(data, 'selected_core')
        return;
    end
    key = make_core_cache_key(data.selected_core);
    if isempty(key) || ~isfield(data.om_window_cache, key)
        return;
    end
    cached = data.om_window_cache.(key);
    if isstruct(cached) && isfield(cached, 'area_m2') && cached.area_m2 > 0
        metrics = cached;
    end
end

function cache = set_om_window_cache_entry(cache, core_name, metrics)
    if ~isstruct(cache)
        cache = struct();
    end
    if ~isstruct(metrics) || ~isfield(metrics, 'area_m2') || metrics.area_m2 <= 0
        return;
    end
    key = make_core_cache_key(core_name);
    if isempty(key)
        return;
    end
    cache.(key) = metrics;
end

function key = make_core_cache_key(core_name)
    if isempty(core_name)
        key = '';
        return;
    end
    key = regexprep(char(core_name), '[^a-zA-Z0-9_]', '_');
    if isempty(key)
        key = 'core';
    end
    if ~isempty(regexp(key, '^[0-9]', 'once'))
        key = ['c_' key];
    end
end

function metrics = get_om_window_metrics(om_meta)
    metrics = struct('width_m', 0, 'height_m', 0, 'area_m2', 0);
    if ~isstruct(om_meta)
        return;
    end
    if isfield(om_meta, 'bobbin_window_width_m')
        metrics.width_m = om_meta.bobbin_window_width_m;
    end
    if isfield(om_meta, 'bobbin_window_height_m')
        metrics.height_m = om_meta.bobbin_window_height_m;
    end
    if isfield(om_meta, 'bobbin_window_area_m2')
        metrics.area_m2 = om_meta.bobbin_window_area_m2;
    elseif metrics.width_m > 0 && metrics.height_m > 0
        metrics.area_m2 = metrics.width_m * metrics.height_m;
    end
end

function color_map = parse_css_colors(svg_str)
    % Parse CSS <style> block to extract class name -> color mapping
    color_map = struct();
    style_match = regexp(svg_str, '<style[^>]*>\s*<!\[CDATA\[(.*?)\]\]>\s*</style>', 'tokens', 'once');
    if isempty(style_match)
        style_match = regexp(svg_str, '<style[^>]*>(.*?)</style>', 'tokens', 'once');
    end
    if isempty(style_match)
        return;
    end
    css_text = style_match{1};
    rules = regexp(css_text, '\.([A-Za-z_][A-Za-z0-9_]*)\s*\{([^}]*)\}', 'tokens');
    for i = 1:length(rules)
        class_name = rules{i}{1};
        rule_body = rules{i}{2};
        safe_name = make_safe_field(class_name);
        has_fill = false;
        rgb = [];
        fill_none = ~isempty(regexp(rule_body, 'fill:\s*none', 'once'));
        if ~fill_none
            fill_match = regexp(rule_body, 'fill:\s*#([0-9a-fA-F]{6})', 'tokens', 'once');
            if ~isempty(fill_match)
                hex = fill_match{1};
                rgb = [hex2dec(hex(1:2)), hex2dec(hex(3:4)), hex2dec(hex(5:6))] / 255;
                has_fill = true;
            end
        end
        has_stroke = false;
        stroke_rgb = [];
        stroke_w = 0;
        stroke_none = ~isempty(regexp(rule_body, 'stroke:\s*none', 'once'));
        if ~stroke_none
            stroke_match = regexp(rule_body, 'stroke:\s*#([0-9a-fA-F]{6})', 'tokens', 'once');
            if ~isempty(stroke_match)
                shex = stroke_match{1};
                stroke_rgb = [hex2dec(shex(1:2)), hex2dec(shex(3:4)), hex2dec(shex(5:6))] / 255;
                has_stroke = true;
            end
            stroke_w_match = regexp(rule_body, 'stroke-width:\s*([0-9.]+)', 'tokens', 'once');
            if ~isempty(stroke_w_match)
                stroke_w = str2double(stroke_w_match{1});
            end
            if ~isfinite(stroke_w) || stroke_w < 0
                stroke_w = 0;
            end
            has_stroke = has_stroke && stroke_w > 0;
        end
        opacity_match = regexp(rule_body, 'opacity:\s*([0-9.]+)', 'tokens', 'once');
        alpha = 1.0;
        if ~isempty(opacity_match)
            alpha = str2double(opacity_match{1});
        end
        color_map.(safe_name) = struct( ...
            'rgb', rgb, 'alpha', alpha, 'has_fill', has_fill, ...
            'stroke_rgb', stroke_rgb, 'stroke_w', stroke_w, 'has_stroke', has_stroke);
    end
end

function [rgb, alpha, has_fill, known, stroke_rgb, stroke_w, has_stroke] = get_class_style(class_name, color_map)
    rgb = [];
    alpha = 1.0;
    has_fill = true;
    known = false;
    stroke_rgb = [];
    stroke_w = 0;
    has_stroke = false;
    safe_name = make_safe_field(class_name);
    if isfield(color_map, safe_name)
        entry = color_map.(safe_name);
        known = true;
        if isfield(entry, 'alpha'); alpha = entry.alpha; end
        if isfield(entry, 'has_fill'); has_fill = entry.has_fill; end
        if isfield(entry, 'rgb'); rgb = entry.rgb; end
        if isfield(entry, 'stroke_rgb'); stroke_rgb = entry.stroke_rgb; end
        if isfield(entry, 'stroke_w'); stroke_w = entry.stroke_w; end
        if isfield(entry, 'has_stroke'); has_stroke = entry.has_stroke; end
    end
end

function rgb = get_default_color(class_name)
    switch class_name
        case 'ferrite'
            rgb = [0.482 0.486 0.490];
        case 'bobbin'
            rgb = [0.325 0.592 0.588];
        case 'copper'
            rgb = [0.722 0.451 0.200];
        case 'insulation'
            rgb = [1.000 0.941 0.357];
        case 'spacer'
            rgb = [0.231 0.231 0.231];
        case 'fr4'
            rgb = [0.0 0.5 0.0];
        otherwise
            rgb = [0.9 0.9 0.9];
    end
end

function tf = tag_has_fill_none(tag)
    tf = ~isempty(regexp(tag, 'fill\s*=\s*["'']none["'']', 'once')) || ...
         ~isempty(regexp(tag, 'fill\s*:\s*none', 'once'));
end

function safe = make_safe_field(name)
    safe = regexprep(name, '[^a-zA-Z0-9_]', '_');
    if ~isempty(safe) && (safe(1) >= '0' && safe(1) <= '9')
        safe = ['c_' safe];
    end
    if isempty(safe)
        safe = 'unknown';
    end
end


% ================================================================
% CORE LOSS & MAGNETIC PARAMETER COMPUTATION
% ================================================================

function [B_waveform, t] = compute_flux_waveform_forward(Vin, duty, fsw, N, Ae, n_samples)
% Compute B(t) for a 2-switch forward converter primary.
% V(t) = +Vin for 0<t<D/f, -Vin for D/f<t<2D/f, 0 for 2D/f<t<1/f
% B(t) = (1/N*Ae) * integral(V(t) dt) + B_offset
    if nargin < 6, n_samples = 512; end
    T = 1/fsw;
    t = linspace(0, T, n_samples+1)';
    t = t(1:end-1);  % one full period, no duplicate endpoint
    dt = T / n_samples;

    % Voltage waveform: +Vin during D, -Vin during reset (D), 0 during 1-2D
    V = zeros(size(t));
    t_on  = duty * T;
    t_reset = 2 * duty * T;
    for i = 1:length(t)
        if t(i) < t_on
            V(i) = Vin;
        elseif t(i) < t_reset
            V(i) = -Vin;
        else
            V(i) = 0;
        end
    end

    % Integrate voltage to get flux: B(t) = (1/N*Ae) * integral V dt
    flux = cumsum(V) * dt;   % Volt-seconds
    B_waveform = flux / (N * Ae);

    % Remove DC offset so B swings symmetrically
    B_waveform = B_waveform - mean(B_waveform);
end


function Pcore = compute_core_loss_igse(B_waveform, t, k, alpha, beta, Ve)
% iGSE core loss computation.
% Reference: Venkatachalam, Sullivan, Abdallah, Tacca (IEEE COMPEL 2002)
%
% Pv = (1/T) * integral(ki * |dB/dt|^alpha * deltaB^(beta-alpha) dt)
%
% Inputs:
%   B_waveform - B(t) values [T] over one period
%   t          - time vector [s]
%   k, alpha, beta - Steinmetz parameters
%   Ve         - core effective volume [m^3]
% Output:
%   Pcore      - total core loss [W]

    T = t(end) - t(1) + (t(2) - t(1));  % full period
    deltaB = max(B_waveform) - min(B_waveform);

    if deltaB < 1e-12 || k <= 0
        Pcore = 0;
        return;
    end

    % Compute ki coefficient
    theta = linspace(0, 2*pi, 2000);
    dtheta = theta(2) - theta(1);
    int_val = sum(abs(cos(theta)).^alpha .* 2^(beta - alpha)) * dtheta;
    ki = k / ((2*pi)^(alpha - 1) * int_val);

    % dB/dt
    dBdt = diff(B_waveform) ./ diff(t);
    t_mid = (t(1:end-1) + t(2:end)) / 2;

    % Core loss density [W/m^3]
    integrand = ki * abs(dBdt).^alpha .* deltaB^(beta - alpha);
    Pv = (1/T) * trapz(t_mid, integrand);

    Pcore = Pv * Ve;
end


function Pcore = compute_core_loss_i2gse(B_waveform, t, k, alpha, beta, Ve)
% i²GSE core loss computation with relaxation.
% Reference: Muhlethaler, Biela, Kolar, Ecklebe (IEEE TPE 2012)
%
% Extends iGSE with relaxation loss during constant-B intervals.

    T = t(end) - t(1) + (t(2) - t(1));
    deltaB = max(B_waveform) - min(B_waveform);

    if deltaB < 1e-12 || k <= 0
        Pcore = 0;
        return;
    end

    % Compute ki (same as iGSE)
    theta = linspace(0, 2*pi, 2000);
    dtheta = theta(2) - theta(1);
    int_val = sum(abs(cos(theta)).^alpha .* 2^(beta - alpha)) * dtheta;
    ki = k / ((2*pi)^(alpha - 1) * int_val);

    % dB/dt
    dBdt = diff(B_waveform) ./ diff(t);
    dt_vec = diff(t);

    % Identify segments: active (|dB/dt| > threshold) vs relaxation
    threshold = 0.01 * max(abs(dBdt));  % 1% of peak dB/dt

    Pv_total = 0;
    N = length(dBdt);

    % Relaxation time constant estimate (material-dependent, typical ~10us)
    tau_relax = 10e-6;

    last_active_dB = 0;
    relax_start = false;

    for i = 1:N
        if abs(dBdt(i)) > threshold
            % Active segment: standard iGSE contribution
            Pv_total = Pv_total + ki * abs(dBdt(i))^alpha * deltaB^(beta - alpha) * dt_vec(i);
            last_active_dB = abs(dBdt(i)) * dt_vec(i);  % flux change in this step
            relax_start = true;
        else
            % Relaxation segment: add decaying loss term
            if relax_start && last_active_dB > 0
                % Relaxation contribution proportional to last flux change
                relax_loss = ki * (last_active_dB / dt_vec(i))^alpha * ...
                             deltaB^(beta - alpha) * dt_vec(i) * ...
                             exp(-dt_vec(i) / tau_relax);
                Pv_total = Pv_total + relax_loss;
                relax_start = false;
            end
        end
    end

    Pv = Pv_total / T;
    Pcore = Pv * Ve;
end


function mag_results = compute_magnetic_params(data, geom)
% Compute magnetic parameters (Lm, Llk, Bpk, core loss) from PEEC + core data.
%
% Lm: Computed from reluctance network: Lm = N^2 / (R_core + sum(R_gap))
%     Includes gap reluctance with Partridge fringing correction.
%     The PEEC L matrix is air-core only (uses mu_0, not mu_r), so it
%     CANNOT provide Lm. Only the reluctance network model can.
%
% Llk: Extracted from PEEC air-core L matrix (Margueron/Keradec 2007).
%      Leakage flux travels through air, so free-space PEEC is correct.
%
% Returns struct with:
%   .Lm_H, .Llk_pri_H, .Llk_sec_H - inductances [H]
%   .Bpk_T, .deltaB_T - flux density [T]
%   .Pcore_W - core loss [W]
%   .method - core loss method used
%   .valid - true if computation succeeded

    mag_results = struct('valid', false, 'Lm_H', 0, 'Llk_pri_H', 0, 'Llk_sec_H', 0, ...
                         'Bpk_T', 0, 'deltaB_T', 0, 'Pcore_W', 0, 'method', '', ...
                         'Lm_source', '', 'R_core', 0, 'R_gap_total', 0, ...
                         'R_total', 0, 'n_gaps_used', 0);

    % --- Get core parameters ---
    core_params = data.api.get_core_params(data.selected_core);
    Ae = core_params.Ae;
    Ve = core_params.Ve;
    MLT = core_params.MLT;

    if Ae <= 0 || MLT <= 0
        fprintf('  Magnetic params: missing Ae (%.2e) or MLT (%.4f) for core %s\n', ...
                Ae, MLT, data.selected_core);
        return;
    end

    % --- Get material permeability for reluctance model ---
    mu_r = data.api.get_initial_permeability(data.selected_material);
    if mu_r <= 0
        fprintf('  Magnetic params: no initial permeability for material %s\n', ...
                data.selected_material);
    else
        fprintf('  Core: Ae=%.2e m2, le=%.4f m, mu_r=%.0f (%s)\n', ...
                Ae, core_params.le, mu_r, data.selected_material);
    end

    % --- Build gapping array from GUI gap settings ---
    gapping = data.api.build_gapping_array(data.core_gap_type, ...
                                            data.core_gap_length, ...
                                            data.core_num_gaps);
    if isempty(gapping)
        % Default: add residual gap (ungapped core still has ~10um air gap)
        gapping = {struct('type', 'residual', 'length', 10e-6)};
    end
    n_gaps = length(gapping);
    total_gap = 0;
    for gi = 1:n_gaps
        total_gap = total_gap + gapping{gi}.length;
    end
    fprintf('  Gap: %s, %d gap(s), total=%.1f um\n', ...
            data.core_gap_type, n_gaps, total_gap * 1e6);

    % --- Extract leakage inductance from PEEC + Lm from reluctance network ---
    try
        mp = compute_winding_inductance_matrix(geom, MLT, core_params, mu_r, gapping);
        mag_results.Lm_H = mp.Lm;
        mag_results.Lm_source = mp.Lm_source;
        mag_results.Llk_pri_H = mp.Llk_pri;
        mag_results.Llk_sec_H = mp.Llk_sec;
        mag_results.coupling_k = mp.coupling_k;
        mag_results.n_eff = mp.n_eff;
        mag_results.L_winding = mp.L_winding;
        mag_results.R_core = mp.R_core;
        mag_results.R_gap_total = mp.R_gap_total;
        mag_results.R_total = mp.R_total;
        mag_results.n_gaps_used = mp.n_gaps_used;
    catch ME
        fprintf('  Magnetic params: inductance extraction failed: %s\n', ME.message);
        return;
    end

    % --- Compute B(t) and peak flux density ---
    fsw = data.f;
    Npri = data.windings(1).n_turns;
    if Npri <= 0
        fprintf('  Magnetic params: Npri = 0\n');
        return;
    end

    % Get Vin and duty from design spec if available (forward converter)
    Vin = 0; duty = 0;
    if isfield(data, 'design_spec') && ~isempty(data.design_spec)
        spec = data.design_spec;
        if isfield(spec, 'converter')
            if isfield(spec.converter, 'vin_nom'), Vin = spec.converter.vin_nom; end
        end
        if isfield(spec, 'requirements')
            if isfield(spec.requirements, 'duty_nom'), duty = spec.requirements.duty_nom; end
        end
    end

    if Vin > 0 && duty > 0 && fsw > 0
        % Forward converter: compute B(t) from voltage waveform
        [B_waveform, t_B] = compute_flux_waveform_forward(Vin, duty, fsw, Npri, Ae);
        mag_results.Bpk_T = max(abs(B_waveform));
        mag_results.deltaB_T = max(B_waveform) - min(B_waveform);
    else
        % Fallback: estimate from Lm and current
        % deltaB = Lm * I_pp / (Npri * Ae)
        % For simple sinusoidal estimate:
        I_rms = data.windings(1).current;
        I_pk = I_rms * sqrt(2);
        mag_results.Bpk_T = mag_results.Lm_H * I_pk / (Npri * Ae);
        mag_results.deltaB_T = 2 * mag_results.Bpk_T;

        % Synthesize triangular B waveform for core loss
        n_samples = 512;
        T = 1/fsw;
        t_B = linspace(0, T, n_samples)';
        % Manual triangular wave (no dependency on signal package)
        phase = mod(t_B * fsw, 1);  % 0 to 1
        tri = zeros(size(phase));
        for ti = 1:length(phase)
            if phase(ti) < 0.5
                tri(ti) = 4 * phase(ti) - 1;  % -1 to +1
            else
                tri(ti) = 3 - 4 * phase(ti);  % +1 to -1
            end
        end
        B_waveform = mag_results.deltaB_T/2 * tri;
    end

    % --- Compute core loss ---
    sk = data.steinmetz.k;
    sa = data.steinmetz.alpha;
    sb = data.steinmetz.beta;

    if ~isempty(sk) && ~isempty(sa) && ~isempty(sb) && Ve > 0
        if strcmp(data.core_loss_method, 'i2GSE')
            mag_results.Pcore_W = compute_core_loss_i2gse(B_waveform, t_B, sk, sa, sb, Ve);
            mag_results.method = 'i2GSE';
        else
            mag_results.Pcore_W = compute_core_loss_igse(B_waveform, t_B, sk, sa, sb, Ve);
            mag_results.method = 'iGSE';
        end
    else
        mag_results.method = 'N/A (no Steinmetz data)';
    end

    mag_results.valid = true;
end
