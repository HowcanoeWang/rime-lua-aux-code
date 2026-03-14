# 词组按字位匹配与命中提示 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在保留现有词语级召回能力的前提下，改为“按字位精确匹配（禁止跨字混拼）”，并在词组候选中显示命中字提示（如 `椰子蟹(蟹:ij)`）。

**Architecture:** 在 `lua/aux_code.lua` 中引入辅码索引预处理，将逐候选字符串扫描改为哈希查询；匹配阶段对词组逐字位从左到右短路匹配，返回首个命中位置；输出阶段采用双层分桶（首字命中优先）稳定排序。注释展示层仅对词组追加命中提示，单字维持原有“显示该字所有辅码”。

**Tech Stack:** Rime Lua filter (`lua_filter`), librime-lua Candidate API (`Candidate`, `ShadowCandidate`), Lua 5.4 syntax check (`luac`).

---

### Task 1: 建立高效辅码索引（一次预处理，多次 O(1) 查询）

**Files:**
- Modify: `lua/aux_code.lua`

**Step 1: 写失败前置说明（行为基线）**

在辅助函数区域添加简短注释，明确当前问题：
- 现有 `unique + in` 无法定位命中字位。
- 现有 `unique + in` 可能发生跨字混拼命中。

**Step 2: 实现索引构建函数**

新增函数（可拆分为多个 <50 行函数）：

```lua
local function build_char_aux_index(aux_code)
    -- 返回:
    -- index[char].k1[first_key] = true
    -- index[char].k12[two_key_token] = true
end
```

规则：
- 遍历每个字的辅码 token（空格分隔）。
- token 长度 >= 1 时写入 `k1`。
- token 长度 >= 2 时写入 `k12`（仅前两键）。

**Step 3: 在 init 阶段挂载索引**

在 `AuxFilter.init` 成功读取码表后构建：

```lua
AuxFilter.aux_index = build_char_aux_index(AuxFilter.aux_code)
```

读取失败时设置空索引，避免 nil 分支散落。

**Step 4: 语法验证**

Run: `luac -p lua/aux_code.lua`
Expected: PASS。

---

### Task 2: 实现按字位匹配核心（禁止跨字混拼）

**Files:**
- Modify: `lua/aux_code.lua`

**Step 1: 新增单字匹配函数**

```lua
local function char_matches_aux(char, aux_str)
    -- 1 键查 k1, 2 键查 k12
end
```

规则：
- `aux_str == ""` 返回 `false`。
- `#aux_str == 1`：`k1[aux_str]`。
- `#aux_str >= 2`：`k12[aux_str:sub(1,2)]`。

**Step 2: 新增词组定位函数**

```lua
local function find_phrase_match(word, aux_str)
    -- 从左到右逐字匹配，命中即短路
    -- return { pos = n, char = "字" } or nil
end
```

要求：
- 只能由同一字完成匹配，天然禁止“第1字+第3字”混拼。
- 返回首个命中字位，便于排序与提示。

**Step 3: 移除旧 fullAux 函数用途**

不保留召回兼容逻辑。

**Step 4: 语法验证**

Run: `luac -p lua/aux_code.lua`
Expected: PASS。

---

### Task 3: 改造过滤流程为双层分桶（首字优先）

**Files:**
- Modify: `lua/aux_code.lua`

**Step 1: 构建单次遍历分桶流程**

在 `AuxFilter.func` 的 `#auxStr > 0` 分支内：
- `tier_first_char = {}`（`pos == 1`）
- `tier_non_first = {}`（`pos > 1`）

每个候选只计算一次 `find_phrase_match(cand.text, auxStr)`。

**Step 2: 保持类型范围与快路径**

仅对 `user_phrase|phrase|simplified` 做词组匹配。
保留：
- `mode == "none"` 快路径
- 缺码表提示路径
- `#auxStr == 0` 路径

**Step 3: 统一输出与去重**

先输出 `tier_first_char`，再输出 `tier_non_first`；
使用 `seen` 去重键（`type/start/end/text`）避免重复。

**Step 4: no-learn 行为不回归**

在最终 `yield` 前统一走：

```lua
if mode == "no_learn" then
    yield(to_commit_only_candidate(cand))
else
    yield(cand)
end
```

**Step 5: 语法验证**

Run: `luac -p lua/aux_code.lua`
Expected: PASS。

---

### Task 4: 词组显示命中提示 `(蟹:ij)`，单字保持原注释

**Files:**
- Modify: `lua/aux_code.lua`

**Step 1: 新增注释拼接函数**

```lua
local function append_phrase_match_hint(cand, matched_char, aux_str)
    -- 输出格式: (蟹:ij)
end
```

要求：
- 仅在词组候选命中时追加。
- 不覆盖已有注释，采用 merge 方式拼接。
- 兼容 `ShadowCandidate`。

**Step 2: 单字注释逻辑保持不变**

当前单字显示“全部辅码”的逻辑不改：
- `auxCodes:gsub(' ', ',')` 的输出继续保留。

**Step 3: 在词组命中入桶前注入提示**

当 `find_phrase_match` 返回 `{pos, char}` 时，为该 cand 追加 `(char:auxStr)` 提示后再入桶。

**Step 4: 语法验证**

Run: `luac -p lua/aux_code.lua`
Expected: PASS。

---

### Task 5: README 更新与回归验证

**Files:**
- Modify: `README.md`

**Step 1: 更新匹配规则说明**

补充三点：
- 按字位精确匹配（不跨字混拼）。
- 排序为“首字命中优先”。
- 词组候选会显示命中提示 `(命中字:输入辅码)`。

**Step 2: 添加示例说明**

示例：
- 输入：`ye zi xie` + `ij`
- 候选注释：`椰子蟹(蟹:ij)`

**Step 3: 最终验证命令**

Run:

```bash
luac -p lua/aux_code.lua
git diff -- lua/aux_code.lua README.md
```

Expected:
- Lua 语法通过
- diff 仅包含本次需求相关改动

**Step 4: 手工回归清单**

- 词组命中：显示 `(蟹:ij)`。
- 单字候选：仍显示该字所有辅码。
- 首字命中优先于非首字命中。
- 不出现跨字混拼误命中。
- `no_learn` 与 `learn` 触发键行为保持既有语义。
