#!/usr/bin/env bash
# ============================================================
#  paper-export :: 回归测试
#
#  每一条断言都对应一个曾经真实发生过的故障。改 preamble / lua filter /
#  后处理之前先跑一遍留基线，改完再跑一遍对比 —— 这套脚本存在的意义就是
#  让「只改行为、不改排版结果」这句话有据可查。
#
#  用法:
#    scripts/test.sh                 全跑（含 PDF 编译，约 1~2 分钟）
#    scripts/test.sh --fast          跳过 PDF 编译与渲染（约 10 秒）
#    scripts/test.sh --render        额外跑 soffice 渲染断言（很慢）
#    scripts/test.sh -k lint         只跑名字含 lint 的组
#    scripts/test.sh --keep          保留临时目录，便于人工查看产物
#    scripts/test.sh -v              打印每条通过项（默认只打印失败）
#
#  组: syntax  chars  args  lint  filters  docx  pdf  render
# ============================================================
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$SKILL_DIR/assets"
SCRIPTS="$SKILL_DIR/scripts"
EXPORT="$SCRIPTS/export.sh"
LINT="$SCRIPTS/md-lint.py"
POST="$SCRIPTS/docx-postprocess.py"

FAST=0; RENDER=0; KEEP=0; VERBOSE=0; ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fast)   FAST=1; shift ;;
    --render) RENDER=1; shift ;;
    --keep)   KEEP=1; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -k)       ONLY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知选项: $1" >&2; exit 2 ;;
  esac
done

PANDOC=""
for c in /opt/homebrew/bin/pandoc /usr/local/bin/pandoc "$(command -v pandoc || true)"; do
  [[ -n "$c" && -x "$c" ]] && { PANDOC="$c"; break; }
done
[[ -z "$PANDOC" ]] && { echo "未找到 pandoc，先跑 scripts/doctor.sh" >&2; exit 1; }
PY="$(command -v python3 || true)"
[[ -z "$PY" ]] && { echo "未找到 python3" >&2; exit 1; }

# export.sh 用的 reader 扩展。测试必须用同一套 —— 用 pandoc 默认设置去判断
# 「应有行为」会得出相反的结论（blank_before_header 在这里是关掉的）。
FROMSPEC='markdown-blank_before_header+lists_without_preceding_blankline'
FROMSPEC+='+east_asian_line_breaks+pipe_tables+tex_math_dollars+raw_tex'

TD="$(mktemp -d)"
cleanup() { [[ $KEEP -eq 1 ]] && echo "临时目录保留: $TD" || rm -rf "$TD"; }
trap cleanup EXIT

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; D=$'\033[2m'; B=$'\033[1m'; Z=$'\033[0m'
else
  G=""; R=""; Y=""; D=""; B=""; Z=""
fi

PASS=0; FAIL=0; SKIP=0
FAILED_NAMES=""
GROUP=""

group() {
  GROUP="$1"
  if [[ -n "$ONLY" && "$1" != *"$ONLY"* ]]; then return 1; fi
  printf '\n%s── %s %s\n' "$B" "$1" "$Z"
  return 0
}

ok()   { PASS=$((PASS+1)); [[ $VERBOSE -eq 1 ]] && printf '  %s✓%s %s\n' "$G" "$Z" "$1"; return 0; }
bad()  {
  FAIL=$((FAIL+1))
  FAILED_NAMES="$FAILED_NAMES
  [$GROUP] $1"
  printf '  %s✗%s %s\n' "$R" "$Z" "$1"
  [[ -n "${2:-}" ]] && printf '    %s%s%s\n' "$D" "$2" "$Z"
  return 0
}
skip() { SKIP=$((SKIP+1)); printf '  %s-%s %s %s(%s)%s\n' "$Y" "$Z" "$1" "$D" "${2:-跳过}" "$Z"; return 0; }

# 期望值 实际值 名称
eq() {
  if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3" "期望 [$1]，实际 [$2]"; fi
}
# 名称：命令输出应包含
has() {
  if printf '%s' "$2" | grep -q -- "$3"; then ok "$1"; else bad "$1" "输出中未找到 [$3]"; fi
}
hasnt() {
  if printf '%s' "$2" | grep -q -- "$3"; then bad "$1" "输出中不该出现 [$3]"; else ok "$1"; fi
}

# pandoc AST 里某种节点的个数
ast_count() { "$PANDOC" --from="$FROMSPEC" -t native "$1" 2>/dev/null | grep -cw "$2"; }

# ---------------------------------------------------------------- 测试数据
mkdir -p "$TD/md"
md() { cat > "$TD/md/$1"; }

# 完全正确的文档：任何检查都不该报
md ok.md <<'EOF'
# 正确文档

## 一、概述

正文一段。

| 端口 | 用途 |
|---|---|
| 8080 | HTTP |

## 二、结论

正文。
EOF

# lint 用例：文件名 = 期望的 error 数
md e1-indent-head-after-para.md <<'EOF'
# A

正文。
  ## 缩进标题

正文。
EOF
md e1-indent-head-after-blank.md <<'EOF'
# A

正文。

  ## 缩进标题

正文。
EOF
md w1-head-after-para.md <<'EOF'
# A

正文。
## 行首标题

正文。
EOF
md e1-table-no-blank-before.md <<'EOF'
# A

说明：
| a | b |
|---|---|
| 1 | 2 |
EOF
md e1-table-after-list.md <<'EOF'
# A

- 项一
| a | b |
|---|---|
| 1 | 2 |
EOF
md e1-delim-short.md <<'EOF'
# A

| 甲 | 乙 | 丙 |
|---|---|
| 1 | 2 | 3 |
EOF
md ok-frontmatter-head.md <<'EOF'
---
title: T
---
# H1

