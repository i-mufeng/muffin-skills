#!/usr/bin/env python3
"""
paper-export :: docx 最终修补

pandoc 产出的 docx 只有一个节，页码从封面连着数，目录标题是英文，
表格继承正文行距。本脚本在 pandoc 之后跑，完成：

  1. 封面标记段落 → 封面节分节符（A4、无页眉页脚、页码不显示）
  2. 目录之后插入前置节分节符（页码大写罗马 I/II/III，引用 header2/footer2）
  3. 文档末尾 body sectPr → 正文节（引用 header1/footer1，页码阿拉伯从 1 重排）
  4. 标题前独立分页段 → 标题自身 pageBreakBefore，避免偶发空白页
  5. 页眉标题占位符 → 实际标题（按显示宽度截断到 30）
  6. --footer-total 1 时页脚改成「第 N 页  共 M 页」
  7. 目录标题兜底改成「目　录」
  8. 表格三线表化：居中、去竖线、表头重复、单元格五号 1.0 行距不缩进
  9. 评审语义标签着色：待确认 / 需补充 / 建议方案
 10. settings.xml updateFields=true；重算 [Content_Types].xml 与 rels

幂等：同参数重复执行结果一致。

用法:
    python3 docx-postprocess.py <out.docx> --style report|gb \\
        --title "文档标题" [--toc 0|1] [--footer-total 0|1]
"""
import argparse
import copy
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

# ---------------------------------------------------------------- 常量

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG_REL = "http://schemas.openxmlformats.org/package/2006/relationships"
CT_NS = "http://schemas.openxmlformats.org/package/2006/content-types"
DC = "http://purl.org/dc/elements/1.1/"

REL_TYPE_HDR = R + "/header"
REL_TYPE_FTR = R + "/footer"
CT_HDR = ("application/vnd.openxmlformats-officedocument.wordprocessingml."
          "header+xml")
CT_FTR = ("application/vnd.openxmlformats-officedocument.wordprocessingml."
          "footer+xml")

REL_HDR1 = "rIdPEHeader1"
REL_FTR1 = "rIdPEFooter1"
REL_HDR2 = "rIdPEHeader2"
REL_FTR2 = "rIdPEFooter2"

HDR_PARTS = {
    REL_HDR1: ("word/header1.xml", REL_TYPE_HDR, CT_HDR),
    REL_FTR1: ("word/footer1.xml", REL_TYPE_FTR, CT_FTR),
    REL_HDR2: ("word/header2.xml", REL_TYPE_HDR, CT_HDR),
    REL_FTR2: ("word/footer2.xml", REL_TYPE_FTR, CT_FTR),
}

# 行间分界线：只是阅读辅助线，必须比顶/底线细得多、浅得多，
# 否则整张表退化成网格，比不画还吵。与 LaTeX 侧的 \perowrule 保持一致。
ROW_RULE_COLOR = "D0D0D0"
ROW_RULE_SZ = "2"          # 八分之一磅 → 2 = 0.25pt
LINE_UNITS = 80            # A4 版心在五号字下一行约容纳 80 个显示宽度单位

TITLE_PLACEHOLDER = "@@PE_DOC_TITLE@@"
TOC_TITLE = "目　录"            # 目 + U+3000 + 录

PG_W, PG_H = 11906, 16838
MARGIN = 1440
HDR_DIST, FTR_DIST = 850, 992
# 每个预设的页边距（twips）：top / bottom / left / right
# brief 走 GB/T 9704 公文版心：天头 37mm、地脚 35mm、左 28mm、右 26mm，
# 且不装订成册，左边不再额外留装订线。
PAGE_MARGIN = {
    "report": (MARGIN, MARGIN, 1701, MARGIN),
    "modern": (MARGIN, MARGIN, 1701, MARGIN),   # 版面同 report，只换字体
    "gb":     (MARGIN, MARGIN, 1797, MARGIN),
    "brief":  (2098, 1984, 1587, 1474),
}

CN_SERIF, CN_SANS, LATIN = "宋体", "黑体", "Times New Roman"
CN_FANG = "仿宋"
PH_REG = "Alibaba PuHuiTi 3.0 55 Regular"
PH_BOLD = "Alibaba PuHuiTi 3.0 85 Bold"
SANS_LATIN = "Arial"
SZ_WU, SZ_XWU, SZ_XSI = 21, 18, 24
# 表格单元格字号：正文小四的预设用五号，brief 正文是三号，五号落差太大，用小四
TABLE_CELL_SZ = {"report": SZ_WU, "modern": SZ_WU, "gb": SZ_WU, "brief": SZ_XSI}

# 每个预设的（正文中文字体、表头中文字体、旧拉丁占位）。普通英文和数字实际
# 跟随正文或表头中文字体；第三项暂留以保持现有调用结构。
FONTS = {
    "report": (CN_SERIF, CN_SANS, LATIN),
    "modern": (PH_REG, PH_BOLD, SANS_LATIN),
    "gb":     (CN_SERIF, CN_SANS, LATIN),
    "brief":  (CN_FANG, CN_SANS, LATIN),
}
BLACK = "000000"
SEMANTIC_MARKERS = {
    "【待确认】": ("C00000", "FCE8E6"),
    "【需补充】": ("C00000", "FCE8E6"),
    "【建议方案】": ("1F4E78", "DDEBF7"),
    "【对抗意见】": ("C00000", "FCE8E6"),
    "【建议暂缓】": ("C00000", "FCE8E6"),
    "【建议剔除】": ("C00000", "FCE8E6"),
}

