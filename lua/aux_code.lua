local AuxFilter = {}
-- local log = require ('log')
-- log.outfile = "a.txt"


-- 定义函数来统计子字符串出现的次数
local function countSubstringOccurrences(str, substr)
    local count = 0
    local startPos = 1

    while true do
        local foundPos = string.find(str, substr, startPos, true) -- true 表示按字面意义查找（不使用模式匹配）
        if not foundPos then
            break
        end
        count = count + 1
        startPos = foundPos + #substr -- 更新开始位置以继续查找
    end

    return count
end

-- 计算UTF-8字符串中的字符数量
local function utf8len(str)
    local len = 0
    local currentIndex = 1
    local bytes = string.len(str)
    while currentIndex <= bytes do
        len = len + 1
        local byte = string.byte(str, currentIndex)
        if byte <= 127 then
            currentIndex = currentIndex + 1
        elseif byte <= 223 then
            currentIndex = currentIndex + 2
        elseif byte <= 239 then
            currentIndex = currentIndex + 3
        else
            currentIndex = currentIndex + 4
        end
    end
    return len
end

-- 提取UTF-8字符串的子字符串
local function utf8sub(str, i, j)
    local currentIndex = 1
    local startIndex = 1
    local endIndex = string.len(str)

    local function nextIndex(currentIndex)
        local byte = string.byte(str, currentIndex)
        if byte <= 127 then
            return currentIndex + 1
        elseif byte <= 223 then
            return currentIndex + 2
        elseif byte <= 239 then
            return currentIndex + 3
        else
            return currentIndex + 4
        end
    end

    local len = utf8len(str)
    if i < 0 then
        i = len + i + 1
    end
    if j == nil then
        j = len
    elseif j < 0 then
        j = len + j + 1
    end

    local charIndex = 1
    while currentIndex <= string.len(str) do
        if charIndex == i then
            startIndex = currentIndex
        end
        if charIndex == j + 1 then
            endIndex = currentIndex - 1
            break
        end
        currentIndex = nextIndex(currentIndex)
        charIndex = charIndex + 1
    end

    return string.sub(str, startIndex, endIndex)
end
function AuxFilter.init(env)
    -- log.info("ini",111)
    -- log.info("** AuxCode filter", env.name_space)
    local engine = env.engine
    local config = engine.schema.config
    AuxFilter.matchmode=0 --设置匹配模式 0宽松匹配和1严格匹配
    --读码
    if AuxFilter.aux_code == nil then
        AuxFilter.readAuxTxt(env.name_space)
    end
    -- if AuxFilter.comb_code == nil then
    --     AuxFilter.comb_code = AuxFilter.read_ybxkcomb_File("ybxkcomb")
    -- end
    -- 設定預設觸發鍵為分號，並從配置中讀取自訂的觸發鍵
    AuxFilter.trigger_key = config:get_string("key_binder/aux_code_trigger") or ";"
    -- 设定是否显示辅助码，默认为显示
    AuxFilter.show_aux_notice = config:get_string("key_binder/show_aux_notice") or 'true'
    if AuxFilter.show_aux_notice == "false" then
        AuxFilter.show_aux_notice = false
    else
        AuxFilter.show_aux_notice = true
    end
    -- 不同模式不同处理逻辑

    env.notifier = engine.context.select_notifier:connect(function(ctx)

    if env.notifiermark ==1 then
        AuxFilter.main1_notifier(ctx)
    elseif env.notifiermark==2 then
        AuxFilter.longcandimodify_notifier(ctx)
    elseif env.notifiermark==3 then
        AuxFilter.longcandimodify_ybnotifier(ctx)
    end
    end)
end

--- notifier main1模式  (辅筛)
    ----------------------------
    -- 持續選詞上屏，保持輔助碼分隔符存在 --
    ----------------------------
function AuxFilter.main1_notifier(ctx)
    local preedit = ctx:get_preedit()
        local removeAuxInput = ctx.input:match("([^,]+)" .. AuxFilter.trigger_key)
        local reeditTextFront = preedit.text:match("([^,]+)" .. AuxFilter.trigger_key)
        -- log.info(removeAuxInput,reeditTextFront)
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
            ctx.input = ctx.input .. AuxFilter.trigger_key
        else
            -- 剩下的直接上屏 
            ctx:commit()
        end
    end







--- notifier longcandimodify模式  (断句模式)
    ----------------------------
    -- 保持輔助碼分隔符和原辅码存在 --
    ----------------------------
