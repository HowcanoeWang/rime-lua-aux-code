local AuxFilter = {}

-- local log = require 'log'
-- log.outfile = "aux_code.log"

local function endswith(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

function AuxFilter.init(env)
    -- log.info("** AuxCode filter", env.name_space)

    env.aux_code = AuxFilter.readAuxTxt(env.name_space)

    ----------------------------
    -- 持續選詞上屏，保持分號存在 --
    ----------------------------
    env.notifier = env.engine.context.select_notifier:connect(function(ctx)
        -- 含有輔助碼分隔符才處理，；
        if not string.find(ctx.input, ';') then
            return
        end

        local preedit = ctx:get_preedit()
        local removeAuxInput = ctx.input:match("([^,]+);")
        local reeditTextFront = preedit.text:match("([^,]+);")

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
        -- 如果已經全部選完了，分割後的結果就是 nil，否則都是 啞卡 a 這種字符串
        -- 驗證方式：
        -- log.info('select_notifier', ctx.input, removeAuxInput, preedit.text, reeditTextFront)

        -- 當最終不含有任何字母時 (候選)，就跳出分割模式，並把；符號刪掉
        ctx.input = removeAuxInput
        if reeditTextFront and reeditTextFront:match("[a-z]") then
            -- 給詞尾自動添加分隔符，上面的 re.match 會把分隔符刪掉
            ctx.input = ctx.input .. ';'
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
    -- log.info("** AuxCode filter", 'read Aux code txt:', txtpath)

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
        line = line:match("[^\r\n]+") -- 去掉換行符，不然 value 是帶著 \n 的
        local key, value = line:match("([^=]+)=(.+)") -- 分割 = 左右的變數
        if key and value then
            auxCodes[key] = auxCodes[key] or {}
            table.insert(auxCodes[key], value)
        end
    end
    file:close()
    -- 確認 code 能打印出來
    -- for key, value in pairs(env.aux_code) do
    --     log.info(key, table.concat(value, ','))
    -- end

    return auxCodes
end

-----------------------------------------------
-- 計算詞語整體的輔助碼
-- 目前定義為
--   fullAux(word)[k] = { code[k] | code in aux_code(char) for char in word }
--   白日依山尽
--   fullAux = {
--       1: [p,pa,pn,pn, ..]  -- '白'
--       2: [o,or,ri, ..]     -- '日'
--   }
-----------------------------------------------
function AuxFilter.fullAux(env, word)
    local fullAuxCodes = {}
    -- log.info('候选词：', word)
    for i, codePoint in utf8.codes(word) do
        -- i = 1, 4, 7, ...
        local char = utf8.char(codePoint)
        local charAuxCodes = env.aux_code[char] -- 每個字的輔助碼組
        if charAuxCodes then -- 輔助碼存在
            -- log.info('遍历第'.. (i-1)//3+1 .. '个字', char, table.concat(charAuxCodes, ',', 1, #charAuxCodes))
            fullAuxCodes[(i - 1) // 3 + 1] = charAuxCodes
        end
    end
    return fullAuxCodes
end

-----------------------------------------------
-- 判斷 auxStr 是否匹配 fullAux，且返回匹配的是第幾個字，
--    如果沒有匹配，則返回 0
-----------------------------------------------
function AuxFilter.fullMatch(fullAux, auxStr)
    if #fullAux == 0 then
        return 0
    end

    for i = 1, #fullAux do
        local codeList = fullAux[i]

        -- 一個個遍歷待選項
        for _, cl in ipairs(codeList) do
            -- log.info(cl, i, auxStr)
            if cl == auxStr then
                return i
            end
        end
    end

    return 0
end

-----------------
-- filter 主函數 --
-----------------
function AuxFilter.func(input, env)
    local context = env.engine.context
    local inputCode = context.input

    -- 分割部分正式開始
    local auxStr = ''
    if string.find(inputCode, ';') then
        -- 字符串中包含 ; 分字字符
        local localSplit = inputCode:match(";([^,]+)")
        if localSplit then
            auxStr = string.sub(localSplit, 1, 2)
            -- log.info('re.match ' .. local_split)
        end
    end

    local insertLater = {}
    local orderByIndex = {}

    -- 遍歷每一個待選項
    for cand in input:iter() do
        -- local auxCodes = env.aux_code[cand.text]  -- 僅單字非 nil
        -- local current_aux = AuxFilter.fullAux(env, cand.text)

        local auxCodes = AuxFilter.fullAux(env, cand.text)

        -- 查看 auxCodes
        -- log.info(cand.text, #auxCodes)
        -- for i, cl in ipairs(auxCodes) do
        --     log.info(i, table.concat(cl, ',', 1, #cl))
        -- end

        -- 給單個字的待選項加上輔助碼提示
        if #auxCodes == 1 then
            local codeComment = table.concat(auxCodes[1], ',')
            -- 處理 simplifier
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

        -- 過濾輔助碼
        if #auxStr > 0 and auxCodes and (cand.type == 'user_phrase' or cand.type == 'phrase') then
            local matchId = AuxFilter.fullMatch(auxCodes, auxStr)
            if matchId > 0 then
                -- log.info('匹配到候选['.. cand.text ..  '] 第' .. matchId .. '个字，权重：'.. cand.quality)
                -- yield(cand)
                orderByIndex[matchId] = orderByIndex[matchId] or {}
                table.insert(orderByIndex[matchId], cand)
            end
        else
            table.insert(insertLater, cand)
        end
    end

    -- 逐個添加輔助碼過濾出來的結果
    -- 並且按照匹配到的字數進行排序
    for _, obi in ipairs(orderByIndex) do
        for _, cand in ipairs(obi) do
            yield(cand)
        end
    end

    -- 把沒有匹配上的待選給添加上
    for _, cand in ipairs(insertLater) do
        yield(cand)
    end
end

function AuxFilter.fini(env)
    env.notifier:disconnect()
end

return AuxFilter