PPR_ORDER = [
    "pStyle", "keepNext", "keepLines", "pageBreakBefore", "framePr",
    "widowControl", "numPr", "suppressLineNumbers", "pBdr", "shd", "tabs",
    "suppressAutoHyphens", "kinsoku", "wordWrap", "overflowPunct",
    "topLinePunct", "autoSpaceDE", "autoSpaceDN", "bidi", "adjustRightInd",
    "snapToGrid", "spacing", "ind", "contextualSpacing", "mirrorIndents",
    "suppressOverlap", "jc", "textDirection", "textAlignment",
    "textboxTightWrap", "outlineLvl", "divId", "cnfStyle", "rPr", "sectPr",
    "pPrChange",
]
RPR_ORDER = [
    "rStyle", "rFonts", "b", "bCs", "i", "iCs", "caps", "smallCaps", "strike",
    "dstrike", "outline", "shadow", "emboss", "imprint", "noProof",
    "snapToGrid", "vanish", "webHidden", "color", "spacing", "w", "kern",
    "position", "sz", "szCs", "highlight", "u", "effect", "bdr", "shd",
    "fitText", "vertAlign", "rtl", "cs", "em", "lang", "eastAsianLayout",
    "specVanish", "oMath",
]
TBLPR_ORDER = [
    "tblStyle", "tblpPr", "tblOverlap", "bidiVisual", "tblStyleRowBandSize",
    "tblStyleColBandSize", "tblW", "jc", "tblCellSpacing", "tblInd",
    "tblBorders", "shd", "tblLayout", "tblCellMar", "tblLook", "tblCaption",
    "tblDescription",
]
TCPR_ORDER = [
    "cnfStyle", "tcW", "gridSpan", "hMerge", "vMerge", "tcBorders", "shd",
    "noWrap", "tcMar", "textDirection", "tcFitText", "vAlign", "hideMark",
]


def w(tag):
    return f"{{{W}}}{tag}"


def r_(tag):
    return f"{{{R}}}{tag}"


def local(el):
    t = el.tag
    return t.split("}", 1)[1] if "}" in t else t


class Fail(Exception):
    pass


# ---------------------------------------------------------------- XML 工具


def register_ns(raw: bytes):
    """按文档根标签上的声明注册前缀，避免 ET 写出 ns0: 之类的前缀。"""
    head = raw[:4000].decode("utf-8", "replace")
    for prefix, uri in re.findall(r'xmlns:([A-Za-z0-9_]+)="([^"]+)"', head):
        try:
            ET.register_namespace(prefix, uri)
        except ValueError:
            pass


def frag(xml: str):
    """把一段 OpenXML 片段解析成元素列表。"""
    wrapper = (f'<root xmlns:w="{W}" xmlns:r="{R}">{xml}</root>')
    return list(ET.fromstring(wrapper))


def frag1(xml: str):
    return frag(xml)[0]


def reorder(parent, order):
    """按 OOXML schema 的元素顺序重排子元素（顺序不对 Word 会报文档损坏）。"""
    idx = {n: i for i, n in enumerate(order)}
    kids = list(parent)
    kids.sort(key=lambda e: idx.get(local(e), len(order)))
    for k in list(parent):
        parent.remove(k)
    for k in kids:
        parent.append(k)


def sub_get(parent, tag, order):
    el = parent.find(w(tag))
    if el is None:
        el = ET.SubElement(parent, w(tag))
        reorder(parent, order)
    return el


def get_ppr(p):
    ppr = p.find(w("pPr"))
    if ppr is None:
        ppr = ET.Element(w("pPr"))
        p.insert(0, ppr)
    return ppr


def get_rpr(run):
    rpr = run.find(w("rPr"))
    if rpr is None:
        rpr = ET.Element(w("rPr"))
        run.insert(0, rpr)
    return rpr


def set_el(parent, tag, order, **attrs):
    el = parent.find(w(tag))
    if el is None:
        el = ET.SubElement(parent, w(tag))
    for k, v in attrs.items():
        el.set(w(k), str(v))
    reorder(parent, order)
    return el


def drop(parent, tag):
    el = parent.find(w(tag))
    if el is not None:
        parent.remove(el)


def disp_width(s: str) -> int:
    n = 0
    for ch in s:
        c = ord(ch)
        if (0x1100 <= c <= 0x115F or 0x2E80 <= c <= 0xA4CF
                or 0xAC00 <= c <= 0xD7A3 or 0xF900 <= c <= 0xFAFF
                or 0xFE30 <= c <= 0xFE4F or 0xFF00 <= c <= 0xFF60
                or 0xFFE0 <= c <= 0xFFE6):
            n += 2
        else:
            n += 1
    return n


