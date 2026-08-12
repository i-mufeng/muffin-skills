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

modern 与 report 只差字体，标题层级刻意偏移一档（H1 归封面、H2 才是规范
意义上的一级标题）。这两件事的来由与实现见 `references/typography.md`。

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

# 写 Markdown 时必须遵守的约定

这些是**写文档时就要照着做**的，不照做导出会出问题。产出成品的排版规范
（版面、字号、颜色、封面、页眉页脚、分页、字体）见
`references/typography.md` —— 那些是核对成品或改版式时才需要翻的。

## 空行与缩进

**标题、表格、列表、代码围栏前后都要留空行**，而且 **`#` 必须顶到行首**。

哪些写法真的会丢内容，逐条实测过（pandoc 3.10.1 + 本 skill 的 `FROMSPEC`）：

| 写法 | 实际后果 | md-lint |
|---|---|---|
| 段落后紧跟标题，`#` 在行首 | 标题正常识别，导出不受影响 | warn |
| **标题缩进 1~3 空格** | **整行退化成正文文字，目录少一章** | error |
| **表格前缺空行** | **整张表退化成上一段的文字** | error |
| **列表后紧跟表格** | **整张表退化成列表项里的文字** | error |
| **分隔行列数少于表头** | **多出来的整列被静默丢弃** | error |

> 最隐蔽的是缩进。pandoc 的 markdown 要求 ATX 标题从行首开始（这一点与
> CommonMark 不同），`  ## 四、待确认事项` 前面哪怕有空行也**不会**被识别成
> 标题 —— 目录里少一整章，而编译不报任何错。

本 skill 关掉了 `blank_before_header`，所以「行首标题紧跟段落」在这里仍能正常
识别，只报 warn；但换任何其他 Markdown 工具（编辑器预览、GitHub、别的 pandoc
配置）都会被吞进上一段，仍应补空行。

每次导出前自动跑 `scripts/md-lint.py`。导出时只展开 error（**会实际丢内容**的
问题），警告折叠成计数；`md-lint.py 文件 --verbose` 看全部，`--strict-lint`
让 error 直接中止导出。

## 表格

**内容上的硬约束：**

- **单元格不得放大段文字。** 上限 40 个显示宽度单位（≈20 汉字）为宜，
  **超过 80（≈40 汉字）`md-lint` 会报 error**。超了就改成正文段落、
  列表，或把这一列拆成两列。
  > 表格是用来做「横向对比」的，不是用来装叙述的。一段话塞进单元格，
  > 既读不了也排不好 —— 列宽算法只能保证它不吃掉别的列，救不了它自己。
- 列数不超过 6。超了拆表，或改写成「字段说明列表」。
- 单元格内不放多个段落、不放代码块、不放列表。
- 不要用表格做两栏排版。
- 表格应有表题：`: 端口清单 {#tbl:ports}`，正文用 `@tbl:ports` 引用。
- **分隔行的列数必须和表头一致**。少一列，pandoc 会把多出来的整列（表头带
  数据）静默丢掉；`md-lint` 报 error。
- 表头列名同样受 80 上限约束（中文长列名最容易超）。

产出的是三线表，列宽按内容重算（不看 Markdown 分隔行的长度），内容密的表
自动加行间浅灰细线。`--table-rule` / `--table-head-fill` / `--no-table-fit`
可以覆盖，细节见 `references/typography.md`。

## 列表

无序 `•` / `–` / `·`，有序 `1.` / `(1)` / `①`。**三级以上建议改用带小标题的
段落** —— 再深就没人读得下去了。

## 语义标签（需求评审稿）

全文文字纯黑，唯一的例外是下面这套固定标签。只有标签本身着色，后续正文
保持黑色：

| 语义标签 | Markdown 写法 | 字体色 | 背景色 |
|---|---|---|---|
| 待确认 | `[【待确认】]{.mark-confirm}` | 深红 `C00000` | 浅红 `FCE8E6` |
| 需补充 | `[【需补充】]{.mark-supplement}` | 深红 `C00000` | 浅红 `FCE8E6` |
| 建议方案 | `[【建议方案】]{.mark-suggestion}` | 深蓝 `1F4E78` | 浅蓝 `DDEBF7` |
| 对抗意见 | `[【对抗意见】]{.mark-adversarial}` | 深红 `C00000` | 浅红 `FCE8E6` |
| 建议暂缓 | `[【建议暂缓】]{.mark-defer}` | 深红 `C00000` | 浅红 `FCE8E6` |
| 建议剔除 | `[【建议剔除】]{.mark-reject}` | 深红 `C00000` | 浅红 `FCE8E6` |

