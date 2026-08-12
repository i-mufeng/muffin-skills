--[[
  paper-export :: cover-docx.lua
  为 Word（docx）输出生成封面页。其余格式原样返回（PDF 封面由 titlepage.tex 负责）。

  读取的 metadata 键：
      title  subtitle  org  author  doc-no  version  security  date

  版式（SPEC §6，A4 = 11906 × 16838 twips）：
      顶部留白 ≥ 15% 页高 → 单位名 → 主标题 → 副标题 → 0.75pt 横线（宽 60%）
      → 信息栏（文档编号 / 版本 / 密级 / 编制人）→ 弹性留白 → 日期（页面 85% 处）

  所有纵向尺寸都用 lineRule="exact" 的段落高度精确控制，弹性留白由本 filter
  按「日期中心落在页高 85%」反算，因此字段增减不会把日期挤走。

  末尾输出一个 PESectCover 标记段落，供 scripts/docx-postprocess.py 换成封面
  节的分节符。同时清空 meta.title / author / date，避免 pandoc 再输出一份
  Title/Author/Date 段落；原标题通过 meta['pe-title'] 传递给下游。
--]]

-- ---------------------------------------------------------------- 版面常量
local PAGE_H       = 16838   -- A4 页高
local MARGIN_TOP   = 1440    -- 2.54cm
local TEXT_W       = 8669    -- 版心宽度（取 gb 的较小值，折行估算更保守）

local FIRST_TOP    = 2600    -- 首个可见元素距页顶（= 15.4% 页高 ≥ 15%）
local DATE_CENTER  = math.floor(PAGE_H * 0.85)   -- 日期垂直中心 14312

-- 与 build-reference-docx.py 里 PECover* 样式的 exact 行高保持一致
local H_ORG        = 520
local H_TITLE_LINE = 800
local H_SUBTITLE   = 560
local H_INFO       = 480
local H_DATE       = 520
local H_RULE       = 220
local H_MARKER     = 20

local GAP_ORG_TITLE   = 700   -- 单位名 → 主标题
local GAP_TITLE_SUB   = 320   -- 主标题 → 副标题
local GAP_BEFORE_RULE = 700   -- 副标题 → 横线
local GAP_AFTER_RULE  = 700   -- 横线 → 信息栏
local GAP_MIN         = 240   -- 弹性留白下限

-- 信息栏字段：标签统一 4 个汉字宽（U+3000 全角空格 / U+2002 半宽空格补齐）
local INFO_FIELDS = {
  { key = 'doc-no',   label = '文档编号' },
  { key = 'version',  label = '版\227\128\128\227\128\128本' },   -- 版　　本
  { key = 'security', label = '密\227\128\128\227\128\128级' },   -- 密　　级
  { key = 'author',   label = '编\226\128\130制\226\128\130人' }, -- 编 制 人
}

-- ---------------------------------------------------------------- 工具

local function esc(s)
  s = s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')
  return s
end

--- 显示宽度：CJK / 全角标点计 2，其余计 1
local function disp_width(s)
  local w = 0
  for _, cp in utf8.codes(s) do
    if cp >= 0x1100 and (cp <= 0x115F
        or (cp >= 0x2E80 and cp <= 0xA4CF)
        or (cp >= 0xAC00 and cp <= 0xD7A3)
        or (cp >= 0xF900 and cp <= 0xFAFF)
        or (cp >= 0xFE30 and cp <= 0xFE4F)
        or (cp >= 0xFF00 and cp <= 0xFF60)
        or (cp >= 0xFFE0 and cp <= 0xFFE6)
        or (cp >= 0x20000 and cp <= 0x3FFFD)) then
      w = w + 2
    else
      w = w + 1
    end
  end
  return w
end

local function meta_str(meta, key)
  local v = meta[key]
  if v == nil then return nil end
  local s = pandoc.utils.stringify(v)
  s = s:gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' then return nil end
  return s
end

-- ---------------------------------------------------------------- OpenXML 片段

