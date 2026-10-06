<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import SettingsLayout from '../../settings/SettingsLayout.vue';
import BaseSettingsHeader from '../../settings/components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import RequiredComboBox from '../RequiredComboBox.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import ProductDialog from './ProductDialog.vue';
import { useFlowKanban } from '../useFlowKanban';

const { t, locale } = useI18n();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const { money, currency } = useFlowKanban();

const products = ref([]);
const meta = ref({ count: 0, page: 1, per_page: 25 });
const searchQuery = ref('');
const isLoading = ref(true);
const hasLoaded = ref(false);
const productDialogRef = ref(null);
const deleteDialogRef = ref(null);
const productToDelete = ref(null);
const isDeleting = ref(false);
const currencies = ref([]);
const isSavingCurrency = ref(false);

const fetchProducts = async (page = 1) => {
  isLoading.value = true;
  try {
    const { data } = await FlowKanbanAPI.getProducts({
      q: searchQuery.value.trim() || undefined,
      page,
    });
    products.value = data.payload;
    meta.value = data.meta;
  } finally {
    isLoading.value = false;
    hasLoaded.value = true;
  }
};

watch(
  searchQuery,
  useDebounceFn(() => fetchProducts(1), 300)
);

const isCatalogEmpty = computed(
  () => hasLoaded.value && !meta.value.count && !searchQuery.value.trim()
);

const tableHeaders = computed(() => [
  t('FLOW_KANBAN.PRODUCTS.TABLE.NAME'),
  t('FLOW_KANBAN.PRODUCTS.TABLE.UNIT'),
  t('FLOW_KANBAN.PRODUCTS.TABLE.PRICE'),
  t('FLOW_KANBAN.PRODUCTS.TABLE.STATUS'),
  '',
]);

// "Real brasileiro (BRL)": the code stays visible, since it is what the money shows.
const currencyName = code => {
  try {
    const names = new Intl.DisplayNames([locale.value.replace('_', '-')], {
      type: 'currency',
    });
    return `${names.of(code)} (${code})`;
  } catch {
    return code;
  }
};
const currencyOptions = computed(() =>
  currencies.value.map(code => ({ value: code, label: currencyName(code) }))
);

const changeCurrency = async code => {
  if (!code || code === currency.value) return;
  isSavingCurrency.value = true;
  try {
    await FlowKanbanAPI.updateSettings({ currency: code });
    await store.dispatch('accounts/get', {
      silent: true,
      accountId: accountId.value,
    });
    useAlert(t('FLOW_KANBAN.PRODUCTS.CURRENCY.SAVED'));
  } catch {
    useAlert(t('FLOW_KANBAN.ERRORS.GENERIC'));
  } finally {
    isSavingCurrency.value = false;
  }
};

const selectedCurrency = computed({
  get: () => currency.value,
  set: changeCurrency,
});

const unitLabel = unit => t(`FLOW_KANBAN.UNIT_NAMES.${unit}`);

const askDelete = product => {
  productToDelete.value = product;
  deleteDialogRef.value?.open();
};

const confirmDelete = async () => {
  isDeleting.value = true;
  try {
    await FlowKanbanAPI.deleteProduct(productToDelete.value.id);
    deleteDialogRef.value?.close();
    useAlert(t('FLOW_KANBAN.PRODUCTS.DELETED'));
    const lastOnPage = products.value.length === 1 && meta.value.page > 1;
    await fetchProducts(lastOnPage ? meta.value.page - 1 : meta.value.page);
  } catch {
    useAlert(t('FLOW_KANBAN.ERRORS.GENERIC'));
  } finally {
    isDeleting.value = false;
  }
};

