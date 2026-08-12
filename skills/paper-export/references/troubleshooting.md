# 报错与异常现象对照表

每条按「现象 → 原因 → 处理」组织。最危险的是第 1 节那几条——它们**不报错**，
导出看着成功，问题藏在成品里。

---

## 0. 四件排错工具

**`scripts/doctor.sh`** —— 先跑它。缺 pandoc / LaTeX 引擎 / 字体 / Word 母版
都会逐项报出来，并给可直接复制的安装命令。`doctor.sh --install` 自动补装 brew 组件。

**`md-lint.py`** —— 内容层体检：

```bash
python3 ~/.claude/skills/paper-export/scripts/md-lint.py 文档.md            # 默认
python3 ~/.claude/skills/paper-export/scripts/md-lint.py 文档.md --verbose  # 展开全部
python3 ~/.claude/skills/paper-export/scripts/md-lint.py 文档.md --strict   # 有 error 就 exit 1
```

默认输出**只展开 error**，warn / info 折叠成一行计数——长文档里几十条「表格前缺空行」
会把真正要命的那两条淹掉。要看全部加 `--verbose`。

error 只有两条（标题前缺空行、单元格显示宽度 > 80），但都会实际改变成品。
`export.sh` 默认已经跑过一遍（只打印不拦截），加 `--strict-lint` 才会中止导出。

**`--keep-tex`** —— LaTeX 报错时定位行号：

```bash
bash scripts/export.sh 文档.md --to pdf --keep-tex
sed -n '540,600p' 输出.tex     # 报错信息里的行号对应这个文件
```

注意 tectonic 的报错行号指的是**生成的 .tex**，不是你的 Markdown。

**`soffice --headless`** —— 不开 Word 也能看 Word 排版：

```bash
soffice --headless --convert-to pdf 输出.docx --outdir .
pdftotext -f 1 -l 3 输出.pdf -    # 逐页看文字与页眉页脚
```

限制见本文 4.4：LibreOffice 不刷新域，目录会是空的。

---

## 1. 不报错但成品是错的

### 1.1 目录少一章，正文里出现字面的 `## 四、待确认事项`

**现象**：导出成功，但目录比源文档少一章；正文某段末尾多出一行
「## 四、待确认事项」这样的原文。

**原因**：标题前面漏了空行。

```markdown
这里是一段正文。
## 四、待确认事项
```

pandoc 的 `markdown` 方言默认开着 `blank_before_header` 扩展——**标题行前必须有
空行才算标题**，否则整行被当作上一段的续行。于是这一章的标题退化成普通文字，
目录里没有它，章节分页也不会在这里发生。中文长文档里这是最常见的静默事故：
成品看上去完全正常，只有对着目录数章数才能发现。

**处理**：已经修好了，两道防线：

1. `export.sh` 的 `--from` 里显式关掉这个扩展：
   `markdown-blank_before_header+lists_without_preceding_blankline+…`
   现在标题前有没有空行都识别为标题，列表同理。
2. `md-lint.py` 把它列为 **error**，并指出该在第几行和第几行之间插空行。

自己直接调 pandoc 时记得带上 `-blank_before_header`，否则又会被吞。

验证方法：

```bash
pandoc --from=markdown -t native 文档.md | grep -c Header               # 默认方言
pandoc --from=markdown-blank_before_header -t native 文档.md | grep -c Header
```

两个数字不一样，就说明文档里有被吞掉的标题。

### 1.2 表格里长文本列被挤成四行，短列一大片留白

**现象**：「说明」「备注」这类列每格折成三四行，「序号」「状态」列却空着大半。

**原因**：pandoc 按 Markdown **分隔行的长度**分配列宽——`|---|-------|` 里第二列的
短横多，就多给宽度；分隔行等长时干脆等分。这跟单元格里实际有多少字毫无关系。

