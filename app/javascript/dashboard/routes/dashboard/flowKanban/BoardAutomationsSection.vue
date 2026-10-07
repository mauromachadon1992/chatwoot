<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import AutomationEditor from './AutomationEditor.vue';
import EmptyState from './EmptyState.vue';
import SkeletonRows from './SkeletonRows.vue';
import StatePill from './StatePill.vue';
import {
  blankRule,
  describeResults,
  describeRule,
  starterRules,
} from './automations';

// Rules that act on a deal when something happens: move it, schedule a task, hand it to an
// agent, label its conversation. The server applies them; here an administrator writes them,
// turns them on and off, and sees what they did.
const props = defineProps({
  boardId: { type: Number, required: true },
  stages: { type: Array, required: true },
});

const { t, locale } = useI18n();
const agents = useMapGetter('agents/getAgents');

const rules = ref([]);
const runs = ref([]);
const isLoading = ref(true);
const isSaving = ref(false);
const serverError = ref('');
// null: closed; { id?: number, rule }: the editor is open on a new or an existing rule.
const editing = ref(null);
const ruleToDelete = ref(null);
const deleteDialogRef = ref(null);

const lookup = computed(() => ({
  stageName: id =>
    props.stages.find(stage => stage.id === Number(id))?.name ||
    t('FLOW_KANBAN.AUTOMATIONS.UNKNOWN.STAGE'),
  agentName: id =>
    agents.value.find(agent => agent.id === Number(id))?.name ||
    t('FLOW_KANBAN.AUTOMATIONS.UNKNOWN.AGENT'),
}));
const starters = computed(() =>
  starterRules({ stages: props.stages }, t).map(starter => ({
    ...starter,
    title: t(`FLOW_KANBAN.AUTOMATIONS.STARTERS.${starter.key}`),
    hint: t(`FLOW_KANBAN.AUTOMATIONS.STARTERS.${starter.key}_HINT`),
  }))
);

const sentence = rule => describeRule(rule, lookup.value, t);
const reasonLabel = reason =>
  t(`FLOW_KANBAN.AUTOMATIONS.NEEDS_ATTENTION.${reason.toUpperCase()}`);

const fail = error =>
  useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));

const when = seconds =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(seconds * 1000));

const loadRuns = async () => {
  try {
    const { data } = await FlowKanbanAPI.getAutomationRuns(props.boardId);
    runs.value = data.payload;
  } catch {
    runs.value = [];
  }
};

const load = async () => {
  isLoading.value = true;
  editing.value = null;
  try {
    const { data } = await FlowKanbanAPI.getAutomations(props.boardId);
    rules.value = data.payload;
    await loadRuns();
  } catch (error) {
    fail(error);
  } finally {
    isLoading.value = false;
  }
};

const startNew = (rule = blankRule({ stages: props.stages })) => {
  serverError.value = '';
  editing.value = { rule };
};

const startEdit = rule => {
  serverError.value = '';
  editing.value = { id: rule.id, rule };
};

const save = async payload => {
  if (isSaving.value) return;
  isSaving.value = true;
  serverError.value = '';
  try {
    const { id } = editing.value;
    const { data } = id
      ? await FlowKanbanAPI.updateAutomation(props.boardId, id, payload)
      : await FlowKanbanAPI.createAutomation(props.boardId, payload);
    rules.value = id
      ? rules.value.map(rule => (rule.id === id ? data.payload : rule))
      : [...rules.value, data.payload];
    editing.value = null;
  } catch (error) {
    serverError.value =
      parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC');
  } finally {
    isSaving.value = false;
  }
};

const toggle = async (rule, active) => {
  try {
    const { data } = await FlowKanbanAPI.updateAutomation(
      props.boardId,
      rule.id,
      { active }
    );
    rules.value = rules.value.map(item =>
      item.id === rule.id ? data.payload : item
    );
  } catch (error) {
    fail(error);
  }
};

const askDelete = rule => {
  ruleToDelete.value = rule;
  deleteDialogRef.value?.open();
};

const confirmDelete = async () => {
  const rule = ruleToDelete.value;
  try {
    await FlowKanbanAPI.removeAutomation(props.boardId, rule.id);
    rules.value = rules.value.filter(item => item.id !== rule.id);
    deleteDialogRef.value?.close();
  } catch (error) {
    fail(error);
  }
};

onMounted(load);
watch(() => props.boardId, load);
</script>

