local Updater = {}

local PACKAGE_NAME = "rime-lua-aux-code"
local NPM_MIRROR_BASE = "https://registry.npmmirror.com"
local NPM_REGISTRY_BASE = "https://registry.npmjs.org"
local STATE_DIRNAME = ".update"
local BACKUP_DIRNAME = "backup"
local WORK_DIRNAME = "work"
local CURL_TIMEOUT = 30
local CURL_CONNECT_TIMEOUT = 10

local UPDATE_FILES = { "aux_code.lua", "aux_code_updater.lua" }
local REL_PATH_PREFIX = "lua/"

local SAFE_HOSTS = {
    ["registry.npmmirror.com"] = true,
    ["registry.npmjs.org"] = true,
}

local PHASE = {
    INIT = "init", IDLE = "idle",
    LAUNCH_CHECK = "launch_check", CHECKING = "checking",
    LAUNCH_CURRENT_META = "launch_current_meta", FETCHING_CURRENT = "fetching_current",
    LAUNCH_LOCAL_HASH = "launch_local_hash", HASHING_LOCAL = "hashing_local",
    LAUNCH_TARGET_META = "launch_target_meta", FETCHING_TARGET = "fetching_target",
    LAUNCH_DOWNLOAD = "launch_download", DOWNLOADING = "downloading",
    LAUNCH_TARBALL_HASH = "launch_tarball_hash", HASHING_TARBALL = "hashing_tarball",
    LAUNCH_EXTRACT = "launch_extract", EXTRACTING = "extracting",
    LAUNCH_EXTRACTED_HASH = "launch_extracted_hash", HASHING_EXTRACTED = "hashing_extracted",
    BACKING_UP = "backing_up", REPLACING = "replacing", COMMITTING = "committing",
    NOTIFIED = "notified", DONE = "done", ERROR = "error", OFF = "off",
}

