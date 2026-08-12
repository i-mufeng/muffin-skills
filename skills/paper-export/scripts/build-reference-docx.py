#!/usr/bin/env python3
"""
paper-export :: 生成 Word 母版（reference-{gb,report,brief}.docx）

pandoc 自带的 reference.docx 是西文排版风格：US Letter、无页眉页脚、
标题带主题蓝、中文落到 Word 默认回退字体。本脚本以它为基底，
按 SPEC 重写页面设置 / 样式表 / 页眉页脚部件，产出中文论文·报告母版。

产出的母版包含：
  - word/document.xml 的 sectPr：A4 + 中式页边距 + header1/footer1 引用
  - word/header1.xml / footer1.xml   正文节页眉页脚
  - word/header2.xml / footer2.xml   前置（目录）节页眉页脚
  - word/styles.xml                  全套黑色中文样式 + 三线表 + 封面样式
  - word/settings.xml                updateFields=true（Word 打开即刷新域）

用法:
    python3 build-reference-docx.py gb      → assets/reference-gb.docx
    python3 build-reference-docx.py report  → assets/reference-report.docx
    python3 build-reference-docx.py brief   → assets/reference-brief.docx
    python3 build-reference-docx.py all
"""
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

# ---------------------------------------------------------------- 常量

CN_SERIF = "宋体"
CN_SANS = "黑体"
CN_KAI = "楷体"
CN_FANG = "仿宋"     # 公文正文字体（brief 预设）
# 阿里巴巴普惠体（modern 预设）。Word 认的是 name ID 1，也就是带字重后缀的
# 那个名字 —— 只写「Alibaba PuHuiTi 3.0」会落到 Regular，Bold 变伪粗。
PH_REG = "Alibaba PuHuiTi 3.0 55 Regular"
PH_MED = "Alibaba PuHuiTi 3.0 65 Medium"
PH_BOLD = "Alibaba PuHuiTi 3.0 85 Bold"
# 这两个旧默认名只作为调用参数保留；rfonts() 会让普通英文和数字跟随 cn。
# 唯一例外是显式传入 MONO 的代码块。
SANS_LATIN = "Arial"
LATIN = "Times New Roman"
# 代码块等宽：Maple Mono CN 中英同源、中文恰好 2 倍宽，与 PDF 侧一致；
# Word 里字体缺失会静默回退，所以 CJK 侧仍单独给正文字体兜底。
MONO = "Maple Mono CN"

BLACK = "000000"
CODE_BG = "F7F7F8"
QUOTE_BAR = "BFBFBF"
TABLE_HEAD_FILL = "F2F2F2"

# 字号（w:sz = 半磅）
SZ_YI = 52      # 一号 26pt
SZ_ER = 44      # 二号 22pt
SZ_SAN = 32     # 三号 16pt
SZ_XSAN = 30    # 小三 15pt
SZ_SI = 28      # 四号 14pt
SZ_13 = 26      # 13pt
SZ_XSI = 24     # 小四 12pt
SZ_WU = 21      # 五号 10.5pt
SZ_XWU = 18     # 小五 9pt

# 页面（twips）
PG_W, PG_H = 11906, 16838
MARGIN_TOP = MARGIN_BOTTOM = MARGIN_RIGHT = 1440
HDR_DIST, FTR_DIST = 850, 992

# 页眉页脚里替换用的占位符
TITLE_PLACEHOLDER = "@@PE_DOC_TITLE@@"

# 自定义关系 ID（避开 pandoc 自己从 rId99 倒着分配的区间）
REL_HDR1 = "rIdPEHeader1"
REL_FTR1 = "rIdPEFooter1"
REL_HDR2 = "rIdPEHeader2"
REL_FTR2 = "rIdPEFooter2"

PRESETS = {
    "report": {
        "margin_left": 1701,          # 3.0cm 装订边
        "h1_align": "center",
        "h3_sz": SZ_13,               # report 的 H3 = 13pt，与正文拉开层级
        "h3_font": CN_SANS,
        "h4_font": CN_SANS,
        "footer_fmt": "dash",         # - N -
        "header_layout": "title_left_h1_right",
    },
    # 默认预设：版面与 report 完全相同，只换字体族。
    # 改版面请改 report，这里刻意只列字体相关的键。
    "modern": {
        "margin_left": 1701,
        "h1_align": "center",
        "h3_sz": SZ_13,
        "h3_font": PH_BOLD,
        "h4_font": PH_MED,            # H4/H5 降一档字重，否则四级标题全塌成 Bold
        "footer_fmt": "dash",
        "header_layout": "title_left_h1_right",
        "body_font": PH_REG,
        "sans_font": PH_BOLD,         # 承担原来「黑体」的角色
        "kai_font": PH_MED,           # 承担原来「楷体」的角色（封面信息栏）
        "latin": SANS_LATIN,          # rfonts() 会统一为当前普惠体字重
        "body_line": 365,             # 1.52 倍，与 preamble-modern.tex 一致
    },
    "gb": {
        "margin_left": 1797,          # 3.17cm 装订边
        "h1_align": "center",
        "h3_sz": SZ_XSI,
        "h3_font": CN_SANS,
        "h4_font": CN_SANS,
        "footer_fmt": "plain",        # N
        "header_layout": "chapter_center",
    },
    # 简报 / 通报 / 会议纪要：GB/T 9704-2012 公文版心，无页眉页脚无页码。
    # 层级靠**字体**区分（黑体→楷体→仿宋加粗），四级标题与正文同为三号 ——
    # 通报正文短，用字号分级反而像技术手册。
    "brief": {
        "margin_top": 2098,           # 37mm 天头
        "margin_bottom": 1984,        # 35mm 地脚
        "margin_left": 1587,          # 28mm，公文不装订，无额外装订线
        "margin_right": 1474,         # 26mm
        "h1_align": "center",
        "h3_sz": SZ_SAN,
        "h3_font": CN_KAI,
        "h4_font": CN_FANG,
        "footer_fmt": "none",
        "header_layout": "none",
        "body_font": CN_FANG,
        "body_sz": SZ_SAN,            # 三号 16pt
        "body_line": 560,             # 固定 28pt —— 公文一页 22 行的来源
        "body_line_rule": "exact",
    },
}

