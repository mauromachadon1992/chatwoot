<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import RequiredComboBox from './RequiredComboBox.vue';
import SkeletonRows from './SkeletonRows.vue';
import StatePill from './StatePill.vue';
import {
  SUMMARY_MAX,
  canRetry,
  canSchedule,
  dueInput,
  errorMessage,
  fitsDescription,
  usedNote,
} from './aiSummary';
import { TASK_TYPES, dueInputToISO } from './tasks';

// A draft summary of the deal and one suggested follow-up, written by the AI on the agent's
// request. It is only a draft: nothing is saved until the agent accepts it, and accepting the
// summary puts it in the card's description field (saved with the card's own Save).
const props = defineProps({
  card: { type: Object, required: true },
  // The description as it is in the form now, so the "add" button can say when it would not fit.
  description: { type: String, default: '' },
});

const emit = defineEmits(['acceptSummary', 'taskCreated']);

const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');

// idle | generating | draft | failed
const step = ref('idle');
const draft = ref(null);
const summary = ref('');
const task = ref(null);
const failure = ref({ message: '', retry: false });
const isScheduling = ref(false);

const hasConversations = computed(() => props.card.conversations.length > 0);
const note = computed(() => (draft.value ? usedNote(draft.value.used) : null));
const taskTypeOptions = computed(() =>
  TASK_TYPES.map(type => ({
    value: type,
    label: t(`FLOW_KANBAN.TASKS.TYPES.${type.toUpperCase()}`),
  }))
);
const summaryTooLong = computed(() => summary.value.length > SUMMARY_MAX);
const fits = computed(() => fitsDescription(props.description, summary.value));

const decide = decision => {
  if (draft.value) {
    // Only the metric reads this: a failed report changes nothing for the agent.
    FlowKanbanAPI.decideAiDraft(draft.value.draft_id, decision).catch(() => {});
  }
};

const reset = () => {
  step.value = 'idle';
  draft.value = null;
  summary.value = '';
  task.value = null;
};

const generate = async () => {
  if (step.value === 'generating') return;
  step.value = 'generating';
  try {
    const { data } = await FlowKanbanAPI.createAiSummary(props.card.id);
    draft.value = data.payload;
    summary.value = data.payload.summary;
    task.value = data.payload.next_task
      ? {
          ...data.payload.next_task,
          due: dueInput(data.payload.next_task.due_in_days),
        }
      : null;
    step.value = 'draft';
  } catch (error) {
    failure.value = {
      message: errorMessage(error, t),
      retry: canRetry(error),
    };
    step.value = 'failed';
  }
};

const addSummary = () => {
  if (!summary.value.trim() || summaryTooLong.value || !fits.value) return;
  emit('acceptSummary', summary.value.trim());
  decide('accepted');
  summary.value = '';
  draft.value = { ...draft.value, summaryTaken: true };
  if (!task.value) reset();
};

const scheduleTask = async () => {
  if (!canSchedule(task.value) || isScheduling.value) return;
  isScheduling.value = true;
  try {
    await FlowKanbanAPI.createCardTask(props.card.id, {
      title: task.value.title.trim(),
      task_type: task.value.task_type,
      due_at: dueInputToISO(task.value.due),
      user_id: props.card.assignee_id || currentUser.value.id,
    });
    emit('taskCreated');
    decide('accepted');
    task.value = null;
    useAlert(t('FLOW_KANBAN.AI.TASK_SCHEDULED'));
    if (draft.value?.summaryTaken || !summary.value) reset();
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));
  } finally {
    isScheduling.value = false;
  }
};

const discard = () => {
  decide('discarded');
  reset();
};

// A draft belongs to one deal: opening another card starts clean.
watch(() => props.card.id, reset);
</script>