local MODE = { OFF = "off", NOTIFY = "notify", AUTO = "auto" }
local DEFAULT_MODE = MODE.NOTIFY
local DEFAULT_INTERVAL_DAYS = 7

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64_encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local b1, b2, b3 = data:byte(i, i + 2)
        b2 = b2 or 0
        b3 = b3 or 0
        local n = b1 * 65536 + b2 * 256 + b3
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = b64chars:sub(c1 + 1, c1 + 1)
        out[#out + 1] = b64chars:sub(c2 + 1, c2 + 1)
        out[#out + 1] = (i + 1 <= #data) and b64chars:sub(c3 + 1, c3 + 1) or "="
        out[#out + 1] = (i + 2 <= #data) and b64chars:sub(c4 + 1, c4 + 1) or "="
    end
    return table.concat(out)
end

local function hex_to_binary(hex)
    return (hex:gsub("..", function(pair)
        return string.char(tonumber(pair, 16))
    end))
end

local function is_windows()
    return package.config:sub(1, 1) == "\\"
end

local function path_join(...)
    local result = nil
    for i = 1, select("#", ...) do
        local p = tostring(select(i, ...) or "")
        p = p:gsub("\\", "/")
        if p ~= "" then
            if not result then
                result = p:gsub("/+$", "")
            else
                p = p:gsub("^/+", ""):gsub("/+$", "")
                if p ~= "" then
                    result = result .. "/" .. p
                end
            end
        end
    end
    return result or ""
end

local function shell_escape_path(path)
    if is_windows() then return '"' .. path:gsub("/", "\\"):gsub('"', '""') .. '"' end
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function shell_escape(value)
    if is_windows() then return '"' .. value:gsub('"', '""') .. '"' end
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function path_exists(path)
    local ok, _, code = os.rename(path, path)
    return ok == true or code == 13 or file_exists(path)
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function write_file(path, content)
    local f = io.open(path, "wb")
    if not f then return nil end
    f:write(content)
    local ok = f:close()
    return ok ~= nil
end

local function mkdir_p(path)
    if path_exists(path) then return true end
    local parent = path:match("^(.*)[/\\]")
    if parent and parent ~= path then mkdir_p(parent) end
    if is_windows() then
        local ok = os.execute("mkdir " .. shell_escape_path(path) .. " 2>nul")
        return ok == 0 or ok == true or path_exists(path)
    end
    local ok = os.execute("mkdir -p " .. shell_escape_path(path) .. " 2>/dev/null")
    return ok == 0 or ok == true or path_exists(path)
end

local function rm_rf(path)
    if not path or path == "" or path == "/" then return end
    if is_windows() then
        os.execute("rmdir /s /q " .. shell_escape_path(path) .. " 2>nul")
    else
        os.execute("rm -rf " .. shell_escape_path(path) .. " 2>/dev/null")
    end
end

local function atomic_rename(src, dst)
    if not is_windows() then return os.rename(src, dst) end
    local ok = os.execute("move /Y " .. shell_escape_path(src) .. " " .. shell_escape_path(dst) .. " >nul 2>nul")
    return (ok == true or ok == 0) and file_exists(dst)
end

local function is_safe_url(url)
    if not url or not url:match("^https://") then return false end
    local host = url:match("^https://([^/?#:]+)")
    if not host then return false end
    host = host:lower()
    return SAFE_HOSTS[host] == true
end

local function make_curl_cmd(url, out_path)
    local part_path = out_path .. ".part"
    local curl = "curl --fail --silent --show-error --location --proto \"=https\" --proto-redir \"=https\""
        .. " --max-time " .. tostring(CURL_TIMEOUT)
        .. " --connect-timeout " .. tostring(CURL_CONNECT_TIMEOUT)
        .. " -o " .. shell_escape_path(part_path)
        .. " " .. shell_escape(url)
    if is_windows() then
        return "del /q " .. shell_escape_path(part_path) .. " " .. shell_escape_path(out_path)
            .. " 2>nul\r\n" .. curl
            .. " && move /y " .. shell_escape_path(part_path) .. " " .. shell_escape_path(out_path) .. " >nul"
    end
    return "rm -f " .. shell_escape_path(part_path) .. " " .. shell_escape_path(out_path)
        .. "\n" .. curl
        .. " && mv -f " .. shell_escape_path(part_path) .. " " .. shell_escape_path(out_path)
end

local function make_sha512_worker_body(filepath, out_path)
    local fp_esc = shell_escape_path(filepath)
    local out_esc = shell_escape_path(out_path)
    if is_windows() then
        return "certutil -hashfile " .. fp_esc .. " SHA512 > "
            .. shell_escape_path(out_path .. ".tmp") .. "\n"
            .. "findstr /i /v \"hash certutil SHA512\" " .. shell_escape_path(out_path .. ".tmp")
            .. " > " .. out_esc .. "\n"
            .. "del " .. shell_escape_path(out_path .. ".tmp")
    end
    return "if command -v sha512sum >/dev/null 2>&1; then\n"
        .. "  sha512sum " .. fp_esc .. " | cut -d' ' -f1 > " .. out_esc .. "\n"
        .. "elif command -v shasum >/dev/null 2>&1; then\n"
        .. "  shasum -a 512 " .. fp_esc .. " | cut -d' ' -f1 > " .. out_esc .. "\n"
        .. "else\n"
        .. "  openssl dgst -sha512 " .. fp_esc .. " | cut -d' ' -f2 > " .. out_esc .. "\n"
        .. "fi"
end

local function make_tar_worker_body(tarball, dest, files)
    local parts = { "tar -xzf " .. shell_escape_path(tarball)
        .. " -C " .. shell_escape_path(dest)
        .. " --strip-components=2" }
    for _, f in ipairs(files) do
        parts[#parts + 1] = " package/lua/" .. f
    end
    return table.concat(parts, " ")
end

local function launch_worker(h, name, script_body)
    local wd = path_join(h.state_dir, WORK_DIRNAME)
    mkdir_p(wd)
    local ext = is_windows() and ".cmd" or ".sh"
    local sp = path_join(wd, name .. ext)
    local of = path_join(wd, name .. ".out")
    local ef = path_join(wd, name .. ".exit")
    os.remove(sp); os.remove(of); os.remove(ef)
    local exit_escaped = shell_escape_path(ef)
    local full
    if is_windows() then
        full = "@echo off\r\n" .. script_body
            .. "\r\necho %ERRORLEVEL% > " .. exit_escaped .. "\r\n"
    else
        full = "#!/bin/sh\n" .. script_body
            .. "\nRC=$?\necho $RC > " .. exit_escaped .. "\nexit $RC\n"
    end
    if not write_file(sp, full) then return false end
    local launch_cmd
    if is_windows() then
        launch_cmd = "start \"\" /B cmd /D /C call " .. shell_escape_path(sp)
    else
        launch_cmd = "sh " .. shell_escape_path(sp) .. " >/dev/null 2>&1 &"
    end
    h.worker = { name = name, of = of, ef = ef, script = sp }
    local launched = os.execute(launch_cmd)
    if launched == true or launched == 0 then return true end
    write_file(ef, "1\n")
    return false
end

local function poll_worker(h)
    local w = h.worker
    if not w then return "done" end
    if not file_exists(w.ef) then return "busy" end
    local exit_raw = read_file(w.ef)
    if not exit_raw or exit_raw:gsub("%s+", "") == "" then return "busy" end
    local exit_code = tonumber(exit_raw:match("(%d+)"))
    os.remove(w.script)
    h.worker = nil
    if not exit_code or exit_code ~= 0 then return "error", exit_code end
    return "done"
end

local function work_dir(h)
    return path_join(h.state_dir, WORK_DIRNAME)
end

local function parse_semver(version)
    if not version or type(version) ~= "string" then return nil end
    local core, suffix = version:match("^v?(%d+%.%d+%.%d+)(.*)$")
    if not core then return nil end
    local major, minor, patch = core:match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then return nil end
    local prerelease = nil
    local build = nil
    if suffix:sub(1, 1) == "-" then
        prerelease, build = suffix:match("^%-([0-9A-Za-z%.%-]+)%+([0-9A-Za-z%.%-]+)$")
        prerelease = prerelease or suffix:match("^%-([0-9A-Za-z%.%-]+)$")
        if not prerelease then return nil end
    elseif suffix:sub(1, 1) == "+" then
        build = suffix:match("^%+([0-9A-Za-z%.%-]+)$")
        if not build then return nil end
    elseif suffix ~= "" then
        return nil
    end
    for identifiers in pairs({ [prerelease or ""] = true, [build or ""] = true }) do
        if identifiers ~= "" and (identifiers:sub(1, 1) == "." or identifiers:sub(-1) == "."
            or identifiers:find("..", 1, true)) then
            return nil
        end
    end
    return {
        major = tonumber(major), minor = tonumber(minor), patch = tonumber(patch),
        original = version, prerelease = prerelease, build = build,
        is_prerelease = prerelease ~= nil,
    }
end

local function read_installed_version(lua_dir)
    local content = read_file(path_join(lua_dir, "aux_code.lua"))
    local version = content and content:match('AuxFilter%.VERSION%s*=%s*"([^"]+)"')
    if not parse_semver(version) then return nil end
    return version
end

local function compare_prerelease(a, b)
    if not a and not b then return 0 end
    if not a then return 1 end
    if not b then return -1 end
    local a_ids, b_ids = {}, {}
    for id in a:gmatch("[^.]+") do a_ids[#a_ids + 1] = id end
    for id in b:gmatch("[^.]+") do b_ids[#b_ids + 1] = id end
    local count = math.max(#a_ids, #b_ids)
    for index = 1, count do
        local ai, bi = a_ids[index], b_ids[index]
        if not ai then return -1 end
        if not bi then return 1 end
        if ai ~= bi then
            local an, bn = ai:match("^%d+$") and tonumber(ai), bi:match("^%d+$") and tonumber(bi)
            if an and bn then return an > bn and 1 or -1 end
            if an then return -1 end
            if bn then return 1 end
            return ai > bi and 1 or -1
        end
    end
    return 0
end

local function compare_semver(a, b)
    if type(a) == "string" then a = parse_semver(a) end
    if type(b) == "string" then b = parse_semver(b) end
    if not a or not b then return nil end
    if a.major ~= b.major then return a.major > b.major and 1 or -1 end
    if a.minor ~= b.minor then return a.minor > b.minor and 1 or -1 end
    if a.patch ~= b.patch then return a.patch > b.patch and 1 or -1 end
    return compare_prerelease(a.prerelease, b.prerelease)
end

local function should_update(cur_sv, tgt_sv)
    if not cur_sv or not tgt_sv then return false, "版本格式无效" end
    if tgt_sv.is_prerelease and not cur_sv.is_prerelease then return false, "稳定版不跟随预发布版本" end
    local cmp = compare_semver(tgt_sv, cur_sv)
    if not cmp then return false, "版本比较失败" end
    if cmp < 0 then return false, "不允许降级" end
    if cmp == 0 then return false, "已是最新版本" end
    if cur_sv.major == 0 then
        if tgt_sv.major == 0 and tgt_sv.minor == cur_sv.minor then return true end
        return false, "0.x 版本只允许补丁更新"
    end
    if tgt_sv.major ~= cur_sv.major then return false, "不允许跨主版本更新" end
    return true
end

local function read_config(config)
    local mode = DEFAULT_MODE
    local interval_days = DEFAULT_INTERVAL_DAYS
    if config then
        local ok, raw = pcall(config.get_string, config, "aux_code/update_mode")
        if ok and type(raw) == "string" and raw ~= "" then
            raw = raw:lower()
            if raw == MODE.OFF or raw == MODE.NOTIFY or raw == MODE.AUTO then mode = raw end
        end
        ok, raw = pcall(config.get_int, config, "aux_code/check_interval_days")
        if not ok or raw == nil then
            ok, raw = pcall(config.get_string, config, "aux_code/check_interval_days")
        end
        if ok then
            local n = tonumber(raw)
            if n and n > 0 and n == math.floor(n) then interval_days = n end
        end
    end
    return mode, interval_days
end

local function parse_json(str)
    if not str or str == "" then return nil end
    local pos, len = 1, #str
    local read_object, read_array, read_value
    local function skip()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == " " or c == "\n" or c == "\r" or c == "\t" then pos = pos + 1 else break end
        end
    end
    local function expect(ch)
        skip()
        if pos > len or str:sub(pos, pos) ~= ch then return nil end
        pos = pos + 1; return true
    end
    local function read_string()
        if not expect('"') then return nil end
        local parts = {}
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == '"' then pos = pos + 1; return table.concat(parts)
            elseif c == "\\" then
                pos = pos + 1; local esc = str:sub(pos, pos); pos = pos + 1
                if esc == '"' then parts[#parts + 1] = '"'
                elseif esc == "\\" then parts[#parts + 1] = "\\"
                elseif esc == "/" then parts[#parts + 1] = "/"
                elseif esc == "n" then parts[#parts + 1] = "\n"
                elseif esc == "r" then parts[#parts + 1] = "\r"
                elseif esc == "t" then parts[#parts + 1] = "\t"
                else return nil end
            else parts[#parts + 1] = c; pos = pos + 1 end
        end
        return nil
    end
    local function read_number()
        local start = pos
        if pos <= len and str:sub(pos, pos) == "-" then pos = pos + 1 end
        while pos <= len and str:sub(pos, pos) >= "0" and str:sub(pos, pos) <= "9" do pos = pos + 1 end
        if pos <= len and str:sub(pos, pos) == "." then
            pos = pos + 1
            while pos <= len and str:sub(pos, pos) >= "0" and str:sub(pos, pos) <= "9" do pos = pos + 1 end
        end
        return tonumber(str:sub(start, pos - 1))
    end
    read_object = function()
        pos = pos + 1; local result, count = {}, 0
        while true do
            skip()
            if pos > len then return nil end
            if str:sub(pos, pos) == "}" then pos = pos + 1; return result end
            if count > 0 then if not expect(",") then return nil end; skip() end
            local key = read_string()
            if not key then return nil end
            skip(); if not expect(":") then return nil end
            result[key] = read_value(); count = count + 1
        end
    end
    read_array = function()
        pos = pos + 1; local result, idx = {}, 1
        while true do
            skip()
            if pos > len then return nil end
            if str:sub(pos, pos) == "]" then pos = pos + 1; return result end
            if idx > 1 then if not expect(",") then return nil end; skip() end
            result[idx] = read_value(); idx = idx + 1
        end
    end
    read_value = function()
        skip()
        if pos > len then return nil end
        local c = str:sub(pos, pos)
        if c == '"' then return read_string()
        elseif c == "{" then return read_object()
        elseif c == "[" then return read_array()
        elseif c == "t" then
            if str:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end; return nil
        elseif c == "f" then
            if str:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end; return nil
        elseif c == "n" then
            if str:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end; return nil
        elseif c == "-" or (c >= "0" and c <= "9") then return read_number() end
        return nil
    end
    local ok, result = pcall(read_value)
    if not ok then return nil end
    return result
end

local function save_json(value)
    if value == nil then return "{}" end
    local function enc(v)
        local t = type(v)
        if t == "table" then
            local is_arr = true; local maxk = 0
            for k in pairs(v) do
                if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then is_arr = false; break end
                if k > maxk then maxk = k end
            end
            if is_arr and maxk > 0 then
                local items = {}
                for i = 1, maxk do items[i] = enc(v[i]) end
                return "[" .. table.concat(items, ",") .. "]"
            end
            local pairs_l = {}
            for k, val in pairs(v) do pairs_l[#pairs_l + 1] = string.format("%q:%s", tostring(k), enc(val)) end
            return "{" .. table.concat(pairs_l, ",") .. "}"
        elseif t == "string" then return string.format("%q", v)
        elseif t == "number" then return tostring(v)
        elseif t == "boolean" then return v and "true" or "false"
        else return "null" end
    end
    return enc(value)
end

local function load_state(state_dir)
    if not state_dir then return {} end
    local state_path = path_join(state_dir, "state.json")
    local tmp_path = state_path .. ".tmp"
    local tmp_content = read_file(tmp_path)
    if tmp_content and parse_json(tmp_content) then
        atomic_rename(tmp_path, state_path)
        return parse_json(tmp_content) or {}
    end
    local content = read_file(state_path)
    if not content then return {} end
    return parse_json(content) or {}
end

local function save_state(state_dir, state)
    if not state_dir then return false end
    if not mkdir_p(state_dir) then return false end
    local sp = path_join(state_dir, "state.json")
    local tmp = sp .. ".tmp"
    if not write_file(tmp, save_json(state)) then return false end
    return atomic_rename(tmp, sp)
end

local function restore_pending_notice(h)
    local pending = h.state.pending_notice
    if type(pending) ~= "table" then
        local version = h.state.last_notify_version
        local should = version and should_update(parse_semver(h.current_version), parse_semver(version))
        if should then
            pending = {
                kind = "update_available",
                message = "有新版本 " .. version .. " (当前 " .. h.current_version .. ")，可手动更新",
                source_version = h.current_version,
                version = version,
            }
            h.state.pending_notice = pending
            h.state.last_notify_version = nil
            h.state.last_notify_at = nil
            save_state(h.state_dir, h.state)
        elseif version then
            h.state.last_notify_version = nil
            h.state.last_notify_at = nil
            save_state(h.state_dir, h.state)
        end
    end

    if type(pending) ~= "table" or type(pending.message) ~= "string" or pending.message == "" then
        return false
    end

    local stale = false
    if pending.kind == "update_available" then
        stale = not should_update(parse_semver(h.current_version), parse_semver(pending.version))
    elseif pending.kind == "updated" then
        local cmp = compare_semver(pending.version, h.current_version)
        stale = not cmp or cmp <= 0
    elseif pending.source_version and pending.source_version ~= h.current_version then
        stale = true
    end

    if stale then
        h.state.pending_notice = nil
        h.state.last_notify_version = nil
        h.state.last_notify_at = nil
        save_state(h.state_dir, h.state)
        return false
    end

    h.notice = pending.message
    h.notice_consumed = false
    h.remote_version = pending.version
    h.phase = pending.kind == "updated" and PHASE.DONE or PHASE.NOTIFIED
    return true
end

local function persist_pending_notice(h, message)
    local pending = {
        kind = "generic",
        message = message,
        source_version = h.current_version,
    }
    if h.phase == PHASE.DONE and h.remote_version then
        pending.kind = "updated"
        pending.version = h.remote_version
    elseif h.mode == MODE.NOTIFY and h.phase == PHASE.NOTIFIED and h.remote_version
        and ((type(h.state.pending_notice) == "table"
                and h.state.pending_notice.kind == "update_available"
                and h.state.pending_notice.version == h.remote_version)
            or h.state.last_notify_version == h.remote_version) then
        pending.kind = "update_available"
        pending.version = h.remote_version
    end
    h.state.pending_notice = pending
    save_state(h.state_dir, h.state)
end

local function parse_dist_tags(json_str, tag)
    local parsed = parse_json(json_str)
    if not parsed then return nil end
    tag = tag or "latest"
    if parsed[tag] and type(parsed[tag]) == "string" then return parsed[tag] end
    if parsed["dist-tags"] and type(parsed["dist-tags"]) == "table" then
        if parsed["dist-tags"][tag] and type(parsed["dist-tags"][tag]) == "string" then
            return parsed["dist-tags"][tag]
        end
    end
    return nil
end

local function validate_package_metadata(parsed, expected_version)
    if not parsed or type(parsed) ~= "table" then return nil end
    local version = parsed.version
    if type(version) ~= "string" or version == "" then return nil end
    if expected_version and version ~= expected_version then return nil end
    if type(parsed.rimePlugin) ~= "table"
        or parsed.rimePlugin.schema ~= 1
        or parsed.rimePlugin.updaterApi ~= 1
        or type(parsed.rimePlugin.files) ~= "table" then
        return nil
    end
    local integrity = nil
    local tarball = nil
    if type(parsed.dist) == "table" then
        if type(parsed.dist.integrity) == "string"
            and #parsed.dist.integrity == 95
            and parsed.dist.integrity:match("^sha512%-%S+$") then
            integrity = parsed.dist.integrity
        end
        if type(parsed.dist.tarball) == "string" then
            if not is_safe_url(parsed.dist.tarball) then return nil end
            tarball = parsed.dist.tarball
        end
    end
    local files = {}
    for _, fname in ipairs(UPDATE_FILES) do
        local rpath = REL_PATH_PREFIX .. fname
        local sha = parsed.rimePlugin.files[rpath]
        if type(sha) ~= "string" or #sha ~= 95 or not sha:match("^sha512%-%S+$") then return nil end
        files[fname] = sha
    end
    local count = 0
    for _ in pairs(parsed.rimePlugin.files) do count = count + 1 end
    if count ~= #UPDATE_FILES then return nil end
    return { version = version, integrity = integrity, tarball = tarball, files = files }
end

local function extract_sha512_hex(out)
    if not out then return nil end
    for line in out:gmatch("[^\r\n]+") do
        local compact = line:gsub("%s+", "")
        if #compact == 128 and compact:match("^%x+$") then return compact:lower() end
    end
    return nil
end

local function verify_sri(file_hex, sri)
    if not sri or not sri:match("^sha512%-") then return false end
    if not file_hex then return false end
    local expected_b64 = sri:sub(8)
    local computed_b64 = base64_encode(hex_to_binary(file_hex))
    return computed_b64 == expected_b64
end

local function check_dir_perms(dir, basename)
    local tf = path_join(dir, basename)
    if not write_file(tf, "test") then return false end
    if read_file(tf) ~= "test" then os.remove(tf); return false end
    local tf2 = tf .. ".rn"
    if not atomic_rename(tf, tf2) then os.remove(tf); return false end
    return os.remove(tf2) == true
end

local function check_lua_dir_perms(lua_dir)
    return check_dir_perms(lua_dir, ".updater_perm_test")
end

local function restore_backup(h)
    local backup_dir = path_join(h.state_dir, BACKUP_DIRNAME)
    local prepared = {}
    for _, fname in ipairs(UPDATE_FILES) do
        local content = read_file(path_join(backup_dir, fname))
        local restore_path = path_join(h.lua_dir, fname) .. ".restore"
        if not content or not write_file(restore_path, content) then
            for _, path in ipairs(prepared) do os.remove(path) end
            return false
        end
        prepared[#prepared + 1] = restore_path
    end
    for index, fname in ipairs(UPDATE_FILES) do
        if not atomic_rename(prepared[index], path_join(h.lua_dir, fname)) then return false end
    end
    return true
end

local function advance_phase(h)
    if h.mode == MODE.OFF then h.phase = PHASE.OFF; return end

    -- INIT: load state, recover transaction
    if h.phase == PHASE.INIT then
        if h.mode ~= MODE.OFF then
            if not mkdir_p(h.state_dir) then
                h.error_msg = "无法创建更新状态目录，更新已停用"
                h.phase = PHASE.OFF; return
            end
            if not check_dir_perms(h.state_dir, ".updater_perm_test") then
                if h.mode == MODE.AUTO then
                    h.notice = "更新状态目录不可写，自动更新已停用"
                    h.notice_consumed = false
                end
                h.phase = PHASE.OFF; return
            end
            h.state = load_state(h.state_dir)
        end
        -- Recover interrupted transaction
        if h.state.transaction and type(h.state.transaction) == "table" then
            if not restore_backup(h) then
                h.notice = "检测到未完成更新，但旧版本恢复失败，请手动重新安装"
                h.notice_consumed = false
                h.phase = PHASE.OFF
                return
            end
            h.state.transaction = nil
            save_state(h.state_dir, h.state)
        end
        if restore_pending_notice(h) then return end
        h.phase = PHASE.IDLE
        return
    end

    -- IDLE: check interval
    if h.phase == PHASE.IDLE then
        local now = os.time()
        local attempt = h.state.last_attempt_at or 0
        if now - attempt < h.interval_days * 86400 then return end
        h.phase = PHASE.LAUNCH_CHECK
        return
    end

    -- LAUNCH_CHECK: spawn curl for dist-tags (npmmirror first)
    if h.phase == PHASE.LAUNCH_CHECK then
        h.state.last_attempt_at = os.time()
        save_state(h.state_dir, h.state)
        local url = NPM_MIRROR_BASE .. "/-/package/" .. PACKAGE_NAME .. "/dist-tags"
        local out = path_join(work_dir(h), "dist_tags.out")
        launch_worker(h, "check", make_curl_cmd(url, out))
        h.phase = PHASE.CHECKING
        h.tried_fallback = false
        return
    end

    -- CHECKING: poll dist-tags worker
    if h.phase == PHASE.CHECKING then
        local status = poll_worker(h)
        if status == "busy" then return end
        if status == "error" and not h.tried_fallback then
            h.tried_fallback = true
            local url = NPM_REGISTRY_BASE .. "/-/package/" .. PACKAGE_NAME .. "/dist-tags"
            local of = path_join(work_dir(h), "dist_tags.out")
            launch_worker(h, "check", make_curl_cmd(url, of))
            return
        end
        if status == "error" then
            h.error_msg = "版本检查网络请求失败"
            h.phase = PHASE.ERROR; return
        end
        local latest = parse_dist_tags(read_file(path_join(work_dir(h), "dist_tags.out")) or "", h.dist_tag)
        if not latest and not h.tried_fallback then
            h.tried_fallback = true
            local url = NPM_REGISTRY_BASE .. "/-/package/" .. PACKAGE_NAME .. "/dist-tags"
            launch_worker(h, "check", make_curl_cmd(url, path_join(work_dir(h), "dist_tags.out")))
            return
        end
        if not latest then
            h.error_msg = "版本检查解析响应失败"
            h.phase = PHASE.ERROR; return
        end
        h.state.last_check = os.time()
        h.remote_version = latest
        save_state(h.state_dir, h.state)

        local cur_sv = parse_semver(h.current_version)
        local tgt_sv = parse_semver(latest)
        if not cur_sv or not tgt_sv then
            h.error_msg = "版本格式无效"
            h.phase = PHASE.ERROR; return
        end
        local should, reason = should_update(cur_sv, tgt_sv)
        if not should then
            local cmp = compare_semver(tgt_sv, cur_sv)
            if cmp and cmp > 0 then
                h.notice = "有新版本 " .. latest .. " (当前 " .. h.current_version .. ")，但 " .. reason .. "，请手动更新"
                h.notice_consumed = false
                h.phase = PHASE.NOTIFIED
            else
                h.phase = PHASE.IDLE
                if not h.worker then rm_rf(work_dir(h)) end
            end
            return
        end

        if h.mode == MODE.NOTIFY then
            h.notice = "有新版本 " .. latest .. " (当前 " .. h.current_version .. ")，可手动更新"
            h.notice_consumed = false
            h.state.last_notify_version = latest
            h.state.last_notify_at = os.time()
            save_state(h.state_dir, h.state)
            h.phase = PHASE.NOTIFIED; return
        end

        -- AUTO mode: fetch CURRENT version metadata
        h.phase = PHASE.LAUNCH_CURRENT_META
        return
    end

    if h.phase == PHASE.NOTIFIED or h.phase == PHASE.DONE or h.phase == PHASE.OFF then return end

    -- LAUNCH_CURRENT_META: fetch metadata for current version
    if h.phase == PHASE.LAUNCH_CURRENT_META then
        local url = NPM_MIRROR_BASE .. "/" .. PACKAGE_NAME .. "/" .. h.current_version
        local out = path_join(work_dir(h), "current_meta.out")
        launch_worker(h, "cur_meta", make_curl_cmd(url, out))
        h.current_meta_fallback = false
        h.phase = PHASE.FETCHING_CURRENT
        return
    end

    if h.phase == PHASE.FETCHING_CURRENT then
        local status = poll_worker(h)
        if status == "busy" then return end
        if status == "error" and not h.current_meta_fallback then
            h.current_meta_fallback = true
            local url = NPM_REGISTRY_BASE .. "/" .. PACKAGE_NAME .. "/" .. h.current_version
            local out = path_join(work_dir(h), "current_meta.out")
            launch_worker(h, "cur_meta", make_curl_cmd(url, out))
            return
        end
        if status == "error" then
            h.notice = "获取当前版本元数据失败，自动更新取消"
            h.notice_consumed = false
            h.phase = PHASE.NOTIFIED; return
        end
        local parsed = parse_json(read_file(path_join(work_dir(h), "current_meta.out")) or "")
        h.current_meta = validate_package_metadata(parsed, h.current_version)
        if not h.current_meta and not h.current_meta_fallback then
            h.current_meta_fallback = true
            local url = NPM_REGISTRY_BASE .. "/" .. PACKAGE_NAME .. "/" .. h.current_version
            launch_worker(h, "cur_meta", make_curl_cmd(url, path_join(work_dir(h), "current_meta.out")))
            return
        end
        if not h.current_meta then
            h.error_msg = "当前版本元数据验证失败"
            h.phase = PHASE.ERROR; return
        end
        h.phase = PHASE.LAUNCH_LOCAL_HASH
        return
    end

    -- LAUNCH_LOCAL_HASH: hash both local Lua files
    if h.phase == PHASE.LAUNCH_LOCAL_HASH then
        local body_parts = {}
        for _, fname in ipairs(UPDATE_FILES) do
            local fp = path_join(h.lua_dir, fname)
            local op = path_join(work_dir(h), fname .. ".sha512")
            body_parts[#body_parts + 1] = make_sha512_worker_body(fp, op)
        end
        launch_worker(h, "local_hash", table.concat(body_parts, "\n"))
        h.phase = PHASE.HASHING_LOCAL
        return
    end

    if h.phase == PHASE.HASHING_LOCAL then
        local status, _ = poll_worker(h)
        if status == "busy" then return end
        if status == "error" then
            h.notice = "无法校验本地文件，自动更新取消"
            h.notice_consumed = false
            h.phase = PHASE.NOTIFIED; return
        end
        -- Compare local SHA512 against current_meta.files
        for _, fname in ipairs(UPDATE_FILES) do
            local hash_file = path_join(work_dir(h), fname .. ".sha512")
            local hex = extract_sha512_hex(read_file(hash_file) or "")
            if not hex or not verify_sri(hex, h.current_meta.files[fname]) then
                local installed_version = read_installed_version(h.lua_dir)
                if installed_version and installed_version ~= h.current_version then
                    h.current_version = installed_version
                    local installed_semver = parse_semver(installed_version)
                    h.dist_tag = installed_semver.is_prerelease and "beta" or "latest"
                    h.disk_version_changed = installed_version
                    h.current_meta = nil
                    h.phase = PHASE.LAUNCH_CURRENT_META
                    return
                end
                h.notice = "本地文件 " .. fname .. " 已被修改，自动更新取消"
                h.notice_consumed = false
                h.phase = PHASE.NOTIFIED; return
            end
        end
        if h.disk_version_changed then
            h.remote_version = h.disk_version_changed
            h.disk_version_changed = nil
            h.notice = "已自动更新到 " .. h.remote_version .. "，请完全重启输入法以生效"
            h.notice_consumed = false
            h.phase = PHASE.DONE
            return
        end
        h.phase = PHASE.LAUNCH_TARGET_META
        return
    end

    -- LAUNCH_TARGET_META: fetch metadata for target version
    if h.phase == PHASE.LAUNCH_TARGET_META then
        local url = NPM_MIRROR_BASE .. "/" .. PACKAGE_NAME .. "/" .. h.remote_version
        local out = path_join(work_dir(h), "target_meta.out")
        launch_worker(h, "tgt_meta", make_curl_cmd(url, out))
        h.target_meta_fallback = false
        h.phase = PHASE.FETCHING_TARGET
        return
    end

    if h.phase == PHASE.FETCHING_TARGET then
        local status = poll_worker(h)
        if status == "busy" then return end
        if status == "error" and not h.target_meta_fallback then
            h.target_meta_fallback = true
            local url = NPM_REGISTRY_BASE .. "/" .. PACKAGE_NAME .. "/" .. h.remote_version
            local out = path_join(work_dir(h), "target_meta.out")
            launch_worker(h, "tgt_meta", make_curl_cmd(url, out))
            return
        end
        if status == "error" then
            h.notice = "获取目标版本元数据失败，自动更新取消"
            h.notice_consumed = false
            h.phase = PHASE.NOTIFIED; return
        end
        local parsed = parse_json(read_file(path_join(work_dir(h), "target_meta.out")) or "")
        h.target_meta = validate_package_metadata(parsed, h.remote_version)
        if not h.target_meta and not h.target_meta_fallback then
            h.target_meta_fallback = true
            local url = NPM_REGISTRY_BASE .. "/" .. PACKAGE_NAME .. "/" .. h.remote_version
            launch_worker(h, "tgt_meta", make_curl_cmd(url, path_join(work_dir(h), "target_meta.out")))
            return
        end
        if not h.target_meta then
            h.error_msg = "目标版本元数据验证失败"
            h.phase = PHASE.ERROR; return
        end
        if not h.target_meta.tarball then
            h.error_msg = "目标版本 tarball 下载地址不安全或缺失"
            h.phase = PHASE.ERROR; return
        end
        if not h.target_meta.integrity then
            h.error_msg = "目标版本缺少完整性校验值"
            h.phase = PHASE.ERROR; return
        end
        h.phase = PHASE.LAUNCH_DOWNLOAD
        return
    end

    -- LAUNCH_DOWNLOAD
    if h.phase == PHASE.LAUNCH_DOWNLOAD then
        local out = path_join(work_dir(h), "package.tgz")
        launch_worker(h, "download", make_curl_cmd(h.target_meta.tarball, out))
        h.download_fallback = false
        h.phase = PHASE.DOWNLOADING
        return
    end

    if h.phase == PHASE.DOWNLOADING then
        local status, _ = poll_worker(h)
        if status == "busy" then return end
        if status == "error" and not h.download_fallback
            and h.target_meta.tarball:match("^https://registry%.npmmirror%.com/") then
            h.download_fallback = true
            local fallback_url = NPM_REGISTRY_BASE .. "/" .. PACKAGE_NAME .. "/-/"
                .. PACKAGE_NAME .. "-" .. h.remote_version .. ".tgz"
            launch_worker(h, "download", make_curl_cmd(fallback_url, path_join(work_dir(h), "package.tgz")))
            return
        end
        if status == "error" then
            h.error_msg = "下载失败"
            h.phase = PHASE.ERROR; return
        end
        h.phase = PHASE.LAUNCH_TARBALL_HASH
        return
    end

    -- LAUNCH_TARBALL_HASH: verify tarball integrity via SHA512
    if h.phase == PHASE.LAUNCH_TARBALL_HASH then
        local tgz = path_join(work_dir(h), "package.tgz")
        local op = path_join(work_dir(h), "tarball.sha512")
        launch_worker(h, "tarball_hash", make_sha512_worker_body(tgz, op))
        h.phase = PHASE.HASHING_TARBALL
        return
    end

    if h.phase == PHASE.HASHING_TARBALL then
        local status, _ = poll_worker(h)
        if status == "busy" then return end
        if status == "error" then
            h.error_msg = "tarball 哈希计算失败"
            h.phase = PHASE.ERROR; return
        end
        local hex = extract_sha512_hex(read_file(path_join(work_dir(h), "tarball.sha512")) or "")
        if not hex or not verify_sri(hex, h.target_meta.integrity) then
            h.error_msg = "tarball 完整性校验失败"
            h.phase = PHASE.ERROR; return
        end
        h.phase = PHASE.LAUNCH_EXTRACT
        return
    end

    -- LAUNCH_EXTRACT
    if h.phase == PHASE.LAUNCH_EXTRACT then
        local tgz = path_join(work_dir(h), "package.tgz")
        local ed = path_join(work_dir(h), "extracted")
        mkdir_p(ed)
        launch_worker(h, "extract", make_tar_worker_body(tgz, ed, UPDATE_FILES))
        h.phase = PHASE.EXTRACTING
        return
    end

    if h.phase == PHASE.EXTRACTING then
        local status, _ = poll_worker(h)
        if status == "busy" then return end
        if status == "error" then
            h.error_msg = "解压失败"
            h.phase = PHASE.ERROR; return
        end
        h.phase = PHASE.LAUNCH_EXTRACTED_HASH
        return
    end

    -- LAUNCH_EXTRACTED_HASH: verify extracted files against target_meta.files
    if h.phase == PHASE.LAUNCH_EXTRACTED_HASH then
        local body_parts = {}
        local ed = path_join(work_dir(h), "extracted")
        for _, fname in ipairs(UPDATE_FILES) do
            local fp = path_join(ed, fname)
            if not file_exists(fp) then
                h.error_msg = "解压结果缺少文件: " .. fname
                h.phase = PHASE.ERROR; return
            end
            local op = path_join(work_dir(h), "ext_" .. fname .. ".sha512")
            body_parts[#body_parts + 1] = make_sha512_worker_body(fp, op)
        end
        launch_worker(h, "ext_hash", table.concat(body_parts, "\n"))
        h.phase = PHASE.HASHING_EXTRACTED
        return
    end

    if h.phase == PHASE.HASHING_EXTRACTED then
        local status, _ = poll_worker(h)
        if status == "busy" then return end
        if status == "error" then
            h.error_msg = "解压文件哈希计算失败"
            h.phase = PHASE.ERROR; return
        end
        local new_files = {}
        for _, fname in ipairs(UPDATE_FILES) do
            local hash_file = path_join(work_dir(h), "ext_" .. fname .. ".sha512")
            local hex = extract_sha512_hex(read_file(hash_file) or "")
            if not hex or not verify_sri(hex, h.target_meta.files[fname]) then
                h.error_msg = "解压文件 " .. fname .. " 哈希校验失败"
                h.phase = PHASE.ERROR; return
            end
            local ed = path_join(work_dir(h), "extracted")
            local content = read_file(path_join(ed, fname))
            if not content then
                h.error_msg = "无法读取解压文件: " .. fname
                h.phase = PHASE.ERROR; return
            end
            -- loadfile check
            local loaded, lerr = loadfile(path_join(ed, fname))
            if not loaded then
                h.error_msg = "文件 " .. fname .. " loadfile 失败: " .. tostring(lerr or "unknown")
                h.phase = PHASE.ERROR; return
            end
            new_files[fname] = content
        end
        h.new_files = new_files
        h.phase = PHASE.BACKING_UP
        return
    end

    -- BACKING_UP: backup current files, save transaction
    if h.phase == PHASE.BACKING_UP then
        if not check_lua_dir_perms(h.lua_dir) then
            h.notice = "Lua 目录无写入权限，自动更新取消"
            h.notice_consumed = false
            h.phase = PHASE.NOTIFIED; return
        end
        local backup_dir = path_join(h.state_dir, BACKUP_DIRNAME)
        mkdir_p(backup_dir)
        for _, fname in ipairs(UPDATE_FILES) do
            local src = path_join(h.lua_dir, fname)
            local dst = path_join(backup_dir, fname)
            local content = read_file(src)
            if not content then
                h.error_msg = "无法备份文件: " .. fname
                h.phase = PHASE.ERROR; return
            end
            if not write_file(dst, content) then
                h.error_msg = "备份写入失败: " .. fname
                h.phase = PHASE.ERROR; return
            end
        end
        h.state.transaction = {
            version = h.remote_version,
            time = os.time(),
        }
        if not save_state(h.state_dir, h.state) then
            h.error_msg = "事务状态保存失败"
            h.phase = PHASE.ERROR; return
        end
        h.phase = PHASE.REPLACING
        return
    end

    -- REPLACING: write .new files, then rename
    if h.phase == PHASE.REPLACING then
        local success = true
        local written = {}
        for _, fname in ipairs(UPDATE_FILES) do
            local dest = path_join(h.lua_dir, fname)
            local newp = dest .. ".new"
            if not write_file(newp, h.new_files[fname]) then
                success = false; break
            end
            written[fname] = { newp = newp, dest = dest }
        end
        if not success then
            for _, info in pairs(written) do os.remove(info.newp) end
            restore_backup(h)
            h.error_msg = "更新文件写入失败，已回滚"
            h.phase = PHASE.ERROR; return
        end
        for _, fname in ipairs(UPDATE_FILES) do
            local info = written[fname]
            local ok = atomic_rename(info.newp, info.dest)
            if not ok then
                restore_backup(h)
                h.error_msg = "替换文件 " .. fname .. " 失败，已回滚"
                h.phase = PHASE.ERROR; return
            end
        end
        h.phase = PHASE.COMMITTING
        return
    end

    -- COMMITTING
    if h.phase == PHASE.COMMITTING then
        local transaction = h.state.transaction
        local previous_update_version = h.state.last_update_version
        local previous_update_time = h.state.last_update_time
        h.state.transaction = nil
        h.state.last_update_version = h.remote_version
        h.state.last_update_time = os.time()
        h.state.last_notify_version = nil
        h.state.last_notify_at = nil
        if not save_state(h.state_dir, h.state) then
            h.state.transaction = transaction
            h.state.last_update_version = previous_update_version
            h.state.last_update_time = previous_update_time
            restore_backup(h)
            h.error_msg = "更新状态提交失败，已回滚"
            h.phase = PHASE.ERROR
            return
        end
        h.notice = "已自动更新到 " .. h.remote_version .. "，请完全重启输入法以生效"
        h.notice_consumed = false
        h.phase = PHASE.DONE
        return
    end

    -- ERROR: rollback transaction, cleanup work, set notice
    if h.phase == PHASE.ERROR then
        if h.state and h.state.transaction then
            if restore_backup(h) then
                h.state.transaction = nil
                save_state(h.state_dir, h.state)
            else
                h.notice = "更新失败且自动回滚未完成，请从 backup 目录手动恢复"
                h.notice_consumed = false
                h.phase = PHASE.OFF
                return
            end
        end
        if h.error_msg and h.mode == MODE.AUTO then
            h.notice = "更新出错: " .. h.error_msg
            h.notice_consumed = false
        end
        h.error_msg = nil
        -- Don't clean work if worker is running
        if not h.worker then rm_rf(work_dir(h)) end
        h.phase = PHASE.IDLE
        return
    end

    h.error_msg = "内部状态错误: " .. tostring(h.phase)
    h.phase = PHASE.ERROR
end

function Updater.init(options)
    local ok, handle = pcall(function()
        options = options or {}
        local config = options.config
        local user_data_dir = options.user_data_dir
        if not user_data_dir or user_data_dir == "" then return nil end
        local mode, interval_days = read_config(config)
        local state_dir = nil
        if user_data_dir then
            state_dir = path_join(user_data_dir, "aux_code", STATE_DIRNAME)
        end
        local lua_dir = path_join(user_data_dir, "lua")
        local current_version = options.current_version or "0.0.0"
        local current_semver = parse_semver(current_version)
        local h = {
            mode = mode, interval_days = interval_days,
            current_version = current_version,
            dist_tag = current_semver and current_semver.is_prerelease and "beta" or "latest",
            user_data_dir = user_data_dir, state_dir = state_dir, lua_dir = lua_dir,
            config = config, state = {}, phase = PHASE.INIT,
            notice = nil, notice_consumed = true, error_msg = nil,
            worker = nil, logfn = options.log,
            remote_version = nil, tried_fallback = false,
            current_meta = nil, target_meta = nil, new_files = nil,
        }
        if mode == MODE.OFF then h.phase = PHASE.OFF end
        return h
    end)
    if not ok then return nil end
    return handle
end

function Updater.poll(h)
    if not h then return end
    if h.worker then
        local now = os.time()
        if h.next_worker_poll_at and now < h.next_worker_poll_at then return end
        h.next_worker_poll_at = now + 1
    end
    local ok, err = pcall(advance_phase, h)
    if not ok then
        if h.mode == MODE.AUTO then
            if h.error_msg then
                h.notice = "更新出错: " .. (h.error_msg or tostring(err))
            else
                h.notice = "更新出错: " .. tostring(err)
            end
            h.notice_consumed = false
        end
        h.error_msg = nil
        if h.state and h.state.transaction then
            if restore_backup(h) then
                h.state.transaction = nil
                pcall(save_state, h.state_dir, h.state)
            else
                h.notice = "更新失败且自动回滚未完成，请从 backup 目录手动恢复"
                h.notice_consumed = false
                h.phase = PHASE.OFF
                return
            end
        end
        if not h.worker then rm_rf(work_dir(h)) end
        h.phase = PHASE.IDLE
    end
end

function Updater.take_notice(h)
    if not h then return nil end
    if h.notice and not h.notice_consumed then
        h.notice_consumed = true
        local n = h.notice
        persist_pending_notice(h, n)
        h.notice = nil
        if h.phase == PHASE.NOTIFIED or h.phase == PHASE.DONE then
            h.phase = PHASE.IDLE
            if not h.worker then rm_rf(work_dir(h)) end
        end
        return n
    end
    return nil
end

function Updater.ack_notice(h)
    if not h then return end
    h.notice = nil
    h.notice_consumed = true
    h.state.pending_notice = nil
    h.state.last_notify_version = nil
    h.state.last_notify_at = nil
    if h.phase == PHASE.NOTIFIED or h.phase == PHASE.DONE then
        h.phase = PHASE.IDLE
    end
    save_state(h.state_dir, h.state)
    if not h.worker then rm_rf(work_dir(h)) end
end

function Updater.fini(h)
    if not h then return end
    pcall(function()
        if h.mode ~= MODE.OFF then
            save_state(h.state_dir, h.state)
            if not h.worker then rm_rf(work_dir(h)) end
        end
        h.worker = nil
        h.phase = PHASE.OFF
    end)
end

Updater._test = {
    PHASE = PHASE, MODE = MODE,
    PATH_JOIN = path_join,
    BASE64_ENCODE = base64_encode,
    HEX_TO_BINARY = hex_to_binary,
    PARSE_SEMVER = parse_semver,
    COMPARE_SEMVER = compare_semver,
    SHOULD_UPDATE = should_update,
    READ_CONFIG = read_config,
    IS_SAFE_URL = is_safe_url,
    MAKE_CURL_CMD = make_curl_cmd,
    MAKE_SHA512_WORKER_BODY = make_sha512_worker_body,
    MAKE_TAR_WORKER_BODY = make_tar_worker_body,
    PARSE_DIST_TAGS = parse_dist_tags,
    VALIDATE_PACKAGE_METADATA = validate_package_metadata,
    EXTRACT_SHA512_HEX = extract_sha512_hex,
    VERIFY_SRI = verify_sri,
    LOAD_JSON = function(s) return parse_json(s) end,
    SAVE_JSON = save_json,
    SHELL_ESCAPE_PATH = shell_escape_path,
    IS_WINDOWS = is_windows,
    CHECK_LUA_DIR_PERMS = check_lua_dir_perms,
    UPDATE_FILES = UPDATE_FILES,
}

return Updater
