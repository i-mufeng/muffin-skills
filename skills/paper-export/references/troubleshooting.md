# 原生链路排查

先运行 `scripts/doctor.sh`。它会真实制作 DOCX 并用原生 `docx2pdf` 导出 PDF，保留产物与字体记录；不是只检查 `--version`。实际稿件可用 `--input 文件`，支持相同的 `--office`、`--font-dir`、`--theme-file`。`--out DIR` 指定检查产物目录，未指定则使用临时目录并打印位置。

| 现象 | 处理 |
| --- | --- |
| 找不到或不能执行 office | 设置 `MO_OFFICE_BIN` 或 `--office`，确认安装的引擎具备 md2docx/json2docx/docx2pdf 能力 |
| 缺少原生 PDF 功能/许可证 | 修复预装引擎及其合法运行环境；Skill 不下载或分发私有引擎，不切其他转换器 |
| 真实字体缺失、目录为空 | 查看 engine 原始错误，核对真实族名、文件与许可，补齐 TTF/TTC；目录可重复传入，当前引擎不读取 OTF |
| 缺字 | 查看错误中的字符及所选字体，取得包含该字符的正确字体；不删除字符或静默换族 |
| `pdf.native_font` | 实际字体溯源记录，核对 family、字重、face 与哈希，不是转换失败 |
| `pdf.synthetic_style` | 同族合成样式提示；用户要求真实字重时取得正确字重文件后重导 |
| unsupported 或 PDF 能力错误 | 按引擎当前能力修正文稿/模型或明确说明未完成；不能跳过 strict、后处理修补或用其他软件兜底 |
| 图像丢失/错误 | 检查源文件目录下的相对路径、图像格式与清晰度；准备 PNG 后再引用 |
| 失败但目录已有旧成品 | 旧成品是上一次成功结果；看新生成的 `*.failed-fontwarnings.*`，不要误当本次成功 |

`*.fontwarnings.log` 记录生成同一 DOCX 与 PDF 的引擎原始输出。脚本以非零退出码/缺失产物判失败，保留 warning 而不擅自升级。只请求 DOCX 仍需字体目录，因为验收会实际生成临时 PDF。

`legacy/` 是旧 Pandoc/LaTeX/Python 实现资料，没有活动入口，不作自动回退。运行旧脚本得到的产物不能用作新链路验证证据。
