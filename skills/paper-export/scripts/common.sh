#!/usr/bin/env bash
# Shared by native export entry points; compatible with Bash 3.2.
pe_fail() { printf '%s\n' "$*" >&2; exit 1; }
pe_value() {
  [[ -n "${2:-}" && "$2" != --* ]] || pe_fail "选项 $1 缺少取值"
}
pe_office() {
  if [[ -z "$OFFICE" ]]; then OFFICE="$(command -v office || true)"; fi
  [[ -n "$OFFICE" ]] || pe_fail "未找到 office；设置 MO_OFFICE_BIN 或 --office"
  if [[ "$OFFICE" != */* ]]; then OFFICE="$(command -v "$OFFICE" || true)"; fi
  [[ -n "$OFFICE" && -f "$OFFICE" && -x "$OFFICE" ]] || pe_fail "office 不可执行：$OFFICE"
  OFFICE="$(cd "$(dirname "$OFFICE")" && pwd)/$(basename "$OFFICE")"
}
pe_fonts() {
  [[ ${#FONT_DIRS[@]} -gt 0 ]] || pe_fail "请用 --font-dir 或 MO_PDF_FONT_DIR 指定真实字体目录"
  FONT_ARGS=()
  for font_dir in "${FONT_DIRS[@]}"; do
    [[ -d "$font_dir" ]] || pe_fail "字体目录不存在：$font_dir"
    FONT_ARGS+=(--font-dir "$(cd "$font_dir" && pwd)")
  done
}