local function p_spacer(h)
  return string.format(
    '<w:p><w:pPr><w:pStyle w:val="PECoverGap"/>' ..
    '<w:spacing w:before="0" w:after="0" w:line="%d" w:lineRule="exact"/>' ..
    '</w:pPr></w:p>', h)
end

local function p_text(style, text)
  return '<w:p><w:pPr><w:pStyle w:val="' .. style .. '"/></w:pPr>' ..
         '<w:r><w:rPr><w:rFonts w:hint="eastAsia"/></w:rPr>' ..
         '<w:t xml:space="preserve">' .. esc(text) .. '</w:t></w:r></w:p>'
end

local function p_empty(style)
  return '<w:p><w:pPr><w:pStyle w:val="' .. style .. '"/></w:pPr></w:p>'
end

-- ---------------------------------------------------------------- 封面装配

local function build_cover(meta)
  local title    = meta_str(meta, 'title') or meta_str(meta, 'pe-title')
  local subtitle = meta_str(meta, 'subtitle')
  local org      = meta_str(meta, 'org')
  local date     = meta_str(meta, 'date')

  if not title then return nil, nil end

  -- 信息栏（缺失字段整行省略）
  local infos = {}
  for _, f in ipairs(INFO_FIELDS) do
    local v = meta_str(meta, f.key)
    if v then infos[#infos + 1] = f.label .. '：' .. v end
  end

  -- 主标题折行数估算：一号字 26pt + 字间距 2pt ≈ 560 twips / 汉字
  local title_lines = math.max(1,
    math.ceil(disp_width(title) * 280 / TEXT_W))

  -- 纵向堆叠
  local parts = {}
  local used = MARGIN_TOP

  local function push(xml, h)
    parts[#parts + 1] = xml
    used = used + h
  end

  push(p_spacer(FIRST_TOP - MARGIN_TOP), FIRST_TOP - MARGIN_TOP)

  if org then
    push(p_text('PECoverOrg', org), H_ORG)
    push(p_spacer(GAP_ORG_TITLE), GAP_ORG_TITLE)
  end

  push(p_text('PECoverTitle', title), H_TITLE_LINE * title_lines)

  if subtitle then
    push(p_spacer(GAP_TITLE_SUB), GAP_TITLE_SUB)
    local s = subtitle
    if not s:match('^\226\128\148') then    -- 不是以 — 开头才补破折号
      s = '\226\128\148\226\128\148 ' .. s .. ' \226\128\148\226\128\148'
    end
    push(p_text('PECoverSubtitle', s), H_SUBTITLE)
  end

  push(p_spacer(GAP_BEFORE_RULE), GAP_BEFORE_RULE)
  push(p_empty('PECoverRule'), H_RULE)

  if #infos > 0 then
    push(p_spacer(GAP_AFTER_RULE), GAP_AFTER_RULE)
    for _, line in ipairs(infos) do
      push(p_text('PECoverInfo', line), H_INFO)
    end
  end

  -- 弹性留白：让日期段落的垂直中心落在页高 85%
  if date then
    local date_top = DATE_CENTER - math.floor(H_DATE / 2)
    local gap = date_top - used
    if gap < GAP_MIN then gap = GAP_MIN end
    push(p_spacer(gap), gap)
    push(p_text('PECoverDate', date), H_DATE)
  end

  -- 分节标记（由 docx-postprocess.py 换成封面节的 sectPr）
  push(p_empty('PESectCover'), H_MARKER)

  return table.concat(parts), title
end

-- ---------------------------------------------------------------- brief 文头

--[[
  brief 预设不画封面页：标题直接印在正文第一页顶部，下面一道「上粗下细」
  的双线隔开正文 —— 与 PDF 侧 masthead-brief.tex 一一对应。

      〔单位名，--masthead-org 时才出现〕
       2026年8月5日会议内容简报        PEBriefTitle    二号黑体居中
          —— 项目管理模块 ——           PEBriefSubtitle 三号楷体居中
      ━━━━━━━━━━━━━━━━━━━  PEBriefRuleThick 1.2pt
      ─────────────────  PEBriefRuleThin  0.4pt

  不输出 PESectCover 标记：brief 全文只有一个节，也没有页眉页脚可引用。
--]]
local function build_masthead(meta)
  local title    = meta_str(meta, 'title') or meta_str(meta, 'pe-title')
  local subtitle = meta_str(meta, 'subtitle')
  local org      = meta_str(meta, 'org')
  local show_org = (meta_str(meta, 'masthead-org') == '1')

  if not title then return nil, nil end

  local parts = {}
  if show_org and org then
    parts[#parts + 1] = p_text('PEBriefOrg', org)
  end
  parts[#parts + 1] = p_text('PEBriefTitle', title)
  if subtitle then
    local s = subtitle
    if not s:match('^\226\128\148') then    -- 不是以 — 开头才补破折号
      s = '\226\128\148\226\128\148 ' .. s .. ' \226\128\148\226\128\148'
    end
    parts[#parts + 1] = p_text('PEBriefSubtitle', s)
  end
  -- 双线由两个空段落的下边框实现：Word 里画不出真正的「双线边框 + 自定粗细」，
  -- 两条独立的下边框反而更可控，粗细比也和 PDF 侧完全一致。
  parts[#parts + 1] = p_empty('PEBriefRuleThick')
  parts[#parts + 1] = p_empty('PEBriefRuleThin')
  parts[#parts + 1] = p_empty('PEBriefGap')

  return table.concat(parts), title
end

--- 文末落款：单位 / 编制人 / 日期，右对齐，距右边界 4 字宽（样式里设的右缩进）
local function build_signoff(meta)
  local lines = {}
  local org  = meta_str(meta, 'org')
  local auth = meta_str(meta, 'author')
  local date = meta_str(meta, 'signoff-date') or meta_str(meta, 'date')
  if org  then lines[#lines + 1] = org end
  if auth then lines[#lines + 1] = '编制：' .. auth end
  if date then lines[#lines + 1] = date end
  if #lines == 0 then return nil end

  local parts = { p_empty('PEBriefGap'), p_empty('PEBriefGap') }
  for _, line in ipairs(lines) do
    parts[#parts + 1] = p_text('PEBriefSignoff', line)
  end
  return table.concat(parts)
end

-- ---------------------------------------------------------------- filter

function Pandoc(doc)
  if not FORMAT:match('docx') then return nil end

  -- modern-plain 使用 pandoc 的行内 Title 样式，标题直接接正文，不生成封面。
  -- 作者、日期和副标题是封面信息；直接删掉 metadata，避免 pandoc 生成空的
  -- Author/Date 段落（空作者段会让部分办公软件错误回退中文字体）。
  if meta_str(doc.meta, 'pe-style') == 'modern-plain' then
    doc.meta.author = nil
    doc.meta.date = nil
    doc.meta.subtitle = nil
    return doc
  end

  if meta_str(doc.meta, 'pe-style') == 'brief' then
    local xml, title = build_masthead(doc.meta)
    if not xml then return nil end
    table.insert(doc.blocks, 1, pandoc.RawBlock('openxml', xml))
    local sig = build_signoff(doc.meta)
    if sig then
      doc.blocks[#doc.blocks + 1] = pandoc.RawBlock('openxml', sig)
    end
    doc.meta['pe-title'] = pandoc.MetaString(title)
    doc.meta.title    = nil
    doc.meta.author   = nil
    doc.meta.date     = nil
    doc.meta.subtitle = nil
    return doc
  end

  local xml, title = build_cover(doc.meta)
  if not xml then return nil end

  table.insert(doc.blocks, 1, pandoc.RawBlock('openxml', xml))

  -- 原标题留给下游（页眉文字、docProps 元数据由 docx-postprocess.py 还原）
  doc.meta['pe-title'] = pandoc.MetaString(title)
  -- 清空，避免 pandoc 再写一份 Title / Author / Date 段落
  doc.meta.title    = nil
  doc.meta.author   = nil
  doc.meta.date     = nil
  doc.meta.subtitle = nil

  return doc
end
