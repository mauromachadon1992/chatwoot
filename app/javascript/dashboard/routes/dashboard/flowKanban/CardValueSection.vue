<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CardItemRow from './CardItemRow.vue';
import QuoteDialog from './QuoteDialog.vue';
import MoneyInput from './MoneyInput.vue';
import { useFlowKanban } from './useFlowKanban';

// The deal's value: typed while it has no products, the sum of its product lines once it
// has some. Every change here saves at once and updates the board.
const props = defineProps({
  card: { type: Object, required: true },
});

const emit = defineEmits(['update:card']);

const { t } = useI18n();
const kanban = useFlowKanbanStore();
const { isAdmin } = useAdmin();
const accountId = useMapGetter('getCurrentAccountId');
const { money } = useFlowKanban();

const productOptions = ref([]);
const productPick = ref('');
const catalogIsEmpty = ref(false);
const isAdding = ref(false);
const quoteDialogRef = ref(null);

const hasItems = computed(() => props.card.items?.length > 0);
const productsPath = computed(() =>
  frontendURL(`accounts/${accountId.value}/settings/products`)
);

const toOption = product => ({
  value: product.id,
  label: [product.name, product.sku].filter(Boolean).join(' · '),
});

const searchProducts = async (query = '') => {
  const { data } = await FlowKanbanAPI.getProducts({ q: query, active: true });
  productOptions.value = data.payload.map(toOption);
  if (!query) catalogIsEmpty.value = data.meta.count === 0;
};
const onSearch = useDebounceFn(query => searchProducts(query?.trim()), 250);

const apply = payload => {
  kanban.upsertCard(payload);
  emit('update:card', payload);
};

const run = async request => {
  try {
    const { data } = await request();
    apply(data.payload);
    return true;
  } catch {
    useAlert(t('FLOW_KANBAN.VALUE.ITEM_INVALID'));
    return false;
  }
};

const saveValue = cents => {
  if ((cents ?? 0) === props.card.value_cents) return;
  run(() =>
    FlowKanbanAPI.updateCard(props.card.id, { value_cents: cents ?? 0 })
  );
};

const addProduct = async productId => {
  if (!productId) return;
  isAdding.value = true;
  await run(() =>
    FlowKanbanAPI.addCardItem(props.card.id, { product_id: productId })
  );
  productPick.value = '';
  isAdding.value = false;
};

const updateItem = (item, changes) =>
  run(() => FlowKanbanAPI.updateCardItem(props.card.id, item.id, changes));

const removeItem = item =>
  run(() => FlowKanbanAPI.removeCardItem(props.card.id, item.id));

onMounted(() => searchProducts());
</script>

<template>
  <section class="flex flex-col gap-3">
    <div class="flex items-baseline justify-between gap-3">
      <h4 class="text-heading-3 text-n-slate-12">
        {{ t('FLOW_KANBAN.VALUE.SECTION') }}
      </h4>
      <span class="text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.VALUE.ITEMS_AUTOSAVE') }}
      </span>
    </div>

    <MoneyInput
      v-if="!hasItems"
      :model-value="card.value_cents"
      :label="t('FLOW_KANBAN.VALUE.AMOUNT')"
      :message="t('FLOW_KANBAN.VALUE.AMOUNT_HINT')"
      :invalid-message="t('FLOW_KANBAN.VALUE.INVALID')"
      @commit="saveValue"
    />

    <template v-else>
      <ul
        class="flex flex-col rounded-lg outline outline-1 outline-n-container divide-y divide-n-weak"
      >
        <CardItemRow
          v-for="item in card.items"
          :key="item.id"
          :item="item"
          @update="updateItem(item, $event)"
          @remove="removeItem(item)"
        />
      </ul>
      <div class="flex items-baseline justify-between gap-3 px-1">
        <span class="text-label-small text-n-slate-11">
          {{ t('FLOW_KANBAN.VALUE.FROM_ITEMS') }}
        </span>
        <span class="flex items-baseline gap-2 flex-shrink-0">
          <span class="text-label text-n-slate-11">
            {{ t('FLOW_KANBAN.VALUE.TOTAL') }}
          </span>
          <span class="text-heading-2 tabular-nums text-n-slate-12">
            {{ money(card.value_cents) }}
          </span>
        </span>
      </div>
    </template>

    <div v-if="hasItems" class="flex items-center gap-2 flex-wrap">
      <Button
        faded
        blue
        sm
        type="button"
        icon="i-lucide-file-text"
        :label="t('FLOW_KANBAN.QUOTE.BUTTON')"
        @click="quoteDialogRef?.open()"
      />
      <span class="text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.QUOTE.BUTTON_HINT') }}
      </span>
    </div>

    <div v-if="catalogIsEmpty" class="flex items-center gap-2 flex-wrap">
      <span class="text-body-main text-n-slate-11">
        {{
          isAdmin
            ? t('FLOW_KANBAN.VALUE.EMPTY_CATALOG_ADMIN')
            : t('FLOW_KANBAN.VALUE.EMPTY_CATALOG_AGENT')
        }}
      </span>
      <router-link v-if="isAdmin" :to="productsPath">
        <Button
          link
          blue
          sm
          type="button"
          :label="t('FLOW_KANBAN.VALUE.MANAGE_PRODUCTS')"
        />
      </router-link>
    </div>
    <ComboBox
      v-else
      v-model="productPick"
      :options="productOptions"
      :placeholder="t('FLOW_KANBAN.VALUE.ADD_PRODUCT')"
      :search-placeholder="t('FLOW_KANBAN.VALUE.SEARCH_PRODUCT')"
      :empty-state="t('FLOW_KANBAN.VALUE.NO_PRODUCTS')"
      :disabled="isAdding"
      use-api-results
      @search="onSearch"
      @update:model-value="addProduct"
    />

    <QuoteDialog ref="quoteDialogRef" :card="card" />
  </section>
</template>
