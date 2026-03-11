# 辅码码表清单

本目录存放 `aux_code.lua` 使用的辅码码表（`.txt`）。

| 文件名 | 辅码方案 | 来源 |
| --- | --- | --- |
| `ZRM_Aux-code_4.3.txt` | 自然码辅码（修改版，去冗余首码） | [copperay/ZRM_Aux-code](https://github.com/copperay/ZRM_Aux-code/tree/main) |
| `ZRM-wanxiang.txt` | 原版自然码码表（对应关系更精确） | [amzxyz/rime_wanxiang](https://github.com/amzxyz/rime_wanxiang) |
| `flypy_full.txt` | 小鹤形码（全码） | 社区贡献（[@AiraNadih](https://github.com/AiraNadih)） |
| `wubi86-code.txt` | 五笔 86 辅助码 | [rime/rime-wubi](https://github.com/rime/rime-wubi) |
| `moqi_aux_code.txt` | 墨奇辅助码 | [gaboolic/moqima-tables](https://github.com/gaboolic/moqima-tables) |
| `cangjie5_quick_code.txt` | 仓颉五代（快码/首尾码方案） | 社区贡献（[@BH2WFR](https://github.com/BH2WFR)） 原始码表：[rime/rime-cangjie](https://github.com/rime/rime-cangjie) |

## 使用说明

- `lua_filter@*aux_code@<文件名去掉 .txt>` 中的名称需要与上表文件名对应。
- 例如：`lua_filter@*aux_code@ZRM_Aux-code_4.3` 对应 `ZRM_Aux-code_4.3.txt`。

## 定制码表

若要制作个人码表，确保文件格式为 UTF-8 编码即可。文件中每一行应对应一个字的辅码，使用 `=` 号作为分隔符。若同一汉字有多种编码方案，应分别在新的一行中列出，如：

```plaintxt
阿=ek
厑=ib
厑=ii
...
```

首先，将相关内容或代码保存为 txt 文件，例如命名为 `my_aux_code.txt`，并放到 `config/rime/aux_code/` 目录。

接着，需要在 `*.custom.yaml` 文件的相应部分作出修改，把原有的 `- lua_filter@*aux_code@ZRM_Aux-code_4.3` 替换为 `- lua_filter@*aux_code@my_aux_code`（注意，这里不需要加 `.txt` 后缀）。

修改完成后，重新配置 Rime 输入法，新的设置便会生效。

## 各辅码方案的注意事项

- **仓颉五代首尾码**（五代速成）辅助码：
  - 码表来自 [rime/rime-cangjie](https://github.com/rime/rime-cangjie)，并基于此编码，使用脚本进行了自动化的首尾码摘取，并依据「朙月拼音」方案码表，去除了所有没有拼音编码的汉字。
  - 单码字（如「日」）的辅码，可仅输入一个字母，也支持「z+字母」，如「日」字的辅码可为 `a`（日） 或 `za`（z日）
  - 汉字「〇」的辅码定为 `r` (口) 或 `zr`（`z口`）
  - 首码不可以使用 `x`（難）
  - 部分汉字存在繁简同码问题，建议在输入方案中设置 `simplifier/tips` 为 `all`，以开启繁简转换前原始汉字的提示。
  - 如果您使用的是朙月拼音方案，输入辅码时，请务必输入繁体字的辅码，否则会造成词库混乱！
