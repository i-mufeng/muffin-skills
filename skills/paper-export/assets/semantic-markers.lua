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

  PDF 在这里转换为带前景色和底色的 LaTeX；Word 保留原始文字，交给
  docx-postprocess.py 在 OOXML 层着色。只允许固定标签，避免任意内容通过
  RawInline 注入 LaTeX。
]]

local MARKERS = {
  ["mark-confirm"] = {
    text = "【待确认】", fg = "C00000", bg = "FCE8E6",
  },
  ["mark-supplement"] = {
    text = "【需补充】", fg = "C00000", bg = "FCE8E6",
  },
  ["mark-suggestion"] = {
    text = "【建议方案】", fg = "1F4E78", bg = "DDEBF7",
  },
  ["mark-adversarial"] = {
    text = "【对抗意见】", fg = "C00000", bg = "FCE8E6",
  },
  ["mark-defer"] = {
    text = "【建议暂缓】", fg = "C00000", bg = "FCE8E6",
  },
  ["mark-reject"] = {
    text = "【建议剔除】", fg = "C00000", bg = "FCE8E6",
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

  -- docx 侧由后处理脚本按固定标签文字处理；其他格式保留正常文本。
  return el.content
end