**文字和类名必须成对使用，不要把整句话放进 Span。** 例如：

```markdown
[【待确认】]{.mark-confirm} 项目暂停超过多少天后升级提醒。
[【需补充】]{.mark-supplement} 请提供现行审批表单和制度文件。
[【建议方案】]{.mark-suggestion} 采用“发起、处理、复核、解除”的风险闭环。
[【对抗意见】]{.mark-adversarial} 当前指标口径不足，不能直接用于对外展示。
[【建议暂缓】]{.mark-defer} 待数据基础和投入产出验证后再纳入建设。
[【建议剔除】]{.mark-reject} 当前阶段不建议进入对外展示。
```

## 元数据

可选。写在 YAML frontmatter 里，也可以完全不写 —— 命令行参数优先级更高。
字段说明见 `references/frontmatter.md`。

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

## 图表与交叉引用

需要 pandoc-crossref：

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

## 参考文献

`--bib refs.bib`，正文里 `[@zhang2024]`。PDF 与 Word 共用
citeproc，两侧样式完全一致；gb 预设自动套 GB/T 7714 —— 前提是
`assets/gb-t-7714-2015-numeric.csl` 在位（不随 skill 分发，`scripts/doctor.sh
--install` 补装）。缺了会退回 pandoc 默认样式，导出时会明确提示，不静默降级。

---

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

modern 用阿里巴巴普惠体，report/gb 用 macOS 自带的宋体 + Heiti SC Medium，
brief 用思源宋体，代码块用 Maple Mono CN。手动装的那几个缺失时都有回退
（观感降一档，不会编译失败），`scripts/doctor.sh` 会逐个列出在位情况。

字体清单、安装方式，以及「在 preamble 里写字体名的两个坑」（多字重必须用
PostScript 名、.ttc 里的非首 face 取不到）见 `references/typography.md`。

## 已知边界

- **Tectonic 首次编译**需联网下载宏包（约 2 分钟），之后走缓存约 3 秒/次。
- **Mermaid 代码块不渲染**，原样输出为代码。需要图请先转成 PNG/SVG 再引用。
- **彩色 emoji 无法渲染**：XeTeX 不支持彩色字体，默认映射为 √ × ! 等文本符号。
- **ASCII 框图**已做等宽对齐（中文恰好 2 倍拉丁宽），但源文档必须本身是按终端
  等宽画的；超宽的框图会缩到五号仍放不下时按空格折行。
- **Word 的目录**是域，用 Word 打开会自动更新页码；用 LibreOffice 无头转 PDF
  预览时目录页是空的，属正常。
- 列宽按「CJK=2 / 西文=1」估算，不是真实字体度量，比例可靠、绝对值有偏差。
  这份显示宽度表在 `assets/tablefit.lua` 与 `scripts/md-lint.py` 里各有一份，
  已逐码位比对确认一致；改一处必须同步改另一处。
- **带合并单元格的表格不加行间分界线**。`\noalign` 只在行首合法，跨行/跨列
  单元格里插会让 XeTeX 直接编译失败，所以这些行一律跳过 —— 宁可少一条线。
- **文档里没有对应级别的标题时，Word 页眉右侧留空**（不印 STYLEREF 域）。
  例如 title 写在 frontmatter、正文只有一个 H1 而无 H2 的情况。
- **语义标签只认 `[【待确认】]{.mark-confirm}` 这种带类的写法**。正文里当普通
  词语用的「【待确认】」PDF 与 Word 两侧都不着色。

## 出问题时

1. `scripts/doctor.sh` 先自检工具链与字体。
2. `python3 scripts/md-lint.py 你的文档.md` 看是不是源文件的问题。
3. 加 `--keep-tex`，LaTeX 报错行号对应生成的 `.tex`，直接定位。
   想看引擎的完整原始输出再加 `--verbose`（默认过滤 tectonic 每次必刷的
   40~50 行「accessing absolute path」字体路径警告；编译失败时无论有没有
   `--verbose` 都会原样吐出完整日志）。
4. Word 效果可用 `soffice --headless --convert-to pdf --outdir /tmp x.docx` 预览。
5. 常见报错与机理见 `references/troubleshooting.md`。

## 参考文件

| 文件 | 内容 |
|---|---|
| `references/frontmatter.md` | 元数据字段与优先级 |
| `references/typography.md` | 排版规范实现细节、字体、各文件职责与注入顺序 |
| `references/troubleshooting.md` | 报错对照表与机理 |