onMounted(async () => {
  fetchProducts(1);
  const { data } = await FlowKanbanAPI.getSettings();
  currencies.value = data.payload.currencies;
});
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading && !hasLoaded"
    :loading-message="t('FLOW_KANBAN.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="t('FLOW_KANBAN.PRODUCTS.HEADER')"
        :description="t('FLOW_KANBAN.PRODUCTS.DESCRIPTION')"
        :search-placeholder="t('FLOW_KANBAN.PRODUCTS.SEARCH')"
      >
        <template v-if="meta.count" #count>
          <span class="text-body-main text-n-slate-11">
            {{ t('FLOW_KANBAN.PRODUCTS.COUNT', { n: meta.count }, meta.count) }}
          </span>
        </template>
        <template #actions>
          <Button
            :label="t('FLOW_KANBAN.PRODUCTS.NEW')"
            icon="i-lucide-plus"
            size="sm"
            @click="productDialogRef?.open()"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #preBody>
      <div
        class="flex flex-wrap items-center justify-between gap-x-6 gap-y-3 py-4 mb-2 border-b border-n-weak"
      >
        <div class="flex flex-col gap-0.5 max-w-xl">
          <span class="text-heading-3 text-n-slate-12">
            {{ t('FLOW_KANBAN.PRODUCTS.CURRENCY.LABEL') }}
          </span>
          <span class="text-label-small text-n-slate-11">
            {{ t('FLOW_KANBAN.PRODUCTS.CURRENCY.HINT') }}
          </span>
        </div>
        <div class="w-full sm:w-64">
          <RequiredComboBox
            v-model="selectedCurrency"
            :options="currencyOptions"
            :disabled="isSavingCurrency || !currencyOptions.length"
          />
        </div>
      </div>
    </template>

    <template #body>
      <div
        v-if="isCatalogEmpty"
        class="flex flex-col items-center gap-4 px-6 py-16 text-center"
      >
        <span
          class="flex items-center justify-center rounded-xl size-12 bg-n-alpha-2 text-n-slate-11"
        >
          <Icon icon="i-lucide-package" class="size-6" />
        </span>
        <div class="flex flex-col gap-1 max-w-md">
          <h2 class="text-heading-2 text-n-slate-12">
            {{ t('FLOW_KANBAN.PRODUCTS.EMPTY_TITLE') }}
          </h2>
          <p class="text-body-main text-n-slate-11">
            {{ t('FLOW_KANBAN.PRODUCTS.EMPTY_BODY') }}
          </p>
        </div>
        <Button
          solid
          blue
          sm
          icon="i-lucide-plus"
          :label="t('FLOW_KANBAN.PRODUCTS.NEW')"
          @click="productDialogRef?.open()"
        />
      </div>

      <div
        v-else
        class="flex flex-col transition-opacity duration-150"
        :class="{ 'opacity-60': isLoading }"
        :aria-busy="isLoading"
      >
        <BaseTable
          :headers="tableHeaders"
          :items="products"
          :loading="isLoading"
          :no-data-message="
            t('FLOW_KANBAN.PRODUCTS.NO_RESULTS', { query: searchQuery.trim() })
          "
        >
          <template #header-2="{ header }">
            <span class="block text-end">{{ header }}</span>
          </template>
          <template #row="{ items }">
            <BaseTableRow
              v-for="product in items"
              :key="product.id"
              :item="product"
            >
              <BaseTableCell>
                <div class="flex flex-col min-w-0">
                  <span class="text-body-main text-n-slate-12">
                    {{ product.name }}
                  </span>
                  <span
                    v-if="product.sku"
                    class="text-label-small text-n-slate-11"
                  >
                    {{ product.sku }}
                  </span>
                </div>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-11">
                  {{ unitLabel(product.unit) }}
                </span>
              </BaseTableCell>
              <BaseTableCell align="end">
                <span class="text-body-main tabular-nums text-n-slate-12">
                  {{ money(product.price_cents) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span
                  class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-md text-label-small"
                  :class="
                    product.active
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-alpha-2 text-n-slate-11'
                  "
                >
                  <Icon
                    :icon="
                      product.active
                        ? 'i-lucide-circle-check'
                        : 'i-lucide-circle-pause'
                    "
                    class="size-3.5"
                  />
                  {{
                    product.active
                      ? t('FLOW_KANBAN.PRODUCTS.ACTIVE')
                      : t('FLOW_KANBAN.PRODUCTS.INACTIVE')
                  }}
                </span>
              </BaseTableCell>
              <BaseTableCell align="end">
                <div class="flex justify-end gap-1">
                  <Button
                    v-tooltip.top="t('FLOW_KANBAN.PRODUCTS.EDIT')"
                    ghost
                    slate
                    sm
                    icon="i-lucide-pencil"
                    :aria-label="t('FLOW_KANBAN.PRODUCTS.EDIT')"
                    @click="productDialogRef?.open(product)"
                  />
                  <Button
                    v-tooltip.top="t('FLOW_KANBAN.PRODUCTS.DELETE')"
                    ghost
                    ruby
                    sm
                    icon="i-lucide-trash-2"
                    :aria-label="t('FLOW_KANBAN.PRODUCTS.DELETE')"
                    @click="askDelete(product)"
                  />
                </div>
              </BaseTableCell>
            </BaseTableRow>
          </template>
        </BaseTable>
        <PaginationFooter
          v-if="meta.count > meta.per_page"
          :current-page="meta.page"
          :total-items="meta.count"
          :items-per-page="meta.per_page"
          class="mt-4"
          @update:current-page="fetchProducts"
        />
      </div>
    </template>

    <ProductDialog ref="productDialogRef" @saved="fetchProducts(meta.page)" />
    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('FLOW_KANBAN.PRODUCTS.DELETE')"
      :description="
        t('FLOW_KANBAN.PRODUCTS.DELETE_CONFIRM', {
          name: productToDelete?.name || '',
        })
      "
      :confirm-button-label="t('FLOW_KANBAN.PRODUCTS.DELETE')"
      :is-loading="isDeleting"
      @confirm="confirmDelete"
    />
  </SettingsLayout>
</template>
