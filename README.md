# muffin-skills

沐风自用的 Claude Code Skills 仓库。

## 目录结构

```
skills/
  paper-export/     Markdown → PDF / Word 规范级排版（Pandoc + XeLaTeX/Tectonic）
```

每个 skill 一个目录，内含 `SKILL.md`（skill 入口，Claude 读它决定怎么用）
以及 `scripts/` `assets/` `references/`。目录名即 skill 名。

## 安装

Claude Code 从 `~/.claude/skills/<name>/` 加载全局 skill。用软链接指过来，
仓库里改完立刻生效，不用来回拷：

```bash
ln -sfn "$PWD/skills/paper-export" ~/.claude/skills/paper-export
```

已经有实体目录时先备份再换：

```bash
mv ~/.claude/skills/paper-export ~/.claude/skills/paper-export.bak
```

## skills

### paper-export

把 Markdown 排成可直接交付评审的 PDF 或 Word。五套预设：
`modern`（默认，阿里巴巴普惠体）、`modern-plain`（无封面目录）、
`report`（宋体纸质件）、`gb`（学位论文 GB/T 7714）、`brief`（简报通报，GB/T 9704 观感）。

```bash
skills/paper-export/scripts/doctor.sh              # 工具链与字体自检
skills/paper-export/scripts/export.sh 文档.md --to both
skills/paper-export/scripts/test.sh                # 回归测试（108 条断言）
```

详见 [skills/paper-export/SKILL.md](skills/paper-export/SKILL.md)。

## 约定

- **改 skill 之前先跑 `scripts/test.sh` 留基线，改完再跑一遍。**
  每条断言都对应一个曾经真实发生过的故障；`--fast` 跳过 PDF 编译约 7 秒，
  全量约 2 分钟。提交前跑全量。
- 脚本以 macOS 自带的 **bash 3.2** 为兼容底线（`/bin/bash` 就是它）。
  注意两个坑：`set -u` 下空数组不能 `"${arr[@]}"` 展开；
  `$( )` 里不能嵌 heredoc（语法阶段就报 unexpected EOF）。
