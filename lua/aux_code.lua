-- local the aux table
local DEFAULT_FILE = 'ZRM_Aux-code_4.3.txt'
local user_path = rime_api.get_user_data_dir() .. "/lua/"
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
        -- print('select_notifier', ctx.input, ctx.caret_pos, preedit.text, preedit.sel_start, preedit.sel_end)
        local remove_aux_input = ctx.input:match("([^,]+);")

        -- ctx.text随着选字的进行，oaoaoa； 有如下的输出：
        -- >>> 啊 oaoa；
        -- >>> 啊吖 oa；
        -- >>> 啊吖啊；

        -- 所以当最终不含有任何字母时，就跳出分割模式并把；符号删掉 (使用pop_input)
        if AuxFilter.hasEnglishLetter(preedit.text) then
           -- 給詞尾自動添加分隔符，上面的re.match會把分隔符刪掉
           ctx.input = remove_aux_input .. ';'
        else
           -- 把；符号删掉 (使用pop_input)
           ctx:pop_input(1)
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
   
    local fileAbs = user_path .. txtpath .. ".txt"  
    local aux_code = {}
    for line in (io.open(fileAbs) or io.open(user_path .. )):lines() do
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

----------------------------
-- 判断字符串内是否有英文字母 --
----------------------------
function AuxFilter.hasEnglishLetter(str)
    return string.find(str, "%a") ~= nil
end
-- 测试是否能运行字母判断
-- print('啊阿oa；', hasEnglishLetter('啊阿oa；'))
-- print('啊阿吖；', hasEnglishLetter('啊阿吖；'))

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

    local l = {}

    -- 遍历每一个待选项
    for cand in input:iter() do
        -- 获取当前待选项的所有辅助码编号
        local code_list = env.aux_code[cand.text]

        -- 给待选项加上辅助码提示
        if code_list then
            local code_comment = table.concat(code_list, ',', 1, #code_list)

            if cand:get_dynamic_type() == "Shadow" then
                local s_text= cand.text
                local s_comment = cand.comment 
                local org_cand = cand:get_genuine() 
                cand = ShadowCandidate(org_cand, org_cand.type, s_text, org_cand.comment .. s_comment  .. '(' .. code_comment .. ')' )
            else
                cand.comment = '(' .. code_comment .. ')'
            end
            -- print(cand.text .. ' -> code_list: ' .. code_comment)
        end

        -- 过滤辅助码
        if aux_str and code_list and #aux_str>0 then
            -- print('input aux code ->')

            for i, cl in ipairs(code_list) do
                -- print(cl, i, aux_str)
                if cl == aux_str then
                    -- print('matched!')
                    yield(cand)
                end
            end
        else
            table.insert(l, cand)
        end
    end

    for i, cand in ipairs(l) do
        yield(cand)
    end
end

function AuxFilter.fini(env)
    env.notifier:disconnect()
end

return AuxFilter
