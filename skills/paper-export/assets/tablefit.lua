--[[
  paper-export :: tablefit.lua  —— 表格列宽重算（修 D7）

  pandoc 把 Markdown 分隔行 `| --- | ------- |` 的相对长度当列宽，或者干脆等分。
  结果是「说明」这种长文本列被挤成四行、而「编号」列留一大片白。

  本 filter 丢掉那套宽度，按**列内容的显示宽度**重新分配（SPEC §4.2）：

    1. w(s)   CJK / 全角计 2，其余计 1
    2. 每列取 head_w、max_w、p90_w（90 分位）
    3. weight = max(head_w + 2, min(max_w, p90_w * 1.3))，钳到 [6, 60]
    4. 线性归一化 与 √ 压缩归一化 各占一半 —— √ 压缩防止一列吃掉整版心
    5. 每列钳到 [0.06, 0.55]，迭代重归一化到和为 1
    6. 写回 colspecs（ColWidth），LaTeX 与 docx 两侧都吃这个值

  顺带把列对齐定下来：
    纯数字/百分比列 → 右对齐；最大显示宽度 ≤ 8 的窄列 → 居中；其余 → 左对齐。
  （表头一律居中，由 preamble / reference.docx 的样式负责，不在这里管。）

  另外把表头单元格的内容包一层 Strong：pandoc 生成的 longtable 表头是普通字重，
  而 `\toprule` 后面紧跟 `\noalign{}`，LaTeX 侧插不进只作用于表头行的字体命令。
  在 AST 层加粗，PDF 与 Word 两侧同时生效。

  开关（metadata）：
    table-fit        false 时整个 filter 空转
    table-head-bold  false 时不给表头加粗（默认 true）

  行间分界线（table-rule）：
    三线表只在「每格都是短词」时才好看。一旦某些单元格要折成两三行，相邻两行
    就会糊在一起、读者串行。所以按内容密度自动切换：

      auto （默认）任一数据单元格会折行 → 行间加一道极细浅灰线；否则纯三线表
      three        永远纯三线表
      grid         永远加行间线

    判据：单元格显示宽度 > 每行可容纳宽度 × 该列宽度占比。每行可容纳宽度由
    table-line-units 给出（默认 80，即 A4 版心在五号字下约 40 个汉字）。

    横线只用于「行间分界」，所以要压得比三线表的顶/底/表头线细得多、浅得多
    （0.25pt 浅灰），否则整张表会退化成网格，反而更吵。

    LaTeX 侧靠在下一行**第一个单元格开头**插一段 `\noalign{\perowrule}` 实现
    —— `\noalign` 只在「刚结束一行、还没开始下一个单元格」时合法，而 pandoc
    恰好把每行的第一个单元格顶在 `\\` 之后，位置严丝合缝。
    Word 侧拿不到 raw TeX，由 scripts/docx-postprocess.py 用同一套判据加
    `insideH` 边框。

  只读取、不实现的 metadata（底纹在 LaTeX 侧由 preamble、Word 侧由母版负责）：
    table-head-fill  0|1（默认 0，国标三线表不加底纹）
]]

-- ---------------------------------------------------------------------------
-- 参数（与 SPEC §4.2 一一对应）
-- ---------------------------------------------------------------------------
local P90          = 0.90
local P90_FACTOR   = 1.30
local HEAD_PAD     = 2      -- 表头保底：至少放得下表头再加两格
local WEIGHT_MIN   = 6
local WEIGHT_MAX   = 60
local SQRT_MIX     = 0.50   -- √ 压缩结果所占比例
local WIDTH_MIN    = 0.06
local WIDTH_MAX    = 0.55
local NARROW_CENTER = 8     -- 最大显示宽度 ≤ 8 的列居中
local LINE_UNITS   = 80     -- A4 版心在五号字下一行约容纳 80 个显示宽度单位

local enabled = true
local head_bold = true
local table_rule = 'auto'   -- auto | three | grid
local line_units = LINE_UNITS

-- 只读、不实现：底纹由 preamble（PDF）和 reference.docx（Word）负责
local head_fill = false

-- 行间分界线。\perowrule 在 preamble-common.tex 里定义（0.25pt 浅灰），
-- 线宽与颜色集中在那里调，filter 只负责决定插不插。
local ROW_RULE = '\\noalign{\\perowrule}'

