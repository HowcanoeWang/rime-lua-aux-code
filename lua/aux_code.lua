local AuxFilter = {}
local parse_aux_input

local function normalize_trigger(token, fallback)
    if token == nil or token == "" then
        return fallback
    end
    return token
end

local function build_missing_dict_message(filename)
    return "(⚠️config/rime/aux_code/ 中未找到辅码文件 " .. filename .. ")"
end

local function merge_comment(origin, message)
    if not origin or origin == "" then
        return message
    end
    if origin:find(message, 1, true) then
        return origin
    end
    return origin .. " | " .. message
end

local function append_missing_hint(cand, message)
    if not message or message == "" then
        return cand
    end

    if cand:get_dynamic_type() == "Shadow" then
        local shadow_text = cand.text
        local shadow_comment = cand.comment or ""
        local original = cand:get_genuine()
        if not original then
            cand.comment = merge_comment(cand.comment, message)
            return cand
        end

        local merged = merge_comment((original.comment or "") .. shadow_comment, message)
        return ShadowCandidate(original, original.type, shadow_text, merged)
    end

    cand.comment = merge_comment(cand.comment, message)
    return cand
end

-- local log = require 'log'
-- log.outfile = "aux_code.log"

function AuxFilter.init(env)
    -- log.info("** AuxCode filter", env.name_space)

    local aux_code, missing_path, missing_file = AuxFilter.readAuxTxt(env.name_space)
    if aux_code then
        AuxFilter.aux_code = aux_code
        env.aux_ready = true
        env.aux_error_msg = nil
    else
        AuxFilter.aux_code = {}
        env.aux_ready = false
        env.aux_error_msg = build_missing_dict_message(missing_file or (env.name_space .. ".txt"))
        if log and log.warning then
            log.warning("aux_code: dictionary load failed: " .. (missing_path or ""))
        end
    end

    local engine = env.engine
    local config = engine.schema.config

    -- 双触发键：learn 与 no_learn
    env.learn_trigger = normalize_trigger(config:get_string("key_binder/aux_code_learn_trigger"), nil)
        or normalize_trigger(config:get_string("key_binder/aux_code_trigger"), nil)
        or ";"
    env.no_learn_trigger = normalize_trigger(config:get_string("key_binder/aux_code_no_learn_trigger"), "")

    if env.no_learn_trigger == env.learn_trigger then
        env.no_learn_trigger = ""
    end

    env.triggers = {
        { mode = "no_learn", token = env.no_learn_trigger },
        { mode = "learn", token = env.learn_trigger },
    }

    local active_triggers = {}
    for _, item in ipairs(env.triggers) do
        if item.token ~= "" then
            table.insert(active_triggers, item)
        end
    end
    env.triggers = active_triggers

    table.sort(env.triggers, function(a, b)
        return #a.token > #b.token
    end)

    -- 兼容旧逻辑，后续任务会替换为 parse 模式
    env.trigger_key = env.learn_trigger
    -- 设定是否显示辅助码，默认为显示
    env.show_aux_notice = config:get_string("key_binder/show_aux_notice") or 'true'
    if env.show_aux_notice == "false" then
        env.show_aux_notice = false
    else
        env.show_aux_notice = true
    end

    ----------------------------
    -- 持續選詞上屏，保持輔助碼分隔符存在 --
    ----------------------------
    env.notifier = engine.context.select_notifier:connect(function(ctx)
        local mode, _, trigger_token = parse_aux_input(ctx.input, env)
        if mode == "none" then
            return
        end

        local preedit = ctx:get_preedit()
        local trigger_pattern = trigger_token:gsub("%W", "%%%1")
        local removeAuxInput = ctx.input:match("([^,]+)" .. trigger_pattern)
        local reeditTextFront = preedit.text:match("([^,]+)" .. trigger_pattern)

        if not removeAuxInput then
            return
        end

        -- ctx.text 隨著選字的進行，oaoaoa； 有如下的輸出：
        -- ---- 有輔助碼 ----
        -- >>> 啊 oaoa；au
        -- >>> 啊吖 oa；au
        -- >>> 啊吖啊；au
        -- ---- 無輔助碼 ----
        -- >>> 啊 oaoa；
        -- >>> 啊吖 oa；
        -- >>> 啊吖啊；
        -- 這邊把已經上屏的字段 (preedit:text) 進行分割；
        -- 如果已經全部選完了，分割後的結果就是 nil，否則都是 吖卡 a 這種字符串
        -- 驗證方式：
        -- log.info('select_notifier', ctx.input, removeAuxInput, preedit.text, reeditTextFront)

        -- 當最終不含有任何字母時 (候選)，就跳出分割模式，並把輔助碼分隔符刪掉
        ctx.input = removeAuxInput
        if reeditTextFront and reeditTextFront:match("[a-z]") then
            -- 給詞尾自動添加分隔符，上面的 re.match 會把分隔符刪掉
            ctx.input = ctx.input .. trigger_token
        else
            -- 剩下的直接上屏
            ctx:commit()
        end
    end)