**处理**：`tablefit.lua` 丢掉那套宽度，按列内容重算（SPEC §4.2）：显示宽度按
CJK 计 2，每列取表头宽、最大宽、90 分位宽算权重，线性归一化与 √ 压缩各占一半
（√ 压缩防止一列吃掉整个版心），再把每列钳到 [0.06, 0.55] 重新归一化，写回 AST 的
`colspecs`——PDF 与 Word 两侧吃的是同一组宽度。

`--no-table-fit` 会退回 pandoc 的旧行为，只在需要对照排查时用。

仍然挤：说明源表本身超纲。`md-lint.py` 会告警——单元格显示宽度 > 40 是 warn、
> 80 是 error，列数 > 6 是 warn。这种表应该拆成正文段落或「字段说明列表」。

### 1.3 页码是对的，页眉右侧永远空白

**现象**：PDF 正文页码从 1 正常开始，但页眉右侧应该显示当前章节名的位置一直是空的，
而且页眉左侧还顶着前置节的样式。

**原因**：pandoc 的 LaTeX 模板把目录整段包在一对花括号里，为的是让
`\hypersetup{linkcolor=toccolor}` 只作用于目录：

```tex
{
\hypersetup{linkcolor=black}
\setcounter{tocdepth}{3}
\tableofcontents
}
```

在这个分组里调用 `\pagestyle{fancy}` 做的是**局部 `\let`**，出了右花括号就弹回
`pefront`。偏偏 `\pagenumbering` 内部用的是 `\gdef`，页码切换是全局的、看着完全正常。
于是这个 bug 表现为「页码对、页眉不对」，极难联想到分组作用域上去。

**处理**：`preamble-report.tex` / `preamble-gb.tex` 用 `\aftergroup` 把切换推迟到
分组结束之后执行：

```tex
\AtBeginDocument{%
  \let\pe@origtoc\tableofcontents
  \renewcommand{\tableofcontents}{\pe@origtoc\aftergroup\pe@beginbody}}
\newcommand{\pe@beginbody}{\clearpage\pagenumbering{arabic}\pagestyle{fancy}}
```

**不要试图用 `\globaldefs=1` 强行全局化。** 它会把这段代码执行期间**所有**赋值
变成全局的，包括 `\protected@write` 内部那些本该局部的 `\let\protect\@unexpandable@protect`。
副作用是：之后写进 `.aux` 的控制序列集体丢掉反斜杠（`\contentsline` 变成
`contentsline`），下一轮编译读 `.aux` 时直接报

```
! LaTeX Error: Missing \begin{document}.
```

排查时很容易误以为是 preamble 里混进了正文内容，方向全错。`\aftergroup` 是干净解。

另有一条相关机制：`fancyhdr` 在切换页面样式时会把 `\sectionmark` / `\chaptermark`
重置成自己的版本，写在 preamble 里的重定义会被悄悄盖掉。所以 `\pe@setmarks` 必须
写在每个 `\fancypagestyle{...}` 的**体内**，而不是外面。

---

## 2. PDF 封面与页眉

### 2.1 封面顶端漏出一条页眉横线

**现象**：封面本该干干净净，页顶却有一条细横线。

**原因**：`\headrule` 被重定义成无条件画线：

```tex
\renewcommand{\headrule}{{\color{prule}\hrule height 0.6pt}}   % 错
```

`\fancypagestyle{empty}` 关页眉的手段是把 `\headrulewidth` 设成 0pt，而上面这个版本
根本不看 `\headrulewidth`，于是关不掉。

**处理**：自己判一次（`preamble-*.tex` 已改）：

```tex
\renewcommand{\headrule}{%
  \ifdim\headrulewidth>0pt\relax
    {\color{prule}\hrule height \headrulewidth}%
  \fi}
```

### 2.2 封面副标题出现两遍 / 页眉被撑成两行（已修）

**现象**：PDF 封面主标题下方紧贴着一个字号偏小的副标题，隔一行还有一个正常的；
页眉左侧的文档标题也变成两行，页眉线被顶开。

**原因**：pandoc 的 LaTeX 模板在 `$if(subtitle)$` 分支里把副标题**拼进 `\title`**：