local function truthy(v)
  local s = pandoc.utils.stringify(v):lower()
  return not (s == 'false' or s == 'no' or s == '0' or s == 'off')
end

-- ---------------------------------------------------------------------------
-- 显示宽度
--
-- 东亚宽字符计 2：CJK 统一表意文字及扩展、CJK 标点、假名、注音、谚文、
-- 全角形式、CJK 兼容字符、常见 emoji。
-- U+FF61–U+FFDC 是半角片假名/谚文，虽在 FFxx 段内但只占 1 格，单列出来。
-- 组合附加符号（U+0300–U+036F 等）不占宽。
-- ---------------------------------------------------------------------------
local function char_width(cp)
  if cp < 0x1100 then
    if cp < 0x20 or cp == 0x7F then return 0 end   -- 控制字符
    return 1
  end
  if (cp >= 0x0300 and cp <= 0x036F)
    or (cp >= 0x200B and cp <= 0x200F)
    or (cp >= 0xFE00 and cp <= 0xFE0F)             -- 变体选择符
    or cp == 0xFEFF then
    return 0
  end
  if (cp >= 0x1100 and cp <= 0x115F)               -- 谚文字母
    or (cp >= 0x2E80 and cp <= 0x303E)             -- CJK 部首 / 康熙 / CJK 标点
    or (cp >= 0x3041 and cp <= 0x33FF)             -- 假名 / 注音 / 兼容谚文 / 方块
    or (cp >= 0x3400 and cp <= 0x4DBF)             -- CJK 扩展 A
    or (cp >= 0x4E00 and cp <= 0x9FFF)             -- CJK 统一表意文字
    or (cp >= 0xA000 and cp <= 0xA4CF)             -- 彝文
    or (cp >= 0xAC00 and cp <= 0xD7A3)             -- 谚文音节
    or (cp >= 0xF900 and cp <= 0xFAFF)             -- CJK 兼容表意文字
    or (cp >= 0xFE10 and cp <= 0xFE19)             -- 竖排标点
    or (cp >= 0xFE30 and cp <= 0xFE6F)             -- CJK 兼容形式
    or (cp >= 0xFF00 and cp <= 0xFF60)             -- 全角形式
    or (cp >= 0xFFE0 and cp <= 0xFFE6)             -- 全角符号
    or (cp >= 0x1F300 and cp <= 0x1F64F)
    or (cp >= 0x1F680 and cp <= 0x1F6FF)
    or (cp >= 0x1F900 and cp <= 0x1F9FF)
    or (cp >= 0x20000 and cp <= 0x3FFFD) then      -- CJK 扩展 B 及以后
    return 2
  end
  return 1
end

-- 单行显示宽度
local function line_width(s)
  local w = 0
  local ok = pcall(function()
    for _, cp in utf8.codes(s) do w = w + char_width(cp) end
  end)
  if not ok then return #s end   -- 非法 UTF-8：退化成字节数，绝不让 filter 崩
  return w
end

-- 多行文本取各行最大值
local function text_width(s)
  local best = 0
  for line in (s .. '\n'):gmatch('([^\n]*)\n') do
    local w = line_width(line)
    if w > best then best = w end
  end
  return best
end

-- ---------------------------------------------------------------------------
-- 单元格取文本
--
-- 一个单元格可能有多个 Block（grid table 里很常见），要全部拼起来；
-- 硬/软换行也还原成换行，这样 text_width 的「按行取最大」才有意义。
-- ---------------------------------------------------------------------------
local BREAK_TO_NL = {
  LineBreak = function() return pandoc.Str('\n') end,
  SoftBreak = function() return pandoc.Str('\n') end,
}

