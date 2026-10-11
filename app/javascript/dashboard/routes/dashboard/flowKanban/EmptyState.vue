<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';

// DESIGN.md → Feedback → Empty state: an icon tile, a heading-2 title, one sentence that says
// what to do, and the action when the user may take it (default slot).
defineProps({
  icon: { type: String, required: true },
  title: { type: String, required: true },
  description: { type: String, default: '' },
  // `page` fills a screen or a table area; `compact` sits inside a popover or a panel section.
  size: {
    type: String,
    default: 'page',
    validator: value => ['page', 'compact'].includes(value),
  },
  // A dashed frame, for an area that would otherwise hold content (a chart, a list).
  framed: { type: Boolean, default: false },
  // The heading level that fits the page outline around it.
  titleTag: { type: String, default: 'h3' },
});
</script>

<template>
  <div
    class="flex flex-col items-center text-center"
    :class="[
      size === 'page' ? 'gap-4 px-6 py-16' : 'gap-2 px-6 py-10',
      framed &&
        'rounded-xl outline outline-1 outline-dashed outline-n-container',
    ]"
  >
    <span
      class="flex items-center justify-center rounded-xl bg-n-alpha-2 text-n-slate-11"
      :class="size === 'page' ? 'size-12' : 'size-10'"
    >
      <Icon :icon="icon" :class="size === 'page' ? 'size-6' : 'size-5'" />
    </span>
    <div class="flex flex-col gap-1 max-w-md">
      <component :is="titleTag" class="text-heading-2 text-n-slate-12">
        {{ title }}
      </component>
      <p v-if="description" class="text-body-main text-n-slate-11">
        {{ description }}
      </p>
    </div>
    <slot />
  </div>
</template>
