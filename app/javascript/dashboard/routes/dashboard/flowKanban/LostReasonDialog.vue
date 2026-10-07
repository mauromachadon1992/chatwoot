<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

// Asked when a deal lands on a lost stage. Skipping is allowed ("No reason"), so the drag never
// blocks the agent; cancelling leaves the deal where it was. `ask()` resolves with
// { lostReasonId, lostNote } or null when cancelled.
const NOTE_MAX_LENGTH = 500;

const { t } = useI18n();
const dialogRef = ref(null);
const reasons = ref([]);
const reasonId = ref('');
const note = ref('');
const loadFailed = ref(false);
let settle = null;

const options = computed(() =>
  reasons.value.map(reason => ({ value: reason.id, label: reason.name }))
);

const loadReasons = async () => {
  loadFailed.value = false;
  try {
    const { data } = await FlowKanbanAPI.getLostReasons();
    reasons.value = data.payload;
  } catch {
    // The list is a convenience: without it the deal can still be marked lost with no reason.
    loadFailed.value = true;
  }
};

const finish = value => {
  settle?.(value);
  settle = null;
};

const ask = () => {
  reasonId.value = '';
  note.value = '';
  loadReasons();
  dialogRef.value?.open();
  return new Promise(resolve => {
    settle = resolve;
  });
};

const confirm = () => {
  finish({
    lostReasonId: reasonId.value || undefined,
    lostNote: note.value.trim() || undefined,
  });
  dialogRef.value?.close();
};

// `close` also fires after a confirm; by then the promise is settled and this does nothing.
const cancel = () => finish(null);

defineExpose({ ask });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('FLOW_KANBAN.LOST.TITLE')"
    :description="t('FLOW_KANBAN.LOST.DESCRIPTION')"
    :confirm-button-label="t('FLOW_KANBAN.LOST.CONFIRM')"
    width="md"
    @confirm="confirm"
    @close="cancel"
  >
    <div class="flex flex-col gap-4">
      <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
        {{ t('FLOW_KANBAN.LOST.REASON') }}
        <ComboBox
          v-model="reasonId"
          :options="options"
          :placeholder="t('FLOW_KANBAN.LOST.NO_REASON')"
          :empty-state="t('FLOW_KANBAN.LOST.EMPTY')"
        />
        <span v-if="loadFailed" class="text-label-small text-n-amber-11">
          {{ t('FLOW_KANBAN.LOST.LOAD_FAILED') }}
        </span>
      </label>
      <TextArea
        v-model="note"
        :label="t('FLOW_KANBAN.LOST.NOTE')"
        :placeholder="t('FLOW_KANBAN.LOST.NOTE_PLACEHOLDER')"
        :max-length="NOTE_MAX_LENGTH"
        auto-height
        min-height="4rem"
      />
    </div>
  </Dialog>
</template>
