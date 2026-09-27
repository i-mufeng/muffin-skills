<script setup lang="ts">
withDefaults(defineProps<{
  variant?: 'primary' | 'secondary' | 'quiet'
  type?: 'button' | 'submit' | 'reset'
  loading?: boolean
  disabled?: boolean
}>(), { variant: 'secondary', type: 'button', loading: false, disabled: false })
</script>
<template>
  <button :type="type" class="ui-button" :class="`ui-button--${variant}`"
    :disabled="disabled || loading" :aria-busy="loading || undefined">
    <span v-if="loading" aria-hidden="true" class="spinner" />
    <slot />
  </button>
</template>