def truncate(s: str, limit: int = 30) -> str:
    if disp_width(s) <= limit:
        return s
    out, n = [], 0
    for ch in s:
        cw = disp_width(ch)
        if n + cw > limit - 1:
            break
        out.append(ch)
        n += cw
    return "".join(out) + "…"


# ---------------------------------------------------------------- sectPr


def sect_pr(style: str, kind: str) -> str:
    """kind: cover / front / body"""
    top, bottom, left, right = PAGE_MARGIN[style]
    refs, pgnum = "", ""
    if style == "brief":
        # 简报全文一个节：无页眉页脚、无页码。不引用 header/footer 部件 ——
        # 母版里根本没有生成它们，引用一个不存在的 rId 会让 Word 报文件损坏。
        pgnum = ""
    elif kind == "cover":
        pgnum = '<w:pgNumType w:start="1"/>'
    elif kind == "front":
        refs = (f'<w:headerReference w:type="default" r:id="{REL_HDR2}"/>'
                f'<w:footerReference w:type="default" r:id="{REL_FTR2}"/>')
        pgnum = '<w:pgNumType w:fmt="upperRoman" w:start="1"/>'
    else:
        refs = (f'<w:headerReference w:type="default" r:id="{REL_HDR1}"/>'
                f'<w:footerReference w:type="default" r:id="{REL_FTR1}"/>')
        pgnum = '<w:pgNumType w:fmt="decimal" w:start="1"/>'
    return (
        "<w:sectPr>" + refs
        + '<w:footnotePr><w:numRestart w:val="eachSect"/></w:footnotePr>'
        + '<w:type w:val="nextPage"/>'
        + f'<w:pgSz w:w="{PG_W}" w:h="{PG_H}"/>'
        + f'<w:pgMar w:top="{top}" w:right="{right}" w:bottom="{bottom}" '
          f'w:left="{left}" w:header="{HDR_DIST}" w:footer="{FTR_DIST}" '
          'w:gutter="0"/>'
        + pgnum
        + '<w:cols w:space="425"/>'
        + "</w:sectPr>")


def make_break_para(style: str, kind: str, pstyle: str):
    p = ET.Element(w("p"))
    ppr = ET.SubElement(p, w("pPr"))
    ET.SubElement(ppr, w("pStyle")).set(w("val"), pstyle)
    ppr.append(frag1(sect_pr(style, kind)))
    reorder(ppr, PPR_ORDER)
    return p


# ---------------------------------------------------------------- 各步骤


def find_pstyle(p) -> str:
    ppr = p.find(w("pPr"))
    if ppr is None:
        return ""
    ps = ppr.find(w("pStyle"))
    return ps.get(w("val"), "") if ps is not None else ""


def find_cover_idx(body):
    for i, el in enumerate(list(body)):
        if local(el) == "p" and find_pstyle(el) in ("PESectCover",
                                                    "PESectCoverBreak"):
            return i
    return None


def find_toc_idx(body):
    for i, el in enumerate(list(body)):
        if is_toc_sdt(el):
            return i
    return None


def step_reorder(body) -> bool:
    """pandoc 把目录 sdt 写在所有 body 块之前，封面（filter 插入的第一个块）
    因此落到目录后面。这里把目录整体挪到封面标记之后。"""
    cover_i = find_cover_idx(body)
    toc_i = find_toc_idx(body)
    if cover_i is None or toc_i is None or toc_i > cover_i:
        return False
    sdt = body[toc_i]
    body.remove(sdt)
    body.insert(cover_i, sdt)   # 删除后封面标记退到 cover_i-1，这里正好紧随其后
    return True


def step_cover(body, style: str) -> bool:
    """封面标记段落 → 封面节分节符。幂等：认标记样式，也认已生成的分节段落。"""
    for i, el in enumerate(list(body)):
        if local(el) != "p":
            continue
        if find_pstyle(el) in ("PESectCover", "PESectCoverBreak"):
            body.remove(el)
            body.insert(i, make_break_para(style, "cover", "PESectCoverBreak"))
            return True
    return False


def is_toc_sdt(el) -> bool:
    if local(el) != "sdt":
        return False
    for g in el.iter(w("docPartGallery")):
        if g.get(w("val")) == "Table of Contents":
            return True
    return False


def step_toc(body, style: str, want_toc: bool):
    """修目录标题文字；在目录之后插入前置节分节符。"""
    sdt_idx = None
    for i, el in enumerate(list(body)):
        if is_toc_sdt(el):
            sdt_idx = i
            break
    if sdt_idx is None:
        return False, False

    # 目录标题兜底成「目　录」
    fixed_title = False
    sdt = body[sdt_idx]
    for p in sdt.iter(w("p")):
        if find_pstyle(p) == "TOCHeading":
            runs = p.findall(w("r"))
            texts = [t for run in runs for t in run.findall(w("t"))]
            if texts:
                texts[0].text = TOC_TITLE
                texts[0].set(
                    "{http://www.w3.org/XML/1998/namespace}space", "preserve")
                for t in texts[1:]:
                    t.text = ""
                fixed_title = True
            break

    if not want_toc:
        return fixed_title, False

    nxt = body[sdt_idx + 1] if sdt_idx + 1 < len(body) else None
    if nxt is not None and local(nxt) == "p" \
            and find_pstyle(nxt) == "PESectFront":
        body.remove(nxt)
        body.insert(sdt_idx + 1,
                    make_break_para(style, "front", "PESectFront"))
    else:
        body.insert(sdt_idx + 1,
                    make_break_para(style, "front", "PESectFront"))
    return fixed_title, True


