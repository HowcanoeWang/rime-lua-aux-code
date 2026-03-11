# Aux Code Strict Dict Directory Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Force auxiliary dictionaries to load only from `config/rime/aux_code/` (user data dir `aux_code/`), disable aux behavior safely when dictionary is missing, and show a clear candidate hint on trigger-without-aux input.

**Architecture:** Keep all behavior in `lua/aux_code.lua`. Replace current multi-path + fallback loader with a strict resolver: `<user_data_dir>/aux_code/<namespace>.txt` only. On load failure, switch filter into a soft-disabled state (`aux_ready=false`) so normal input stays stable, and inject one user-facing message into the first candidate comment only when trigger is present and aux letters are still empty.

**Tech Stack:** Rime Lua filter (`lua_filter`), librime-lua candidate API (`Candidate`, `ShadowCandidate`), Lua pattern parsing, README configuration docs.

---

### Task 1: Introduce Strict Dictionary Path Resolution

**Files:**
- Modify: `lua/aux_code.lua`
- Test: `tests/aux_code_dict_path_test.lua`

**Step 1: Write the failing test**

Create `tests/aux_code_dict_path_test.lua` with a pure-path expectation:

```lua
package.path = "./lua/?.lua;" .. package.path

rime_api = {
    get_user_data_dir = function()
        return "/tmp/rime"
    end,
}

local aux = require("aux_code")
local path = aux._build_aux_dict_path("ZRM_Aux-code_4.3")
assert(path == "/tmp/rime/aux_code/ZRM_Aux-code_4.3.txt")
```

**Step 2: Run test to verify it fails**

Run: `lua tests/aux_code_dict_path_test.lua`
Expected: FAIL because `_build_aux_dict_path` does not exist yet.

**Step 3: Write minimal implementation**

Add helper in `lua/aux_code.lua` and expose for test use:

```lua
function AuxFilter._build_aux_dict_path(namespace)
    local user_dir = rime_api.get_user_data_dir()
    return user_dir .. "/aux_code/" .. namespace .. ".txt"
end
```

Update `readAuxTxt` to only call `io.open` on this strict path, with no fallback path.

**Step 4: Run test to verify it passes**

Run: `lua tests/aux_code_dict_path_test.lua`
Expected: PASS.

**Step 5: Commit**

```bash
git add lua/aux_code.lua tests/aux_code_dict_path_test.lua
git commit -m "refactor(aux): enforce strict aux_code dictionary directory" \
  -m "- resolve dictionary path only from user_data_dir/aux_code" \
  -m "- remove lua directory fallback behavior"
```

---

### Task 2: Add Soft-Disable Runtime State on Dictionary Load Failure

**Files:**
- Modify: `lua/aux_code.lua`
- Test: `tests/aux_code_load_failure_state_test.lua`

**Step 1: Write the failing test**

Create `tests/aux_code_load_failure_state_test.lua` to validate state contract:

```lua
package.path = "./lua/?.lua;" .. package.path

rime_api = {
    get_user_data_dir = function()
        return "/tmp/rime"
    end,
}

local aux = require("aux_code")
local state = aux._build_missing_dict_state("missing_file")
assert(state.aux_ready == false)
assert(state.missing_file == "missing_file.txt")
```

**Step 2: Run test to verify it fails**

Run: `lua tests/aux_code_load_failure_state_test.lua`
Expected: FAIL because helper/state contract does not exist yet.

**Step 3: Write minimal implementation**

In `AuxFilter.init(env)`:
- wrap dictionary load with `pcall`
- on success: `env.aux_ready = true`
- on failure: `env.aux_ready = false`, `env.aux_error_msg`, `env.aux_missing_file`
- never call `error()` for missing dictionary

Suggested message builder:

```lua
function AuxFilter._build_missing_dict_message(filename)
    return "config/rime/aux_code/ 中未找到辅码文件 " .. filename
end
```

**Step 4: Run tests to verify they pass**

Run:
- `lua tests/aux_code_dict_path_test.lua`
- `lua tests/aux_code_load_failure_state_test.lua`

Expected: PASS.

**Step 5: Commit**

```bash
git add lua/aux_code.lua tests/aux_code_load_failure_state_test.lua
git commit -m "feat(aux): add non-crashing missing-dictionary state" \
  -m "- keep input flow alive when aux dictionary cannot be loaded" \
  -m "- record structured missing-file status for UI hinting"
```

---

### Task 3: Inject Missing-File Hint into First Candidate on Trigger Entry

**Files:**
- Modify: `lua/aux_code.lua`
- Test: `tests/aux_code_missing_hint_test.lua`

**Step 1: Write the failing test**

Create test for message formatter and merge behavior:

```lua
package.path = "./lua/?.lua;" .. package.path
local aux = require("aux_code")

local msg = aux._build_missing_dict_message("ZRM_Aux-code_4.3.txt")
assert(msg == "config/rime/aux_code/ 中未找到辅码文件 ZRM_Aux-code_4.3.txt")

local merged = aux._merge_comment("orig", msg)
assert(merged == "orig | config/rime/aux_code/ 中未找到辅码文件 ZRM_Aux-code_4.3.txt")
```

**Step 2: Run test to verify it fails**

Run: `lua tests/aux_code_missing_hint_test.lua`
Expected: FAIL because helper(s) do not exist.

