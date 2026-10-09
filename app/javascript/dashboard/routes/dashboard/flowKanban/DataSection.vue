<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import Button from 'dashboard/components-next/button/Button.vue';
import ImportDialog from './ImportDialog.vue';
import RequiredComboBox from './RequiredComboBox.vue';
import { filenameFrom, saveBlob } from './csv';

// Settings → Kanban → Data: the catalog and a board's deals, out as CSV and in from CSV.
// Administrators only (the settings route). Deals are exported here without filters; the
// board's own toolbar exports what its filters show.
const { t } = useI18n();
const kanban = useFlowKanbanStore();

const boardId = ref('');
const exporting = ref('');
const productsDialogRef = ref(null);
const dealsDialogRef = ref(null);

const boardOptions = computed(() =>
  kanban.boards.map(board => ({ value: board.id, label: board.name }))
);

const fail = error =>
  useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));

const download = async (key, request, fallback) => {
  if (exporting.value) return;
  exporting.value = key;
  try {
    const response = await request();
    saveBlob(
      response.data,
      filenameFrom(response.headers['content-disposition'], fallback)
    );
  } catch (error) {
    fail(error);
  } finally {
    exporting.value = '';
  }
};

const exportProducts = () =>
  download('products', () => FlowKanbanAPI.exportProducts(), 'products.csv');
const exportDeals = () =>
  download(
    'deals',
    () => FlowKanbanAPI.exportDeals(boardId.value),
    'deals.csv'
  );

const productsImported = () =>
  useAlert(t('FLOW_KANBAN.SETTINGS.DATA.PRODUCTS_IMPORTED'));
const dealsImported = async () => {
  useAlert(t('FLOW_KANBAN.SETTINGS.DATA.DEALS_IMPORTED'));
  await kanban.refreshActiveBoard?.();
};

onMounted(async () => {
  if (!kanban.boards.length) await kanban.fetchBoards();
  boardId.value = kanban.activeBoardId || kanban.boards[0]?.id || '';
});
</script>

<template>
  <section class="flex flex-col gap-4" aria-labelledby="flow-data-title">
    <div class="flex flex-col gap-1">
      <h2 id="flow-data-title" class="text-heading-1 text-n-slate-12">
        {{ t('FLOW_KANBAN.SETTINGS.DATA.TITLE') }}
      </h2>
      <p class="text-body-main text-n-slate-11">
        {{ t('FLOW_KANBAN.SETTINGS.DATA.DESCRIPTION') }}
      </p>
    </div>

    <div
      class="flex flex-col gap-3 p-4 rounded-lg outline outline-1 outline-n-container bg-n-solid-1"
    >
      <div class="flex flex-col gap-1">
        <h3 class="text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.SETTINGS.DATA.PRODUCTS') }}
        </h3>
        <p class="text-label-small text-n-slate-11">
          {{ t('FLOW_KANBAN.SETTINGS.DATA.PRODUCTS_HINT') }}
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          faded
          slate
          sm
          type="button"
          icon="i-lucide-download"
          :label="t('FLOW_KANBAN.SETTINGS.DATA.EXPORT')"
          :is-loading="exporting === 'products'"
          :disabled="!!exporting"
          @click="exportProducts"
        />
        <Button
          faded
          blue
          sm
          type="button"
          icon="i-lucide-upload"
          :label="t('FLOW_KANBAN.SETTINGS.DATA.IMPORT')"
          @click="productsDialogRef?.open()"
        />
      </div>
    </div>

    <div
      class="flex flex-col gap-3 p-4 rounded-lg outline outline-1 outline-n-container bg-n-solid-1"
    >
      <div class="flex flex-col gap-1">
        <h3 class="text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.SETTINGS.DATA.DEALS') }}
        </h3>
        <p class="text-label-small text-n-slate-11">
          {{ t('FLOW_KANBAN.SETTINGS.DATA.DEALS_HINT') }}
        </p>
      </div>
      <label
        class="flex flex-col gap-1.5 text-label-small text-n-slate-11 sm:max-w-sm"
      >
        {{ t('FLOW_KANBAN.SETTINGS.DATA.BOARD') }}
        <RequiredComboBox v-model="boardId" :options="boardOptions" />
      </label>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          faded
          slate
          sm
          type="button"
          icon="i-lucide-download"
          :label="t('FLOW_KANBAN.SETTINGS.DATA.EXPORT')"
          :is-loading="exporting === 'deals'"
          :disabled="!boardId || !!exporting"
          @click="exportDeals"
        />
        <Button
          faded
          blue
          sm
          type="button"
          icon="i-lucide-upload"
          :label="t('FLOW_KANBAN.SETTINGS.DATA.IMPORT')"
          :disabled="!boardId"
          @click="dealsDialogRef?.open()"
        />
      </div>
    </div>
  </section>

  <ImportDialog
    ref="productsDialogRef"
    kind="products"
    @imported="productsImported"
  />
  <ImportDialog
    ref="dealsDialogRef"
    kind="deals"
    :board-id="boardId"
    @imported="dealsImported"
  />
</template>
