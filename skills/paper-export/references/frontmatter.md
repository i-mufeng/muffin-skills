# 元数据：怎么给、给了之后落在哪

封面、页眉、文档属性用到的字段一共八个：
`title` `subtitle` `author` `org` `doc-no` `version` `security` `date`。

三种给法：命令行参数、Markdown YAML frontmatter、自动推断。下面的结论都是在
当前版本上实测的，含一个必须避开的坑（多行值与列表，见 §2.2）。

---

## 1. 优先级

```
命令行参数  >  第一个输入文件的 YAML frontmatter  >  自动推断
                                                    （title 取首个 H1，
                                                      再退到 --name / 文件名；
                                                      date 取今天）
```

**逐字段独立生效**：只给 `--title` 不会影响其余七个字段，它们照常从 frontmatter 取。
实测——frontmatter 里八个字段都写齐，命令行只给 `--title` `--org` `--date`，
封面上这三个用命令行的值，另外五个仍是 frontmatter 的值。

### 它是怎么做到的

pandoc 的 `-M key=value` **覆盖**文档内的 YAML。而 `export.sh` 组装参数时必须用
`-M title=...` 把标题传下去（封面、页眉、`title-dedup` 都要用），如果不管 YAML，
用户写在 frontmatter 里的值就永远被顶掉。

所以 `export.sh` 在组装 pandoc 参数**之前**先用 `read_fm()` 自己读一遍第一个输入
文件的 frontmatter，对八个字段逐个做「命令行为空就回填 frontmatter 值」，
之后才统一 `-M` 注入。三级优先级是在这一步落定的，不是靠 pandoc 自己的合并规则。

自动推断只有两条，都在回填之后才兜底：

- `title`：frontmatter 没有 → 第一个输入文件里第一行 `# ` 开头的标题 → 还没有就用
  `--name`（没给 `--name` 时是第一个 .md 的文件名；目录输入时是目录名）。
  **`title` 永远不会为空。**
- `date`：frontmatter 没有 → `date +%Y-%m-%d` 的今天。**也永远不会为空。**

其余六个字段没有推断，缺就整行省略。

---

## 2. frontmatter 的两个限制

### 2.1 只读第一个输入文件——但 pandoc 会偷偷合并其余的

`read_fm()` 只解析 `FIRST`，也就是第一个输入文件（目录输入时是 `LC_ALL=C` 排序后的
第一个 .md）。后续文件的 frontmatter 不参与优先级计算。

但 **pandoc 自己会把所有输入文件的 YAML 块合并成一份文档元数据**，而
`export.sh` 只在字段非空时才 `-M` 注入。于是出现一个不对称：

实测——`a.md` 写 `org`，`b.md` 写 `version` 和 `security`，合并导出：

| 输出 | 封面上出现的字段 |
|---|---|
| Word | `org`（来自 a.md）+ `version` `security`（**来自 b.md，渗进来了**） |
| PDF | 只有 `org`；`version` `security` 不出现 |

原因：Word 封面由 `cover-docx.lua` 直接读 `doc.meta`（pandoc 合并后的结果），
PDF 封面读的是 `export.sh` 生成的 `cover-vars.tex`（只认 `read_fm` + 命令行）。
`title` 和 `date` 因为被无条件 `-M` 注入，两侧都以第一个文件为准，不受影响。

**结论：合并多份文档时，把封面字段全部写到命令行，或者只在第一份里写 frontmatter、
其余各份不要留 YAML 块。**

### 2.2 `read_fm` 是简易解析，不是 YAML 解析器

它只做这些：

- frontmatter 必须是**文件最开头**的 `---` … `---`（或 `...`）块；
- 只认**顶格**的 `key: value` 单行形式，键名限 `[A-Za-z_][\w-]*`（`doc-no` 合法）；
- 值两端的成对引号（`"` 或 `'`）会被剥掉，前后空白会被 trim。

不支持的写法及其实际后果（都实测过）：

