<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';

import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

// The board's automatic-deal rule (Board#auto_create). Saved as it changes, like the stages.
// Turning it on without an inbox only reveals the fields: the rule is saved once it can work.
const props = defineProps({
  boardId: { type: Number, required: true },
});

const { t } = useI18n();
const kanban = useFlowKanbanStore();
const inboxes = useMapGetter('inboxes/getInboxes');

const CAP_MIN = 1;
const CAP_MAX = 500;

const board = computed(() =>
  kanban.boards.find(item => item.id === props.boardId)
);
const saved = computed(
  () =>
    board.value?.auto_create || {
      enabled: false,
      inbox_ids: [],
      daily_cap: 50,
      created_today: 0,
    }
);

const enabled = ref(false);
const inboxIds = ref([]);
const cap = ref('50');
const capInvalid = ref(false);
const isSaving = ref(false);

const sync = () => {
  enabled.value = saved.value.enabled;
  inboxIds.value = [...saved.value.inbox_ids];
  cap.value = String(saved.value.daily_cap);
  capInvalid.value = false;
};
watch(saved, sync, { immediate: true });

const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
);
const needsInbox = computed(() => enabled.value && !inboxIds.value.length);

const save = async changes => {
  isSaving.value = true;
  try {
    await kanban.updateBoard(props.boardId, { auto_create: changes });
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));
    sync();
  } finally {
    isSaving.value = false;
  }
};

const toggle = value => {
  enabled.value = value;
  if (value && !inboxIds.value.length) return;
  save({ enabled: value, inbox_ids: inboxIds.value });
};

const pickInboxes = ids => {
  inboxIds.value = ids;
  if (enabled.value && !ids.length) return;
  save({ enabled: enabled.value, inbox_ids: ids });
};

const commitCap = () => {
  const value = Number(cap.value);
  capInvalid.value =
    !Number.isInteger(value) || value < CAP_MIN || value > CAP_MAX;
  if (capInvalid.value || value === saved.value.daily_cap) return;
  save({ daily_cap: value });
};
</script>

<template>
  <section class="flex flex-col gap-3" :aria-busy="isSaving">
    <div class="flex items-start justify-between gap-4">
      <div class="flex flex-col gap-1">
        <h4 id="flow-auto-create-title" class="text-heading-3 text-n-slate-12">
          {{ t('FLOW_KANBAN.AUTO_CREATE.SECTION') }}
        </h4>
        <p class="text-label-small text-n-slate-11">
          {{ t('FLOW_KANBAN.AUTO_CREATE.HINT') }}
        </p>
      </div>
      <Switch
        :model-value="enabled"
        aria-labelledby="flow-auto-create-title"
        @update:model-value="toggle"
      />
    </div>

    <div
      v-if="enabled || saved.inbox_ids.length"
      class="flex flex-col gap-4 p-3 rounded-lg bg-n-alpha-1"
    >
      <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
        {{ t('FLOW_KANBAN.AUTO_CREATE.INBOXES') }}
        <TagMultiSelectComboBox
          :model-value="inboxIds"
          :options="inboxOptions"
          :placeholder="t('FLOW_KANBAN.AUTO_CREATE.INBOXES_PLACEHOLDER')"
          @update:model-value="pickInboxes"
        />
        <span v-if="needsInbox" class="text-label-small text-n-amber-11">
          {{ t('FLOW_KANBAN.AUTO_CREATE.NEEDS_INBOX') }}
        </span>
      </label>

      <div class="flex flex-wrap items-end gap-3">
        <Input
          v-model="cap"
          type="number"
          :min="String(CAP_MIN)"
          :max="String(CAP_MAX)"
          class="w-32"
          :label="t('FLOW_KANBAN.AUTO_CREATE.CAP')"
          :message="capInvalid ? t('FLOW_KANBAN.AUTO_CREATE.CAP_INVALID') : ''"
          :message-type="capInvalid ? 'error' : 'info'"
          @blur="commitCap"
          @keydown.enter.prevent="commitCap"
        />
        <p
          v-if="saved.enabled"
          class="pb-2.5 text-label-small tabular-nums text-n-slate-11"
        >
          {{
            t('FLOW_KANBAN.AUTO_CREATE.TODAY', {
              count: saved.created_today,
              cap: saved.daily_cap,
            })
          }}
        </p>
      </div>

      <ul
        class="flex flex-col gap-1 ps-4 list-disc text-label-small text-n-slate-11"
      >
        <li>{{ t('FLOW_KANBAN.AUTO_CREATE.RULE_STAGE') }}</li>
        <li>{{ t('FLOW_KANBAN.AUTO_CREATE.RULE_DEDUP') }}</li>
        <li>{{ t('FLOW_KANBAN.AUTO_CREATE.RULE_GROUPS') }}</li>
        <li>{{ t('FLOW_KANBAN.AUTO_CREATE.RULE_ASSIGNEE') }}</li>
      </ul>
    </div>
  </section>
</template>
