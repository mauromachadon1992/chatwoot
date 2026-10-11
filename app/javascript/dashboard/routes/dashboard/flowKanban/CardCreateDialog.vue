<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';
import ContactAPI from 'dashboard/api/contacts';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import RequiredComboBox from './RequiredComboBox.vue';

const { t } = useI18n();
const kanban = useFlowKanbanStore();
const agents = useMapGetter('agents/getAgents');

const dialogRef = ref(null);
const isSaving = ref(false);
const contactOptions = ref([]);
const form = ref({ stage_id: '', contact_id: '', title: '', assignee_id: '' });

const stageOptions = computed(() =>
  kanban.stages.map(stage => ({ value: stage.id, label: stage.name }))
);
const assigneeOptions = computed(() => [
  { value: '', label: t('FLOW_KANBAN.CARD_FORM.NO_ASSIGNEE') },
  ...agents.value.map(agent => ({ value: agent.id, label: agent.name })),
]);
const selectedContactLabel = computed(
  () =>
    contactOptions.value.find(option => option.value === form.value.contact_id)
      ?.label || ''
);

const searchContacts = useDebounceFn(async query => {
  if (!query?.trim()) return;
  const { data } = await ContactAPI.search(query.trim());
  contactOptions.value = data.payload.map(contact => ({
    value: contact.id,
    label: [contact.name, contact.phone_number || contact.email]
      .filter(Boolean)
      .join(' · '),
  }));
}, 300);

const open = stageId => {
  form.value = {
    stage_id: stageId || kanban.stages[0]?.id || '',
    contact_id: '',
    title: '',
    assignee_id: '',
  };
  contactOptions.value = [];
  dialogRef.value?.open();
};

const create = async () => {
  if (!form.value.contact_id || !form.value.stage_id) return;
  isSaving.value = true;
  try {
    await kanban.createCard({
      stage_id: form.value.stage_id,
      contact_id: form.value.contact_id,
      title: form.value.title.trim() || undefined,
      assignee_id: form.value.assignee_id || undefined,
    });
    dialogRef.value?.close();
    useAlert(t('FLOW_KANBAN.CARD_FORM.CREATED'));
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
    :title="t('FLOW_KANBAN.CARD_FORM.CREATE_TITLE')"
    :confirm-button-label="t('FLOW_KANBAN.CARD_FORM.CREATE')"
    :disable-confirm-button="!form.contact_id || !form.stage_id"
    :is-loading="isSaving"
    width="md"
    overflow-y-auto
    @confirm="create"
  >
    <div class="flex flex-col gap-4">
      <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
        {{ t('FLOW_KANBAN.CARD_FORM.CONTACT') }}
        <ComboBox
          v-model="form.contact_id"
          :options="contactOptions"
          :display-label="selectedContactLabel"
          :placeholder="t('FLOW_KANBAN.CARD_FORM.CONTACT_PLACEHOLDER')"
          :search-placeholder="t('FLOW_KANBAN.CARD_FORM.CONTACT_SEARCH')"
          :empty-state="t('FLOW_KANBAN.CARD_FORM.CONTACT_EMPTY')"
          use-api-results
          @search="searchContacts"
        />
      </label>
      <Input
        v-model="form.title"
        :label="t('FLOW_KANBAN.CARD_FORM.TITLE')"
        :placeholder="t('FLOW_KANBAN.CARD_FORM.TITLE_PLACEHOLDER')"
      />
      <div class="grid grid-cols-2 gap-4">
        <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.CARD_FORM.STAGE') }}
          <RequiredComboBox v-model="form.stage_id" :options="stageOptions" />
        </label>
        <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.CARD_FORM.ASSIGNEE') }}
          <ComboBox v-model="form.assignee_id" :options="assigneeOptions" />
        </label>
      </div>
    </div>
  </Dialog>
</template>