```tex
\title{一期工程总体方案 \\ \vspace{0.5em} {\large 二期扩容}}
```

（老版模板写成 `\providecommand{\subtitle}[1]{\apptocmd{\@title}{...}}` +
`\subtitle{...}`，效果一样。）而本 skill 是自绘封面：`titlepage.tex` 重定义
`\maketitle`，用 `\@title` 排主标题、用自己的 `\pesubtitle` 排副标题。模板那份和
自绘那份**叠加**，副标题就出现两遍；`\@title` 被撑成两行之后，页眉取 `\@title` 也跟着
变两行。

**修法：显式传空值，不是「不传」。** 这是最容易重犯的点——`export.sh` 原本只是
不把 `--subtitle` 放进公共参数，那只挡得住命令行那条路；**写在文档 YAML 块里的
`subtitle:` pandoc 自己照样读得到**，模板照样生成。现在 `build_pdf` 里显式加了

```bash
-M "subtitle="
```

空字符串让模板的 `$if(subtitle)$` 判假，那一段不再生成。PDF 侧副标题一律走
`cover-vars.tex` 的 `\pesubtitle`；Word 侧不受影响，仍由 `build_docx` 单独传
`-M subtitle=<值>` 给 `cover-docx.lua`。

实测：`subtitle` 写在 frontmatter、命令行什么都不给，PDF 封面副标题出现一次，
页眉单行；命令行 `--subtitle` 与 frontmatter 并存时命令行胜出，也只有一次。

**推广**：凡是 pandoc 默认模板也认识的元数据键（`subtitle` `institute` `thanks`
`abstract` `keywords`…），只要你自绘了对应的版面，就必须显式传空值把模板那份关掉。
排查手法是 `--keep-tex` 之后 `grep -n 'subtitle\|\\title{' 输出.tex`，
看模板到底写了什么。

---

## 3. LaTeX 编译中断

### 3.1 `! You can't use \spacefactor in vertical mode.`

**现象**：报错位置指向 `\begin{document}` 附近，preamble 里看不出哪里有问题。

**原因**：`\AtBeginDocument{...}` 的花括号内容在**读到的那一刻**就被 token 化存下来。
如果这时 `@` 还是普通字符（catcode 12），里面的 `\@ifundefined` 会被切成
`\@` + `ifundefined`——而 `\@` 是 LaTeX 的「句末间距」宏，垂直模式下调用它就报
`\spacefactor` 那句话。

```tex
\AtBeginDocument{\@ifundefined{Shaded}{}{...}}          % 错：外面没有 \makeatletter
```

**处理**：把 `\AtBeginDocument` 整个包进 `\makeatletter … \makeatother`
（`preamble-common.tex` 第 3 节就是这么写的）。凡是钩子里出现带 `@` 的内部命令，
都要检查这一点——因为报错点在 `\begin{document}`，离出错的代码很远。

### 3.2 `! Incomplete \ifx; all text was ignored after line NN.`

**现象**：封面或某个条件分支处编译中断。

**原因**：条件分支的分支体里出现了 `tabular` 的对齐符 `&` 或换行 `\\`。TeX 在跳过
未选中分支时做的是**词法扫描**，而对齐符会启动 alignment 扫描，两种扫描互相打断，
条件语句就找不到自己的 `\fi`。

**处理**：条件里不要放表格。封面信息栏原本用 `tabular` 排「标签：值」两列，现在改成
两个零宽 `\makebox` 共用一个锚点：

```tex
\newcommand{\pe@inforow}[2]{%
  \pe@ifempty{#2}{}{%
    \makebox[0pt][r]{\pe@lbl{#1}}%          标签向左伸
    \makebox[0pt][l]{：\hspace{0.35em}#2}%  值向右伸
    \par\vspace{0.5\baselineskip}}}
```

`\centering` 环境里锚点就是页面中线，视觉效果与两列表格一致，且没有对齐扫描。

