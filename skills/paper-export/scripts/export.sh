#!/usr/bin/env bash
# ============================================================
#  paper-export :: Markdown → PDF / Word 规范级排版
#  用法:  export.sh [选项] <input.md | 目录> [更多.md ...]
# ============================================================
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$SKILL_DIR/assets"
SCRIPTS="$SKILL_DIR/scripts"

# ---------- 默认值 ----------
TO="pdf"; STYLE="modern"; OUT=""; NAME=""; TITLE=""; SUBTITLE=""
AUTHOR=""; DATE=""; ORG=""; DOCNO=""; VERSION=""; SECURITY=""
TOC=1; TOC_DEPTH=3; NUMBER="auto"; BIB=""; CSL=""; KEEP_TEX=0; EMOJI="text"
BREAK_LEVEL="auto"; LINKS="black"; FOOTER_TOTAL=0
TABLE_FIT=1; TABLE_RULE="auto"; TABLE_HEAD_FILL=0; CODE_COLOR=0
TABLE_LINE_UNITS=80
LINT=1; STRICT_LINT=0
MASTHEAD_ORG=0; VERBOSE=0
# 记录用户是否显式动过这些开关 —— brief 会强制覆盖它们，覆盖前要告知
TOC_SET=0; BREAK_SET=0
INPUTS=()

usage() {
  cat <<'EOF'
用法: export.sh [选项] <input.md | 目录> [更多.md ...]

输出:
  --to pdf|docx|both      输出格式（默认 pdf）
  --style modern|modern-plain|report|gb|brief
                          排版预设（默认 modern）
                            modern = 版式同 report，正文换阿里巴巴普惠体。
                                     屏幕/投影清晰，日常技术文档默认走这套
                            modern-plain = 复用 modern 字体和 report 版式，
                                     标题直接进入正文，无封面、无目录、不主动换页
                            report = 同样版式但用宋体，交付纸质正式件时用
                            gb     = 中文学位论文，ctexbook，第一章 / 图 1-1，GB/T 7714
                            brief  = 简报/通报/会议纪要，仿政府公文（GB/T 9704 观感）
                                     文头即标题，仿宋三号正文，文末右下角落款；
                                     无封面页、无目录、无页眉、无页码、不主动分页 ——
                                     这些开关一律被忽略，一个 --style brief 就够了
  --out DIR               输出目录（默认：第一个输入所在目录）
  --name NAME             输出文件名（不含扩展名；多输入时默认取目录名）

封面与元数据:
  --title T               主标题（默认取首个 H1，再退到 --name）
  --subtitle S            副标题
  --org O                 编制单位（report/gb 显示在封面标题上方；brief 在落款）
  --author A              编制人
  --doc-no N              文档编号        （brief 忽略）
  --version V             版本号（如 V1.0）（brief 忽略）
  --security S            密级（如 内部）  （brief 忽略）
  --date D                日期（默认今天；brief 排在落款末行）
  --masthead-org          brief 专用：单位名也印在文头标题上方（默认只在落款）

结构:
  --toc / --no-toc        是否生成目录（默认生成）
  --toc-depth N           目录收录到第几级标题（默认 3）
  --number / --no-number  是否自动编号章节
                            默认 auto：gb 自动编号；report 沿用你手写的编号
  --break-level auto|0|1|2|3
                          在第几级标题前分页（默认 auto：正文 H1 ≥2 个按 H1 分，
                          否则按 H2 分 —— 单 H1 会被当作文档名摘到封面）
  --bib FILE              BibTeX 参考文献
  --csl FILE              CSL 样式（默认按 style 选，gb → GB/T 7714）

版式:
  --links black|color     超链接颜色（默认 black，打印友好）
  --footer-total          页脚显示「第 N 页 共 M 页」
  --table-rule auto|three|grid
                          表格线型。默认 auto：单元格会折行的表加行间浅灰细线，
                          全是短词的表保持纯三线表
  --table-head-fill       表头加浅灰底纹（默认不加，符合三线表规范）
  --code-color            代码块用彩色语法高亮（默认单色，与「全文黑色」一致）
  --no-table-fit          关闭表格列宽按内容重算（不建议）
  --emoji text|strip|keep 彩色 emoji 处理（默认 text，映射为 √ × ! 等）

检查与排错:
  --no-lint               跳过 Markdown 体检
  --strict-lint           体检发现 error 级问题时直接退出
  --keep-tex              保留中间 .tex，便于排查 LaTeX 报错
  --verbose               打印引擎原始输出（默认过滤 tectonic 的字体路径噪音）
  -h, --help              显示本帮助

示例:
  export.sh 需求文档.md --to both --subtitle "V1.0 评审稿" --org "XX科技" --version V1.0
  export.sh 技术稿.md --style modern-plain --to pdf
  export.sh 论文.md --style gb --to pdf
  export.sh 会议纪要.md --style brief --to both --subtitle "项目管理模块" --author 张三
  export.sh ./docs/交付文档 --name 交付文档 --title "系统交付文档" --to both
EOF
}

