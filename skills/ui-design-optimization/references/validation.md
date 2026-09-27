# 本轮验证记录

日期：2026-09-27。仅记录实际执行结果，不作为以后改动自动通过的依据。

## 安装与版本来源

仓库维护源：`skills/ui-design-optimization/`。

本机 Codex 入口：`/Users/mufeng/.codex/skills/ui-design-optimization`，已验证为指向 `/Users/mufeng/Code/Githb/muffin-skills/skills/ui-design-optimization` 的符号链接。

原实体目录备份在 `/Users/mufeng/.codex/skill-backups/ui-design-optimization-20260927-230006`，位于技能发现目录之外。原始导入文件另由 Git 提交 `8225007` 保留。后续直接修改仓库源文件，链接同步反映；Git 历史仍需显式提交，不会自动提交。

迁移到其他机器时，在仓库根目录确认目标不存在后创建链接（不覆盖已有目录）：

```bash
ln -s "$PWD/skills/ui-design-optimization" "${CODEX_HOME:-$HOME/.codex}/skills/ui-design-optimization"
```

## 命令与结果

| 检查 | 结果 |
|---|---|
| `quick_validate.py skills/ui-design-optimization`（使用 uv 临时 PyYAML 环境） | `Skill is valid!` |
| `python3 -m unittest discover -s skills/ui-design-optimization/scripts -p 'test_*.py' -v` | 4 项通过：已知比值、未四舍五入边界、非法输入、CLI 状态码 |
| starter `npm run typecheck` | 通过 |
| starter `npm test` | 1 个测试文件、7 项通过，含中文 IME/ARIA 属性组合 |
| starter `npm run build` | 27 模块构建成功 |
| 对 starter 明暗 token 提取明确色对后执行 `check-contrast.py` | 20/20 通过，涵盖正文、次要文字、按钮、状态、focus、输入边界 |
| 本地 Markdown 引用、35 个编号、安装链接 | 通过 |
| `git diff --check` | 通过 |
| 仓库约定的 paper-export 既有回归 | 修改前 fast：92 通过/3 跳过；收尾全量：107 通过/1 跳过（未启用 soffice 渲染） |

首次系统 Python 运行格式校验因缺少 `yaml` 失败；改用 `uv run --with pyyaml` 后通过，未修改系统 Python 安装。

## 真实浏览器检查

使用 Codex 内置浏览器访问本地 Vite 服务。实际操作项目搜索与零结果恢复、状态筛选、项目详情展开/收起、团队筛选、视图切换、表单错误/修复/保存示例反馈、三个按钮变体及明暗切换；禁用/加载按钮不可点击。Tab 从搜索框移至状态选择框，实测可见 2px 焦点边框；Enter 可清除筛选。

320、390、768、1440 CSS px 宽度下页面 scrollWidth 与 innerWidth 一致；数据表在自身容器内横向滚动。查看了窄屏、手机、平板/桌面、明暗主题截图，控制台 warn/error 查询为空。截图保存在仓库忽略目录 `out/ui-design-optimization/`。

检查期间修复了输入框覆盖外部 ARIA、中文输入法组合状态、手机隐藏页头操作，以及表格隐藏标签绝对定位导致页面横向溢出的问题；相关类型检查、测试、构建及溢出检查已重跑。

## 证据边界

本次是可运行技能资产与本地交互验收；没有付费模型调用、生产 API、线上部署或真实账号验收。未进行完整屏幕阅读器审计、跨浏览器兼容矩阵、200% 浏览器缩放和所有 WCAG 条款合规审计。独立代理完成三个请求场景的指令走查，未进行多次独立生成作品的视觉质量基准评测。
