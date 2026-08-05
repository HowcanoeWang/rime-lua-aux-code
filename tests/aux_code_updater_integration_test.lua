package.path = "./lua/?.lua;" .. package.path

if not _G.ShadowCandidate then
    _G.ShadowCandidate = function(original, cand_type, text, comment)
        local c = {
            type = cand_type,
            start = original.start,
            _end = original._end,
            text = text,
            comment = comment,
            quality = original.quality,
            preedit = original.preedit,
            get_dynamic_type = function() return "Shadow" end,
            get_genuine = function() return original end,
        }
        return c
    end
end

if not _G.Candidate then
    _G.Candidate = function(cand_type, start, _end, text, comment)
        return {
            type = cand_type,
            start = start,
            _end = _end,
            text = text,
            comment = comment,
        }
    end
end

local AuxFilter = require("aux_code")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assert_not_nil(value, message)
    if value == nil then
        error(string.format("%s: expected non-nil", message), 2)
    end
end

local function assert_not_equal(actual, unexpected, message)
    if actual == unexpected then
        error(string.format("%s: should not equal %s", message, tostring(unexpected)), 2)
    end
end

local function assert_truthy(value, message)
    if not value then
        error(string.format("%s: expected truthy, got %s", message, tostring(value)), 2)
    end
end

local function make_candidate(opts)
    return {
        type = opts.type or "phrase",
        start = opts.start or 0,
        _end = opts._end or 2,
        text = opts.text or "test",
        comment = opts.comment,
        quality = opts.quality,
        preedit = opts.preedit,
        get_dynamic_type = function()
            return opts.shadow_type or "Candidate"
        end,
        get_genuine = function()
            return opts.genuine
        end,
    }
end

local function make_input(candidates)
    return {
        iter = function()
            local index = 0
            return function()
                index = index + 1
                return candidates[index]
            end
        end,
    }
end

local function make_base_env(input_code)
    return {
        aux_ready = true,
        show_aux_notice = false,
        triggers = {
            { mode = "learn", token = ";" },
        },
        engine = {
            context = {
                input = input_code,
            },
        },
    }
end

local function make_init_env()
    local callback
    local config = {
        get_string = function(_, key)
            if key == "aux_code/learn_trigger" then
                return ";"
            end
            return nil
        end,
        get_bool = function(_, key)
            if key == "aux_code/show_aux_notice" then
                return false
            end
            return nil
        end,
    }

    return {
        name_space = "*aux_code",
        engine = {
            schema = { config = config },
            context = {
                select_notifier = {
                    connect = function(_, fn)
                        callback = fn
                        return { disconnect = function() end }
                    end,
                },
            },
        },
        get_select_callback = function()
            return callback
        end,
    }
end

local function stub_rime_api()
    local old = _G.rime_api
    _G.rime_api = {
        get_shared_data_dir = function()
            return "/tmp"
        end,
        get_user_data_dir = function()
            return "/tmp"
        end,
    }
    return old
end

local function restore_rime_api(old)
    _G.rime_api = old
end

local function collect_yields(input_code, aux_index, candidates, env_override)
    local output = {}
    local old_yield = _G.yield
    _G.yield = function(cand)
        table.insert(output, cand)
    end

    AuxFilter.aux_code = {}
    AuxFilter.aux_index = aux_index or {}
    local env = make_base_env(input_code)
    if env_override then
        for k, v in pairs(env_override) do
            env[k] = v
        end
    end
    AuxFilter.func(make_input(candidates or {}), env)

    _G.yield = old_yield
    return output
end

local function clear_updater_preload()
    package.preload["aux_code_updater"] = nil
    package.loaded["aux_code_updater"] = nil
end

local function disable_updater()
    package.preload["aux_code_updater"] = function()
        return false
    end
    package.loaded["aux_code_updater"] = nil
end

local function mock_updater(mock)
    package.preload["aux_code_updater"] = function()
        return mock
    end
    package.loaded["aux_code_updater"] = nil
end

--------------------------------------------------
-- Test 1: updater module absent — init succeeds --
--------------------------------------------------
local function test_updater_absent_init_succeeds()
    disable_updater()
    local old_api = stub_rime_api()
    local old_read_aux_txt = AuxFilter.readAuxTxt
    AuxFilter.readAuxTxt = function()
        return {}
    end

    local env = make_init_env()
    AuxFilter.init(env)

    AuxFilter.readAuxTxt = old_read_aux_txt
    restore_rime_api(old_api)

    assert_equal(env.updater, nil, "updater should be nil when module absent")
    assert_equal(env.learn_trigger, ";", "init should still configure triggers")
