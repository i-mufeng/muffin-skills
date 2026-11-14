#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/scripts/common.sh"
OFFICE="${MO_OFFICE_BIN:-}"; FONT_DIRS=(); KEEP=0
[[ -z "${MO_PDF_FONT_DIR:-}" ]] || FONT_DIRS+=("$MO_PDF_FONT_DIR")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --office) pe_value "$1" "${2:-}"; OFFICE="$2"; shift 2 ;;
    --font-dir) pe_value "$1" "${2:-}"; FONT_DIRS+=("$2"); shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) echo '用法：test.sh [--office FILE] [--font-dir DIR ...] [--keep]；必须提供可运行的原生引擎与真实字体'; exit 0 ;;
    *) pe_fail "不支持的测试选项：$1" ;;
  esac
done
pe_office
pe_fonts
TD="$(mktemp -d "${TMPDIR:-/tmp}/paper-native-tests.XXXXXX")"
cleanup() { if [[ $KEEP -eq 0 ]]; then rm -rf "$TD"; else printf '测试产物：%s\n' "$TD"; fi; }
trap cleanup EXIT
EXPORT="$SKILL_DIR/scripts/export.sh"; COUNT=0
pass() { COUNT=$((COUNT+1)); printf '通过：%s\n' "$1"; }
fail() { printf '失败：%s\n' "$1" >&2; [[ ! -f "$TD/last.log" ]] || cat "$TD/last.log" >&2; exit 1; }
run_export() { /bin/bash "$EXPORT" --office "$OFFICE" "${FONT_ARGS[@]}" "$@" > "$TD/last.log" 2>&1; }
expect_fail() { if run_export "$@"; then fail "应拒绝：$*"; fi; }
mkdir -p "$TD/source space" "$TD/out space" "$TD/empty fonts"
cat > "$TD/source space/input file.md" <<'MD'
# 导出测试

中文段落与 Latin 0123，检查真实字体。

| 项目 | 数值 |
| --- | --- |
| 中文 | 12 |
MD
INPUT="$TD/source space/input file.md"
for script in common.sh export.sh doctor.sh test.sh; do
  /bin/bash -n "$SKILL_DIR/scripts/$script" || fail "Bash 语法 $script"
