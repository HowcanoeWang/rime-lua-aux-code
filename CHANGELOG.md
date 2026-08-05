# Changelog

## 1.0.0 - 2026-08-05

- 首个正式版本。
- 支持通过 npm 检查并自动更新插件，稳定版跟踪 `latest`，预发布版跟踪 `beta`。
- 支持独立的 `aux_code` 插件配置，并兼容旧版 filter 与 `key_binder` 配置。
- 更新操作采用 SHA-512 完整性校验，并在替换失败时回滚。

## 1.0.0-beta.4 - 2026-08-04

- 将 filter 简化为固定写法 `lua_filter@*aux_code`。
- 新增 `aux_code/dictionary`，用于选择辅码码表；默认使用 `ZRM_Aux-code_4.3`。
- 继续兼容旧写法 `lua_filter@*aux_code@<码表名>`，并提示迁移。
- 更新安装、定制码表及繁体输入示例。
