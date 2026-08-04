# rime-lua-aux-code

RIME 输入法辅助码与音形分离插件 -> <a href="https://www.bilibili.com/video/BV18z4y1A75w">B站整活视频</a>

![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/rime_select.gif)

<p align="center">
  <img alt="GitHub Downloads" height="400px" src="https://api.star-history.com/svg?repos=HowcanoeWang/rime-lua-aux-code&type=Date">
</p>

## 特点

* 辅码独立存放，无需生成音形混合词典；内置[多种主流辅助码码表](./aux_code/README.md)，也支持自定义码表
* 输入触发符（默认 `;`）即可按辅码筛选候选；可另设不写入用户词库的触发符（默认 `;;`）；连续选词时，插件会自动清理已上屏文字的辅码<br>
  ![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/aux_split.png)
* 输入辅码后可直接用标点上屏候选，无需额外按空格
* 可在候选单提示单字辅码（可手动配置关闭）    
  ![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/aux_notice.png)
* 支持词语级筛选：可匹配词中任意字，并优先显示首字命中的候选    
  ![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/aux_word.png)    
  如「白日依山尽」可用 `i` 匹配「尽」；词组命中时会显示命中字与辅码，如 `椰子蟹(蟹:ij)`
* 为优化性能，**未**匹配辅助码的候选**不会**出现在列表中
* 此方案适用于使用辅助码排序候选项，而非音形结合的**四键单字**输入模式 （请用单字字库来满足需求）

## 背景

目前，Rime 拼音在实现音形输入方面，普遍采用的方法是将音码和形码通过排列组合的方式组合成词库进行引入。这样做会导致音码和形码的排列组合数量呈指数级增长，变得庞大而复杂。

此外，采用不同的音码和形码方案还需要重新构建词库。例如，我使用智能 ABC 方案十几年后才了解到形码方案的存在，但要使用形码，还必须重新学习和适应自然码或小鹤的音码方案。一方面，我个人不愿意再投入时间去做这件事；另一方面，目前所有的传统音形词库都不支持智能 ABC 与其他形码方案的组合。

因此，音形分离不但有助于减轻输入法的词库负担，也有助于减少个人的心智负担。目前，手心输入法提供了音形分离方案，但该方案已经停止了维护，并且没有适用于 Linux 的版本。因此，为了在 Linux 上也能享受类似的输入体验，我开发了这款插件。

## 安装

### 环境依赖

