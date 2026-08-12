# 排版规范实现细节

本文件记录 paper-export **产出成品长什么样**，以及这些效果落在哪个文件里。
写 Markdown 时要遵守的约定不在这里，在 `SKILL.md` —— 那些是每次写文档都
用得上的，所以刻意留在主文件里。这里的内容只在两种时候需要：核对产出是否
合规、或者要改版式。

---

## 1. 版面

A4，上下边距 2.54cm，右边距 2.54cm，左边距 3.0cm（gb 为 3.17cm，留装订线）。
页眉距边界 1.5cm，页脚距边界约 1.75cm。

brief 走公文版心：上 37mm / 下 35mm / 左 28mm / 右 26mm。

## 2. 字号与字体（report 预设）

| 元素 | 字号 | 字体 |
|---|---|---|
| 封面主标题 | 一号 26pt | 黑体 |
| 封面副标题 | 三号 16pt | 黑体 |
| 封面信息栏 | 小三 15pt | 楷体 |
| 目录标题「目　录」/ H1 | 三号 16pt 居中 | 黑体 |
| H2（规范一级标题） | 小三 15pt | 黑体 |
| H3 | 13pt | 黑体 |
| H4 | 小四 12pt | 黑体 |
| H5 | 小四 12pt 加粗 | 宋体 |
| 正文 | 小四 12pt，行距 1.5，首行缩进 2 字符 | 宋体 |
| 表格 / 题注 | 五号 10.5pt，行距 1.0 | 宋体（表头黑体加粗） |
| 页眉页脚 | 小五 9pt | 宋体 |

gb 预设：章 三号黑体居中、节 四号黑体、条/款 小四黑体，正文同上。

字号刻意逐级拉开。ctex 在 macOS 上默认把 `\heiti` 落到 STXihei（华文细黑），
笔画细、字面小，会让三号标题看起来比正文还弱 —— 已显式改绑 `Heiti SC Medium`。

**modern 与 report 只差字体**：版面、标题层级、页眉页脚、目录全部复用
`preamble-report.tex` 与 `reference-report` 那一套逻辑，`preamble-modern.tex`
只在其后覆盖字体族。改版面改 report 即可，两套同步生效。

**为什么 modern/report 的标题要偏移一档**：技术文档里 H1 通常是文档名（会被
摘到封面），作者写的「## 一、概述」才是规范意义上的一级标题。brief 沿用同一套
偏移，gb 预设不做这个偏移。

## 3. 颜色实现

一切文字纯黑：标题、正文、目录（含条目与页码）、页眉页脚、题注、表格、代码、
列表符号。超链接默认也是黑色（打印友好），`--links color` 才转深蓝。
代码块默认单色高亮，`--code-color` 才启用彩色。

允许的非黑仅三处：

| 位置 | 色值 |
|---|---|
| 代码块底色 | `F7F7F8` |
| 引用块左侧竖条 | `BFBFBF` |
| 表格行间分界线 | `D0D0D0` |

图片本身不受限。语义标签的配色见 SKILL.md 的标签表 —— 那张表写 Markdown 时
就要用，所以留在主文件。

## 4. 表格视觉

- **三线表**：顶线/底线 0.9pt 纯黑，表头下线 0.4pt 纯黑，**无竖线**。
- **行间分界线按内容密度自动加**（`--table-rule auto`，默认）：
  任一单元格会折行 → 行间加 0.3pt `D0D0D0` 浅灰细线；全是短词 → 保持纯三线表。
  分界线刻意比结构线细得多、浅得多，否则整张表退化成网格反而更吵。
  `--table-rule three` 强制纯三线表，`grid` 强制全部加线。
- 表格水平居中，宽度撑满版心；表头黑体加粗居中；跨页自动重复表头。
- **列宽按内容重算**，不用 Markdown 分隔行的长度（那会把长文本列挤成四行、
  短列留一大片白）。纯数字列右对齐，最宽不超过 8 个显示宽度的窄列居中。
