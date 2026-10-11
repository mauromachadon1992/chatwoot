<script setup>
import { computed } from 'vue';

// DESIGN.md → Feedback → Loading: skeleton rows (`bg-n-alpha-2 animate-pulse`), never a spinner
// in the middle of content. Hidden from assistive technology; the container says it is busy.
const props = defineProps({
  rows: { type: Number, default: 2 },
  // The height of each row, or one height per row when the shapes differ (`['h-10', 'h-24']`).
  height: { type: [String, Array], default: 'h-10' },
});

const heights = computed(() =>
  Array.isArray(props.height)
    ? props.height
    : Array.from({ length: props.rows }, () => props.height)
);
</script>

<template>
  <div class="flex flex-col gap-2" aria-hidden="true">
    <div
      v-for="(rowHeight, index) in heights"
      :key="index"
      class="rounded-lg bg-n-alpha-2 animate-pulse"
      :class="rowHeight"
    />
  </div>
</template>