function AuxFilter.longcandimodify_notifier(ctx)
    local preedit = ctx:get_preedit()
        local removeAuxInput = ctx.input:match("(%a*)" .. AuxFilter.trigger_key.."-")
        local auxcode = ctx.input:match(AuxFilter.trigger_key .. "(%a*)" .. AuxFilter.trigger_key)
        -- log.info("auxcode",auxcode)
        -- log.info("removeauxinput",removeAuxInput)
        local reeditTextFront = preedit.text:match("([^"..AuxFilter.trigger_key .."]-)" .. AuxFilter.trigger_key)
        ctx.input = removeAuxInput
        if reeditTextFront and reeditTextFront:match("[a-z]") then
            -- 給詞尾自動添加分隔符和原辅码进入到辅筛模式，上面的 re.match 會把分隔符刪掉
            ctx.input = ctx.input .. AuxFilter.trigger_key .. auxcode
        else
            -- 剩下的直接上屏 
            ctx:commit()
        end
    end

--- notifier longcandimodify2模式(修音模式) 
    ----------------------------
    --保持輔助碼分隔符存在 -- 
    ----------------------------

function AuxFilter.longcandimodify_ybnotifier(ctx)
    -- log.info("modifyinput",AuxFilter.ybmodifiedcode)
    ctx.input = AuxFilter.ybmodifiedcode
    end



-- 生成所有长度为1和2的组合 的函数  输入 adf 会输出 {a,d,f,ad,af,df}  
local function two_char_combinations(str)
    local result = {}
    local n = #str
    
    -- 生成所有长度为1的组合
    for i = 1, n do
        table.insert(result, str:sub(i, i))
    end
    
    -- 生成所有长度为2的组合
    for i = 1, n do
        for j = i + 1, n do
            table.insert(result, str:sub(i, i) .. str:sub(j, j))
        end
    end
    
    return result
end
----------------
----------------
-- 閱讀輔碼文件 --
----------------
function AuxFilter.readAuxTxt(txtpath)
    -- 读得文件格式变了 字 音 辅的表   ||  嗄	aa	kw
    -- log.info("** AuxCode filter", 'read Aux code txt:', txtpath)
    -- log.info("读文件") --这里打印日志 
    local defaultFile = 'ZRM_Aux-code_4.3.txt'
    local userPath = rime_api.get_user_data_dir() .. "/lua/"
    local fileAbsolutePath = userPath .. txtpath .. ".txt"
    -- log.info(fileAbsolutePath)
    local file = io.open(fileAbsolutePath, "r") or io.open(userPath .. defaultFile, "r")
    if not file then
        error("Unable to open auxiliary code file.")
        return {}
    end

    local auxCodes = {}
    local mixedCodes= {}  --{音码:{可匹配的辅码集}}
    for line in file:lines() do
        line = line:match("[^\r\n]+") -- 去掉換行符，不然 value 是帶著 \n 的
        -- local key, value = line:match("([^=]+)=(.+)") -- 分割 = 左右的變數
        local zi,yb,fu = string.match(line,"([^\t]+)\t([^\t]+)\t([^\t]+)")
        -- local key = zi
        -- local value = xk
        -- log.info(key,value)
        local fuset = two_char_combinations(fu)
        if zi and fu and yb then
            -- auxCodes 的逻辑不变
            auxCodes[zi] = auxCodes[fu] or {}
            table.insert(auxCodes[zi], fu)
            --加入mixedcodes的逻辑  这里只考虑到音码是两位,且完整辅码是两位
            mixedCodes[yb] = mixedCodes[yb] or {}
            for k,v in ipairs(fuset) do
                mixedCodes[yb][v] = true
            end

        end
    end
    AuxFilter.aux_code = auxCodes
    AuxFilter.comb_code = mixedCodes
    file:close()
    return auxCodes
end


-- 定义一个函数来读取音形混合体文件并返回内容
function AuxFilter.read_ybxkcomb_File(fileName)
    local userPath = rime_api.get_user_data_dir() .. "/lua/"
    local fileAbsolutePath = userPath .. fileName.. ".txt"
    local file = io.open(fileAbsolutePath ,"r")  -- 打开文件
    if not file then
        return nil
    end

    local result = {}
    for line in file:lines() do
        local key = string.sub(line, 1, 2)
        local value = string.sub(line,3,-1)
        result[key] = result[key] or {}
        for i=1,#value do
            v = value:sub(i,i)
            result[key][v]=true
            
        end
        result[key][value] = true
        result[key][value:reverse()] = true
       
    end

    file:close()
    return result
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