| 写法 | PDF 侧结果 | Word 侧结果 |
|---|---|---|
| `org: >` 或 `org: \|` 后接缩进的多行 | 封面单位名变成一个字面的 **`>`** 字符 | 同样是 `>` |
| `author:` 后接 `- 张三` / `- 李四` 列表 | 取到空值，**「编制人」整行消失** | pandoc 自己解析成列表，stringify 后拼成「张三李四」（无分隔符） |
| 缩进后的 `  title: x` | 取不到，退到首个 H1 | 同左 |

`#` 也不当注释处理（真 YAML 会），`doc-no: JXF-2026-#7` 会原样保留 `#7`——但 pandoc
自己那一遍 YAML 解析未必这么认为，两边可能不一致，尽量别在值里写 `#`。

**一句话：八个字段都写成一行纯文本，别用块标量、别用列表、别缩进。**

### 2.3 `subtitle` 走的是另一条路（已处理）

`subtitle` 与其余七个字段的注入方式不同，值得单独说一句——它曾经会让 PDF 封面上
副标题出现两遍，现在修好了。

`export.sh` 不把副标题放进公共参数：PDF 侧只经由 `cover-vars.tex` 的 `\pesubtitle`
给 `titlepage.tex` 自绘，Word 侧才单独传 `-M subtitle=` 给 `cover-docx.lua`。
但**光是「不传」挡不住写在文档 YAML 块里的那份**——pandoc 自己会读到它，
LaTeX 模板的 `$if(subtitle)$` 分支就把副标题拼进 `\title{... \\ {\large ...}}`，
与自绘的那份叠加成两遍，`\@title` 变两行后页眉也跟着变两行。

现在 `build_pdf` 显式传 `-M "subtitle="`，用空值让模板判假，模板那份不再生成。

实测（`title` `subtitle` `author` `org` `version` `security` 全写 frontmatter、
命令行什么都不给）：PDF 封面副标题只出现一次，页眉是单行的主标题，
信息栏各字段正常。命令行 `--subtitle` 与 frontmatter 同时存在时，命令行胜出，
也只出现一次。

**所以八个字段现在都可以放心写在 frontmatter 里。** 自己扩字段时记住这个教训：
凡是 pandoc 默认模板也认识的键（`subtitle` `institute` `thanks` `abstract`…），
自绘封面就得显式传空值把模板那份关掉，不能只靠「不传」。

---

## 3. 封面字段全表

封面从上到下：单位 → 主标题 → 副标题 → 分隔线 → 信息栏 → 日期。

| 字段 | 命令行 | 封面位置 | PDF | Word | 留空时 |
|---|---|---|---|---|---|
| `title` | `--title` | 上部居中，顶部留白 ≥15% 页高，一号黑体加粗 | 生效 | 生效 | 退到首个 H1 → 文件名，**不会为空** |
| `subtitle` | `--subtitle` | 主标题下方，三号黑体 | 生效（注入路径特殊，见 §2.3） | 生效 | 整行省略 |
| `org` | `--org` | 主标题上方，三号黑体 | 生效 | 生效 | 整行省略 |
| `doc-no` | `--doc-no` | 信息栏第 1 行「文档编号」 | 生效 | 生效 | 整行省略 |
| `version` | `--version` | 信息栏第 2 行「版本号」 | 生效 | 生效 | 整行省略 |
| `security` | `--security` | 信息栏第 3 行「密级」 | 生效 | 生效 | 整行省略 |
| `author` | `--author` | 信息栏第 4 行「编制人」 | 生效 | 生效 | 整行省略 |
| `date` | `--date` | 页面下部，三号宋体 | 生效 | 生效 | 退到今天，**不会为空** |

信息栏是「有几行画几行」，缺的字段不留空行；四行全缺时分隔线下方那块留白一起收掉，
日期位置不受影响（PDF 用 `\vfill`，Word 由 `cover-docx.lua` 按「日期中心落在页高
85%」反算）。

两侧的两处细微差异，知道即可：

