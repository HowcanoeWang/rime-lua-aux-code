# rime-lua-aux-code
RIME输入法辅助码音形分离插件

![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/rime_select.gif)


## 特点

* 使用独立的文件来存储辅码，不用生成音形混合的词典。
* 在输入的末尾使用`;`开启辅码模式，候选上屏后(空格或数字选择)可以连续输入，插件会自动清除已上屏文字的辅码。
  ![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/aux_split.png)
* 在候选单中直接提示辅助码。
  ![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/aux_notice.png)
* 支持词语级筛选(非首字筛选)    
  ![](https://cdn.jsdelivr.net/gh/HowcanoeWang/rime-lua-aux-code/static/aux_word.png)   
  如「白日依山尽」仍然可以匹配到「i」（尽的辅码）
* 此方案适用于使用辅助码排序候选项，而非音形结合的四键单字输入模式(请用单字字库来满足需求)

## 背景

目前rime拼音想要实现音形输入，普遍采用的做法是把音码和形码通过排列组合合成为词库引入。对于单字输入来说尚可接受，但一旦要进行词组输入，音码和形码的排列组合会呈恐怖的指数级增长。

传统方案除了音形本身的排列组合造成指数级增长的巨大字库，不同的音码和形码方案也需要重新制作词库。如我自己高强度使用智能ABC方案十几年才知道有形码方案，但为了使用形码还需要重新学习和适应自然码或小鹤的音码方案。一方面个人没有意愿再花时间做这个事情；另一方面，现有的所有传统音形词库都不支持智能ABC+其他形码方案的组合。

因此，音形分离不但有助于减轻输入法的词库负担，也有助于减少个人的心智负担。目前手心输入法提供了音形分离方案，但已经停止维护且没有Linux版本。为了在Linux上也有类似的输入体验，故开发此插件。

## 安装

且受限于本人的编程水平，目前尚不能提供自动的安装指令，需要手动配置来实现安装。

### 环境依赖

首先需要测试rime输入法是否能正常运行Lua插件，比较简单的测试方法是，按照[Lua-DateTranslator](https://github.com/hchunhui/librime-lua/wiki)安装并测试能否正常运行，即输入date可以成功在候选中找到当前的日期。

### 插件安装

1. 将本项目中的的 `lua/aux_code.lua`和`lua/ZRM_Aux-code_4.3.txt`(自然码辅码表) 复制到 `Rime配置文件夹/lua/` 文件夹中
2. 该插件须附加在某个具体的输入方案上，修改某个具体的输入方案的 `*.schema.yaml` 文件，具体如下：    
    在 `engine/filters` 最后面中添加 `lua_filter@*aux_code@ZRM_Aux-code_4.3`。
    ```yaml
    engine:
        ...
        filters:
            - simplifier@emoji_suggestion
            - simplifier
            - uniquifier
            - lua_filter@*aux_code@ZRM_Aux-code_4.3
    ```
    **一定要在 `simplifier` 后面，不然简体字的辅码提示会不显示**

    ---
    以及在 `spellers/alphabet` 中允许 `;` 符号上屏，
    ```yaml
    speller:
      alphabet: zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA.,;  
      #最后的;号，英文字符。前面的根据自己的配置自行修改
    ```
   
3. 重新配置rime输入法，不出意外的话即可使用

### 定制码表

默认使用的是这个自然码码表：[copperay/ZRM_Aux-code](https://github.com/copperay/ZRM_Aux-code/tree/main)。源文件是GB2324编码，Linux下会乱码所以我项目里的txt文件已经转换为UTF-8编码了，可以直接使用。

如果需要制作自己的码表，只要保证文件为UTF-8编码，然后文件的每一行都是一个字的辅码即可，中间用 `=` 号隔开。对于同一个字有不同的编码方案，需要另开一行，如：

```plaintxt
阿=e
阿=ek
厑=i
厑=ib
厑=ii
...
```

如果保存为了不同的txt文件名，如`my_aux_code.txt`，只需要修改配置yaml文件中的    
`- lua_filter@*aux_code@ZRM_Aux-code_4.3` 改成     
`- lua_filter@*aux_code@my_aux_code` 即可。    
(不需要`.txt`后缀)

修改完后，重新配置Rime输入法

## TODO

- [ ] 目前使用辅助码上屏的词组，似乎没有添加到用户词典里
- [ ] 偶发`；`没有被移除的问题

## 异常处理

如果需要debug的话，请在命令管理器中启动，可以考虑把 `lua/aux_code.lua` 里面的print注释取消，查看输出(会很多，不建议亲自搞)

## 致谢

* [@copperay](https://github.com/copperay) 维护的手心输入法自然码码表 [copperay/ZRM_Aux-code](https://github.com/copperay/ZRM_Aux-code/tree/main)
* [@ksqsf](https://github.com/ksqsf) 贡献的词语级筛选功能
* [@shewer](https://github.com/shewer) 优化的代码以及辅码文件配置