-- 定义函数来获取表的所有值
function table_values(tbl)
    local values = {}
    for _, value in pairs(tbl) do
        table.insert(values, value)
    end
    return values
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
    for _, codePoint in utf8.codes(word) do
        local char = utf8.char(codePoint)
        local charAuxCodes = AuxFilter.aux_code[char] -- 每個字的輔助碼組
        if charAuxCodes then -- 輔助碼存在
            for _, code in ipairs(charAuxCodes) do
                for i = 1, #code do
                    fullAuxCodes[i] = fullAuxCodes[i] or {}
                    -- fullAuxCodes[i][code:sub(i, i)] = true
                    table.insert(fullAuxCodes[i],code:sub(i,i))
                end
            end
        end
    end

    -- 將表格轉換為字符串
    for i, chars in pairs(fullAuxCodes) do
        fullAuxCodes[i] = table.concat(table_values(chars), "")
    end
    return fullAuxCodes
end

-- 定义函数来将字符串两两分割
local function splitToPairs(str)
    local result = {}
    for i = 1, #str, 2 do
        local pair = str:sub(i, i+1) -- 取出两个字符
        table.insert(result, pair)   -- 将两个字符插入到结果表中
    end
    return result
end

-----------------------------------------------
-- 判斷 auxStr 是否匹配 fullAux  --修改为了宽松匹配
-----------------------------------------------
function AuxFilter.match(fullAux, auxStr)
    if #fullAux == 0 then
        return false
    end
    

    local firstKeyMatched = fullAux[1]:find(auxStr:sub(1, 1)) ~= nil
    local secondKeymatched = fullAux[2]:find(auxStr:sub(1, 1)) ~= nil
    -- 如果辅助码只有一个键，且第一个键匹配两辅码中任意一个，则返回 true
    if #auxStr == 1 then
        return firstKeyMatched or secondKeymatched
    end
    -- 宽松模式下如果辅助码有两个或以上,有效组合的排列都有效  严格模式下 顺序一致有效
    local fiestKeymatched = fullAux[1]:find(auxStr:sub(2, 2)) ~= nil
    local secondKeyMatched = fullAux[2] and fullAux[2]:find(auxStr:sub(2, 2)) ~= nil
    local vgpipw = firstKeyMatched and secondKeyMatched
    local fjpipw = secondKeymatched and fiestKeymatched
    if AuxFilter.matchmode==1 then
        return vgpipw
    end
    return vgpipw or fjpipw
end
-- 返回指定长度的候选
function AuxFilter.candisub(cand,len)
    local candset = utf8sub(cand.text,1,len)
    local _end = 2*len
    local fiend = cand._start+_end
    if fiend>cand._end then
        fiend = cand._end
    end
    local finalcandi = Candidate(cand.type,cand._start,fiend,candset,cand.comment)
    -- log.info(Candi)
    return finalcandi

end

-- 辅码与音码匹配与否
local function combmath(aux,tab)
    local mark = true --;;这种空辅码也返回true也就是断在头部
    if AuxFilter.matchmode ==0 then
        --宽匹配下无关辅码顺序
        if #aux~=0 then
            if not (tab[aux] or tab[aux:reverse()]) then --
                mark = false
                -- log.info(aux,tab[aux],tab[aux:reverse()],table.concat(table_keys(tab),"-"))
            end
        end
    elseif AuxFilter.matchmode==1 then
        if #aux~=0 then
            if not tab[aux] then
                mark = false
            end
        end
    end


    -- log.info(aux,mark)
return mark
end

