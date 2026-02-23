function files_written = generate_real_mas_cases(case_dir, options)
%GENERATE_REAL_MAS_CASES Build a "real-use" case pack from MAS templates.
%
% This generator clones baseline MAS cases into a separate pack and stamps
% metadata fields so they can be benchmarked independently as real-use runs.

    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(case_dir)
        case_dir = fullfile(here, 'mas_cases_real');
    end
    if nargin < 2 || ~isstruct(options)
        options = struct();
    end
    clean_case_dir = get_opt_bool(options, 'clean_case_dir', true);
    if ~exist(case_dir, 'dir')
        mkdir(case_dir);
    end
    if clean_case_dir
        clear_existing_case_files(case_dir);
    end

    src_dir = fullfile(here, 'mas_cases');
    if ~exist(src_dir, 'dir') || isempty(dir(fullfile(src_dir, '*.json')))
        generate_default_mas_cases(src_dir);
    end

    src_files = sort({dir(fullfile(src_dir, '*.json')).name});
    if isempty(src_files)
        error('generate_real_mas_cases: no source cases available in %s', src_dir);
    end

    files_written = cell(1, numel(src_files));
    for i = 1:numel(src_files)
        src_path = fullfile(src_dir, src_files{i});
        data = load_json(src_path);

        base_id = strip_json_suffix(src_files{i});
        case_id = sprintf('real_case_%02d_%s', i, base_id);
        data = stamp_real_case_metadata(data, case_id, i);

        out_file = fullfile(case_dir, [case_id '.json']);
        write_json(data, out_file);
        files_written{i} = out_file;
    end
end

function data = stamp_real_case_metadata(data, case_id, ordinal)
    if ~isstruct(data)
        data = struct();
    end
    if ~isfield(data, 'meta') || ~isstruct(data.meta)
        data.meta = struct();
    end
    data.meta.case_id = case_id;
    data.meta.source_solver = get_struct_str(data.meta, 'source_solver', 'internal_realistic');
    data.meta.case_pack = 'mas_cases_real';
    data.meta.scenario = get_struct_str(data.meta, 'scenario', sprintf('real_use_case_%02d', ordinal));

    if ~isfield(data, 'benchmark') || ~isstruct(data.benchmark)
        data.benchmark = struct();
    end
    if ~isfield(data.benchmark, 'operating_profile')
        data.benchmark.operating_profile = struct();
    end
    data.benchmark.operating_profile.case_pack = 'real';
    data.benchmark.operating_profile.ordinal = ordinal;
end

function obj = load_json(in_file)
    fid = fopen(in_file, 'r');
    if fid == -1
        error('generate_real_mas_cases: cannot open %s', in_file);
    end
    raw = fread(fid, '*char')';
    fclose(fid);
    raw = sanitize_json_text(raw);
    obj = jsondecode(raw);
end

function write_json(payload, out_file)
    fid = fopen(out_file, 'w');
    if fid == -1
        error('generate_real_mas_cases: cannot write %s', out_file);
    end
    fwrite(fid, jsonencode(payload));
    fclose(fid);
end

function s = strip_json_suffix(name_in)
    s = char(name_in);
    if numel(s) > 5 && strcmpi(s(end-4:end), '.json')
        s = s(1:end-5);
    end
end

function txt = sanitize_json_text(txt)
    if isempty(txt)
        return;
    end
    if double(txt(1)) == 65279
        txt = txt(2:end);
    end
    txt = strtrim(txt);
end

function out = get_struct_str(s, field_name, default_val)
    out = default_val;
    if ~isstruct(s) || ~isfield(s, field_name)
        return;
    end
    v = s.(field_name);
    if ischar(v)
        out = char(v);
        return;
    end
    if (exist('isstring', 'builtin') || exist('isstring', 'file')) && isstring(v)
        out = char(v);
    end
end

function clear_existing_case_files(case_dir)
    stale = dir(fullfile(case_dir, '*.json'));
    for i = 1:numel(stale)
        delete(fullfile(case_dir, stale(i).name));
    end
end

function out = get_opt_bool(s, field_name, default_val)
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