def step_body_sect(body, style: str):
    """文档末尾的 body sectPr 换成正文节。"""
    old = None
    for el in list(body):
        if local(el) == "sectPr":
            old = el
    if old is not None:
        body.remove(old)
    body.append(frag1(sect_pr(style, "body")))


def normalize_heading_page_breaks(body) -> int:
    """把标题前的独立分页段移到标题 pPr，避免分页段独占空白页。"""
    changed = 0
    children = list(body)
    for idx in range(len(children) - 2, -1, -1):
        para = children[idx]
        if para.tag != w("p"):
            continue
        text = "".join(t.text or "" for t in para.findall(f".//{w('t')}"))
        breaks = para.findall(f".//{w('br')}")
        if text or len(breaks) != 1 or breaks[0].get(w("type")) != "page":
            continue

        next_idx = idx + 1
        while next_idx < len(children) and local(children[next_idx]) in (
                "bookmarkStart", "bookmarkEnd", "proofErr"):
            next_idx += 1
        if next_idx >= len(children):
            continue
        nxt = children[next_idx]
        if nxt.tag != w("p") or not find_pstyle(nxt).lower().startswith("heading"):
            continue
        set_el(get_ppr(nxt), "pageBreakBefore", PPR_ORDER)
        body.remove(para)
        changed += 1
    return changed


# ---------------------------------------------------------------- 表格


def table_is_dense(tbl, line_units: int = LINE_UNITS) -> bool:
    """表里是否存在会折行的单元格。

    判据与 assets/tablefit.lua 的 needs_rules 一致：
    单元格显示宽度 > 每行可容纳宽度 × 该列宽度占比。
    列宽取 tblGrid（pandoc 按 tablefit.lua 算好的比例写进去的）。
    """
    grid = tbl.find(w("tblGrid"))
    cols = []
    if grid is not None:
        for gc in grid.findall(w("gridCol")):
            try:
                cols.append(int(gc.get(w("w"), "0")))
            except ValueError:
                cols.append(0)
    total = sum(cols)
    ncols = len(cols) or 1

    for ri, tr in enumerate(tbl.findall(w("tr"))):
        if ri == 0:
            continue                      # 表头不参与判定
        ci = 0
        for tc in tr.findall(w("tc")):
            span = 1
            tcpr = tc.find(w("tcPr"))
            if tcpr is not None:
                gs = tcpr.find(w("gridSpan"))
                if gs is not None:
                    try:
                        span = max(1, int(gs.get(w("val"), "1")))
                    except ValueError:
                        span = 1
            if total > 0 and ci < len(cols):
                frac = sum(cols[ci:ci + span]) / total
            else:
                frac = span / ncols
            text = "".join(t.text or "" for t in tc.iter(w("t")))
            if disp_width(text) > line_units * frac:
                return True
            ci += span
    return False


def style_table(tbl, rule: str = "auto", style: str = "report"):
    # 行间分界线：短词表格用纯三线表最清爽，长文本表格不加则相邻行糊成一片
    if rule == "grid":
        dense = True
    elif rule == "three":
        dense = False
    else:
        dense = table_is_dense(tbl)

    # ---- tblPr ----
    tblpr = tbl.find(w("tblPr"))
    if tblpr is None:
        tblpr = ET.Element(w("tblPr"))
        tbl.insert(0, tblpr)
    set_el(tblpr, "jc", TBLPR_ORDER, val="center")
    set_el(tblpr, "tblInd", TBLPR_ORDER, w="0", type="dxa")
    drop(tblpr, "tblBorders")
    tblpr.append(frag1(
        "<w:tblBorders>"
        f'<w:top w:val="single" w:sz="12" w:space="0" w:color="{BLACK}"/>'
        '<w:left w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
        f'<w:bottom w:val="single" w:sz="12" w:space="0" w:color="{BLACK}"/>'
        '<w:right w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
        + (f'<w:insideH w:val="single" w:sz="{ROW_RULE_SZ}" w:space="0" '
           f'w:color="{ROW_RULE_COLOR}"/>' if dense else
           '<w:insideH w:val="none" w:sz="0" w:space="0" w:color="auto"/>')
        + '<w:insideV w:val="none" w:sz="0" w:space="0" w:color="auto"/>'
        "</w:tblBorders>"))
    drop(tblpr, "tblCellMar")
    tblpr.append(frag1(
        "<w:tblCellMar>"
        '<w:top w:w="60" w:type="dxa"/><w:left w:w="108" w:type="dxa"/>'
        '<w:bottom w:w="60" w:type="dxa"/><w:right w:w="108" w:type="dxa"/>'
        "</w:tblCellMar>"))
    reorder(tblpr, TBLPR_ORDER)

    rows = tbl.findall(w("tr"))
    for ri, tr in enumerate(rows):
        head = ri == 0
        if head:
            trpr = tr.find(w("trPr"))
            if trpr is None:
                trpr = ET.Element(w("trPr"))
                tr.insert(0, trpr)
            if trpr.find(w("tblHeader")) is None:
                ET.SubElement(trpr, w("tblHeader")).set(w("val"), "true")
        for tc in tr.findall(w("tc")):
            tcpr = tc.find(w("tcPr"))
            if tcpr is None:
                tcpr = ET.Element(w("tcPr"))
                tc.insert(0, tcpr)
            if head:
                drop(tcpr, "tcBorders")
                tcpr.append(frag1(
                    "<w:tcBorders>"
                    f'<w:bottom w:val="single" w:sz="6" w:space="0" '
                    f'w:color="{BLACK}"/>'
                    "</w:tcBorders>"))
                set_el(tcpr, "vAlign", TCPR_ORDER, val="center")
            else:
                set_el(tcpr, "vAlign", TCPR_ORDER, val="top")
            reorder(tcpr, TCPR_ORDER)
            for p in tc.iter(w("p")):
                style_table_para(p, head, style)
    return dense


