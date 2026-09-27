# 研究记录与移植取舍

2026-09-27 调研。推荐把设计原则转为 Vue 的可运行组件与验收方法，而不是叠加多个相互冲突的风格提示词。以下是本技能的综合判断，不是任何来源对质量的保证。

## 实际探索的本机技能

| 技能 | 采用的方法 | 不照搬的部分 |
|---|---|---|
| design:design-system | token → component → pattern；先复用再扩展 | 不强制每个项目搭建新设计系统 |
| design:design-handoff | 变体、状态、响应式、边界与 token 引用 | 避免不必要的大型交付文档 |
| design:design-critique | 首印象、主任务、层级、一致性；按影响修复 | 不把主观风格偏好当合规门槛 |
| design:accessibility-review | 自动检查结合键盘与人工视觉 | 修正 44×44 在 AA/AAA 之间的等级混淆 |
| sites:sites-building | 先定视觉方向、首屏直接做事、真实内容 | 不移植 React/Vinext、托管与自动发布流程 |
| visualize:visualize | 类别映射稳定、色彩编码有意义、标签冗余 | 不移植宿主桥接、内联渲染和工具专属约束 |
| anthropic-skills:web-artifacts-builder | 避免同质模板和廉价装饰 | 不采用 React、单 HTML 打包或可选验收作为 Vue 主流程 |
| frontend-ui-design（仓库现有草稿） | 信息层级、状态与浏览器验证 | 保留原文件；本技能补足 Vue API/复用实物和色彩依据 |
| 原 ui-design-optimization | 35 条局部设计技巧 | 校正“必须渐变/毛玻璃/插画”“颜色数量”等绝对说法 |

这些是独立插件/本地技能，不统称“OpenAI 官方技能”；安装名称不代表来源背书。本技能自包含，不要求其他技能必须安装。

## 在线一手资料与采用范围

- [OpenAI Frontend prompt instructions](https://developers.openai.com/api/docs/guides/frontend-prompt)：采用按产品领域设计、尊重既有系统、可操作首屏、完整状态和真实截图验证。其圆角、字体、图片和英雄区的具体偏好不升级为所有 Vue 项目的硬规则。
- [Vue Slots](https://vuejs.org/guide/components/slots.html) 与 [Composables](https://vuejs.org/guide/reusability/composables.html)：采用结构与状态逻辑的分离复用方式。
- [Material 色彩角色](https://codelabs.developers.google.com/customizing-material-color)：借鉴角色及前景/容器配对，不要求照搬 Material 外观。
- [DTCG Format](https://www.designtokens.org/tr/2025.10/format/)：按需用于工具间 token 交换，不强制所有项目增加编译层。
- [Reka UI Accessibility](https://www.reka-ui.com/docs/overview/accessibility)：复杂行为可借助 Vue primitives，保留集成验收。
- W3C 色彩/目标尺寸原始依据分别列于 [color-system.md](color-system.md) 和 [delivery-and-review.md](delivery-and-review.md)。

## 本轮要验证的假设

组件同源、真实 API、明暗 token 与不同业务情境，比只增加审美描述更能让 Vue 稿可维护。配套 starter 用于验证这条工程路径；它不证明所有未来生成都好看，也不强制后续产品复刻示例。视觉品质仍要在真实任务和用户评审中持续验证。

本次安装方式、测试实证与未验证边界见 [validation.md](validation.md)。
