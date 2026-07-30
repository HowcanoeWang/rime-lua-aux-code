# Aux Code Updater Implementation Plan

Status: completed

## Goal

为桌面端 Rime 增加大陆友好的后台版本检查与可选自动更新能力。默认仅通知，不阻塞输入，不覆盖用户修改，不更新辅码码表。

## Decisions

- 运行时文件仅为 `lua/aux_code.lua` 和 `lua/aux_code_updater.lua`。
- `aux_code_updater.lua` 是普通 Lua 模块，由 `aux_code.lua` 通过 `pcall(require, ...)` 容错加载，不新增 Rime filter。
- 配置为 `aux_code/update_mode: off | notify | auto`，缺失或无效时默认 `notify`。
- 配置为 `aux_code/check_interval_days`，仅接受正整数，默认 `7` 天。
- 版本检查优先使用 npmmirror，失败后使用 npm 官方 Registry；运行时不依赖 GitHub 或 jsDelivr。
- npm 包仅发布两个 Lua 文件；首次安装及码表继续通过 GitHub 完成。
- npm `dist.integrity` 校验整个 tarball；`package.json` 的 `rimePlugin.files` 提供两个 Lua 文件的 SHA-512。
- `aux_code.lua` 暴露当前版本；更新器本身只保存包名、协议版本、Registry 等稳定逻辑。
- 自动更新前根据当前版本 npm 元数据校验本地两个 Lua 文件。任一文件被修改时降级为通知。
- 自动更新范围：`0.x` 只跨 patch；正式版不跨 major；不降级、不跟随预发布版本。
- 更新状态固定放在 `<user_data>/aux_code/.update/`。

## Persistent Layout

```text
aux_code/.update/
├── state.json
└── backup/
    ├── aux_code.lua
    └── aux_code_updater.lua
```

更新期间临时创建 `work/`，成功或失败后清理。`state.json` 合并检查时间、已安装元数据、通知状态和事务状态。

## Runtime Flow

1. `aux_code.lua` 初始化时读取配置并容错初始化 updater。
2. `off` 不联网，也不创建 `.update/`。
3. 检查到期后使用后台 `curl` 获取 dist-tags，不在输入线程等待网络。
4. `notify` 只比较版本并缓存通知，不下载 tarball。
5. `auto` 查询当前与目标版本元数据，校验本地修改和自动更新边界。
6. 后台下载 tarball，校验 `dist.integrity`，提取两个 Lua 文件并校验文件哈希。
7. 对新文件执行 `loadfile()`，通过后备份、写事务状态并替换。
8. 失败时恢复上一套备份；成功后提示重新部署。
9. 所有更新异常都不能中断现有辅码筛选。

## Permissions

- 只写 `rime_api.get_user_data_dir()`，绝不写 shared data dir。
- `notify` 检查 `.update/` 的创建、写入和改名能力。
- `auto` 额外检查用户 `lua/` 目录的写入和改名能力。
- 权限不足时 `notify` 静默停用；`auto` 降级并每进程最多提示一次。
- 最终替换使用目标 `lua/` 目录内的 `.new` 文件，避免跨文件系统 rename。

## Implementation Tasks

1. 新增 updater 模块及纯函数测试：配置、SemVer、元数据提取、状态、更新边界、通知。
2. 在 `aux_code.lua` 中加入版本、updater 生命周期和首候选通知接入。
3. 新增 npm 包元数据及发布前哈希生成/验证脚本。
4. 更新 README 的安装文件、配置、模式说明、依赖、权限和恢复方式。
5. 增加权限失败、用户修改、完整性失败、事务恢复及后台任务测试。
6. 运行 `luac -p`、全部 Lua 测试和 `npm pack --dry-run`。

## Acceptance Criteria

- `off` 不产生网络和更新目录副作用。
- 默认 `notify` 每 7 天检查，只获取版本元数据。
- 网络、权限、curl、tar、SHA-512 或校验失败时输入功能不受影响。
- `auto` 不覆盖用户修改，不更新任何 `.txt` 或 YAML 文件。
- Windows、macOS、Linux 命令生成和路径引用有测试覆盖。
- npm 产物只含两个 Lua 运行文件以及 npm 自动包含的元数据、README、LICENSE。
- 首次发布后验证 npmmirror 返回 `rimePlugin` 自定义元数据。
