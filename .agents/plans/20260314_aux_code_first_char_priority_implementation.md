# Aux Code First-Char Priority Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep existing fullAux in-unique matching for phrase-level auxiliary-code filtering, while prioritizing candidates whose first character exactly matches current aux input.

**Architecture:** Extend `lua/aux_code.lua` with a first-character exact matcher and a two-bucket output pipeline. During aux filtering, collect candidates into `first_exact_bucket` and `full_aux_bucket`, then yield first-exact candidates first and phrase-level matches second, with stable original order inside each bucket and de-duplication between buckets.

**Tech Stack:** Rime Lua filter (`lua_filter`), librime-lua candidate APIs (`Candidate`, `ShadowCandidate`), Lua 5.4 syntax validation (`luac`).

---

### Task 1: Add First-Character Exact Match Helper

**Files:**
- Modify: `lua/aux_code.lua`

**Step 1: Write the failing behavior note as executable checklist**

Add temporary local checks (comment block near helper section) to define expected behavior:

```lua
-- expected:
-- 1) auxStr="dj" and first char has code "dj" => true
-- 2) auxStr="dj" and only fullAux contains d/j from later chars => false
-- 3) auxStr="d" and first char has any code starting with d => true
```

Expected: current codebase has no helper to express this rule directly.

**Step 2: Implement minimal helper**

Add helper near `AuxFilter.match`:

```lua
local function first_char_exact_match(aux_code_map, word, aux_str)
    -- uses first UTF-8 char only
    -- checks first char's own codes, not aggregated fullAux
end
```

Rules:
- Empty `aux_str` => `false` (filter logic handles empty separately).
- If word has no first char aux mapping => `false`.
- For 1-key aux: first key match is enough.
- For 2-key aux: both keys in same code token must match (`code:sub(1, 2) == aux_str`).

**Step 3: Syntax-check helper addition**

Run: `luac -p lua/aux_code.lua`
Expected: pass.

**Step 4: Commit checkpoint (implementation session)**

```bash
git add lua/aux_code.lua
git commit -m "feat(aux): add first-char exact match helper" -m "- define first-character-only aux matching for ranking tier"
```

---

### Task 2: Split Filtering Into Two Stable Buckets

**Files:**
- Modify: `lua/aux_code.lua`

**Step 1: Write failing test scenario checklist**

Document expected ordering in code comments near filter branch:

```lua
-- input aux="dj"
-- first-char exact matches should appear before pure fullAux matches
-- relative order inside each bucket remains original iterator order
```

Expected: current implementation yields on first match and cannot reorder by tier.

**Step 2: Implement minimal two-bucket pipeline**

Inside `AuxFilter.func` aux branch (`#auxStr > 0`):
- Create `local first_exact_bucket = {}`
- Create `local full_aux_bucket = {}`
- Create `local seen = {}` for dedupe by key (`cand.text .. "\t" .. cand.start .. "\t" .. cand._end`).

For each candidate:
- Keep existing aux comment decoration behavior unchanged.
- If first-char exact matches => push to `first_exact_bucket`.
- Else if existing `AuxFilter.match(fullAuxCodes, auxStr)` true => push to `full_aux_bucket`.
- Else skip (keep current strict filtering behavior).

**Step 3: Yield buckets in order**

After iteration:

```lua
for _, cand in ipairs(first_exact_bucket) do yield(...) end
for _, cand in ipairs(full_aux_bucket) do yield(...) end
```

Apply existing `mode == "no_learn"` conversion at yield point to preserve current no-learn behavior.

**Step 4: Syntax check**

Run: `luac -p lua/aux_code.lua`
Expected: pass.

**Step 5: Commit checkpoint (implementation session)**

```bash
git add lua/aux_code.lua
git commit -m "feat(aux): prioritize first-char exact matches" -m "- add two-tier bucket output for aux filtering" -m "- keep fullAux phrase matching as fallback tier"
```

---

### Task 3: Preserve Existing Mode Semantics and Candidate Decoration

**Files:**
- Modify: `lua/aux_code.lua`

**Step 1: Guard existing behavior with explicit checks**

Ensure unchanged behavior for:
- `mode == "none"`: immediate passthrough (performance path).
- `#auxStr == 0`: no filtering, direct yield.
- missing aux dictionary: existing hint flow unchanged.

**Step 2: Keep simplifier/shadow comment compatibility**

Verify current block for `cand:get_dynamic_type() == "Shadow"` still runs before bucket insertion so display comments stay correct in both tiers.

**Step 3: Validate no-learn in both tiers**

At final yield stage, apply:

```lua
if mode == "no_learn" then
    yield(to_commit_only_candidate(cand))
else
    yield(cand)
end
```

for both tier loops.

**Step 4: Syntax check**

Run: `luac -p lua/aux_code.lua`
Expected: pass.

**Step 5: Commit checkpoint (implementation session)**

```bash
git add lua/aux_code.lua
git commit -m "refactor(aux): preserve no-learn and shadow behavior in tiered output" -m "- keep existing passthrough and missing-dict logic unchanged"
```

---

### Task 4: Add User-Facing Behavior Notes

**Files:**
- Modify: `README.md`

**Step 1: Write the new ordering rule section**

Add a concise section describing:
- current segment first-character definition (not previously committed text)
- tier rule: first-char exact > fullAux in-unique
- no trigger changes required

Example text:

```markdown
当输入辅码后，候选排序采用双层策略：
1. 候选首字完整匹配当前辅码（优先）
2. 候选任意字命中词语级 fullAux 聚合（次级）

说明："首字"指当前候选词条的第一个字（当前正在选词的 segment），不包含已上屏的前文。
```

**Step 2: Sanity check formatting**

Run: `git diff -- README.md`
Expected: section is clear and does not conflict with existing trigger docs.

**Step 3: Commit checkpoint (implementation session)**

```bash
git add README.md
git commit -m "docs(readme): document first-char-priority aux ranking" -m "- clarify current-segment first-character definition"
```

---

### Task 5: Final Verification and Integration Commit

**Files:**
- Modify: `lua/aux_code.lua`
- Modify: `README.md`

**Step 1: Run verification commands**

Run:

```bash
luac -p lua/aux_code.lua
```

If Python tests exist in future, run:

```bash
uv run pytest
```

Expected:
- Lua syntax passes.
- Tests pass or no relevant tests collected.

**Step 2: Manual behavior verification checklist**

Validate in Rime:
- Aux trigger active with 1-key and 2-key input.
- Case A: first-char exact candidates appear before long phrase fullAux-only matches.
- Case B: fullAux-only candidates still appear (compatibility retained).
- Case C: already committed prefix text does not affect “首字优先” target segment.

**Step 3: Final commit (if checkpoints were skipped)**

```bash
git add lua/aux_code.lua README.md
git commit -m "feat(aux): add first-char priority while preserving phrase-level matching" \
  -m "- rank first-character exact aux matches ahead of fullAux in-unique matches" \
  -m "- keep no-learn mode and candidate comment behavior intact" \
  -m "- document current-segment first-character rule"
```

**Step 4: Post-commit status**

Run: `git status`
Expected: clean tree or only unrelated pre-existing changes.
