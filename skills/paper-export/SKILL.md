---
name: paper-export
description: 把 Markdown 导出为符合国内技术文档/论文规范的 PDF 或 Word（Pandoc + XeLaTeX/Tectonic）。五套预设：modern、modern-plain（无封面目录）、report、gb、brief。当用户要把 md 文档「导出 PDF」「转成 Word」「生成交付文档/需求文档/论文/报告/简报/通报/会议纪要」，或需要封面、目录、页眉页脚、图表编号、参考文献等正式排版时使用。支持单文件与整目录合并成册。
---

# Markdown → PDF / Word 规范级排版

用 Pandoc + LaTeX 把 Markdown 排成可直接交付评审的 PDF 或 Word。
五套预设：默认（阿里巴巴普惠体）、无封面现代技术稿、技术报告（宋体）、
学位论文（GB/T 7714）、简报通报（GB/T 9704 观感）。

## 快速开始

```bash
# 什么都不指定就是 modern：版式同 report，正文用阿里巴巴普惠体
scripts/export.sh 需求文档.md --to both \
  --subtitle "需求评审稿" --org "XX科技有限公司" \
  --author "张三" --version V1.0 --security 内部

# 简报 / 通报 / 会议纪要：一个 --style brief 就够了
scripts/export.sh 会议记录.md --style brief --to both \
  --title "2026年8月5日会议内容简报" --subtitle "项目管理模块" \
  --org "XX科技有限公司" --author "张三"

# 要交付纸质正式件 —— 同样版式，正文换回宋体
scripts/export.sh 需求文档.md --style report --to pdf

# 现代技术稿：复用 modern 字体与 report 版式，无封面、无目录、不主动换页
scripts/export.sh 技术稿.md --style modern-plain --to pdf

# 学位论文
scripts/export.sh 论文.md --style gb --to pdf

# 整个目录合并成一本
scripts/export.sh ./docs/交付文档 --name 交付文档 --title "系统交付文档" --to both
```

目录输入按**文件名自然序**合并（`1-` `2-` `10-`，不是字节序的 `1-` `10-` `2-`），
并在导出前把实际顺序逐个打印出来 —— 顺序错了要在这里发现，不是在成品里。

首次使用或报错时先自检：`scripts/doctor.sh`（`--install` 可自动补装）。

## 五套预设怎么选

| | `--style modern`（默认） | `--style modern-plain` | `--style report` | `--style gb` | `--style brief` |
|---|---|---|---|---|---|
| 适用 | 日常技术文档 | 简洁技术稿 | 纸质正式件 | 中文论文 | 简报、通报 |
| 正文字体 | 阿里巴巴普惠体 55 | 同 modern | 宋体小四 | 宋体小四 | 仿宋三号 |
| 首页 | 独立封面页 | **标题直接接正文** | 独立封面页 | 独立封面页 | 文头直接接正文 |
| 目录 | 有 | **无** | 有 | 有 | 无 |
| 页眉页脚 | 有 | 有 | 有 | 有 | 无 |
| 分页 | 一级标题前换页 | **不主动分页** | 一级标题前换页 | 每章换页 | 不主动分页 |

**modern 与 report 只差字体**：版面、标题层级、页眉页脚、目录全部复用
`preamble-report.tex` 与 `reference-report` 那一套逻辑，`preamble-modern.tex`
只在其后覆盖字体族。改版面改 report 即可，两套同步生效。

**为什么 modern/report 要偏移一档**：技术文档里 H1 通常是文档名（会被摘到封面），
作者写的「## 一、概述」才是规范意义上的一级标题。brief 沿用同一套偏移，
gb 预设不做这个偏移。

### brief 预设（简报 / 通报）

参照《党政机关公文格式》GB/T 9704-2012 的观感做的简化版。版面长这样：

```
              2026年8月5日会议内容简报          ← 二号黑体居中
                 —— 项目管理模块 ——             ← 三号楷体居中，可选
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━     ← 1.2pt
        ───────────────────────────────────     ← 0.4pt
          一、项目管理模块需求                   ← H2，三号黑体
          （一）组织架构体系                     ← H3，三号楷体
          1. 具体条款                            ← H4，三号仿宋加粗
          　　正文正文正文……                    ← 三号仿宋，首行缩进 2 字

                              微航科技有限公司   ← 落款，距右 4 字宽
                              编制：张三
                              2026 年 8 月 5 日
```

字段映射与其他两套不同，注意：