def style_table_para(p, head: bool, style: str = "report"):
    ppr = get_ppr(p)
    set_el(ppr, "spacing", PPR_ORDER, before="20", after="20",
           line="240", lineRule="auto")
    set_el(ppr, "ind", PPR_ORDER, firstLine="0", firstLineChars="0",
           left="0", leftChars="0", right="0", rightChars="0")
    set_el(ppr, "snapToGrid", PPR_ORDER, val="0")
    if head:
        set_el(ppr, "jc", PPR_ORDER, val="center")
        set_el(ppr, "keepNext", PPR_ORDER)
    reorder(ppr, PPR_ORDER)
    # 单元格字体跟随预设：brief 通篇仿宋、modern 通篇普惠体，
    # 表格里再换回宋体会在同一页出现两套字，很显眼
    cell_cn, head_cn, _latin = FONTS.get(style, FONTS["report"])
    sz = str(TABLE_CELL_SZ.get(style, SZ_WU))
    for run in p.findall(w("r")):
        rpr = get_rpr(run)
        fonts = rpr.find(w("rFonts"))
        if fonts is None:
            fonts = ET.SubElement(rpr, w("rFonts"))
        run_font = head_cn if head else cell_cn
        fonts.set(w("ascii"), run_font)
        fonts.set(w("hAnsi"), run_font)
        fonts.set(w("cs"), run_font)
        fonts.set(w("eastAsia"), run_font)
        fonts.set(w("hint"), "eastAsia")
        set_el(rpr, "color", RPR_ORDER, val=BLACK)
        set_el(rpr, "sz", RPR_ORDER, val=sz)
        set_el(rpr, "szCs", RPR_ORDER, val=sz)
        if head:
            set_el(rpr, "b", RPR_ORDER)
            set_el(rpr, "bCs", RPR_ORDER)
        reorder(rpr, RPR_ORDER)


# ---------------------------------------------------------------- 页眉页脚


def patch_header_title(raw: bytes, title: str) -> bytes:
    """把页眉里的标题占位符 / PEDocTitle 运行的文字换成实际标题。"""
    register_ns(raw)
    root = ET.fromstring(raw)
    hit = False
    for run in root.iter(w("r")):
        rpr = run.find(w("rPr"))
        marked = False
        if rpr is not None:
            rs = rpr.find(w("rStyle"))
            marked = rs is not None and rs.get(w("val")) == "PEDocTitle"
        ts = run.findall(w("t"))
        if not ts:
            continue
        if marked or any((t.text or "") == TITLE_PLACEHOLDER for t in ts):
            ts[0].text = title
            ts[0].set("{http://www.w3.org/XML/1998/namespace}space",
                      "preserve")
            for t in ts[1:]:
                t.text = ""
            hit = True
    if not hit:
        return raw
    return ET.tostring(root, encoding="UTF-8", xml_declaration=True)


def patch_header_level(raw: bytes, level: int) -> bytes:
    """把页眉 STYLEREF 域指向的标题级别改成 level（幂等）。

    **域参数必须是数字，不能是样式名。** 中文版 Word 认的是本地化样式名
    「标题 2」，给它 "Heading 2" 会解析失败，页眉排出
    「错误!使用"开始"选项卡将 Heading 2 应用于要在此处显示的文字。」；
    反过来给 "标题 2" 又轮到 LibreOffice 解析不到。数字形式 `STYLEREF 2`
    指的是内置标题级别，与界面语言无关，是实测下来唯一两侧都正确的写法。
    """
    s = raw.decode("utf-8")
    # 历史母版里的样式名形式（可能被 XML 转义过），一并归一成数字形式
    s = re.sub(r'STYLEREF\s+(?:&quot;|")\s*Heading\s*\d+\s*(?:&quot;|")',
               f'STYLEREF {level}', s)
    s = re.sub(r'STYLEREF\s+\d+', f'STYLEREF {level}', s)
    return s.encode("utf-8")