BODY_LINE = 360        # 1.5 倍行距
TIGHT_LINE = 240       # 1.0 倍行距


def margins(preset: str):
    """(top, bottom, left, right)，未声明的字段回落到通用值。"""
    P = PRESETS[preset]
    return (P.get("margin_top", MARGIN_TOP),
            P.get("margin_bottom", MARGIN_BOTTOM),
            P["margin_left"],
            P.get("margin_right", MARGIN_RIGHT))


def text_width(preset: str) -> int:
    _, _, left, right = margins(preset)
    return PG_W - left - right


# ---------------------------------------------------------------- XML 片段生成


def esc(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;")
             .replace(">", "&gt;").replace('"', "&quot;"))


def rfonts(cn: str = None, latin: str = None) -> str:
    if not cn and not latin:
        return ""
    # 普通文本的英文、数字跟随当前中文字体；代码块明确传 MONO，保持等宽。
    if cn and latin != MONO:
        latin = cn
    a = []
    if latin:
        a.append(f'w:ascii="{latin}" w:hAnsi="{latin}" w:cs="{latin}"')
    if cn:
        a.append(f'w:eastAsia="{cn}"')
    return f'<w:rFonts {" ".join(a)}/>'


def rpr(cn=None, latin=None, sz=None, bold=False, italic=False,
        color=BLACK, underline=None, shd=None, char_spacing=None,
        vert=None, rstyle=None, caps=False) -> str:
    """按 CT_RPr 的元素顺序拼装 <w:rPr>。color 传 None 表示不写。"""
    p = []
    if rstyle:
        p.append(f'<w:rStyle w:val="{rstyle}"/>')
    p.append(rfonts(cn, latin))
    if bold:
        p.append("<w:b/><w:bCs/>")
    if italic:
        p.append("<w:i/><w:iCs/>")
    if caps:
        p.append("<w:caps/>")
    if color:
        p.append(f'<w:color w:val="{color}"/>')
    if char_spacing is not None:
        p.append(f'<w:spacing w:val="{char_spacing}"/>')
    if sz:
        p.append(f'<w:sz w:val="{sz}"/><w:szCs w:val="{sz}"/>')
    p.append(f'<w:u w:val="{underline}"/>' if underline else "")
    if shd:
        p.append(f'<w:shd w:val="clear" w:color="auto" w:fill="{shd}"/>')
    if vert:
        p.append(f'<w:vertAlign w:val="{vert}"/>')
    body = "".join(x for x in p if x)
    return f"<w:rPr>{body}</w:rPr>" if body else ""


def ppr(align=None, line=None, line_rule="auto", before=None, after=None,
        first_chars=None, first=None, left=None, right=None, hanging=None,
        keep_next=False, keep_lines=False, page_break=False, widow=True,
        outline=None, bdr_bottom=None, bdr_left=None, shd=None, tabs=None,
        contextual=False, snap_to_grid_off=True) -> str:
    """按 CT_PPr 的元素顺序拼装 <w:pPr>。"""
    p = []
    if keep_next:
        p.append("<w:keepNext/>")
    if keep_lines:
        p.append("<w:keepLines/>")
    if page_break:
        p.append("<w:pageBreakBefore/>")
    if widow:
        p.append("<w:widowControl/>")
    # 段落边框
    if bdr_bottom or bdr_left:
        b = ["<w:pBdr>"]
        if bdr_left:
            sz, color = bdr_left
            b.append(f'<w:left w:val="single" w:sz="{sz}" w:space="4" '
                     f'w:color="{color}"/>')
        if bdr_bottom:
            sz, color = bdr_bottom
            b.append(f'<w:bottom w:val="single" w:sz="{sz}" w:space="1" '
                     f'w:color="{color}"/>')
        b.append("</w:pBdr>")
        p.append("".join(b))
    if shd:
        p.append(f'<w:shd w:val="clear" w:color="auto" w:fill="{shd}"/>')
    if tabs:
        t = ["<w:tabs>"]
        for val, pos, leader in tabs:
            ld = f' w:leader="{leader}"' if leader else ""
            t.append(f'<w:tab w:val="{val}"{ld} w:pos="{pos}"/>')
        t.append("</w:tabs>")
        p.append("".join(t))
    if snap_to_grid_off:
        p.append('<w:snapToGrid w:val="0"/>')
    if line is not None or before is not None or after is not None:
        a = []
        if before is not None:
            a.append(f'w:before="{before}" w:beforeLines="0" '
                     f'w:beforeAutospacing="0"')
        if after is not None:
            a.append(f'w:after="{after}" w:afterLines="0" '
                     f'w:afterAutospacing="0"')
        if line is not None:
            a.append(f'w:line="{line}" w:lineRule="{line_rule}"')
        p.append(f'<w:spacing {" ".join(a)}/>')
    ind = []
    if left is not None:
        ind.append(f'w:left="{left}" w:leftChars="0"')
    if right is not None:
        ind.append(f'w:right="{right}" w:rightChars="0"')
    if hanging is not None:
        ind.append(f'w:hanging="{hanging}"')
    elif first_chars is not None:
        ind.append(f'w:firstLineChars="{first_chars}" w:firstLine="{first}"')
    elif first is not None:
        ind.append(f'w:firstLineChars="0" w:firstLine="{first}"')
    if ind:
        p.append(f'<w:ind {" ".join(ind)}/>')
    if contextual:
        p.append("<w:contextualSpacing/>")
    if align:
        p.append(f'<w:jc w:val="{align}"/>')
    if outline is not None:
        p.append(f'<w:outlineLvl w:val="{outline}"/>')
    body = "".join(p)
    return f"<w:pPr>{body}</w:pPr>" if body else ""


# ---------------------------------------------------------------- 样式表