<template>
  <section class="flex flex-col gap-3">
    <div class="flex flex-col gap-1">
      <h4 class="text-heading-3 text-n-slate-12">
        {{ t('FLOW_KANBAN.AUTOMATIONS.SECTION') }}
      </h4>
      <p class="text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.AUTOMATIONS.HINT') }}
      </p>
    </div>

    <SkeletonRows v-if="isLoading" :rows="2" />

    <template v-else>
      <EmptyState
        v-if="!rules.length && !editing"
        icon="i-lucide-zap"
        size="compact"
        title-tag="h5"
        :title="t('FLOW_KANBAN.AUTOMATIONS.EMPTY_TITLE')"
        :description="t('FLOW_KANBAN.AUTOMATIONS.EMPTY')"
      >
        <ul class="flex flex-col w-full gap-3 p-0 m-0 list-none">
          <li
            v-for="starter in starters"
            :key="starter.key"
            class="flex flex-col items-center gap-1"
          >
            <Button
              faded
              slate
              sm
              type="button"
              icon="i-lucide-plus"
              :label="starter.title"
              @click="startNew(starter.rule)"
            />
            <span class="text-label-small text-n-slate-11">
              {{ starter.hint }}
            </span>
          </li>
        </ul>
      </EmptyState>

      <ul
        v-if="rules.length"
        class="flex flex-col p-0 m-0 list-none rounded-lg outline outline-1 outline-n-container divide-y divide-n-weak"
      >
        <li
          v-for="rule in rules"
          :key="rule.id"
          class="flex flex-col gap-2 px-3 py-2"
        >
          <div class="flex items-start gap-3">
            <Icon
              icon="i-lucide-zap"
              class="flex-shrink-0 mt-0.5 size-4"
              :class="rule.active ? 'text-n-slate-11' : 'text-n-slate-8'"
            />
            <span
              class="flex-1 min-w-0 text-body-main"
              :class="rule.active ? 'text-n-slate-12' : 'text-n-slate-10'"
            >
              {{ sentence(rule) }}
            </span>
            <Switch
              :model-value="rule.active"
              :aria-label="t('FLOW_KANBAN.AUTOMATIONS.ACTIVE')"
              @update:model-value="toggle(rule, $event)"
            />
            <Button
              v-tooltip.top="t('FLOW_KANBAN.AUTOMATIONS.EDIT')"
              ghost
              slate
              xs
              type="button"
              icon="i-lucide-pencil"
              :aria-label="t('FLOW_KANBAN.AUTOMATIONS.EDIT')"
              @click="startEdit(rule)"
            />
            <Button
              v-tooltip.top="t('FLOW_KANBAN.AUTOMATIONS.DELETE')"
              ghost
              slate
              xs
              type="button"
              icon="i-lucide-trash-2"
              :aria-label="t('FLOW_KANBAN.AUTOMATIONS.DELETE')"
              @click="askDelete(rule)"
            />
          </div>
          <div
            v-if="rule.needs_attention?.length"
            class="flex flex-wrap items-center gap-2 ps-7"
          >
            <StatePill
              tone="amber"
              icon="i-lucide-triangle-alert"
              :label="t('FLOW_KANBAN.AUTOMATIONS.NEEDS_ATTENTION.LABEL')"
            />
            <span class="text-label-small text-n-slate-11">
              {{ rule.needs_attention.map(reasonLabel).join(' · ') }}
            </span>
          </div>
        </li>
      </ul>

      <AutomationEditor
        v-if="editing"
        :key="editing.id || 'new'"
        :model-value="editing.rule"
        :stages="stages"
        :is-saving="isSaving"
        :server-error="serverError"
        @save="save"
        @cancel="editing = null"
      />
      <Button
        v-else-if="rules.length"
        faded
        blue
        sm
        type="button"
        class="self-start"
        icon="i-lucide-plus"
        :label="t('FLOW_KANBAN.AUTOMATIONS.NEW')"
        @click="startNew()"
      />

      <div v-if="runs.length" class="flex flex-col gap-2">
        <h5 class="text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.AUTOMATIONS.RUNS') }}
        </h5>
        <ol class="flex flex-col gap-2 p-0 m-0 list-none">
          <li
            v-for="run in runs"
            :key="run.id"
            class="flex flex-col gap-0.5 text-label-small"
          >
            <span class="text-n-slate-12">
              {{ run.card.title }}
              <span class="text-n-slate-11">
                · {{ describeResults(run.data.results, t) }}
              </span>
            </span>
            <time class="text-n-slate-10 tabular-nums">
              {{ when(run.created_at) }}
            </time>
          </li>
        </ol>
      </div>
      <p v-else-if="rules.length" class="text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.AUTOMATIONS.RUNS_EMPTY') }}
      </p>
    </template>

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('FLOW_KANBAN.AUTOMATIONS.DELETE')"
      :description="
        ruleToDelete
          ? t('FLOW_KANBAN.AUTOMATIONS.DELETE_CONFIRM', {
              rule: sentence(ruleToDelete),
            })
          : ''
      "
      :confirm-button-label="t('FLOW_KANBAN.AUTOMATIONS.DELETE')"
      @confirm="confirmDelete"
    />
  </section>
</template>
