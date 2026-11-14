#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/scripts/common.sh"
OFFICE="${MO_OFFICE_BIN:-}"; TO=pdf; OUT=""; NAME=""; INPUT=""
THEME="$SKILL_DIR/assets/report.json"; THEME_SET=0; FONT_DIRS=()
[[ -z "${MO_PDF_FONT_DIR:-}" ]] || FONT_DIRS+=("$MO_PDF_FONT_DIR")
usage() {
  cat <<'HELP'
用法：export.sh 文件.md|文件.json|文件.docx [选项]
  --to pdf|docx|both     默认 pdf；PDF 从同一份 DOCX 原生生成
  --out DIR             输出目录，默认输入目录
  --name NAME           输出名，不含扩展名
  --office FILE         office 可执行文件；也可设置 MO_OFFICE_BIN 或放入 PATH
  --font-dir DIR        真实 TTF/TTC 字体目录，可重复；MO_PDF_FONT_DIR 为单目录
  --theme-file FILE     Markdown/JSON 原生主题，默认随附 report.json
  -h, --help
所有输出均经过原生 PDF 字体验证；日志为 NAME.fontwarnings.log。
JSON 须符合当前 office schema model。旧预设、BibTeX、CSL 及目录合并参数不再支持。
HELP
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to) pe_value "$1" "${2:-}"; TO="$2"; shift 2 ;;
    --out) pe_value "$1" "${2:-}"; OUT="$2"; shift 2 ;;
    --name) pe_value "$1" "${2:-}"; NAME="$2"; shift 2 ;;
    --office) pe_value "$1" "${2:-}"; OFFICE="$2"; shift 2 ;;
    --font-dir) pe_value "$1" "${2:-}"; FONT_DIRS+=("$2"); shift 2 ;;
    --theme-file) pe_value "$1" "${2:-}"; THEME="$2"; THEME_SET=1; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; [[ $# -eq 1 && -z "$INPUT" ]] || pe_fail "只接受一个输入文件"; INPUT="$1"; shift ;;
    -*) pe_fail "不支持的选项：$1；请查看 --help，旧导出参数不能静默沿用" ;;
    *) [[ -z "$INPUT" ]] || pe_fail "只接受一个输入文件；请先明确合并顺序并制作单份源文件"; INPUT="$1"; shift ;;
  esac
 done
[[ -n "$INPUT" && -f "$INPUT" ]] || pe_fail "需要一个存在的 Markdown、JSON 或 DOCX 文件"
case "$TO" in pdf|docx|both) ;; *) pe_fail "--to 只能为 pdf / docx / both" ;; esac
INPUT="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
EXT="${INPUT##*.}"
case "$EXT" in md|json|docx) ;; *) pe_fail "输入扩展名只支持 .md / .json / .docx" ;; esac
[[ "$EXT" != docx || $THEME_SET -eq 0 ]] || pe_fail "DOCX 输入保留自身样式，不接受 --theme-file"
[[ -f "$THEME" ]] || pe_fail "主题不存在：$THEME"
THEME="$(cd "$(dirname "$THEME")" && pwd)/$(basename "$THEME")"
[[ -n "$OUT" ]] || OUT="$(dirname "$INPUT")"
[[ -n "$NAME" ]] || NAME="$(basename "$INPUT" ".$EXT")"
case "$NAME" in ''|.|..|*/*) pe_fail "--name 必须是单个文件名" ;; esac
pe_office
pe_fonts
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
for suffix in docx pdf fontwarnings.log; do
  case "$suffix:$TO" in docx:pdf|pdf:docx) continue ;; esac
  target="$OUT/$NAME.$suffix"
  [[ ! -d "$target" ]] || pe_fail "输出路径是目录：$target"
  [[ ! -e "$target" || ! "$target" -ef "$INPUT" ]] || pe_fail "输出不能覆盖输入：$target；请指定 --out 或 --name"
done
WORK="$(mktemp -d "$OUT/.paper-export.XXXXXX")"
LOG="$WORK/fontwarnings.log"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
fail_conversion() {
  cat "$LOG" >&2
  failure_log="$(mktemp "$OUT/$NAME.failed-fontwarnings.XXXXXX")"
  cp "$LOG" "$failure_log"
  pe_fail "导出失败，原有成品保持不变；诊断日志：$failure_log"
}
case "$EXT" in
  md|json)
    command_name=md2docx; [[ "$EXT" != json ]] || command_name=json2docx
    if ! (cd "$(dirname "$INPUT")" && "$OFFICE" "$command_name" "$INPUT" --theme-file "$THEME" --strict -o "$WORK/document.docx") >"$LOG" 2>&1; then fail_conversion; fi ;;
  docx) cp "$INPUT" "$WORK/document.docx"; : > "$LOG" ;;
esac
[[ -s "$WORK/document.docx" ]] || { printf '%s\n' 'office 未生成 DOCX' >> "$LOG"; fail_conversion; }
if ! "$OFFICE" docx2pdf "$WORK/document.docx" "${FONT_ARGS[@]}" -o "$WORK/document.pdf" >>"$LOG" 2>&1; then fail_conversion; fi
[[ -s "$WORK/document.pdf" ]] || { printf '%s\n' 'office 未生成 PDF' >> "$LOG"; fail_conversion; }
case "$TO" in docx|both) mv -f "$WORK/document.docx" "$OUT/$NAME.docx" ;; esac
case "$TO" in pdf|both) mv -f "$WORK/document.pdf" "$OUT/$NAME.pdf" ;; esac
mv -f "$LOG" "$OUT/$NAME.fontwarnings.log"
case "$TO" in docx|both) printf '%s\n' "$OUT/$NAME.docx" ;; esac
case "$TO" in pdf|both) printf '%s\n' "$OUT/$NAME.pdf" ;; esac
