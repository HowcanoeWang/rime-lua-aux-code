# Aux Code Dual Trigger No-Learn Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add dual auxiliary-code triggers so users can choose per input whether committed text should be learned by user dictionary (`learn_trigger`) or commit-only (`no_learn_trigger`).

**Architecture:** Keep current aux filtering pipeline in `lua/aux_code.lua`, then branch behavior by parsed trigger mode. In `no_learn` mode, yield rebuilt plain `Candidate` objects to detach from memorize path; in `learn` mode, keep original candidate objects. Parse triggers with longest-match priority so `;;` and `;` can coexist safely.

**Tech Stack:** Rime Lua filter (`lua_filter`), librime-lua candidate APIs (`Candidate`, `ShadowCandidate`), schema YAML configuration, README docs.

---

### Task 1: Add Config Model for Dual Triggers

**Files:**
- Modify: `lua/aux_code.lua`
- Modify: `README.md`

**Step 1: Define new config keys and fallback rules**

Add in `AuxFilter.init(env)`:

```lua
env.learn_trigger = config:get_string("key_binder/aux_code_learn_trigger")
    or config:get_string("key_binder/aux_code_trigger")
    or ";"
env.no_learn_trigger = config:get_string("key_binder/aux_code_no_learn_trigger")
    or ""
```

Rules:
- `learn_trigger` must always exist (fallback to old key then `;`).
- `no_learn_trigger` empty means feature disabled (per user decision #1).
- if two triggers are identical, disable `no_learn_trigger` and keep `learn_trigger`.

**Step 2: Add trigger ordering metadata**

Create a small ordered list in init:

```lua
env.triggers = {
    { mode = "no_learn", token = env.no_learn_trigger },
    { mode = "learn", token = env.learn_trigger },
}
```

Filter out empty tokens and sort by descending token length to guarantee longest-match priority.

**Step 3: Document config in README**

Add a section with examples:

```yaml
key_binder/+:
  aux_code_learn_trigger: ";"
  aux_code_no_learn_trigger: ";;"
```

State behavior clearly:
- `;` = normal aux filtering + learn
- `;;` = aux filtering + no learn
- if `aux_code_no_learn_trigger` is missing/empty, only normal learn mode is active

**Step 4: Verification**

Run a syntax check command (if available locally):
- `luac -p lua/aux_code.lua`

Expected: no syntax errors.

---

### Task 2: Isolate Parsing Logic (Mode + Aux Payload)

**Files:**
- Modify: `lua/aux_code.lua`

**Step 1: Create parser helper with guard clauses**

Add a local helper:

```lua
local function parse_aux_input(input_code, env)
    -- returns mode("none"|"learn"|"no_learn"), aux_str, trigger_token
end
```

Behavior:
- iterate ordered `env.triggers`
- detect first matching token occurrence
- extract suffix after trigger until delimiter boundary (existing code uses `,`)
- keep first 2 aux chars (`string.sub(local_split, 1, 2)`) for compatibility
- return `"none"` when no trigger matched

**Step 2: Replace inline parsing in filter**

In `AuxFilter.func`, replace current `env.trigger_key` parsing with:

```lua
local mode, aux_str, token = parse_aux_input(context.input, env)
```

**Step 3: Keep existing performance behavior for non-aux path**

If `mode == "none"`, preserve current fast path (direct yield without extra logic).

**Step 4: Verification**

Manual check in Rime:
- input without trigger still shows same candidates and performance
- both `;` and `;;` can enter aux filtering

---

### Task 3: Implement No-Learn Candidate Rebuild Path

**Files:**
- Modify: `lua/aux_code.lua`

**Step 1: Add candidate clone helper**

Create helper:

```lua
local function to_commit_only_candidate(cand)
    local rebuilt = Candidate(cand.type, cand.start, cand._end, cand.text, cand.comment)
    rebuilt.preedit = cand.preedit
    rebuilt.quality = cand.quality
    return rebuilt
end
```

Goal: return a detached candidate object, not the original phrase-backed candidate.

**Step 2: Preserve ShadowCandidate comment behavior before rebuild**

Keep existing simplifier branch:
- apply aux notice comment formatting first
- then if mode is `no_learn`, rebuild from final display candidate text/comment

**Step 3: Branch yield behavior by mode**

In matched-candidate branch:

```lua
if mode == "no_learn" then
    yield(to_commit_only_candidate(cand))
else
    yield(cand)
end
```

Do not change matching condition semantics (`phrase`, `user_phrase`, `simplified` etc.) unless a bug is confirmed.

**Step 4: Verification**

Manual behavior checks:
- same input + `;` multiple times: ranking can learn as before
- same input + `;;` multiple times: ranking should not drift from those commits

---

### Task 4: Update Select Notifier for Dual Trigger Preservation

**Files:**
- Modify: `lua/aux_code.lua`

**Step 1: Parse current context input with shared parser**

Inside `select_notifier` callback, replace hardcoded `env.trigger_key` checks with `parse_aux_input(ctx.input, env)`.

**Step 2: Preserve correct trigger token during split selection**

When reassembling `ctx.input` after partial commit:
- append the same matched trigger token (e.g., keep `;;`, not collapse to `;`)
- if final segment has no remaining letters, do `ctx:commit()` unchanged

**Step 3: Maintain backward behavior**

If no trigger detected, return early exactly as now.

**Step 4: Verification**

Manual flow test:
- type multi-syllable code + `;;` + aux
- select first segment and continue selection
- confirm trigger remains `;;` through partial commits

---

### Task 5: Edge Cases, Safety, and Docs Finalization

**Files:**
- Modify: `lua/aux_code.lua`
- Modify: `README.md`

**Step 1: Add edge-case guards**

Handle:
- empty `no_learn_trigger`
- trigger collision (`learn == no_learn`)
- prefix overlap (enforced by longest-match parse)

Optional lightweight logging hooks can remain commented out like current style.

**Step 2: Add user-facing behavior matrix to README**

Document table:
- trigger token
- filtering active?
- user dict memorize?

Also include migration note from old `aux_code_trigger` key.

**Step 3: Run final checks**

Commands:
- `luac -p lua/aux_code.lua`
- (if repo has tests later) `uv run pytest`

Expected:
- syntax check passes
- no regressions in manual input behavior

---

### Task 6: Commit Plan (Implementation Session)

**Files:**
- Modify: `lua/aux_code.lua`
- Modify: `README.md`

**Step 1: Stage files**

Run:

```bash
git add lua/aux_code.lua README.md
```

**Step 2: Commit with conventional format**

Run:

```bash
git commit -m "feat(aux): add dual trigger learn/no-learn aux mode" \
  -m "- add configurable learn and no-learn triggers" \
  -m "- route no-learn mode through rebuilt commit-only candidates" \
  -m "- document behavior and configuration in README"
```

**Step 3: Post-commit check**

Run:

```bash
git status
```

Expected: clean working tree or only unrelated pre-existing changes.
