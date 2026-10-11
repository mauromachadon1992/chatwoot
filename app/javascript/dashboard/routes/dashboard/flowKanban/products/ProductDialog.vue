<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import RequiredComboBox from '../RequiredComboBox.vue';
import MoneyInput from '../MoneyInput.vue';

const emit = defineEmits(['saved']);

// Mirrors Custom::Kanban::Product::UNITS.
const UNITS = [
  'un',
  'm',
  'm2',
  'm3',
  'kg',
  't',
  'l',
  'cx',
  'pc',
  'sc',
  'par',
  'kit',
  'h',
  'srv',
];

const { t } = useI18n();

const dialogRef = ref(null);
const productId = ref(null);
const form = ref({});
const showErrors = ref(false);
const isSaving = ref(false);

const unitOptions = computed(() =>
  UNITS.map(unit => ({
    value: unit,
    label: `${t(`FLOW_KANBAN.UNIT_NAMES.${unit}`)} (${t(`FLOW_KANBAN.UNITS.${unit}`)})`,
  }))
);
const nameMissing = computed(() => !form.value.name?.trim());

const open = (product = null) => {
  productId.value = product?.id || null;
  form.value = {
    name: product?.name || '',
    sku: product?.sku || '',
    unit: product?.unit || 'un',
    price_cents: product?.price_cents ?? null,
    active: product?.active ?? true,
  };
  showErrors.value = false;
  dialogRef.value?.open();
};

const save = async () => {
  showErrors.value = true;
  if (nameMissing.value) return;
  isSaving.value = true;
  const payload = {
    ...form.value,
    name: form.value.name.trim(),
    sku: form.value.sku.trim() || null,
    price_cents: form.value.price_cents ?? 0,
  };
  try {
    const { data } = productId.value
      ? await FlowKanbanAPI.updateProduct(productId.value, payload)
      : await FlowKanbanAPI.createProduct(payload);
    dialogRef.value?.close();
    useAlert(
      t(
        productId.value
          ? 'FLOW_KANBAN.PRODUCTS.FORM.SAVED'
          : 'FLOW_KANBAN.PRODUCTS.FORM.CREATED'
      )
    );
    emit('saved', data.payload);
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      productId
        ? t('FLOW_KANBAN.PRODUCTS.FORM.EDIT_TITLE')
        : t('FLOW_KANBAN.PRODUCTS.FORM.CREATE_TITLE')
    "
    :confirm-button-label="
      productId
        ? t('FLOW_KANBAN.PRODUCTS.FORM.SAVE')
        : t('FLOW_KANBAN.PRODUCTS.FORM.CREATE')
    "
    :is-loading="isSaving"
    width="md"
    overflow-y-auto
    @confirm="save"
  >
    <form class="flex flex-col gap-4" @submit.prevent="save">
      <Input
        v-model="form.name"
        :label="t('FLOW_KANBAN.PRODUCTS.FORM.NAME')"
        :placeholder="t('FLOW_KANBAN.PRODUCTS.FORM.NAME_PLACEHOLDER')"
        :message="
          showErrors && nameMissing
            ? t('FLOW_KANBAN.PRODUCTS.FORM.NAME_REQUIRED')
            : ''
        "
        :message-type="showErrors && nameMissing ? 'error' : 'info'"
        maxlength="160"
        autofocus
      />
      <div class="grid grid-cols-2 gap-4">
        <Input
          v-model="form.sku"
          :label="t('FLOW_KANBAN.PRODUCTS.FORM.SKU')"
          :placeholder="t('FLOW_KANBAN.PRODUCTS.FORM.SKU_PLACEHOLDER')"
          maxlength="60"
        />
        <MoneyInput
          v-model="form.price_cents"
          :label="t('FLOW_KANBAN.PRODUCTS.FORM.PRICE')"
          :invalid-message="t('FLOW_KANBAN.PRODUCTS.FORM.PRICE_INVALID')"
        />
      </div>
      <label class="flex flex-col gap-1.5 text-heading-3 text-n-slate-12">
        {{ t('FLOW_KANBAN.PRODUCTS.FORM.UNIT') }}
        <RequiredComboBox v-model="form.unit" :options="unitOptions" />
      </label>
      <div class="flex items-start justify-between gap-4 pt-1">
        <label for="flow-product-active" class="flex flex-col gap-0.5">
          <span class="text-heading-3 text-n-slate-12">
            {{ t('FLOW_KANBAN.PRODUCTS.FORM.ACTIVE') }}
          </span>
          <span class="text-label-small text-n-slate-11">
            {{ t('FLOW_KANBAN.PRODUCTS.FORM.ACTIVE_HINT') }}
          </span>
        </label>
        <Switch id="flow-product-active" v-model="form.active" class="mt-0.5" />
      </div>
    </form>
  </Dialog>
</template>