- Word 封面会自动给副标题补破折号（`—— 一期工程 ——`），PDF 不补。想让 PDF 也有，
  自己写进 `--subtitle` 的值里。
- 信息栏标签 PDF 是「版本号」，Word 是「版　　本」。

`title` 除封面外还用在三处：report 预设的页眉左侧 / gb 预设前置节的页眉居中；
Word 文档属性；以及 `title-dedup.lua`——正文里第一个与 `title` **完全相同**的 H1
会被摘掉，避免封面、正文首页、目录三处重复。文中后续的同名标题不受影响。

`--name` 只决定输出文件名，与封面无关（只是 `title` 的最后兜底）。

**没有 python3 时 `read_fm` 直接返回空**——整个 frontmatter 回填失效，退化成
「命令行 > 首个 H1 / 今天」。`doctor.sh` 会把 python3 报成必需项缺失。

---

## 4. 影响排版的元数据

这些键由 `export.sh` 根据命令行选项注入，一般不需要自己写。列在这里是为了让你在读
`.tex` 中间产物或调 filter 时知道它们从哪来、默认值是多少。注意它们**不走**上面那套
三级优先级——`read_fm` 只回填封面那八个字段。

| 键 | 取值 | 默认 | 消费者 | frontmatter 能不能改 |
|---|---|---|---|---|
| `break-level` | `auto` `0` `1` `2` `3`（也认 `h1` `none` `off` `false`） | `auto` | `pagebreak.lua` | 不能，`export.sh` 无条件注入解析后的值；用 `--break-level` |
| `front-break` | `true` / `false` | `true` | `pagebreak.lua` | PDF 侧能；Word 侧被强制为 `false` |
| `table-fit` | `true` / `false` | `true` | `tablefit.lua` | 能（filter 载入时空转）；`--no-table-fit` 时 filter 根本不加载 |
| `table-rule` | `auto` `three` `grid` | `auto` | `tablefit.lua` + `docx-postprocess.py` | 不能，用 `--table-rule` |
| `table-line-units` | 正整数 | `80` | `tablefit.lua` | 不能，`export.sh` 写死 80；要改改脚本里的 `TABLE_LINE_UNITS` |
| `table-head-bold` | `true` / `false` | `true` | `tablefit.lua` | **能，且是唯一入口**（没有对应命令行选项） |
| `table-head-fill` | `0` / `1` | `0` | `tablefit.lua`（只读不实现） | 不能，用 `--table-head-fill`——但目前两侧都没实现底纹，见下 |
| `emoji` | `text` `strip` `keep` | `text` | `sanitize.lua` | 不能，用 `--emoji` |
| `toc-title` | 字符串 | `目　录` | pandoc LaTeX 模板 / docx writer | 不能，`export.sh` 写死 |
| `code-color` | `0` / `1` | `0` | 当前无消费者（预留） | 不能；真正起作用的是 `--code-color` |

几个需要说清楚的：

**`break-level` 的 auto**。`export.sh` 先数正文里的 H1：≥2 个 → 按 H1 分页；
≤1 个 → 按 H2 分页。因为单个 H1 会被 `title-dedup.lua` 摘去当文档名，
`## 一、概述`「## 二、…」才是真正的一级标题。gb 预设恒为 `0`——`\chapter` 自带分页。
页眉右侧取哪一级标题也跟着这个值走。

**`front-break` 在 Word 侧强制关闭**。Word 的「目录后另起一页」靠
`docx-postprocess.py` 插的分节符，分节符本身就换页；`pagebreak.lua` 再插一个分页符
会在正文第一页前多出一整张空白页。PDF 侧不存在这个问题（`\clearpage` 幂等）。

**`table-rule` 的 auto**。判据是「该表有没有单元格会折行」——单元格显示宽度超过
`table-line-units × 该列宽度占比` 就算会折。会折就在行间加一道 0.3pt 的浅灰线
（`D0D0D0`），不会折就保持纯三线表。`three` / `grid` 强制其一。