def detect_head_level(body, style: str) -> int:
    """与 export.sh 的 HEAD_LEVEL 推断保持一致：
    report/modern 预设下正文里 H1 少于 2 个时（H1 就是文档名），页眉改取 H2。"""
    if style not in ("report", "modern"):
        return 1
    n = 0
    for p in body.iter(w("p")):
        if find_pstyle(p) == "Heading1":
            n += 1
    return 1 if n >= 2 else 2


HF_NS = (f'xmlns:w="{W}" xmlns:r="{R}"')


def _rpr_hf(style: str = "report"):
    body_cn, _head_cn, _latin = FONTS.get(style, FONTS["report"])
    return (f'<w:rPr><w:rFonts w:ascii="{body_cn}" w:hAnsi="{body_cn}" '
            f'w:cs="{body_cn}" w:eastAsia="{body_cn}" w:hint="eastAsia"/>'
            f'<w:color w:val="{BLACK}"/><w:sz w:val="{SZ_XWU}"/>'
            f'<w:szCs w:val="{SZ_XWU}"/></w:rPr>')


def _field(instr, result="1", style="report"):
    rp = _rpr_hf(style)
    return (f'<w:r>{rp}<w:fldChar w:fldCharType="begin"/></w:r>'
            f'<w:r>{rp}<w:instrText xml:space="preserve">{instr}'
            f'</w:instrText></w:r>'
            f'<w:r>{rp}<w:fldChar w:fldCharType="separate"/></w:r>'
            f'<w:r>{rp}<w:t xml:space="preserve">{result}</w:t></w:r>'
            f'<w:r>{rp}<w:fldChar w:fldCharType="end"/></w:r>')


def _text(s, style="report"):
    return (f'<w:r>{_rpr_hf(style)}<w:t xml:space="preserve">{s}</w:t></w:r>')


def footer_total_xml(style: str = "report") -> bytes:
    # 「共 M 页」必须与「第 N 页」同口径。正文节的 PAGE 是从 1 重排的，
    # 而 NUMPAGES 统计的是**整份文档**（含封面节、目录节），两者分母不同：
    # 末页会排出「第 9 页  共 11 页」这种自相矛盾的结果。
    # SECTIONPAGES 只统计当前节，与 PDF 侧 \pageref{LastPage} 的口径一致。
    #
    # 代价：LibreOffice 完全不实现 SECTIONPAGES，soffice 转出的 PDF 会显示
    # 缓存值。页码验收本来就只能以 Word/WPS 为准，见 troubleshooting §4.4/§4.5。
    body = (_text("第 ", style) + _field(" PAGE \\* MERGEFORMAT ", style=style)
            + _text(" 页  共 ", style)
            + _field(" SECTIONPAGES \\* MERGEFORMAT ", style=style)
            + _text(" 页", style))
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            f'<w:ftr {HF_NS}><w:p><w:pPr><w:pStyle w:val="Footer"/>'
            f'<w:jc w:val="center"/></w:pPr>{body}</w:p></w:ftr>'
            ).encode("utf-8")


# ---------------------------------------------------------------- 包级修补


def fix_settings(raw: bytes) -> bytes:
    s = raw.decode("utf-8")
    if "<w:updateFields" in s:
        s = re.sub(r'<w:updateFields[^>]*/>',
                   '<w:updateFields w:val="true"/>', s)
    elif "<w:footnotePr>" in s:
        s = s.replace("<w:footnotePr>",
                      '<w:updateFields w:val="true"/><w:footnotePr>', 1)
    else:
        s = s.replace("</w:settings>",
                      '<w:updateFields w:val="true"/></w:settings>', 1)
    return s.encode("utf-8")


def fix_rels(raw: bytes, present: set) -> bytes:
    s = raw.decode("utf-8")
    ids = re.findall(r'Id="([^"]+)"', s)
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        raise Fail(f"document.xml.rels 中存在重复的 rId: {sorted(dupes)}")
    add = []
    for rid, (target, rtype, _ct) in HDR_PARTS.items():
        if target.split("/")[-1] not in present:
            continue
        if f'Id="{rid}"' in s:
            continue
        add.append(f'<Relationship Id="{rid}" Type="{rtype}" '
                   f'Target="{target.split("/")[-1]}"/>')
    if add:
        s = s.replace("</Relationships>", "".join(add) + "</Relationships>")
    return s.encode("utf-8")


def fix_content_types(raw: bytes, names) -> bytes:
    s = raw.decode("utf-8")
    add = []
    for n in names:
        if re.fullmatch(r"word/header\d+\.xml", n):
            ct = CT_HDR
        elif re.fullmatch(r"word/footer\d+\.xml", n):
            ct = CT_FTR
        else:
            continue
        if f'PartName="/{n}"' not in s:
            add.append(f'<Override PartName="/{n}" ContentType="{ct}"/>')
    if add:
        s = s.replace("</Types>", "".join(add) + "</Types>")
    return s.encode("utf-8")


