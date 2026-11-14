#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARGS=(); OUT=""; INPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --office|--font-dir|--theme-file)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { echo "选项 $1 缺少取值" >&2; exit 2; }
      ARGS+=("$1" "$2"); shift 2 ;;
    --out|--input)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { echo "选项 $1 缺少取值" >&2; exit 2; }
      if [[ "$1" == --out ]]; then OUT="$2"; else INPUT="$2"; fi
      shift 2 ;;
    -h|--help)
      echo '用法：doctor.sh [--office FILE] [--font-dir DIR ...] [--theme-file FILE] [--input 文件] [--out DIR]'
      echo '真实运行 DOCX→PDF 并保留字体记录；--input 可检查实际文稿。不会自动安装依赖或字体。'
      exit 0 ;;
    *) echo "不支持的选项：$1" >&2; exit 2 ;;
  esac
done
if [[ -z "$OUT" ]]; then OUT="$(mktemp -d "${TMPDIR:-/tmp}/paper-export-doctor.XXXXXX")"; fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
if [[ -z "$INPUT" ]]; then
  smoke_dir="$(mktemp -d "$OUT/.smoke-source.XXXXXX")"
  trap 'rm -rf "$smoke_dir"' EXIT
  INPUT="$smoke_dir/probe.md"
  cat > "$INPUT" <<'MD'
# 字体自检

正文宋体：中文标点，数字 0123456789；Latin Times New Roman.

| 项目 | 内容 |
| --- | --- |
| 字体 | 中文与 Latin |
MD
fi
if [[ ${#ARGS[@]} -gt 0 ]]; then
  /bin/bash "$SKILL_DIR/scripts/export.sh" "$INPUT" --to both --out "$OUT" --name probe "${ARGS[@]}"
else
  /bin/bash "$SKILL_DIR/scripts/export.sh" "$INPUT" --to both --out "$OUT" --name probe
fi
printf '原生 DOCX→PDF 检查通过；字体记录：%s\n' "$OUT/probe.fontwarnings.log"