done
pass 'Bash 3.2 可解析全部入口'
run_export "$INPUT" --to both --out "$TD/out space" --name 'result file' || fail 'Markdown 原生导出'
[[ -s "$TD/out space/result file.docx" && -s "$TD/out space/result file.pdf" ]] || fail '双格式产物'
[[ "$(LC_ALL=C head -c 5 "$TD/out space/result file.pdf")" == '%PDF-' ]] || fail 'PDF 文件头'
grep -q 'pdf.native_font' "$TD/out space/result file.fontwarnings.log" || fail '原生字体溯源'
pass '带空格路径、中文表格、双格式及原生字体记录'
cp "$TD/out space/result file.docx" "$TD/source space/original.docx"
run_export "$TD/source space/original.docx" --to pdf || fail '现成 DOCX 原生转 PDF'
cmp -s "$TD/source space/original.docx" "$TD/out space/result file.docx" || fail '不得改写 DOCX 源'
[[ -s "$TD/source space/original.pdf" ]] || fail 'DOCX PDF 产物'
pass 'DOCX 输入默认同目录转 PDF，源文件保持不变'
"$OFFICE" md2json "$INPUT" --kind docs > "$TD/source space/model.json" 2> "$TD/last.log" || fail '生成原生 JSON 输入'
run_export "$TD/source space/model.json" --to docx --out "$TD/out space" --name json-result || fail 'JSON 输入'
[[ -s "$TD/out space/json-result.docx" && ! -e "$TD/out space/json-result.pdf" ]] || fail 'docx-only 输出'
grep -q 'pdf.native_font' "$TD/out space/json-result.fontwarnings.log" || fail 'docx-only PDF 字体验证'
pass 'JSON→DOCX，同样完成实际 PDF 字体验证'
for option in --style --bib --csl --keep-tex --no-lint --install; do expect_fail "$INPUT" "$option" old; done
expect_fail "$INPUT" --to invalid
expect_fail "$INPUT" --theme-file
expect_fail "$INPUT" --font-dir
expect_fail "$INPUT" --name '../escape'
expect_fail "$INPUT" "$INPUT"
expect_fail "$TD/source space"
expect_fail "$TD/source space/original.docx" --to both
expect_fail "$TD/source space/original.docx" --theme-file "$SKILL_DIR/assets/report.json"
pass '旧参数、非法取值、目录、多输入和覆盖源文件均拒绝'
cp "$TD/out space/result file.docx" "$TD/old.docx"
cp "$TD/out space/result file.pdf" "$TD/old.pdf"
cp "$TD/out space/result file.fontwarnings.log" "$TD/old.log"
printf '%s' '{invalid' > "$TD/bad.json"
expect_fail "$TD/bad.json" --to both --out "$TD/out space" --name 'result file'
cmp -s "$TD/old.docx" "$TD/out space/result file.docx" && cmp -s "$TD/old.pdf" "$TD/out space/result file.pdf" && cmp -s "$TD/old.log" "$TD/out space/result file.fontwarnings.log" || fail '失败后保持已有成品'
pass '转换失败时已有 DOCX/PDF/字体日志均保持不变'
if MO_PDF_FONT_DIR= /bin/bash "$EXPORT" "$INPUT" --office "$OFFICE" --font-dir "$TD/empty fonts" --out "$TD/out space" --name 'result file' > "$TD/last.log" 2>&1; then fail '无字体必须失败'; fi
cmp -s "$TD/old.docx" "$TD/out space/result file.docx" && cmp -s "$TD/old.pdf" "$TD/out space/result file.pdf" || fail '字体失败后保持成品'
pass '真实空字体目录失败且不覆盖成品'
sed 's/"宋体"/"PaperExportMissingFont_983746"/g' "$SKILL_DIR/assets/report.json" > "$TD/missing-font.json"
expect_fail "$INPUT" --theme-file "$TD/missing-font.json" --out "$TD/out space" --name 'result file'
grep -q 'PDF_FONT_MISSING' "$TD/last.log" || fail '真实缺字体错误'
printf '\n\364\217\277\277\n' >> "$INPUT"
expect_fail "$INPUT" --out "$TD/out space" --name 'result file'
grep -q 'PDF_MISSING_GLYPH' "$TD/last.log" || fail '真实缺字错误'
cmp -s "$TD/old.docx" "$TD/out space/result file.docx" && cmp -s "$TD/old.pdf" "$TD/out space/result file.pdf" || fail '缺字体缺字后保持成品'
pass '真实缺字体/缺字报错并保护已有成品'
sed '$d' "$INPUT" > "$TD/valid.md"
mkdir -p "$TD/bin"
ln -s "$OFFICE" "$TD/bin/office"
MO_OFFICE_BIN= PATH="$TD/bin:$PATH" /bin/bash "$EXPORT" "$TD/valid.md" "${FONT_ARGS[@]}" --out "$TD/path-result" > "$TD/last.log" 2>&1 || fail 'PATH office 选择'
MO_OFFICE_BIN="$TD/missing" /bin/bash "$EXPORT" "$TD/valid.md" --office "$OFFICE" "${FONT_ARGS[@]}" --out "$TD/explicit-result" > "$TD/last.log" 2>&1 || fail '显式 office 优先级'
pass 'PATH office 及显式路径优先于环境变量'
if MO_OFFICE_BIN="$TD/no office" /bin/bash "$EXPORT" "$INPUT" "${FONT_ARGS[@]}" > "$TD/last.log" 2>&1; then fail '无引擎必须失败'; fi
pass '缺少引擎明确失败'
/bin/bash "$SKILL_DIR/scripts/doctor.sh" --office "$OFFICE" "${FONT_ARGS[@]}" --out "$TD/doctor space" > "$TD/last.log" 2>&1 || fail 'doctor 实际 smoke'
[[ -s "$TD/doctor space/probe.docx" && -s "$TD/doctor space/probe.pdf" && -s "$TD/doctor space/probe.fontwarnings.log" ]] || fail 'doctor 真实产物'
pass 'doctor 实际执行 DOCX→PDF 并保留日志'
if command -v pdftotext >/dev/null 2>&1; then
  pdftotext -layout "$TD/out space/result file.pdf" "$TD/content.txt" || fail '独立 PDF 内容提取'
  grep -q '中文段落' "$TD/content.txt" && grep -q '数值' "$TD/content.txt" && grep -q '12' "$TD/content.txt" || fail 'PDF 中文表格内容'
  grep -Eq '^[[:space:]]*1[[:space:]]*$' "$TD/content.txt" || fail 'PDF PAGE 页码'
  pass '独立读取 PDF 核对中文、表格与 PAGE 页码'
fi
printf '通过 %d 组；无跳过。\n' "$COUNT"
