# 辅码码表清单

本目录存放 `aux_code.lua` 使用的辅码码表（`.txt`）。

| 文件名 | 辅码方案 | 来源 |
| --- | --- | --- |
| `ZRM_Aux-code_4.3.txt` | 自然码辅码（修改版，去冗余首码） | [copperay/ZRM_Aux-code](https://github.com/copperay/ZRM_Aux-code/tree/main) |
| `ZRM-wanxiang.txt` | 原版自然码码表（对应关系更精确） | [amzxyz/rime_wanxiang](https://github.com/amzxyz/rime_wanxiang) |
| `flypy_full.txt` | 小鹤形码（全码） | 社区贡献（[@AiraNadih](https://github.com/AiraNadih)） |
| `wubi86-code.txt` | 五笔 86 辅助码 | [rime/rime-wubi](https://github.com/rime/rime-wubi) |
| `moqi_aux_code.txt` | 墨奇辅助码 | [gaboolic/moqima-tables](https://github.com/gaboolic/moqima-tables) |
| `cangjie5_quick_code.txt` | 仓颉五代（快码/首尾码方案） | 社区贡献（[@BH2WFR](https://github.com/BH2WFR)） |

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