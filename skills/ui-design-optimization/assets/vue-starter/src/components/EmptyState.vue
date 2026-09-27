<script setup lang="ts">
import UiIcon from './UiIcon.vue'
defineProps<{ title: string; description?: string }>()
</script>
<template><div class="empty-state"><span class="empty-symbol"><UiIcon name="search" /></span>
  <h2>{{ title }}</h2><p v-if="description">{{ description }}</p><slot />
</div></template>