- 列宽按「CJK=2 / 西文=1」估算，不是真实字体度量，比例可靠、绝对值有偏差。
  这份显示宽度表在 `assets/tablefit.lua` 与 `scripts/md-lint.py` 里各有一份，
  **必须保持一致** —— 不一致会导致 lint 说没超宽而实际排出来溢出。

## 5. 列表

无序 `•` / `–` / `·`，有序 `1.` / `(1)` / `①`。左缩进与正文首行对齐，
项间紧凑，列表内不再首行缩进。

## 6. 页眉页脚与页码分节

文档分三节，页码独立：

| 节 | 页眉 | 页脚 | 页码 |
|---|---|---|---|
| 封面 | 无 | 无 | 不计数、不显示 |
| 前置（目录） | 横线 + 文档标题**居中** | 居中 | 大写罗马 I、II |
| 正文 | 横线 + 左文档标题 + 右当前一级标题 | 居中 | 阿拉伯，**从 1 重新开始** |

`--footer-total` 可把页脚换成「第 N 页 共 M 页」。PDF 与 Word 两侧一致。

页眉右侧取哪一级标题跟随分页级别：按 H2 分页时取 H2，否则取 H1；gb 恒为章。

brief 没有页眉、页脚、页码，单节。

## 7. 封面

从上到下：顶部留白（≥15% 页高，主标题绝不贴顶）→ 单位名 → 主标题（一号黑体）
→ 副标题 → 分隔线 → 信息栏（文档编号/版本号/密级/编制人，标签两端对齐并相对
中线略向左）→ 弹性留白 → **日期（页面下部约 85% 处）** → 底部留白。

未提供的字段整行省略，不留空行。封面标题默认取第一个 H1，此时正文里那个 H1
会被自动摘掉，避免封面、正文、目录三处重复。

brief 不排封面，走「文头 + 落款」：二号黑体标题居中、三号楷体副标题、
1.2pt + 0.4pt 双分隔线；文末右下角落款（单位 / 编制人 / 中文日期），距右 4 字宽。

## 8. 分页

- 封面独占一页，目录独占。
- **长文档的一级标题之间必然换页**。`--break-level auto`（默认）会自己判断：
  正文里 H1 有两个以上 → 按 H1 分页；只有一个 H1（被当作文档名摘到封面了）
  → **按 H2 分页**。`--break-level 0` 关闭，`1|2|3` 指定级别。
- 标题后至少留 4 行正文，杜绝标题孤零零挂在页面末行；标题紧跟表格时，
  标题与表头保证同页。
- 段落孤行寡行全部抑制；表格跨页重复表头。
- gb 的 `\chapter` 自带分页，`--break-level` 恒为 0。

---

## 字体来源与安装

| 用途 | 字体 | 来源 |
|---|---|---|
| modern 正文 / 标题 / 四级标题 | 阿里巴巴普惠体 3.0 的 55 / 85 / 65 | 免费商用，需手动装 |
| report、gb 正文 | Songti SC | macOS 自带 |
| report、gb 标题 | Heiti SC Medium | macOS 自带 |
| brief 正文 | Noto Serif CJK SC Regular（回退普惠体/仿宋） | 免费商用，独立 OTF 可嵌入 PDF |
| brief 文头大标题 | Noto Serif CJK SC Black | `brew install --cask font-noto-serif-cjk-sc` |
| 代码块 / ASCII 框图 | Maple Mono CN | 免费开源，需手动装 |

普通文本里的英文与数字跟随当前中文字体，不再单独切换 Arial 或 Times New Roman；
标题、封面信息栏和正文会分别使用各自中文字体自带的西文字形。代码块为了保持
中英文 2:1 等宽对齐，仍独立使用 Maple Mono CN。

