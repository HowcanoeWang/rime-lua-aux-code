# v1.0.0-beta.4 发布公告草稿

## 标题

rime-lua-aux-code v1.0.0-beta.4：辅码库改用独立配置

## 正文

v1.0.0-beta.4 将辅码库选择移入插件自己的 `aux_code` 配置，filter 不再携带码表名：

```yaml
patch:
  engine/filters/+:
    - lua_filter@*aux_code

  aux_code:
    dictionary: cangjie5_quick_code
    learn_trigger: ";"
    no_learn_trigger: ";;"
```

`dictionary` 填写 `aux_code/` 目录下的 txt 文件名，不含 `.txt`；未设置时默认使用 `ZRM_Aux-code_4.3`。

旧写法 `lua_filter@*aux_code@<码表名>` 仍可继续使用，新配置优先。检测到旧写法时，候选栏会提示迁移，插件不会自动修改 YAML。

较早版本放在 `key_binder` 下的触发键配置也继续兼容，迁移对应关系见项目 README。

beta.1 和 beta.2 的更新提示可能一闪而过，建议这些版本的用户手动更新一次 beta.4。beta.3 及后续版本会持续显示更新提示，直到首次选定候选。

完整安装和迁移说明见项目 README：
https://github.com/HowcanoeWang/rime-lua-aux-code

## 发布前检查

- [x] 版本更新为 `1.0.0-beta.4`
- [x] npm 文件 SHA-512 已更新
- [x] Lua 测试、语法检查和 npm 包校验通过
- [x] README 与码表说明已更新
- [ ] 提交并推送 beta.4 改动
- [ ] 创建并推送 `v1.0.0-beta.4`
- [ ] 确认 GitHub Actions 发布成功
- [ ] 确认 npm 与 npmmirror 的 `beta` 标签指向 beta.4
