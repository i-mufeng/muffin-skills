import { afterEach, describe, expect, it } from 'vitest'
import { mount, enableAutoUnmount } from '@vue/test-utils'
import App from './App.vue'
import UiButton from './components/UiButton.vue'
import UiField from './components/UiField.vue'
enableAutoUnmount(afterEach)
afterEach(() => { delete document.documentElement.dataset.theme })
describe('reusable controls', () => {
  it('blocks interaction while loading and defaults to a non-submit button', async () => {
    const wrapper = mount(UiButton, { props: { loading: true }, slots: { default: '保存' } })
    expect(wrapper.attributes('type')).toBe('button')
    expect(wrapper.attributes('aria-busy')).toBe('true')
    await wrapper.trigger('click')
    expect(wrapper.emitted('click')).toBeUndefined()
  })
  it('keeps label and error associations stable while the value changes', async () => {
    const wrapper = mount(UiField, { props: { modelValue: '', label: '邮箱', error: '请填写邮箱' } })
    const input = wrapper.get('input')
    const id = input.attributes('id')
    expect(wrapper.get('label').attributes('for')).toBe(id)
    expect(input.attributes('aria-describedby')).toBe(`${id}-description`)
    expect(wrapper.get('[role="alert"]').attributes('id')).toBe(`${id}-description`)
    await input.setValue('team@example.com')
    expect(wrapper.emitted('update:modelValue')?.[0]).toEqual(['team@example.com'])
    await wrapper.setProps({ modelValue: 'team@example.com', error: undefined })
    expect(input.attributes('id')).toBe(id)
    expect(input.attributes('aria-invalid')).toBeUndefined()
  })
})
describe('field composition', () => {
  it('waits for Chinese IME composition to finish before updating v-model', async () => {
    const wrapper = mount(UiField, { props: { modelValue: '', label: '姓名' } })
    const input = wrapper.get('input')
    await input.trigger('compositionstart')
    ;(input.element as HTMLInputElement).value = 'lin'
    await input.trigger('input')
    expect(wrapper.emitted('update:modelValue')).toBeUndefined()
    ;(input.element as HTMLInputElement).value = '林'
    await input.trigger('compositionend')
    expect(wrapper.emitted('update:modelValue')).toEqual([['林']])
  })

  it('merges external descriptions and preserves caller invalid state after internal error clears', async () => {
    const wrapper = mount(UiField, {
      props: { id: 'email', modelValue: '', label: '邮箱', error: '请填写邮箱' },
      attrs: { 'aria-describedby': 'privacy-note', 'aria-invalid': 'spelling' },
    })
    expect(wrapper.get('input').attributes('aria-describedby')).toBe('privacy-note email-description')
    expect(wrapper.get('input').attributes('aria-invalid')).toBe('true')
    await wrapper.setProps({ error: undefined })
    expect(wrapper.get('input').attributes('aria-describedby')).toBe('privacy-note')
    expect(wrapper.get('input').attributes('aria-invalid')).toBe('spelling')
  })
})
describe('workbench behavior', () => {
  it('filters projects, recovers from an empty result, and opens the selected detail', async () => {
    const wrapper = mount(App)
    await wrapper.get('input[type="search"]').setValue('不存在的项目')
    expect(wrapper.text()).toContain('没有找到匹配结果')
    const reset = wrapper.findAll('button').find(button => button.text() === '清除筛选')!
    await reset.trigger('click')
    expect(wrapper.findAll('tbody tr')).toHaveLength(4)
    await wrapper.get('select').setValue('待评审')
    expect(wrapper.findAll('tbody tr')).toHaveLength(1)
    await wrapper.get('.project-name').trigger('click')
    expect(wrapper.get('[aria-label="项目详情"]').text()).toContain('路线发现、收藏与行程分享')
  })
  it('resets filters on navigation, filters team members, and switches theme', async () => {
    const wrapper = mount(App)
    await wrapper.get('input[type="search"]').setValue('旧搜索')
    await wrapper.findAll('nav button')[1]!.trigger('click')
    expect((wrapper.get('input').element as HTMLInputElement).value).toBe('')
    await wrapper.get('select').setValue('休假中')
    expect(wrapper.findAll('.member-list li')).toHaveLength(1)
    expect(wrapper.get('.member-list').text()).toContain('周以宁')
    await wrapper.get('[aria-pressed]').trigger('click')
    expect(document.documentElement.dataset.theme).toBe('dark')
  })
  it('shows form errors, accepts corrected input, and announces success', async () => {
    const wrapper = mount(App)
    await wrapper.findAll('nav button')[2]!.trigger('click')
    await wrapper.get('form').trigger('submit')
    expect(wrapper.get('[role="alert"]').text()).toContain('有效的邮箱')
    await wrapper.get('input[placeholder="name@example.com"]').setValue('team@example.com')
    await wrapper.get('form').trigger('submit')
    expect(wrapper.find('[role="alert"]').exists()).toBe(false)
    expect(wrapper.get('[role="status"]').text()).toContain('已保存')
  })
})