**`table-head-fill` 目前是空开关**。`tablefit.lua` 读了就丢；`preamble-common.tex`
定义了 `ptablehead` 颜色但没用；Word 母版里有个 `TableFilled` 备用样式，但没有开关
把表格切过去。传了不会报错，也不会有可见变化——国标三线表本来就不要底纹。

**`code-color` 只影响 PDF**。默认单色（`--syntax-highlighting monochrome`），
`--code-color` 把它换成 `tango`。Word 侧无论怎么设，`docx-postprocess.py` 都会把
31 个 `...Tok` 字符样式的颜色压成纯黑（SPEC §3 要求全文黑色），只保留粗体/斜体的区分。

---

## 5. 两个完整例子

### 例一：纯命令行

Markdown 里什么都不用写，第一行给个 H1 当标题即可：

```markdown
# H5 金服页面功能梳理

## 一、背景

……
```

```bash
bash ~/.claude/skills/paper-export/scripts/export.sh \
  H5金服页面功能梳理.md \
  --to both \
  --style report \
  --title "H5 金服页面功能梳理" \
  --subtitle "V1.2 评审稿" \
  --org "XX 科技股份有限公司" \
  --author "沐风" \
  --doc-no "JXF-REQ-2026-007" \
  --version "V1.2" \
  --security "内部" \
  --date "2026-08-04" \
  --toc-depth 3 \
  --break-level auto \
  --table-rule auto \
  --out ./dist --name H5金服页面功能梳理
```

### 例二：YAML frontmatter

八个字段全写在文档里，命令行只留输出选项：

```markdown
---
title: H5 金服页面功能梳理
subtitle: V1.2 评审稿
author: 沐风
org: XX 科技股份有限公司
doc-no: JXF-REQ-2026-007
version: V1.2
security: 内部
date: 2026-08-04
table-head-bold: true      # 这个键没有命令行选项，只能写在这里
bibliography: refs.bib
csl: assets/gb-t-7714-2015-numeric.csl
---

## 一、背景

……
```

```bash
bash ~/.claude/skills/paper-export/scripts/export.sh H5金服页面功能梳理.md --to both
```

想临时改某一个字段，命令行单独覆盖它即可，其余仍从 frontmatter 取：

```bash
bash ~/.claude/skills/paper-export/scripts/export.sh H5金服页面功能梳理.md \
  --to both --version V1.3 --date 2026-08-10
```

---

## 6. 参考文献

frontmatter 的 `bibliography` / `csl` 两侧都正常生效（`export.sh` 不碰这两个键，
由 pandoc 自己读）。也可以用命令行：

```bash
--bib refs.bib --csl assets/gb-t-7714-2015-numeric.csl
```

`gb` 预设在 `assets/gb-t-7714-2015-numeric.csl` 存在时自动套用 GB/T 7714-2015
顺序编码制；文件不在就用 pandoc 默认样式。安装命令见 `scripts/doctor.sh` 的提示。

正文引用写 `[@zhang2024]`、`[@zhang2024, 45]`、`[@a; @b]`。PDF 与 Word 都走
citeproc，两侧样式完全一致。

## 7. 图表与交叉引用

需要 `pandoc-crossref`（`doctor.sh` 会检查；没装时 `@fig:` 会原样输出）。

```markdown
![火线识别流程](img/flow.png){#fig:flow}

如 @fig:flow 所示，算法分三步。

: 对外端口清单 {#tbl:ports}

| 端口 | 用途 |
|---|---|
| 8080 | 大屏 |

端口分配见 @tbl:ports。

$$ E = mc^2 $$ {#eq:mass}

由 @eq:mass 可得……
```

编号格式（`图 1-1` 还是 `图 1`）由预设决定，配置在 `assets/crossref-gb.yaml`
与 `assets/crossref-report.yaml`。

## 8. 图片路径

相对路径以**第一个输入文件所在目录**为基准解析（`--resource-path` 里还加了当前
工作目录做兜底）；合并整个目录时以该目录为基准。SVG 需要 `rsvg-convert`。
`md-lint.py` 会在图片文件不存在时给 warn。