手动装的那几个：把 `.otf`/`.ttf` 拷进 `~/Library/Fonts/`，再 `fc-cache -f`。
全部缺失时都有回退（普惠体→宋体、思源宋体→宋体伪粗、Maple→Menlo+宋体），
只是观感降一档，不会编译失败。`scripts/doctor.sh` 会逐个列出在位情况。

### 在 preamble 里写字体名的两个坑

都表现为「编译不报错但排出豆腐块」：

1. **多字重字体必须用 PostScript 名**。`AlibabaPuHuiTi_3_55_Regular` 可以，
   fontconfig 显示的家族名 `Alibaba PuHuiTi 3.0 55 Regular` 不行 ——
   tectonic 的字体索引按家族名查不到，会报 font cannot be found。
2. **字体集合（.ttc）里的非首 face 取不到**。macOS 的 Songti SC 确实带
   Black 字重，但它藏在 `Songti.ttc` 里，三种写法（family+BoldFont、全名、
   PostScript 名）实测全部落空 —— 这就是 brief 文头改用思源宋体的原因。
   对比 `Heiti SC Medium` 能用，因为它是独立的 `.ttf`。

Word 侧相反：`rFonts` 要写 **name ID 1**，也就是带字重后缀的
`Alibaba PuHuiTi 3.0 85 Bold`；只写 `Alibaba PuHuiTi 3.0` 会落到 Regular，
Bold 变成 Word 自己描边的伪粗。

---

## 文件职责

```
assets/
  preamble-common.tex    字体、符号兜底、表格、列表、代码块、分页质量
  preamble-report.tex    技术报告版式：页面、标题层级、页眉页脚、目录
  preamble-modern.tex    modern 的字体覆盖层（叠在 report 之上，版式不动）
  preamble-modern-plain.tex modern-plain 的无封面行内标题层
  preamble-gb.tex        学位论文版式
  preamble-brief.tex     简报版式：公文版心、仿宋三号、无页眉页脚
  titlepage.tex          封面（PDF 侧）
  masthead-brief.tex     简报文头：标题 + 副标题 + 双分隔线（PDF 侧）
  signoff-brief.tex      简报落款：单位 / 编制人 / 日期（PDF 侧）
  before-body.tex        封面节 → 前置节的切换
  sanitize.lua           Unicode 清洗 + 行内代码断行
  semantic-markers.lua   待确认 / 需补充 / 建议方案语义标签（PDF 着色）
  title-dedup.lua        正文里与封面重名的首个 H1 摘除
  tablefit.lua           表格列宽重算 + 表头加粗 + 行间分界线
  pagebreak.lua          按级别分页
  cover-docx.lua         封面 / brief 文头与落款（Word 侧，直接写 OpenXML）
  crossref-*.yaml        图表编号格式
  reference-*.docx       Word 母版（由 scripts/build-reference-docx.py 生成）
scripts/
  export.sh              导出入口
  doctor.sh              依赖与字体自检
  md-lint.py             Markdown 体检
  build-reference-docx.py 重新生成 Word 母版（改版式后需重跑）
  docx-postprocess.py    Word 分节、页眉页脚、页码、表格线型、语义标签着色
references/
  frontmatter.md         元数据字段与优先级
  typography.md          本文件：排版规范实现细节
  troubleshooting.md     报错对照表与机理
```

lua filter 的调用顺序在 `scripts/export.sh` 的 `COMMON` 数组与
`build_pdf` / `build_docx` 里：sanitize → title-dedup → pagebreak →
semantic-markers → tablefit，Word 侧末尾再追加 cover-docx。
顺序有依赖，改之前先看那两处的注释。

PDF 侧 preamble 的注入顺序同样有依赖：cover-vars（`\def` 落定字段值）→
preamble-common（颜色与 `\pecircled`）→ preamble-`<style>`（版式）→
preamble-modern（仅 modern，字体覆盖，必须在 report 之后）→
titlepage（用前面全部组装封面）。
