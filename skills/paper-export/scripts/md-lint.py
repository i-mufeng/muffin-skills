#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
paper-export :: md-lint.py —— 导出前的 Markdown 体检（SPEC §9，修 D9 的可见性）

用法:
    python3 md-lint.py file1.md [file2.md ...] [--strict] [--quiet]

定级依据：**error 只给「在本 skill 的 FROMSPEC 下真的会丢内容」的问题。**

export.sh 用的是 `markdown-blank_before_header`，即缺空行也能识别标题。
所有定级都按这个配置实测过（pandoc 3.10.1）：

    写法                          实测后果              定级
    段落后紧跟标题（行首）        标题正常识别          warn
    标题缩进 1~3 空格             **标题被吞**          error
    表格前缺空行                  **整张表退化成文字**  error
    列表后紧跟表格                **整张表退化成文字**  error
    分隔行列数少于表头            **整列内容丢失**      error
    单元格显示宽度 > 80           必然被挤成多行        error

pandoc 的 markdown 方言要求 ATX 标题**从行首开始** —— 这一点和 CommonMark
不同，缩进 1~3 空格的标题即使前面有空行也不被识别，是最隐蔽的一类事故。

检查项:
    error  标题缩进 1~3 空格        —— 不被识别为标题，目录少一章
    error  表格前缺空行             —— 整张表被上一段吸收成文字
    error  列表后紧跟表格           —— 同上
    error  分隔行列数少于表头       —— pandoc 静默丢弃多出来的整列
    error  表格单元格显示宽度 > 80  —— ≈40 汉字，必然被挤成多行
    error  代码围栏未闭合
    error  文件不是 UTF-8 编码
    warn   标题行前缺空行（行首）   —— 本配置下能识别，但应补上
    warn   表格单元格显示宽度 > 40
    warn   表格列数 > 6
    warn   表格 / 代码围栏 / 列表 前后缺空行
    warn   标题层级跳级（## 直接到 ####）
    warn   同级标题手写编号不连续（三、之后直接 五、）
    warn   图片引用的文件不存在
    warn   行尾两个以上空格（Markdown 硬换行，中文文档里通常是笔误）
    info   表格行数 > 15
    info   单段落显示宽度 > 800