end

--------------------------------------------------
-- Test 2: updater.init throws — filter init OK --
--------------------------------------------------
local function test_updater_init_throws_is_caught()
    mock_updater({
        init = function(_)
            error("simulated init failure")
        end,
        poll = function() end,
        take_notice = function() return nil end,
        fini = function() end,
    })
    local old_api = stub_rime_api()
    local old_read_aux_txt = AuxFilter.readAuxTxt
    AuxFilter.readAuxTxt = function()
        return {}
    end

    local env = make_init_env()
    AuxFilter.init(env)

    AuxFilter.readAuxTxt = old_read_aux_txt
    restore_rime_api(old_api)

    assert_equal(env.updater, nil, "updater should be nil when init throws")
    assert_equal(env.learn_trigger, ";", "filter init should still complete")
    clear_updater_preload()
end

--------------------------------------------------
-- Test 3: updater.poll throws — func works fine --
--------------------------------------------------
local function test_updater_poll_throws_is_caught()
    mock_updater({
        init = function(_)
            return {}
        end,
        poll = function(_)
            error("simulated poll failure")
        end,
        take_notice = function()
            return nil
        end,
        fini = function() end,
    })
    local old_api = stub_rime_api()
    local old_read_aux_txt = AuxFilter.readAuxTxt
    AuxFilter.readAuxTxt = function()
        return {}
    end

    local env = make_init_env()
    AuxFilter.init(env)

    AuxFilter.readAuxTxt = old_read_aux_txt
    restore_rime_api(old_api)

    assert_not_nil(env.updater, "updater should be set when init succeeds")
    env.engine.context.input = "ni"

    local output = {}
    local old_yield = _G.yield
    _G.yield = function(cand)
        table.insert(output, cand)
    end
    AuxFilter.aux_code = {}
    AuxFilter.aux_index = {}
    AuxFilter.func(
        make_input({
            make_candidate({ text = "你" }),
            make_candidate({ text = "泥" }),
        }),
        env
    )
    _G.yield = old_yield

    assert_equal(#output, 2, "should yield all candidates despite poll failure")
    assert_equal(output[1].text, "你", "first candidate should survive")
    clear_updater_preload()
end

--------------------------------------------------
-- Test 4: notice on first regular candidate --
--------------------------------------------------
local function test_notice_on_first_regular_candidate()
    mock_updater({
        init = function(_)
            return {}
        end,
        poll = function() end,
        take_notice = function()
            return "Update available"
        end,
        fini = function() end,
    })
    local old_api = stub_rime_api()
    local old_read_aux_txt = AuxFilter.readAuxTxt
    AuxFilter.readAuxTxt = function()
        return {}
    end

    local env = make_init_env()
    AuxFilter.init(env)

    AuxFilter.readAuxTxt = old_read_aux_txt
    restore_rime_api(old_api)

    assert_not_nil(env.updater, "updater should be available")
    env.engine.context.input = "ni"

    local output = {}
    local old_yield = _G.yield
    _G.yield = function(cand)
        table.insert(output, cand)
    end
    AuxFilter.aux_code = {}
    AuxFilter.aux_index = {}
    AuxFilter.func(
        make_input({
            make_candidate({ text = "你" }),
            make_candidate({ text = "泥" }),
        }),
        env
    )
    _G.yield = old_yield

    assert_equal(#output, 2, "should yield all candidates")
    assert_truthy(output[1].comment, "first candidate should have comment")
    assert_truthy(string.find(output[1].comment, "Update available", 1, true), "notice should be in first candidate comment")
    assert_equal(output[2].comment, nil, "second candidate should NOT have notice")
    clear_updater_preload()
end

--------------------------------------------------
-- Test 5: notice applied only once (not on 2nd) --
--------------------------------------------------
local function test_notice_applied_only_once()
    mock_updater({
        init = function(_)
            return {}
        end,
        poll = function() end,
        take_notice = function()
            return "Update available"
        end,
        fini = function() end,
    })
    local old_api = stub_rime_api()
    local old_read_aux_txt = AuxFilter.readAuxTxt
    AuxFilter.readAuxTxt = function()
        return {}
    end

    local env = make_init_env()
    AuxFilter.init(env)

    AuxFilter.readAuxTxt = old_read_aux_txt
    restore_rime_api(old_api)

    env.engine.context.input = "ni"

    local output = {}
    local old_yield = _G.yield
    _G.yield = function(cand)
        table.insert(output, cand)
    end
    AuxFilter.aux_code = {}
    AuxFilter.aux_index = {}
    AuxFilter.func(
        make_input({
            make_candidate({ text = "你" }),
            make_candidate({ text = "我" }),
            make_candidate({ text = "他" }),
        }),
        env
    )
    _G.yield = old_yield

    for i = 2, #output do
        local c = output[i].comment
        local has_notice = c and string.find(c, "Update available", 1, true)
        assert_equal(has_notice, nil, "candidate " .. i .. " should NOT have notice")
    end
    clear_updater_preload()
end

local function test_notice_remains_until_candidate_selection()
    local take_count = 0
    local ack_count = 0
    mock_updater({
        init = function(_)
            return {}
        end,
        poll = function() end,
        take_notice = function()
            take_count = take_count + 1
            if take_count == 1 then return "Update available" end
            return nil
        end,
        ack_notice = function()
            ack_count = ack_count + 1
        end,
        fini = function() end,
    })
    local old_api = stub_rime_api()
    local old_read_aux_txt = AuxFilter.readAuxTxt
    AuxFilter.readAuxTxt = function()
        return {}
    end

    local env = make_init_env()
    AuxFilter.init(env)
    AuxFilter.readAuxTxt = old_read_aux_txt
    restore_rime_api(old_api)
    env.engine.context.input = "ni"

    local function run_filter()
        local output = {}
        local old_yield = _G.yield
        _G.yield = function(cand) output[#output + 1] = cand end
        AuxFilter.func(make_input({ make_candidate({ text = "你" }) }), env)
        _G.yield = old_yield
        return output[1]
    end

    local first = run_filter()
    local second = run_filter()
    assert_truthy(string.find(first.comment, "Update available", 1, true),
        "update notice should be shown")
    assert_truthy(string.find(second.comment, "Update available", 1, true),
        "update notice should remain visible while composing")
    assert_equal(take_count, 1, "cached update notice should only be taken once")

    env.get_select_callback()(env.engine.context)
    local after_selection = run_filter()
    assert_equal(after_selection.comment, nil, "update notice should stop after candidate selection")
    assert_equal(ack_count, 1, "candidate selection should acknowledge the update notice")
    AuxFilter.fini(env)
    clear_updater_preload()
end

--------------------------------------------------
-- Test 6: ShadowCandidate comment not corrupted --
--------------------------------------------------
local function test_shadow_candidate_comment_not_corrupted()
    mock_updater({
        init = function(_)
            return {}
        end,
        poll = function() end,
        take_notice = function()
            return "v2.0"
        end,
        fini = function() end,
    })
    local old_api = stub_rime_api()
    local old_read_aux_txt = AuxFilter.readAuxTxt
    AuxFilter.readAuxTxt = function()
        return {}
    end

    local env = make_init_env()
    AuxFilter.init(env)

    AuxFilter.readAuxTxt = old_read_aux_txt
    restore_rime_api(old_api)

    local genuine = make_candidate({ text = "你", comment = "orig" })

    env.engine.context.input = "ni"

    local output = {}
    local old_yield = _G.yield
    _G.yield = function(cand)
        table.insert(output, cand)
    end
    AuxFilter.aux_code = {}
    AuxFilter.aux_index = {}
    AuxFilter.func(
        make_input({
            make_candidate({
                text = "尔",
                comment = "shadow",
                shadow_type = "Shadow",
                genuine = genuine,
            }),
            make_candidate({ text = "泥" }),
        }),
        env
    )
    _G.yield = old_yield

    -- The first candidate is Shadow; notice should be merged into its comment
    assert_truthy(output[1].comment, "Shadow candidate should have comment")
    assert_truthy(string.find(output[1].comment, "v2.0", 1, true), "notice should appear in Shadow comment")
    -- Verify Shadow still points to original with original comment
    assert_not_nil(output[1].get_genuine, "should still be Shadow-like object")
    clear_updater_preload()
end

--------------------------------------------------
-- Test 7: AuxFilter.VERSION is set --
--------------------------------------------------
local function test_version_is_set()
    assert_equal(AuxFilter.VERSION, "1.0.0", "VERSION should be stable 1.0.0")
end

--------------------------------------------------
-- Test 8: notice does not disrupt aux_ready path --
--------------------------------------------------
local function test_notice_with_aux_error_path()
    mock_updater({
        init = function(_)
            return {}
        end,
        poll = function() end,
        take_notice = function()
            return "New version"
        end,
        fini = function() end,
    })
    local old_api = stub_rime_api()
    local old_read_aux_txt = AuxFilter.readAuxTxt

    -- Simulate dict load failure
    AuxFilter.readAuxTxt = function()
        return nil, "/tmp/missing", "missing.txt"
    end

    local env = make_init_env()
    AuxFilter.init(env)

    AuxFilter.readAuxTxt = old_read_aux_txt
    restore_rime_api(old_api)

    assert_equal(env.aux_ready, false, "should not be ready")
    assert_not_nil(env.updater, "updater should still be available")

    env.engine.context.input = "ni;"

    local output = {}
    local old_yield = _G.yield
    _G.yield = function(cand)
        table.insert(output, cand)
    end
    AuxFilter.func(
        make_input({
            make_candidate({ text = "你" }),
            make_candidate({ text = "泥" }),
        }),
        env
    )
    _G.yield = old_yield

    -- First candidate should have both error hint and version notice
    assert_truthy(output[1].comment, "should have comment")
    assert_truthy(string.find(output[1].comment, "New version", 1, true), "should have version notice")
    assert_truthy(string.find(output[1].comment, "未找到辅码文件", 1, true), "should have error hint")
    -- Second candidate should have neither
    assert_equal(output[2].comment, nil, "second candidate should be clean")
    clear_updater_preload()
end

--------------------------------------------------
-- Test 9: fini cleans up updater --
--------------------------------------------------
local function test_fini_cleans_up_updater()
    local fini_called = false
    local mock = {
        init = function(_)
            return {}
        end,
        poll = function() end,
        take_notice = function() return nil end,
        fini = function(_)
            fini_called = true
        end,
    }
    mock_updater(mock)
    local old_api = stub_rime_api()
    local old_read_aux_txt = AuxFilter.readAuxTxt
    AuxFilter.readAuxTxt = function()
        return {}
    end

    local env = make_init_env()
    AuxFilter.init(env)

    AuxFilter.readAuxTxt = old_read_aux_txt
    restore_rime_api(old_api)

    AuxFilter.fini(env)
    assert_truthy(fini_called, "updater fini should have been called")
    clear_updater_preload()
end

--------------------------------------------------
-- Test 10: fini without updater is safe --
--------------------------------------------------
local function test_fini_without_updater_is_safe()
    disable_updater()
    local old_api = stub_rime_api()
    local old_read_aux_txt = AuxFilter.readAuxTxt
    AuxFilter.readAuxTxt = function()
        return {}
    end

    local env = make_init_env()
    AuxFilter.init(env)

    AuxFilter.readAuxTxt = old_read_aux_txt
    restore_rime_api(old_api)

    AuxFilter.fini(env)
    assert_truthy(true, "fini without updater should not throw")
    clear_updater_preload()
end

--------------------------------------------------
-- Test 11: no_notice_means_notice_is_nil — no change to candidates --
--------------------------------------------------
local function test_no_notice_means_no_change()
    mock_updater({
        init = function(_)
            return {}
        end,
        poll = function() end,
        take_notice = function()
            return nil
        end,
        fini = function() end,
    })
    local old_api = stub_rime_api()
    local old_read_aux_txt = AuxFilter.readAuxTxt
    AuxFilter.readAuxTxt = function()
        return {}
    end

    local env = make_init_env()
    AuxFilter.init(env)

    AuxFilter.readAuxTxt = old_read_aux_txt
    restore_rime_api(old_api)

    env.engine.context.input = "ni"

    local output = {}
    local old_yield = _G.yield
    _G.yield = function(cand)
        table.insert(output, cand)
    end
    AuxFilter.aux_code = {}
    AuxFilter.aux_index = {}
    AuxFilter.func(
        make_input({
            make_candidate({ text = "你", comment = "orig" }),
            make_candidate({ text = "泥", comment = "orig2" }),
        }),
        env
    )
    _G.yield = old_yield

    assert_equal(#output, 2, "should yield both")
    assert_equal(output[1].comment, "orig", "comment unchanged")
    assert_equal(output[2].comment, "orig2", "comment unchanged")
    clear_updater_preload()
end

--------------------------------------------------
-- Run all tests --
--------------------------------------------------
test_version_is_set()
test_updater_absent_init_succeeds()
test_updater_init_throws_is_caught()
test_updater_poll_throws_is_caught()
test_notice_on_first_regular_candidate()
test_notice_applied_only_once()
test_notice_remains_until_candidate_selection()
test_shadow_candidate_comment_not_corrupted()
test_notice_with_aux_error_path()
test_fini_cleans_up_updater()
test_fini_without_updater_is_safe()
test_no_notice_means_no_change()

print("All updater integration tests passed.")
