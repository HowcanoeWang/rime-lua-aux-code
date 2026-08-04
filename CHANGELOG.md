# Changelog

## 1.0.0-beta.4 - 2026-08-04

- 将 filter 简化为固定写法 `lua_filter@*aux_code`。
- 新增 `aux_code/dictionary`，用于选择辅码码表；默认使用 `ZRM_Aux-code_4.3`。
- 继续兼容旧写法 `lua_filter@*aux_code@<码表名>`，并提示迁移。
- 更新安装、定制码表及繁体输入示例。