--- 分支一 原来的功能
function AuxFilter.main1(input,env)
    env.notifiermark = 1  --辅筛情况下的 选词后的逻辑标记 变为 1
    local context = env.engine.context
    local inputCode = context.input

    -- 分割部分正式開始
    local auxStr = ''
    local funccode = ""
    local trigger_pattern = AuxFilter.trigger_key:gsub("%W", "%%%1") -- 處理特殊字符
    local localSplit = inputCode:match(trigger_pattern .. "([^"..AuxFilter.trigger_key.."]+)")
    if localSplit then
        auxStr = string.sub(localSplit, 1, 2)
        funccode = string.gsub(localSplit,auxStr,"",1) 
    --[[
    除去两位辅码剩余的判定为功能码
    为什么这里也要引入偏移量?
    因为有时筛出的词长度长,第一页内有包含目的词的词,通过功能码可以上修改候选长度.
]]

    end
    local leftcompen = countSubstringOccurrences(funccode,"a") + 2* countSubstringOccurrences(funccode,"s") --左偏移量 
    local rightcompen = countSubstringOccurrences(funccode,"d") + 2 * countSubstringOccurrences(funccode,"f") -- 右偏移量
    -- 更新逻辑：没有匹配上就不出现再候选框里，提升性能
    -- local insertLater = {}

    -- 遍歷每一個待選項
    local counter = 0 -- 计数返回候选数量
    local firstcandi = ""      -- 第一个候选也就是最长的那个
    local index=0  --为了获取第一个候选的判断变量
    for cand in input:iter() do
        local compensate = utf8len(cand.text)  
        local ficompensate = compensate- leftcompen + rightcompen
        if ficompensate<=0 then
            ficompensate = 1
        end
        -- log.info(cand.text,ficompensate)
        index = index+1
        --第一个候选词 额外逻辑
        if index==1 then
            firstcandi = cand
        end

        
        local auxCodes = AuxFilter.aux_code[cand.text] -- 僅單字非 nil
        local fullAuxCodes = AuxFilter.fullAux(env, cand.text)

        -- 查看 auxCodes
        -- log.info(cand.text, #auxCodes)
        -- for i, cl in ipairs(auxCodes) do
        --     log.info(i, table.concat(cl, ',', 1, #cl))
        -- end

        -- 給待選項加上輔助碼提示
        if AuxFilter.show_aux_notice and auxCodes and #auxCodes > 0 then
            local codeComment = table.concat(auxCodes, ',')
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
            counter=counter+1
            yield(AuxFilter.candisub(cand,ficompensate))
        elseif #auxStr > 0 and fullAuxCodes and (cand.type == 'user_phrase' or cand.type == 'phrase') and
            AuxFilter.match(fullAuxCodes, auxStr) then
            -- 匹配到辅助码的待选项，直接插入到候选框中( 获得靠前的位置 )
            counter = counter+1
            yield(AuxFilter.candisub(cand,ficompensate))
        else
            -- 待选项字词 没有 匹配到当前的辅助码，插入到列表中，最后插入到候选框里( 获得靠后的位置 )
            -- table.insert(insertLater, cand)
            -- 更新逻辑：没有匹配上就不出现再候选框里，提升性能
        end
    end
    --如果辅筛没筛出来,提示你进行辅断
    if counter==0 then
        local removeAuxInput = context:get_preedit().text:match("(%a+)" .. AuxFilter.trigger_key.."-") --
        local inputspls  = splitToPairs(removeAuxInput) --未翻译的音码集合
        -- log.info("inputls")
        local matchybtab = {} --辅码可以组合的未翻译的音码的集合
        local firstcandtext = firstcandi.text
        -- log.info(auxStr)
        for index, value in ipairs(inputspls) do
            -- log.info(index,value)
            local auxtab = AuxFilter.comb_code[value]
            if combmath(auxStr,auxtab) then
                table.insert(matchybtab,tostring(index).."." .. utf8sub(firstcandtext,index,index))
            end
        end
        -- log.info(111)
        local commentfirst =  "无匹配"
        if #matchybtab~=0 then
            commentfirst = table.concat(matchybtab,"--")
        end
            -- log.info(firstcandi.text)
        firstcandi.comment = commentfirst
        -- log.info(firstcandi.text)
        -- log.info("comment" ,commentfirst)
        yield(firstcandi)
    end
end



--- 无触发分支
function AuxFilter.defaultmain(input)
    -- log.info(1)
    for cand in input:iter() do
        yield(cand)
    end
    
end



--- 句子修改分支
function AuxFilter.longcandimodify(input,env)
    local branchmark = 1 --在句子修改分支中的分支  1-断句分支  2-修音分支
    env.notifiermark = 2  --断句情况下的 选词后的逻辑标记 变为 2
    ---获取第一个候选也就是最长的那个,,怎么简单的获取,
    local firstcandi = ""
    for cand in input:iter() do
        firstcandi = cand
        break
    end
    local context = env.engine.context
    local inputCode0 = context.input:match("(%a+)" .. AuxFilter.trigger_key.."-")  --纯输入引导键前的部分
    local inputCode = context:get_preedit().text  
    -- log.info("inputcode",inputCode) 
    -- log.info(inputCode)
    local removeAuxInput = inputCode:match("(%a+)" .. AuxFilter.trigger_key.."-")  --翻译过后引导键前的未翻译部分  
    local transdcode = string.gsub(inputCode0,removeAuxInput,"")  --已翻译部分
    -- log.info("转换了的音码",transdcode)
    -- log.info("removeauxinput",removeAuxInput)
    local auxcode = inputCode:match(AuxFilter.trigger_key .. "(%a*)" .. AuxFilter.trigger_key) --辅码部分
    -- log.info("auxcode",auxcode)
    local funccode = inputCode:match(AuxFilter.trigger_key .. "%a*" .. AuxFilter.trigger_key .. "+(%a*)") --功能码部分
    -- log.info("fucncode",funccode)
    local ybmodif = funccode:match("s(%a%a)") --功能码部分捕获的修音的音码
    if ybmodif then 
        --进入修音分支处理
        branchmark=2
        funccode = string.gsub(funccode,"s" .. ybmodif,"") --减掉修音部分的功能码,为后续统计偏移做准备
    end
    -- log.info("音码",ybmodif)
    -- log.info("funccode",funccode)
    local leftcompen = countSubstringOccurrences(funccode,"a") --左偏移量
    local rightcompen = countSubstringOccurrences(funccode,"d") + 2 * countSubstringOccurrences(funccode,"f") -- 右偏移量
    local inputspls  = splitToPairs(removeAuxInput) --把未翻译的音码拆成单字音码列表  {音码1,音码2}
    local compensate = utf8len(firstcandi.text) --初始化偏移量  默认在断点尾部
    local passnum = countSubstringOccurrences(inputCode,AuxFilter.trigger_key) -2  --计算跳过匹配数  功能码中 ; 的作用
    -- log.info(inputspls[1])
    --确定最终断点位置
    local matchedmark = false  --整句辅码是否有有效配对
    for index, value in ipairs(inputspls) do
        local auxtab = AuxFilter.comb_code[value]
        if combmath(auxcode,auxtab) then
            compensate = index
            matchedmark= true
            if passnum==0 then
            break
            end
            passnum=passnum-1

        end
    end
    -- if compensate<=0 then
    --     compensate=1
    -- end
    compensate = compensate + rightcompen - leftcompen
    if matchedmark then
       compensate = compensate -1  --减1是要断在作用词之前  
    end
  
    --如果前面没字就上一个
    if compensate<=0 then
        compensate =1
    end

    --在断点处修音逻辑
    if branchmark==2 then
        env.notifiermark = 3 --修音模式下,选词后的逻辑的标志变为3
        local wrongyb = inputspls[compensate]
        inputspls[compensate] = ybmodif
        local inputcode2 = table.concat(inputspls,"")  --修改后的未翻译音码连接为字符串
        -- log.info(inputcode2)
        AuxFilter.ybmodifiedcode = transdcode .. inputcode2 .. AuxFilter.trigger_key  --修改后的音码 + 引导键
        yield(Candidate(firstcandi.type,firstcandi._start,firstcandi._start,"",wrongyb .."->" .. ybmodif))  --"确定"  候选项
    
    --在断点处断句逻辑
    elseif branchmark==1 then
        local comment = ""
    -- compensate = compensate+trigger_key_n-1
    -- local compensate = utf8len(firstcandi.text) - trigger_key_n + 1
    local finalcandi = AuxFilter.candisub(firstcandi,compensate)
    if not matchedmark then
        comment = "辅码无匹配"
    end
    finalcandi.comment = comment
    yield(finalcandi)
    end


    
end
------------------
-- filter 主函數 --
------------------
function AuxFilter.func(input, env)
    -- log.info("func")
    local context = env.engine.context
    local inputCode = context.input

    -- 分割部分正式開始
    local pattern_main1 = "^%a+" .. AuxFilter.trigger_key ..'%a*$'  --辅筛分支的正则
    local pattern_long = "^%a+" .. AuxFilter.trigger_key .. "%a*" .. AuxFilter.trigger_key .."+%a*$" --长句修改分支的正则
    if string.match(inputCode,pattern_main1)then
        AuxFilter.main1(input,env)
    elseif string.match(inputCode,pattern_long) then
        AuxFilter.longcandimodify(input,env)     
    --都不匹配直接返回的分支
    else
        AuxFilter.defaultmain(input)
        end
end

function AuxFilter.fini(env)
    -- log.info("fini")
        env.notifier:disconnect()

    

end

return AuxFilter
