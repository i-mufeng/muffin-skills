export type Project = { id: number; name: string; category: string; owner: string; status: '进行中' | '待评审' | '已完成'; progress: number; updated: string; description: string }
export const projects: Project[] = [
  { id: 1, name: '拾光品牌升级', category: '品牌设计', owner: '林小满', status: '进行中', progress: 68, updated: '今天 10:24', description: '围绕日常生活的温度，梳理视觉语言、品牌色彩与线上触点。当前正在打磨关键应用场景。' },
  { id: 2, name: '城市漫游指南', category: '产品体验', owner: '陈一禾', status: '待评审', progress: 90, updated: '今天 09:12', description: '让周末探索变得更轻松。路线发现、收藏与行程分享已完成本轮设计，等待团队评审。' },
  { id: 3, name: 'Studio 春季作品集', category: '内容策划', owner: '周以宁', status: '进行中', progress: 42, updated: '昨天 17:30', description: '整理近期项目过程与成果，形成连贯的工作室故事和作品展示。' },
  { id: 4, name: '微光会员体验', category: '产品体验', owner: '林小满', status: '已完成', progress: 100, updated: '9 月 24 日', description: '从加入到首次使用，建立清晰、友好的会员服务体验。关键页面与组件已归档。' },
]
export const members = [
  { id: 1, name: '林小满', initials: '满', role: '设计负责人', email: 'xiaoman@example.com', status: '协作中', projects: 2 },
  { id: 2, name: '陈一禾', initials: '禾', role: '产品设计师', email: 'yihe@example.com', status: '协作中', projects: 1 },
  { id: 3, name: '周以宁', initials: '宁', role: '内容设计师', email: 'yining@example.com', status: '休假中', projects: 1 },
  { id: 4, name: '许知远', initials: '远', role: '前端工程师', email: 'zhiyuan@example.com', status: '协作中', projects: 0 },
]
