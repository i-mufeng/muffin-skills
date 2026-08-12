#!/usr/bin/env bash
# ============================================================
#  paper-export :: 依赖自检
#
#  用法: doctor.sh [--install]
#        --install   自动补装缺失的 Homebrew 组件（只装 CLI，不装 cask）
#        -h|--help   显示帮助
#
#  图例: ✓ 就绪    ✗ 缺失（必需）    ○ 未装（可选，不影响基本导出）
# ============================================================
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$SKILL_DIR/assets"
SCRIPTS="$SKILL_DIR/scripts"

DO_INSTALL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) DO_INSTALL=1; shift ;;
    -h|--help)
      sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^#[[:space:]]\{0,2\}//'
      exit 0 ;;
    *) echo "未知选项: $1（只支持 --install / --help）" >&2; exit 2 ;;
  esac
done

OK="✓"; NO="✗"; OPT="○"

fatal=0        # 必需项缺失数
warn=0         # 建议项缺失数
optn=0         # 可选项未装数
missing_brew=()
hints=()

add_hint() { hints+=("$1"); }

# ---------- 对齐：printf 的 %-Ns 按字节算，中文标签会错位 ----------
_utf8_ok=0
_probe() { local LC_ALL=en_US.UTF-8 s="中文"; [[ ${#s} -eq 2 ]]; }
_probe && _utf8_ok=1

dwidth() {
  local s="$1"
  if [[ $_utf8_ok -eq 1 ]]; then
    local LC_ALL=C;           local b=${#s}
    LC_ALL=en_US.UTF-8;       local c=${#s}
    echo $(( (b + c) / 2 ))
  else
    echo ${#s}
  fi
}

say() {   # $1=图标  $2=名称  $3=说明
  local w pad
  w="$(dwidth "$2")"
  pad=$(( 26 - w )); [[ $pad -lt 1 ]] && pad=1
  printf "  %s %s%*s%s\n" "$1" "$2" "$pad" "" "$3"
}

sect() { printf "\n\033[1m%s\033[0m\n" "$1"; }

echo "── paper-export 依赖自检 ──────────────────────────────"

# ============================================================
#  1. 必需
# ============================================================
sect "[必需]"

# ---- pandoc ----
# pandoc-crossref 是针对特定 pandoc 版本编译的；anaconda / conda 环境里那份
# pandoc 常与它的 AST 版本对不上，filter 会直接崩。优先取 Homebrew 的。
PANDOC=""
for c in /opt/homebrew/bin/pandoc /usr/local/bin/pandoc "$(command -v pandoc || true)"; do
  [[ -n "$c" && -x "$c" ]] && { PANDOC="$c"; break; }
done
PANDOC_VER=""
if [[ -n "$PANDOC" ]]; then
  PANDOC_VER="$("$PANDOC" --version 2>/dev/null | head -1 | awk '{print $2}')"
  PMAJ="${PANDOC_VER%%.*}"
  if [[ "${PMAJ:-0}" -ge 3 ]] 2>/dev/null; then
    say "$OK" "pandoc" "$PANDOC_VER   $PANDOC"
  else
    say "$NO" "pandoc" "$PANDOC_VER 过旧 —— 需要 ≥ 3.0"
    missing_brew+=(pandoc); fatal=$((fatal+1))
    add_hint "升级 pandoc（≥3.0）：brew install pandoc  或  brew upgrade pandoc"
  fi
  if [[ "$PANDOC" != /opt/homebrew/* && "$PANDOC" != /usr/local/* ]]; then
    say " " "" "! 非 Homebrew 版本（$PANDOC）"
    say " " "" "  conda 等环境的 pandoc 常与 pandoc-crossref 版本错配"
    add_hint "改用 Homebrew 的 pandoc：brew install pandoc（export.sh 会自动优先选它）"
  fi
else
  say "$NO" "pandoc" "未安装 —— 必需"
  missing_brew+=(pandoc); fatal=$((fatal+1))
  add_hint "安装 pandoc：brew install pandoc"
fi

# ---- python3 ----
PY="$(command -v python3 || true)"
if [[ -n "$PY" ]]; then
  say "$OK" "python3" "$("$PY" -V 2>&1 | awk '{print $2}')   $PY"
else
  say "$NO" "python3" "未安装 —— md-lint / Word 后处理 / 母版生成都要用"
  fatal=$((fatal+1))
  add_hint "安装 python3：brew install python@3.12   （macOS 自带的在 /usr/bin/python3）"
fi

# ============================================================
#  2. PDF 引擎（二选一）
# ============================================================
sect "[PDF 引擎 —— 二选一即可]"

ENGINE=""
for e in xelatex lualatex tectonic; do
  if command -v "$e" >/dev/null 2>&1; then
    [[ -z "$ENGINE" ]] && ENGINE="$e"
    say "$OK" "$e" "$(command -v "$e")"
  else
    say "$OPT" "$e" "未安装"
  fi
done

if [[ -n "$ENGINE" ]]; then
  say " " "" "export.sh 将使用：$ENGINE"
  [[ "$ENGINE" == "tectonic" ]] && \
    say " " "" "首次编译需联网下载宏包（约 1–2 分钟），之后走本地缓存"
else
  say "$NO" "（无可用引擎）" "PDF 导出不可用；--to docx 仍可用"
  missing_brew+=(tectonic); fatal=$((fatal+1))
  add_hint "装轻量引擎（推荐，约 30 MB）：brew install tectonic"
  add_hint "或装完整 TeX Live（约 5 GB，含 xelatex）：brew install --cask mactex-no-gui"
fi

# ============================================================
#  3. 可选组件
# ============================================================
sect "[可选]"

if command -v pandoc-crossref >/dev/null 2>&1; then
  say "$OK" "pandoc-crossref" "$(pandoc-crossref --version 2>/dev/null | head -1 | awk '{print $2}')"
else
  say "$OPT" "pandoc-crossref" "未装 —— @fig: / @tbl: / @eq: 交叉引用不可用"
  missing_brew+=(pandoc-crossref); optn=$((optn+1))
  add_hint "装交叉引用支持：brew install pandoc-crossref"
fi

if command -v soffice >/dev/null 2>&1; then
  say "$OK" "soffice" "$(command -v soffice)"
else
  say "$OPT" "soffice" "未装 —— 无法用命令行预览 Word 输出"
  optn=$((optn+1))
  add_hint "装 LibreOffice 以预览 Word：brew install --cask libreoffice"
fi

if command -v rsvg-convert >/dev/null 2>&1; then
  say "$OK" "rsvg-convert" "$(command -v rsvg-convert)"
else
  say "$OPT" "rsvg-convert" "未装 —— 文档里有 .svg 图片时才需要"
  missing_brew+=(librsvg); optn=$((optn+1))
  add_hint "支持 SVG 图片：brew install librsvg"
fi

CSL="$ASSETS/gb-t-7714-2015-numeric.csl"
if [[ -f "$CSL" ]]; then
  say "$OK" "GB/T 7714 CSL" "已就位"
else
  say "$OPT" "GB/T 7714 CSL" "未装 —— 仅 --bib 引参考文献且要国标格式时需要"
  optn=$((optn+1))
  add_hint "装中文国标参考文献样式（约 30 KB）：
    curl -fsSL -o '$CSL' \\
      https://raw.githubusercontent.com/citation-style-language/styles/master/china-national-standard-gb-t-7714-2015-numeric.csl"
fi

# ============================================================
#  4. 字体
# ============================================================
sect "[字体]"

# 字体名可能是族名（Songti SC）也可能是全名（Heiti SC Medium，族名其实是
# Heiti SC）。所以 family / fullname / postscriptname 三种都收进来一起查。
FONT_DB=""
FONT_SRC=""
if command -v fc-list >/dev/null 2>&1; then
  FONT_DB="$(fc-list -f '%{family}\n%{fullname}\n%{postscriptname}\n' 2>/dev/null \
             | tr ',' '\n' | sed 's/\\//g')"
  FONT_SRC="fc-list"
elif [[ "$(uname -s)" == "Darwin" ]] && command -v system_profiler >/dev/null 2>&1; then
  FONT_DB="$(system_profiler SPFontsDataType 2>/dev/null \
             | sed -n 's/^[[:space:]]*\(Full Name\|Family\):[[:space:]]*//p')"
  FONT_SRC="system_profiler"
fi

# 用 here-string 而不是管道：grep -q 命中后立刻退出，会给上游 printf 一个
# SIGPIPE，在 set -o pipefail 下整条管道返回 141，字体全被误判成缺失。
has_font() { grep -Fqix "$1" <<< "$FONT_DB"; }

# 名称|用途|是否必需(1/0)
FONT_LIST=(
  "Songti SC|正文宋体（PDF）|1"
  "Heiti SC Medium|标题黑体（PDF）|1"
  "Heiti SC|三级有序列表的 ①②③（宋体无此区段）|1"
  "Menlo|等宽 + 框线/箭头符号兜底|1"
  "Kaiti SC|封面信息栏楷体 / brief 的副标题与三级标题|0"
  "STFangsong|brief（简报）预设的正文仿宋|0"
  "AlibabaPuHuiTi_3_55_Regular|modern（默认）预设的正文|0"
  "AlibabaPuHuiTi_3_85_Bold|modern 预设的标题|0"
  "AlibabaPuHuiTi_3_65_Medium|modern 预设的四级标题|0"
  "Maple Mono CN|代码块 / ASCII 框图等宽（中文恰好 2 倍宽）|0"
  "Noto Serif CJK SC Black|brief 文头的小标宋替代|0"
)

if [[ -z "$FONT_DB" ]]; then
  say "$OPT" "字体检查" "跳过 —— 既没有 fc-list 也没有 system_profiler"
  add_hint "装 fontconfig 以启用字体检查：brew install fontconfig"
else
  for row in "${FONT_LIST[@]}"; do
    fname="${row%%|*}"; rest="${row#*|}"
    fdesc="${rest%%|*}"; freq="${rest##*|}"
    if has_font "$fname"; then
      say "$OK" "$fname" "$fdesc"
    elif [[ "$freq" == "1" ]]; then
      say "$NO" "$fname" "缺失 —— $fdesc"
      fatal=$((fatal+1))
    else
      say "$OPT" "$fname" "缺失 —— $fdesc（会自动回退，观感略有出入）"
      warn=$((warn+1))
    fi
  done
  say " " "" "（检测方式：$FONT_SRC）"
  if [[ $fatal -gt 0 || $warn -gt 0 ]]; then
    add_hint "字体在 macOS 上均为系统自带，缺失通常是被「字体册」停用或删除了：
    打开「字体册」→ 全部字体 → 找到对应字体 → 右键启用；
    或「文件 → 恢复标准字体」。
    非 macOS 请改绑替代字体（见 references/troubleshooting.md §5.7）：
      正文宋体 → SimSun / Noto Serif CJK SC
      标题黑体 → SimHei / Noto Sans CJK SC
      等宽     → Consolas / DejaVu Sans Mono
    改 assets/preamble-common.tex 与 scripts/build-reference-docx.py 顶部常量，
    改完重新生成 Word 母版。"
  fi
fi

# ============================================================
#  5. Word 母版
# ============================================================
sect "[Word 母版]"

ref_missing=0
for s in modern report gb brief; do
  f="$ASSETS/reference-$s.docx"
  if [[ -f "$f" ]]; then
    say "$OK" "reference-$s.docx" "$(du -h "$f" | awk '{print $1}')"
  else
    say "$NO" "reference-$s.docx" "缺失 —— Word 会退回 pandoc 自带西文母版（Letter 纸、蓝标题）"
    ref_missing=1; fatal=$((fatal+1))
  fi
done
[[ $ref_missing -eq 1 ]] && \
  add_hint "重新生成 Word 母版：
    python3 '$SCRIPTS/build-reference-docx.py' all"

# ============================================================
#  6. skill 自身文件
# ============================================================
sect "[skill 文件完整性]"

miss_files=0

check_file() {   # $1=路径 $2=说明
  if [[ -f "$1" ]]; then
    say "$OK" "$(basename "$1")" "$2"
  else
    say "$NO" "$(basename "$1")" "缺失 —— $2"
    miss_files=$((miss_files+1)); fatal=$((fatal+1))
  fi
}

for pair in \
  "sanitize.lua|清洗 emoji / 零宽字符，行内代码断行" \
  "title-dedup.lua|摘掉与封面同名的首个 H1" \
  "pagebreak.lua|章级分页 / 目录独占一页" \
  "tablefit.lua|表格列宽按内容重算" \
  "cover-docx.lua|Word 封面"
do
  check_file "$ASSETS/${pair%%|*}" "${pair#*|}"
done

for pair in \
  "preamble-common.tex|字体 / 表格 / 列表 / 代码块" \
  "preamble-report.tex|report 预设版式" \
  "preamble-gb.tex|gb 预设版式" \
  "preamble-brief.tex|brief 预设版式" \
  "preamble-modern.tex|modern 预设字体覆盖层" \
  "preamble-modern-plain.tex|modern-plain 无封面标题层" \
  "titlepage.tex|PDF 封面" \
  "masthead-brief.tex|brief 文头（PDF）" \
  "signoff-brief.tex|brief 落款（PDF）" \
  "before-body.tex|封面→前置节切换" \
  "crossref-report.yaml|report 图表编号格式" \
  "crossref-gb.yaml|gb 图表编号格式" \
  "crossref-brief.yaml|brief 图表编号格式"
do
  check_file "$ASSETS/${pair%%|*}" "${pair#*|}"
done

PY_SCRIPTS=(
  "md-lint.py|导出前 Markdown 体检"
  "build-reference-docx.py|生成 Word 母版"
  "docx-postprocess.py|Word 分节 / 页眉页脚 / A4 / 三线表"
)
for pair in "${PY_SCRIPTS[@]}"; do
  f="$SCRIPTS/${pair%%|*}"; d="${pair#*|}"
  if [[ ! -f "$f" ]]; then
    say "$NO" "$(basename "$f")" "缺失 —— $d"
    miss_files=$((miss_files+1)); fatal=$((fatal+1))
  elif [[ -z "$PY" ]]; then
    say "$OPT" "$(basename "$f")" "$d（无 python3，跳过语法检查）"
  elif "$PY" -c "import ast,sys; ast.parse(open(sys.argv[1],encoding='utf-8').read(), sys.argv[1])" "$f" 2>/dev/null; then
    say "$OK" "$(basename "$f")" "$d"
  else
    say "$NO" "$(basename "$f")" "语法错误 —— $d"
    fatal=$((fatal+1))
    add_hint "查看语法错误详情：
    python3 -c \"import ast,sys; ast.parse(open(sys.argv[1],encoding='utf-8').read(), sys.argv[1])\" '$f'"
  fi
done

check_file "$SCRIPTS/export.sh" "导出入口"

# lua 语法检查（借 pandoc 内置的 lua 解释器，没有 pandoc 就跳过）
if [[ -n "$PANDOC" ]]; then
  lua_bad=0
  for f in "$ASSETS"/*.lua; do
    [[ -f "$f" ]] || continue
    "$PANDOC" lua -e "assert(loadfile('$f'))" >/dev/null 2>&1 || {
      say "$NO" "$(basename "$f")" "Lua 语法错误"
      lua_bad=1; fatal=$((fatal+1))
    }
  done
  [[ $lua_bad -eq 0 ]] && say "$OK" "lua 语法" "全部 filter 通过 pandoc lua 解析"
fi

[[ $miss_files -gt 0 ]] && \
  add_hint "有 skill 自带文件缺失，说明目录被改动过。重新拉一份完整的
    ~/.claude/skills/paper-export 覆盖即可。"

# ============================================================
#  汇总
# ============================================================
echo
echo "──────────────────────────────────────────────────────"

if [[ ${#hints[@]} -gt 0 ]]; then
  echo
  echo "处理办法："
  for h in "${hints[@]}"; do
    printf '  • %s\n' "$h"
  done
fi

# ---------- 自动补装 ----------
if [[ ${#missing_brew[@]} -gt 0 ]]; then
  echo
  if ! command -v brew >/dev/null 2>&1; then
    echo "未检测到 Homebrew，无法自动补装。先装 Homebrew："
    echo "    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/brew/HEAD/install.sh)\""
  elif [[ $DO_INSTALL -eq 1 ]]; then
    echo "正在补装: ${missing_brew[*]}"
    brew install "${missing_brew[@]}" && echo "安装完成，重新运行 doctor.sh 复查。"
  else
    echo "一条命令补齐 Homebrew 组件："
    echo "    brew install ${missing_brew[*]}"
    echo "或直接执行： bash '$SCRIPTS/doctor.sh' --install"
  fi
elif [[ $DO_INSTALL -eq 1 ]]; then
  echo
  echo "没有需要补装的 Homebrew 组件。"
fi

echo
printf "汇总: 必需项缺失 %d，建议项缺失 %d，可选项未装 %d\n" "$fatal" "$warn" "$optn"

if [[ $fatal -eq 0 ]]; then
  if [[ $warn -eq 0 && $optn -eq 0 ]]; then
    echo "$OK 工具链完整，PDF 与 Word 都可以导出。"
  else
    echo "$OK 必需项齐全，可以导出；上面 $OPT 标记的按需补装即可。"
  fi
  exit 0
else
  echo "$NO 存在必需项缺失，请按上面的「处理办法」补齐后重跑。"
  exit 1
fi