<template>
  <section class="flex flex-col gap-3" aria-labelledby="flow-ai-title">
    <div class="flex items-center justify-between gap-3">
      <h4 id="flow-ai-title" class="text-heading-3 text-n-slate-12">
        {{ t('FLOW_KANBAN.AI.SECTION') }}
      </h4>
      <StatePill
        tone="blue"
        icon="i-lucide-sparkles"
        :label="t('FLOW_KANBAN.AI.GENERATED_BY_AI')"
      />
    </div>

    <template v-if="step === 'idle'">
      <p class="text-label-small text-n-slate-11">
        {{
          hasConversations
            ? t('FLOW_KANBAN.AI.HINT')
            : t('FLOW_KANBAN.AI.NO_CONVERSATIONS')
        }}
      </p>
      <Button
        faded
        blue
        sm
        type="button"
        class="self-start"
        icon="i-lucide-sparkles"
        :label="t('FLOW_KANBAN.AI.SUMMARIZE')"
        :disabled="!hasConversations"
        @click="generate"
      />
    </template>

    <div v-else-if="step === 'generating'" aria-live="polite">
      <p class="mb-2 text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.AI.GENERATING') }}
      </p>
      <SkeletonRows :rows="3" />
    </div>

    <div
      v-else-if="step === 'failed'"
      class="flex flex-col items-start gap-2"
      role="alert"
    >
      <p class="text-body-main text-n-slate-12">{{ failure.message }}</p>
      <Button
        v-if="failure.retry"
        faded
        slate
        sm
        type="button"
        icon="i-lucide-rotate-cw"
        :label="t('FLOW_KANBAN.AI.RETRY')"
        @click="generate"
      />
      <Button
        v-else
        link
        slate
        sm
        type="button"
        :label="t('FLOW_KANBAN.AI.BACK')"
        @click="reset"
      />
    </div>

    <template v-else-if="step === 'draft'">
      <p class="text-label-small text-n-slate-11">
        {{ t(`FLOW_KANBAN.AI.${note.key}`, note.params, note.count) }}
        {{ t('FLOW_KANBAN.AI.REVIEW') }}
      </p>

      <template v-if="!draft.summaryTaken">
        <TextArea
          v-model="summary"
          :label="t('FLOW_KANBAN.AI.SUMMARY')"
          :max-length="SUMMARY_MAX"
          auto-height
          min-height="7rem"
        />
        <div class="flex flex-wrap items-center gap-2">
          <Button
            solid
            blue
            sm
            type="button"
            icon="i-lucide-plus"
            :label="t('FLOW_KANBAN.AI.ADD_TO_DESCRIPTION')"
            :disabled="!summary.trim() || summaryTooLong || !fits"
            @click="addSummary"
          />
          <Button
            ghost
            slate
            sm
            type="button"
            :label="t('FLOW_KANBAN.AI.DISCARD')"
            @click="discard"
          />
        </div>
        <p
          class="text-label-small"
          :class="fits ? 'text-n-slate-11' : 'text-n-ruby-11'"
        >
          {{
            fits ? t('FLOW_KANBAN.AI.SAVE_HINT') : t('FLOW_KANBAN.AI.TOO_LONG')
          }}
        </p>
      </template>
      <p v-else class="text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.AI.ADDED') }}
      </p>

      <div
        v-if="task"
        class="flex flex-col gap-3 p-3 rounded-lg outline outline-1 outline-n-container bg-n-solid-1"
      >
        <h5 class="text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.AI.SUGGESTED_TASK') }}
        </h5>
        <Input
          v-model="task.title"
          :label="t('FLOW_KANBAN.TASKS.TITLE')"
          maxlength="255"
        />
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <Input
            v-model="task.due"
            type="datetime-local"
            :label="t('FLOW_KANBAN.TASKS.DUE')"
          />
          <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
            {{ t('FLOW_KANBAN.TASKS.TYPE') }}
            <RequiredComboBox
              v-model="task.task_type"
              :options="taskTypeOptions"
            />
          </label>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <Button
            faded
            blue
            sm
            type="button"
            icon="i-lucide-calendar-plus"
            :label="t('FLOW_KANBAN.AI.SCHEDULE_TASK')"
            :is-loading="isScheduling"
            :disabled="!canSchedule(task) || !task.due || isScheduling"
            @click="scheduleTask"
          />
          <Button
            ghost
            slate
            sm
            type="button"
            :label="t('FLOW_KANBAN.AI.DISCARD_TASK')"
            @click="task = null"
          />
        </div>
      </div>

      <Button
        v-if="draft.summaryTaken && !task"
        link
        slate
        sm
        type="button"
        class="self-start"
        :label="t('FLOW_KANBAN.AI.DONE')"
        @click="reset"
      />
    </template>
  </section>
</template>
