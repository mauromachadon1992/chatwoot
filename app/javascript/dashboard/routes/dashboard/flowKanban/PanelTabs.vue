<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { nextTabIndex, panelId, tabId } from './panelTabs';

// The tab row of a side panel (DESIGN.md → Tabs): a real tablist with the keyboard model of the
// pattern, a count pill where a number says what is behind the tab, and a row that scrolls
// sideways instead of squeezing the labels on a phone. The panels belong to the caller: each is
// `role="tabpanel"` with `id` `panelId(prefix, id)` and `aria-labelledby` `tabId(prefix, id)`.
const props = defineProps({
  modelValue: { type: String, required: true },
  tabs: { type: Array, required: true },
  idPrefix: { type: String, default: 'flow-tabs' },
  ariaLabel: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);

const { locale } = useI18n();
const tabRefs = ref({});

const rtl = computed(() => ['ar', 'he', 'fa', 'ur'].includes(locale.value));
const currentIndex = computed(() =>
  Math.max(
    0,
    props.tabs.findIndex(tab => tab.id === props.modelValue)
  )
);

const select = tab => emit('update:modelValue', tab.id);

const onKeydown = event => {
  const index = nextTabIndex(
    event.key,
    currentIndex.value,
    props.tabs.length,
    rtl.value
  );
  if (index === null) return;
  event.preventDefault();
  const tab = props.tabs[index];
  select(tab);
  // The Button is a component: its root element is the real <button>.
  tabRefs.value[tab.id]?.$el?.focus();
};
</script>

<template>
  <div
    role="tablist"
    :aria-label="ariaLabel || undefined"
    class="flex items-end gap-1 overflow-x-auto border-b border-n-weak"
    @keydown="onKeydown"
  >
    <Button
      v-for="tab in tabs"
      :id="tabId(idPrefix, tab.id)"
      :key="tab.id"
      :ref="el => (tabRefs[tab.id] = el)"
      ghost
      sm
      type="button"
      role="tab"
      :aria-selected="modelValue === tab.id"
      :aria-controls="panelId(idPrefix, tab.id)"
      :tabindex="modelValue === tab.id ? 0 : -1"
      :color="modelValue === tab.id ? 'blue' : 'slate'"
      class="relative flex-shrink-0 rounded-b-none !px-2.5 after:absolute after:inset-x-2 after:-bottom-px after:h-0.5 after:rounded-full after:transition-colors"
      :class="
        modelValue === tab.id
          ? 'after:bg-n-brand !text-n-slate-12'
          : 'after:bg-transparent !text-n-slate-11'
      "
      @click="select(tab)"
    >
      <span class="truncate">{{ tab.label }}</span>
      <span
        v-if="tab.count"
        class="px-1.5 rounded-md bg-n-alpha-2 tabular-nums text-label-small text-n-slate-11"
      >
        {{ tab.count }}
      </span>
    </Button>
  </div>
</template>
