package.path = "./lua/?.lua;" .. package.path

local Updater = require("aux_code_updater")
local T = Updater._test

local passed, failed = 0, 0
local IS_WINDOWS = package.config:sub(1, 1) == "\\"
local TMP_BASE = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"
local TMP
local TMP_DIRS = {}

local function mkdir(path)
    if IS_WINDOWS then
        os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
    else
        os.execute("mkdir -p '" .. path:gsub("'", "'\\''") .. "' 2>/dev/null")
    end
end

local function cleanup(path)
    if IS_WINDOWS then
        os.execute('rmdir /s /q "' .. path:gsub("/", "\\") .. '" 2>nul')
    else
        os.execute("rm -rf '" .. path:gsub("'", "'\\''") .. "' 2>/dev/null")
    end
end

local function make_tmp()
    local d = TMP_BASE .. "/auxtest_" .. tostring(os.time()) .. "_" .. tostring(math.random(99999))
    mkdir(d)
    TMP = d
    TMP_DIRS[#TMP_DIRS + 1] = d
    return d
end

local function assert_eq(actual, expected, msg)
    if actual == expected then passed = passed + 1; return end
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s\n  expected: %q\n  got:      %q\n", msg or "", tostring(expected), tostring(actual)))
end
local function assert_ok(value, msg)
    if value then passed = passed + 1; return end
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s\n  expected truthy, got: %q\n", msg or "", tostring(value)))
end
local function assert_nil(value, msg)
    if value == nil then passed = passed + 1; return end
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s\n  expected nil, got: %q\n", msg or "", tostring(value)))
end
local function assert_false(value, msg)
    if value == false then passed = passed + 1; return end
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s\n  expected false, got: %q\n", msg or "", tostring(value)))
end

-----------------------
-- path_join
-----------------------
local function test_path_join_basic()
    assert_eq(T.PATH_JOIN("a", "b", "c"), "a/b/c", "path_join basic")
    assert_eq(T.PATH_JOIN("a/", "b/"), "a/b", "path_join trail slash")
end

local function test_path_join_root()
    assert_eq(T.PATH_JOIN("/", "foo", "bar"), "/foo/bar", "path_join unix root")
    assert_eq(T.PATH_JOIN("/home", "sub"), "/home/sub", "path_join abs path")
    assert_eq(T.PATH_JOIN("/home/", "/sub/"), "/home/sub", "path_join mixed slashes")
end

local function test_path_join_empty()
    assert_eq(T.PATH_JOIN("", "a", ""), "a", "path_join empty parts")
    assert_eq(T.PATH_JOIN(), "", "path_join no args")
    assert_eq(T.PATH_JOIN(nil, "a", nil), "a", "path_join nil parts")
end

-----------------------
-- base64 / hex
-----------------------
local function test_base64()
    assert_eq(T.BASE64_ENCODE(""), "", "base64 empty")
    assert_eq(T.BASE64_ENCODE("a"), "YQ==", "base64 a")
    assert_eq(T.BASE64_ENCODE("abc"), "YWJj", "base64 abc")
end

local function test_hex_to_binary()
    assert_eq(T.HEX_TO_BINARY("616263"), "abc", "hex_to_binary")
end

-----------------------
-- SemVer
-----------------------
local function test_parse_semver()
    local v = T.PARSE_SEMVER("1.2.3")
    assert_ok(v, "parse 1.2.3")
    assert_eq(v.major, 1, "major")
    assert_eq(v.minor, 2, "minor")
    assert_eq(v.patch, 3, "patch")
    assert_eq(v.is_prerelease, false, "not prerelease")
end

local function test_parse_semver_v()
    local v = T.PARSE_SEMVER("v2.0.0")
    assert_ok(v, "parse v2.0.0")
    assert_eq(v.major, 2, "v prefix")
end

local function test_parse_semver_prerelease()
    local v = T.PARSE_SEMVER("1.2.3-beta.1")
    assert_ok(v, "parse prerelease")
    assert_eq(v.is_prerelease, true, "is prerelease")
end

local function test_parse_semver_invalid()
    assert_nil(T.PARSE_SEMVER(nil), "nil")
    assert_nil(T.PARSE_SEMVER(""), "empty")
    assert_nil(T.PARSE_SEMVER("abc"), "letters")
    assert_nil(T.PARSE_SEMVER("1.2"), "incomplete")
    assert_nil(T.PARSE_SEMVER("1.2.3invalid"), "invalid suffix")
end

local function test_compare_semver()
    assert_eq(T.COMPARE_SEMVER("1.0.0", "1.0.0"), 0, "cmp equal")
    assert_eq(T.COMPARE_SEMVER("1.0.1", "1.0.0"), 1, "cmp higher")
    assert_eq(T.COMPARE_SEMVER("1.0.0", "2.0.0"), -1, "cmp lower")
    assert_eq(T.COMPARE_SEMVER("1.0.0-beta.2", "1.0.0-beta.1"), 1, "beta sequence")
    assert_eq(T.COMPARE_SEMVER("1.0.0", "1.0.0-beta.2"), 1, "stable follows beta")
    assert_eq(T.COMPARE_SEMVER("1.0.0-beta.2", "1.0.0"), -1, "beta precedes stable")
end

local function test_should_update()
    local cur = T.PARSE_SEMVER("1.5.0")
    local ok, _ = T.SHOULD_UPDATE(cur, T.PARSE_SEMVER("1.6.0"))
    assert_ok(ok, "minor update allowed")
    ok, _ = T.SHOULD_UPDATE(cur, T.PARSE_SEMVER("1.5.1"))
    assert_ok(ok, "patch update allowed")
    ok, reason = T.SHOULD_UPDATE(cur, T.PARSE_SEMVER("2.0.0"))
    assert_false(ok, "major cross blocked")
    assert_ok(reason:find("主版本"), "reason mentions major")
    ok, reason = T.SHOULD_UPDATE(cur, T.PARSE_SEMVER("1.4.0"))
    assert_false(ok, "downgrade blocked")
    assert_ok(reason:find("降级"), "reason mentions downgrade")
end

local function test_should_update_0x()
    local cur = T.PARSE_SEMVER("0.1.0")
    local ok, _ = T.SHOULD_UPDATE(cur, T.PARSE_SEMVER("0.1.1"))
    assert_ok(ok, "0.x patch allowed")
    ok, _ = T.SHOULD_UPDATE(cur, T.PARSE_SEMVER("0.2.0"))
    assert_false(ok, "0.x minor blocked")
end

local function test_should_update_prerelease()
    local cur = T.PARSE_SEMVER("1.5.0")
    local ok, _ = T.SHOULD_UPDATE(cur, T.PARSE_SEMVER("1.6.0-alpha"))
    assert_false(ok, "prerelease blocked")
end

local function test_should_update_beta_channel()
    local current = T.PARSE_SEMVER("1.0.0-beta.1")
    local ok = T.SHOULD_UPDATE(current, T.PARSE_SEMVER("1.0.0-beta.2"))
    assert_ok(ok, "beta increment allowed for beta users")
    ok = T.SHOULD_UPDATE(current, T.PARSE_SEMVER("1.0.0"))
    assert_ok(ok, "stable release allowed for beta users")
end

local function test_should_update_same()
    local ok, reason = T.SHOULD_UPDATE(T.PARSE_SEMVER("1.5.0"), T.PARSE_SEMVER("1.5.0"))
    assert_false(ok, "same blocked")
    assert_ok(reason:find("最新"), "reason mentions up-to-date")
end

-----------------------
-- Config
-----------------------
local function test_read_config_default()
    local mode, days = T.READ_CONFIG(nil)
    assert_eq(mode, "notify", "default mode")
    assert_eq(days, 7, "default interval")
end

local function test_read_config_off()
    local c = { get_string = function(_, k) if k == "aux_code/update_mode" then return "off" end end }
    assert_eq(T.READ_CONFIG(c), "off", "off mode")
end

local function test_read_config_invalid()
    local c = { get_string = function(_, k) if k == "aux_code/update_mode" then return "unknown" end end }
    assert_eq(T.READ_CONFIG(c), "notify", "invalid mode defaults")
end

local function test_read_config_interval_neg()
    local c = { get_string = function(_, k) if k == "aux_code/check_interval_days" then return "-1" end end }
    local _, d = T.READ_CONFIG(c)
    assert_eq(d, 7, "neg interval defaults")
end

local function test_read_config_integer_interval()
    local c = {
        get_string = function() return nil end,
        get_int = function(_, k) if k == "aux_code/check_interval_days" then return 14 end end,
    }
    local _, days = T.READ_CONFIG(c)
    assert_eq(days, 14, "integer interval")
end

-----------------------
-- URL safety
-----------------------
local function test_is_safe_url()
    assert_ok(T.IS_SAFE_URL("https://registry.npmmirror.com/-/package/rime-lua-aux-code/dist-tags"), "npm mirror")
    assert_ok(T.IS_SAFE_URL("https://registry.npmjs.org/-/package/rime-lua-aux-code/dist-tags"), "npmjs")
    assert_false(T.IS_SAFE_URL("http://registry.npmjs.org/pkg"), "http blocked")
    assert_false(T.IS_SAFE_URL("https://evil.com/hack"), "unsafe host")
    assert_false(T.IS_SAFE_URL(""), "empty")
end

-----------------------
-- Curl command generation
-----------------------
local function test_make_curl_cmd()
    local cmd = T.MAKE_CURL_CMD("https://registry.npmmirror.com/-/package/rime-lua-aux-code/dist-tags", "/tmp/out")
    assert_ok(cmd:find("curl ", 1, true), "has curl")
    assert_ok(cmd:find("--max-time", 1, true), "has max-time")
    assert_ok(cmd:find("--connect-timeout", 1, true), "has connect-timeout")
    assert_ok(cmd:find("https://", 1, true), "has https")
end

-----------------------
-- SHA512 worker body
-----------------------
local function test_make_sha512_worker_body()
    local body = T.MAKE_SHA512_WORKER_BODY("/tmp/test.bin", "/tmp/hash.out")
    assert_ok(body:find("sha512sum", 1, true) or body:find("shasum", 1, true) or body:find("certutil", 1, true), "has sha cmd")
end

-----------------------
-- Tar worker body
-----------------------
local function test_make_tar_worker_body()
    local body = T.MAKE_TAR_WORKER_BODY("/tmp/pkg.tgz", "/tmp/extracted", {"aux_code.lua", "aux_code_updater.lua"})
    assert_ok(body:find("tar ", 1, true), "has tar")
    assert_ok(body:find("--strip-components=2", 1, true), "strip components")
    assert_ok(body:find("aux_code.lua", 1, true), "has filename")
end

-----------------------
-- Dist-tags parsing
-----------------------
local function test_parse_dist_tags_flat()
    assert_eq(T.PARSE_DIST_TAGS([[{"latest":"1.2.3","beta":"2.0.0-beta.1"}]]), "1.2.3", "flat latest")
end
local function test_parse_dist_tags_nested()
    assert_eq(T.PARSE_DIST_TAGS([[{"dist-tags":{"latest":"1.2.3","next":"2.0.0"}}]]), "1.2.3", "nested latest")
end
local function test_parse_dist_tags_beta()
    assert_eq(T.PARSE_DIST_TAGS([[{"latest":"1.0.0","beta":"1.1.0-beta.2"}]], "beta"),
        "1.1.0-beta.2", "beta tag")
end
local function test_parse_dist_tags_invalid()
    assert_nil(T.PARSE_DIST_TAGS("not json"), "invalid json")
    assert_nil(T.PARSE_DIST_TAGS("{}"), "empty object")
end

-----------------------
-- Package metadata validation (strict)
-----------------------
local SRIFMT = "sha512-" .. string.rep("A", 86) .. "=="
local function test_validate_package_metadata_full()
    local json = string.format([=[{
        "version":"1.2.3",
        "dist":{"integrity":"%s","tarball":"https://registry.npmmirror.com/rime-lua-aux-code/-/pkg-1.2.3.tgz"},
        "rimePlugin":{"schema":1,"updaterApi":1,"files":{
            "lua/aux_code.lua":"%s",
            "lua/aux_code_updater.lua":"%s"
        }}}
    ]=], SRIFMT, SRIFMT, SRIFMT)
    local m = T.VALIDATE_PACKAGE_METADATA(T.LOAD_JSON(json), "1.2.3")
    assert_ok(m, "valid metadata")
    assert_eq(m.version, "1.2.3", "version")
    assert_ok(m.tarball:find("https://"), "tarball https")
    for _, fn in ipairs(T.UPDATE_FILES) do
        assert_ok(m.files[fn]:find("sha512%-"), "file sri: " .. fn)
    end
end

local function test_validate_package_metadata_reject_extra_files()
    local json = [=[{
        "version":"1.0.0",
        "dist":{"integrity":"sha512-abc","tarball":"https://registry.npmmirror.com/pkg.tgz"},
        "rimePlugin":{"schema":1,"updaterApi":1,"files":{
            "lua/aux_code.lua":"sha512-abc","lua/aux_code_updater.lua":"sha512-abc","lua/extra.lua":"sha512-abc"
        }}}
    ]=]
    assert_nil(T.VALIDATE_PACKAGE_METADATA(T.LOAD_JSON(json), "1.0.0"), "reject extra")
end

local function test_validate_package_metadata_reject_missing_files()
    local json = [=[{
        "version":"1.0.0",
        "dist":{"integrity":"sha512-abc","tarball":"https://registry.npmmirror.com/pkg.tgz"},
        "rimePlugin":{"schema":1,"updaterApi":1,"files":{"lua/aux_code.lua":"sha512-abc"}}
    }]=]
    assert_nil(T.VALIDATE_PACKAGE_METADATA(T.LOAD_JSON(json), "1.0.0"), "reject missing")
end

local function test_validate_package_metadata_reject_version_mismatch()
    local json = [=[{
        "version":"1.0.0",
        "dist":{"integrity":"sha512-abc","tarball":"https://registry.npmmirror.com/pkg.tgz"},
        "rimePlugin":{"schema":1,"updaterApi":1,"files":{
            "lua/aux_code.lua":"sha512-abc","lua/aux_code_updater.lua":"sha512-abc"
        }}}
    ]=]
    assert_nil(T.VALIDATE_PACKAGE_METADATA(T.LOAD_JSON(json), "2.0.0"), "reject version mismatch")
end

local function test_validate_package_metadata_reject_unsafe_tarball()
    local json = string.format([=[{
        "version":"1.0.0",
        "dist":{"integrity":"%s","tarball":"https://evil.com/pkg.tgz"},
        "rimePlugin":{"schema":1,"updaterApi":1,"files":{
            "lua/aux_code.lua":"%s","lua/aux_code_updater.lua":"%s"
        }}}
    ]=], SRIFMT, SRIFMT, SRIFMT)
    local m = T.VALIDATE_PACKAGE_METADATA(T.LOAD_JSON(json), "1.0.0")
    assert_nil(m, "unsafe tarball rejected")
end

local function test_validate_package_metadata_reject_protocol_mismatch()
    local json = string.format([=[{
        "version":"1.0.0",
        "dist":{"integrity":"%s","tarball":"https://registry.npmjs.org/pkg.tgz"},
        "rimePlugin":{"schema":2,"updaterApi":1,"files":{
            "lua/aux_code.lua":"%s","lua/aux_code_updater.lua":"%s"
        }}}
    ]=], SRIFMT, SRIFMT, SRIFMT)
    assert_nil(T.VALIDATE_PACKAGE_METADATA(T.LOAD_JSON(json), "1.0.0"), "protocol mismatch rejected")
end

-----------------------
-- SHA512 hex extraction
-----------------------
local function test_extract_sha512_hex()
    assert_eq(T.EXTRACT_SHA512_HEX(string.rep("a", 128)), string.rep("a", 128), "128 hex")
    assert_nil(T.EXTRACT_SHA512_HEX(string.rep("g", 128)), "invalid hex")
    assert_nil(T.EXTRACT_SHA512_HEX(string.rep("a", 127)), "too short")
    assert_nil(T.EXTRACT_SHA512_HEX(string.rep("a", 129)), "too long")
end

-----------------------
-- SRI verification
-----------------------
local function test_verify_sri()
    local hex = string.rep("ab", 64)
    local sri = "sha512-" .. T.BASE64_ENCODE(T.HEX_TO_BINARY(hex))
    assert_ok(T.VERIFY_SRI(hex, sri), "sri match")
    assert_false(T.VERIFY_SRI(hex .. "00", sri), "sri mismatch")
    assert_false(T.VERIFY_SRI(hex, "sha256-abc"), "wrong algo")
    assert_false(T.VERIFY_SRI(nil, sri), "nil hex")
    assert_false(T.VERIFY_SRI(hex, nil), "nil sri")
end

-----------------------
-- JSON roundtrip
-----------------------
local function test_json_roundtrip()
    local data = { version = "1.0.0", count = 5, flag = true, nested = { a = 1 } }
    local parsed = T.LOAD_JSON(T.SAVE_JSON(data))
    assert_eq(parsed.version, "1.0.0", "json version")
    assert_eq(parsed.count, 5, "json count")
    assert_eq(parsed.flag, true, "json flag")
    assert_eq(parsed.nested.a, 1, "json nested")
end

local function test_json_array()
    local parsed = T.LOAD_JSON(T.SAVE_JSON({ "a", "b", "c" }))
    assert_eq(#parsed, 3, "array len")
    assert_eq(parsed[1], "a", "array[1]")
end

-----------------------
-- Updater lifecycle
-----------------------
local function make_config(mode)
    return { get_string = function(_, k)
        if k == "aux_code/update_mode" then return mode end
        if k == "aux_code/check_interval_days" then return "7" end
    end }
end

local function write_state_fixture(user_data_dir, content)
    local state_dir = user_data_dir .. "/aux_code/.update"
    mkdir(state_dir)
    local file = assert(io.open(state_dir .. "/state.json", "wb"))
    file:write(content)
    file:close()
end

local function test_updater_init_off()
    local h = Updater.init({ config = make_config("off"), user_data_dir = "/tmp/test_off", current_version = "1.0.0" })
    assert_ok(h, "init off")
    assert_eq(h.phase, T.PHASE.OFF, "phase off")
    Updater.fini(h)
end

local function test_updater_beta_tag()
    local h = Updater.init({ config = make_config("off"), user_data_dir = "/tmp/test_beta", current_version = "1.0.0-beta.1" })
    assert_eq(h.dist_tag, "beta", "prerelease tracks beta dist-tag")
    Updater.fini(h)
end

local function test_updater_init_no_dir()
    assert_nil(Updater.init({ config = {}, user_data_dir = nil }), "nil dir")
    assert_nil(Updater.init({ config = {}, user_data_dir = "" }), "empty dir")
end

local function test_updater_take_notice()
    assert_nil(Updater.take_notice(nil), "nil handle")
    Updater.ack_notice(nil)
    passed = passed + 1
end

local function test_restore_legacy_update_notice_state()
    local d = make_tmp()
    write_state_fixture(d,
        [[{"last_attempt_at":123,"last_notify_at":456,"last_notify_version":"1.0.0-beta.2"}]])
    local h = Updater.init({
        config = make_config("notify"),
        user_data_dir = d,
        current_version = "1.0.0-beta.1",
    })

    Updater.poll(h)
    assert_eq(h.phase, T.PHASE.NOTIFIED, "legacy state restores pending update notice")
    local notice = Updater.take_notice(h)
    assert_ok(notice and notice:find("1.0.0%-beta%.2"), "restored notice includes target version")
    assert_ok(type(h.state.pending_notice) == "table", "taken notice is persisted until acknowledgement")

    Updater.ack_notice(h)
    assert_nil(h.state.pending_notice, "ack clears persisted notice")
    assert_nil(h.state.last_notify_version, "ack clears legacy pending version")
    assert_nil(h.state.last_notify_at, "ack clears legacy pending timestamp")
    Updater.fini(h)
end

local function test_restore_generic_notice_state()
    local d = make_tmp()
    local h = Updater.init({
        config = make_config("auto"),
        user_data_dir = d,
        current_version = "1.0.0",
    })
    Updater.poll(h)
    h.notice = "更新出错: test"
    h.notice_consumed = false
    assert_eq(Updater.take_notice(h), "更新出错: test", "generic notice can be taken")
    Updater.fini(h)

    local restored = Updater.init({
        config = make_config("auto"),
        user_data_dir = d,
        current_version = "1.0.0",
    })
    Updater.poll(restored)
    assert_eq(restored.phase, T.PHASE.NOTIFIED, "generic notice is restored after reinitialization")
    assert_eq(Updater.take_notice(restored), "更新出错: test", "restored generic notice keeps its message")
    Updater.ack_notice(restored)
    Updater.fini(restored)
end

local function test_stale_completed_notice_is_discarded()
    local d = make_tmp()
    write_state_fixture(d, [[{"pending_notice":{"kind":"updated","message":"redeploy","source_version":"1.0.0-beta.1","version":"1.0.0-beta.2"}}]])
    local h = Updater.init({
        config = make_config("auto"),
        user_data_dir = d,
        current_version = "1.0.0-beta.2",
    })

    Updater.poll(h)
    assert_eq(h.phase, T.PHASE.IDLE, "completed notice is stale after the new version loads")
    assert_nil(Updater.take_notice(h), "stale completed notice is not shown")
    assert_nil(h.state.pending_notice, "stale completed notice is removed from state")
    Updater.fini(h)
end

local function test_stale_available_notice_is_discarded()
    local d = make_tmp()
    write_state_fixture(d, [[{"pending_notice":{"kind":"update_available","message":"update","source_version":"1.0.0-beta.1","version":"1.0.0-beta.2"}}]])
    local h = Updater.init({
        config = make_config("notify"),
        user_data_dir = d,
        current_version = "1.0.0-beta.2",
    })

    Updater.poll(h)
    assert_eq(h.phase, T.PHASE.IDLE, "available notice is stale after its version loads")
    assert_nil(Updater.take_notice(h), "installed version notice is not shown")
    assert_nil(h.state.pending_notice, "installed version notice is removed from state")
    Updater.fini(h)
end

local function test_cross_version_generic_notice_is_discarded()
    local d = make_tmp()
    write_state_fixture(d, [[{"pending_notice":{"kind":"generic","message":"old error","source_version":"1.0.0-beta.1"}}]])
    local h = Updater.init({
        config = make_config("auto"),
        user_data_dir = d,
        current_version = "1.0.0-beta.2",
    })

    Updater.poll(h)
    assert_eq(h.phase, T.PHASE.IDLE, "generic notice expires after a version change")
    assert_nil(Updater.take_notice(h), "old-version generic notice is not shown")
    assert_nil(h.state.pending_notice, "old-version generic notice is removed from state")
    Updater.fini(h)
end

local function test_updater_fini_safe()
    Updater.fini(nil)
    passed = passed + 1
end

local function test_updater_lifecycle_off()
    local h = Updater.init({ config = make_config("off"), user_data_dir = "/tmp/test_lc_off" })
    Updater.poll(h)
    assert_eq(h.phase, T.PHASE.OFF, "stays off after poll")
    assert_nil(Updater.take_notice(h), "no notice")
    Updater.fini(h)
    assert_eq(h.phase, T.PHASE.OFF, "fini off")
end

local function test_updater_lifecycle_idle_no_workers()
    local d = make_tmp()
    mkdir(d .. "/lua")
    local h = Updater.init({ config = make_config("notify"), user_data_dir = d, current_version = "1.0.0" })
    assert_ok(h, "init notify lifecycle")
    h.state.last_check = os.time()
    h.state.last_attempt_at = os.time()
    h.phase = T.PHASE.IDLE
    Updater.poll(h)
    assert_eq(h.phase, T.PHASE.IDLE, "stays idle with recent check")
    Updater.fini(h)
end

local function test_updater_poll_error_caught()
    local h = Updater.init({ config = make_config("notify"), user_data_dir = make_tmp(), current_version = "1.0.0" })
    h.phase = "nonexistent"
    Updater.poll(h) -- triggers unknown→ERROR
    Updater.poll(h) -- ERROR→IDLE
    assert_eq(h.phase, T.PHASE.IDLE, "stuck phase recovered to idle")
    local n = Updater.take_notice(h)
    assert_nil(n, "notify mode keeps internal errors silent")
    Updater.fini(h)
end

local function test_updater_fini_preserves_worker_dir()
    local d = make_tmp()
    local work_dir = d .. "/aux_code/.update/work"
    mkdir(work_dir)
    local marker = work_dir .. "/sentinel"
    local f = io.open(marker, "wb")
    assert_ok(f, "create sentinel")
    if f then f:write("keep"); f:close() end
    local h = Updater.init({ config = make_config("notify"), user_data_dir = d, current_version = "1.0.0" })
    h.worker = { name = "test", of = marker, ef = marker, script = marker }
    Updater.fini(h)
    local mf = io.open(marker, "rb")
    assert_ok(mf, "work dir preserved when worker running")
    if mf then mf:close() end
end

local function test_last_attempt_rate_limit()
    local d = make_tmp()
    mkdir(d .. "/lua")
    local h = Updater.init({ config = make_config("notify"), user_data_dir = d, current_version = "1.0.0" })
    h.state.last_attempt_at = os.time()
    h.state.last_check = 0
    h.phase = T.PHASE.IDLE
    Updater.poll(h)
    assert_eq(h.phase, T.PHASE.IDLE, "rate limited at idle")
    Updater.fini(h)
end

local function test_same_version_returns_to_idle()
    local d = make_tmp()
    local work = d .. "/aux_code/.update/work"
    mkdir(work)
    local h = Updater.init({ config = make_config("notify"), user_data_dir = d, current_version = "1.0.0" })
    h.state = {}
    h.phase = T.PHASE.CHECKING
    h.worker = nil
    local f = assert(io.open(work .. "/dist_tags.out", "wb"))
    f:write([[{"latest":"1.0.0"}]])
    f:close()
    Updater.poll(h)
    assert_eq(h.phase, T.PHASE.IDLE, "same version returns to idle")
    assert_nil(Updater.take_notice(h), "same version has no notice")
    Updater.fini(h)
end

local function test_stale_runtime_version_rechecks_installed_version()
    local d = make_tmp()
    local work = d .. "/aux_code/.update/work"
    local lua_dir = d .. "/lua"
    mkdir(work)
    mkdir(lua_dir)

    local aux = assert(io.open(lua_dir .. "/aux_code.lua", "wb"))
    aux:write('local AuxFilter = {}\nAuxFilter.VERSION = "1.0.0"\n')
    aux:close()
    local updater = assert(io.open(lua_dir .. "/aux_code_updater.lua", "wb"))
    updater:write("return {}\n")
    updater:close()

    local h = Updater.init({ config = make_config("auto"), user_data_dir = d, current_version = "1.0.0-beta.4" })
    h.state = {}
    h.phase = T.PHASE.HASHING_LOCAL
    h.current_meta = {
        files = {
            ["aux_code.lua"] = "sha512-old",
            ["aux_code_updater.lua"] = "sha512-old",
        },
    }
    for _, name in ipairs(T.UPDATE_FILES) do
        local hash = assert(io.open(work .. "/" .. name .. ".sha512", "wb"))
        hash:write(string.rep("a", 128), "  ", name, "\n")
        hash:close()
    end

    Updater.poll(h)

    assert_eq(h.current_version, "1.0.0", "disk version replaces stale runtime version")
    assert_eq(h.dist_tag, "latest", "refreshed stable version tracks latest")
    assert_eq(h.phase, T.PHASE.LAUNCH_CURRENT_META, "installed version metadata is rechecked")
    assert_nil(h.notice, "stale runtime version is not reported as a local modification")

    local verified_hex = string.rep("b", 128)
    local verified_sri = "sha512-" .. T.BASE64_ENCODE(T.HEX_TO_BINARY(verified_hex))
    h.current_meta = { files = {} }
    for _, name in ipairs(T.UPDATE_FILES) do
        h.current_meta.files[name] = verified_sri
        local hash = assert(io.open(work .. "/" .. name .. ".sha512", "wb"))
        hash:write(verified_hex, "\n")
        hash:close()
    end
    h.phase = T.PHASE.HASHING_LOCAL
    Updater.poll(h)

    assert_eq(h.phase, T.PHASE.DONE, "verified disk update waits for input method restart")
    assert_ok(h.notice and h.notice:find("完全重启输入法", 1, true), "restart notice explains required action")
    Updater.fini(h)
end

local function test_transaction_backup_restore()
    local d = make_tmp()
    local backup_dir = d .. "/aux_code/.update/backup"
    local lua_dir = d .. "/lua"
    mkdir(backup_dir)
    mkdir(lua_dir)

    local orig = lua_dir .. "/aux_code.lua"
    local f = io.open(orig, "wb")
    assert_ok(f, "create original")
    if f then f:write("original content"); f:close() end

    -- backup via pure Lua read/write
    local bf = backup_dir .. "/aux_code.lua"
    local rf = io.open(orig, "rb")
    assert_ok(rf, "read original for backup")
    local content = rf:read("*a"); rf:close()
    local wf = io.open(bf, "wb")
    assert_ok(wf, "write backup")
    if wf then wf:write(content); wf:close() end

    -- corrupt original
    local cf = io.open(orig, "wb")
    if cf then cf:write("corrupted"); cf:close() end

    -- restore
    local rbf = io.open(bf, "rb")
    assert_ok(rbf, "read backup for restore")
    local rc = rbf:read("*a"); rbf:close()
    local wrf = io.open(orig, "wb")
    if wrf then wrf:write(rc); wrf:close() end

    local vf = io.open(orig, "rb")
    assert_ok(vf, "verify restored")
    local vc = vf and vf:read("*a") or ""; if vf then vf:close() end
    assert_eq(vc, "original content", "restore from backup")
end

-----------------------
-- Run all
-----------------------
make_tmp()

test_path_join_basic()
test_path_join_root()
test_path_join_empty()
test_base64()
test_hex_to_binary()
test_parse_semver()
test_parse_semver_v()
test_parse_semver_prerelease()
test_parse_semver_invalid()
test_compare_semver()
test_should_update()
test_should_update_0x()
test_should_update_prerelease()
test_should_update_beta_channel()
test_should_update_same()
test_read_config_default()
test_read_config_off()
test_read_config_invalid()
test_read_config_interval_neg()
test_read_config_integer_interval()
test_is_safe_url()
test_make_curl_cmd()
test_make_sha512_worker_body()
test_make_tar_worker_body()
test_parse_dist_tags_flat()
test_parse_dist_tags_nested()
test_parse_dist_tags_beta()
test_parse_dist_tags_invalid()
test_validate_package_metadata_full()
test_validate_package_metadata_reject_extra_files()
test_validate_package_metadata_reject_missing_files()
test_validate_package_metadata_reject_version_mismatch()
test_validate_package_metadata_reject_unsafe_tarball()
test_validate_package_metadata_reject_protocol_mismatch()
test_extract_sha512_hex()
test_verify_sri()
test_json_roundtrip()
test_json_array()
test_updater_init_off()
test_updater_beta_tag()
test_updater_init_no_dir()
test_updater_take_notice()
test_restore_legacy_update_notice_state()
test_restore_generic_notice_state()
test_stale_completed_notice_is_discarded()
test_stale_available_notice_is_discarded()
test_cross_version_generic_notice_is_discarded()
test_updater_fini_safe()
test_updater_lifecycle_off()
test_updater_lifecycle_idle_no_workers()
test_updater_poll_error_caught()
test_updater_fini_preserves_worker_dir()
test_last_attempt_rate_limit()
test_same_version_returns_to_idle()
test_stale_runtime_version_rechecks_installed_version()
test_transaction_backup_restore()

for _, path in ipairs(TMP_DIRS) do cleanup(path) end

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
if failed > 0 then os.exit(1) end
