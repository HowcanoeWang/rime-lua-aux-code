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

local function make_init_env(trigger, no_learn_trigger)
    local callback
    local config = {
        get_string = function(_, key)
            if key == "key_binder/aux_code_learn_trigger" then
                return trigger
            end
            if key == "key_binder/aux_code_no_learn_trigger" then
                return no_learn_trigger
            end
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

local function test_repeated_trigger_does_not_leave_aux_residue()
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
end

test_punctuation_after_aux_bypasses_filtering()
test_letter_aux_still_filters_candidates()
test_repeated_trigger_does_not_leave_aux_residue()
