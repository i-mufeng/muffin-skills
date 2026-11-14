# 参数与输入

`export.sh` 只接受一个 `.md`、`.json` 或 `.docx` 文件。相对路径图片按源文件目录解析，脚本从该目录调用 Markdown/JSON 导出。

| 参数 | 行为 |
| --- | --- |
| `--to pdf\|docx\|both` | 默认 PDF；所有格式都实际执行原生 DOCX→PDF 检查 |
| `--out DIR` | 默认输入目录 |
| `--name NAME` | 默认输入文件去掉扩展名；不能含路径 |
| `--office FILE` | 优先于 `MO_OFFICE_BIN`，其次 PATH 的 `office` |
| `--font-dir DIR` | 可重复；与 `MO_PDF_FONT_DIR` 指定的单目录一起传给原生引擎 |
| `--theme-file FILE` | Markdown/JSON 默认用 `assets/report.json`；DOCX 输入拒绝此参数 |

不存在的输入、字体目录、主题或引擎立即失败。不能覆盖源文件，DOCX 想另存 DOCX 或双格式时必须指定不同输出名或目录。现成 DOCX 转 PDF 可直接放在原目录。

不再提供旧版封面字段命令、`--style`、`--bib`、`--csl`、`--keep-tex`、`--no-lint` 等参数；传入会报错。YAML 元数据按当前引擎能力解释，不沿用旧版“八字段自动封面”契约。定制元数据展示应显式组织成 Markdown 内容、主题或模型。

JSON 是原生文档模型，不是任意业务 JSON。以当前安装的引擎输出为准：

```bash
office schema model > model.schema.json
office schema theme > theme.schema.json
```

原生转换使用 `--strict` 拒绝已知不支持的 Markdown/模型内容。原生 PDF 报告的实际字体和其他 warning 原样保存在 `NAME.fontwarnings.log`；warning 不等于失败，应逐条理解后说明交付边界。缺字体、缺字等引擎错误会中止导出，保存独立的 `NAME.failed-fontwarnings.*` 日志。
