package.path = "./lua/?.lua;" .. package.path

local AuxFilter = require("aux_code")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, expected, actual), 2)
    end
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

local function make_env(input_code)
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

local function make_init_env(trigger, no_learn_trigger, show_aux_notice, legacy)
    local callback
    legacy = legacy or {}
    local config = {
        get_string = function(_, key)
            if key == "aux_code/learn_trigger" and trigger ~= nil then
                return trigger
            end
            if key == "aux_code/no_learn_trigger" and no_learn_trigger ~= nil then
                return no_learn_trigger
            end
            if legacy.strings then return legacy.strings[key] end
            return nil
        end,
        get_bool = function(_, key)
            if key == "aux_code/show_aux_notice" and show_aux_notice ~= nil then
                return show_aux_notice
            end
            if legacy.bools then return legacy.bools[key] end
            return nil
        end,
    }

    return {
        name_space = "missing_aux_code_test",
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

local function init_filter(env)
    package.preload["aux_code_updater"] = function() return false end
    package.loaded["aux_code_updater"] = nil
    local old_rime_api = _G.rime_api
    local old_read_aux_txt = AuxFilter.readAuxTxt
    _G.rime_api = {
        get_shared_data_dir = function() return "/tmp" end,
        get_user_data_dir = function() return "/tmp" end,
    }
    AuxFilter.readAuxTxt = function() return {} end
    AuxFilter.init(env)
    AuxFilter.readAuxTxt = old_read_aux_txt
    _G.rime_api = old_rime_api
    return env
end

local function collect_output(input_code, aux_index)
    local output = {}
    local old_yield = _G.yield

    _G.yield = function(cand)
        table.insert(output, cand)
    end

    AuxFilter.aux_code = {}
    AuxFilter.aux_index = aux_index or {}
    AuxFilter.func(make_input({
        { type = "phrase", text = "你", start = 0, _end = 2 },
        { type = "phrase", text = "泥", start = 0, _end = 2 },
    }), make_env(input_code))

    _G.yield = old_yield
    return output
end

local function test_punctuation_after_aux_bypasses_filtering()
    local output = collect_output("ni;zz.")

    assert_equal(#output, 2, "punctuation after aux should bypass filtering")
    assert_equal(output[1].text, "你", "first candidate should remain")
    assert_equal(output[2].text, "泥", "second candidate should remain")
end

local function test_letter_aux_still_filters_candidates()
    local output = collect_output("ni;z", {
        ["你"] = { k1 = { z = true }, k12 = {} },
    })

    assert_equal(#output, 1, "letter aux should still filter candidates")
    assert_equal(output[1].text, "你", "matching candidate should remain")
end

local function test_trigger_at_input_start_bypasses_filtering()
    local output = collect_output(";z", {
        ["你"] = { k1 = { z = true }, k12 = {} },
    })

    assert_equal(#output, 2, "trigger at input start should not enable aux filtering")
    assert_equal(output[1].text, "你", "first candidate should remain")
    assert_equal(output[2].text, "泥", "second candidate should remain")
end

local function test_init_reads_aux_code_config()
    package.preload["aux_code_updater"] = function() return false end
    package.loaded["aux_code_updater"] = nil

    local env = make_init_env(";", "#", false)
    local old_rime_api = _G.rime_api
    local old_read_aux_txt = AuxFilter.readAuxTxt
    _G.rime_api = {
        get_shared_data_dir = function()
            return "/tmp"
        end,
        get_user_data_dir = function()
            return "/tmp"
        end,
    }
    AuxFilter.readAuxTxt = function()
        return {}
    end

    AuxFilter.init(env)

    AuxFilter.readAuxTxt = old_read_aux_txt
    _G.rime_api = old_rime_api

    assert_equal(env.learn_trigger, ";", "learn trigger should use aux_code config")
    assert_equal(env.no_learn_trigger, "#", "no-learn trigger should use aux_code config")
    assert_equal(env.show_aux_notice, false, "notice flag should use aux_code config")
    assert_equal(env.updater, nil, "updater should be nil when module is absent")
end

local function test_init_reads_legacy_key_binder_config()
    local env = init_filter(make_init_env(nil, nil, nil, {
        strings = {
            ["key_binder/aux_code_learn_trigger"] = "#",
            ["key_binder/aux_code_trigger"] = "$",
            ["key_binder/aux_code_no_learn_trigger"] = "##",
            ["key_binder/show_aux_notice"] = "false",
        },
    }))
    assert_equal(env.learn_trigger, "#", "legacy trigger should remain compatible")
    assert_equal(env.no_learn_trigger, "##", "legacy no-learn trigger should remain compatible")
    assert_equal(env.show_aux_notice, false, "legacy notice flag should remain compatible")
    assert_equal(env.uses_legacy_config, true, "legacy config should be detected")
    AuxFilter.fini(env)
end

local function test_new_config_overrides_legacy_config()
    local env = init_filter(make_init_env("#", "", false, {
        strings = {
            ["key_binder/aux_code_learn_trigger"] = ";",
            ["key_binder/aux_code_no_learn_trigger"] = ";;",
            ["key_binder/show_aux_notice"] = "true",
        },
    }))
    assert_equal(env.learn_trigger, "#", "new trigger should take priority")
    assert_equal(env.no_learn_trigger, "", "explicit empty new trigger should disable legacy no-learn")
    assert_equal(env.show_aux_notice, false, "new notice flag should take priority")
    assert_equal(env.uses_legacy_config, false, "ignored legacy config should not trigger migration")
    AuxFilter.fini(env)
end

local function test_legacy_config_notice_remains_until_selection()
    local env = init_filter(make_init_env(nil, nil, nil, {
        strings = { ["key_binder/aux_code_trigger"] = ";" },
    }))
    env.engine.context.input = "ni"
    local function run_filter()
        local output = {}
        local old_yield = _G.yield
        _G.yield = function(cand) output[#output + 1] = cand end
        AuxFilter.func(make_input({ {
            type = "phrase", text = "你", start = 0, _end = 2,
            get_dynamic_type = function() return "Candidate" end,
        } }), env)
        _G.yield = old_yield
        return output[1]
    end
    local first = run_filter()
    local second = run_filter()
    assert_equal(first.comment:find("请迁移辅助码插件旧版配置", 1, true) ~= nil, true,
        "legacy migration notice should be shown")
    assert_equal(second.comment:find("请迁移辅助码插件旧版配置", 1, true) ~= nil, true,
        "legacy migration notice should remain visible while composing")
    env.get_select_callback()(env.engine.context)
    local after_selection = run_filter()
    assert_equal(after_selection.comment, nil, "legacy migration notice should stop after candidate selection")
    AuxFilter.fini(env)

    env = init_filter(make_init_env(nil, nil, nil, {
        strings = { ["key_binder/aux_code_trigger"] = ";" },
    }))
    env.engine.context.input = "ni"
    local after_reinit = run_filter()
    assert_equal(after_reinit.comment:find("请迁移辅助码插件旧版配置", 1, true) ~= nil, true,
        "legacy migration notice should reset after filter initialization")
    AuxFilter.fini(env)
end

local function test_repeated_trigger_does_not_leave_aux_residue()
    package.preload["aux_code_updater"] = function() return false end
    package.loaded["aux_code_updater"] = nil

    local ctx = { input = "ni;;fy" }
    local committed = false
    local env = make_init_env(";", "")

    local old_rime_api = _G.rime_api
    local old_read_aux_txt = AuxFilter.readAuxTxt
    _G.rime_api = {
        get_shared_data_dir = function()
            return "/tmp"
        end,
        get_user_data_dir = function()
            return "/tmp"
        end,
    }
    AuxFilter.readAuxTxt = function()
        return {}
    end

    AuxFilter.init(env)
    ctx.get_preedit = function()
        return { text = "拟;;fy" }
    end
    ctx.commit = function()
        committed = true
    end
    env.get_select_callback()(ctx)

    AuxFilter.readAuxTxt = old_read_aux_txt
    _G.rime_api = old_rime_api

    assert_equal(ctx.input, "ni", "repeated trigger residue should be removed")
    assert_equal(committed, true, "selection should commit after clearing residue")
    assert_equal(env.updater, nil, "updater should be nil when module is absent")
end

test_punctuation_after_aux_bypasses_filtering()
test_letter_aux_still_filters_candidates()
test_trigger_at_input_start_bypasses_filtering()
test_init_reads_aux_code_config()
test_init_reads_legacy_key_binder_config()
test_new_config_overrides_legacy_config()
test_legacy_config_notice_remains_until_selection()
test_repeated_trigger_does_not_leave_aux_residue()
