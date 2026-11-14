# muffin-skills

沐风自用的 Agent Skills 仓库。每个 `skills/<name>/` 以 `SKILL.md` 为入口，按需提供脚本、资产和参考资料。

## 安装

将目标目录软链接到客户端的全局 skills 目录；已有实体目录先备份。下例从本仓库根目录执行：

```bash
mkdir -p ~/.claude/skills ~/.codex/skills
ln -sfn "$PWD/skills/paper-export" ~/.claude/skills/paper-export
ln -sfn "$PWD/skills/paper-export" ~/.codex/skills/paper-export
ln -sfn "$PWD/skills/frontend-ui-design" ~/.claude/skills/frontend-ui-design
```

确认软链最终指向本仓库且没有断链；启用新版后，避免让旧备份的 `paper-export` 同时作为活动 Skill 被加载。仓库改动会通过软链生效，客户端已加载的说明可能需要新会话重新读取。

## paper-export

使用预装 `office` 原生导出 Markdown、文档 JSON 和 DOCX。PDF 从同一份 DOCX 生成，使用真实字体文件并保留字体记录。公开仓库不分发私有引擎、字体原件或用户稿件。

```bash
export MO_OFFICE_BIN=/path/to/office
export MO_PDF_FONT_DIR=/path/to/fonts
skills/paper-export/scripts/doctor.sh
skills/paper-export/scripts/export.sh 文稿.md --to both
skills/paper-export/scripts/test.sh
```

支持 `--office`、重复 `--font-dir`、`--theme-file`、`--out`、`--name` 和 `--to`。失败不替换已有成品；不存在依赖时明确失败。旧五套预设和旧参数不再作为兼容接口，旧资产移至 `legacy/` 供历史查阅，禁止作为回退。详见 [SKILL.md](skills/paper-export/SKILL.md)。

## frontend-ui-design

设计、实现或审查 Web 与移动端前端界面，覆盖层级、配色、字体、留白、交互、响应式、无障碍与浏览器验收。详见 [SKILL.md](skills/frontend-ui-design/SKILL.md)。

## 约定

- 修改前运行该 Skill 的现有测试留基线，修改后运行当前完整测试。原生导出测试必须使用实际引擎与字体，不能全跳过报通过。
- 脚本以 macOS 自带 Bash 3.2 为兼容底线；`set -u` 下不要展开空数组，不在命令替换中嵌 heredoc。