TOK_STYLE_RE = re.compile(
    r'<w:style\b[^>]*?w:styleId="\w*Tok"\s*>.*?</w:style>', re.S)


def fix_code_colors(raw: bytes):
    """pandoc 会往 styles.xml 里注入 31 个带色的语法高亮字符样式（KeywordTok…）。
    SPEC §3 要求一切文字纯黑，这里把颜色压成黑色，保留粗体/斜体区分。"""
    s = raw.decode("utf-8")
    n = 0

    def blacken(m):
        nonlocal n
        blk = m.group(0)
        new = re.sub(r'<w:color w:val="(?!000000)[0-9A-Fa-f]{6}"\s*/>',
                     '<w:color w:val="000000"/>', blk)
        new = re.sub(r'\s+w:themeColor="[^"]*"', "", new)
        if new != blk:
            n += 1
        return new

    s = TOK_STYLE_RE.sub(blacken, s)
    return s.encode("utf-8"), n


def _apply_marker_style(run, fg: str, bg: str):
    rpr = get_rpr(run)
    set_el(rpr, "b", RPR_ORDER)
    set_el(rpr, "bCs", RPR_ORDER)
    set_el(rpr, "color", RPR_ORDER, val=fg)
    set_el(rpr, "shd", RPR_ORDER, val="clear", color="auto", fill=bg)
    reorder(rpr, RPR_ORDER)


def style_semantic_markers(root) -> int:
    """只给固定评审标签着色；标签与正文同 run 时先安全拆分。"""
    count = 0
    marker_re = re.compile("(" + "|".join(
        re.escape(s) for s in SEMANTIC_MARKERS) + ")")

    for parent in list(root.iter()):
        for idx, run in reversed(list(enumerate(list(parent)))):
            if run.tag != w("r"):
                continue
            texts = run.findall(w("t"))
            other = [el for el in run if el.tag not in (w("rPr"), w("t"))]
            if len(texts) != 1 or other:
                continue
            full_text = texts[0].text or ""
            parts = [p for p in marker_re.split(full_text) if p]
            if not any(p in SEMANTIC_MARKERS for p in parts):
                continue

            replacements = []
            for part in parts:
                new_run = copy.deepcopy(run)
                new_text = new_run.find(w("t"))
                new_text.text = part
                if part[:1].isspace() or part[-1:].isspace():
                    new_text.set("{http://www.w3.org/XML/1998/namespace}space",
                                 "preserve")
                if part in SEMANTIC_MARKERS:
                    fg, bg = SEMANTIC_MARKERS[part]
                    _apply_marker_style(new_run, fg, bg)
                    count += 1
                replacements.append(new_run)

            parent.remove(run)
            for new_run in reversed(replacements):
                parent.insert(idx, new_run)
    return count


def fix_core_props(raw: bytes, title: str) -> bytes:
    s = raw.decode("utf-8")
    esc_title = (title.replace("&", "&amp;").replace("<", "&lt;")
                 .replace(">", "&gt;"))
    if re.search(r"<dc:title>.*?</dc:title>", s, re.S):
        s = re.sub(r"<dc:title>.*?</dc:title>",
                   lambda _: f"<dc:title>{esc_title}</dc:title>", s,
                   count=1, flags=re.S)
    else:
        s = re.sub(r"(<cp:coreProperties[^>]*>)",
                   lambda m: m.group(1) + f"<dc:title>{esc_title}</dc:title>",
                   s, count=1)
    return s.encode("utf-8")


# ---------------------------------------------------------------- 主流程