正文。
EOF
md ok-html-comment-head.md <<'EOF'
<!-- 说明 -->
# H1

正文。
EOF
md ok-rawtex-head.md <<'EOF'
# A

正文。

\newpage
## H2

正文。
EOF
md ok-setext-head.md <<'EOF'
标题一
=====
### 子节

正文。
EOF
md ok-inline-triple-tick.md <<'EOF'
# A

```json``` 是格式。

正文。
EOF
md ok-indented-code-table.md <<'EOF'
# A

演示：

    | a | b |
    |---|---|
    | 长内容 | 备注 |
EOF
md ok-year-not-number.md <<'EOF'
# A

## 2024 年回顾

正文。

## 2026 年展望

正文。
EOF
md ok-codespan-pipe.md <<'EOF'
# A

| 命令 | 说明 |
|---|---|
| `a|b|c` | x |
EOF

# 宽单元格用例（49 个汉字 = 98 显示宽度）
WIDE="$("$PY" -c "print('国'*49)")"
printf '# A\n\n| %s | b |\n|---|---|\n| 1 | 2 |\n' "$WIDE" > "$TD/md/e1-wide-header.md"
printf '# A\n\n| a | b |\n|---|---|\n| %s | 2 |\n' "$WIDE" > "$TD/md/e1-wide-body.md"
printf '# A\n\n+---+---+\n| a | b |\n+===+===+\n| %s | c |\n+---+---+\n' "$WIDE" \
  > "$TD/md/e1-wide-grid.md"

# BOM / GBK
"$PY" - "$TD/md" <<'PYEOF'
import os, sys
d = sys.argv[1]
open(os.path.join(d, 'ok-bom.md'), 'wb').write(
    b'\xef\xbb\xbf' + '# 一、引言\n## 1.1 背景\n\n正文。\n'.encode())
open(os.path.join(d, 'e1-gbk.md'), 'wb').write(
    '# 引言\n\n正文测试。\n'.encode('gbk'))
PYEOF

# 表格线型用例
md tbl-dense.md <<'EOF'
| 项目 | 说明 |
|---|---|
| 甲 | 这一段说明文字刻意写得很长，长到必然会在版心里折行，用来触发行间分界线的自动判定。 |
| 乙 | 另一段同样很长的说明文字，确保两行都超过单行容量，行间线应当加上。 |
EOF
md tbl-sparse.md <<'EOF'
| 端口 | 用途 |
|---|---|
| 8080 | HTTP |
| 5432 | PG |
EOF
md tbl-rowspan.md <<'EOF'
# 测试

+--------+------------------------------------------------------------------+
| 分类   | 说明                                                             |
+========+==================================================================+
| 合并项 | 第一行说明文字，需要足够长以触发行间分界线的自动判定逻辑生效。   |
+        +------------------------------------------------------------------+
|        | 第二行说明文字，同样需要足够长以触发行间分界线的自动判定。       |
+--------+------------------------------------------------------------------+
EOF
md tbl-inline-code.md <<'EOF'
# 测试

| 序号 | 镜像名称 | 说明 |
|---|---|---|
| 1 | `fireline-frontend-service:latest-20260812` | 前端服务镜像，随每次发布重新构建 |
EOF
md tbl-nohead.md <<'EOF'
# 测试

+--------+--------+
| 甲一   | 乙一   |
+--------+--------+
| 甲二   | 乙二   |
+--------+--------+
EOF
md tbl-withhead.md <<'EOF'
# 测试

| 甲 | 乙 |
|---|---|
| 甲二 | 乙二 |
EOF
md tbl-link.md <<'EOF'
# 测试