def build_styles(preset: str) -> dict:
    """返回 {styleId: (pPr_xml, rPr_xml)} 以及新建样式的完整定义。"""
    P = PRESETS[preset]
    tw = text_width(preset)
    brief = preset == "brief"

    # 字体族三件套：预设没声明就回落到「宋体 / 黑体 / 楷体 + Times」那一套。
    # modern 把它们整体换成阿里巴巴普惠体的三档字重 + Arial。
    sans_cn = P.get("sans_font", CN_SANS)
    kai_cn = P.get("kai_font", CN_KAI)
    latin = P.get("latin", LATIN)

    # 正文字体 / 字号 / 行距：brief 是仿宋三号 + 固定 28pt，其余是宋体小四 + 1.5 倍
    body_cn = P.get("body_font", CN_SERIF)
    body_sz = P.get("body_sz", SZ_XSI)
    body_line = P.get("body_line", BODY_LINE)
    body_rule = P.get("body_line_rule", "auto")
    # 首行缩进 2 字符：first_chars 是给 Word 用的，first 是给不认 chars 的
    # 渲染器（LibreOffice 等）用的绝对值，两者必须按当前字号同步换算。
    body_indent = dict(first_chars=200, first=body_sz * 10)

    def body_ppr(**kw):
        kw.setdefault("align", "both")
        kw.setdefault("before", 0)
        kw.setdefault("after", 0)
        return ppr(line=body_line, line_rule=body_rule, **kw)

    S = {}

    def st(sid, pp="", rp=""):
        S[sid] = (pp, rp)

    # ---- 正文族 ----
    body_rp = rpr(cn=body_cn, latin=latin, sz=body_sz)
    st("Normal", body_ppr(**body_indent), body_rp)
    st("BodyText", body_ppr(**body_indent), body_rp)
    st("FirstParagraph", body_ppr(**body_indent), body_rp)
    # Compact 同时服务「紧凑列表项」与「表格单元格」：
    # 不设字号（由 Normal 继承正文字号），表格里的字号由 docx-postprocess.py
    # 以直接格式压小 —— 这样列表跟随正文、表格自成一档，两不相扰。
    st("Compact", body_ppr(first=0), body_rp)

    # ---- 标题族 ----
    if brief:
        # 公文层级：一、（黑体）→（一）（楷体）→ 1.（仿宋加粗）。
        # 全部三号、全部首行缩进 2 字符、全部左对齐（H1 除外，它是兜底的篇名）。
        heading = [
            (1, SZ_SAN, sans_cn, True,  False, "center", 120, 120),
            (2, SZ_SAN, sans_cn, False, False, "left",   160,  80),
            (3, SZ_SAN, kai_cn,  False, False, "left",   120,  60),
            (4, SZ_SAN, CN_FANG, True,  False, "left",    80,  40),
            (5, SZ_SAN, CN_FANG, True,  False, "left",    60,  40),
            (6, SZ_SAN, CN_FANG, True,  True,  "left",    60,  40),
            (7, SZ_SAN, CN_FANG, True,  False, "left",    60,  40),
            (8, SZ_SAN, CN_FANG, True,  True,  "left",    60,  40),
            (9, SZ_SAN, CN_FANG, False, False, "left",    60,  40),
        ]
    else:
        heading = [
            (1, SZ_SAN, sans_cn, True, False, P["h1_align"], 0, 360),
            (2, SZ_SI, sans_cn, True, False, "left", 360, 240),
            (3, P["h3_sz"], P["h3_font"], True, False, "left", 240, 120),
            (4, SZ_XSI, P["h4_font"], True, False, "left", 180, 60),
            (5, SZ_XSI, body_cn, True, False, "left", 120, 60),
            (6, SZ_XSI, body_cn, True, True, "left", 120, 60),
            (7, SZ_XSI, body_cn, True, False, "left", 120, 60),
            (8, SZ_XSI, body_cn, True, True, "left", 120, 60),
            (9, SZ_XSI, body_cn, False, False, "left", 120, 60),
        ]
    for lvl, sz, cn, bold, ital, align, before, after in heading:
        # 所有预设的标题一律左顶格，缩进只留给正文段落首行 ——
        # 理由见 preamble-brief.tex 第 4 节：标题也缩进会让左边界失去锚点。
        ind = dict(first=0)
        pp = ppr(align=align, line=body_line if brief else BODY_LINE,
                 line_rule=body_rule if brief else "auto",
                 before=before, after=after,
                 keep_next=True, keep_lines=True, outline=lvl - 1, **ind)
        rp = rpr(cn=cn, latin=latin, sz=sz, bold=bold, italic=ital)
        st(f"Heading{lvl}", pp, rp)
        st(f"Heading{lvl}Char", "", rp)

    # ---- 标题页 / 封面相关（Title、Subtitle 仍保留，供不走封面 filter 的场景）----
    st("Title",
       ppr(align="center", line=TIGHT_LINE, before=240, after=240, first=0),
       rpr(cn=sans_cn, latin=latin, sz=SZ_YI, bold=True))
    st("TitleChar", "", rpr(cn=sans_cn, latin=latin, sz=SZ_YI, bold=True))
    st("Subtitle",
       ppr(align="center", line=TIGHT_LINE, before=120, after=240, first=0),
       rpr(cn=sans_cn, latin=latin, sz=SZ_SAN))
    st("SubtitleChar", "", rpr(cn=sans_cn, latin=latin, sz=SZ_SAN))
    st("Author",
       ppr(align="center", line=TIGHT_LINE, before=60, after=60, first=0),
       rpr(cn=kai_cn, latin=latin, sz=SZ_XSAN))
    st("Date",
       ppr(align="center", line=TIGHT_LINE, before=60, after=60, first=0),
       rpr(cn=body_cn, latin=latin, sz=SZ_SAN))
    st("AbstractTitle",
       ppr(align="center", line=BODY_LINE, before=240, after=180, first=0,
           keep_next=True),
       rpr(cn=sans_cn, latin=latin, sz=SZ_SAN, bold=True))
    st("Abstract", body_ppr(after=180, **body_indent), body_rp)
    st("Bibliography",
       body_ppr(after=60, left=480, hanging=480), body_rp)

    # ---- 目录 ----
    # 不加 pageBreakBefore：分页由 docx-postprocess.py 的分节符负责
    st("TOCHeading",
       ppr(align="center", line=BODY_LINE, before=0, after=360, first=0,
           keep_next=True, outline=9),
       rpr(cn=sans_cn, latin=latin, sz=SZ_SAN, bold=True, char_spacing=60))
    toc_ind = [0, 420, 840, 1260, 1680, 2100, 2520, 2940, 3360]
    for lvl in range(1, 10):
        cn = sans_cn if lvl == 1 else body_cn
        st(f"TOC{lvl}",
           ppr(align="left", line=TIGHT_LINE, before=60 if lvl == 1 else 0,
               after=60 if lvl == 1 else 0, first=0,
               left=toc_ind[lvl - 1],
               tabs=[("right", tw, "dot")]),
           rpr(cn=cn, latin=latin, sz=SZ_XSI))

    # ---- 题注 ----
    cap_ppr = ppr(align="center", line=TIGHT_LINE, before=60, after=60,
                  first=0, keep_lines=True)
    # brief 正文是三号，题注用五号落差太大，抬到小四
    cap_rpr = rpr(cn=sans_cn, latin=latin, sz=SZ_XSI if brief else SZ_WU)
    st("Caption", cap_ppr, cap_rpr)
    st("TableCaption",
       ppr(align="center", line=TIGHT_LINE, before=120, after=60, first=0,
           keep_next=True, keep_lines=True), cap_rpr)
    st("ImageCaption",
       ppr(align="center", line=TIGHT_LINE, before=60, after=120, first=0,
           keep_lines=True), cap_rpr)
    st("Figure",
       ppr(align="center", line=TIGHT_LINE, before=120, after=60, first=0),
       rpr(cn=body_cn, latin=latin, sz=SZ_XSI))
    st("CaptionedFigure",
       ppr(align="center", line=TIGHT_LINE, before=120, after=0, first=0,
           keep_next=True),
       rpr(cn=body_cn, latin=latin, sz=SZ_XSI))

    # ---- 代码 ----
    st("SourceCode",
       ppr(align="left", line=TIGHT_LINE, before=60, after=60, first=0,
           left=120, shd=CODE_BG),
       rpr(cn=body_cn, latin=MONO, sz=SZ_WU))
    st("VerbatimChar", "", rpr(cn=body_cn, latin=MONO, sz=SZ_WU, shd=CODE_BG))

    # ---- 引用块：左竖条 + 浅灰底 + 不缩进 ----
    st("BlockText",
       body_ppr(before=120, after=120, first=0,
                left=284, right=0, bdr_left=(18, QUOTE_BAR), shd=CODE_BG),
       body_rp)

    # ---- 脚注 ----
    st("FootnoteText",
       ppr(align="both", line=TIGHT_LINE, before=0, after=0, first=0),
       rpr(cn=body_cn, latin=latin, sz=SZ_WU))
    st("FootnoteBlockText",
       ppr(align="both", line=TIGHT_LINE, before=0, after=0, first=0,
           left=284),
       rpr(cn=body_cn, latin=latin, sz=SZ_WU))
    st("FootnoteReference", "",
       rpr(cn=body_cn, latin=latin, sz=SZ_WU, vert="superscript"))
    st("BodyTextChar", "", body_rp)
    st("DefaultParagraphFont", "", "")
    st("SectionNumber", "", rpr(cn=sans_cn, latin=latin))

    # ---- 定义列表 ----
    st("DefinitionTerm",
       body_ppr(align="left", before=120, first=0,
                keep_next=True, keep_lines=True),
       rpr(cn=sans_cn, latin=latin, sz=body_sz, bold=True))
    st("Definition",
       body_ppr(after=60, first=0, left=480), body_rp)

    # ---- 超链接：黑色无下划线（打印友好）----
    st("Hyperlink", "", rpr(cn=body_cn, latin=latin, underline="none"))
    st("FollowedHyperlink", "",
       rpr(cn=body_cn, latin=latin, underline="none"))

    return S