def process(path: Path, style: str, title: str, want_toc: bool,
            table_rule: str, footer_total: bool):
    if not path.exists():
        raise Fail(f"找不到文件: {path}")
    if style not in PAGE_MARGIN:
        raise Fail(f"--style 只能是 report / gb / brief，收到: {style}")

    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        items = {n: zf.read(n) for n in names}

    if "word/document.xml" not in items:
        raise Fail("不是有效的 docx：缺少 word/document.xml")

    raw = items["word/document.xml"]
    register_ns(raw)
    root = ET.fromstring(raw)
    body = root.find(w("body"))
    if body is None:
        raise Fail("word/document.xml 里没有 <w:body>")

    brief = style == "brief"

    report = {}
    if brief:
        # 简报没有封面页也没有目录，三步分节全部跳过：文档只有末尾一个 sectPr。
        report["moved"] = report["cover"] = False
        report["toc_title"] = report["front"] = False
    else:
        report["moved"] = step_reorder(body)
        report["cover"] = step_cover(body, style)
        report["toc_title"], report["front"] = step_toc(body, style, want_toc)
    step_body_sect(body, style)
    report["heading_breaks"] = normalize_heading_page_breaks(body)

    tables = body.findall(f".//{w('tbl')}")
    dense_n = 0
    for tbl in tables:
        if style_table(tbl, table_rule, style):
            dense_n += 1
    report["tables"] = len(tables)
    report["dense_tables"] = dense_n
    report["semantic_markers"] = style_semantic_markers(root)

    items["word/document.xml"] = ET.tostring(root, encoding="UTF-8",
                                             xml_declaration=True)

    # 页眉标题 + STYLEREF 取的标题级别
    short = truncate(title, 30)
    head_level = detect_head_level(body, style)
    if not brief:
        for hdr in ("word/header1.xml", "word/header2.xml"):
            if hdr in items:
                items[hdr] = patch_header_title(items[hdr], short)
        if "word/header1.xml" in items:
            items["word/header1.xml"] = patch_header_level(
                items["word/header1.xml"], head_level)
    report["title"] = short
    report["head_level"] = head_level

    # 页脚：只改正文节。前置节是罗马页码，NUMPAGES 会跟着渲染成 LVI 之类，
    # 「共 M 页」在那儿没有意义，保持纯页码。
    if footer_total and not brief and "word/footer1.xml" in items:
        items["word/footer1.xml"] = footer_total_xml(style)
    report["footer_total"] = footer_total and not brief

    # 代码高亮去色
    report["tok"] = 0
    if "word/styles.xml" in items:
        items["word/styles.xml"], report["tok"] = \
            fix_code_colors(items["word/styles.xml"])

    # 包级
    if "word/settings.xml" in items:
        items["word/settings.xml"] = fix_settings(items["word/settings.xml"])
    present = {n.split("/")[-1] for n in items
               if re.fullmatch(r"word/(header|footer)\d+\.xml", n)}
    if "word/_rels/document.xml.rels" in items:
        items["word/_rels/document.xml.rels"] = fix_rels(
            items["word/_rels/document.xml.rels"], present)
    if "[Content_Types].xml" in items:
        items["[Content_Types].xml"] = fix_content_types(
            items["[Content_Types].xml"], items.keys())
    if "docProps/core.xml" in items:
        items["docProps/core.xml"] = fix_core_props(
            items["docProps/core.xml"], title)

    # 检查引用的 header/footer 都真实存在
    doc_xml = items["word/document.xml"].decode("utf-8")
    rels_xml = items.get("word/_rels/document.xml.rels", b"").decode("utf-8")
    for rid in HDR_PARTS:
        if f'"{rid}"' in doc_xml and f'Id="{rid}"' not in rels_xml:
            raise Fail(f"sectPr 引用了 {rid}，但 rels 里没有对应关系")

    tmp = Path(tempfile.mkstemp(suffix=".docx", dir=str(path.parent))[1])
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zf:
        for n in names:
            zf.writestr(n, items[n])
        for n in items:
            if n not in names:
                zf.writestr(n, items[n])
    shutil.move(str(tmp), str(path))

    print(f"✓ docx 修补完成: {path.name}")
    if brief:
        print(f"    简报版式: 单节、无页眉页脚、无页码；公文版心 37/35/28/26mm"
              f"    表格: {report['tables']} 个已三线表化"
              f"（其中 {report['dense_tables']} 个内容较长，已加行间浅灰细线）"
              f"    代码高亮去色: {report['tok']} 个样式")
        print(f"    评审语义标签着色: {report['semantic_markers']} 处")
        return
    print(f"    封面节: {'已生成' if report['cover'] else '未找到封面标记'}"
          f"    前置节: {'已生成' if report['front'] else '无（未启用目录）'}"
          f"    目录标题: {'已改为「目　录」' if report['toc_title'] else '未找到'}")
    print(f"    正文节: 页码 decimal 从 1 重排；页眉标题「{report['title']}」"
          f"，右侧取 H{report['head_level']}"
          f"    表格: {report['tables']} 个已三线表化"
          f"（其中 {report['dense_tables']} 个内容较长，已加行间浅灰细线）"
          f"    代码高亮去色: {report['tok']} 个样式"
          f"    评审语义标签着色: {report['semantic_markers']} 处"
          f"    标题分页归一: {report['heading_breaks']} 处"
          f"{'；页脚含总页数' if report['footer_total'] else ''}")


def main():
    ap = argparse.ArgumentParser(
        description="paper-export :: pandoc docx 输出的最终修补")
    ap.add_argument("docx", help="pandoc 产出的 .docx")
    ap.add_argument("--style", required=True,
                    choices=["modern", "report", "gb", "brief"])
    ap.add_argument("--title", required=True, help="文档标题（写进页眉）")
    ap.add_argument("--toc", default="1", choices=["0", "1"],
                    help="文档是否含目录（默认 1）")
    ap.add_argument("--footer-total", default="0", choices=["0", "1"],
                    help="页脚是否显示总页数（默认 0）")
    ap.add_argument("--table-rule", default="auto",
                    choices=["auto", "three", "grid"],
                    help="表格线型：auto=内容长的表加行间线（默认）")
    a = ap.parse_args()
    try:
        process(Path(a.docx).resolve(), a.style, a.title,
                a.toc == "1", a.table_rule, a.footer_total == "1")
    except Fail as e:
        print(f"✗ docx 修补失败: {e}", file=sys.stderr)
        sys.exit(1)
    except (zipfile.BadZipFile, ET.ParseError) as e:
        print(f"✗ docx 修补失败（文件损坏或不是 docx）: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