- `--org` 走**落款**而不是标题上方。想让单位名也印在文头，加 `--masthead-org`。
- `--author` 落款里显示成「编制：张三」。
- `--date` 会自动中文化成「2026 年 8 月 5 日」放在落款末行；
  自己写成别的格式（如「二〇二六年八月」）则原样保留。
- `--doc-no` / `--version` / `--security` / `--footer-total` / `--toc*` /
  `--break-level` **一律忽略**，并在导出时明确告知 —— 简报不排这些东西。

---

# 排版规范

以下是本 skill 产出文档所遵循的规范，也是**写 Markdown 时应当遵守的约定**。

## 1. 版面

A4，上下边距 2.54cm，右边距 2.54cm，左边距 3.0cm（gb 为 3.17cm，留装订线）。
页眉距边界 1.5cm，页脚距边界约 1.75cm。

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

## 3. 颜色

**一切文字纯黑**：标题、正文、目录（含条目与页码）、页眉页脚、题注、表格、
代码、列表符号。超链接默认也是黑色（打印友好），`--links color` 才转深蓝。
代码块默认单色高亮，`--code-color` 才启用彩色。

允许的非黑仅三处：代码块底色 `F7F7F8`、引用块左侧竖条 `BFBFBF`、
表格行间分界线 `D0D0D0`。图片本身不受限。需求评审稿还允许使用下述固定的
语义标签；只有标签本身着色，后续正文保持黑色：

| 语义标签 | Markdown 写法 | 字体色 | 背景色 |
|---|---|---|---|
| 待确认 | `[【待确认】]{.mark-confirm}` | 深红 `C00000` | 浅红 `FCE8E6` |
| 需补充 | `[【需补充】]{.mark-supplement}` | 深红 `C00000` | 浅红 `FCE8E6` |
| 建议方案 | `[【建议方案】]{.mark-suggestion}` | 深蓝 `1F4E78` | 浅蓝 `DDEBF7` |
| 对抗意见 | `[【对抗意见】]{.mark-adversarial}` | 深红 `C00000` | 浅红 `FCE8E6` |
| 建议暂缓 | `[【建议暂缓】]{.mark-defer}` | 深红 `C00000` | 浅红 `FCE8E6` |
| 建议剔除 | `[【建议剔除】]{.mark-reject}` | 深红 `C00000` | 浅红 `FCE8E6` |

语义标签的文字和类名必须成对使用，不要把整句话放进 Span。例如：

```markdown
[【待确认】]{.mark-confirm} 项目暂停超过多少天后升级提醒。
[【需补充】]{.mark-supplement} 请提供现行审批表单和制度文件。
[【建议方案】]{.mark-suggestion} 采用“发起、处理、复核、解除”的风险闭环。
[【对抗意见】]{.mark-adversarial} 当前指标口径不足，不能直接用于对外展示。
[【建议暂缓】]{.mark-defer} 待数据基础和投入产出验证后再纳入建设。
[【建议剔除】]{.mark-reject} 当前阶段不建议进入对外展示。
```

## 4. 表格规范

### 视觉
- **三线表**：顶线/底线 0.9pt 纯黑，表头下线 0.4pt 纯黑，**无竖线**。
- **行间分界线按内容密度自动加**（`--table-rule auto`，默认）：
  任一单元格会折行 → 行间加 0.3pt `D0D0D0` 浅灰细线；全是短词 → 保持纯三线表。
  分界线刻意比结构线细得多、浅得多，否则整张表退化成网格反而更吵。
  `--table-rule three` 强制纯三线表，`grid` 强制全部加线。
- 表格水平居中，宽度撑满版心；表头黑体加粗居中；跨页自动重复表头。
- **列宽按内容重算**，不用 Markdown 分隔行的长度（那会把长文本列挤成四行、
  短列留一大片白）。纯数字列右对齐，最宽不超过 8 个显示宽度的窄列居中。

### 内容（写 Markdown 时必须遵守）
- **单元格不得放大段文字。** 上限 40 个显示宽度单位（≈20 汉字）为宜，
  **超过 80（≈40 汉字）`md-lint` 会报 error**。超了就改成正文段落、
  列表，或把这一列拆成两列。
  > 表格是用来做「横向对比」的，不是用来装叙述的。一段话塞进单元格，
  > 既读不了也排不好 —— 列宽算法只能保证它不吃掉别的列，救不了它自己。
- 列数不超过 6。超了拆表，或改写成「字段说明列表」。
- 单元格内不放多个段落、不放代码块、不放列表。
- 不要用表格做两栏排版。
- 表格应有表题：`: 端口清单 {#tbl:ports}`，正文用 `@tbl:ports` 引用。

## 5. 列表

