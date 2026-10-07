<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';

// A state said three ways (DESIGN.md → The State-Not-Decoration Rule): tone, icon and words.
// The tone only reinforces what the label already says.
defineProps({
  label: { type: String, required: true },
  icon: { type: String, required: true },
  tone: {
    type: String,
    default: 'slate',
    validator: value =>
      ['slate', 'amber', 'ruby', 'teal', 'blue'].includes(value),
  },
});

// Full class names, so Tailwind keeps them.
const TONES = {
  slate: 'bg-n-alpha-2 text-n-slate-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
  ruby: 'bg-n-ruby-3 text-n-ruby-11',
  teal: 'bg-n-teal-3 text-n-teal-11',
  blue: 'bg-n-blue-3 text-n-blue-11',
};
</script>

<template>
  <span
    class="inline-flex items-center gap-1 px-1.5 rounded-md w-fit text-label-small tabular-nums"
    :class="TONES[tone]"
  >
    <Icon :icon="icon" class="flex-shrink-0 size-3.5" />
    {{ label }}
  </span>
</template>