顺带一条同源的坑：判断字段是否为空要用 `\ifx#1\@empty` 直接比宏，**不要 `\edef`**
——字段值里可能含 `\&` `\%` 这类转义序列，`\edef` 展开它们会炸。

### 3.3 `! Undefined control sequence. \hypersetup`

**原因**：在 `preamble-*.tex` 里调用了 `\hypersetup`。pandoc 模板加载 hyperref 的
位置**晚于** `header-includes`，此时该命令还不存在。

**处理**：链接颜色用 pandoc 变量设（`-V colorlinks=true -V linkcolor=black …`，
见 `export.sh` 的 `build_pdf`）。hyperref 提供的任何命令都不能写在 preamble 里。

### 3.4 `! Missing number, treated as zero.`

**原因**：往 pandoc 生成的转义序列里插了不该插的 token。典型是重定义 `\texttt` 后
逐 token 插 `\penalty`——pandoc 会把 `^` 转成 `\^{}`，`\penalty` 被当成重音命令的参数。

**处理**：行内代码的断行在 AST 层做（`sanitize.lua` 的 `Code`），不要在 TeX 侧
重定义 `\texttt`。

### 3.5 `! LaTeX cmd Error: First argument of '\NewDocumentCommand' must be a command.`

**原因**：`\ExplSyntaxOn` 下 `@` 不是 letter，命令名里带 `@` 会被切断。

**处理**：expl3 代码块内的命令名用驼峰或 `_`。

### 3.6 章节编号变成「1 1. 概述」

**原因**：Markdown 标题里已手写编号，同时又开了 `--number`。

**处理**：去掉 `--number`（`report` 预设默认就不编号），或把标题里的手写编号删掉。
`gb` 预设同理——一级标题只写章名，不要写「第一章」。

---

## 4. Word 输出

### 4.1 各级标题是蓝色

**现象**：Word 里 H1–H6 全是蓝灰色 `0F4761`，与「全文纯黑」的要求相悖。

**原因**：pandoc 自带的默认 `reference.docx` 里，`Heading1..9` 的 `w:rPr` 同时带着
`w:color` 和 `w:themeColor`：

```xml
<w:color w:val="0F4761" w:themeColor="accent1" w:themeShade="BF"/>
```

**`w:themeColor` 的优先级高于 `w:color`**。只把 `w:val` 改成 `000000` 而不删
`w:themeColor` 属性，Word 仍然按主题色渲染——看起来「改了没用」。

**处理**：`build-reference-docx.py` 生成母版时，把 `w:themeColor` / `w:themeShade`
/ `w:themeTint` 属性整个删掉再写 `w:color="000000"`；`docx-postprocess.py` 对
语法高亮的 31 个 `...Tok` 字符样式做同样的事。自己改母版时记住：**删属性，不是改值**。

### 4.2 页面是 US Letter 不是 A4

**现象**：Word 打开后页面偏宽偏短，版心和 PDF 对不上。

**原因**：pandoc 默认母版的 `sectPr` 里根本没有 `<w:pgSz>` 元素，Word 按区域设置
回落到 Letter。

**处理**：`docx-postprocess.py` 重写三个节（封面 / 前置 / 正文）的 `sectPr`，
显式写死 `w:w="11906" w:h="16838"`（A4，1cm = 567 twips）以及页边距、
页眉页脚距边界、页码格式。母版缺失时 `export.sh` 会打印
`! 未找到 …/reference-*.docx`，这时 A4 也保不住——先跑
`python3 scripts/build-reference-docx.py all`。

### 4.3 正文第一页前面多出一整张空白页

**现象**：Word 里目录之后是一张全白的页，再往后才是正文。

**原因**：两个换页机制叠加。`docx-postprocess.py` 在目录后插的是**分节符**
（`w:sectPr` + `w:type="nextPage"`），分节符本身就换页；`pagebreak.lua` 的
`front-break` 又在正文最前面插了一个显式分页符 `<w:br w:type="page"/>`。
一次换页变两次，中间夹出一张空白页。