end

----------------
-- 閱讀輔碼文件 --
----------------
function AuxFilter.readAuxTxt(txtpath)
    local dict_filename = txtpath .. ".txt"
    local file_absolute_path = rime_api.get_user_data_dir() .. "/aux_code/" .. dict_filename

    if not AuxFilter.cache then
        AuxFilter.cache = {}
    end

    if AuxFilter.cache[file_absolute_path] then
        return AuxFilter.cache[file_absolute_path], nil, dict_filename
    end

    -- log.info("** AuxCode filter", 'read Aux code txt:', txtpath)

    local file = io.open(file_absolute_path, "r")
    if not file then
        return nil, file_absolute_path, dict_filename
    end

    local auxCodes = {}
    for line in file:lines() do
        line = line:match("[^\r\n]+") -- 去掉換行符，不然 value 是帶著 \n 的
        local key, value = line:match("([^=]+)=(.+)") -- 分割 = 左右的變數
        if key and value then
            if auxCodes[key] then
                auxCodes[key] = auxCodes[key] .. " " .. value
            else
                auxCodes[key] = value
            end
        end
    end
    file:close()
    -- 確認 code 能打印出來
    -- for key, value in pairs(AuxFilter.aux_code) do
    --     log.info(key, table.concat(value, ','))
    -- end

    AuxFilter.cache[file_absolute_path] = auxCodes
    return auxCodes, nil, dict_filename
end

-- local function getUtf8CharLength(byte)
--     if byte < 128 then
--         return 1
--     elseif byte < 224 then
--         return 2
--     elseif byte < 240 then
--         return 3
--     else
--         return 4
--     end
-- end

-- 輔助函數，用於獲取表格的所有鍵
local function table_keys(t)
    local keys = {}
    for key, _ in pairs(t) do
        table.insert(keys, key)
    end
    return keys
end

-----------------------------------------------
-- 計算詞語整體的輔助碼
-- 目前定義為
--   把字或词组的所有辅码，第一个键堆到一起，第二个键堆到一起
--   例子：
--       候选(word) = 拜日
--          【拜】 的辅码有 charAuxCodes=
--             p a
--             p u
--             u a
--             u f
--             u u
--          【日】 的辅码有 charAuxCodes=
--             o r
--             r i
--             a a
--             u h
--       (竖着拍成左右两个字符串)
--   第一个辅码键的不重复列表为：fullAuxCodes[1]= urpao 
--   第二个辅码键的不重复列表为：fullAuxCodes[2]= urhafi
-- -----------------------------------------------
function AuxFilter.fullAux(env, word)
    local fullAuxCodes = {}
    -- log.info('候选词：', word)
    for _, codePoint in utf8.codes(word) do
        local char = utf8.char(codePoint)
        local charAuxCodes = AuxFilter.aux_code[char] -- 每個字的輔助碼組
        if charAuxCodes then -- 輔助碼存在
            for code in charAuxCodes:gmatch("%S+") do
                for i = 1, #code do
                    fullAuxCodes[i] = fullAuxCodes[i] or {}
                    fullAuxCodes[i][code:sub(i, i)] = true
                end
            end
        end
    end

    -- 將表格轉換為字符串
    for i, chars in pairs(fullAuxCodes) do
        fullAuxCodes[i] = table.concat(table_keys(chars), "")
    end

    return fullAuxCodes
end

-----------------------------------------------
-- 判斷 auxStr 是否匹配 fullAux
-----------------------------------------------
function AuxFilter.match(fullAux, auxStr)
    if #fullAux == 0 then
        return false
    end

    local firstKeyMatched = fullAux[1]:find(auxStr:sub(1, 1)) ~= nil
    -- 如果辅助码只有一个键，且第一个键匹配，则返回 true
    if #auxStr == 1 then
        return firstKeyMatched
    end

    -- 如果辅助码有两个或更多键，检查第二个键是否匹配
    local secondKeyMatched = fullAux[2] and fullAux[2]:find(auxStr:sub(2, 2)) ~= nil

    -- 只有当第一个键和第二个键都匹配时，才返回 true
    return firstKeyMatched and secondKeyMatched
