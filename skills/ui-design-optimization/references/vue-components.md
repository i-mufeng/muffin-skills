# Vue 组件：从能复用到可验证

## 推荐分层

```text
src/
  styles/tokens.css          # 全局语义值；组件不另建私有色盘
  components/ui/            # Button、Field、Badge 等领域无关单元
  components/patterns/      # PageHeader、FilterBar、EmptyState 等组合
  features/<domain>/        # 领域类型、业务组件、逻辑；样例数据隔离
  views/                    # 页面布局、数据注入、路由衔接
  showcase/                 # 引用相同组件的可操作状态样例
```

这是新项目起点；已有项目沿用目录。组件数量按实际职责决定，不为“全部复用”把每一行布局抽象成参数配置器。基础/模式组件避免领域知识；业务组件可以使用领域类型，但不要把某个页面 URL、固定客户名字、请求地址嵌进去。

## API 设计

- Vue 3 默认 `<script setup lang="ts">`，现有版本与团队约定优先。
- `props` 输入内容、有限语义变体及状态；如 `variant: 'primary' | 'secondary' | 'ghost'`，避免 `green=true`、`isProjectPage` 或一堆互斥布尔值。
- `emits` 输出用户意图与所需 ID；接口、权限和通知由调用者/领域层处理。异步按钮由父级给 `loading`，避免双击重复提交。
- `slots` 用于标题操作区、图标、复杂单元格等结构扩展，不把整段 HTML 塞字符串。API 不需要的自由度不提前抽象。
- 双向数据采用兼容项目版本的 `v-model`（`modelValue`/`update:modelValue` 或支持版本的 `defineModel`）；不要修改 props 或制造父子两份不同步状态。
- 输入组件把 `id`、`name`、`aria-*`、`autocomplete` 等传给真实控件；`label for`、`aria-describedby` 与错误 ID 必须对应。多个实例 ID 唯一、SSR 稳定；不要用随机数解决 hydration。
- 明确 `$attrs` 与事件落在哪个根节点；包装组件避免意外双发 click。按钮默认 `type="button"`，提交由调用者明确声明。
- 有状态逻辑在确实复用时提取 composable；卸载时清理监听与定时器。不要把组件私有状态无意做成模块级单例。

## 选择基础库

优先复用项目已有 Element Plus、Naive UI、Vuetify、自有组件或其他 Vue 体系；不因视觉优化同时安装第二套大组件库。

新项目需要高定制外观和复杂可访问行为时，可评估 Reka UI 等 Vue headless primitives，再封装项目自己的语义外观。headless 的代价是自己维护 token/样式；完整库更快但外观改造受其 API 约束。先读取当前版本官方文档，不能把 React Radix/shadcn 的 import 直接贴进 Vue。

简单按钮/输入优先原生语义；复杂 combobox、菜单、对话框、树和日期选择器优先成熟实现。引入组件库并不自动证明当前组合的可访问性。

## 组件展示与真实复用

- 现有 Storybook/Histoire 优先；小项目可用普通 Vue 展示路由，不为展示引入大工具链。
- 展示组件真实源码的变体、长文本、禁用、加载、错误及必要主题。展示页与业务页共用同一 CSS/token 源。
- 为基础组件提供两组明显不同的内容/状态；对主要模式在两种业务情境中验证（如项目列表与团队列表）。已有业务只有一处时，用隔离展示验证第二种情境，不虚构新产品页面。
- 复用验收：换标题/数据不改组件源码；通过事件完成行为；更改一个 token 后所有实例同步；组件在独立父容器仍可布局。
- 无纯装饰性 `div` 冒充按钮；组件不可依赖 hover 才暴露关键操作。图标按钮要有可访问名称，文字提示不能只在鼠标可达。

## 防止“假 Vue”交付

页面、列表、表单等使用 SFC 与响应式状态。不得用 iframe 套历史 HTML、全页 `v-html`、整页截图或 CDN 临时组件冒充 Vue 迁移。不要在本任务中批量删除仍有运行依赖的旧稿。

设计数据明确置于 fixture/本地 store，生产 API 接入作为单独工作。浏览器主流程只证明设计交互，不证明真实登录、支付、模型或数据服务已接通。

## 官方依据

- [Vue Slots](https://vuejs.org/guide/components/slots.html)：结构扩展。
- [Vue Composables](https://vuejs.org/guide/reusability/composables.html)：复用有状态逻辑与生命周期。
- [Reka UI Accessibility](https://www.reka-ui.com/docs/overview/accessibility)：成熟 primitives 的行为基础；项目集成仍需验收。