无序 `•` / `–` / `·`，有序 `1.` / `(1)` / `①`。左缩进与正文首行对齐，
项间紧凑，列表内不再首行缩进。三级以上建议改用带小标题的段落。

## 6. 页眉页脚与页码分节

文档分三节，页码独立：

| 节 | 页眉 | 页脚 | 页码 |
|---|---|---|---|
| 封面 | 无 | 无 | 不计数、不显示 |
| 前置（目录） | 横线 + 文档标题**居中** | 居中 | 大写罗马 I、II |
| 正文 | 横线 + 左文档标题 + 右当前一级标题 | 居中 | 阿拉伯，**从 1 重新开始** |

`--footer-total` 可把页脚换成「第 N 页 共 M 页」。PDF 与 Word 两侧一致。

## 7. 封面

从上到下：顶部留白（≥15% 页高，主标题绝不贴顶）→ 单位名 → 主标题（一号黑体）
→ 副标题 → 分隔线 → 信息栏（文档编号/版本号/密级/编制人，标签两端对齐并相对中线略向左）
→ 弹性留白 → **日期（页面下部约 85% 处）** → 底部留白。

未提供的字段整行省略，不留空行。封面标题默认取第一个 H1，此时正文里那个 H1
会被自动摘掉，避免封面、正文、目录三处重复。

## 8. 分页

- 封面独占一页，目录独占。
- **长文档的一级标题之间必然换页**。`--break-level auto`（默认）会自己判断：
  正文里 H1 有两个以上 → 按 H1 分页；只有一个 H1（被当作文档名摘到封面了）
  → **按 H2 分页**。`--break-level 0` 关闭，`1|2|3` 指定级别。
- 标题后至少留 4 行正文，杜绝标题孤零零挂在页面末行；标题紧跟表格时，
  标题与表头保证同页。
- 段落孤行寡行全部抑制；表格跨页重复表头。

---

## 写 Markdown 时的约定

**标题、表格、列表、代码围栏前后都要留空行。** 这不是洁癖：

> `## 四、待确认事项` 紧跟上一段没有空行时，pandoc 会把它**并进上一段**。
> 导出后目录里少一整章，正文里出现字面的「## 四、待确认事项」，
> 而编译不报任何错。这是长文档最容易中招、又最难发现的事故。

本 skill 已关掉 `blank_before_header`（缺空行也能识别为标题），并且每次导出前
自动跑 `scripts/md-lint.py` 把这类问题**报出来**。导出时只展开 error（会实际
改变导出结果的问题），警告折叠成计数；`md-lint.py 文件 --verbose` 看全部，
`--strict-lint` 让 error 直接中止导出。

**元数据**：可选。写在 YAML frontmatter 里，也可以完全不写 ——
命令行参数优先级更高。字段说明见 `references/frontmatter.md`。

```yaml
---
title: 系统需求规格说明书
subtitle: V1.0 评审稿
author: 张三
org: XX科技有限公司
version: V1.0
security: 内部
date: 2026-08-04
---
```

**图表与交叉引用**（需要 pandoc-crossref）：

```markdown
![火线识别流程](img/flow.png){#fig:flow}
如 @fig:flow 所示……

: 端口清单 {#tbl:ports}

| 端口 | 用途 |
|---|---|
```

### SVG 嵌入与兼容方案

含中文文字、流程框或复杂排版的 SVG，默认采用“**SVG 源图 + PNG 成册图**”双轨方案：

1. 在文档的 `assets/` 目录保留同名 `.svg` 作为可编辑、可追溯的源图。
2. 用 `rsvg-convert` 将 SVG 渲染为高分辨率、白色背景的同名 `.png`；PNG 宽度建议
   至少为最终版面显示宽度的 2 倍。
3. Markdown 正文引用 PNG，PDF 与 Word 共用同一个成册图；交付时同时保留 SVG。

```text
assets/
  lifecycle.svg    # 可编辑源图
  lifecycle.png    # Word/PDF 实际嵌入图
```

```bash
rsvg-convert --keep-aspect-ratio --width 2400 \
  --background-color white \
  --output assets/lifecycle.png assets/lifecycle.svg
```

```markdown
![工程项目全生命周期主线](assets/lifecycle.png){#fig:lifecycle width=90%}
```

不要把带文字的 SVG 直接作为 Word/PDF 的默认输入。不同转换器和办公软件可能替换字体、
改变文字度量或裁剪 `clipPath`，造成文字超出框体、被截断或不可见。只有纯图形、图标等
不含关键文字的简单 SVG，且 PDF 与 Word 两侧均已验证时，才可直接引用
`![图名](assets/name.svg){#fig:name}`；直接引用前运行 `scripts/doctor.sh`，确认
`rsvg-convert` 可用。