local function cell_text(cell)
  local parts = {}
  for _, blk in ipairs(cell.contents) do
    local ok, res = pcall(function()
      return pandoc.utils.stringify(pandoc.walk_block(blk, BREAK_TO_NL))
    end)
    parts[#parts + 1] = ok and res or pandoc.utils.stringify(blk)
  end
  return table.concat(parts, '\n')
end

-- ---------------------------------------------------------------------------
-- 纯数字 / 百分比判定（右对齐用）
-- ---------------------------------------------------------------------------
local function is_numeric(s)
  s = s:gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' then return nil end                  -- 空格不参与判定
  s = s:gsub('[,，]', ''):gsub('^[%-+±~]', '')
  return s:match('^%d+%.?%d*%%?$') ~= nil
      or s:match('^%.%d+%%?$') ~= nil
      or s:match('^%d+%.?%d*[%-~－—]%d+%.?%d*%%?$') ~= nil   -- 区间 1~3、10-20
end

-- ---------------------------------------------------------------------------
-- 遍历表格的所有行（表头 / 表体 / 表脚）
-- 用占位网格处理 col_span / row_span，保证列号不串位。
-- ---------------------------------------------------------------------------
local function collect_rows(tbl)
  local head, body = {}, {}
  for _, row in ipairs(tbl.head.rows) do head[#head + 1] = row end
  for _, tb in ipairs(tbl.bodies) do
    for _, row in ipairs(tb.head or {}) do body[#body + 1] = row end
    for _, row in ipairs(tb.body) do body[#body + 1] = row end
  end
  for _, row in ipairs(tbl.foot.rows) do body[#body + 1] = row end
  return head, body
end

-- 把一批行摊平成 [col] = { w1, w2, ... }
local function measure(rows, ncols, texts)
  local widths = {}
  for i = 1, ncols do widths[i] = {} end
  local pending = {}          -- [col] = 还要占用多少行（row_span 余量）

  for _, row in ipairs(rows) do
    local carried = {}      -- 本行被上一行 row_span 占掉的列
    for c = 1, ncols do
      if (pending[c] or 0) > 0 then
        pending[c] = pending[c] - 1
        carried[c] = true
      end
    end

    local col = 1
    for _, cell in ipairs(row.cells) do
      while col <= ncols and carried[col] do col = col + 1 end
      if col > ncols then break end
      local span = math.max(1, cell.col_span or 1)
      local rspan = math.max(1, cell.row_span or 1)
      local txt = cell_text(cell)
      -- 跨列单元格的宽度按列数摊薄，避免把一列撑爆
      local w = text_width(txt) / span
      for k = col, math.min(col + span - 1, ncols) do
        widths[k][#widths[k] + 1] = w
        if texts then texts[k][#texts[k] + 1] = txt end
        if rspan > 1 then pending[k] = rspan - 1 end
      end
      col = col + span
    end
  end
  return widths
end

local function percentile(sorted, q)
  local n = #sorted
  if n == 0 then return 0 end
  local idx = math.ceil(q * n)
  if idx < 1 then idx = 1 end
  if idx > n then idx = n end
  return sorted[idx]
end

local function round4(x)
  return math.floor(x * 10000 + 0.5) / 10000
end

-- ---------------------------------------------------------------------------
-- 表头样式：加粗 + 强制居中
-- ---------------------------------------------------------------------------
local function bold_inlines(inlines)
  if #inlines == 0 then return inlines end
  -- 已经整体被 Strong 包裹就别再套一层
  if #inlines == 1 and inlines[1].t == 'Strong' then return inlines end
  return pandoc.Inlines({ pandoc.Strong(inlines) })
end

-- 表头：加粗 + 强制居中
--
-- 居中必须写在 Cell 自己的 alignment 上。列的 alignment 会同时管到表头行，
-- 数字列的表头就跟着右对齐了；而 pandoc 是把对齐当**直接格式**写进 docx 的
-- `<w:jc>`，Word 母版样式覆盖不掉，所以只能在 AST 层按单元格设。
local function style_head(tbl)
  for _, row in ipairs(tbl.head.rows) do
    for _, cell in ipairs(row.cells) do
      if head_bold then
        local blocks = pandoc.List({})
        for _, blk in ipairs(cell.contents) do
          if blk.t == 'Plain' or blk.t == 'Para' then
            blk.content = bold_inlines(blk.content)
          end
          blocks:insert(blk)
        end
        cell.contents = blocks
      end
      cell.alignment = 'AlignCenter'
    end
  end
end

-- ---------------------------------------------------------------------------
-- 行间分界线
--
-- 只在「有单元格会折行」时才加：短词表格用纯三线表最清爽，
-- 长文本表格不加分界线则相邻两行糊成一片。
-- ---------------------------------------------------------------------------

-- 遍历所有数据行，算出每个单元格的**真实起始列**。
--
-- 必须和 measure 用同一套占位网格：col_span 往右占位，row_span 往下占位。
-- 不跟踪 row_span 的后果有两个，都实测复现过：
--   needs_rules   拿错列的容量去比 —— 内容相同的两张表，只因第一列有没有
--                 合并单元格，一张判密一张判疏。
--   add_row_rules 把 \noalign 插到不在行首的单元格里 —— XeTeX 报
--                 「! Misplaced \noalign」，**PDF 一页都出不来**。
local function walk_body_rows(tbl, ncols, fn)
  local pending = {}          -- [col] = 还要占用多少行（row_span 余量）
  for _, tb in ipairs(tbl.bodies) do
    for _, row in ipairs(tb.body) do
      local carried = {}      -- 本行被上一行 row_span 占掉的列
      for c = 1, ncols do
        if (pending[c] or 0) > 0 then
          pending[c] = pending[c] - 1
          carried[c] = true
        end
      end

      local infos = {}
      local col = 1
      for _, cell in ipairs(row.cells) do
        while col <= ncols and carried[col] do col = col + 1 end
        if col > ncols then break end
        local span = math.max(1, cell.col_span or 1)
        local rspan = math.max(1, cell.row_span or 1)
        infos[#infos + 1] = { cell = cell, col = col, span = span }
        for k = col, math.min(col + span - 1, ncols) do
          if rspan > 1 then pending[k] = rspan - 1 end
        end
        col = col + span
      end
      fn(infos)
    end
  end
end

-- 该表是否需要行间线
local function needs_rules(tbl, widths)
  if table_rule == 'three' then return false end
  if table_rule == 'grid' then return true end
  -- auto：任一数据单元格的显示宽度超过它那一列的单行容量，即判为「密」
  local ncols = #widths
  local dense = false
  walk_body_rows(tbl, ncols, function(infos)
    for _, it in ipairs(infos) do
      local cap = 0
      for k = it.col, math.min(it.col + it.span - 1, ncols) do
        cap = cap + line_units * widths[k]
      end
      if text_width(cell_text(it.cell)) > cap then dense = true end
    end
  end)
  return dense
end

local function add_row_rules(tbl, widths, _)
  -- raw TeX 只有 LaTeX 侧吃得下；Word 侧由 docx-postprocess.py 用同一套判据加边框
  if not FORMAT:match('latex') then return end
  if not needs_rules(tbl, widths) then return end

  local ncols = #widths
  local first = true
  walk_body_rows(tbl, ncols, function(infos)
    if first then
      first = false            -- 首个数据行上方已经有表头的 \midrule
      return
    end
    -- \noalign 只在「刚结束一行」的位置合法。四种情况一律跳过该行的线，
    -- 宁可少一条分界线，也不能让整个 PDF 编译不出来：
    --   1. 本行第一个单元格不在第 1 列 —— 被上一行的 row_span 占了，
    --      它前面有个 & ，\noalign 就不在行首了
    --   2. 该单元格跨列 —— pandoc 包成 \multicolumn{n}{...}{...}，
    --      \noalign 落进第三个参数里
    --   3. 单元格不止一个块 —— 会被包进 \begin{minipage}
    --   4. 那个块不是 Plain/Para —— 同样不是能塞 inline 的位置
    local it = infos[1]
    if not it or it.col ~= 1 or it.span > 1 then return end
    local cell = it.cell
    local blk = cell.contents[1]
    if blk and #cell.contents == 1
       and (blk.t == 'Plain' or blk.t == 'Para') then
      table.insert(blk.content, 1, pandoc.RawInline('tex', ROW_RULE))
    end
  end)
end

-- ---------------------------------------------------------------------------
-- 主体
-- ---------------------------------------------------------------------------
local function fit(tbl)
  local ncols = #tbl.colspecs
  if ncols == 0 then return nil end

  local head_rows, body_rows = collect_rows(tbl)

  -- 表头宽度
  local head_widths = measure(head_rows, ncols)
  -- 数据单元格宽度 + 原文（数字判定要用）
  local body_texts = {}
  for i = 1, ncols do body_texts[i] = {} end
  local data_widths = measure(body_rows, ncols, body_texts)

  local weights = {}
  local col_max = {}
  for i = 1, ncols do
    local head_w = 0
    for _, w in ipairs(head_widths[i]) do if w > head_w then head_w = w end end

    local ws = {}
    for _, w in ipairs(data_widths[i]) do ws[#ws + 1] = w end
    table.sort(ws)

    local data_max = ws[#ws] or 0
    local max_w = math.max(data_max, head_w)
    local p90_w = percentile(ws, P90)
    if p90_w == 0 then p90_w = head_w end
    -- 居中判定只看数据格：`是否需审核` 这种长表头 + `是/否` 短数据的列，
    -- 表头本就由样式居中，数据跟着居中才好看
    col_max[i] = (data_max > 0) and data_max or head_w

    local weight = math.max(head_w + HEAD_PAD, math.min(max_w, p90_w * P90_FACTOR))
    if weight < WEIGHT_MIN then weight = WEIGHT_MIN end
    if weight > WEIGHT_MAX then weight = WEIGHT_MAX end
    weights[i] = weight
  end

  -- 线性归一化 与 √ 压缩归一化 按 SQRT_MIX 混合
  local sum_lin, sum_sqrt = 0, 0
  for i = 1, ncols do
    sum_lin = sum_lin + weights[i]
    sum_sqrt = sum_sqrt + math.sqrt(weights[i])
  end
  if sum_lin <= 0 then return nil end

  local widths = {}
  for i = 1, ncols do
    local lin = weights[i] / sum_lin
    local sq = math.sqrt(weights[i]) / sum_sqrt
    widths[i] = (1 - SQRT_MIX) * lin + SQRT_MIX * sq
  end

  -- 钳位 + 重归一化（列太多时下限自动放宽，否则无解）
  local lo = math.min(WIDTH_MIN, 1 / ncols)
  local hi = math.max(WIDTH_MAX, 1 / ncols)
  for _ = 1, 20 do
    local changed = false
    for i = 1, ncols do
      if widths[i] < lo then widths[i] = lo; changed = true
      elseif widths[i] > hi then widths[i] = hi; changed = true end
    end
    local s = 0
    for i = 1, ncols do s = s + widths[i] end
    for i = 1, ncols do widths[i] = widths[i] / s end
    if not changed then break end
  end

  -- 取四位小数，把舍入误差补回最宽的一列，保证和恰为 1
  local total, widest = 0, 1
  for i = 1, ncols do
    widths[i] = round4(widths[i])
    total = total + widths[i]
    if widths[i] > widths[widest] then widest = i end
  end
  widths[widest] = round4(widths[widest] + (1 - total))

  -- 对齐
  for i = 1, ncols do
    local align
    local numeric_seen, all_numeric = false, true
    for _, t in ipairs(body_texts[i]) do
      local r = is_numeric(t)
      if r == true then numeric_seen = true
      elseif r == false then all_numeric = false; break end
    end
    if numeric_seen and all_numeric then
      align = 'AlignRight'
    elseif col_max[i] <= NARROW_CENTER then
      align = 'AlignCenter'
    else
      align = 'AlignLeft'
    end
    tbl.colspecs[i][1] = align
    tbl.colspecs[i][2] = widths[i]
  end

  style_head(tbl)
  add_row_rules(tbl, widths, body_texts)

  return tbl
end

return {
  {
    Meta = function(meta)
      if meta['table-fit'] ~= nil then enabled = truthy(meta['table-fit']) end
      if meta['table-head-bold'] ~= nil then
        head_bold = truthy(meta['table-head-bold'])
      end
      if meta['table-head-fill'] ~= nil then
        head_fill = truthy(meta['table-head-fill'])
      end
      if meta['table-rule'] ~= nil then
        local v = pandoc.utils.stringify(meta['table-rule']):lower()
        if v == 'auto' or v == 'three' or v == 'grid' then
          table_rule = v
        else
          io.stderr:write('[tablefit] 无法识别的 table-rule：' .. v ..
                          '，按 auto 处理\n')
        end
      end
      if meta['table-line-units'] ~= nil then
        local n = tonumber(pandoc.utils.stringify(meta['table-line-units']))
        if n and n > 10 then line_units = n end
      end
      local _ = head_fill    -- 读到即可，底纹实现不在本 filter
      return meta
    end,
  },
  {
    Table = function(tbl)
      if not enabled then return nil end
      local ok, res = pcall(fit, tbl)
      if not ok then
        io.stderr:write('[tablefit] 跳过一张表：' .. tostring(res) .. '\n')
        return nil
      end
      return res
    end,
  },
}
