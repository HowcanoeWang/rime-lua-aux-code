local AuxFilter = {}

function AuxFilter.init(env)
    print("** AuxCode filter", env.name_space)

    env.aux_code = AuxFilter.readAuxTxt(env.name_space);

    ----------------------------
    -- 持续选词上屏，保持分号存在 --
    ----------------------------
    env.notifier = env.engine.context.select_notifier:connect(function(ctx)
        -- 含有辅助码分割符才處理，；
        if not string.find(ctx.input, ';') then
            return
        end

        local preedit = ctx:get_preedit()
        local removeAuxInput = ctx.input:match("([^,]+);")
        local reeditTextFront = preedit.text:match("([^,]+);")

        -- ctx.text 随着选字的进行，oaoaoa； 有如下的输出：
        -- ---- 有辅助码 ----
        -- >>> 啊 oaoa；au
        -- >>> 啊吖 oa；au
        -- >>> 啊吖啊；au
        -- ---- 无辅助码 ----
        -- >>> 啊 oaoa；
        -- >>> 啊吖 oa；
        -- >>> 啊吖啊；
        -- 这边把已经上屏的字段 (preedit:text) 进行分割；
        -- 如果已经全部选完了，分割后的结果就是 nil，否则都是 吖卡 a 这种字符串
        -- 验证方式：
        -- print('select_notifier', ctx.input, remove_aux_input, preedit.text, reedit_text_front)

        -- 当最终不含有任何字母时 (候选)，就跳出分割模式，并把；符号删掉
        if reeditTextFront ~= nil then
            -- 給詞尾自動添加分隔符，上面的 re.match 會把分隔符刪掉
            ctx.input = removeAuxInput .. ';'
        else
            -- 把；符号删掉
            ctx.input = removeAuxInput
            -- 剩下的直接上屏
            ctx:commit()
        end
    end)
end

----------------
-- 阅读辅码文件 --
----------------
function AuxFilter.readAuxTxt(txtpath)
    -- print("** AuxCode filter", 'read Aux code txt:', txtpath)

    local defaultFile = 'ZRM_Aux-code_4.3.txt'
    local userPath = rime_api.get_user_data_dir() .. "/lua/"
    local fileAbsolutePath = userPath .. txtpath .. ".txt"

    local file = io.open(fileAbsolutePath, "r") or io.open(userPath .. defaultFile, "r")
    if not file then
        error("Unable to open auxiliary code file.")
        return {}
    end

    local auxCodes = {}
    for line in file:lines() do
        line = line:match("[^\r\n]+") -- 去掉换行符，不然 value 是带着 \n 的
        local key, value = line:match("([^=]+)=(.+)") -- 分割 = 左右的变量
        if key and value then
            auxCodes[key] = auxCodes[key] or {}
            table.insert(auxCodes[key], value)
        end
    end
    file:close()
    -- 确认 code 能打印出来
    -- for key, value in pairs(env.aux_code) do
    --     print(key, table.concat(value, ','))
    -- end

    return auxCodes
end

-----------------------------------------------
-- 计算词语整体的辅助码
-- 目前定义为
--   fullAux(word)[k] = {code[k] | code in aux_code(char) for char in word }
--   白日依山尽
--   fullAux = {
--       1: [p,pa,pn,pn, ..]  -- '白'
--       2: [o,or,ri, ..]     -- '日'
--   }
-----------------------------------------------
function AuxFilter.fullAux(env, word)
    local fullAuxCodes = {}
    -- print('候选词：', word)
    for i, codePoint in utf8.codes(word) do
        -- i = 1, 4, 7, ...
        local char = utf8.char(codePoint)
        local charAuxCodes = env.aux_code[char] -- cl = 每个字的辅助码组
        if charAuxCodes then -- 辅助码存在
            -- print('遍历第'.. (i-1)//3+1 .. '个字', c, table.concat(cl, ',', 1, #cl))
            fullAuxCodes[(i - 1) // 3 + 1] = charAuxCodes
        end
    end
    return fullAuxCodes
end

-----------------------------------------------
-- 判断 aux_str 是否匹配 full_aux，且返回匹配的是第几个字，
--    如果没有匹配，则返回 0
-----------------------------------------------
function AuxFilter.fullMatch(fullAux, auxStr)
    if #fullAux == 0 then
        return 0
    end

    for i = 1, #fullAux do
        local codeList = fullAux[i]

        -- 一个个遍历待选项
        for _, cl in ipairs(codeList) do
            -- print(cl, i, aux_str)
            if cl == auxStr then
                return i
            end
        end
    end

    return 0
end

-----------------
-- filter 主函数 --
-----------------
function AuxFilter.func(input, env)
    local context = env.engine.context
    local inputCode = context.input

    -- 分割部分正式开始
    local auxStr = ''
    if string.find(inputCode, ';') then
        -- 字符串中包含; 分字字符
        local localSplit = inputCode:match(";([^,]+)")
        if localSplit then
            auxStr = string.sub(localSplit, 1, 2)
            -- print('re.match ' .. local_split)
        end
    end

    local insertLater = {}
    local orderByIndex = {}

    -- 遍历每一个待选项
    for cand in input:iter() do
        -- local code_list = env.aux_code[cand.text]  -- 仅单字非 nil
        -- local current_aux = AuxFilter.fullAux(env, cand.text)

        local auxCodes = AuxFilter.fullAux(env, cand.text)

        -- 查看 code_list
        -- print(cand.text, #code_list)
        -- for i, cl in ipairs(code_list) do
        --     print(i, table.concat(cl, ',', 1, #cl))
        -- end

        -- 给单个字的待选项加上辅助码提示
        if #auxCodes == 1 then
            local codeComment = table.concat(auxCodes[1], ',')
            -- 处理 simplifier
            if cand:get_dynamic_type() == "Shadow" then
                local shadowText = cand.text
                local shadowComment = cand.comment
                local originalCand = cand:get_genuine()
                cand = ShadowCandidate(originalCand, originalCand.type, shadowText,
                    originalCand.comment .. shadowComment .. ' (' .. codeComment .. ')')
            else
                cand.comment = cand.comment .. ' (' .. codeComment .. ')'
            end
        end

        -- 过滤辅助码
        local matchId = AuxFilter.fullMatch(auxCodes, auxStr)
        if matchId > 0 and (cand.type == 'user_phrase' or cand.type == 'phrase') then
            -- print('匹配到候选['.. cand.text ..  '] 第' .. match_id .. '个字，权重：'.. cand.quality)
            -- yield(cand)
            orderByIndex[matchId] = orderByIndex[matchId] or {}
            table.insert(orderByIndex[matchId], cand)
        else
            table.insert(insertLater, cand)
        end
    end

    -- 逐个添加辅助码过滤出来的结果
    -- 并且按照匹配到的字数进行排序
    for _, obi in ipairs(orderByIndex) do
        for _, cand in ipairs(obi) do
            yield(cand)
        end
    end

    -- 把没有匹配上的待选给添加上
    for _, cand in ipairs(insertLater) do
        yield(cand)
    end
end

function AuxFilter.fini(env)
    env.notifier:disconnect()
end

return AuxFilter
