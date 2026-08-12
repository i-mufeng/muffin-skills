--[[
  paper-export :: pagebreak.lua  —— 分页控制（修 D10）

  保证四件事（PDF 与 Word 一致）：
    1. 标题页独占一页  —— 由 export.sh 经 include-before 注入 \clearpage 完成
                          （pandoc 模板顺序：maketitle → include-before → toc → body）
    2. 目录页独占一页  —— 本 filter 在正文最前面插一个分页符（front-break）
    3. 章级标题另起一页 —— 按 break-level 在指定级别的标题前插分页符
    4. 正文第一个章级标题若就在正文开头，不重复插 —— 否则白多一页

  开关（metadata）：
    front-break   正文是否另起一页（默认 true，即目录页独占）
    break-level   auto | 0 | 1 | 2 | 3（默认 auto）
                    auto = 统计正文里各级标题数量后自行决定：
                      H1 数量 ≥ 2  → 在 H1 前分页
                      H1 数量 ≤ 1  → 在 H2 前分页
                    单 H1 的文档里那个 H1 会被 title-dedup 当作文档名摘掉，
                    剩下的 `## 一、概述` `## 二、…` 才是真正的章，所以降一级。
                    0 = 完全不按标题分页。
    break-h1      旧开关，向后兼容：为真且未显式给 break-level 时等价于 break-level=1

  依赖顺序：必须排在 title-dedup.lua **之后**运行 —— auto 推断要以「实际剩余的
  blocks」为准，否则会把已被摘掉的 H1 也算进去，导致该按 H2 分页的文档不分页。
]]

local front_break = true
local break_level_raw = nil     -- 用户显式给的 break-level
local break_h1 = false          -- 旧开关

local function truthy(v)
  local s = pandoc.utils.stringify(v):lower()
  return s == 'true' or s == 'yes' or s == '1' or s == 'on'
end

function Meta(meta)
  if meta['front-break'] ~= nil then front_break = truthy(meta['front-break']) end
  if meta['break-h1'] ~= nil then break_h1 = truthy(meta['break-h1']) end
  if meta['break-level'] ~= nil then
    local s = pandoc.utils.stringify(meta['break-level']):lower()
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    if s ~= '' then break_level_raw = s end
  end
  return meta
end

local function pagebreak()
  if FORMAT:match 'latex' then
    -- \clearpage 而非 \newpage：先冲掉浮动体，避免图表被甩到分页之后
    return pandoc.RawBlock('tex', '\\clearpage')
  elseif FORMAT:match 'docx' then
    return pandoc.RawBlock('openxml',
      '<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
  end
  return nil
end

-- 统计各级标题数量（只看顶层 blocks —— Div/BlockQuote 里的标题不参与分页）
local function count_headers(blocks)
  local n = { 0, 0, 0, 0, 0, 0 }
  for _, b in ipairs(blocks) do
    if b.t == 'Header' and b.level >= 1 and b.level <= 6 then
      n[b.level] = n[b.level] + 1
    end
  end
  return n
end

-- 解析 break-level → 目标级别（0 表示不分页）
local function resolve_level(blocks)
  local raw = break_level_raw
  if raw == nil then
    -- 没显式给：旧开关 break-h1=true 走 1 级，否则走 auto
    raw = break_h1 and '1' or 'auto'
  end

  raw = raw:gsub('^h', '')       -- 容忍 h1 / H2 这类写法
  if raw == 'none' or raw == 'off' or raw == 'false' or raw == 'no' then
    return 0
  end
  local n = tonumber(raw)
  if n then
    n = math.floor(n)
    if n < 0 then n = 0 end
    if n > 6 then n = 6 end
    return n
  end
  if raw ~= 'auto' then
    io.stderr:write('[pagebreak] 无法识别的 break-level="' .. tostring(break_level_raw)
      .. '"，按 auto 处理\n')
  end

  -- auto 推断
  local n_head = count_headers(blocks)
  if n_head[1] >= 2 then return 1 end
  -- H1 只有 0 或 1 个（多半已被 title-dedup 摘掉）：降到 H2
  if n_head[2] >= 2 then return 2 end
  -- 连 H2 都不足两个，分页没意义
  return 0
end

function Pandoc(doc)
  local br = pagebreak()
  if not br then return nil end          -- 非 latex/docx 输出，什么都不做

  local level = resolve_level(doc.blocks)

  local out = pandoc.List({})
  if front_break then out:insert(pagebreak()) end
  local body_start = #out                -- 正文内容的起点

  for _, b in ipairs(doc.blocks) do
    if level > 0 and b.t == 'Header' and b.level == level then
      -- 已经在正文起始处的那个标题不插：front-break 已经翻过页了，
      -- 再插一次会多出一整张空白页。
      if #out > body_start then out:insert(pagebreak()) end
    end
    out:insert(b)
  end

  doc.blocks = out
  return doc
end

return {
  { Meta = Meta },
  { Pandoc = Pandoc },
}
