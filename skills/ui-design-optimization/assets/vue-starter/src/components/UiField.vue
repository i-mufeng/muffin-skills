<script setup lang="ts">
import { computed, useAttrs, useId } from 'vue'
defineOptions({ inheritAttrs: false })
const props = withDefaults(defineProps<{
  modelValue: string
  label: string
  id?: string
  error?: string
  hint?: string
  type?: 'text' | 'email' | 'search'
}>(), { type: 'text' })
const emit = defineEmits<{ 'update:modelValue': [value: string] }>()
const value = computed({ get: () => props.modelValue, set: (next: string) => emit('update:modelValue', next) })
const attrs = useAttrs()
const generatedId = useId()
const fieldId = computed(() => props.id || generatedId)
// useAttrs is always current but not reactive: read it during each render.
function describedBy() {
  return [...new Set([
    ...String(attrs['aria-describedby'] || '').split(/\s+/).filter(Boolean),
    ...(props.error || props.hint ? [`${fieldId.value}-description`] : []),
  ])].join(' ') || undefined
}
function invalid() {
  return props.error ? true : attrs['aria-invalid'] as boolean | 'true' | 'false' | 'grammar' | 'spelling' | undefined
}
</script>
<template>
  <div class="ui-field">
    <label :for="fieldId">{{ label }}</label>
    <input v-bind="$attrs" :id="fieldId" :type="type" v-model="value"
      :aria-invalid="invalid()" :aria-describedby="describedBy()">
    <small v-if="error || hint" :id="`${fieldId}-description`"
      :class="{ 'field-error': error }" :role="error ? 'alert' : undefined">{{ error || hint }}</small>
  </div>
</template>
