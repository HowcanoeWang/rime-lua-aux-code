local AuxFilter = {}

function AuxFilter.init(env)
    print( "** AuxCode filter", env.name_space )

    env.aux_code = AuxFilter.read_aux_txt(env.name_space);

    ----------------------------
    -- 持续选词上屏，保持分号存在 --
    ----------------------------
    env.notifier = env.engine.context.select_notifier:connect(
    function(ctx)
        -- 含有辅助码分割符才處理，；
        if not string.find(ctx.input, ';') then return end

        local preedit = ctx:get_preedit()
        local remove_aux_input = ctx.input:match("([^,]+);")
        local reedit_text_front = preedit.text:match("([^,]+);")
        
        -- ctx.text随着选字的进行，oaoaoa； 有如下的输出：
        -- ----有辅助码----
        -- >>> 啊 oaoa；au
        -- >>> 啊吖 oa；au
        -- >>> 啊吖啊；au
        -- ----无辅助码----
        -- >>> 啊 oaoa；
        -- >>> 啊吖 oa；
        -- >>> 啊吖啊；
        -- 这边把已经上屏的字段(preedit:text)进行分割；
        -- 如果已经全部选完了，分割后的结果就是nil，否则都是 吖卡a 这种字符串
        -- 验证方式：
        -- print('select_notifier', ctx.input, remove_aux_input, preedit.text, reedit_text_front)
        
        -- 当最终不含有任何字母时(候选)，就跳出分割模式，并把；符号删掉
        if reedit_text_front ~= nil then
            -- 給詞尾自動添加分隔符，上面的re.match會把分隔符刪掉
            ctx.input = remove_aux_input .. ';'
        else
            -- 把；符号删掉
            ctx.input = remove_aux_input
            -- 剩下的直接上屏
            ctx:commit()
        end 
    end)
end

----------------
-- 阅读辅码文件 --
----------------
function AuxFilter.read_aux_txt(txtpath)
    print( "** AuxCode filter", 'read Aux code txt:', txtpath)

    local DEFAULT_FILE = 'ZRM_Aux-code_4.3.txt'
    local user_path = rime_api.get_user_data_dir() .. "/lua/"
    local fileAbs = user_path .. txtpath .. ".txt"  
    local aux_code = {}
    for line in (io.open(fileAbs) or io.open(user_path .. DEFAULT_FILE)):lines() do
        line = line:match("[^\r\n]+") --去掉换行符，不然value是带着\n的
        local key, value = line:match("([^=]+)=(.+)")  -- 分割=左右的变量
        if key and value then
            aux_code[key] = aux_code[key] or {}
            table.insert(aux_code[key], value)
        end
    end
    -- 确认code能打印出来
    -- for key, value in pairs(env.aux_code) do
    --     print(key, table.concat(value, ','))
    -- end

    return aux_code
end

-----------------------------------------------
-- 计算词语整体的辅助码
-- 目前定义为
--   fullAux(word)[k] = { code[k] | code in aux_code(char) for char in word }
--   白日依山尽
--   fullAux = {
--       1: [p,pa,pn,pn, ..]  -- '白'
--       2: [o,or,ri, ..]     -- '日'
--   }
-----------------------------------------------
function AuxFilter.fullAux(env, word)
    local full_aux = {}
    -- print('候选词：', word)
    for i, cp in utf8.codes(word) do
        -- i = 1, 4, 7, ...
        local c = utf8.char(cp)
        local cl = env.aux_code[c]   -- cl = 每个字的辅助码组
        if cl then  -- 辅助码存在
            -- print('遍历第'.. i//3+1 .. '个字', c, table.concat(cl, ',', 1, #cl))
            full_aux[i//3+1] = cl
        end
    end
    return full_aux
end


-----------------------------------------------
-- 判断 aux_str 是否匹配 full_aux，且返回匹配的是第几个字，
--    如果没有匹配，则返回0
-----------------------------------------------
function AuxFilter.fullMatch(full_aux, aux_str)
    if #full_aux == 0 then
        return 0
    end

    for i = 1, #full_aux do
        local code_list = full_aux[i]

        -- 一个个遍历待选项
        for j, cl in ipairs(code_list) do
            -- print(cl, i, aux_str)
            if cl == aux_str then
                return i
            end
        end
    end

    return 0
end

-----------------
-- filter主函数 --
-----------------
function AuxFilter.func(input,env)
    local engine = env.engine
    local context = engine.context
    local input_code = engine.context.input

    -- 分割部分正式开始
    local aux_str = ''

    if string.find(input_code, ';') then
        -- 字符串中包含;分字字符
        local local_split = input_code:match(";([^,]+)")
        
        if local_split then
            aux_str = string.sub(local_split, 1, 2)
            -- print('re.match ' .. local_split)
        end
    end

    local insert_later = {}
    local order_by_index = {}

    -- 遍历每一个待选项
    for cand in input:iter() do
        -- local code_list = env.aux_code[cand.text]  -- 仅单字非 nil
        -- local current_aux = AuxFilter.fullAux(env, cand.text)

        local code_list = AuxFilter.fullAux(env, cand.text)

        -- 查看 code_list
        -- print(cand.text, #code_list)
        -- for i, cl in ipairs(code_list) do
        --     print(i, table.concat(cl, ',', 1, #cl))
        -- end
        
        -- 给单个字的待选项加上辅助码提示
        if code_list and #code_list == 1 then
            local code_comment = table.concat(code_list[1], ',', 1, #code_list[1])
            -- 处理 simplifier
            if cand:get_dynamic_type() == "Shadow" then
                local s_text= cand.text
                local s_comment = cand.comment
                local org_cand = cand:get_genuine()
                cand = ShadowCandidate(org_cand, org_cand.type, s_text, org_cand.comment .. s_comment  .. '(' .. code_comment .. ')' )
            else
                cand.comment = '(' .. code_comment .. ')'
            end
        end

        -- 过滤辅助码
        if aux_str and #aux_str > 0 and code_list and (cand.type == 'user_phrase' or cand.type == 'phrase') then
            local match_id =  AuxFilter.fullMatch(code_list, aux_str)
            if match_id > 0 then
                print('匹配到候选['.. cand.text ..  '] 第' .. match_id .. '个字，权重：'.. cand.quality)
                -- yield(cand)
                order_by_index[match_id] = order_by_index[match_id] or {}
                table.insert(order_by_index[match_id], cand)
            end
        else
            table.insert(insert_later, cand)
        end
    end

    -- 逐个添加辅助码过滤出来的结果
    -- 并且按照字数进行排序
    for i, obi in ipairs(order_by_index) do
        for j, cand in ipairs(obi) do
            yield(cand)
        end
    end

    -- 把没有匹配上的待选给添加上
    for i, cand in ipairs(insert_later) do
        yield(cand)
    end
end

function AuxFilter.fini(env)
    env.notifier:disconnect()
end

return AuxFilter