def new_style_xml(sid: str, name: str, stype: str, based: str,
                  pp: str, rp: str, extra: str = "") -> str:
    custom = ' w:customStyle="1"' if name == sid else ""
    based_xml = f'<w:basedOn w:val="{based}"/>' if based else ""
    return (f'<w:style w:type="{stype}"{custom} w:styleId="{sid}">'
            f'<w:name w:val="{esc(name)}"/>{based_xml}'
            f'<w:qFormat/>{extra}{pp}{rp}</w:style>')


# 母版基底里没有、需要新建的样式：sid -> (name, type, basedOn)
NEW_STYLES = {
    "SourceCode": ("Source Code", "paragraph", "Normal"),
    "Header": ("header", "paragraph", "Normal"),
    "Footer": ("footer", "paragraph", "Normal"),
    "FollowedHyperlink": ("FollowedHyperlink", "character",
                          "DefaultParagraphFont"),
    "PEDocTitle": ("PEDocTitle", "character", "DefaultParagraphFont"),
    "PECoverOrg": ("PECoverOrg", "paragraph", "Normal"),
    "PECoverTitle": ("PECoverTitle", "paragraph", "Normal"),
    "PECoverSubtitle": ("PECoverSubtitle", "paragraph", "Normal"),
    "PECoverInfo": ("PECoverInfo", "paragraph", "Normal"),
    "PECoverDate": ("PECoverDate", "paragraph", "Normal"),
    "PECoverRule": ("PECoverRule", "paragraph", "Normal"),
    "PECoverGap": ("PECoverGap", "paragraph", "Normal"),
    "PESectCover": ("PESectCover", "paragraph", "Normal"),
    "PESectCoverBreak": ("PESectCoverBreak", "paragraph", "Normal"),
    "PESectFront": ("PESectFront", "paragraph", "Normal"),
    "PEBriefOrg": ("PEBriefOrg", "paragraph", "Normal"),
    "PEBriefTitle": ("PEBriefTitle", "paragraph", "Normal"),
    "PEBriefSubtitle": ("PEBriefSubtitle", "paragraph", "Normal"),
    "PEBriefRuleThick": ("PEBriefRuleThick", "paragraph", "Normal"),
    "PEBriefRuleThin": ("PEBriefRuleThin", "paragraph", "Normal"),
    "PEBriefGap": ("PEBriefGap", "paragraph", "Normal"),
    "PEBriefSignoff": ("PEBriefSignoff", "paragraph", "Normal"),
}
for _l in range(1, 10):
    NEW_STYLES[f"TOC{_l}"] = (f"toc {_l}", "paragraph", "Normal")


