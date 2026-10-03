# 前端设计质量门槛

实现或审查时按风险选取相关检查。数值采用 WCAG 2.2 和主流平台规范的可验证下限，不因视觉风格而降低。

## 响应式与内容韧性

- 从内容需要断行或重排的时刻设置断点，不按某几款设备硬编码。
- 至少验证约 `320px` 窄屏、`390px` 常见手机、`768px` 平板/窄窗口、`1440px` 桌面；产品另有目标设备时以产品矩阵为准。
- 页面不产生意外横向滚动；固定工具栏、浮层、虚拟键盘和安全区不会遮住内容或操作。
- 网格、媒体、图表、表格和弹窗有明确的 `min/max`、宽高比或溢出策略，动态内容不会导致布局跳动。
- 文本可放大到 200% 后仍可阅读和操作；不要禁用浏览器缩放。

## 无障碍基线

- 普通文本与背景对比度至少 `4.5:1`；大文本至少 `3:1`。重要图标、输入边框、焦点和图形对象等非文本内容至少 `3:1`。
- 所有交互可用键盘完成，焦点顺序符合视觉和阅读顺序；焦点样式始终可见，不被 sticky 区域或弹窗遮挡。
- Web 目标尺寸至少符合 WCAG 2.2 AA 的 `24 x 24 CSS px` 或满足间距例外；移动端主要操作优先达到约 `44-48px` 的舒适触控区。
- 使用语义 HTML。按钮执行动作，链接导航；表单有程序化标签，图片有适当 `alt`，纯装饰图片使用空 `alt`。
- 颜色不是唯一信息载体；图表、错误、选中和状态均有文字、形状或图标冗余。
- 弹窗打开后管理初始焦点，焦点留在弹窗内，关闭后返回触发点；Escape、关闭按钮和遮罩行为符合产品约定。
- 尊重 `prefers-reduced-motion`，避免闪烁、强视差和阻碍操作的长动效。

## 状态与交互

- 检查默认、hover、active、focus-visible、selected、disabled、loading、success、error。触屏不能依赖 hover 才暴露关键功能。
- 加载时保留布局尺寸，减少跳动；超过短暂等待时显示进度或骨架，完成后给出可感知反馈。
- 空状态、零结果、离线、请求失败、权限不足分别处理；可恢复错误提供重试或修正方法。
- 删除、覆盖、付款等高风险动作与普通动作明显区分，并按后果提供撤销或确认。确认文案具体说明对象和后果。
- 导航、筛选、排序、分页和滚动位置在返回页面后按产品需求保留，避免用户重复劳动。

## 视觉与组件一致性

- 颜色、字体、间距、圆角、阴影、层级和动效使用语义 token，不在组件内散布无规律常量。
- 同类组件尺寸、对齐、图标、标签和状态一致；变体有明确用途，不以页面为单位复制出新样式。
- 每个视区的主次焦点明确，不同时出现多个同权重的主按钮。
- 数据表、表单和运营工具按扫描与批量操作效率设计；品牌页、内容页和作品页才扩大视觉叙事权重。
- 页面避免无意义的卡片嵌套、过度圆角、重阴影、同色渐变和装饰性背景；效果的加入必须能解释其信息或交互作用。

## 性能与感知质量

- 图片提供适当尺寸、现代格式与响应式候选，首屏关键图优先加载，其余延迟加载；避免用大图模拟可由 CSS 完成的简单效果。
- 字体子集和字重数量受控，提供合理回退，避免字体加载造成长时间空白或严重跳动。
- 动画优先使用 `transform` 和 `opacity`，避免持续触发布局；低性能设备下仍能完成主流程。
- 为异步媒体和动态区域预留稳定尺寸，关注 Core Web Vitals，尤其是 LCP、INP 与 CLS。

## 浏览器验收

1. 用真实内容走通主要任务和至少一个失败路径。
2. 用 Tab、Shift+Tab、Enter、Space、Escape 和方向键检查相关控件。
3. 在浅色/深色（若支持）、系统字号放大、减少动态效果和高对比环境下检查。
4. 截取窄屏和桌面整页及关键交互状态，检查遮挡、裁切、断行、对齐、浮层层级和固定区域。
5. 打开控制台与网络面板，确认没有影响体验的报错、资源 404、重复请求或明显布局抖动。

## 研究依据

- [WCAG 2.2: Contrast (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)：文本对比度。
- [WCAG 2.2: Non-text Contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)：控件、焦点与图形对象对比度。
- [WCAG 2.2: Target Size (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)：`24 x 24 CSS px` 目标尺寸及例外。
- [WCAG 2.2: Focus Visible](https://www.w3.org/WAI/WCAG22/Understanding/focus-visible.html) 与 [Focus Not Obscured](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html)：键盘焦点可见性。
- [WAI-ARIA Authoring Practices Guide](https://www.w3.org/WAI/ARIA/apg/)：常见交互模式的键盘与语义行为。
- [Apple Human Interface Guidelines: Layout](https://developer.apple.com/design/human-interface-guidelines/layout)：适配不同窗口、方向与安全区。
- [Material Design: Accessibility](https://m2.material.io/design/usability/accessibility.html)：触控目标、层级和无障碍设计实践。
- [web.dev: Responsive web design basics](https://web.dev/articles/responsive-web-design-basics)：内容驱动的响应式布局。
- [web.dev: Core Web Vitals](https://web.dev/articles/vitals)：感知加载、交互响应和布局稳定性。
- [Nielsen Norman Group: 10 Usability Heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/)：系统状态、用户控制、一致性、错误预防与恢复。

以上来源于 2026-08-31 复核。规范更新或产品合规要求更高时，以更新、更严格的要求为准。