PDF 侧不会有这个问题——LaTeX 的 `\clearpage` 在已经处于页首时是空操作，幂等。

**处理**：`export.sh` 的 `build_docx` 固定传 `-M front-break=false`。
如果你自己调 pandoc，导 docx 时记得关掉它。

### 4.4 LibreOffice 转出来的 PDF 里目录是空的

**现象**：`soffice --headless --convert-to pdf` 后，目录页只有「目　录」标题，
底下一条条目都没有。

**原因**：Word 目录是一个 `TOC` **域**（field），需要「更新域」才会填充内容。
LibreOffice 的 headless 转换不刷新域，只渲染域的缓存结果——而 pandoc 生成时缓存是空的。

**处理**：这不是缺陷，用 Word（或 WPS）打开就会自动填充——母版的
`settings.xml` 里已经设了 `<w:updateFields w:val="true"/>`，打开时会弹一次
「此文档包含可能引用其他文件的域，是否更新？」，选「是」。

所以 `soffice` 只适合看**版面**（页面尺寸、字号、页眉页脚、封面、表格线），
目录内容与页码要以 Word 为准。

### 4.5 `--footer-total` 的「共 M 页」比「第 N 页」大一截

**现象**：Word 里正文末页排出「第 9 页　共 11 页」——分子已经数到头了，
分母还多出两三页。PDF 侧同一份文档是正确的「第 9 页　共 9 页」。

**原因**：**分子和分母不是同一个口径。** 正文节的页码是从 1 重排的
（`w:pgNumType w:start="1"`，见 §4.2 的三节结构），`PAGE` 域给的是「正文第几页」；
而 `NUMPAGES` 域统计的是**整份文档**的物理页数，把封面节和目录节也算了进去。
差值恰好等于封面 + 目录的页数，目录越长偏得越多。

PDF 侧不会错，因为 `\pageref*{LastPage}` 取的是文末那一页的 `\thepage`，
而 `\thepage` 在正文节同样是从 1 重排的——分子分母天然同源。

**处理**：docx 侧改用 `SECTIONPAGES` 域（只统计当前节的页数），与 PDF 口径对齐。
已在 `docx-postprocess.py` 的 `footer_total_xml()` 中修正。

**副作用**：**LibreOffice 完全不实现 `SECTIONPAGES`**，`soffice` 转出的 PDF 会
原样显示域的缓存值（「共 1 页」）。这和 §4.4 目录为空是同一类限制——
`soffice` 只能用来看版面，**页码与目录一律以 Word/WPS 打开的结果为准**。

想自己验证某个域在 LibreOffice 下到底有没有被实现，把页脚临时换成
`PAGE=… NUMPAGES=… SECTIONPAGES=…` 并排放，转一次 PDF 看哪个还是缓存值即可。

### 4.6 页眉右上角是「错误!使用"开始"选项卡将 Heading 2 应用于…」

**现象**：Word 打开后，页眉右侧本该显示当前章节名的位置，排出一整句

> 错误!使用"开始"选项卡将 Heading 2 应用于要在此处显示的文字。

而这一页明明就有应用了 Heading 2 的标题。PDF 侧和 LibreOffice 转出的 PDF
都完全正常——**只有 Word 会错**。

**原因**：页眉的「当前标题」是个 `STYLEREF` 域，参数原先写的是**样式名**
`"Heading 2"`。中文版 Word 认的是本地化名「标题 2」，拿英文名去查匹配不到，
于是报这条「没有应用该样式的文字」。这条错误信息有误导性：它说的是「找不到」，
真实原因是「样式名没解析到」。

**处理**：改用**数字形式** `STYLEREF 2`——数字指的是内置标题级别，与界面语言
无关。已在 `build-reference-docx.py` 的 `STYLEREF_HEAD` 与
`docx-postprocess.py` 的 `patch_header_level()` 中修正。

四种写法实测（同一份文档，Word for Mac 简体中文 / LibreOffice 26.2）：

