<script setup>
import { ref } from 'vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

// Chatwoot's ComboBox clears the value when the selected option is clicked again. For a
// field that must always hold a value (a stage, a board) that click is ignored: the
// ComboBox is remounted so it shows the current value again.
defineProps({
  modelValue: { type: [String, Number], default: '' },
});

const emit = defineEmits(['update:modelValue']);
const resetKey = ref(0);

const onUpdate = value => {
  if (value === '' || value === null || value === undefined) {
    resetKey.value += 1;
    return;
  }
  emit('update:modelValue', value);
};
</script>

<template>
  <ComboBox
    :key="resetKey"
    :model-value="modelValue"
    @update:model-value="onUpdate"
  />
</template>
