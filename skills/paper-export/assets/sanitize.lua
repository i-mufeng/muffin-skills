--[[
  paper-export :: sanitize.lua
  清洗 Markdown 中会让 LaTeX 缺字形（Missing character）的 Unicode。

  处理三类：
  1. 零宽/变体选择符 —— 无字形，且会让前一个符号被当彩色 emoji，必须剔除
  2. 彩色 emoji     —— XeTeX 不支持 CBDT/sbix 彩色字体，映射为等义文本符号
  3. 其余保留       —— Box Drawing、☐、✓、★ 等由 preamble 的 \newunicodechar
                       指到 Menlo(DejaVu 血统，字形覆盖完整)，不在此处动

  emoji 策略由 metadata 变量 `emoji` 控制：
    text (默认) —— 映射为文本符号，保留语义
    strip       —— 直接删除
    keep        —— 原样保留（仅在你确认字体覆盖时使用）
]]

-- 零宽与变体选择符：一律剔除
local ZERO_WIDTH = {
  ["\u{FE0E}"] = true, ["\u{FE0F}"] = true,  -- variation selector 15/16
  ["\u{200B}"] = true, ["\u{200C}"] = true,
  ["\u{200D}"] = true, ["\u{2060}"] = true,  -- ZWJ / word joiner
}

-- 彩色 emoji → 文本等价物（保留语义，不丢信息）
local EMOJI_TEXT = {
  ["✅"] = "√",  ["❌"] = "×",  ["✔️"] = "√", ["✖️"] = "×",
  ["⚠️"] = "!",  ["🔴"] = "●",  ["🟢"] = "●", ["🟡"] = "●",
  ["🔵"] = "●",  ["⭐"] = "★",  ["🌟"] = "★", ["💡"] = "*",
  ["📌"] = "*",  ["📝"] = "*",  ["🔧"] = "*", ["🚀"] = "*",
  ["👍"] = "√",  ["🎯"] = "*",  ["📊"] = "*", ["🔍"] = "*",
  ["❗"] = "!",  ["❓"] = "?",  ["➡️"] = "→", ["⬅️"] = "←",
}

local emoji_mode = "text"

function Meta(meta)
  if meta.emoji then
    emoji_mode = pandoc.utils.stringify(meta.emoji)
  end
  return meta
end

local function clean(s)
  local out = {}
  for _, cp in utf8.codes(s) do
    local ch = utf8.char(cp)
    if ZERO_WIDTH[ch] then
      -- drop
    elseif EMOJI_TEXT[ch] then
      if emoji_mode == "text" then
        out[#out + 1] = EMOJI_TEXT[ch]
      elseif emoji_mode == "keep" then
        out[#out + 1] = ch
      end
      -- strip: drop
    elseif emoji_mode ~= "keep"
        and ((cp >= 0x1F300 and cp <= 0x1FAFF)   -- 杂项符号与图形/补充
          or (cp >= 0x1F000 and cp <= 0x1F2FF)) then
      -- 未在映射表内的彩色 emoji：text 模式下也无法可靠渲染，剔除
      if emoji_mode == "text" then out[#out + 1] = "*" end
    else
      out[#out + 1] = ch
    end
  end
  return table.concat(out)
end

function Str(el)
  local c = clean(el.text)
  if c ~= el.text then return pandoc.Str(c) end
end

-- 代码块与行内代码同样要清洗（否则 verbatim 里的 emoji 一样炸）
function CodeBlock(el)
  el.text = clean(el.text)
  return el
end

-- ---------------------------------------------------------------------------
-- 行内代码的断行
--
-- 长标识符（fireline-frontend:latest、com.foo.BarService）在 \texttt 里
-- 不可断行，会直接撑破表格列宽和版心。在 LaTeX 输出时自行转义并逐字符
-- 插入高代价断点：只有实在放不下才断，正常情况观感不变。
--
-- 必须在 AST 层做而不是重定义 \texttt —— pandoc 会把 ^ 转义成 \^{}，
-- 在 TeX 侧逐 token 插 \penalty 会把它喂给重音命令，编译直接中断。
-- ---------------------------------------------------------------------------
local LATEX_ESC = {
  ['\\'] = '\\textbackslash{}', ['{'] = '\\{', ['}'] = '\\}',
  ['$'] = '\\$', ['&'] = '\\&', ['#'] = '\\#', ['%'] = '\\%',
  ['_'] = '\\_', ['^'] = '\\^{}', ['~'] = '\\textasciitilde{}',
}

local function tex_code_with_breaks(s)
  local out = {}
  for _, cp in utf8.codes(s) do
    local ch = utf8.char(cp)
    out[#out + 1] = LATEX_ESC[ch] or ch
    -- penalty 取 100：足够低，放不下时会断；又不至于让短代码被随意断开。
    -- 尾随空格是 TeX 的数字终止符，不会产生可见空白
    out[#out + 1] = '\\penalty100 '
  end
  return table.concat(out)
end

-- 标题里的行内代码保持原样：raw TeX 进目录/书签会出问题，
-- 而标题本就很短，不存在撑破版心的风险。
local function mark_protected(el)
  el.content = pandoc.walk_inline(pandoc.Span(el.content), {
    Code = function(c)
      c.classes:insert('pe-nobreak')
      return c
    end,
  }).content
  return el
end

function Code(el)
  el.text = clean(el.text)
  if not FORMAT:match('latex') then return el end
  if el.classes:includes('pe-nobreak') then return el end
  return pandoc.RawInline('tex', '\\texttt{' .. tex_code_with_breaks(el.text) .. '}')
end

-- ---------------------------------------------------------------------------
-- 有序列表的编号样式
--
-- pandoc 只要看到列表带具体的 style/delim（Markdown 的 `1.` 会被解析成
-- Decimal + Period），就在 \begin{enumerate} 后面直接写死
--     \def\labelenumi{\arabic{enumi}.}
-- 把 preamble 里 enumitem 设的「1. / (1) / ①」三级样式整个盖掉。
--
-- 把 style 与 delim 还原成 Default，pandoc 就不再写那行，编号交回 enumitem。
-- 只对 LaTeX 做：Word 侧的编号走 numbering.xml，与此无关。
-- ---------------------------------------------------------------------------
local function default_numbering(el)
  if not FORMAT:match('latex') then return nil end
  local start = el.start or 1
  el.style = 'DefaultStyle'
  el.delimiter = 'DefaultDelim'
  el.start = start
  return el
end

return {
  { Meta = Meta },
  { Header = mark_protected },
  { Str = Str, Code = Code, CodeBlock = CodeBlock,
    OrderedList = default_numbering },
}
