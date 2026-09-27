<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import UiButton from './components/UiButton.vue'
import UiIcon from './components/UiIcon.vue'
import UiBadge from './components/UiBadge.vue'
import UiField from './components/UiField.vue'
import PageHeader from './components/PageHeader.vue'
import EmptyState from './components/EmptyState.vue'
import { projects, members } from './data'
import type { Project } from './data'
const view = ref<'projects' | 'team' | 'components'>('projects')
const dark = ref(false)
const query = ref('')
const status = ref('全部状态')
const selected = ref<Project | null>(null)
const sampleName = ref('')
const sampleEmail = ref('')
const submitted = ref(false)
const notice = ref('')
const emailError = computed(() => submitted.value && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(sampleEmail.value) ? '请输入有效的邮箱地址' : '')
const filteredProjects = computed(() => projects.filter(p => `${p.name}${p.owner}${p.category}`.includes(query.value.trim()) && (status.value === '全部状态' || p.status === status.value)))
const filteredMembers = computed(() => members.filter(m => `${m.name}${m.role}${m.email}`.toLowerCase().includes(query.value.trim().toLowerCase()) && (status.value === '全部状态' || m.status === status.value)))
watch(view, () => { query.value = ''; status.value = '全部状态'; selected.value = null; notice.value = '' })
watch(dark, value => { document.documentElement.dataset.theme = value ? 'dark' : 'light' })
function resetFilters() { query.value = ''; status.value = '全部状态' }
function saveExample() { submitted.value = true; notice.value = emailError.value ? '' : '已保存本次示例输入' }
const tone = (state: string) => state === '待评审' || state === '休假中' ? 'warning' as const : state === '已完成' ? 'neutral' as const : 'brand' as const
</script>
<template>
  <a class="skip-link" href="#main">跳到主要内容</a>
  <div class="workbench">
    <aside class="sidebar">
      <a class="brand" href="#main" @click="view = 'projects'"><span class="brand-mark" aria-hidden="true">序</span><span>序集<small>团队工作台</small></span></a>
      <div class="workspace"><span class="workspace-avatar" aria-hidden="true">M</span><div>木木设计工作室<small>设计与产品协作</small></div></div>
      <p class="nav-label">工作空间</p>
      <nav aria-label="工作空间">
        <button :aria-current="view === 'projects' ? 'page' : undefined" @click="view = 'projects'"><UiIcon name="projects" />项目<span class="nav-count">04</span></button>
        <button :aria-current="view === 'team' ? 'page' : undefined" @click="view = 'team'"><UiIcon name="team" />团队成员<span class="nav-count">04</span></button>
        <button :aria-current="view === 'components' ? 'page' : undefined" @click="view = 'components'"><UiIcon name="components" />组件展示</button>
      </nav>
      <div class="sidebar-bottom"><UiBadge>本地演示</UiBadge><div class="account"><span class="avatar">沐</span><div>沐风<small>工作空间管理员</small></div></div></div>
    </aside>
    <div class="main-shell">
      <div class="topbar"><span>工作空间 <span aria-hidden="true">/</span> {{ view === 'projects' ? '项目' : view === 'team' ? '团队成员' : '组件展示' }}</span>
        <UiButton variant="quiet" :aria-pressed="dark" @click="dark = !dark"><UiIcon :name="dark ? 'sun' : 'moon'" />{{ dark ? '浅色' : '深色' }}</UiButton>
      </div>
      <main id="main" tabindex="-1">
        <template v-if="view !== 'components'">
          <PageHeader :title="view === 'projects' ? '项目' : '团队成员'" :description="view === 'projects' ? '查看项目进度、负责人和评审状态。' : '查看团队分工与当前协作状态。'">
            <template #actions><UiBadge>{{ view === 'projects' ? '4 个项目' : '4 位伙伴' }}</UiBadge></template>
          </PageHeader>
          <section v-if="view === 'projects'" class="summary-strip" aria-label="项目概况">
            <div><span>正在推进</span><strong>02<small>个项目</small></strong></div><div><span>等待评审</span><strong>01<small>个项目</small></strong></div><div><span>本月完成</span><strong>01<small>个项目</small></strong></div>
          </section>
          <section class="content-panel" :aria-label="view === 'projects' ? '项目列表' : '团队列表'">
            <div class="section-heading"><h2>{{ view === 'projects' ? '全部项目' : '团队成员' }}</h2><span class="muted">{{ view === 'projects' ? filteredProjects.length : filteredMembers.length }} 项结果</span></div>
            <div class="filter-bar"><UiField v-model="query" label="搜索" type="search" :placeholder="view === 'projects' ? '搜索项目、负责人…' : '搜索姓名、角色…'" />
              <div class="ui-field"><label for="status-filter">状态</label><select id="status-filter" v-model="status"><option>全部状态</option><template v-if="view === 'projects'"><option>进行中</option><option>待评审</option><option>已完成</option></template><template v-else><option>协作中</option><option>休假中</option></template></select></div>
            </div>
            <div v-if="view === 'projects' && filteredProjects.length" class="table-scroll">
              <table><caption class="sr-only">项目进度与负责人</caption><thead><tr><th>项目名称</th><th>负责人</th><th>状态</th><th>进度</th><th>最近更新</th><th><span class="sr-only">操作</span></th></tr></thead>
                <tbody><tr v-for="project in filteredProjects" :key="project.id"><td><button class="project-name" @click="selected = project">{{ project.name }}</button><small class="row-subtitle">{{ project.category }}</small></td><td>{{ project.owner }}</td><td><UiBadge :tone="tone(project.status)">{{ project.status }}</UiBadge></td><td><div class="progress-cell"><progress :value="project.progress" max="100" :aria-label="`${project.name}进度`" /><span>{{ project.progress }}%</span></div></td><td class="muted nowrap">{{ project.updated }}</td><td><UiButton variant="quiet" :aria-label="`查看${project.name}`" @click="selected = project">查看 <UiIcon name="arrow" /></UiButton></td></tr></tbody>
              </table>
            </div>
            <ul v-else-if="view === 'team' && filteredMembers.length" class="member-list"><li v-for="member in filteredMembers" :key="member.id"><span class="avatar" aria-hidden="true">{{ member.initials }}</span><div class="member-info"><strong>{{ member.name }}</strong><small>{{ member.role }}</small></div><span class="member-email muted">{{ member.email }}</span><span class="member-projects muted">{{ member.projects }} 个项目</span><UiBadge :tone="tone(member.status)">{{ member.status }}</UiBadge></li></ul>
            <EmptyState v-else title="没有找到匹配结果" description="试试其他关键词，或清除筛选。"><UiButton @click="resetFilters">清除筛选</UiButton></EmptyState>
          </section>
          <section v-if="selected && view === 'projects'" class="detail-panel" aria-label="项目详情" aria-live="polite"><div class="section-heading"><h2>{{ selected.name }}</h2><UiButton variant="quiet" @click="selected = null">收起详情</UiButton></div><p>{{ selected.description }}</p><div class="detail-meta"><UiBadge :tone="tone(selected.status)">{{ selected.status }}</UiBadge><span>{{ selected.owner }} · {{ selected.category }}</span></div></section>
        </template>
        <template v-else>
          <PageHeader title="组件展示" description="常用控件与状态，一处查看。" />
          <div class="showcase">
            <section class="showcase-section"><h2>按钮与反馈</h2><div class="sample-row"><UiButton variant="primary" @click="notice = '操作已完成'">主要操作</UiButton><UiButton @click="notice = '已选择次要操作'">次要操作</UiButton><UiButton variant="quiet" @click="notice = '已选择轻量操作'">轻量操作</UiButton><UiButton disabled>暂不可用</UiButton><UiButton loading>处理中</UiButton></div><div class="sample-row"><UiBadge tone="brand">进行中</UiBadge><UiBadge tone="warning">待评审</UiBadge><UiBadge tone="danger">需处理</UiBadge><UiBadge>已归档</UiBadge></div></section>
            <section class="showcase-section"><h2>输入与校验</h2><form class="sample-form" @submit.prevent="saveExample"><UiField v-model="sampleName" label="姓名" placeholder="你的名字" hint="在工作空间中显示的名称" /><UiField v-model="sampleEmail" label="邮箱" placeholder="name@example.com" :error="emailError" /><UiButton type="submit" variant="primary">保存示例</UiButton></form></section>
            <section class="showcase-section"><h2>空状态</h2><EmptyState title="暂无项目" description="浏览现有项目，查看团队最近的进展。"><UiButton @click="view = 'projects'">浏览项目</UiButton></EmptyState></section>
          </div>
        </template>
        <p v-if="notice" class="notice" role="status">{{ notice }}</p>
      </main>
    </div>
  </div>
</template>