--strict 且存在 error 时退出码 1，否则 0。
"""

import argparse
import os
import re
import sys

# ---------------------------------------------------------------------------
# 显示宽度：与 assets/tablefit.lua 的 char_width 保持一致
# ---------------------------------------------------------------------------
_WIDE_RANGES = (
    (0x1100, 0x115F), (0x2E80, 0x303E), (0x3041, 0x33FF),
    (0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xA000, 0xA4CF),
    (0xAC00, 0xD7A3), (0xF900, 0xFAFF), (0xFE10, 0xFE19),
    (0xFE30, 0xFE6F), (0xFF00, 0xFF60), (0xFFE0, 0xFFE6),
    (0x1F300, 0x1F64F), (0x1F680, 0x1F6FF), (0x1F900, 0x1F9FF),
    (0x20000, 0x3FFFD),
)
_ZERO_RANGES = (
    (0x0300, 0x036F), (0x200B, 0x200F), (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF),
)


def char_width(ch):
    cp = ord(ch)
    if cp < 0x20 or cp == 0x7F:
        return 0
    if cp < 0x1100:
        return 1
    for lo, hi in _ZERO_RANGES:
        if lo <= cp <= hi:
            return 0
    for lo, hi in _WIDE_RANGES:
        if lo <= cp <= hi:
            return 2
    return 1


def disp_width(s):
    return sum(char_width(c) for c in s)


def clip(s, n=30):
    """按显示宽度截断，用于报错时回显内容片段。"""
    out, w = [], 0
    for c in s:
        cw = char_width(c)
        if w + cw > n * 2:
            out.append('…')
            break
        out.append(c)
        w += cw
    return ''.join(out)


# ---------------------------------------------------------------------------
# 诊断收集
# ---------------------------------------------------------------------------
LEVELS = ('error', 'warn', 'info')
_COLOR = {'error': '\033[31m', 'warn': '\033[33m', 'info': '\033[36m'}
_LABEL = {'error': '错误', 'warn': '警告', 'info': '提示'}
_RESET = '\033[0m'
_DIM = '\033[2m'
_BOLD = '\033[1m'


class Report(object):
    def __init__(self, path):
        self.path = path
        self.items = []          # (line, level, msg, hint)

    def add(self, line, level, msg, hint):
        self.items.append((line, level, msg, hint))

    def counts(self):
        c = dict((lv, 0) for lv in LEVELS)
        for _, lv, _, _ in self.items:
            c[lv] += 1
        return c


# ---------------------------------------------------------------------------
# 中文数字 / 编号解析
# ---------------------------------------------------------------------------
_CN_DIGIT = {'零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
             '五': 5, '六': 6, '七': 7, '八': 8, '九': 9}


def cn2int(s):
    """把「三」「十一」「二十三」「一百零五」转成整数，失败返回 None。"""
    if not s:
        return None
    if all(c in _CN_DIGIT for c in s) and len(s) == 1:
        return _CN_DIGIT[s]
    total, section, number = 0, 0, None
    for c in s:
        if c in _CN_DIGIT:
            number = _CN_DIGIT[c]
        elif c == '十':
            section += (number if number is not None else 1) * 10
            number = None
        elif c == '百':
            section += (number if number is not None else 1) * 100
            number = None
        elif c == '千':
            section += (number if number is not None else 1) * 1000
            number = None
        elif c == '万':
            total += (section + (number or 0)) * 10000
            section, number = 0, None
        else:
            return None
    return total + section + (number or 0)


_NUM_PATTERNS = (
    # 第一章 / 第 3 节
    re.compile(r'^第\s*([0-9]+|[零〇一二两三四五六七八九十百千万]+)\s*[章节篇部]'),
    # 三、 / 3、 / 3.
    re.compile(r'^([零〇一二两三四五六七八九十百千万]+)\s*[、.．]'),
    # 1.1 / 3.2.1 —— 分层编号自带层级信息，不要求分隔符
    re.compile(r'^([0-9]+(?:\.[0-9]+)+)\s'),
    # 3、 / 3. —— 单层编号**必须**有分隔符。原先分隔符是可选的（[、.．]?），
    # 于是「## 2024 年经营回顾」「## 3 台服务器的部署清单」里的数字都被当成
    # 章节编号，稳定刷出「编号不连续」的假警告。
    re.compile(r'^([0-9]+)\s*[、.．]\s'),
    re.compile(r'^([0-9]+(?:\.[0-9]+)*)\s*[、．]'),
)


def heading_number(text):
    """从标题文本里抽出手写编号，返回 (原串, 末位整数) 或 (None, None)。"""
    text = text.strip()
    for pat in _NUM_PATTERNS:
        m = pat.match(text)
        if not m:
            continue
        raw = m.group(1)
        if raw[0].isdigit():
            last = raw.split('.')[-1]
            try:
                return raw, int(last)
            except ValueError:
                return None, None
        val = cn2int(raw)
        if val is None or val == 0:
            return None, None
        return raw, val
    return None, None


# ---------------------------------------------------------------------------
# 主检查
# ---------------------------------------------------------------------------
_ATX = re.compile(r'^(#{1,6})(\s+|$)(.*)$')
# pandoc 的 markdown 要求 ATX 标题从行首开始。缩进 1~3 空格的「标题」不被
# 识别（实测：即使前面有空行也一样），必须单独抓出来报 error。
_ATX_IND = re.compile(r'^(\s{1,3})(#{1,6})(\s+|$)(.*)$')
_FENCE = re.compile(r'^\s{0,3}(`{3,}|~{3,})(.*)$')
_INDENTED = re.compile(r'^(?: {4}|\t)')
_GRID_RULE = re.compile(r'^\s*\+[-=+]{3,}\+\s*$')
_LIST = re.compile(r'^\s{0,3}([-*+]\s+|\d+[.)]\s+)')
_DELIM_ROW = re.compile(r'^\s*\|?[\s:\-|]+\|[\s:\-|]*$')
_IMG = re.compile(r'!\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')
_SETEXT = re.compile(r'^\s{0,3}(=+|-{2,})\s*$')


def split_row(line):
    """切分一行 pipe table，处理 \\| 转义与行内代码。

    行内代码里的 | 不是列分隔符 —— pandoc 的 pipe table 解析器尊重 code span，
    这里也必须尊重。否则 `grep -E "a|b" x | awk 1` 这样一格会被切成四格，
    结果是超宽漏报 + 「列数不一致」误报同时发生。
    """
    s = line.strip()
    if s.startswith('|'):
        s = s[1:]
    if s.endswith('|') and not s.endswith('\\|'):
        s = s[:-1]
    cells, buf, i = [], [], 0
    tick = 0            # 当前未闭合的行内代码反引号个数，0 表示不在代码里
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s) and s[i + 1] == '|':
            buf.append('|')
            i += 2
            continue
        if c == '`':
            k = i
            while k < len(s) and s[k] == '`':
                k += 1
            run = k - i
            if tick == 0:
                tick = run
            elif tick == run:
                tick = 0
            buf.append(s[i:k])
            i = k
            continue
        if c == '|' and tick == 0:
            cells.append(''.join(buf).strip())
            buf = []
        else:
            buf.append(c)
        i += 1
    cells.append(''.join(buf).strip())
    return cells


def cell_plain(s):
    """去掉行内标记，只留可见文字，用于宽度估算。"""
    s = re.sub(r'`([^`]*)`', r'\1', s)
    s = re.sub(r'!\[[^\]]*\]\([^)]*\)', '[图]', s)
    s = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', s)
    s = re.sub(r'<br\s*/?>', ' ', s, flags=re.I)
    s = re.sub(r'\*\*|__|\*|_|~~', '', s)
    return s.strip()


def lint_file(path):
    rep = Report(path)
    try:
        # utf-8-sig：带 BOM 的文件用 utf-8 读会让首行变成 '\ufeff# 标题'，
        # 首行标题识别不出来，紧跟的第二行标题反被判成「段落后紧跟标题」。
        with open(path, 'r', encoding='utf-8-sig') as f:
            raw = f.read()
    except OSError as e:
        rep.add(0, 'error', '无法读取文件：%s' % e, '检查路径与权限')
        return rep
    except UnicodeDecodeError as e:
        # 原先只捕 OSError，GBK 文件会抛未处理的 UnicodeDecodeError：
        # traceback、整批中断、后续文件全部不检、汇总一行都不打印。
        rep.add(0, 'error', '文件不是 UTF-8 编码：%s' % e,
                '整条链路按 UTF-8 处理；先转码：'
                'iconv -f gbk -t utf-8 旧文件.md > 新文件.md')
        return rep

    lines = raw.split('\n')
    n = len(lines)
    base_dir = os.path.dirname(os.path.abspath(path))

    # ---- 第一遍：标出代码围栏区间，围栏内的一切不做语法检查 ----
    in_code = [False] * n
    fence_open = None            # (char, len, line_idx)
    for i, line in enumerate(lines):
        m = _FENCE.match(line)
        if m:
            marker = m.group(1)
            info = m.group(2)
            # 反引号围栏的 info string 里不能再有反引号（CommonMark 与 pandoc
            # 都是这条规则）。不排除的话，行首的 ```json``` 这种**行内代码**
            # 会被当成开围栏，于是报一条假的「代码围栏未闭合」，还把它之后的
            # 全部检查关掉 —— 一条误报同时掩盖后面所有真问题。
            if marker[0] == '`' and '`' in info:
                continue
            if fence_open is None:
                fence_open = (marker[0], len(marker), i)
                in_code[i] = True
                # 代码围栏前缺空行
                if i > 0 and lines[i - 1].strip() != '':
                    rep.add(i + 1, 'warn', '代码围栏前缺空行',
                            '在 ``` 之前加一个空行，否则围栏可能被并入上一段')
                continue
            if marker[0] == fence_open[0] and len(marker) >= fence_open[1]:
                in_code[i] = True
                fence_open = None
                continue
        if fence_open is not None:
            in_code[i] = True
    if fence_open is not None:
        rep.add(fence_open[2] + 1, 'error', '代码围栏未闭合',
                '补一行 ``` 收尾，否则后续内容全部被当成代码')

    # ---- 标出 YAML frontmatter ----
    # 里面的 `# 这是注释` 不是标题，收尾的 --- 也不是 setext 下划线。
    # 不排除会同时产生两条误报：YAML 注释被当标题报「前缺空行」，紧跟
    # frontmatter 的首个 H1 也被判「前缺空行」—— 都会让 --strict 中止导出。
    fm_end = -1
    if lines and lines[0].strip() == '---':
        for k in range(1, n):
            if lines[k].strip() in ('---', '...'):
                fm_end = k
                break
    for k in range(0, fm_end + 1):
        in_code[k] = True

    # ---- 标出 4 空格缩进代码块 ----
    # 原先只跟踪围栏，缩进代码块里**演示**的 Markdown 表格会被当成真表格，
    # 报出假的「单元格过长」error，--strict 下直接中止导出。
    #
    # CommonMark：缩进代码块必须起于空行之后（段落后面的缩进行是段落续行）。
    # 列表项内部的缩进属于列表内容而非代码块，所以最近的非空行是列表项时
    # 不算 —— 宁可少标，也不要把列表里的表格漏检。
    in_indent = [False] * n
    k = 0
    while k < n:
        if in_code[k] or not _INDENTED.match(lines[k]) or lines[k].strip() == '':
            k += 1
            continue
        j = k - 1
        while j >= 0 and lines[j].strip() == '':
            j -= 1
        if j == k - 1 or (j >= 0 and (_LIST.match(lines[j])
                                     or _INDENTED.match(lines[j]))):
            k += 1
            continue
        while k < n:
            if lines[k].strip() == '':
                k2 = k
                while k2 < n and lines[k2].strip() == '':
                    k2 += 1
                if k2 < n and _INDENTED.match(lines[k2]):
                    k = k2
                    continue
                break
            if not _INDENTED.match(lines[k]):
                break
            in_indent[k] = True
            k += 1
    for k in range(n):
        if in_indent[k]:
            in_code[k] = True

    # ---- grid table：单元格宽度同样要检查 ----
    # 原先只认 pipe table。grid table 是 FROMSPEC 默认开启的扩展，pandoc
    # 正常解析、tablefit 照样按同一套显示宽度压列宽，lint 却一声不响。
    k = 0
    while k < n:
        if in_code[k] or not _GRID_RULE.match(lines[k]):
            k += 1
            continue
        g = k + 1
        rows = []
        while g < n and (_GRID_RULE.match(lines[g])
                         or lines[g].lstrip().startswith('|')):
            if lines[g].lstrip().startswith('|'):
                rows.append(g)
            g += 1
        if rows:
            for r in rows:
                for cell in split_row(lines[r]):
                    txt = cell_plain(cell)
                    w = disp_width(txt)
                    if w > 80:
                        rep.add(r + 1, 'error',
                                'grid 表格单元格过长：显示宽度 %d（≈%d 汉字）'
                                '→ 「%s」' % (w, w // 2, clip(txt, 30)),
                                '单格上限 80；改写成正文段落、列表，'
                                '或把该列拆成多列')
                    elif w > 40:
                        rep.add(r + 1, 'warn',
                                'grid 表格单元格偏长：显示宽度 %d（≈%d 汉字）'
                                % (w, w // 2),
                                '建议压到 40 以内（≈20 汉字）')
            for gi in range(k, g):
                in_code[gi] = True     # 已单独检查完，不再走 pipe table 那套
            k = g
            continue
        k += 1

    # ---- 标出 pipe table 占用的行 ----
    # 实测（pandoc 3.10）：表格行与代码围栏之后紧跟标题不会被吞，段落 / 列表 /
    # 引用之后紧跟标题才会被吞。分级要按这个来，否则 --strict 会误伤能正常导出的文档。
    in_table = [False] * n
    k = 0
    while k < n:
        if (not in_code[k] and '|' in lines[k] and lines[k].strip() != ''
                and k + 1 < n and not in_code[k + 1]
                and '|' in lines[k + 1] and _DELIM_ROW.match(lines[k + 1])):
            in_table[k] = in_table[k + 1] = True
            k += 2
            while k < n and not in_code[k] and '|' in lines[k] \
                    and lines[k].strip() != '':
                in_table[k] = True
                k += 1
            continue
        k += 1

    # ---- 第二遍：逐行检查 ----
    # 标题编号连续性：每级维护上一个编号
    last_num = {}
    prev_level = 0
    table_start = None           # 当前 pipe table 的起始行
    para_lines = []              # 当前段落
    para_start = None

    def flush_para():
        if para_lines and para_start is not None:
            w = disp_width(''.join(x.strip() for x in para_lines))
            if w > 800:
                rep.add(para_start, 'info',
                        '单段落显示宽度 %d（≈%d 汉字），偏长' % (w, w // 2),
                        '按语义拆成多段，或改用列表；过长段落在 PDF 里难以扫读')
        del para_lines[:]

    def prev_nonblank_idx(i):
        j = i - 1
        while j >= 0 and lines[j].strip() == '':
            j -= 1
        return j

    def prev_is_block(j):
        """第 j 行是不是「块级」前导 —— 它后面紧跟标题不会出任何问题。

        实测（pandoc 3.10.1 + 本 skill 的 FROMSPEC）这几种都能正常识别成
        标题，原先一律报 error 是误报，--strict 下会无故中止导出：
          frontmatter 的收尾 ---、HTML 注释、raw TeX（本 skill 自己就用
          \\newpage 控分页）、setext 标题的下划线、裸 HTML 块。
        """
        t = lines[j].strip()
        if j <= fm_end:                       # frontmatter 整段，含收尾 ---
            return True
        if _ATX.match(lines[j]) and not in_code[j]:
            return True
        if _FENCE.match(lines[j]):
            return True
        if t.startswith('<!--') or t.endswith('-->'):
            return True
        if t.startswith('\\'):               # \newpage / \clearpage / \vspace
            return True
        if _SETEXT.match(lines[j]):
            return True
        if t.startswith('<') and t.endswith('>'):
            return True
        return False

    i = 0
    while i < n:
        line = lines[i]
        stripped = line.strip()

        if in_code[i]:
            i += 1
            continue

        # ---------- 行尾硬换行 ----------
        if re.search(r'\S {2,}$', line):
            rep.add(i + 1, 'warn', '行尾有 2 个以上空格（Markdown 硬换行）',
                    '中文文档里通常是笔误，删掉行尾空格；确需换行用 <br> 或空行分段')

        # ---------- 图片存在性 ----------
        for m in _IMG.finditer(line):
            src = m.group(1)
            if re.match(r'^(https?:|data:|ftp:|//)', src):
                continue
            src_clean = src.split('#')[0].split('?')[0]
            try:
                from urllib.parse import unquote
                src_clean = unquote(src_clean)
            except Exception:
                pass
            if not src_clean:
                continue
            full = src_clean if os.path.isabs(src_clean) \
                else os.path.join(base_dir, src_clean)
            if not os.path.exists(full):
                rep.add(i + 1, 'warn', '图片文件不存在：%s' % clip(src, 40),
                        '相对路径以 md 文件所在目录为基准；确认文件已提交或改用绝对路径')

        # ---------- 缩进的「标题」：pandoc 根本不认 ----------
        him = _ATX_IND.match(line)
        if him:
            flush_para()
            para_start = None
            rep.add(i + 1, 'error',
                    '标题「%s」缩进了 %d 个空格，不会被识别为标题'
                    % (clip(him.group(4).strip().rstrip('#').strip(), 20),
                       len(him.group(1))),
                    '把 # 顶到行首。pandoc 的 markdown 要求 ATX 标题从行首'
                    '开始（这一点与 CommonMark 不同），缩进之后整行退化成'
                    '正文文字，目录里会缺这一章 —— 而编译不报任何错')
            i += 1
            continue

        # ---------- 标题 ----------
        hm = _ATX.match(line)
        if hm and not _DELIM_ROW.match(line):
            flush_para()
            para_start = None
            level = len(hm.group(1))
            text = hm.group(3).strip().rstrip('#').strip()

            # 标题前缺空行 —— 本次的真实事故
            j = i - 1
            if j >= 0:
                prev = lines[j]
                if prev.strip() != '':
                    prev_is_heading = bool(_ATX.match(prev)) and not in_code[j]
                    prev_is_fence = bool(_FENCE.match(prev))
                    if prev_is_fence or in_table[j]:
                        where = '代码围栏' if prev_is_fence else '表格'
                        rep.add(i + 1, 'warn',
                                '标题「%s」前缺空行（上一行是%s）'
                                % (clip(text, 20), where),
                                '这一处 pandoc 尚能识别，但同样应补空行，'
                                '以免后续编辑时退化成被吞')
                    elif not prev_is_block(j):
                        # 实测：export.sh 用的是 markdown-blank_before_header，
                        # 行首的标题即使紧跟段落也**能正常识别**，导出结果不受
                        # 影响 —— 所以这条不该是 error（error 的定义是「会实际
                        # 改变导出结果」）。真正会被吞的是缩进标题，已在上面
                        # 单独报 error。
                        rep.add(i + 1, 'warn',
                                '标题「%s」前缺空行' % clip(text, 20),
                                '本 skill 关掉了 blank_before_header，这里仍能'
                                '识别成标题，导出结果不变；但换任何其他 Markdown'
                                '工具（编辑器预览、GitHub、别的 pandoc 配置）都会'
                                '被吞进上一段，仍应在第 %d 行和第 %d 行之间补空行'
                                % (j + 1, i + 1))

            # 层级跳级
            if prev_level and level > prev_level + 1:
                rep.add(i + 1, 'warn',
                        '标题层级从 H%d 跳到 H%d' % (prev_level, level),
                        '补上中间的 H%d，否则目录层级与编号会错位'
                        % (prev_level + 1))

            # 手写编号连续性
            raw_no, val = heading_number(text)
            if val is not None:
                prev_no = last_num.get(level)
                if prev_no is not None and val != prev_no[1] + 1:
                    if val > prev_no[1]:
                        rep.add(i + 1, 'warn',
                                'H%d 手写编号不连续：「%s」之后是「%s」'
                                % (level, prev_no[0], raw_no),
                                '中间可能漏了一章，或编号需要重排')
                    elif val != prev_no[1]:
                        rep.add(i + 1, 'warn',
                                'H%d 手写编号回退：「%s」之后是「%s」'
                                % (level, prev_no[0], raw_no),
                                '确认是否重复编号；同级编号应递增')
                last_num[level] = (raw_no, val)
            # 进入新章后，下级编号重新计数
            for lv in list(last_num.keys()):
                if lv > level:
                    del last_num[lv]
            prev_level = level
            i += 1
            continue

        # ---------- 表格 ----------
        # pipe table：本行含 |，下一行是分隔行
        if ('|' in line and i + 1 < n and not in_code[i + 1]
                and _DELIM_ROW.match(lines[i + 1]) and '|' in lines[i + 1]
                and stripped != ''):
            flush_para()
            para_start = None
            table_start = i
            header_raw = split_row(line)
            header_cells = [cell_plain(c) for c in header_raw]
            ncols = len(header_cells)

            # 表格前缺空行 —— 实测会真的丢内容
            if i > 0 and lines[i - 1].strip() != '' and not _ATX.match(lines[i - 1]):
                rep.add(i + 1, 'error', '表格前缺空行，整张表会退化成上一段的文字',
                        '在表头行之前加一个空行。实测 pandoc 产出 0 个表格 —— '
                        '表头、分隔行、数据行全部变成普通文字，后果与标题被吞同级')

            # 分隔行列数少于表头 —— pandoc 的列数由分隔行决定，多出来的列
            # 会被**整列静默丢弃**（表头带数据一起没），而且写错分隔行的
            # 列数是极常见的手误。
            delim_cols = len(split_row(lines[i + 1]))
            if delim_cols < ncols:
                rep.add(i + 2, 'error',
                        '分隔行只有 %d 列，表头有 %d 列，多出的 %d 列会被整列丢弃'
                        % (delim_cols, ncols, ncols - delim_cols),
                        '把分隔行补成 %d 列，例如 %s'
                        % (ncols, '|' + '---|' * ncols))
            elif delim_cols > ncols:
                rep.add(i + 2, 'warn',
                        '分隔行 %d 列，表头 %d 列' % (delim_cols, ncols),
                        '两者应一致，否则多出的列在成品里是空列')

            # 表头单元格宽度 —— 原先宽度扫描从数据行（i+2）才开始，同样的
            # 长文本放在表头一声不响。中文长列名恰恰最常出现在表头。
            for ci, txt in enumerate(header_cells):
                w = disp_width(txt)
                if w > 80:
                    rep.add(i + 1, 'error',
                            '表头单元格过长：第%d列显示宽度 %d（≈%d 汉字）→ 「%s」'
                            % (ci + 1, w, w // 2, clip(txt, 30)),
                            '单格上限 80；把列名改短，说明挪到正文或表注里')
                elif w > 40:
                    rep.add(i + 1, 'warn',
                            '表头单元格偏长：第%d列显示宽度 %d（≈%d 汉字）'
                            % (ci + 1, w, w // 2),
                            '列名建议压到 40 以内（≈20 汉字）')

            if ncols > 6:
                rep.add(i + 1, 'warn', '表格列数 %d，超过建议上限 6' % ncols,
                        '拆成两张表，或把次要字段改写成「字段说明列表」')

            # 扫描数据行
            r = i + 2
            body_rows = 0
            while r < n and not in_code[r] and '|' in lines[r] \
                    and lines[r].strip() != '':
                body_rows += 1
                cells = split_row(lines[r])
                for ci, cell in enumerate(cells):
                    txt = cell_plain(cell)
                    w = disp_width(txt)
                    col_name = header_cells[ci] if ci < len(header_cells) \
                        else '第%d列' % (ci + 1)
                    if w > 80:
                        rep.add(r + 1, 'error',
                                '表格单元格过长：列「%s」显示宽度 %d（≈%d 汉字）→ 「%s」'
                                % (col_name or ('第%d列' % (ci + 1)), w, w // 2,
                                   clip(txt, 30)),
                                '单格上限 80；改写成正文段落、列表，或把该列拆成多列')
                    elif w > 40:
                        rep.add(r + 1, 'warn',
                                '表格单元格偏长：列「%s」显示宽度 %d（≈%d 汉字）'
                                % (col_name or ('第%d列' % (ci + 1)), w, w // 2),
                                '建议压到 40 以内（≈20 汉字），否则该列会占掉大半版心')
                if len(cells) != ncols:
                    rep.add(r + 1, 'warn',
                            '表格该行 %d 格，表头 %d 格，列数不一致'
                            % (len(cells), ncols),
                            '补齐或删掉多余的 |；单元格内的 | 要写成 \\|')
                r += 1

            if body_rows > 15:
                rep.add(table_start + 1, 'info',
                        '表格 %d 行数据，偏长' % body_rows,
                        '超过 15 行建议按语义拆表，跨页表格阅读体验较差')

            # 表格后缺空行（后面紧跟标题的情况由标题检查单独报，不重复）
            if r < n and lines[r].strip() != '' and not _ATX.match(lines[r]):
                rep.add(r + 1, 'warn', '表格后缺空行',
                        '在表格末行之后加一个空行，否则下一段会被并进表格')

            i = r
            continue

        # ---------- 列表 ----------
        if _LIST.match(line):
            flush_para()
            para_start = None
            j = i - 1
            if j >= 0 and lines[j].strip() != '' and not _LIST.match(lines[j]) \
                    and not _ATX.match(lines[j]) and not in_code[j] \
                    and not lines[j].startswith((' ', '\t')):
                rep.add(i + 1, 'warn', '列表前缺空行',
                        '在列表首项前加一个空行，否则列表会被并入上一段')
            # 吃掉整个列表块 —— 但遇到标题要停下来交还给标题检查，
            # 列表项后面紧跟标题恰恰是会被吞的高危写法。
            #
            # 块内不能一路 skip：原先这个循环把后续所有非空行跳过，于是
            # 列表后面的表格、图片、行尾空格三类检查全部失效。实测列表后
            # 紧跟表格时 pandoc 产出 0 个表格 —— 整张表变成列表项里的文字。
            i += 1
            while i < n and not in_code[i] and lines[i].strip() != '' \
                    and not _ATX.match(lines[i]) and not _ATX_IND.match(lines[i]):
                # 列表块内紧跟的表格 —— 真的会丢
                if ('|' in lines[i] and i + 1 < n and not in_code[i + 1]
                        and '|' in lines[i + 1]
                        and _DELIM_ROW.match(lines[i + 1])):
                    rep.add(i + 1, 'error',
                            '表格紧跟在列表后面，整张表会退化成列表项里的文字',
                            '在列表末项与表头行之间加一个空行。'
                            '实测 pandoc 产出 0 个表格')
                # 行尾硬换行与图片存在性照常检查
                if re.search(r'\S {2,}$', lines[i]):
                    rep.add(i + 1, 'warn',
                            '行尾有 2 个以上空格（Markdown 硬换行）',
                            '中文文档里通常是笔误，删掉行尾空格；'
                            '确需换行用 <br> 或空行分段')
                for m in _IMG.finditer(lines[i]):
                    src = m.group(1)
                    if re.match(r'^(https?:|data:|ftp:|//)', src):
                        continue
                    sc = src.split('#')[0].split('?')[0]
                    try:
                        from urllib.parse import unquote
                        sc = unquote(sc)
                    except Exception:
                        pass
                    if not sc:
                        continue
                    full = sc if os.path.isabs(sc) else os.path.join(base_dir, sc)
                    if not os.path.exists(full):
                        rep.add(i + 1, 'warn',
                                '图片文件不存在：%s' % clip(src, 40),
                                '相对路径以 md 文件所在目录为基准；'
                                '确认文件已提交或改用绝对路径')
                i += 1
            continue

        # ---------- 普通段落 ----------
        if stripped == '':
            flush_para()
            para_start = None
        else:
            if para_start is None:
                para_start = i + 1
            para_lines.append(line)
        i += 1

    flush_para()
    rep.items.sort(key=lambda x: (x[0], LEVELS.index(x[1])))
    return rep


# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------
def render(rep, color, quiet, verbose):
    """verbose=False 时只展开 error，warn/info 折叠成计数。

    长文档的表格警告动辄上百条。每次导出都全量刷屏，真正致命的 error
    反而被淹没 —— 默认只把会改变导出结果的 error 摊开。
    """
    def c(code, s):
        return (code + s + _RESET) if color else s

    if not rep.items:
        if not quiet:
            print(c(_BOLD, rep.path) + '  ' + c('\033[32m', '体检通过，未发现问题'))
        return

    shown = rep.items if verbose else [
        it for it in rep.items if it[1] == 'error']
    folded = len(rep.items) - len(shown)

    if shown or folded:
        print(c(_BOLD, rep.path))
    for line, level, msg, hint in shown:
        if quiet and level == 'info':
            continue
        loc = '%s:%d' % (os.path.basename(rep.path), line)
        print('  %-28s %s  %s' % (
            c(_DIM, loc),
            c(_COLOR[level], _LABEL[level]),
            msg))
        if hint:
            print('  %-28s      %s' % ('', c(_DIM, '建议：' + hint)))

    if folded:
        print('  %-28s %s' % (
            '', c(_DIM, '另有 %d 条警告/提示已折叠，加 --verbose 查看全部'
                  % folded)))


def main(argv=None):
    ap = argparse.ArgumentParser(
        description='Markdown 导出前体检（paper-export）',
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('files', nargs='+', help='待检查的 .md 文件')
    ap.add_argument('--strict', action='store_true',
                    help='存在 error 时退出码为 1')
    ap.add_argument('--quiet', action='store_true',
                    help='关闭颜色，并隐藏 info 级提示')
    ap.add_argument('--verbose', '-v', action='store_true',
                    help='展开全部警告与提示（默认只展开 error）')
    args = ap.parse_args(argv)

    color = (not args.quiet) and sys.stdout.isatty() \
        and os.environ.get('NO_COLOR') is None

    total = dict((lv, 0) for lv in LEVELS)
    for idx, path in enumerate(args.files):
        rep = lint_file(path)
        if idx:
            print('')
        render(rep, color, args.quiet, args.verbose)
        for lv, k in rep.counts().items():
            total[lv] += k

    def c(code, s):
        return (code + s + _RESET) if color else s

    print('')
    print('%s 共检查 %d 个文件：%s %d，%s %d，%s %d' % (
        c(_BOLD, '汇总'), len(args.files),
        c(_COLOR['error'], '错误'), total['error'],
        c(_COLOR['warn'], '警告'), total['warn'],
        c(_COLOR['info'], '提示'), total['info']))
    if total['error']:
        print('%s 错误项会实际丢内容（标题不被识别、整张表或整列消失），'
              '务必先修。' % c(_COLOR['error'], '注意：'))
    if not args.verbose and (total['warn'] or total['info']):
        print('%s 完整清单：python3 scripts/md-lint.py <文件> --verbose'
              % c(_DIM, '  '))

    if args.strict and total['error']:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
