# Vue 设计工作台示例

这是 `ui-design-optimization` 的可运行复用示例：Vue 3 SFC、TypeScript、Vite、本地数据。
青绿工作台只是一个视觉方向；迁移到实际项目时，沿用项目的设计系统、字体、品牌色与工程约定。

```bash
npm ci
npm run dev
npm run typecheck
npm test
npm run build
```

需要 Node.js 22.12 或更高版本。默认预览只监听本机。

## 演示内容

- 项目列表：关键词搜索、状态筛选、空结果恢复、项目详情。
- 团队成员：同样的搜索与筛选组件，不同的业务数据和布局。
- 组件展示：按钮、徽章、表单校验、空状态与反馈。
- 浅色与深色：同一组语义 token 切换；刷新后恢复默认浅色。
- 所有数据仅存于本地示例；没有服务器、账号或真实保存功能。

## 复用边界

| 组件 | 输入和扩展点 |
| --- | --- |
| `UiButton` | `variant/type/loading/disabled`；默认插槽；原生事件与属性透传 |
| `UiBadge` | `tone`；默认插槽 |
| `UiField` | `v-model/label/id/error/hint/type`；输入属性透传；自动生成稳定标签关联 ID |
| `UiIcon` | `name`；统一 SVG 描边；图标为装饰，操作名称由宿主按钮提供 |
| `PageHeader` | `eyebrow/title/description`；`actions` 插槽 |
| `EmptyState` | `title/description`；默认操作插槽 |

组件不访问路由、网络或示例数据。业务数据在 `src/data.ts`，页面负责筛选与选择。
语义颜色、字体、尺寸尺度在 `src/tokens.css`；`src/components.css` 是独立的可携带组件样式入口；`src/style.css` 仅包含示例页面布局。
提取组件时引入 `tokens.css` 与 `components.css`，无需携带页面布局。不要复制整个业务页面来模拟复用。

小屏保留可横向滚动的数据表，页面自身不应横向溢出；团队列表会减少次要信息。
行为测试覆盖 loading 防重复操作、标签/错误关联、筛选恢复、视图切换、主题切换与表单校验。
浏览器视觉、键盘和移动端验收仍需在使用时执行，不能用单元测试替代。