| 文档 | 链接 |
|---|---|
| 说明 | [官方站点](https://example.com/a) |
EOF

md emoji.md <<'EOF'
单码位: ✅ ❌ ❗ ❓ ⭐

多码位: ✔️ ✖️ ⚠️ ➡️ ⬅️

裸基字符: ✔ ✖ ⚠ ➡ ⬅
EOF

md markers.md <<'EOF'
# 语义标签

## 一、正常用法

[【待确认】]{.mark-confirm} 这是带类的标签。

## 二、裸文字

正文里的【待确认】是普通词语，不该着色。
EOF

md pb-h1-then-h2.md <<'EOF'
# 2026 Q3 季度报告

## 一、概述

正文一。

## 二、结论

正文二。
EOF
md pb-h1-para-h2.md <<'EOF'
# 报告

引言正文。

## 一、概述

正文一。

## 二、结论

正文二。
EOF

md author-list.md <<'EOF'
---
title: 多作者
author:
  - 张三
  - 李四
---

# 多作者

## 一、概述

正文。
EOF
md author-one.md <<'EOF'
---
title: 单作者
author: 王五
---

# 单作者

## 一、概述

正文。
EOF

# 页眉级别用例
md head-two-h1.md <<'EOF'
# 系统设计说明

## 引言

正文一。

# 总体架构

## 分层

正文二。
EOF
md head-single-h1-no-h2.md <<'EOF'
---
title: 单章节说明
---

# 总述

第一段正文，需要足够长以便产生正文页。

第二段正文。
EOF

# 行内代码 / 代码块的 CJK 字体归属。
# 两个 fixture 刻意都「只含中文、不含任何拉丁」——这样 Maple Mono 是否被嵌入
# 就成了二值判据：出现即说明该处 CJK 落在了等宽族上。掺一个拉丁字符，Maple
# 就会因为要供拉丁字形而必然出现，判据立刻失效。
md inline-code-cjk.md <<'EOF'
---
title: 行内代码中文
---

## 行内代码

正文一句 `旧版模块目录` 结束。
EOF

md block-code-cjk.md <<'EOF'
---
title: 代码块中文
---

## 代码块

```text
设备一览
```
EOF

# 目录合并顺序
mkdir -p "$TD/book"
for i in 1 2 10 3; do
  printf -- '---\ntitle: 第%s章\n---\n\n## 第 %s 章\n\n正文。\n' "$i" "$i" \
    > "$TD/book/$i-章节.md"
done

# ---------------------------------------------------------------- syntax
if group "syntax  脚本语法"; then
  # /bin/bash 在 macOS 上是 3.2，是本 skill 的兼容底线。两个已知坑：
  # set -u 下空数组不能 "${arr[@]}" 展开；$( ) 里不能嵌 heredoc。
  for f in export.sh doctor.sh test.sh; do
    if out="$(/bin/bash -n "$SCRIPTS/$f" 2>&1)"; then
      ok "bash 3.2 语法 $f"
    else
      bad "bash 3.2 语法 $f" "$out"
    fi
  done
  for f in md-lint.py docx-postprocess.py build-reference-docx.py; do
    # -W error::SyntaxWarning：docstring 里的 \p 之类无效转义要当错误
    if out="$("$PY" -W error::SyntaxWarning -c "
import py_compile, sys
py_compile.compile(sys.argv[1], cfile='$TD/pyc', doraise=True)
" "$SCRIPTS/$f" 2>&1)"; then
      ok "python 语法 $f"
    else
      bad "python 语法 $f" "$(printf '%s' "$out" | tail -3)"
    fi
  done
  for f in "$ASSETS"/*.lua; do
    if out="$("$PANDOC" lua -e "assert(loadfile('$f'))" 2>&1)"; then
      ok "lua 语法 $(basename "$f")"
    else
      bad "lua 语法 $(basename "$f")" "$out"
    fi
  done
fi

# ---------------------------------------------------------------- chars
if group "chars   显示宽度表一致性"; then
  # tablefit.lua 与 md-lint.py 各有一份 char_width。不一致会导致 lint 说
  # 没超宽而实际排出来溢出 —— 逐码位比对，不是抽样。
  "$PY" - "$ASSETS/tablefit.lua" > "$TD/cw.lua" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'local function char_width\(cp\).*?\nend\n', src, re.S)
if not m:
    sys.stderr.write('未能从 tablefit.lua 抽出 char_width\n')
    sys.exit(3)
print(m.group(0))
print('''
local out = {}
for cp = 0, 0x40000 do
  local wd = char_width(cp)
  if wd ~= 1 then out[#out+1] = cp .. ':' .. wd end
end
io.write(table.concat(out, '\\n'))
''')
PYEOF
  if [[ ! -s "$TD/cw.lua" ]]; then
    bad "抽取 char_width" "正则未命中，tablefit.lua 结构可能变了"
  else
    "$PANDOC" lua "$TD/cw.lua" > "$TD/cw-lua.txt" 2>"$TD/cw-lua.err"
    "$PY" - "$LINT" > "$TD/cw-py.txt" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ml", sys.argv[1])
ml = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ml)
out = []
for cp in range(0, 0x40001):
    w = ml.char_width(chr(cp))
    if w != 1:
        out.append('%d:%d' % (cp, w))
sys.stdout.write('\n'.join(out))
PYEOF
    if [[ ! -s "$TD/cw-lua.txt" ]]; then
      bad "char_width 逐码位比对" "lua 侧无输出：$(head -2 "$TD/cw-lua.err")"
    elif diff -q "$TD/cw-lua.txt" "$TD/cw-py.txt" >/dev/null; then
      ok "char_width 逐码位比对（cp 0..0x40000，$(wc -l < "$TD/cw-py.txt" | tr -d ' ') 个非 1 宽码位）"
    else
      bad "char_width 逐码位比对" \
        "两份实现有差异，前 3 处：$(diff "$TD/cw-lua.txt" "$TD/cw-py.txt" | head -3 | tr '\n' ' ')"
    fi
  fi
fi

# ---------------------------------------------------------------- args
if group "args    参数校验"; then
  # 漏写取值曾经抛 set -u 的 "$2: unbound variable"，看不出是哪个选项
  out="$("$EXPORT" "$TD/md/ok.md" --style 2>&1)"
  has "漏写取值给中文报错" "$out" "缺少取值"

  for pair in "--links blcak:--links 只能是" \
              "--emoji foo:--emoji 只能是" \
              "--table-rule x:--table-rule 只能是" \
              "--toc-depth 9:--toc-depth 只能是" \
              "--to xml:--to 只能是" \
              "--style xx:--style 只能是" \
              "--break-level 9:--break-level 只能是"; do
    flag="${pair%%:*}"; want="${pair##*:}"
    # shellcheck disable=SC2086
    out="$("$EXPORT" "$TD/md/ok.md" $flag 2>&1)"
    has "枚举校验 $flag" "$out" "$want"
  done

  out="$("$EXPORT" "$TD/md/ok.md" --bib /nonexistent.bib 2>&1)"
  has "--bib 文件不存在即报" "$out" "文件不存在"

  # 目录合并按自然序，且把顺序打印出来。
  # 只认横幅里「  N. 文件名」那几行 —— md-lint 也会逐个打印文件名，
  # 直接 grep 文件名会把两处输出混在一起。
  out="$("$EXPORT" "$TD/book" --name 合集 --to docx --out "$TD/out" 2>&1)"
  order="$(printf '%s' "$out" | grep -E '^ +[0-9]+\. .+\.md$' \
    | sed -E 's/^ +[0-9]+\. //' | tr '\n' ' ')"
  eq "1-章节.md 2-章节.md 3-章节.md 10-章节.md " "$order" "目录合并按自然序并打印顺序"

  # tectonic 的字体路径噪音要被过滤掉
  if [[ $FAST -eq 0 ]]; then
    out="$("$EXPORT" "$TD/md/ok.md" --to pdf --out "$TD/out" 2>&1)"
    n="$(printf '%s' "$out" | grep -c 'accessing absolute path')"
    eq "0" "$n" "默认过滤引擎字体路径噪音"
    out="$("$EXPORT" "$TD/md/ok.md" --to pdf --out "$TD/out" --verbose 2>&1)"
    n="$(printf '%s' "$out" | grep -c 'accessing absolute path')"
    if [[ "$n" -gt 0 ]]; then ok "--verbose 放出原始输出（$n 行）"
    else bad "--verbose 放出原始输出" "仍然一行都没有"; fi
  else
    skip "引擎噪音过滤" "--fast"
  fi

  # crossref 状态行曾经打印成「已启用/opt/homebrew/bin/pandoc-crossref」
  out="$("$EXPORT" "$TD/md/ok.md" --to docx --out "$TD/out" 2>&1)"
  hasnt "crossref 状态行不粘连路径" "$out" "已启用/"
fi

# ---------------------------------------------------------------- lint
if group "lint    md-lint 定级"; then
  # 文件名前缀声明期望：e<N>=N 个 error，w<N>=0 error N warn，ok=干净
  lint_counts() {
    "$PY" "$LINT" "$1" --verbose 2>&1 | tail -3
  }
  for f in "$TD"/md/*.md; do
    base="$(basename "$f" .md)"
    sum="$(lint_counts "$f")"
    e="$(printf '%s' "$sum" | grep -oE '错误 [0-9]+' | tail -1 | tr -dc 0-9)"
    w="$(printf '%s' "$sum" | grep -oE '警告 [0-9]+' | tail -1 | tr -dc 0-9)"
    e="${e:-?}"; w="${w:-?}"
    case "$base" in
      e1-*) eq "1" "$e" "error=1  $base" ;;
      w1-*) eq "0" "$e" "error=0  $base"
            if [[ "${w:-0}" -ge 1 ]]; then ok "warn>=1  $base"
            else bad "warn>=1  $base" "警告数 $w"; fi ;;
      ok*)  eq "0" "$e" "error=0  $base" ;;
      *)    : ;;   # tbl-* / pb-* / author-* 等不参与 lint 断言
    esac
  done

  # 定级必须与 pandoc 的实际行为对齐：error 当且仅当真的丢内容
  eq "1" "$(ast_count "$TD/md/e1-indent-head-after-para.md" Header)" \
     "pandoc 实况：缩进标题不被识别（故为 error）"
  eq "1" "$(ast_count "$TD/md/e1-indent-head-after-blank.md" Header)" \
     "pandoc 实况：缩进标题前有空行也不被识别"
  eq "2" "$(ast_count "$TD/md/w1-head-after-para.md" Header)" \
     "pandoc 实况：行首标题紧跟段落仍识别（故只为 warn）"
  eq "0" "$(ast_count "$TD/md/e1-table-no-blank-before.md" Table)" \
     "pandoc 实况：表格前缺空行整张表消失"
  eq "0" "$(ast_count "$TD/md/e1-table-after-list.md" Table)" \
     "pandoc 实况：列表后紧跟表格整张表消失"
  eq "1" "$(ast_count "$TD/md/ok.md" Table)" \
     "pandoc 实况：正确写法表格在位"

  # 分隔行少列 → 整列丢失
  cols="$("$PANDOC" --from="$FROMSPEC" -t markdown "$TD/md/e1-delim-short.md" 2>/dev/null \
    | grep -c '丙')"
  eq "0" "$cols" "pandoc 实况：分隔行少列时「丙」整列丢失"

  # 非 UTF-8 混在批量里不能中断后续检查
  out="$("$PY" "$LINT" "$TD/md/ok.md" "$TD/md/e1-gbk.md" "$TD/md/ok-bom.md" 2>&1)"
  has "GBK 不中断批量（汇总仍打印）" "$out" "共检查 3 个文件"
  hasnt "GBK 不抛 traceback" "$out" "Traceback"

  # --strict 退出码
  "$PY" "$LINT" "$TD/md/ok.md" --strict >/dev/null 2>&1
  eq "0" "$?" "--strict 正确文档退出 0"
  "$PY" "$LINT" "$TD/md/e1-indent-head-after-para.md" --strict >/dev/null 2>&1
  eq "1" "$?" "--strict 有 error 退出 1"
  "$PY" "$LINT" "$TD/md/w1-head-after-para.md" --strict >/dev/null 2>&1
  eq "0" "$?" "--strict 只有 warn 退出 0"
fi

# ---------------------------------------------------------------- filters
if group "filters lua filter 行为"; then
  # 列宽：同一张表两侧必须一致。行内代码曾在 latex 侧被量成 0 宽。
  cat > "$TD/dump.lua" <<'EOF'
function Table(t)
  local s = {}
  for _, c in ipairs(t.colspecs) do
    s[#s+1] = string.format("%s/%.4f", tostring(c[1]),
      (type(c[2]) == "number") and c[2] or -1)
  end
  io.stderr:write(table.concat(s, " ") .. "\n")
end
EOF
  colspec() {
    "$PANDOC" --from="$FROMSPEC" "$1" -t "$2" \
      --lua-filter="$ASSETS/sanitize.lua" \
      --lua-filter="$ASSETS/tablefit.lua" \
      --lua-filter="$TD/dump.lua" -o /dev/null 2>&1 | tail -1
  }
  a="$(colspec "$TD/md/tbl-inline-code.md" latex)"
  b="$(colspec "$TD/md/tbl-inline-code.md" docx)"
  eq "$b" "$a" "含行内代码的表格两侧列宽一致"

  a="$(colspec "$TD/md/tbl-dense.md" latex)"
  b="$(colspec "$TD/md/tbl-dense.md" docx)"
  eq "$b" "$a" "长文本表格两侧列宽一致"

  # 行间线：auto/three/grid 三种模式
  rules() {
    "$PANDOC" --from="$FROMSPEC" "$1" -t latex \
      --lua-filter="$ASSETS/sanitize.lua" \
      --lua-filter="$ASSETS/tablefit.lua" \
      -M "table-rule=$2" 2>/dev/null | grep -c perowrule
  }
  if [[ "$(rules "$TD/md/tbl-dense.md" auto)" -ge 1 ]]; then
    ok "auto：长文本表加行间线"
  else bad "auto：长文本表加行间线" "perowrule 数为 0"; fi
  eq "0" "$(rules "$TD/md/tbl-sparse.md" auto)"  "auto：短词表不加行间线"
  eq "0" "$(rules "$TD/md/tbl-dense.md" three)"  "three：强制纯三线表"
  if [[ "$(rules "$TD/md/tbl-sparse.md" grid)" -ge 1 ]]; then
    ok "grid：强制加线"
  else bad "grid：强制加线" "perowrule 数为 0"; fi
  # 合并单元格的行必须跳过 —— 插进去 XeTeX 报 Misplaced \noalign，PDF 出不来
  eq "0" "$(rules "$TD/md/tbl-rowspan.md" auto)" "合并单元格行不插 \\noalign（auto）"
  eq "0" "$(rules "$TD/md/tbl-rowspan.md" grid)" "合并单元格行不插 \\noalign（grid）"

  # emoji：单码位 / 多码位（基字符+VS16）/ 裸基字符
  out="$("$PANDOC" --from="$FROMSPEC" "$TD/md/emoji.md" -t plain \
    --lua-filter="$ASSETS/sanitize.lua" 2>/dev/null)"
  eq "单码位: √ × ! ? ★" "$(printf '%s' "$out" | grep '单码位')" "emoji 单码位映射"
  eq "多码位: √ × ! → ←" "$(printf '%s' "$out" | grep '多码位')" "emoji 多码位映射"
  eq "裸基字符: √ × ! → ←" "$(printf '%s' "$out" | grep '裸基字符')" "emoji 裸基字符映射"
  out="$("$PANDOC" --from="$FROMSPEC" "$TD/md/emoji.md" -t plain \
    --lua-filter="$ASSETS/sanitize.lua" -M emoji=strip 2>/dev/null)"
  hasnt "emoji strip 模式清空" "$out" "✔"

  # pagebreak：H1 紧跟 H2 不该分页；H1 + 正文 + H2 照常分页
  pbcount() {
    "$PANDOC" --from="$FROMSPEC" "$1" -t latex \
      --lua-filter="$ASSETS/title-dedup.lua" \
      --lua-filter="$ASSETS/pagebreak.lua" \
      -M "title=季度报告" -M "break-level=2" -M "front-break=false" 2>/dev/null \
      | grep -c clearpage
  }
  eq "1" "$(pbcount "$TD/md/pb-h1-then-h2.md")" "H1 紧跟 H2 不多插分页"
  eq "2" "$(pbcount "$TD/md/pb-h1-para-h2.md")" "H1+正文+H2 照常分页"

  # 语义标签：两侧都只认带类的 Span
  n="$("$PANDOC" --from="$FROMSPEC" "$TD/md/markers.md" -t latex \
    --lua-filter="$ASSETS/semantic-markers.lua" 2>/dev/null | grep -c colorbox)"
  eq "1" "$n" "PDF 侧只给带类的 Span 着色"
  n="$("$PANDOC" --from="$FROMSPEC" "$TD/md/markers.md" -t docx \
    --lua-filter="$ASSETS/semantic-markers.lua" -o "$TD/mk.docx" 2>/dev/null; \
    "$PY" -c "
import zipfile, re
x = zipfile.ZipFile('$TD/mk.docx').read('word/document.xml').decode()
print(len(re.findall(r'PEMark\w+', x)))")"
  eq "1" "$n" "Word 侧只给带类的 Span 打标记"
fi

# ---------------------------------------------------------------- docx
if group "docx    Word 后处理"; then
  dx() {   # dx <md> <name> [额外参数...]
    local m="$1" nm="$2"; shift 2
    "$EXPORT" "$TD/md/$m" --to docx --out "$TD/out" --name "$nm" "$@" >/dev/null 2>&1
    echo "$TD/out/$nm.docx"
  }
  xml() { unzip -p "$1" "word/${2:-document}.xml" 2>/dev/null; }

  # 页眉级别：Word 的 STYLEREF 必须与 export.sh 打印的、PDF 的 \peheadlevel 一致
  out="$("$EXPORT" "$TD/md/head-two-h1.md" --style modern --to docx \
    --out "$TD/out" --name h2h1 2>&1)"
  printed="$(printf '%s' "$out" | grep -oE '页眉取第 [0-9]+ 级' | grep -oE '[0-9]+')"
  actual="$(xml "$TD/out/h2h1.docx" header1 | grep -oE 'STYLEREF [0-9]+' | head -1 | grep -oE '[0-9]+')"
  eq "$printed" "$actual" "Word STYLEREF 与 export.sh 打印的级别一致"

  out="$("$EXPORT" "$TD/md/head-two-h1.md" --style modern --break-level 2 --to docx \
    --out "$TD/out" --name h2h1b 2>&1)"
  printed="$(printf '%s' "$out" | grep -oE '页眉取第 [0-9]+ 级' | grep -oE '[0-9]+')"
  actual="$(xml "$TD/out/h2h1b.docx" header1 | grep -oE 'STYLEREF [0-9]+' | head -1 | grep -oE '[0-9]+')"
  eq "$printed" "$actual" "--break-level 2 时两处级别仍一致"

  # 目标级别不存在 → 必须删掉整个 STYLEREF 域，否则页眉每页印
  # 「Error: Reference source not found」
  f="$(dx head-single-h1-no-h2.md nostyleref --style modern)"
  eq "0" "$(xml "$f" header1 | grep -c STYLEREF)" "无对应级别时移除 STYLEREF 域"
  has "页眉左侧标题仍保留" "$(xml "$f" header1)" "单章节说明"

  # 无表头表格：第一行是真实数据，不能加粗 / 划表头下线 / 标 tblHeader
  f="$(dx tbl-nohead.md nohead --style report)"
  "$PY" - "$f" <<'PYEOF' > "$TD/nohead.txt"
import re, sys, zipfile
x = zipfile.ZipFile(sys.argv[1]).read("word/document.xml").decode()
t = x[x.find("<w:tbl>"):x.find("</w:tbl>")]
r0 = t[:t.find("</w:tr>")]
print("tblHeader=%s bold=%s borders=%s" % (
    "<w:tblHeader" in r0, bool(re.search(r"<w:b\b", r0)), "<w:tcBorders>" in r0))
PYEOF
  eq "tblHeader=False bold=False borders=False" "$(cat "$TD/nohead.txt")" \
     "无表头表格首行不被当表头"

  f="$(dx tbl-withhead.md withhead --style report)"
  "$PY" - "$f" <<'PYEOF' > "$TD/withhead.txt"
import re, sys, zipfile
x = zipfile.ZipFile(sys.argv[1]).read("word/document.xml").decode()
t = x[x.find("<w:tbl>"):x.find("</w:tbl>")]
r0 = t[:t.find("</w:tr>")]
print("tblHeader=%s bold=%s borders=%s" % (
    "<w:tblHeader" in r0, bool(re.search(r"<w:b\b", r0)), "<w:tcBorders>" in r0))
PYEOF
  eq "tblHeader=True bold=True borders=True" "$(cat "$TD/withhead.txt")" \
     "有表头表格首行仍正常处理"

  # 表格里的超链接：run 包在 w:hyperlink 里，曾经漏掉字号与字体
  f="$(dx tbl-link.md link --style modern)"
  "$PY" - "$f" <<'PYEOF' > "$TD/link.txt"
import re, sys, zipfile
x = zipfile.ZipFile(sys.argv[1]).read("word/document.xml").decode()
m = re.search(r"<w:hyperlink[^>]*>(.*?)</w:hyperlink>", x, re.S)
seg = m.group(1) if m else ""
print("sz=%s font=%s" % (
    re.findall(r'<w:sz w:val="(\d+)"', seg) or "无",
    "有" if re.search(r'w:ascii="Alibaba', seg) else "无"))
PYEOF
  eq "sz=['21'] font=有" "$(cat "$TD/link.txt")" "表格内超链接有字号与字体"

  # --footer-total：页眉、正文页脚、目录页脚三处字体必须一致
  f="$(dx tbl-link.md ft --style modern --footer-total)"
  fonts=""
  for part in header1 footer1 footer2; do
    fonts="$fonts$(xml "$f" "$part" | grep -o 'w:ascii="[^"]*"' | head -1) "
  done
  eq 'w:ascii="宋体" w:ascii="宋体" w:ascii="宋体" ' "$fonts" \
     "--footer-total 三处页眉页脚同字体"

  # 语义标签：只有带类的着色，且不留 rStyle
  f="$(dx markers.md markers)"
  "$PY" - "$f" <<'PYEOF' > "$TD/mk.txt"
import re, sys, zipfile
x = zipfile.ZipFile(sys.argv[1]).read("word/document.xml").decode()
print("shd=%d rstyle=%d" % (len(re.findall(r'w:fill="FCE8E6"', x)),
                            len(re.findall(r"PEMark\w+", x))))
PYEOF
  eq "shd=1 rstyle=0" "$(cat "$TD/mk.txt")" "Word 只给带类标签着色且清掉 rStyle"

  # author 为 YAML 列表：两侧都该是「张三、李四」
  f="$(dx author-list.md aulist)"
  has "Word 封面多作者用「、」连接" "$(xml "$f")" "张三、李四"
  f="$(dx author-one.md auone)"
  has "Word 封面单作者不变" "$(xml "$f")" "王五"

  # 幂等：同参数重跑后处理，全部部件字节相同
  f="$(dx ok.md idem --style modern)"
  cp "$f" "$TD/out/idem2.docx"
  "$PY" "$POST" "$TD/out/idem2.docx" --style modern --title "正确文档" \
    --toc 1 --table-rule auto --footer-total 0 --head-level 2 >/dev/null 2>&1
  "$PY" - "$f" "$TD/out/idem2.docx" <<'PYEOF' > "$TD/idem.txt"
import hashlib, sys, zipfile
a, b = (zipfile.ZipFile(p) for p in sys.argv[1:3])
na, nb = sorted(a.namelist()), sorted(b.namelist())
if na != nb:
    print("部件列表不同")
else:
    d = [n for n in na
         if hashlib.sha256(a.read(n)).hexdigest()
         != hashlib.sha256(b.read(n)).hexdigest()]
    print(",".join(d) if d else "幂等")
PYEOF
  eq "幂等" "$(cat "$TD/idem.txt")" "后处理幂等（重跑字节相同）"

  # 五套预设都要能产出 docx
  for st in modern modern-plain report gb brief; do
    f="$(dx markers.md "p-$st" --style "$st")"
    if [[ -s "$f" ]]; then ok "预设 $st 产出 docx"
    else bad "预设 $st 产出 docx" "文件为空或不存在"; fi
  done

  # 代码块与行内代码的 CJK 归属 —— 与 pdf 组那两条守的是同一条边界，只是
  # Word 侧断在样式表上：rFonts 的 ascii/hAnsi 与 eastAsia 本就分开，
  # 不需要 PDF 侧 \DeclareTextFontCommand 那样的绕法。
  #   SourceCode（代码块）   eastAsia=MONO —— 中文 2 倍宽，ASCII 框图才不散架
  #   VerbatimChar（行内代码）eastAsia≠MONO —— 嵌在句子里，中文跟随正文
  # 注意：真实 Microsoft Word 的渲染无法在 CI 里验证，soffice 预览下 eastAsia
  # 会回退到苹方（见 references/typography.md），所以这里只断言样式表写对，
  # 不断言渲染结果。
  ea() {  # ea <docx> <styleId> → 该样式 rFonts 的 eastAsia 值
    xml "$1" styles | "$PY" -c '
import sys, re
x = sys.stdin.read()
m = re.search(r"w:styleId=\"" + sys.argv[1] + r"\".*?</w:style>", x, re.S)
f = re.search(r"<w:rFonts[^/]*?w:eastAsia=\"([^\"]+)\"", m.group(0)) if m else None
print(f.group(1) if f else "")
' "$2"
  }
  if [[ -n "$PY" ]]; then
    d="$(dx ok.md codefont --style modern)"
    eq "Maple Mono CN" "$(ea "$d" SourceCode)" \
       "Word 代码块的 CJK 是等宽（框图 2:1 对齐）"
    vc="$(ea "$d" VerbatimChar)"
    if [[ -n "$vc" && "$vc" != "Maple Mono CN" ]]; then
      ok "Word 行内代码的 CJK 跟随正文族"
    else
      bad "Word 行内代码的 CJK 跟随正文族" "eastAsia=[$vc]"
    fi
  else
    skip "Word 代码字体归属" "无 python3"
  fi
fi

# ---------------------------------------------------------------- pdf
if group "pdf     PDF 导出"; then
  if [[ $FAST -eq 1 ]]; then
    skip "PDF 导出全部断言" "--fast"
  else
    for st in modern modern-plain report gb brief; do
      if "$EXPORT" "$TD/md/markers.md" --style "$st" --to pdf \
           --out "$TD/out" --name "q-$st" >"$TD/pdf-$st.log" 2>&1 \
         && [[ -s "$TD/out/q-$st.pdf" ]]; then
        ok "预设 $st 产出 PDF"
      else
        bad "预设 $st 产出 PDF" "$(grep -iE 'error|!' "$TD/pdf-$st.log" | head -2)"
      fi
    done

    # 合并单元格 + 长内容：曾经 100% 编译失败（Misplaced \noalign）
    if "$EXPORT" "$TD/md/tbl-rowspan.md" --to pdf --out "$TD/out" \
         --name rowspan >"$TD/pdf-rowspan.log" 2>&1 \
       && [[ -s "$TD/out/rowspan.pdf" ]]; then
      ok "合并单元格表格能导出 PDF"
    else
      bad "合并单元格表格能导出 PDF" \
        "$(grep -iE 'noalign|error' "$TD/pdf-rowspan.log" | head -2)"
    fi

    # emoji：✖ ➡ ⬅ 曾经 Missing character 静默丢字
    "$EXPORT" "$TD/md/emoji.md" --to pdf --out "$TD/out" --name emo \
      --verbose >"$TD/pdf-emo.log" 2>&1
    n="$(grep -ci 'missing character' "$TD/pdf-emo.log")"
    eq "0" "$n" "emoji 文档无 Missing character"

    # preamble 里 \pe@sym / \pe@symalt 声明的每个符号都必须真有字形。
    # 这条断言抓出过 ★ U+2605 与 ☆ U+2606：注释写着 symbolfont 覆盖更全，
    # 而 Maple Mono NF CN Regular 里这两个恰恰是空的，PDF 里静默丢字。
    "$PY" - "$ASSETS/preamble-common.tex" > "$TD/syms.md" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
pts = re.findall(r'\\pe@sym(?:alt)?\{(.)\}\{([0-9A-Fa-f]+)\}', src)
print('# 符号字形覆盖\n')
for ch, cp in pts:
    print('U+%s %s\n' % (cp.upper(), ch))
print('<!-- %d 个符号 -->' % len(pts))
PYEOF
    nsym="$(grep -c '^U+' "$TD/syms.md")"
    "$EXPORT" "$TD/syms.md" --to pdf --out "$TD/out" --name syms \
      --no-lint --verbose >"$TD/pdf-syms.log" 2>&1
    miss="$(grep -i 'missing character' "$TD/pdf-syms.log" \
      | grep -oE 'U\+[0-9A-F]+' | sort -u | tr '\n' ' ')"
    if [[ -z "$miss" ]]; then
      ok "preamble 声明的 $nsym 个符号全部有字形"
    else
      bad "preamble 声明的 $nsym 个符号全部有字形" "缺字形: $miss"
    fi

    # author 列表：PDF 封面「编制人」整行曾经消失
    "$EXPORT" "$TD/md/author-list.md" --to pdf --out "$TD/out" --name aupdf \
      >/dev/null 2>&1
    if command -v pdftotext >/dev/null 2>&1; then
      has "PDF 封面多作者用「、」连接" \
        "$(pdftotext -layout "$TD/out/aupdf.pdf" - 2>/dev/null | tr -d ' ')" "张三、李四"
    else
      skip "PDF 封面多作者" "无 pdftotext"
    fi

    # PDF 侧的 \peheadlevel 与 Word 的 STYLEREF 必须同源。
    # 两侧产物都自己生成 —— 不依赖 docx 组跑过，`-k pdf` 要能单独成立。
    "$EXPORT" "$TD/md/head-two-h1.md" --style modern --to pdf --keep-tex \
      --out "$TD/out" --name hlpdf >/dev/null 2>&1
    "$EXPORT" "$TD/md/head-two-h1.md" --style modern --to docx \
      --out "$TD/out" --name hlw >/dev/null 2>&1
    lv="$(grep -oE 'peheadlevel\{[0-9]\}' "$TD/out/hlpdf.tex" 2>/dev/null \
      | head -1 | grep -oE '[0-9]')"
    wv="$(unzip -p "$TD/out/hlw.docx" word/header1.xml 2>/dev/null \
      | grep -oE 'STYLEREF [0-9]+' | head -1 | grep -oE '[0-9]+')"
    eq "${wv:-?w}" "${lv:-?p}" "PDF \\peheadlevel 与 Word STYLEREF 同值"

    # 语义标签：PDF 侧只给带类的着色
    "$EXPORT" "$TD/md/markers.md" --to pdf --keep-tex --out "$TD/out" \
      --name mkpdf >/dev/null 2>&1
    eq "1" "$(grep -c colorbox "$TD/out/mkpdf.tex" 2>/dev/null)" \
       "PDF 只给带类标签着色"

    # 行内代码的 CJK 必须跟随正文族，代码块的必须留在等宽族 —— 这条边界两侧
    # 都要守。行内代码嵌在句子里，中文若落等宽，同一行会并排出现两种中文字体
    # （曾经如此，技术文档里带中文的路径/表名一多，整页观感就是「中英文字体
    # 不一致」）；而代码块的中文一旦离开等宽，就不再是拉丁的 2 倍宽，
    # ASCII 框图当场错位。修前者时顺手把 \setCJKmonofont 一起改掉，
    # 是最容易犯的过头修法，第二条断言专门拦它。
    if command -v pdffonts >/dev/null 2>&1; then
      "$EXPORT" "$TD/md/inline-code-cjk.md" --to pdf --no-toc \
        --out "$TD/out" --name icjk >/dev/null 2>&1
      "$EXPORT" "$TD/md/block-code-cjk.md" --to pdf --no-toc \
        --out "$TD/out" --name bcjk >/dev/null 2>&1
      eq "0" "$(pdffonts "$TD/out/icjk.pdf" 2>/dev/null | grep -c Maple)" \
         "行内代码的 CJK 跟随正文族"
      if [[ -n "$(fc-list 2>/dev/null | grep -i 'Maple Mono CN')" ]]; then
        eq "1" "$(pdffonts "$TD/out/bcjk.pdf" 2>/dev/null | grep -c Maple)" \
           "代码块的 CJK 仍在等宽族（框图 2:1 对齐）"
      else
        skip "代码块 CJK 等宽" "无 Maple Mono CN"
      fi
    else
      skip "行内代码 / 代码块 CJK 字体归属" "无 pdffonts"
    fi
  fi
fi

# ---------------------------------------------------------------- render
if group "render  soffice 渲染"; then
  if [[ $RENDER -eq 0 ]]; then
    skip "渲染断言" "需 --render"
  elif ! command -v soffice >/dev/null 2>&1; then
    skip "渲染断言" "无 soffice"
  else
    for st in modern report gb brief; do
      d="$TD/out/p-$st.docx"
      [[ -s "$d" ]] || { skip "渲染 $st" "无 docx，先跑 docx 组"; continue; }
      if soffice --headless --convert-to pdf --outdir "$TD/out" "$d" \
           >/dev/null 2>&1 && [[ -s "$TD/out/p-$st.pdf" ]]; then
        ok "渲染 $st 无损坏"
      else
        bad "渲染 $st 无损坏" "soffice 转换失败，通常意味着 OOXML 结构非法"
      fi
    done
    # 页眉不能印出域错误
    d="$TD/out/nostyleref.docx"
    if [[ -s "$d" ]]; then
      soffice --headless --convert-to pdf --outdir "$TD/out" "$d" >/dev/null 2>&1
      txt="$(pdftotext -layout "$TD/out/nostyleref.pdf" - 2>/dev/null)"
      hasnt "页眉无 Reference source not found" "$txt" "Reference source"
    fi
  fi
fi

# ---------------------------------------------------------------- 汇总
printf '\n%s─────────────────────────────────────────%s\n' "$B" "$Z"
printf '  %s通过 %d%s' "$G" "$PASS" "$Z"
[[ $FAIL -gt 0 ]] && printf '   %s失败 %d%s' "$R" "$FAIL" "$Z"
[[ $SKIP -gt 0 ]] && printf '   %s跳过 %d%s' "$Y" "$SKIP" "$Z"
printf '\n'
if [[ $FAIL -gt 0 ]]; then
  printf '%s失败项:%s%s\n' "$R" "$Z" "$FAILED_NAMES"
  printf '\n%s排查：--keep 保留产物，-k <组名> 只跑一组，-v 打印全部通过项%s\n' \
    "$D" "$Z"
  exit 1
fi
[[ $FAST -eq 1 ]] && printf '%s（--fast：跳过了 PDF 编译，提交前请跑一遍全量）%s\n' "$D" "$Z"
exit 0
