--[[
  paper-export :: title-dedup.lua

  封面标题默认取文档的第一个一级标题。若正文里那个 H1 原样保留，
  封面写一遍、正文第一页又写一遍、目录里还占一行 —— 三处重复。

  这里把「与封面标题完全相同的首个 H1」从正文里摘掉。只看第一个标题块，
  文中后续同名标题不受影响；合并多份文档时，各份自己的 H1（与总标题不同）
  也照常保留。

  必须排在 pagebreak.lua 之前运行 —— 否则首块已被换成分页符，找不到标题。

  比较时忽略全部空白（含 U+3000 全角空格）：文档里写的是
  `# 2026 年 8 月 5 日 会议内容简报`，命令行传的是
  `--title '2026年8月5日会议内容简报'` —— 人眼看是同一个标题，
  严格相等却匹配不上，于是标题在封面/文头和正文里各出现一遍。
]]

--- 归一化：去掉所有空白后再比。半角空格、制表、换行，以及中文文档里
--- 极常见的 U+3000 全角空格、U+00A0 不换行空格都算。
local function norm(s)
  s = s:gsub('%s+', '')
  s = s:gsub('\227\128\128', '')   -- U+3000
  s = s:gsub('\194\160', '')       -- U+00A0
  return s
end

function Pandoc(doc)
  local title = doc.meta.title
  if not title then return nil end
  title = norm(pandoc.utils.stringify(title))
  if title == '' then return nil end

  for i, block in ipairs(doc.blocks) do
    if block.t == 'Header' then
      if block.level == 1
         and norm(pandoc.utils.stringify(block.content)) == title then
        table.remove(doc.blocks, i)
        return doc
      end
      -- 首个标题不是重复的封面标题，就什么都不做
      return nil
    end
  end
  return nil
end