绘制和检查 SVG 时遵守以下要求：

- 设置完整的 `viewBox`，并让所有图形、连线和文字位于其范围内；不要依赖页面外元素。
- 不使用 `<foreignObject>`、远程字体或远程图片；中文字体提供可用的本机回退字体。
- 不依赖 SVG 自动换行。长文字用多个 `<tspan>` 显式分行，并同步扩大框体或行高。
- 给文字与边框保留明显内边距，重点检查最长标题、括号内容、英文和数字组合。
- 先检查 SVG 原图和转换后的 PNG，再分别检查 PDF 页面以及 Word 渲染页面；确认无文字
  溢出、遮挡、裁剪、缺字、比例失真和模糊后才交付。

**参考文献**：`--bib refs.bib`，正文里 `[@zhang2024]`。PDF 与 Word 共用
citeproc，两侧样式完全一致；gb 预设自动套 GB/T 7714 —— 前提是
`assets/gb-t-7714-2015-numeric.csl` 在位（不随 skill 分发，`scripts/doctor.sh
--install` 补装）。缺了会退回 pandoc 默认样式，导出时会明确提示，不静默降级。

## 常用选项

```
--to pdf|docx|both          输出格式（默认 pdf）
--style modern|modern-plain|report|gb|brief   排版预设（默认 modern）
--title / --subtitle / --org / --author
--doc-no / --version / --security / --date     封面字段（brief 只用 org/author/date）
--masthead-org              brief：单位名也印在文头（默认只在落款）
--toc / --no-toc            目录（默认生成）
--toc-depth N               目录收录层级（默认 3）
--break-level auto|0|1|2|3  在第几级标题前分页（默认 auto）
--number / --no-number      覆盖默认的章节编号策略
--links black|color         超链接颜色（默认 black）
--footer-total              页脚显示「第 N 页 共 M 页」
--table-rule auto|three|grid 表格线型（默认 auto）
--table-head-fill           表头加浅灰底纹（默认不加）
--code-color                代码块彩色高亮（默认单色）
--no-table-fit              关闭表格列宽重算（不建议）
--emoji text|strip|keep     彩色 emoji 处理（默认 text，映射为 √ × ! 等）
--bib FILE [--csl FILE]     参考文献
--no-lint / --strict-lint   Markdown 体检
--keep-tex                  保留中间 .tex，排查 LaTeX 报错时用
--verbose                   打印引擎原始输出（默认过滤 tectonic 的字体路径噪音）
```

取值写错（`--links blcak`、`--emoji foo`、`--toc-depth 9`）或漏写取值会立即
以中文报错退出，不会带着默认值静默出图。`--bib` / `--csl` 指向的文件不存在
也在启动时就报。

## 字体

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

**在 preamble 里写字体名有两个坑**，都表现为「编译不报错但排出豆腐块」：

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

## 已知边界

- **Tectonic 首次编译**需联网下载宏包（约 2 分钟），之后走缓存约 3 秒/次。
- **Mermaid 代码块不渲染**，原样输出为代码。需要图请先转成 PNG/SVG 再引用。
- **彩色 emoji 无法渲染**：XeTeX 不支持彩色字体，默认映射为 √ × ! 等文本符号。
- **ASCII 框图**已做等宽对齐（中文恰好 2 倍拉丁宽），但源文档必须本身是按终端
  等宽画的；超宽的框图会缩到五号仍放不下时按空格折行。
- **Word 的目录**是域，用 Word 打开会自动更新页码；用 LibreOffice 无头转 PDF
  预览时目录页是空的，属正常。
- 列宽按「CJK=2 / 西文=1」估算，不是真实字体度量，比例可靠、绝对值有偏差。

## 出问题时

1. `scripts/doctor.sh` 先自检工具链与字体。
2. `python3 scripts/md-lint.py 你的文档.md` 看是不是源文件的问题。
3. 加 `--keep-tex`，LaTeX 报错行号对应生成的 `.tex`，直接定位。
   想看引擎的完整原始输出再加 `--verbose`（默认过滤 tectonic 每次必刷的
   40~50 行「accessing absolute path」字体路径警告；编译失败时无论有没有
   `--verbose` 都会原样吐出完整日志）。
4. Word 效果可用 `soffice --headless --convert-to pdf --outdir /tmp x.docx` 预览。
5. 常见报错与机理见 `references/troubleshooting.md`。

## 目录结构

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
  troubleshooting.md     报错对照表与机理
```