**Step 3: Write minimal implementation**

In filter loop:
- detect trigger mode via existing parser
- if `env.aux_ready == false` and `#auxStr == 0`, mark first yielded candidate
- append hint to candidate comment using helper `_merge_comment`
- keep candidate `text` unchanged

Implementation constraints:
- inject once per filter call
- support both normal candidates and `ShadowCandidate` path
- if no candidates exist, skip silently

**Step 4: Run test to verify it passes**

Run: `lua tests/aux_code_missing_hint_test.lua`
Expected: PASS.

**Step 5: Commit**

```bash
git add lua/aux_code.lua tests/aux_code_missing_hint_test.lua
git commit -m "feat(aux): show missing dictionary hint in first candidate" \
  -m "- append non-intrusive hint to first candidate comment" \
  -m "- trigger hint only at trigger-enter stage without aux letters"
```

---

### Task 4: Disable Aux Filtering Logic Entirely When Dictionary Is Missing

**Files:**
- Modify: `lua/aux_code.lua`

**Step 1: Write the failing test**

Add behavioral assertion in `tests/aux_code_missing_hint_test.lua`:

```lua
-- pseudo contract: when aux_ready=false and auxStr="ab"
-- filter does not call aux match path
-- and falls back to normal candidate yield order
assert(true)
```

(Use a small mocked iterator/candidate table to verify no `AuxFilter.match` dependency is invoked.)

**Step 2: Run test to verify it fails**

Run: `lua tests/aux_code_missing_hint_test.lua`
Expected: FAIL until soft-disabled branch is wired.

**Step 3: Write minimal implementation**

In `AuxFilter.func`:
- early branch for `env.aux_ready == false`
- if in trigger mode and `#auxStr == 0`: inject first-candidate hint then yield all
- otherwise: yield all candidates untouched
- skip aux notice/match/fullAux logic when not ready

**Step 4: Run tests to verify they pass**

Run:
- `lua tests/aux_code_dict_path_test.lua`
- `lua tests/aux_code_load_failure_state_test.lua`
- `lua tests/aux_code_missing_hint_test.lua`
- `luac -p lua/aux_code.lua`

Expected: all PASS, no Lua syntax error.

**Step 5: Commit**

```bash
git add lua/aux_code.lua tests/aux_code_missing_hint_test.lua
git commit -m "fix(aux): short-circuit aux pipeline when dictionary is unavailable" \
  -m "- keep plugin in safe disabled mode without crashes" \
  -m "- preserve normal candidate flow while aux is unavailable"
```

---

### Task 5: Update User Docs for New Mandatory Dictionary Location

**Files:**
- Modify: `README.md`

**Step 1: Write the failing doc check**

Define acceptance checks:
- README install tree must show `aux_code/` folder at root
- README must remove guidance that puts dictionary txt under `lua/`
- README must document missing-file hint text exactly

**Step 2: Run check and confirm failure**

Run: `rg "lua/.*\.txt|aux_code/" README.md`
Expected: old `lua/*.txt` instructions still present.

**Step 3: Write minimal documentation update**

Update installation section examples:

```text
(config_path)/
├─ lua/
│  ├─ aux_code.lua
│  └─ ...
├─ aux_code/
│  ├─ ZRM_Aux-code_4.3.txt
│  └─ flypy_full.txt
```

Add behavior note:
- dictionary is loaded only from `config/rime/aux_code/`
- if missing, candidate hint shows:
  `config/rime/aux_code/ 中未找到辅码文件 <文件名>.txt`

**Step 4: Run doc check to verify pass**

Run: `rg "config/rime/aux_code/ 中未找到辅码文件|├─ aux_code/" README.md`
Expected: both patterns found.

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs(aux): require dedicated aux_code dictionary directory" \
  -m "- switch installation guide from lua txt placement to aux_code folder" \
  -m "- document missing-dictionary candidate hint behavior"
```

---

### Task 6: Final Verification and Integration Commit

**Files:**
- Modify: `lua/aux_code.lua`
- Modify: `README.md`
- Create/Modify: `tests/aux_code_dict_path_test.lua`
- Create/Modify: `tests/aux_code_load_failure_state_test.lua`
- Create/Modify: `tests/aux_code_missing_hint_test.lua`

**Step 1: Run full verification**

Run:

```bash
lua tests/aux_code_dict_path_test.lua && \
lua tests/aux_code_load_failure_state_test.lua && \
lua tests/aux_code_missing_hint_test.lua && \
luac -p lua/aux_code.lua
```

Expected: no assertion failure, no syntax errors.

**Step 2: Manual runtime smoke check (Rime)**

Check in real input session:
- valid dictionary: `twtw;` enters aux flow normally
- missing dictionary: `twtw;` first candidate comment contains exact hint text
- missing dictionary: `twtw;ab` does not crash and does not perform aux filtering

**Step 3: Final commit**

```bash
git add lua/aux_code.lua README.md tests/*.lua
git commit -m "feat(aux): enforce strict aux_code dict directory with safe missing-file UX" \
  -m "- remove fallback dictionary paths and default-file fallback" \
  -m "- add non-crashing disabled mode and first-candidate missing-file hint" \
  -m "- update docs and add regression tests for strict path behavior"
```

**Step 4: Post-commit status check**

Run: `git status`
Expected: clean tree or only unrelated pre-existing changes.
