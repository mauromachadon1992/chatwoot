<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import { parseMoney, formatPlainMoney } from './money';
import { useFlowKanban } from './useFlowKanban';

// Chatwoot's Input for a money value in cents. While focused it holds the plain number the
// agent types, in either decimal style; on blur it is read back into cents and shown in the
// account currency. Text that is not a number is kept and flagged, never silently dropped.
const props = defineProps({
  modelValue: { type: Number, default: null },
  label: { type: String, default: '' },
  placeholder: { type: String, default: '' },
  message: { type: String, default: '' },
  invalidMessage: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  size: { type: String, default: 'md' },
});

const emit = defineEmits(['update:modelValue', 'commit']);

const { locale } = useI18n();
const { money } = useFlowKanban();

const display = cents => (cents === null ? '' : money(cents));
const text = ref(display(props.modelValue));
const isInvalid = ref(false);

watch(
  () => props.modelValue,
  value => {
    if (!isInvalid.value) text.value = display(value);
  }
);

const onFocus = () => {
  if (props.modelValue !== null && !isInvalid.value) {
    text.value = formatPlainMoney(props.modelValue, locale.value);
  }
};

// Enter confirms the field instead of submitting a surrounding form.
const confirmOnEnter = event => {
  event.preventDefault();
  event.target.blur();
};

const onBlur = () => {
  const cents = text.value.trim() === '' ? null : parseMoney(text.value);
  isInvalid.value = text.value.trim() !== '' && (cents === null || cents < 0);
  if (isInvalid.value) return;
  emit('update:modelValue', cents);
  emit('commit', cents);
  text.value = display(cents);
};
</script>

<template>
  <Input
    v-model="text"
    :label="label"
    :placeholder="placeholder || money(0)"
    :size="size"
    :disabled="disabled"
    inputmode="decimal"
    autocomplete="off"
    custom-input-class="tabular-nums"
    :message="isInvalid ? invalidMessage : message"
    :message-type="isInvalid ? 'error' : 'info'"
    @focus="onFocus"
    @blur="onBlur"
    @keydown.enter="confirmOnEnter"
  />
</template>
