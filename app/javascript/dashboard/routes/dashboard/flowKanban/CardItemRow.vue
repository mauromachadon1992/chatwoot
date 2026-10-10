<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MoneyInput from './MoneyInput.vue';
import { formatQuantity, parseQuantity } from './money';
import { useFlowKanban } from './useFlowKanban';

// One product line of a deal. Each field is sent when it loses focus, and only if it changed
// and makes sense; otherwise it is flagged and the saved value stays.
const props = defineProps({
  item: { type: Object, required: true },
});

const emit = defineEmits(['update', 'remove']);

const { t, locale } = useI18n();
const { money } = useFlowKanban();

const unitLabel = computed(() => t(`FLOW_KANBAN.UNITS.${props.item.unit}`));
const details = computed(() =>
  [props.item.sku, unitLabel.value].filter(Boolean).join(' · ')
);

const quantity = ref('');
const discount = ref('');
const invalid = ref({ quantity: false, discount: false });

const sync = () => {
  quantity.value = formatQuantity(props.item.quantity, locale.value);
  discount.value = formatQuantity(props.item.discount_percent, locale.value);
  invalid.value = { quantity: false, discount: false };
};
watch(() => props.item, sync, { immediate: true });

const FIELDS = {
  quantity: { text: quantity, valid: value => value > 0 },
  discount: {
    text: discount,
    key: 'discount_percent',
    valid: value => value >= 0 && value <= 100,
  },
};

// Enter confirms the field instead of submitting the card form around it.
const confirmOnEnter = event => {
  event.preventDefault();
  event.target.blur();
};

const commit = name => {
  const field = FIELDS[name];
  const value = parseQuantity(field.text.value);
  const key = field.key || name;
  invalid.value[name] = value === null || !field.valid(value);
  if (invalid.value[name] || value === Number(props.item[key])) return;
  emit('update', { [key]: String(value) });
};
</script>

<template>
  <li class="flex flex-col gap-3 p-3">
    <div class="flex items-start gap-2">
      <div class="flex flex-col flex-1 min-w-0">
        <span class="text-body-main truncate text-n-slate-12">
          {{ item.name }}
        </span>
        <span class="text-label-small truncate text-n-slate-11">
          {{ details }}
        </span>
      </div>
      <span class="pt-0.5 text-label tabular-nums text-n-slate-12">
        {{ money(item.total_cents) }}
      </span>
      <Button
        v-tooltip.top="t('FLOW_KANBAN.VALUE.REMOVE_ITEM')"
        ghost
        slate
        xs
        type="button"
        icon="i-lucide-trash-2"
        class="-me-1"
        :aria-label="t('FLOW_KANBAN.VALUE.REMOVE_ITEM')"
        @click="emit('remove')"
      />
    </div>

    <div
      class="grid grid-cols-[minmax(0,6rem)_minmax(0,1fr)_minmax(0,6rem)] items-end gap-2"
    >
      <label class="flex flex-col gap-1 text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.VALUE.QUANTITY') }} ({{ unitLabel }})
        <Input
          v-model="quantity"
          size="sm"
          inputmode="decimal"
          autocomplete="off"
          custom-input-class="tabular-nums"
          :message-type="invalid.quantity ? 'error' : 'info'"
          @blur="commit('quantity')"
          @keydown.enter="confirmOnEnter"
        />
      </label>
      <label class="flex flex-col gap-1 text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.VALUE.UNIT_PRICE') }}
        <MoneyInput
          :model-value="item.unit_price_cents"
          size="sm"
          @commit="
            cents =>
              cents !== item.unit_price_cents &&
              emit('update', { unit_price_cents: cents ?? 0 })
          "
        />
      </label>
      <label class="flex flex-col gap-1 text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.VALUE.DISCOUNT') }}
        <Input
          v-model="discount"
          size="sm"
          inputmode="decimal"
          autocomplete="off"
          custom-input-class="tabular-nums"
          :message-type="invalid.discount ? 'error' : 'info'"
          @blur="commit('discount')"
          @keydown.enter="confirmOnEnter"
        />
      </label>
    </div>
    <p
      v-if="invalid.quantity || invalid.discount"
      class="text-label-small text-n-ruby-11"
      role="alert"
    >
      {{ t('FLOW_KANBAN.VALUE.ITEM_INVALID') }}
    </p>
  </li>
</template>