# ---------- 解析参数 ----------
# 取选项值。直接写 "$2" 在 set -u 下会抛 "$2: unbound variable" —— 用户漏写
# 取值时只能看到一句 shell 内部报错，根本不知道是哪个选项的问题。
val() {
  [[ -n "$2" ]] || { echo "选项 $1 缺少取值" >&2; exit 2; }
  printf '%s' "$2"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)          TO="$(val "$1" "${2:-}")"; shift 2 ;;
    --style)       STYLE="$(val "$1" "${2:-}")"; shift 2 ;;
    --out)         OUT="$(val "$1" "${2:-}")"; shift 2 ;;
    --name)        NAME="$(val "$1" "${2:-}")"; shift 2 ;;
    --title)       TITLE="$(val "$1" "${2:-}")"; shift 2 ;;
    --subtitle)    SUBTITLE="$(val "$1" "${2:-}")"; shift 2 ;;
    --org)         ORG="$(val "$1" "${2:-}")"; shift 2 ;;
    --author)      AUTHOR="$(val "$1" "${2:-}")"; shift 2 ;;
    --doc-no)      DOCNO="$(val "$1" "${2:-}")"; shift 2 ;;
    --version)     VERSION="$(val "$1" "${2:-}")"; shift 2 ;;
    --security)    SECURITY="$(val "$1" "${2:-}")"; shift 2 ;;
    --date)        DATE="$(val "$1" "${2:-}")"; shift 2 ;;
    --masthead-org) MASTHEAD_ORG=1; shift ;;
    --toc)         TOC=1; TOC_SET=1; shift ;;
    --no-toc)      TOC=0; TOC_SET=1; shift ;;
    --toc-depth)   TOC_DEPTH="$(val "$1" "${2:-}")"; TOC_SET=1; shift 2 ;;
    --number)      NUMBER="yes"; shift ;;
    --no-number)   NUMBER="no"; shift ;;
    --break-level) BREAK_LEVEL="$(val "$1" "${2:-}")"; BREAK_SET=1; shift 2 ;;
    --break-h1)    BREAK_LEVEL="1"; BREAK_SET=1; shift ;;   # 兼容旧参数
    --no-break-h1) BREAK_LEVEL="0"; BREAK_SET=1; shift ;;
    --bib)         BIB="$(val "$1" "${2:-}")"; shift 2 ;;
    --csl)         CSL="$(val "$1" "${2:-}")"; shift 2 ;;
    --links)       LINKS="$(val "$1" "${2:-}")"; shift 2 ;;
    --footer-total) FOOTER_TOTAL=1; shift ;;
    --table-rule)  TABLE_RULE="$(val "$1" "${2:-}")"; shift 2 ;;
    --table-head-fill) TABLE_HEAD_FILL=1; shift ;;
    --code-color)  CODE_COLOR=1; shift ;;
    --no-table-fit) TABLE_FIT=0; shift ;;
    --emoji)       EMOJI="$(val "$1" "${2:-}")"; shift 2 ;;
    --no-lint)     LINT=0; shift ;;
    --strict-lint) STRICT_LINT=1; shift ;;
    --keep-tex)    KEEP_TEX=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    -*)            echo "未知选项: $1" >&2; usage; exit 2 ;;
    *)             INPUTS+=("$1"); shift ;;
  esac
done