| 写法 | Word | LibreOffice |
|---|---|---|
| `STYLEREF "Heading 2"` | ✗ 报错 | ✓ |
| `STYLEREF "标题 2"` | ✓ | ✗ 引用源未找到 |
| `STYLEREF Heading2` | ✗ 报错 | ✓ |
| **`STYLEREF 2`** | **✓** | **✓** |

**只有数字形式两侧通吃**，别改回样式名，也别为了迁就某一侧写本地化名。
另外注意：给样式加 `w:aliases` 再按别名引用，Word 可以但 LibreOffice 不认，
同样不可用。

改完 `build-reference-docx.py` 后**必须重建母版**，否则改的只是生成器：

```bash
python3 ~/.claude/skills/paper-export/scripts/build-reference-docx.py all
```

### 4.7 Word 里中文变成西文字体 / 没有首行缩进

**原因**：`assets/reference-*.docx` 缺失，pandoc 回退到自带的西文母版。

**处理**：

```bash
python3 ~/.claude/skills/paper-export/scripts/build-reference-docx.py all
```

---

## 5. 字符、图形与字体

### 5.1 Mermaid 图不渲染，变成一段代码

**现象**：` ```mermaid ` 围栏在成品里成了一块等宽文字。

**原因**：pandoc 不认识 mermaid，任何带语言标注的围栏都按代码块处理。这条链路里
没有任何环节会去调 mermaid 渲染器。

**处理**：导出前自己渲染成图片再引用。

```bash
npm i -g @mermaid-js/mermaid-cli
mmdc -i flow.mmd -o img/flow.png -w 1600 -b white
```

```markdown
![数据流](img/flow.png){#fig:flow}
```

或者改画 ASCII 框图（见 5.3），中文技术文档里这种反而更耐排版。

### 5.2 彩色 emoji 不渲染 / 变成方块 / 消失了

**原因**：XeTeX 不支持 CBDT / sbix 彩色字体，Apple Color Emoji 这类字体的字形取不到。
不处理的话轻则缺字（`Missing character` 只在日志里），重则整段丢字。

**处理**：`sanitize.lua` 按 `--emoji` 的三种策略处理：

| 策略 | 行为 |
|---|---|
| `text`（默认） | 映射为等义文本符号：✅→`√` ❌→`×` ⚠️→`!` 🔴🟢🟡🔵→`●` ⭐→`★` ➡️→`→`；映射表里没有的彩色 emoji 一律换成 `*` |
| `strip` | 直接删除，不留痕迹 |
| `keep` | 原样保留。**只在你确认字体覆盖时用**，否则就是缺字 |

零宽字符与变体选择符（U+200B–200D、U+2060、U+FE0E/FE0F）在三种策略下都会被剔除
——它们没有字形，而且会让前一个符号被判定成彩色 emoji。

### 5.3 ASCII 框图对不齐 / 横线断断续续 / 框角丢失

**对齐的前提有三条**，缺一不可：

1. **源框图本身要在等宽终端里对齐**，即中文按 2 格计。用变宽字体编辑器画的框图
   在任何等宽渲染下都不可能对齐。
2. **CJK 等宽字体的字宽必须恰好是拉丁等宽的 2 倍**。`preamble-common.tex` 里
   `\setmonofont{Menlo}[Scale=0.85]` 与 `\setCJKmonofont{Songti SC}[Scale=1.02]`
   是配对的（Menlo 字身宽 0.6em，0.85 × 0.6 × 2 = 1.02）。换等宽字体必须重算这一对。
3. **框线字符的兜底字体缩放要与 `\setmonofont` 完全一致**。宋体和 Times 都不含
   Box Drawing 区段（U+2500–257F），`preamble-common.tex` 用
   `\newfontfamily\symbolfont{Menlo}[Scale=0.85]` 兜底——`Scale` 一旦与
   `\setmonofont` 不同，字身宽对不上，横线之间就露缝、框角接不拢。

另外替换体必须写码点而不是字符本身：

```tex
\newunicodechar{─}{{\symbolfont\char"2500\relax}}     % 对
\newunicodechar{─}{{\symbolfont ─}}                    % 错：active char 自指，字形丢失
```

**代码块里的框线要另外处理**。`\newunicodechar` 定义的是 active character，而
verbatim 环境里所有字符都是 catcode 12，active 不展开——围栏代码块里的框线走不到
上面那套兜底，会落到 `\setCJKmonofont`（宋体，全角宽）上，1 格宽的横线被排进 2 格，
框线断成一截一截。`preamble-common.tex` 用

```tex
\xeCJKDeclareCharClass{Default}{"2500 -> "259F}
```

把 Box Drawing 与 Block Elements 整段声明成「非 CJK」，它们才改走 Menlo、宽度恰好
1 格。自己扩用其他区段的符号时记得同步扩这一行。

### 5.4 框图被折行，出现 `↪` 续行符

**原因**：框图实际宽度超出版心，fvextra 按空格折了行。

**处理**：代码块已经是五号字并且 `breakanywhere=false`（只在空格处断）。仍放不下
说明源框图太宽，只能改窄，或把该页改成横向。

### 5.5 表格右侧出血 / `Overfull \hbox … in alignment`

**原因**：单元格里的长标识符不可断行，或列数太多。

**处理**：行内代码的断行 `sanitize.lua` 已在 AST 层自动加了 `\penalty100`。
仍溢出就减少列数、把长内容改成正文，或该表单独用横向页。溢出 3pt 以内肉眼不可见。

### 5.6 中文全变方块 / 标题看着比正文还小

**原因一**：字体没找到。先跑 `doctor.sh` 看字体那几项。

**原因二**：ctex 在 macOS 上默认把 `\heiti` 落到 STXihei（华文细黑），笔画细、字面小，
三号黑体标题的视觉重量反而不如小四宋体正文。`preamble-common.tex` 已经显式改绑
`Heiti SC Medium`。

**原因三**：层级映射错位。技术文档的 H1 是文档名、H2 才是一级标题，按 Markdown 层级
直接映射的话 H2 只能拿到四号、H3 与正文同号。`report` 预设整体上移一档解决。

**确认字号不要目测**，从日志读真实值：

```latex
\makeatletter\newcommand{\dg}[1]{\PackageWarningNoLine{DIAG}{#1=\f@size pt}}\makeatother
\ctexset{section/format=\heiti\zihao{2}\centering}
\section{一\protect\dg{H1}}
```

```bash
tectonic -X compile diag.tex --keep-logs && grep -A1 DIAG diag.log
```

LaTeX 命令名只能由字母组成，`\d1g` 这种带数字的名字会静默失效。

### 5.7 字体缺失时的表现与替代方案

缺字体的表现分两种：**XeTeX 找不到会直接编译中断**
（`fontspec error: font-not-found`），而**字体存在但缺某个字形只会静默丢字**——
日志里有 `Missing character: There is no X in font …`，成品里那个字就没了。
所以中文缺字务必看日志，别只看有没有报错。

本 skill 默认用的五个字体，以及在非 macOS 上的对应：

| 用途 | macOS（默认） | Windows | Linux |
|---|---|---|---|
| 正文宋体 | `Songti SC` | `SimSun` / `宋体` | `Noto Serif CJK SC` / `Source Han Serif SC` |
| 标题黑体 | `Heiti SC Medium` | `SimHei` / `黑体`（或 `Microsoft YaHei`） | `Noto Sans CJK SC` / `Source Han Sans SC` |
| 封面楷体 | `Kaiti SC` | `KaiTi` / `楷体` | `AR PL UKai CN` / 方正楷体 |
| 等宽与符号兜底 | `Menlo` | `Consolas` | `DejaVu Sans Mono` |
| 英文与数字 | 跟随当前中文字体 | 跟随当前中文字体 | 跟随当前中文字体 |

`Heiti SC Medium` 是**全名（fullname）**不是族名，族名是 `Heiti SC`——用
`fc-list : family` 查不到它，得查 `fullname`。`doctor.sh` 三个名字都查。

换字体要改两处，两处都改才能保持 PDF 与 Word 一致：

- PDF：`assets/preamble-common.tex` 的 `\setCJKfamilyfont{zhhei}{…}`
  / `\setCJKfamilyfont{zhsong}{…}` / `\setmonofont` / `\newfontfamily\symbolfont`
  （后两者的 `Scale` 必须相同，见 5.3）；普通英文和数字由同一字体命令同步切换。
- Word：`scripts/build-reference-docx.py` 顶部的 `CN_SERIF` / `CN_SANS` / `CN_KAI`
  / `MONO`，改完重新生成母版：

```bash
python3 ~/.claude/skills/paper-export/scripts/build-reference-docx.py all
```

Word 侧用的是 `宋体` / `黑体` / `楷体` 这种中文族名——跨平台 Word 都能解析，
不要换成 macOS 的 `Songti SC`。

### 5.8 有序列表编号不对：三级不是 ①，或二级不是 (1)

**现象一**：`preamble-common.tex` 里明明用 enumitem 设了「一级 `1.` / 二级 `(1)` /
三级 `①`」，PDF 里三级还是 `i.`、二级还是 `a.`。

**原因**：pandoc 只要看到列表带具体的 style / delim（Markdown 的 `1.` 会被解析成
`Decimal` + `Period`），就在 `\begin{enumerate}` 后面直接写死一行

```tex
\def\labelenumi{\arabic{enumi}.}
```

把 enumitem 的三级设定整个盖掉。

**处理**：`sanitize.lua` 的 `OrderedList` 钩子把 style 与 delim 还原成
`DefaultStyle` / `DefaultDelim`（保留 `start`），pandoc 就不再写那行，编号交回
enumitem。只对 LaTeX 做——Word 侧编号走 `numbering.xml`，与此无关。

**现象二**：三级编号是一串空方框而不是 ①②③。

**原因**：`Songti SC` 没有 U+2460 区段（`fc-list :charset=2460` 里查不到它），
`\songti\char"2460` 排出来就是缺字形的方框。

**处理**：`preamble-common.tex` 用 `\newfontfamily\pecirclefont{Heiti SC}` 单独绑一个
字体族给 `\pecircled`，绕开 xeCJK 的字符分类。换字体时注意：**目标字体必须含
U+2460–2473**，否则又是方框。

---

## 6. 可以忽略的噪音

下面这些出现在 tectonic 的输出里，**不影响成品**，不用管：

| 输出 | 说明 |
|---|---|
| `warning: lineno.sty:296: Invalid UTF-8 byte or sequence … replaced by U+FFFD` | `lineno.sty` 的注释里有个 Latin-1 字节。宏包本身正常工作 |
| `warning: Object @page.1 already defined.` | hyperref 给同一页注册了两次锚点（封面 `\setcounter{page}{1}` 所致）。PDF 书签和链接都正常 |
| `warning: accessing absolute path /System/Library/Fonts/…` | tectonic 提示「用了系统字体，换台机器可能不可复现」。macOS 上必然出现 |
| `Underfull \hbox (badness 10000)` | 已用 `\hbadness=10000` 抑制大部分；剩下的是中文两端对齐的正常现象 |

### 6.1 Tectonic 首次编译很慢 / `failure fetching … operation timed out`

**原因**：tectonic 不预装宏包，第一次编译要从 `relay.fullyjustified.net` 按需下载
ctex、fancyhdr、mdframed 等几十个包。**首次编译必须联网。**

**处理**：耐心等（首次约 1–2 分钟），成功后进本地缓存
（`~/Library/Caches/Tectonic`），之后同类文档约 3–6 秒。网络不通时 ctex 会加载失败，
表现为中文全部消失或直接中断。已经有缓存的机器可以离线编译。

装了 MacTeX / TeX Live 的话 `export.sh` 会优先用 `xelatex`
（探测顺序 `xelatex` → `lualatex` → `tectonic`），没有下载问题。