def build_extra_styles(preset: str) -> dict:
    """页眉页脚 + 封面 + 分节标记样式，返回 {sid: (pPr, rPr)}。"""
    P = PRESETS[preset]
    tw = text_width(preset)
    sans_cn = P.get("sans_font", CN_SANS)
    kai_cn = P.get("kai_font", CN_KAI)
    latin = P.get("latin", LATIN)
    body_cn = P.get("body_font", CN_SERIF)
    _, _, margin_left, margin_right = margins(preset)
    # 正文左侧有装订边，封面需要按纸张物理中心校正。成对使用负/正缩进，
    # 保持可用宽度不变；信息栏再额外左移约 6mm。
    cover_shift = (margin_left - margin_right) // 2
    info_shift = cover_shift + 340
    cover_left, cover_right = -cover_shift, cover_shift
    info_left, info_right = -info_shift, info_shift
    S = {}
    hf_rpr = rpr(cn=body_cn, latin=latin, sz=SZ_XWU)
    S["Header"] = (
        ppr(align="left", line=TIGHT_LINE, before=0, after=0, first=0,
            bdr_bottom=(6, BLACK),
            tabs=[("center", tw // 2, None), ("right", tw, None)]),
        hf_rpr)
    S["Footer"] = (
        ppr(align="center", line=TIGHT_LINE, before=0, after=0, first=0,
            tabs=[("center", tw // 2, None), ("right", tw, None)]),
        hf_rpr)
    S["PEDocTitle"] = ("", hf_rpr)

    # 封面（行高全部 exact，便于 cover-docx.lua 精确计算纵向位置）
    S["PECoverOrg"] = (
        ppr(align="center", line=520, line_rule="exact", before=0, after=0,
            first=0, left=cover_left, right=cover_right),
        rpr(cn=sans_cn, latin=latin, sz=SZ_SAN))
    S["PECoverTitle"] = (
        ppr(align="center", line=800, line_rule="exact", before=0, after=0,
            first=0, left=cover_left, right=cover_right, keep_next=True),
        rpr(cn=sans_cn, latin=latin, sz=SZ_YI, bold=True, char_spacing=40))
    S["PECoverSubtitle"] = (
        ppr(align="center", line=560, line_rule="exact", before=0, after=0,
            first=0, left=cover_left, right=cover_right),
        rpr(cn=sans_cn, latin=latin, sz=SZ_SAN))
    S["PECoverInfo"] = (
        ppr(align="center", line=480, line_rule="exact", before=0, after=0,
            first=0, left=info_left, right=info_right),
        rpr(cn=kai_cn, latin=latin, sz=SZ_XSAN))
    S["PECoverDate"] = (
        ppr(align="center", line=520, line_rule="exact", before=0, after=0,
            first=0, left=cover_left, right=cover_right),
        rpr(cn=body_cn, latin=latin, sz=SZ_SAN))
    # 横线：宽 60% 居中，靠段落下边框实现
    side = int(tw * 0.2)
    S["PECoverRule"] = (
        ppr(align="center", line=220, line_rule="exact", before=0, after=0,
            first=0, left=side - cover_shift, right=side + cover_shift,
            bdr_bottom=(6, BLACK)),
        rpr(cn=body_cn, latin=latin, sz=2))
    S["PECoverGap"] = (
        ppr(align="center", line=240, line_rule="exact", before=0, after=0,
            first=0),
        rpr(cn=body_cn, latin=latin, sz=2))
    for sid in ("PESectCover", "PESectCoverBreak", "PESectFront"):
        S[sid] = (
            ppr(align="left", line=20, line_rule="exact", before=0, after=0,
                first=0),
            rpr(cn=body_cn, latin=latin, sz=2))

    # ---- brief 的文头与落款（与 masthead-brief.tex / signoff-brief.tex 对应）--
    # 这几个样式在所有母版里都建出来，不按预设裁剪：多几个未使用的样式无害，
    # 而漏建会让 cover-docx.lua 引用到不存在的 pStyle，Word 静默退回 Normal。
    S["PEBriefOrg"] = (
        ppr(align="center", line=440, line_rule="exact", before=0, after=120,
            first=0),
        rpr(cn=kai_cn, latin=latin, sz=SZ_SI))
    S["PEBriefTitle"] = (
        ppr(align="center", line=660, line_rule="exact", before=0, after=0,
            first=0, keep_next=True),
        rpr(cn=sans_cn, latin=latin, sz=SZ_ER, bold=True, char_spacing=20))
    S["PEBriefSubtitle"] = (
        ppr(align="center", line=460, line_rule="exact", before=120, after=0,
            first=0, keep_next=True),
        rpr(cn=kai_cn, latin=latin, sz=SZ_SAN))
    # 双线：两个空段落各画一条下边框，上 1.2pt（sz=10）下 0.4pt（sz=3）。
    # Word 画不出「自定粗细的双线边框」，两条独立的线反而更可控，
    # 粗细比也和 PDF 侧一致。
    S["PEBriefRuleThick"] = (
        ppr(align="left", line=240, line_rule="exact", before=180, after=0,
            first=0, bdr_bottom=(10, BLACK)),
        rpr(cn=body_cn, latin=latin, sz=2))
    S["PEBriefRuleThin"] = (
        ppr(align="left", line=40, line_rule="exact", before=0, after=0,
            first=0, bdr_bottom=(3, BLACK)),
        rpr(cn=body_cn, latin=latin, sz=2))
    S["PEBriefGap"] = (
        ppr(align="left", line=240, line_rule="exact", before=0, after=0,
            first=0),
        rpr(cn=body_cn, latin=latin, sz=2))
    # 落款：右对齐，距右边界 4 字宽（三号 16pt × 4 ≈ 1280 twips）
    S["PEBriefSignoff"] = (
        ppr(align="right", line=460, line_rule="exact", before=0, after=0,
            first=0, right=1280),
        rpr(cn=CN_FANG, latin=latin, sz=SZ_SAN))
    return S


def table_style_xml(preset: str, sid: str = "Table", default: bool = True,
                    head_fill: str = None) -> str:
    """三线表：顶线 1.5pt / 表头下线 0.75pt / 底线 1.5pt，无竖线。

    head_fill=None 时表头不加底纹（国标三线表默认形态，与 PDF 侧一致）；
    传入色值则生成带底纹的变体（TableFilled）。
    """
    dflt = ' w:default="1"' if default else ""
    shd = (f'<w:shd w:val="clear" w:color="auto" w:fill="{head_fill}"/>'
           if head_fill else "")
    return (
        f'<w:style w:type="table"{dflt} w:styleId="{sid}">'
        f'<w:name w:val="{sid}"/>'
        '<w:basedOn w:val="TableNormal"/>'
        '<w:qFormat/>'
        + ppr(align="left", line=TIGHT_LINE, before=20, after=20, first=0,
              widow=False)
        + rpr(cn=CN_SERIF, latin=LATIN, sz=SZ_WU)
        + '<w:tblPr>'
          '<w:jc w:val="center"/>'
          '<w:tblInd w:w="0" w:type="dxa"/>'
          '<w:tblBorders>'
          f'<w:top w:val="single" w:sz="12" w:space="0" w:color="{BLACK}"/>'
          '<w:left w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
          f'<w:bottom w:val="single" w:sz="12" w:space="0" w:color="{BLACK}"/>'
          '<w:right w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
          '<w:insideH w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
          '<w:insideV w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
          '</w:tblBorders>'
          '<w:tblCellMar>'
          '<w:top w:w="60" w:type="dxa"/><w:left w:w="108" w:type="dxa"/>'
          '<w:bottom w:w="60" w:type="dxa"/><w:right w:w="108" w:type="dxa"/>'
          '</w:tblCellMar>'
          '</w:tblPr>'
          '<w:tblStylePr w:type="firstRow">'
        + ppr(align="center", line=TIGHT_LINE, before=20, after=20, first=0,
              keep_next=True, widow=False)
        + rpr(cn=CN_SANS, latin=LATIN, sz=SZ_WU, bold=True)
        + '<w:tcPr>'
          '<w:tcBorders>'
          f'<w:bottom w:val="single" w:sz="6" w:space="0" w:color="{BLACK}"/>'
          '</w:tcBorders>'
        + shd
        + '<w:vAlign w:val="center"/>'
          '</w:tcPr>'
          '</w:tblStylePr>'
          '</w:style>')


def table_normal_style_xml() -> str:
    return (
        '<w:style w:type="table" w:styleId="TableNormal">'
        '<w:name w:val="Normal Table"/>'
        '<w:uiPriority w:val="99"/>'
        + ppr(align="left", line=TIGHT_LINE, before=0, after=0, first=0,
              widow=False)
        + rpr(cn=CN_SERIF, latin=LATIN, sz=SZ_WU)
        + '<w:tblPr>'
          '<w:tblInd w:w="0" w:type="dxa"/>'
          '<w:tblCellMar>'
          '<w:top w:w="60" w:type="dxa"/><w:left w:w="108" w:type="dxa"/>'
          '<w:bottom w:w="60" w:type="dxa"/><w:right w:w="108" w:type="dxa"/>'
          '</w:tblCellMar>'
          '</w:tblPr>'
          '</w:style>')


# ---------------------------------------------------------------- styles.xml


STYLE_RE_TPL = r'<w:style\b[^>]*?w:styleId="%s"\s*>.*?</w:style>'


def find_style(xml: str, sid: str):
    return re.search(STYLE_RE_TPL % re.escape(sid), xml, re.S)


def patch_style_block(block: str, pp: str, rp: str) -> str:
    """删掉旧的 pPr / rPr（含主题色、主题字体），换成新的。"""
    # 只处理顶层 pPr/rPr —— 被管理的段落 / 字符样式里不会有嵌套结构
    block = re.sub(r"<w:pPr\s*/>", "", block)
    block = re.sub(r"<w:rPr\s*/>", "", block)
    block = re.sub(r"<w:pPr>.*?</w:pPr>", "", block, flags=re.S)
    block = re.sub(r"<w:rPr>.*?</w:rPr>", "", block, flags=re.S)
    # 让被 pandoc 母版标成半隐藏的标题样式在 Word 样式面板里可见
    block = re.sub(r"<w:semiHidden\s*/>", "", block)
    block = re.sub(r"<w:unhideWhenUsed\s*/>", "", block)
    return block[: block.rfind("</w:style>")] + pp + rp + "</w:style>"


def rewrite_styles(xml: str, preset: str) -> tuple:
    specs = build_styles(preset)
    specs.update(build_extra_styles(preset))

    patched, created = 0, 0
    for sid, (pp, rp) in specs.items():
        m = find_style(xml, sid)
        if m:
            xml = xml[:m.start()] + patch_style_block(m.group(0), pp, rp) \
                  + xml[m.end():]
            patched += 1
        else:
            name, stype, based = NEW_STYLES.get(sid, (sid, "paragraph",
                                                      "Normal"))
            xml = xml.replace("</w:styles>",
                              new_style_xml(sid, name, stype, based, pp, rp)
                              + "</w:styles>")
            created += 1

    # 表格样式整体替换：Table = 无底纹三线表（默认）；
    # TableFilled = 表头带浅灰底纹的备用变体
    blocks = [
        ("TableNormal", table_normal_style_xml()),
        ("Table", table_style_xml(preset)),
        ("TableFilled", table_style_xml(preset, sid="TableFilled",
                                        default=False,
                                        head_fill=TABLE_HEAD_FILL)),
    ]
    for sid, block in blocks:
        m = find_style(xml, sid)
        if m:
            xml = xml[:m.start()] + block + xml[m.end():]
            patched += 1
        else:
            xml = xml.replace("</w:styles>", block + "</w:styles>")
            created += 1

    # docDefaults：兜底也必须是黑色宋体小四
    dd_rpr = ("<w:rPrDefault><w:rPr>"
              + rfonts(CN_SERIF, LATIN)
              + f'<w:color w:val="{BLACK}"/>'
                f'<w:sz w:val="{SZ_XSI}"/><w:szCs w:val="{SZ_XSI}"/>'
                '<w:lang w:val="en-US" w:eastAsia="zh-CN" w:bidi="ar-SA"/>'
                "</w:rPr></w:rPrDefault>")
    dd_ppr = ("<w:pPrDefault><w:pPr>"
              '<w:widowControl/>'
              f'<w:spacing w:before="0" w:after="0" w:line="{BODY_LINE}" '
              'w:lineRule="auto"/>'
              "</w:pPr></w:pPrDefault>")
    xml = re.sub(r"<w:rPrDefault>.*?</w:rPrDefault>", lambda _: dd_rpr, xml,
                 count=1, flags=re.S)
    xml = re.sub(r"<w:pPrDefault>.*?</w:pPrDefault>", lambda _: dd_ppr, xml,
                 count=1, flags=re.S)

    # 保险：全表清掉残留的主题色/主题字体属性
    xml = re.sub(r'\s+w:themeColor="[^"]*"', "", xml)
    xml = re.sub(r'\s+w:themeShade="[^"]*"', "", xml)
    xml = re.sub(r'\s+w:themeTint="[^"]*"', "", xml)
    xml = re.sub(r'\s+w:(ascii|hAnsi|eastAsia|cs)Theme="[^"]*"', "", xml)
    return xml, patched, created


# ---------------------------------------------------------------- 页眉页脚


HDR_NS = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/'
          '2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/'
          '2006/relationships"')


def field_run(instr: str, placeholder: str = " ") -> str:
    """一段完整的 Word 域：begin / instrText / separate / 结果 / end。"""
    r = rpr(cn=CN_SERIF, latin=LATIN, sz=SZ_XWU)
    return (f'<w:r>{r}<w:fldChar w:fldCharType="begin"/></w:r>'
            f'<w:r>{r}<w:instrText xml:space="preserve">{esc(instr)}'
            f'</w:instrText></w:r>'
            f'<w:r>{r}<w:fldChar w:fldCharType="separate"/></w:r>'
            f'<w:r>{r}<w:t xml:space="preserve">{esc(placeholder)}</w:t></w:r>'
            f'<w:r>{r}<w:fldChar w:fldCharType="end"/></w:r>')


def title_run() -> str:
    r = rpr(cn=CN_SERIF, latin=LATIN, sz=SZ_XWU, rstyle="PEDocTitle")
    return (f'<w:r>{r}<w:t xml:space="preserve">{TITLE_PLACEHOLDER}'
            f'</w:t></w:r>')


def plain_run(text: str) -> str:
    r = rpr(cn=CN_SERIF, latin=LATIN, sz=SZ_XWU)
    return f'<w:r>{r}<w:t xml:space="preserve">{esc(text)}</w:t></w:r>'


def tab_run(n: int = 1) -> str:
    r = rpr(cn=CN_SERIF, latin=LATIN, sz=SZ_XWU)
    return f'<w:r>{r}{"<w:tab/>" * n}</w:r>'


# 页眉「当前标题」域。**必须用数字形式 `STYLEREF 2`，不能用样式名。**
#
# 写成 STYLEREF "Heading 2" 时，中文版 Word 解析不到——它认的是本地化名
# 「标题 2」——页眉直接排出「错误!使用"开始"选项卡将 Heading 2 应用于…」。
# 反过来写成 "标题 2" 则 LibreOffice 解析不到。实测四种写法：
#
#   STYLEREF "Heading 2"   Word ✗   LO ✓
#   STYLEREF "标题 2"       Word ✓   LO ✗
#   STYLEREF Heading2      Word ✗   LO ✓
#   STYLEREF 2             Word ✓   LO ✓   ← 只有数字形式两侧通吃
#
# 数字是内置标题级别，与界面语言无关，故只此一种可用。
STYLEREF_HEAD = ' STYLEREF {level} \\* MERGEFORMAT '


def header_xml(preset: str, front: bool) -> str:
    """front=True 生成前置节（目录）页眉：仅横线 + 文档标题。"""
    P = PRESETS[preset]
    if front:
        pp = ('<w:pPr><w:pStyle w:val="Header"/>'
              '<w:jc w:val="center"/></w:pPr>')
        body = pp + title_run()
    elif P["header_layout"] == "chapter_center":
        pp = ('<w:pPr><w:pStyle w:val="Header"/>'
              '<w:jc w:val="center"/></w:pPr>')
        body = pp + field_run(STYLEREF_HEAD.format(level=1))
    else:
        pp = '<w:pPr><w:pStyle w:val="Header"/></w:pPr>'
        body = (pp + title_run() + tab_run(2)
                + field_run(STYLEREF_HEAD.format(level=1)))
    return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            f'<w:hdr {HDR_NS}><w:p>{body}</w:p></w:hdr>')


def footer_xml(preset: str, total: bool = False) -> str:
    pp = ('<w:pPr><w:pStyle w:val="Footer"/>'
          '<w:jc w:val="center"/></w:pPr>')
    if total:
        # 共 M 页用 SECTIONPAGES 而不是 NUMPAGES，理由见
        # docx-postprocess.py 的 footer_total_xml()
        body = (pp + plain_run("第 ") + field_run(" PAGE \\* MERGEFORMAT ", "1")
                + plain_run(" 页  共 ")
                + field_run(" SECTIONPAGES \\* MERGEFORMAT ", "1")
                + plain_run(" 页"))
    elif PRESETS[preset]["footer_fmt"] == "dash":
        body = (pp + plain_run("- ")
                + field_run(" PAGE \\* MERGEFORMAT ", "1") + plain_run(" -"))
    else:
        body = pp + field_run(" PAGE \\* MERGEFORMAT ", "1")
    return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            f'<w:ftr {HDR_NS}><w:p>{body}</w:p></w:ftr>')


# ---------------------------------------------------------------- sectPr


def has_hf(preset: str) -> bool:
    """该预设是否需要页眉页脚部件。brief 无页眉无页脚无页码。"""
    return PRESETS[preset]["header_layout"] != "none"


def sect_pr_xml(preset: str) -> str:
    """正文节 sectPr（元素顺序严格按 CT_SectPr）。"""
    top, bottom, left, right = margins(preset)
    if has_hf(preset):
        refs = (f'<w:headerReference w:type="default" r:id="{REL_HDR1}"/>'
                f'<w:footerReference w:type="default" r:id="{REL_FTR1}"/>')
        pgnum = '<w:pgNumType w:fmt="decimal" w:start="1"/>'
    else:
        refs, pgnum = "", ""
    return (
        "<w:sectPr>" + refs
        + '<w:footnotePr><w:numRestart w:val="eachSect"/></w:footnotePr>'
        + f'<w:pgSz w:w="{PG_W}" w:h="{PG_H}"/>'
        + f'<w:pgMar w:top="{top}" w:right="{right}" '
          f'w:bottom="{bottom}" w:left="{left}" '
          f'w:header="{HDR_DIST}" w:footer="{FTR_DIST}" w:gutter="0"/>'
        + pgnum
        + '<w:cols w:space="425"/>'
        + "</w:sectPr>")


# ---------------------------------------------------------------- 打包


REL_TYPE_HDR = ("http://schemas.openxmlformats.org/officeDocument/2006/"
                "relationships/header")
REL_TYPE_FTR = ("http://schemas.openxmlformats.org/officeDocument/2006/"
                "relationships/footer")
CT_HDR = ("application/vnd.openxmlformats-officedocument.wordprocessingml."
          "header+xml")
CT_FTR = ("application/vnd.openxmlformats-officedocument.wordprocessingml."
          "footer+xml")


def build(style: str, skill_dir: Path) -> Path:
    if style not in PRESETS:
        raise SystemExit(f"未知预设: {style}（可选: gb / report / all）")

    assets = skill_dir / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    out = assets / f"reference-{style}.docx"

    pandoc = shutil.which("pandoc") or "/opt/homebrew/bin/pandoc"
    proc = subprocess.run([pandoc, "--print-default-data-file",
                           "reference.docx"], stdout=subprocess.PIPE,
                          check=True)
    import io
    zin = zipfile.ZipFile(io.BytesIO(proc.stdout))
    items = {n: zin.read(n) for n in zin.namelist()}
    order = list(zin.namelist())
    zin.close()

    # ---- styles.xml ----
    styles, patched, created = rewrite_styles(
        items["word/styles.xml"].decode("utf-8"), style)
    items["word/styles.xml"] = styles.encode("utf-8")

    # ---- document.xml：改写 sectPr ----
    doc = items["word/document.xml"].decode("utf-8")
    new_sect = sect_pr_xml(style)
    if re.search(r"<w:sectPr\b[^>]*/>", doc):
        doc = re.sub(r"<w:sectPr\b[^>]*/>", lambda _: new_sect, doc, count=1)
    else:
        doc = re.sub(r"<w:sectPr\b.*?</w:sectPr>", lambda _: new_sect, doc,
                     count=1, flags=re.S)
    items["word/document.xml"] = doc.encode("utf-8")

    # ---- 页眉页脚部件 ----
    # brief 一个都不生成：既然 sectPr 不引用它们，多打进包里只会让 Word 的
    # 「页眉页脚」面板凭空多出可选项，反倒诱人误用。
    if has_hf(style):
        parts = {
            "word/header1.xml": header_xml(style, front=False),
            "word/header2.xml": header_xml(style, front=True),
            "word/footer1.xml": footer_xml(style),
            "word/footer2.xml": footer_xml(style),
        }
        for name, xml in parts.items():
            items[name] = xml.encode("utf-8")
            if name not in order:
                order.append(name)

        # ---- rels ----
        rels = items["word/_rels/document.xml.rels"].decode("utf-8")
        add = []
        for rid, target, rtype in ((REL_HDR1, "header1.xml", REL_TYPE_HDR),
                                   (REL_FTR1, "footer1.xml", REL_TYPE_FTR),
                                   (REL_HDR2, "header2.xml", REL_TYPE_HDR),
                                   (REL_FTR2, "footer2.xml", REL_TYPE_FTR)):
            if f'Id="{rid}"' not in rels:
                add.append(f'<Relationship Id="{rid}" Type="{rtype}" '
                           f'Target="{target}"/>')
        rels = rels.replace("</Relationships>",
                            "".join(add) + "</Relationships>")
        items["word/_rels/document.xml.rels"] = rels.encode("utf-8")

        # ---- [Content_Types].xml ----
        ct = items["[Content_Types].xml"].decode("utf-8")
        add = []
        for part, ctype in (("/word/header1.xml", CT_HDR),
                            ("/word/header2.xml", CT_HDR),
                            ("/word/footer1.xml", CT_FTR),
                            ("/word/footer2.xml", CT_FTR)):
            if f'PartName="{part}"' not in ct:
                add.append(f'<Override PartName="{part}" '
                           f'ContentType="{ctype}"/>')
        ct = ct.replace("</Types>", "".join(add) + "</Types>")
        items["[Content_Types].xml"] = ct.encode("utf-8")

    # ---- settings.xml：Word 打开时自动更新域（目录 / 页码 / STYLEREF）----
    st = items["word/settings.xml"].decode("utf-8")
    if "<w:updateFields" not in st:
        st = st.replace("<w:footnotePr>",
                        '<w:updateFields w:val="true"/><w:footnotePr>', 1)
    items["word/settings.xml"] = st.encode("utf-8")

    # ---- 打包 ----
    if out.exists():
        out.unlink()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for name in order:
            zf.writestr(name, items[name])

    size = out.stat().st_size // 1024
    hf = "页眉页脚 4 个部件" if has_hf(style) else "无页眉页脚"
    print(f"✓ {out.name}  ({size} KB；{patched} 个样式改写，"
          f"{created} 个新建；A4 + {hf})")
    return out


def main():
    skill_dir = Path(__file__).resolve().parent.parent
    target = sys.argv[1] if len(sys.argv) > 1 else "all"
    styles = list(PRESETS) if target == "all" else [target]
    for s in styles:
        build(s, skill_dir)


if __name__ == "__main__":
    main()
