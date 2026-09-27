# 色彩体系：标准、预算与验证

## 先澄清“颜色数量”

查阅的 WCAG、Material 和设计 token 规范没有给出“所有网页最多 N 个颜色”的统一要求。色阶、主题、透明合成、照片会产生很多实际色值。不能用 HEX 去重数量代表设计质量。

本技能建议新项目采用以下**角色预算**，可随品牌/任务调整并说明理由：

| 角色 | 默认建议 | 用途与约束 |
|---|---|---|
| 品牌主色 | 1 个色相家族 | 核心操作、当前选中；深浅变体不另算品牌色 |
| 辅助强调 | 0–2 个色相家族 | 次级内容或少量重点；不为填满配额增加颜色 |
| 中性色 | 1 套冷/暖一致的灰阶 | 背景、表面、正文、边框；避免每张卡一个彩色底 |
| 语义状态 | 成功/警告/危险/信息按需 | 语义稳定，只出现在相应状态；不要凑齐四种状态装饰页面 |
| 图表系列 | 独立、固定映射 | 类别多少由数据决定；系列多时分组、小多图、直接标签，不硬砍真实类别 |

“不单调”靠表面层次、明度、排版、信息密度与必要辅助色；“不复杂”靠稳定角色及克制使用高饱和面积。主色同语义色接近时，尤其不能只用色相表达状态。

60/30/10 是面积与视觉权重的设计启发，并非 W3C 合规标准，也不等于三种 HEX。Utah 设计系统把它作为配色指导。业务后台可以大部分为中性背景；不要强制 60% 背景涂品牌色，不需要像素统计证明这个比例。

用户若硬性限定总共三种颜色，先尊重限制，用标签、线型、形状或小多图表达八类数据与危险状态，不擅自给状态/图表色豁免。只有无法同时满足明确要求时解释冲突并提问。

## Token 组织

按需使用三层：原始色阶 → 语义角色 → 组件专用别名。已有系统只有语义层时不强制改造三层。

```css
/* 仅示意命名，数值必须根据项目验证；沿用现有前缀。 */
:root {
  --palette-teal-700: #0f766e;
  --color-action: var(--palette-teal-700);
  --color-on-action: #ffffff;
  --button-primary-bg: var(--color-action);
}
```

新建完整色彩体系时至少定义 background、surface、surface-muted、text、text-muted、border、control-border、action、on-action、focus、selected，以及实际使用的状态前景/背景对。已有项目局部修改只复用已有角色并补当前缺口，不据此重建全局主题。装饰分隔线与必要的控件边界分开，避免所有边框过浅。

组件使用语义变量；不能把 `green` 当作 `success` 直接绑定业务。图表颜色集中映射系列 ID，排序后不可随数组位置变色。跨工具交换 token 时可选 DTCG 格式；普通 CSS 变量项目无需为“先进”引入生成链。DTCG 是社区组规范，不应称作 W3C Recommendation。

## 主题与色阶

- 明暗主题分别映射语义角色，不靠 `invert()` 或统一降低透明度；`color-scheme` 配合原生控件。项目没要求暗色时不要擅自扩大范围。
- OKLCH 可帮助建立较均匀的明度阶梯，但不是可读性证明；检查实际 sRGB 显示色、色域裁切和目标浏览器支持。沿用已工作的 HEX 系统也可以。
- hover、pressed、selected、focus 要分别有用途；选中用图标/字重/边框等冗余，focus 不得被选中底色吞没。
- 图片/渐变后的文字须按实际最弱背景区域核验；透明色必须与背景合成后计算。不要只测遮罩标称色。

## 可验证的 WCAG 要求

- **1.4.3 AA**：普通文本至少 4.5:1；大文本至少 3:1。大文本通常为 18pt（24 CSS px），或 14pt（约 18.67 CSS px）粗体。标识、纯装饰与禁用内容等有规范例外；禁用仍应能被理解。
- **1.4.11 AA**：用于识别控件/状态或理解图形的必要视觉信息与相邻颜色至少 3:1，按标准例外处理。不要求每一条装饰分隔线都 3:1。
- **1.4.1 A**：颜色不能是唯一的信息载体；错误有文字、选中有非颜色提示、图表有标签/形状或等价数据。
- 对比度通过不等于整页 WCAG 合规；键盘、焦点、结构及其他适用条款仍需验证。

## 色对检查脚本

`scripts/check-contrast.py` 接收 JSON 数组，每项为：

```json
[
  {"name":"正文/表面", "foreground":"#182b2a", "background":"#ffffff", "minimum":4.5},
  {"name":"主按钮文字", "foreground":"#ffffff", "background":"#0f766e", "minimum":4.5}
]
```

只接受 `#RGB` / `#RRGGBB` 不透明 sRGB，阈值由实际用途指定。退出码 0 为全部通过，1 为色对未达标，2 为格式错误。不会用四舍五入后的数值判定通过。不接受透明色、CSS `var()`、OKLCH、渐变或截图；这些先在浏览器解析/合成，再检查。此脚本不判断颜色数量、语义正确性或整页合规。

## 来源（2026-09-27 查阅）

- [W3C 文本对比度](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
- [W3C 非文本对比度](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)
- [W3C 不单独依赖颜色](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html)
- [Material 色彩角色](https://codelabs.developers.google.com/customizing-material-color)：借鉴 primary/secondary/tertiary 和前景/容器配对，本文数量预算为技能建议。
- [Utah 配色指南](https://designsystem.utah.gov/guidelinesStandards/designGuidelines/color)：60/30/10 的设计指导语境。
- [DTCG 格式](https://www.designtokens.org/tr/2025.10/format/)：token 值、类型、别名与跨工具表达。
