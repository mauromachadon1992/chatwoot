<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';

// Two to four options that all stay visible (DESIGN.md → Inputs): the same radio group the
// stage type uses in the board settings, with text instead of icons.
defineProps({
  modelValue: { type: [String, Number], default: '' },
  options: { type: Array, required: true },
  ariaLabel: { type: String, default: '' },
});

defineEmits(['update:modelValue']);
</script>

<template>
  <ButtonGroup
    role="radiogroup"
    :aria-label="ariaLabel || undefined"
    class="flex items-center gap-0.5 p-0.5 rounded-lg bg-n-alpha-1"
  >
    <Button
      v-for="option in options"
      :key="option.value"
      ghost
      xs
      type="button"
      role="radio"
      class="flex-1 min-w-0"
      :aria-checked="modelValue === option.value"
      :label="option.label"
      :color="modelValue === option.value ? 'blue' : 'slate'"
      :class="{ 'bg-n-solid-1 shadow-sm': modelValue === option.value }"
      @click="$emit('update:modelValue', option.value)"
    />
  </ButtonGroup>
</template>