[[ ${#INPUTS[@]} -eq 0 ]] && { usage; exit 2; }
[[ "$STYLE" =~ ^(modern|modern-plain|gb|report|brief)$ ]] \
  || { echo "--style 只能是 modern / modern-plain / report / gb / brief" >&2; exit 2; }

# modern / modern-plain 是 report 的字体变体，版式文件和图表编号复用 report。
BASE_STYLE="$STYLE"
[[ "$STYLE" == "modern" || "$STYLE" == "modern-plain" ]] && BASE_STYLE="report"
[[ "$TO" =~ ^(pdf|docx|both)$ ]] || { echo "--to 只能是 pdf / docx / both" >&2; exit 2; }
[[ "$BREAK_LEVEL" =~ ^(auto|0|1|2|3)$ ]] || { echo "--break-level 只能是 auto/0/1/2/3" >&2; exit 2; }
# 剩下这几个原先不校验：拼错 --links blcak 会一路传到 LaTeX，最后表现为
# 一句看不懂的 hyperref 报错，或者干脆静默按默认值出图。
[[ "$LINKS" =~ ^(black|color)$ ]] || { echo "--links 只能是 black / color" >&2; exit 2; }
[[ "$EMOJI" =~ ^(text|strip|keep)$ ]] || { echo "--emoji 只能是 text / strip / keep" >&2; exit 2; }
[[ "$TABLE_RULE" =~ ^(auto|three|grid)$ ]] || { echo "--table-rule 只能是 auto / three / grid" >&2; exit 2; }
[[ "$TOC_DEPTH" =~ ^[1-6]$ ]] || { echo "--toc-depth 只能是 1..6" >&2; exit 2; }
for _f in "$BIB" "$CSL"; do
  [[ -z "$_f" || -f "$_f" ]] || { echo "文件不存在: $_f" >&2; exit 1; }
done

# ---------- 展开目录输入 ----------
# 字节序会把 1- / 10- / 2- 排成 1、10、2，成册顺序直接错乱且不报错。
# sort -V 按版本号（即自然数序）排；BSD sort 不支持时退回字节序。
NATSORT=0
printf '1\n' | sort -V >/dev/null 2>&1 && NATSORT=1
md_sort() { if [[ $NATSORT -eq 1 ]]; then sort -V; else LC_ALL=C sort; fi; }

FILES=()
for it in "${INPUTS[@]}"; do
  if [[ -d "$it" ]]; then
    while IFS= read -r f; do FILES+=("$f"); done < <(find "$it" -maxdepth 1 -name '*.md' | md_sort)
    [[ -z "$NAME" ]] && NAME="$(basename "${it%/}")"
  elif [[ -f "$it" ]]; then
    FILES+=("$it")
  else
    echo "找不到输入: $it" >&2; exit 1
  fi
done
[[ ${#FILES[@]} -eq 0 ]] && { echo "没有匹配到任何 .md 文件" >&2; exit 1; }

FIRST="${FILES[0]}"
# 图片查找路径：原先只放第一个文件所在目录，多目录输入时后面文件里的
# ![](img/x.png) 一律找不到，pandoc 只警告不报错，导出后图直接缺。
RESPATH=""
for f in "${FILES[@]}"; do
  d="$(cd "$(dirname "$f")" && pwd)"
  case ":$RESPATH:" in *":$d:"*) ;; *) RESPATH="${RESPATH:+$RESPATH:}$d" ;; esac
done
RESPATH="$RESPATH:$(pwd)"

[[ -z "$OUT"  ]] && OUT="$(cd "$(dirname "$FIRST")" && pwd)"
[[ -z "$NAME" ]] && NAME="$(basename "$FIRST" .md)"
mkdir -p "$OUT"

# ---------- 工具链探测 ----------
# pandoc-crossref 是按特定 pandoc 版本编译的，优先用 Homebrew 那一套，
# 避免 anaconda 等环境里的旧 pandoc 与 filter 的 AST 版本对不上。
PANDOC=""
for c in /opt/homebrew/bin/pandoc /usr/local/bin/pandoc "$(command -v pandoc || true)"; do
  [[ -n "$c" && -x "$c" ]] && { PANDOC="$c"; break; }
done
[[ -z "$PANDOC" ]] && { echo "未找到 pandoc，请先运行 scripts/doctor.sh" >&2; exit 1; }

ENGINE=""
for e in xelatex lualatex tectonic; do
  command -v "$e" >/dev/null 2>&1 && { ENGINE="$e"; break; }
done

CROSSREF=""
command -v pandoc-crossref >/dev/null 2>&1 && CROSSREF="$(command -v pandoc-crossref)"

PY="$(command -v python3 || true)"

# 临时目录。frontmatter 解析、封面变量、pandoc 日志都往这里写，
# 所以必须在第一个用到它的地方（frontmatter）之前建好。
TMPDIR_PE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_PE"' EXIT

# pandoc 3.9 起 --highlight-style 改名 --syntax-highlighting
HLOPT="--highlight-style"
"$PANDOC" --help 2>/dev/null | grep -q -- '--syntax-highlighting' && HLOPT="--syntax-highlighting"

# 代码高亮：默认单色。彩色高亮会在「全文黑色」的文档里凭空冒出五六种颜色，
# 打印出来还会糊成灰块；Word 侧同样压成黑色，两边保持一致。
HLSTYLE="monochrome"
[[ $CODE_COLOR -eq 1 ]] && HLSTYLE="tango"

# ---------- Markdown 体检 ----------
if [[ $LINT -eq 1 && -n "$PY" && -f "$SCRIPTS/md-lint.py" ]]; then
  set +e
  "$PY" "$SCRIPTS/md-lint.py" "${FILES[@]}" $([[ $STRICT_LINT -eq 1 ]] && echo --strict)
  LINT_RC=$?
  set -e
  if [[ $STRICT_LINT -eq 1 && $LINT_RC -ne 0 ]]; then
    echo "✗ 体检发现 error 级问题，已按 --strict-lint 中止。" >&2
    exit 1
  fi
fi

# ---------- 元数据推断 ----------
# 优先级：命令行参数 > 首个文件的 YAML frontmatter > 自动推断（首个 H1 / 今天）
#
# 必须自己读一遍 frontmatter：下面组装 COMMON 时会用 -M title=... 把标题传给
# pandoc，而 -M 的优先级高于文档内的 YAML —— 不先读出来，用户写在 frontmatter
# 里的 title 永远不会生效，还会被「首个 H1」顶掉。
FM_TITLE=""; FM_SUBTITLE=""; FM_AUTHOR=""; FM_ORG=""
FM_DOC_NO=""; FM_VERSION=""; FM_SECURITY=""; FM_DATE=""

# 一次把整段 frontmatter 读出来。原先每个字段起一个 python 进程读同一个文件，
# 8 个字段就是 8 次解释器冷启动（约 0.3~0.5s），纯浪费。
#
# python 输出的是一段 shell 赋值，用 source 读进来（值经 shlex.quote 转义）。
# 不写成 FM=$(python <<EOF ...)：macOS 自带的 bash 3.2 解析不了命令替换里
# 嵌的 heredoc，整个脚本会在语法阶段就报 unexpected EOF。
if [[ -n "$PY" ]]; then
  "$PY" - "$FIRST" > "$TMPDIR_PE/fm.sh" 2>/dev/null <<'PYEOF' || true
import re, shlex, sys
KEYS = ('title', 'subtitle', 'author', 'org',
        'doc-no', 'version', 'security', 'date')
try:
    text = open(sys.argv[1], encoding='utf-8', errors='replace').read()
except OSError:
    text = ''
vals = {}
m = re.match(r'^---\r?\n(.*?)\r?\n(?:---|\.\.\.)\r?\n', text, re.S)
if m:
    for line in m.group(1).split('\n'):
        km = re.match(r'^([A-Za-z_][\w-]*)\s*:\s*(.*)$', line)
        if not km:
            continue
        k, v = km.group(1), km.group(2).strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
            v = v[1:-1]
        vals[k] = v
print('\n'.join('FM_%s=%s' % (k.upper().replace('-', '_'), shlex.quote(vals.get(k, '')))
                 for k in KEYS))
PYEOF
  [[ -s "$TMPDIR_PE/fm.sh" ]] && . "$TMPDIR_PE/fm.sh"
fi

[[ -z "$TITLE"    ]] && TITLE="$FM_TITLE"
[[ -z "$SUBTITLE" ]] && SUBTITLE="$FM_SUBTITLE"
[[ -z "$AUTHOR"   ]] && AUTHOR="$FM_AUTHOR"
[[ -z "$ORG"      ]] && ORG="$FM_ORG"
[[ -z "$DOCNO"    ]] && DOCNO="$FM_DOC_NO"
[[ -z "$VERSION"  ]] && VERSION="$FM_VERSION"
[[ -z "$SECURITY" ]] && SECURITY="$FM_SECURITY"
[[ -z "$DATE"     ]] && DATE="$FM_DATE"

if [[ -z "$TITLE" ]]; then
  TITLE="$(grep -m1 '^# ' "$FIRST" 2>/dev/null | sed 's/^# *//' || true)"
  [[ -z "$TITLE" ]] && TITLE="$NAME"
fi
[[ -z "$DATE" ]] && DATE="$(date +%Y-%m-%d)"

# ---------- brief 预设：一个参数顶掉一串开关 ----------
# 简报/通报是「一口气读完」的文体：没有封面页、没有目录、没有页眉页码，
# 也不在标题前主动分页。这些恰恰是 report 预设的默认行为，所以在这里
# 统一压掉 —— 用户不必再写 --no-toc --break-level 0 --no-number 一长串。
# 已经传进来的封面字段（编号/版本/密级）也一并清掉，并明确告知，
# 免得用户以为写了却没生效。
SIGNDATE="$DATE"
if [[ "$STYLE" == "brief" ]]; then
  IGNORED=()
  [[ -n "$DOCNO"    ]] && IGNORED+=("--doc-no")
  [[ -n "$VERSION"  ]] && IGNORED+=("--version")
  [[ -n "$SECURITY" ]] && IGNORED+=("--security")
  [[ $FOOTER_TOTAL -eq 1 ]] && IGNORED+=("--footer-total")
  [[ $TOC_SET -eq 1   ]] && IGNORED+=("--toc/--toc-depth")
  [[ $BREAK_SET -eq 1 ]] && IGNORED+=("--break-level")
  if [[ ${#IGNORED[@]} -gt 0 ]]; then
    echo "  ! brief 预设不排版这些内容，已忽略: ${IGNORED[*]}" >&2
  fi
  DOCNO=""; VERSION=""; SECURITY=""
  TOC=0; BREAK_LEVEL=0; NUMBER="no"; FOOTER_TOTAL=0

  # 落款日期中文化：2026-08-05 → 2026 年 8 月 5 日。
  # 公文落款不写 ISO 日期；不是这个格式（比如用户自己写了「二〇二六年八月」）
  # 就原样保留。
  if [[ "$DATE" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})$ ]]; then
    SIGNDATE="${BASH_REMATCH[1]} 年 $((10#${BASH_REMATCH[2]})) 月 $((10#${BASH_REMATCH[3]})) 日"
  fi
fi

# modern-plain 去掉封面、目录和主动分页，其余沿用 modern/report。
# 目录和分页参数在该预设下没有意义，统一忽略。
if [[ "$STYLE" == "modern-plain" ]]; then
  [[ $TOC_SET -eq 1 ]] && echo "  ! modern-plain 预设不生成目录，已忽略 --toc/--toc-depth" >&2
  [[ $BREAK_SET -eq 1 ]] && echo "  ! modern-plain 预设不主动换页，已忽略 --break-level" >&2
  TOC=0
  BREAK_LEVEL=0
fi

# ---------- 编号策略 ----------
# report 预设默认不自动编号：技术文档通常已手写「## 1. 概述」，
# 再叠加 LaTeX 编号会变成「1 1. 概述」。
if [[ "$NUMBER" == "auto" ]]; then
  [[ "$STYLE" == "gb" ]] && NUMBER="yes" || NUMBER="no"
fi

# ---------- 分页级别推断 ----------
# 只有一个 H1 时，它会被 title-dedup 当作文档名摘到封面，正文里实际的
# 一级标题是 H2 —— 此时按 H2 分页才符合「一级标题之间换页」的预期。
count_h1() {
  "$PY" - "$@" <<'PYEOF' 2>/dev/null || echo 0
import re, sys
n = 0
for path in sys.argv[1:]:
    fence = None
    for line in open(path, encoding='utf-8', errors='replace'):
        s = line.rstrip('\n')
        m = re.match(r'^\s*(`{3,}|~{3,})', s)
        if m:
            tok = m.group(1)[0]
            if fence is None: fence = tok
            elif fence == tok: fence = None
            continue
        if fence: continue
        if re.match(r'^#\s+\S', s): n += 1
print(n)
PYEOF
}

if [[ "$BREAK_LEVEL" == "auto" ]]; then
  if [[ "$STYLE" == "gb" ]]; then
    BREAK_LEVEL=0          # ctexbook 的 \chapter 自带分页
  elif [[ -n "$PY" ]]; then
    H1N="$(count_h1 "${FILES[@]}" | tail -1)"
    [[ "${H1N:-0}" -ge 2 ]] && BREAK_LEVEL=1 || BREAK_LEVEL=2
  else
    BREAK_LEVEL=1
  fi
fi

# 页眉右侧取哪一级标题：与分页级别保持一致（gb 恒为章）
HEAD_LEVEL=1
[[ "$BASE_STYLE" == "report" && "$BREAK_LEVEL" == "2" ]] && HEAD_LEVEL=2

# ---------- 封面变量（LaTeX 侧）----------
COVERVARS="$TMPDIR_PE/cover-vars.tex"

if [[ -n "$PY" ]]; then
  ORG="$ORG" SUBTITLE="$SUBTITLE" DOCNO="$DOCNO" VERSION="$VERSION" \
  SECURITY="$SECURITY" AUTHOR="$AUTHOR" SIGNDATE="$SIGNDATE" \
  PE_TOC="$TOC" PE_HEAD="$HEAD_LEVEL" PE_FT="$FOOTER_TOTAL" \
  PE_MHORG="$MASTHEAD_ORG" \
  "$PY" - "$COVERVARS" <<'PYEOF'
import os, sys
# LaTeX 特殊字符转义：封面字段来自命令行，可能含 & % _ # 等
ESC = {'\\': r'\textbackslash{}', '{': r'\{', '}': r'\}', '$': r'\$',
       '&': r'\&', '#': r'\#', '%': r'\%', '_': r'\_',
       '~': r'\textasciitilde{}', '^': r'\^{}'}
def esc(s):
    return ''.join(ESC.get(c, c) for c in s)
out = []
for macro, env in (('peorg', 'ORG'), ('pesubtitle', 'SUBTITLE'),
                   ('pedocno', 'DOCNO'), ('peversion', 'VERSION'),
                   ('pesecurity', 'SECURITY'), ('peauthorline', 'AUTHOR'),
                   ('pesignoffdate', 'SIGNDATE')):
    out.append(r'\def\%s{%s}' % (macro, esc(os.environ.get(env, ''))))
out.append(r'\def\pehastoc{%s}' % (os.environ.get('PE_TOC', '1') or '0'))
out.append(r'\def\peheadlevel{%s}' % os.environ.get('PE_HEAD', '1'))
out.append(r'\def\pefootertotal{%s}' % os.environ.get('PE_FT', '0'))
out.append(r'\def\pemastheadorg{%s}' % os.environ.get('PE_MHORG', '0'))
open(sys.argv[1], 'w', encoding='utf-8').write('\n'.join(out) + '\n')
PYEOF
else
  printf '\\def\\pehastoc{%s}\n\\def\\peheadlevel{%s}\n\\def\\pefootertotal{%s}\n\\def\\pemastheadorg{%s}\n' \
    "$TOC" "$HEAD_LEVEL" "$FOOTER_TOTAL" "$MASTHEAD_ORG" > "$COVERVARS"
fi

# ---------- pandoc 调用包装 ----------
# tectonic 会为每个用到的字体文件打印一行「accessing absolute path ... build may
# not be reproducible」。实测一次 modern 导出刷 49 行，占全部输出的四分之三，
# 把 md-lint 的体检结果和真正的报错全冲出屏幕。
#
# 只过滤下面这几条「每次必现且无害」的：字体绝对路径、TeX 引擎汇总提示、
# lineno.sty 自带的非 UTF-8 字节、hyperref 的 @page 重复定义。
# 其余一律放行；一旦 pandoc 退出码非 0，原样吐出完整日志，排错不丢信息。
# 想看全部：--verbose。
run_pandoc() {
  local log="$TMPDIR_PE/pandoc.err" rc=0
  "$PANDOC" "$@" 2>"$log" || rc=$?
  if [[ $rc -ne 0 || $VERBOSE -eq 1 ]]; then
    [[ -s "$log" ]] && cat "$log" >&2
  elif [[ -s "$log" ]]; then
    grep -v \
      -e 'accessing absolute path' \
      -e 'build may not be reproducible' \
      -e 'warnings were issued by the TeX engine' \
      -e 'lineno\.sty:.*Invalid UTF-8' \
      -e 'Object @page\.[0-9]* already defined' \
      "$log" >&2 || true
  fi
  return $rc
}

# ---------- 组装公共参数 ----------
# -blank_before_header：标题前忘了空行时也当标题处理。
#   这是中文长文档最常见的静默事故：「## 四、待确认事项」被吞进上一段，
#   目录直接少一章，导出后几乎看不出来。
# +lists_without_preceding_blankline：同理，列表紧跟段落也照常识别。
FROMSPEC='markdown-blank_before_header+lists_without_preceding_blankline'
FROMSPEC+='+east_asian_line_breaks+pipe_tables+tex_math_dollars+raw_tex'

COMMON=( "${FILES[@]}"
  --from="$FROMSPEC"
  --lua-filter="$ASSETS/sanitize.lua"
  --lua-filter="$ASSETS/title-dedup.lua"
  --lua-filter="$ASSETS/pagebreak.lua"
  --lua-filter="$ASSETS/semantic-markers.lua"
  -M "emoji=$EMOJI"
  -M "break-level=$BREAK_LEVEL"
  -M "title=$TITLE"
  -M "date=$DATE"
  -M "toc-title=目　录"
  -M "table-rule=$TABLE_RULE"
  -M "table-line-units=$TABLE_LINE_UNITS"
  -M "table-head-fill=$TABLE_HEAD_FILL"
  -M "code-color=$CODE_COLOR"
  --resource-path="$RESPATH"
)
[[ $TABLE_FIT -eq 1 && -f "$ASSETS/tablefit.lua" ]] \
  && COMMON+=( --lua-filter="$ASSETS/tablefit.lua" ) \
  || COMMON+=( -M "table-fit=false" )
[[ -n "$AUTHOR"   ]] && COMMON+=( -M "author=$AUTHOR" )
# subtitle 刻意不进 COMMON：pandoc 的 LaTeX 模板会把它拼进 \title{...\\ {\large ...}}，
# 与我们自己画的封面副标题撞成两遍，还会把页眉的 \@title 撑成两行。
# PDF 侧改从 cover-vars.tex 的 \pesubtitle 取，docx 侧在 build_docx 里单独传。
[[ -n "$ORG"      ]] && COMMON+=( -M "org=$ORG" )
[[ -n "$DOCNO"    ]] && COMMON+=( -M "doc-no=$DOCNO" )
[[ -n "$VERSION"  ]] && COMMON+=( -M "version=$VERSION" )
[[ -n "$SECURITY" ]] && COMMON+=( -M "security=$SECURITY" )
[[ $TOC -eq 1 ]]     && COMMON+=( --toc --toc-depth="$TOC_DEPTH" )
[[ "$NUMBER" == "yes" ]] && COMMON+=( --number-sections )

if [[ -n "$CROSSREF" ]]; then
  COMMON+=( --filter "$CROSSREF" -M "crossrefYaml=$ASSETS/crossref-$BASE_STYLE.yaml" )
fi

# 参考文献：citeproc 同时服务 PDF 与 Word，两侧样式完全一致
if [[ -n "$BIB" ]]; then
  # GB/T 7714 的 CSL 不随 skill 分发（体积 + 上游会更新），装不装决定了
  # gb 预设的参考文献到底是不是国标样式 —— 缺了必须说，不能静默降级。
  if [[ -z "$CSL" && "$STYLE" == "gb" ]]; then
    if [[ -f "$ASSETS/gb-t-7714-2015-numeric.csl" ]]; then
      CSL="$ASSETS/gb-t-7714-2015-numeric.csl"
    else
      echo "  ! 未找到 GB/T 7714 的 CSL，参考文献将退回 pandoc 默认样式" >&2
      echo "    补装: scripts/doctor.sh --install" >&2
    fi
  fi
  COMMON+=( --citeproc --bibliography="$BIB" )
  [[ -n "$CSL" ]] && COMMON+=( --csl="$CSL" )
fi

# ---------- PDF ----------
build_pdf() {
  [[ -z "$ENGINE" ]] && {
    echo "✗ 未找到 LaTeX 引擎（xelatex / tectonic），请运行 scripts/doctor.sh" >&2
    return 1
  }
  # 注入顺序有依赖：cover-vars 用 \def 落定字段值 → preamble-common 定义颜色与
  # \pecircled → preamble-<style> 定义版式 → titlepage 用前三者组装封面。
  #
  # brief 走另一套「文头 + 落款」：没有封面页，也就没有 before-body 要做的
  # 「封面节 → 前置节」切换（它会 \clearpage，在 brief 里凭空多出一张空白页）。
  local args=( "${COMMON[@]}"
    --pdf-engine="$ENGINE"
    -H "$COVERVARS"
    -H "$ASSETS/preamble-common.tex"
    -H "$ASSETS/preamble-$BASE_STYLE.tex"
    -V mainfont="Songti SC"
    "$HLOPT"="$HLSTYLE"
    # 显式清空 subtitle。不传 -M subtitle 只能挡住命令行那份 —— 写在文档 YAML
    # 里的 subtitle pandoc 自己照样读得到，模板会把它拼进 \title{...\\{\large ...}}，
    # 于是封面副标题画两遍、页眉的 \@title 被撑成两行。
    # PDF 侧的副标题一律走 cover-vars.tex 的 \pesubtitle。
    -M "subtitle="
  )
  # modern：在 report 版式之上叠一层字体覆盖。必须排在 preamble-report 之后 ——
  # 它 \renewcommand 的 \songti / \heiti 要盖住前者，反过来就没效果了。
  [[ "$STYLE" == "modern" || "$STYLE" == "modern-plain" ]] \
    && args+=( -H "$ASSETS/preamble-modern.tex" )
  if [[ "$STYLE" == "brief" ]]; then
    # front-break 默认为真：pagebreak.lua 会在正文最前面插一个 \clearpage，
    # 好让目录页独占一页。brief 没有目录也没有封面页，这个分页就变成了
    # 「文头单独占满第一页、正文从第二页开始」—— 必须显式关掉。
    args+=( -H "$ASSETS/masthead-brief.tex" -A "$ASSETS/signoff-brief.tex"
            -M "front-break=false" )
  elif [[ "$STYLE" == "modern-plain" ]]; then
    args+=( -H "$ASSETS/preamble-modern-plain.tex" -M "front-break=false" )
  else
    args+=( -H "$ASSETS/titlepage.tex" -B "$ASSETS/before-body.tex" )
  fi
  # 全文黑色是硬性要求：链接默认也用黑色（不传 colorlinks 会让 hyperref 画彩框）
  local lc="black"
  [[ "$LINKS" == "color" ]] && lc="NavyBlue"
  args+=( -V colorlinks=true -V linkcolor="$lc" -V urlcolor="$lc"
          -V citecolor="$lc" -V toccolor=black )

  if [[ "$STYLE" == "gb" ]]; then
    args+=( -V documentclass=ctexbook -V classoption=UTF8,oneside,zihao=-4
            --top-level-division=chapter )
  elif [[ "$STYLE" == "brief" ]]; then
    # 公文正文是三号（16pt），但 ctex 的 zihao 类选项**只认 5 / -4 / false**
    # 三个值（ctexart.cls 里是 .choice: 定义的），传 3 或 4 都会在
    # \ProcessKeysOptions 阶段报「accepts only a fixed set of choices」，
    # 一页都出不来。这里仍传 -4 打底，真正的三号由 preamble-brief.tex
    # 重定义 \normalsize 落实。
    args+=( -V documentclass=ctexart -V classoption=UTF8,zihao=-4 )
  else
    args+=( -V documentclass=ctexart -V classoption=UTF8,zihao=-4 )
  fi

  if [[ $KEEP_TEX -eq 1 ]]; then
    run_pandoc "${args[@]}" -o "$OUT/$NAME.tex"
    echo "  中间文件: $OUT/$NAME.tex"
  fi
  run_pandoc "${args[@]}" -o "$OUT/$NAME.pdf"
  echo "✓ PDF  → $OUT/$NAME.pdf  ($(du -h "$OUT/$NAME.pdf" | cut -f1))"
}

# ---------- Word ----------
build_docx() {
  local args=( "${COMMON[@]}" )
  [[ -n "$SUBTITLE" ]] && args+=( -M "subtitle=$SUBTITLE" )
  # brief 的 Word 侧由 cover-docx.lua 走另一条分支：文头 + 落款，不画封面页
  args+=( -M "pe-style=$STYLE" -M "signoff-date=$SIGNDATE"
          -M "masthead-org=$MASTHEAD_ORG" )
  # Word 侧「目录后另起一页」由 docx-postprocess.py 插的分节符负责，
  # 分节符本身就换页。再让 pagebreak.lua 加一个分页符，两者叠加会在正文
  # 第一页前多出一整张空白页。
  args+=( -M "front-break=false" )
  local docx_style="$STYLE"
  [[ "$STYLE" == "modern-plain" ]] && docx_style="modern"
  local ref="$ASSETS/reference-$docx_style.docx"
  if [[ -f "$ref" ]]; then
    args+=( --reference-doc="$ref" )
  else
    echo "  ! 未找到 $ref，使用 pandoc 默认 Word 样式" >&2
  fi
  # 封面在 docx 侧由 lua filter 直接写 OpenXML —— 必须排在 title-dedup 之后，
  # 否则拿不到已确定的 meta.title。
  [[ -f "$ASSETS/cover-docx.lua" ]] && args+=( --lua-filter="$ASSETS/cover-docx.lua" )

  run_pandoc "${args[@]}" -o "$OUT/$NAME.docx"

  # 分节符、页眉页脚、A4、页码格式、目录标题：pandoc 写不了，落到后处理
  if [[ -n "$PY" && -f "$SCRIPTS/docx-postprocess.py" ]]; then
    "$PY" "$SCRIPTS/docx-postprocess.py" "$OUT/$NAME.docx" \
      --style "$docx_style" --title "$TITLE" --toc "$TOC" \
      --table-rule "$TABLE_RULE" --footer-total "$FOOTER_TOTAL" \
      --head-level "$HEAD_LEVEL"
  fi
  echo "✓ Word → $OUT/$NAME.docx  ($(du -h "$OUT/$NAME.docx" | cut -f1))"
}

# ---------- 执行 ----------
echo "── paper-export ─────────────────────────"
echo "  输入   : ${#FILES[@]} 个文件"
# 多文件合并时把实际顺序打出来。顺序错了（比如文件名没补零）在成品里
# 才发现，代价远高于这几行输出。
if [[ ${#FILES[@]} -gt 1 ]]; then
  i=1
  for f in "${FILES[@]}"; do
    echo "           $i. $(basename "$f")"
    i=$((i + 1))
  done
fi
echo "  标题   : $TITLE${SUBTITLE:+  /  $SUBTITLE}"
if [[ "$STYLE" == "brief" ]]; then
  echo "  预设   : brief（简报/通报）  无目录 无页眉页脚 无页码 不分页"
  echo "  落款   : ${ORG:-—}${AUTHOR:+  /  $AUTHOR}  /  $SIGNDATE"
elif [[ "$STYLE" == "modern-plain" ]]; then
  echo "  预设   : modern-plain（现代技术稿）  无封面 无目录 不主动换页"
else
  echo "  预设   : $STYLE   编号: $NUMBER   目录: $TOC(depth $TOC_DEPTH)"
  echo "  分页   : 第 $BREAK_LEVEL 级标题前   页眉取第 $HEAD_LEVEL 级"
fi
echo "  引擎   : ${ENGINE:-<无>}   pandoc: $("$PANDOC" --version | head -1 | awk '{print $2}')"
# 原先写成 ${CROSSREF:+已启用}${CROSSREF:-未安装...}：CROSSREF 非空时
# 后一个展开吐的是它自己的值，于是打印成「已启用/opt/homebrew/bin/...」。
if [[ -n "$CROSSREF" ]]; then
  echo "  crossref: 已启用"
else
  echo "  crossref: 未安装（@fig: / @tbl: 引用不可用）"
fi
echo "─────────────────────────────────────────"

case "$TO" in
  pdf)  build_pdf ;;
  docx) build_docx ;;
  both) build_pdf; build_docx ;;
esac
