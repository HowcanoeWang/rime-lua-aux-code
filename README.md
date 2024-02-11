# rime-lua-aux-code

RIME 输入法辅助码与音形分离插件

![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/rime_select.gif)


<p align="center">
  <img alt="GitHub Downloads" height="400px" src="https://api.star-history.com/svg?repos=HowcanoeWang/rime-lua-aux-code&type=Date">
</p>

## 特点

* 通过独立的文件存储辅码，无需生成音形混合词典
* 提供包括**自然码辅码表**和**小鹤形码表**在内的两种主流方案
* 在输入末尾键入分隔符 (默认为 `;` ，可自定义配置) 来激活辅码模式，选择候选词并上屏（通过空格或数字）后，可继续输入，插件会自动移除已上屏文字的辅码  
  ![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/aux_split.png)
* 在候选单中直接提示单字的辅助码  
  ![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/aux_notice.png)
* 支持词语级筛选 （非首字筛选）  
  ![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/aux_word.png)  
  如「白日依山尽」仍然可以匹配到「i」 （尽的辅码）
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

1. 将本项目中的 `lua/aux_code.lua`、`lua/ZRM_Aux-code_4.3.txt` （自然码辅码表） 或 `lua/flypy_full.txt` （小鹤形码表） 复制到 `Rime 配置文件夹/lua/` 文件夹中。

2. 本插件需附加至特定输入方案。首先，复制你所需使用的输入方案文件名，将文件名中的 `schema` 改为 `custom`。然后，创建并打开一个名为 `*.custom.yaml` 的文件，在其中添加所需内容：

    ```yaml
    patch:
      engine/filters/+:
        - lua_filter@*aux_code@ZRM_Aux-code_4.3
        # 或下面的小鹤形码方案
        # - lua_filter@*aux_code@flypy_full

      # 允许以 `;` 符号上屏，最后的 `;` 为英文半角字符，非中文全角。前面部分根据个人配置自行调整
      speller/alphabet: zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA.,;

      # 自定义触发键，注意：请确保所选字符已包含在上述 speller/alphabet 的值中
      # key_binder/+;
        # aux_code_trigger: "."
    ```

3. 重新配置 Rime 输入法，如果一切顺利，应该就可以使用了。

#### 安卓平台的小企鹅输入法 5 安装与配置方法

为确保应用的正常运行，应选择安装 [F-Droid 发行的小企鹅输入法版本](https://f-droid.org/packages/org.fcitx.fcitx5.android/)，而不是从 Google Play 上安装。

随后为小企鹅输入法 5 安装 [Rime 插件](https://f-droid.org/packages/org.fcitx.fcitx5.android.plugin.rime/)。安装后启用 Rime 插件为：
首先打开 App，点击“插件”，加载 Rime 插件并返回。接着，依次操作：点击“输入法” -> 右下角的 “+” 号 -> 选择“中州韵” -> 点击新增行右侧的齿轮图标 -> 进入“用户数据目录”。然后，请确保应用已被授予读写权限。

至此，Rime 插件的激活步骤基本完成，接下来的操作与桌面平台一致。上述提到的 “用户数据目录” 即桌面端平台的 `Rime 配置文件夹`。

## 定制码表

若要制作个人码表，确保文件格式为 UTF-8 编码即可。文件中每一行应对应一个字的辅码，使用 `=` 号作为分隔符。若同一汉字有多种编码方案，应分别在新的一行中列出，如：

```plaintxt
阿=ek
厑=ib
厑=ii
...
```

首先，将相关内容或代码保存为 txt 文件，例如命名为 `my_aux_code.txt`。

接着，需要在 `*.custom.yaml` 文件的相应部分作出修改，把原有的 `- lua_filter@*aux_code@ZRM_Aux-code_4.3` 替换为 `- lua_filter@*aux_code@my_aux_code`（注意，这里不需要加 `.txt` 后缀）。

修改完成后，重新配置 Rime 输入法，新的设置便会生效。

## 开发与异常处理

目前有两种开发的方式：

1. 对于 Windows 和 macOS 端，若需进行调试，建议在 `Rime 配置文件夹/lua/aux_code.lua` 文件中取消被注释的日志模块引入代码及 `log.info` 语句，以便查看详细的输出内容。
2. 对于 Linux 端，可以通过在命令行中启动输入法，以直接获得 `print` 语句的输出，或者使用上述的日志模块获取输出结果

需要注意的是，输出的信息量可能较大，因此不推荐非插件开发人员这样做。

## 致谢

感谢以下贡献者：

* [@copperay](https://github.com/copperay) 维护的手心输入法自然码码表 [copperay/ZRM_Aux-code](https://github.com/copperay/ZRM_Aux-code/tree/main)  
  源文件采用 GB2312 编码且包含手心拼音需要的冗余首码，此项目中的 txt 文件已转换为 UTF-8 编码并且移除了冗余首码，可直接使用（并提供去冗的 python 脚本）。
* [@ksqsf](https://github.com/ksqsf) 贡献的词语级筛选功能
* [@shewer](https://github.com/shewer) 优化的代码以及辅码文件配置
* [@AiraNadih](https://github.com/AiraNadih) 增加小鹤码表、优化辅码分号逻辑、触发键改为可配置项，以及润色此说明文档
* [@expoli](https://github.com/expoli) 对文档说明的修改
