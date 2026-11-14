--[[
  paper-export :: semantic-markers.lua

  为评审稿中的不确定项提供跨 PDF / Word 的稳定语义标记。

  Markdown 写法：
    [【待确认】]{.mark-confirm}
    [【需补充】]{.mark-supplement}
    [【建议方案】]{.mark-suggestion}
    [【对抗意见】]{.mark-adversarial}
    [【建议暂缓】]{.mark-defer}
    [【建议剔除】]{.mark-reject}

  PDF 在这里转换为带前景色和底色的 LaTeX；Word 侧套一个 custom-style，
  pandoc 会写成 <w:rStyle w:val="PEMark…"/>，docx-postprocess.py 认这个标记
  在 OOXML 层着色。只允许固定标签，避免任意内容通过 RawInline 注入 LaTeX。

  **为什么 Word 侧要带标记**：原先这里直接 return el.content 把类丢掉，
  后处理只能按**纯文字**正则找「【待确认】」着色。于是正文里当普通词语用的
  「【待确认】」在 Word 里被着色、在 PDF 里不着色 —— 两侧不一致。带上
  custom-style 之后，两侧都只认「带类的 Span」这一个判据。
]]

local MARKERS = {
  ["mark-confirm"] = {
    text = "【待确认】", fg = "C00000", bg = "FCE8E6", ds = "PEMarkConfirm",
  },
  ["mark-supplement"] = {
    text = "【需补充】", fg = "C00000", bg = "FCE8E6", ds = "PEMarkSupplement",
  },
  ["mark-suggestion"] = {
    text = "【建议方案】", fg = "1F4E78", bg = "DDEBF7", ds = "PEMarkSuggestion",
  },
  ["mark-adversarial"] = {
    text = "【对抗意见】", fg = "C00000", bg = "FCE8E6", ds = "PEMarkAdversarial",
  },
  ["mark-defer"] = {
    text = "【建议暂缓】", fg = "C00000", bg = "FCE8E6", ds = "PEMarkDefer",
  },
  ["mark-reject"] = {
    text = "【建议剔除】", fg = "C00000", bg = "FCE8E6", ds = "PEMarkReject",
  },
}

function Span(el)
  local marker = nil
  for class, spec in pairs(MARKERS) do
    if el.classes:includes(class) then
      marker = spec
      break
    end
  end
  if marker == nil then return nil end

  local actual = pandoc.utils.stringify(el.content)
  if actual ~= marker.text then
    io.stderr:write("[semantic-markers] 标记内容与固定标签不一致，保持原样: "
      .. actual .. "\n")
    return nil
  end

  if FORMAT:match("latex") then
    local tex = string.format(
      "\\begingroup\\setlength{\\fboxsep}{1.2pt}"
      .. "\\colorbox[HTML]{%s}{\\textcolor[HTML]{%s}{\\bfseries %s}}"
      .. "\\endgroup{}",
      marker.bg, marker.fg, marker.text)
    return pandoc.RawInline("tex", tex)
  end

  -- docx 侧套 custom-style，让后处理能区分「带类的 Span」与正文里
  -- 恰好写了同样文字的普通词语。字体字号仍由正文样式决定，后处理只加
  -- 颜色、底纹、加粗 —— 所以不能在这里直接写 raw OpenXML。
  if FORMAT:match("docx") then
    return pandoc.Span(el.content, { ['custom-style'] = marker.ds })
  end

  -- 其他格式保留正常文本。
  return el.content
end