在 Windows、macOS 和 Linux 上的 Rime 输入法中，默认情况下 Lua 插件是开启的。但如果在执行完**插件安装**后发现无法使用，建议你按照 [Lua-DateTranslator](https://github.com/hchunhui/librime-lua/wiki) 的指引进行测试。测试方法是输入 date，查看候选词中是否能显示当前日期（例如 2023 年 10 月 16 日）。请注意，日期信息可能不会出现在第一页候选词中，你可能需要向后翻页查找。如果日期显示正常，但此插件仍然无法使用，请开设一个 issue 进行反馈。

而在 Android 平台上，[同文输入法](https://github.com/osfans/trime) 和 [小企鹅输入法 5 (强烈推荐)](https://github.com/fcitx5-android/fcitx5-android) 都支持 Lua 插件，安装方式见下面的插件安装部分。

### 插件安装

#### 桌面平台 (Windows, macOS 和 Linux)

1.  找到 Rime 用户配置目录

    先找到你的 Rime 配置目录（后文记作 config_path）。常见路径如下（供参考）：

    - Windows (Weasel/小狼毫)
      `C:\Users\<你的用户名>\AppData\Roaming\Rime`
    - macOS (Squirrel/鼠须管)
      `~/Library/Rime`
    - Linux (fcitx5-rime 或 ibus-rime)
      `~/.local/share/fcitx5/rime` 或 `~/.config/ibus/rime`

    不同发行版或输入法前端可能有差异；如果不一致，以你系统里实际“用户目录/配置目录”为准。

2. 放置插件文件与辅码文件

    示例目录结构（file tree）：

    ```
    (config_path)/
    ├─ lua/
    │  ├─ aux_code.lua               # GitHub 中的 lua/aux_code.lua
    │  ├─ aux_code_updater.lua       # GitHub 中的 lua/aux_code_updater.lua
    │  ├─ ...
    ├─ aux_code/
    │  ├─ ZRM_Aux-code_4.3.txt       # 辅助码码表文件
    │  └─ flypy_full.txt             # 二选一即可，也可放你自己的码表
    ├─ ...
    ├─ double_pinyin_abc.schema.yaml  # 你的输入方案原文件
    └─ double_pinyin_abc.custom.yaml  # 插件要自定义的文件
    ```

3. 创建“方案补丁文件” `*.custom.yaml`


    <details>
    <summary>点击查看补丁文件(custom.yaml)和输入方案原文件(schema.yaml)的说明</summary>

    补丁文件就是“**在不改原始 `schema.yaml` 的前提下追加/覆盖配置**”的文件。

    推荐始终改 `custom`，不要直接改 `schema`。

    - `schema.yaml`：输入方案原文件（通常来自方案包/上游）
    - `custom.yaml`：你的个人补丁文件（升级后更不容易被覆盖）

    如果你的方案是：
    
    - `double_pinyin_abc.schema.yaml`

    那对应补丁文件就是（位于 `...(config_path)/`）：
    
    - `double_pinyin_abc.custom.yaml`

    ---

    </details>

    把以下默认配置粘贴到 double_pinyin_abc.custom.yaml：

    ```yaml
    patch:
      engine/filters/+:
        - lua_filter@*aux_code
      
      aux_code:
        dictionary: ZRM_Aux-code_4.3
        learn_trigger: ";"
        no_learn_trigger: ";;"
        show_aux_notice: true
        update_mode: notify
        check_interval_days: 7

      speller/alphabet: zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA;

      key_binder/bindings/+:
        - { when: has_menu, accept: minus, send: Page_Up }
        - { when: has_menu, accept: equal, send: Page_Down }
    ```

    **详细说明**

    1. 选择辅码码表

       `engine/filters` 固定填写 `lua_filter@*aux_code`，辅码 txt 文件名（不带后缀）在 `aux_code/dictionary` 中配置。例如：

       ```yaml
       aux_code:
         dictionary: flypy_full

       # 或
       aux_code:
         dictionary: cangjie5_quick_code
       ```

       `dictionary` 未设置或为空时，默认使用 `ZRM_Aux-code_4.3`。

       > :warning: 辅码文件必须放在 Rime 用户目录下的 `aux_code/` 目录。
       >
       > 如果对应文件不存在，输入主编码和触发符（例如 `twtw;`）时，插件会在首个候选中提示：
       > `(⚠️config/rime/aux_code/ 中未找到辅码文件 <文件名>.txt)`

    2. 配置辅码插件

       `aux_code` 是插件自己的配置项。默认提供两个相互独立的触发符：

       ```yaml
       aux_code:
         dictionary: ZRM_Aux-code_4.3  # 辅码码表文件名，不含 .txt
         learn_trigger: ";"       # 辅码筛选，允许候选词进入用户词库
         no_learn_trigger: ";;"   # 辅码筛选，仅上屏，不进入用户词库
         show_aux_notice: true     # 在候选中显示单字辅码提示
         update_mode: notify       # off、notify 或 auto，默认仅提醒
         check_interval_days: 7   # 每隔多少天检查一次更新
       ```

       | 配置项 | 启用辅码筛选 | 用户词库学习 |
       | --- | --- | --- |
       | `learn_trigger` | 是 | 是 |
       | `no_learn_trigger` | 是 | 否（仅上屏） |

       `;;` 只是默认值，并不是 `no_learn_trigger` 必须重复两次 `learn_trigger`。两个触发符可以完全不同，例如：

       ```yaml
       aux_code:
         learn_trigger: ";"
         no_learn_trigger: "#"
         show_aux_notice: true
       ```

       触发符只有出现在主编码之后才会生效。例如 `ni;fy` 会启用辅码筛选，以 `;` 开头的输入则不会被当作辅码输入。

       其他规则：

       - `no_learn_trigger` 未设置或为空时，不启用「不进入用户词库」模式。
       - 两个触发符相同时，`no_learn_trigger` 自动失效，以避免歧义。
       - 两个触发符存在前缀关系时（例如 `;` 与 `;;`），插件优先匹配更长的触发符。
       - 不需要单字辅码提示时，将 `show_aux_notice` 设置为 `false`。
       - `check_interval_days` 只接受正整数，无效值按 7 天处理。

       可以用较少见的人名观察用户词库学习效果。例如先用 `;;` 多次输入“符筑玛”，其排序不应明显前移；再改用 `;` 输入，候选排序应逐渐前移。

       更新模式说明：

       | `update_mode` | 行为 |
       | --- | --- |
       | `off` | 不检查更新，也不创建更新状态目录 |
       | `notify` | 默认值，只通过候选注释提醒，不下载程序包 |
       | `auto` | 校验通过后自动替换两个 Lua 文件，重新部署后生效 |

       更新与迁移提示会持续显示到首次选定候选。尚未确认的更新提示会在重新部署后恢复，避免因候选刷新而遗漏。

       更新检查优先访问 npmmirror，失败后尝试 npm 官方 Registry。`notify` 需要系统可用的 `curl`；`auto` 还需要 `tar` 及 SHA-512 工具（Windows 为 `certutil`，macOS/Linux 为 `shasum` 或 `sha512sum`）。网络、权限、工具或校验异常都不会影响辅码筛选。

       npm/npmmirror 只承担后续程序更新，不提供首次安装：首次仍从 GitHub 获取两个 Lua 文件和自选码表。自动更新只处理 `lua/aux_code.lua` 与 `lua/aux_code_updater.lua`，不会修改 `aux_code/*.txt`、`*.yaml` 或用户自定义内容。检测到任一 Lua 文件被修改时，`auto` 会取消覆盖并仅作提醒。

       预发布版本自动跟踪 npm 的 `beta` 标签，用于验证更新流程；正式版本只跟踪 `latest`。发布正式版时，`beta` 用户会升级到对应稳定版本。

       从旧版本升级时，插件会继续读取旧 filter 写法及原先位于 `key_binder` 下的配置，并在首次选定候选前持续提醒迁移。新配置优先，更新器不会自动修改任何 YAML：

       | 旧配置 | 新配置 |
       | --- | --- |
       | `lua_filter@*aux_code@<码表名>` | `lua_filter@*aux_code` 与 `aux_code/dictionary: <码表名>` |
       | `key_binder/aux_code_trigger` | `aux_code/learn_trigger` |
       | `key_binder/aux_code_learn_trigger` | `aux_code/learn_trigger` |
       | `key_binder/aux_code_no_learn_trigger` | `aux_code/no_learn_trigger` |
       | `key_binder/show_aux_notice` | `aux_code/show_aux_notice` |

       若需要明确关闭不学习触发符，可以设置 `aux_code/no_learn_trigger: ""`，该值会覆盖旧配置。

       Android 上可继续手动安装插件，但不保证更新功能可用。

    3. 将触发字符加入 `speller/alphabet`

       所有触发符使用的字符都必须包含在 `speller/alphabet` 中。默认的 `;` 配置如下：

       ```yaml
       speller/alphabet: zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA;
       ```

       如果使用 `;` 和 `#` 两个触发符，则两个字符都要加入，并建议用引号包裹包含 `#` 的 YAML 字符串：

       ```yaml
       speller/alphabet: "zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA;#"
       ```

       > :warning: `;` 等符号应使用英文半角字符。输入辅码后的上屏标点不需要加入 `speller/alphabet`，例如 `ni;fy.` 中的 `.` 仍由 Rime 原有标点流程处理。

    4. 必要时处理按键冲突

       `key_binder` 只用于真正的按键映射，不存放插件配置。如果将触发符设置为 `.` 或 `,`，它们可能与输入方案的翻页键冲突，需要调整对应绑定：

       ```yaml
       patch:
         key_binder/bindings/+:
           # 禁用前翻页键 "."
           - { when: has_menu, accept: period, send: period }
           # 禁用后翻页键 ","
           - { when: has_menu, accept: comma, send: comma }
       ```

       > :warning: 是否存在冲突取决于当前输入方案；没有冲突时不需要添加这些绑定。

       本插件使用的自然码方案为修改版，可能和你之前使用的码表有细微区别。建议先开启辅码提示，确认输入习惯和码表一致后再关闭。


4. 保存 `*.custom.yaml` 文件后，执行一次“重新部署/重新加载配置”。


#### 安卓平台的小企鹅输入法 5 安装与配置方法

为确保应用的正常运行，应选择安装 [F-Droid 发行的小企鹅输入法版本](https://f-droid.org/packages/org.fcitx.fcitx5.android/)，而不是从 Google Play 上安装。

随后为小企鹅输入法 5 安装 [Rime 插件](https://f-droid.org/packages/org.fcitx.fcitx5.android.plugin.rime/)。安装后启用 Rime 插件为：
首先打开 App，点击“插件”，加载 Rime 插件并返回。接着，依次操作：点击“输入法” -> 右下角的 “+” 号 -> 选择“中州韵” -> 点击新增行右侧的齿轮图标 -> 进入“用户数据目录”。然后，请确保应用已被授予读写权限。

至此，Rime 插件的激活步骤基本完成，接下来的操作与桌面平台一致。上述提到的 “用户数据目录” 即桌面端平台的 `Rime 配置文件夹`。

### 繁体输入的注意事项

如果您使用的是基于**繁体字**的**朙月拼音**，在打出简体字时需要经过一层 **simplifier**，此时方案 .schema.yaml 文件中 `engine/filter` 段中，如果写成：

```yaml
engine:
  filters:
    - lua_filter@*aux_code
    - simplifier
    - uniquifier
```

则 lua 脚本会在 simplifier（汉字简化）和 uniquifier（一简对多繁汉字的合并）之前处理：**打出繁体字的辅码，上屏时会转换成简体字**。
  
但如果写成：

```yaml
engine:
  filters:
    - simplifier
    - uniquifier
    - lua_filter@*aux_code
```
  
则 lua 脚本会在汉字简化后处理，**打出简体字的辅码，内部会按照对应的繁体字处理**，但此时**无法正确选择「一简对多繁」情况下繁体字的编码**。


## 开发与异常处理

目前有两种开发的方式：

1. 对于 Windows 和 macOS 端，若需进行调试，请将 `lua/aux_code_log.lua` 放入 `Rime 配置文件夹/lua/`，并在 `aux_code.lua` 中取消被注释的日志模块引入代码及 `log.info` 语句，以便查看详细的输出内容。
2. 对于 Linux 端，可以通过在命令行中启动输入法，以直接获得 `print` 语句的输出，或者使用上述的日志模块获取输出结果

需要注意的是，输出的信息量可能较大，因此不推荐非插件开发人员这样做。

## 致谢

感谢以下贡献者：

* [@copperay](https://github.com/copperay) 维护的手心输入法自然码码表 [copperay/ZRM_Aux-code](https://github.com/copperay/ZRM_Aux-code/tree/main)
  源文件采用 GB2312 编码且包含手心拼音需要的冗余首码，此项目中的 txt 文件已转换为 UTF-8 编码并且移除了冗余首码，可直接使用（并提供去冗的 python 脚本）。
* [@dykwok](https://github.com/dykwok) 添加的五笔辅助码 (都会五笔了何苦用拼音=_=)，码表来自 [rime/rime-wubi](https://github.com/rime/rime-wubi)
* [@ksqsf](https://github.com/ksqsf) 贡献的词语级筛选功能及性能优化
* [@shewer](https://github.com/shewer) 优化的代码以及辅码文件配置
* [@AiraNadih](https://github.com/AiraNadih) 增加小鹤码表、优化辅码分号逻辑、触发键改为可配置项，以及润色此说明文档
* [@expoli](https://github.com/expoli) 对文档说明的修改
* [@EtaoinWu](https://github.com/EtaoinWu) 候选过滤逻辑性能优化
* [@gaboolic](https://github.com/gaboolic) 添加的[墨奇辅助码](https://github.com/gaboolic/moqima-tables)
* [@BH2WFR](https://github.com/BH2WFR) 添加的繁体仓颉辅助码以及繁简并输的相关说明
* [@silv3rarr0w](https://github.com/silv3rarr0w) 添加的自然码纯血版方案以及对辅助码存放文件夹的更新方案建议
