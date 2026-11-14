---
name: paper-export
description: 使用预装 office 原生引擎将 Markdown、文档 JSON 或 DOCX 导出为 Word/PDF。适用于技术文档、论文、课程短文和报告的成册排版、真实字体核对与交付检查。
---

# 原生文档导出

使用预装 `office` 的 `md2docx` / `json2docx` / `docx2pdf`；PDF 必须从同一份 DOCX 生成。禁止借助 Word、LibreOffice、Pandoc、LaTeX、Python、Node 转换或后处理，也不自动切换实现。

## 执行

1. 读取用户参考模板与格式要求，先核对正文、标题、中西文字体、字号、行距、边距、页码、图表与参考文献规则。用户指定的格式优先；随附主题只是通用起点，不是任何学校或国家标准的认证模板。
2. 用 `MO_OFFICE_BIN`、`--office FILE` 或 PATH 提供 `office`。字体用可重复的 `--font-dir DIR`，或单目录 `MO_PDF_FONT_DIR`。运行 `scripts/doctor.sh`，用 `--input` 可直接验证实际稿件。
3. 普通内容用 Markdown；精确的段落、表格线、图题、分页或分节控制用原生模型 JSON。按当前引擎的 `office schema model` / `office schema theme` 制作；需要参考模板时读取 [排版指导](references/typography.md)。
4. 执行导出，查看 `.fontwarnings.log` 中实际字体名称、字重、来源与缺字错误。缺字体应主动查找本机合法安装；不足则找官方或明确授权来源，核对许可后取得真实字体。不得重命名字体、伪装族名、静默换字体或把字体原件提交到公共仓库。
5. 用 PDF 页面渲染检查实际排版，重点检查图内文字、表格跨页、标题孤行、字体、页码和参考文献。报告验证边界；未在真实 Word 打开就不声称 Word 显示完全一致。

```bash
scripts/doctor.sh --office /path/to/office --font-dir /path/to/fonts
scripts/export.sh 文稿.md --to both --out ./output \
  --office /path/to/office --font-dir /path/to/fonts --theme-file ./theme.json
scripts/export.sh 排版模型.json --to both --out ./output
scripts/export.sh 原稿.docx --to pdf
```

只有引擎返回成功且成品存在才替换目标文件。失败保留已有 DOCX/PDF/日志，另外保存失败诊断日志。即使只要 DOCX，也会在临时目录实际生成 PDF 验证字体。DOCX 输入保留自身样式；需要重新排版时先整理成模型，不接受主题覆盖现成 DOCX。

## 内容边界

- 不承诺旧五套预设、自动目录页码、公式、BibTeX/CSL、交叉引用或复杂 DOCX 的保真能力。Markdown/JSON 转 DOCX 固定使用 `--strict`，由引擎拒绝已知不支持内容；PDF 同样服从引擎的能力检查。
- 文献先核对真实来源，正文使用静态 `[1]` 等引用并按要求书写文后条目；图表编号、题注与正文引用保持一致，不把 `@fig:`、`[@key]` 等旧标记交给新链路。
- 图片保留可编辑源文件；含文字的复杂图先制作清晰 PNG 成册图并检查中文与边界。表格用于横向比较，避免长段落挤入单元格；精确三线表需在模型中设置边框，不宣称普通 Markdown 自动达到论文模板。
- 多文件先明确顺序与相对资源路径，整理成一份源文件；脚本只接收一个文件，不做隐式目录合并。

[参数与输入](references/frontmatter.md) · [排版指导](references/typography.md) · [故障排查](references/troubleshooting.md)

改动前后运行 `scripts/test.sh`，必须提供实际原生引擎与真实字体；缺依赖会失败，不以全跳过报通过。`legacy/` 仅保留旧实现资料，禁止调用或用作回退。
