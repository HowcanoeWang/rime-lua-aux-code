# rime-lua-aux-code

RIME 输入法辅助码与音形分离插件 -> <a href="https://www.bilibili.com/video/BV18z4y1A75w">B站整活视频</a>

![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/rime_select.gif)

<p align="center">
  <img alt="GitHub Downloads" height="400px" src="https://api.star-history.com/svg?repos=HowcanoeWang/rime-lua-aux-code&type=Date">
</p>

## 特点

* 通过独立的文件存储辅码，无需生成音形混合词典
* 提供包括**自然码辅码表**和**小鹤形码表**在内的两种主流方案 （你甚至能找到**五笔**辅助码和**仓颉五代首尾码**辅助码）
* 在输入末尾键入分隔符 (默认为 `;` ，可自定义配置) 来激活辅码模式，选择候选词并上屏（通过空格或数字）后，可继续输入，插件会自动移除已上屏文字的辅码
  ![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/aux_split.png)
* 在候选单中直接提示单字的辅助码 （可配置关闭）
  ![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/aux_notice.png)
* 支持词语级筛选 （非首字筛选）
  ![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/aux_word.png)
  如「白日依山尽」仍然可以匹配到「i」 （尽的辅码）
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
    │  ├─ aux_code.lua               # github中的lua/aux_code.lua文件
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
        - lua_filter@*aux_code@ZRM_Aux-code_4.3
      
      speller/alphabet: zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA;

      key_binder/+:
        aux_code_learn_trigger: ";"
        aux_code_no_learn_trigger: ";;"
        bindings:
          - { when: has_menu, accept: minus, send: Page_Up }
          - { when: has_menu, accept: equal, send: Page_Down }
        show_aux_notice: true
    ```

    **详细说明**

    `engine/filters` 中的辅助码方案，前面的前缀`lua_filter@*aux_code@`不要修改，如果要换成别的，请使用方案txt的文件名（不带后缀），例如：
    ```yaml
    - lua_filter@*aux_code@flypy_full
    - lua_filter@*aux_code@cangjie5_quick_code
    ```

    > :warning: 辅码文件必须放在 `config/rime/aux_code/`（即 Rime 用户目录下的 `aux_code/`）
    >
    > 若输入了触发键但未输入辅码（例如 `twtw;`），插件会在首个候选中提示：
    > `(⚠️config/rime/aux_code/ 中未找到辅码文件 <文件名>.txt)`

    ---

    `speller/alphabet` 中，需要设置允许以 `;` 符号上屏。其他部分根据个人配置自行调整

    ```yaml
      speller/alphabet: zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA;
    ```
    > :warning: 符号 `;` 为英文半角，而非中文全角

    ---

    `key_binder` 中，如果想修改触发键为别的按键，可以用下面的方法来自定义：

    ```yaml
      key_binder/+:
        aux_code_learn_trigger: "#"
    ```

    > :warning: 请确保所选字符 `#` 已包含在上述 `speller/alphabet` 的值中
    > 如果是自定义触发键为 `.` 或 `,` ，这两个按键在大部分配置中默认为翻页键，可能还需要禁止该翻页键：

    ```yaml
      # 接 key_binder/+:
        bindings:
          # 禁用前翻页键 "."
          - { when: has_menu, accept: period, send: period }
          # 禁用后翻页键 ","
          - { when: has_menu, accept: comma, send: comma }
    ```

    ---

    同时也支持分别配置「记录用户词库触发键」和「不记录用户词库触发键」：

    ```yaml
      key_binder/+:
        aux_code_learn_trigger: ";"      # 辅码筛选，允许候选词进入用户词库
        aux_code_no_learn_trigger: ";;"  # 辅码筛选，仅上屏，不进入用户词库
    ```

    行为对照：

    | 输入触发键 | 启用辅码筛选 | 用户词库学习 |
    | --- | --- | --- |
    | `aux_code_learn_trigger` | 是 | 是 |
    | `aux_code_no_learn_trigger` | 是 | 否（仅上屏） |

    案例：

    建议用人名测试，例如：符筑玛（辅助码的谐音，日常语料中较少出现，便于观察学习效果）。

    1. 先用 ;;（不学习模式）  
      连续输入并上屏多次（例如 5~10 次），符筑玛不应因为这些输入而明显前移到更靠前候选。
    2. 再用 ;（学习模式）  
      再输入并上屏（通常少量次数即可观察到变化），符筑玛应更容易出现在候选中（排序趋于前移）。

    规则说明：
    - `aux_code_learn_trigger` 旧的 `aux_code_trigger`行为保持不变（等价于 learn trigger）。
    - `aux_code_no_learn_trigger` 未设置或为空时，表示不启用「不进入用户词库」模式。
    - 若两个触发键配置为同一个值，不进入用户词库的触发键会自动失效（避免歧义）。
    - 若两个触发键存在前缀关系（例如 `;` 与 `;;`），插件会优先匹配更长的触发键。

    ---

    如果对自己的辅助码熟悉程度非常有信心不需要任何辅助码提示，可以使用下面的配置进行关闭：

    ```yaml
    show_aux_notice: false  # 设置是否显示辅助码字母提示
    ```

    > :warning: 本插件使用的自然码方案为修改版，可能和你之前一直使用的有细微区别，建议开启辅助码提示一段时间后，确定输入没问题了再考虑关闭该项


4. 保存`*.custum.yaml`文件后，后执行一次“重新部署/重新加载配置”。


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
    - lua_filter@*aux_code/aux_code@aux_code/cangjie5_double
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
    - lua_filter@*aux_code/aux_code@aux_code/cangjie5_double
```
  
则 lua 脚本会在汉字简化后处理，**打出简体字的辅码，内部会按照对应的繁体字处理**，但此时**无法正确选择「一简对多繁」情况下繁体字的编码**。

## 开发与异常处理

目前有两种开发的方式：

1. 对于 Windows 和 macOS 端，若需进行调试，建议在 `Rime 配置文件夹/lua/aux_code.lua` 文件中取消被注释的日志模块引入代码及 `log.info` 语句，以便查看详细的输出内容。
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