end

local function escape_lua_pattern(text)
    return text:gsub("%W", "%%%1")
end

parse_aux_input = function(input_code, env)
    if input_code == "" then
        return "none", "", ""
    end

    for _, item in ipairs(env.triggers) do
        local token = item.token
        if token ~= "" then
            local token_pattern = escape_lua_pattern(token)
            if input_code:find(token, 1, true) then
                local local_split = input_code:match(token_pattern .. "([^,]+)")
                if not local_split then
                    return item.mode, "", token
                end
                return item.mode, string.sub(local_split, 1, 2), token
            end
        end
    end

    return "none", "", ""
end

local function to_commit_only_candidate(cand)
    local rebuilt = Candidate(cand.type, cand.start, cand._end, cand.text, cand.comment)
    rebuilt.preedit = cand.preedit
    rebuilt.quality = cand.quality
    return rebuilt
end

------------------
-- filter 主函數 --
------------------
function AuxFilter.func(input, env)
    local context = env.engine.context
    local inputCode = context.input

    local mode, auxStr, _ = parse_aux_input(inputCode, env)

    -- 判断字符串中是否包含輔助碼分隔符
    if mode == "none" then
        -- 没有输入辅助码引导符，则直接yield所有待选项，不进入后续迭代，提升性能
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    if not env.aux_ready then
        local should_hint = #auxStr == 0
        local hinted = false
        for cand in input:iter() do
            if should_hint and not hinted then
                cand = append_missing_hint(cand, env.aux_error_msg)
                hinted = true
            end
            yield(cand)
        end
        return
    end

    -- 更新逻辑：没有匹配上就不出现再候选框里，提升性能
    -- local insertLater = {}

    -- 遍歷每一個待選項
    for cand in input:iter() do
        local auxCodes = AuxFilter.aux_code[cand.text] -- 僅單字非 nil
        local fullAuxCodes = AuxFilter.fullAux(env, cand.text)

        -- 查看 auxCodes
        -- log.info(cand.text, #auxCodes)
        -- for i, cl in ipairs(auxCodes) do
        --     log.info(i, table.concat(cl, ',', 1, #cl))
        -- end

        -- 給待選項加上輔助碼提示
        if env.show_aux_notice and auxCodes and #auxCodes > 0 then
            local codeComment = auxCodes:gsub(' ', ',')
            -- 處理 simplifier
            if cand:get_dynamic_type() == "Shadow" then
                local shadowText = cand.text
                local shadowComment = cand.comment
                local originalCand = cand:get_genuine()
                cand = ShadowCandidate(originalCand, originalCand.type, shadowText,
                    originalCand.comment .. shadowComment .. '(' .. codeComment .. ')')
            else
                cand.comment = '(' .. codeComment .. ')'
            end
        end

        -- 過濾輔助碼
        if #auxStr == 0 then
            -- 沒有輔助碼、不需篩選，直接返回待選項
            if mode == "no_learn" then
                yield(to_commit_only_candidate(cand))
            else
                yield(cand)
            end
        elseif #auxStr > 0 and fullAuxCodes and (cand.type == 'user_phrase' or cand.type == 'phrase' or cand.type == 'simplified') and
            AuxFilter.match(fullAuxCodes, auxStr) then
            -- 匹配到辅助码的待选项，直接插入到候选框中( 获得靠前的位置 )
            if mode == "no_learn" then
                yield(to_commit_only_candidate(cand))
            else
                yield(cand)
            end
        else
            -- 待选项字词 没有 匹配到当前的辅助码，插入到列表中，最后插入到候选框里( 获得靠后的位置 )
            -- table.insert(insertLater, cand)
            -- 更新逻辑：没有匹配上就不出现再候选框里，提升性能
        end
    end

    -- 把沒有匹配上的待選給添加上
    -- for _, cand in ipairs(insertLater) do
    --     yield(cand)
    -- end
    -- 更新逻辑：没有匹配上就不出现再候选框里，提升性能

end

function AuxFilter.fini(env)
    env.notifier:disconnect()
end

return AuxFilter

-- Local Variables:
-- lua-indent-level: 4
-- End:
