<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import RequiredComboBox from './RequiredComboBox.vue';
import SegmentedControl from './SegmentedControl.vue';
import {
  ACTION_TYPES,
  DEAL_AGENT,
  MAX_ACTIONS,
  NO_REPLY_HOURS,
  DUE_HOURS,
  STATUSES,
  TASK_TYPES,
  TRIGGERS,
  blankAction,
  blankTriggerConfig,
  canSaveRule,
  ruleProblems,
  toPayload,
} from './automations';

// One rule, written as: when this happens, do these steps in order. It is a sentence the
// administrator fills in, not a form of unrelated fields. Nothing is saved until "Save".
const props = defineProps({
  modelValue: { type: Object, required: true },
  stages: { type: Array, required: true },
  isSaving: { type: Boolean, default: false },
  // Messages from the server, by field, shown next to the step they belong to.
  serverError: { type: String, default: '' },
});

const emit = defineEmits(['save', 'cancel']);

const { t } = useI18n();
const agents = useMapGetter('agents/getAgents');
const labels = useMapGetter('labels/getLabels');

const rule = ref(JSON.parse(JSON.stringify(props.modelValue)));
const triedToSave = ref(false);

const problems = computed(() => ruleProblems(rule.value));
const isValid = computed(() => canSaveRule(rule.value));
const canAddAction = computed(() => rule.value.actions.length < MAX_ACTIONS);

const named = (scope, values) =>
  values.map(value => ({
    value,
    label: t(`FLOW_KANBAN.AUTOMATIONS.${scope}.${String(value).toUpperCase()}`),
  }));

const triggerOptions = computed(() => named('TRIGGERS', TRIGGERS));
const statusOptions = computed(() => named('STATUSES', STATUSES));
const actionTypeOptions = computed(() => named('ACTIONS', ACTION_TYPES));
const taskTypeOptions = computed(() =>
  TASK_TYPES.map(type => ({
    value: type,
    label: t(`FLOW_KANBAN.TASKS.TYPES.${type.toUpperCase()}`),
  }))
);
const sideOptions = computed(() => named('SIDES', ['customer', 'agent']));
const stageOptions = computed(() =>
  props.stages.map(stage => ({ value: stage.id, label: stage.name }))
);
const agentOptions = computed(() =>
  agents.value.map(agent => ({ value: agent.id, label: agent.name }))
);
// A label the account no longer has stays in the list, so an old rule still shows its choice.
const labelOptions = computed(() => {
  const titles = labels.value.map(label => label.title);
  const current = [
    rule.value.trigger_config.label,
    ...rule.value.actions.map(action => action.label),
  ].filter(title => title && !titles.includes(title));
  return [...titles, ...current].map(title => ({ value: title, label: title }));
});
const assigneeOptions = computed(() => [
  {
    value: DEAL_AGENT,
    label: t('FLOW_KANBAN.AUTOMATIONS.ACTION_TEXT.DEAL_AGENT'),
  },
  ...agentOptions.value,
]);

const changeTrigger = type => {
  rule.value.trigger_type = type;
  rule.value.trigger_config = blankTriggerConfig(type);
};

const changeActionType = (index, type) => {
  rule.value.actions[index] = blankAction(type, { stages: props.stages });
};

const addAction = () => {
  if (canAddAction.value)
    rule.value.actions.push(
      blankAction('move_to_stage', { stages: props.stages })
    );
};

const removeAction = index => rule.value.actions.splice(index, 1);

const moveAction = (index, by) => {
  const target = index + by;
  if (target < 0 || target >= rule.value.actions.length) return;
  const list = rule.value.actions;
  [list[index], list[target]] = [list[target], list[index]];
};

const showError = (list, key) => triedToSave.value && list.includes(key);

const save = () => {
  triedToSave.value = true;
  if (isValid.value) emit('save', toPayload(rule.value));
};
</script>

<template>
  <div
    role="group"
    :aria-label="t('FLOW_KANBAN.AUTOMATIONS.NEW')"
    class="flex flex-col gap-4 p-3 rounded-lg bg-n-alpha-1"
  >
    <fieldset class="flex flex-col gap-2 p-0 m-0 border-0 min-w-0">
      <legend class="mb-2 text-label text-n-slate-12">
        {{ t('FLOW_KANBAN.AUTOMATIONS.WHEN') }}
      </legend>
      <ComboBox
        :model-value="rule.trigger_type"
        :options="triggerOptions"
        @update:model-value="value => value && changeTrigger(value)"
      />

      <div
        v-if="rule.trigger_type === 'conversation_status_changed'"
        class="flex flex-col gap-1.5"
      >
        <span class="text-label-small text-n-slate-11">
          {{ t('FLOW_KANBAN.AUTOMATIONS.STATUS') }}
        </span>
        <SegmentedControl
          v-model="rule.trigger_config.status"
          :options="statusOptions"
          :aria-label="t('FLOW_KANBAN.AUTOMATIONS.STATUS')"
        />
      </div>

      <label
        v-else-if="rule.trigger_type === 'label_added'"
        class="flex flex-col gap-1.5 text-label-small text-n-slate-11"
      >
        {{ t('FLOW_KANBAN.AUTOMATIONS.LABEL') }}
        <ComboBox
          v-model="rule.trigger_config.label"
          :options="labelOptions"
          :placeholder="t('FLOW_KANBAN.AUTOMATIONS.LABEL_PLACEHOLDER')"
          :has-error="showError(problems.trigger, 'label')"
          :message="
            showError(problems.trigger, 'label')
              ? t('FLOW_KANBAN.AUTOMATIONS.PROBLEMS.LABEL')
              : ''
          "
        />
      </label>

      <div
        v-else-if="rule.trigger_type === 'no_reply'"
        class="flex flex-col gap-2"
      >
        <div class="flex flex-col gap-1.5">
          <span class="text-label-small text-n-slate-11">
            {{ t('FLOW_KANBAN.AUTOMATIONS.SIDE') }}
          </span>
          <SegmentedControl
            v-model="rule.trigger_config.side"
            :options="sideOptions"
            :aria-label="t('FLOW_KANBAN.AUTOMATIONS.SIDE')"
          />
        </div>
        <Input
          v-model="rule.trigger_config.hours"
          type="number"
          inputmode="numeric"
          :label="t('FLOW_KANBAN.AUTOMATIONS.HOURS')"
          :message="
            showError(problems.trigger, 'hours')
              ? t('FLOW_KANBAN.AUTOMATIONS.PROBLEMS.HOURS', {
                  min: NO_REPLY_HOURS[0],
                  max: NO_REPLY_HOURS[1],
                })
              : t('FLOW_KANBAN.AUTOMATIONS.HOURS_HINT')
          "
          :message-type="
            showError(problems.trigger, 'hours') ? 'error' : 'info'
          "
        />
      </div>

      <p v-else class="text-label-small text-n-slate-11">
        {{
          t(
            `FLOW_KANBAN.AUTOMATIONS.TRIGGER_HINT.${rule.trigger_type.toUpperCase()}`
          )
        }}
      </p>
    </fieldset>

    <fieldset class="flex flex-col gap-3 p-0 m-0 border-0 min-w-0">
      <legend class="mb-2 text-label text-n-slate-12">
        {{ t('FLOW_KANBAN.AUTOMATIONS.THEN') }}
      </legend>

      <ol class="flex flex-col gap-3 p-0 m-0 list-none">
        <li
          v-for="(action, index) in rule.actions"
          :key="index"
          class="flex flex-col gap-2 p-3 rounded-lg outline outline-1 outline-n-container bg-n-solid-1"
        >
          <div class="flex items-center gap-2">
            <span class="flex-1 text-label-small text-n-slate-11 tabular-nums">
              {{ t('FLOW_KANBAN.AUTOMATIONS.STEP', { n: index + 1 }) }}
            </span>
            <Button
              ghost
              slate
              xs
              type="button"
              icon="i-lucide-chevron-up"
              :disabled="index === 0"
              :aria-label="t('FLOW_KANBAN.AUTOMATIONS.MOVE_UP')"
              @click="moveAction(index, -1)"
            />
            <Button
              ghost
              slate
              xs
              type="button"
              icon="i-lucide-chevron-down"
              :disabled="index === rule.actions.length - 1"
              :aria-label="t('FLOW_KANBAN.AUTOMATIONS.MOVE_DOWN')"
              @click="moveAction(index, 1)"
            />
            <Button
              ghost
              slate
              xs
              type="button"
              icon="i-lucide-trash-2"
              :disabled="rule.actions.length === 1"
              :aria-label="t('FLOW_KANBAN.AUTOMATIONS.REMOVE_STEP')"
              @click="removeAction(index)"
            />
          </div>
          <RequiredComboBox
            :model-value="action.type"
            :options="actionTypeOptions"
            @update:model-value="changeActionType(index, $event)"
          />

          <label
            v-if="action.type === 'move_to_stage'"
            class="flex flex-col gap-1.5 text-label-small text-n-slate-11"
          >
            {{ t('FLOW_KANBAN.AUTOMATIONS.STAGE') }}
            <RequiredComboBox
              v-model="action.stage_id"
              :options="stageOptions"
            />
          </label>

          <label
            v-else-if="action.type === 'assign_agent'"
            class="flex flex-col gap-1.5 text-label-small text-n-slate-11"
          >
            {{ t('FLOW_KANBAN.AUTOMATIONS.AGENT') }}
            <ComboBox
              v-model="action.user_id"
              :options="agentOptions"
              :placeholder="t('FLOW_KANBAN.AUTOMATIONS.AGENT_PLACEHOLDER')"
              :has-error="showError(problems.actions[index], 'agent')"
              :message="
                showError(problems.actions[index], 'agent')
                  ? t('FLOW_KANBAN.AUTOMATIONS.PROBLEMS.AGENT')
                  : ''
              "
            />
          </label>

          <label
            v-else-if="action.type === 'add_label'"
            class="flex flex-col gap-1.5 text-label-small text-n-slate-11"
          >
            {{ t('FLOW_KANBAN.AUTOMATIONS.LABEL') }}
            <ComboBox
              v-model="action.label"
              :options="labelOptions"
              :placeholder="t('FLOW_KANBAN.AUTOMATIONS.LABEL_PLACEHOLDER')"
              :has-error="showError(problems.actions[index], 'label')"
              :message="
                showError(problems.actions[index], 'label')
                  ? t('FLOW_KANBAN.AUTOMATIONS.PROBLEMS.LABEL')
                  : ''
              "
            />
          </label>

          <div v-else class="flex flex-col gap-2">
            <Input
              v-model="action.title"
              :label="t('FLOW_KANBAN.AUTOMATIONS.TASK_TITLE')"
              :placeholder="t('FLOW_KANBAN.AUTOMATIONS.TASK_TITLE_PLACEHOLDER')"
              maxlength="255"
              :message="
                showError(problems.actions[index], 'title')
                  ? t('FLOW_KANBAN.AUTOMATIONS.PROBLEMS.TITLE')
                  : ''
              "
              :message-type="
                showError(problems.actions[index], 'title') ? 'error' : 'info'
              "
            />
            <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <label
                class="flex flex-col gap-1.5 text-label-small text-n-slate-11"
              >
                {{ t('FLOW_KANBAN.AUTOMATIONS.TASK_TYPE') }}
                <RequiredComboBox
                  v-model="action.task_type"
                  :options="taskTypeOptions"
                />
              </label>
              <label
                class="flex flex-col gap-1.5 text-label-small text-n-slate-11"
              >
                {{ t('FLOW_KANBAN.AUTOMATIONS.ASSIGNEE') }}
                <RequiredComboBox
                  v-model="action.assignee"
                  :options="assigneeOptions"
                />
              </label>
            </div>
            <Input
              v-model="action.due_in_hours"
              type="number"
              inputmode="numeric"
              :label="t('FLOW_KANBAN.AUTOMATIONS.DUE_IN_HOURS')"
              :message="
                showError(problems.actions[index], 'due')
                  ? t('FLOW_KANBAN.AUTOMATIONS.PROBLEMS.DUE', {
                      min: DUE_HOURS[0],
                      max: DUE_HOURS[1],
                    })
                  : t('FLOW_KANBAN.AUTOMATIONS.DUE_HINT')
              "
              :message-type="
                showError(problems.actions[index], 'due') ? 'error' : 'info'
              "
            />
          </div>
        </li>
      </ol>

      <div class="flex items-center gap-3">
        <Button
          faded
          slate
          sm
          type="button"
          icon="i-lucide-plus"
          :label="t('FLOW_KANBAN.AUTOMATIONS.ADD_STEP')"
          :disabled="!canAddAction"
          @click="addAction"
        />
        <span v-if="!canAddAction" class="text-label-small text-n-slate-11">
          {{ t('FLOW_KANBAN.AUTOMATIONS.MAX_STEPS', { max: MAX_ACTIONS }) }}
        </span>
      </div>
    </fieldset>

    <p v-if="serverError" role="alert" class="text-label-small text-n-ruby-11">
      {{ serverError }}
    </p>

    <div class="flex items-center justify-end gap-2">
      <Button
        ghost
        slate
        sm
        type="button"
        :label="t('FLOW_KANBAN.AUTOMATIONS.CANCEL')"
        @click="emit('cancel')"
      />
      <Button
        blue
        sm
        type="button"
        :label="t('FLOW_KANBAN.AUTOMATIONS.SAVE')"
        :is-loading="isSaving"
        :disabled="isSaving"
        @click="save"
      />
    </div>
  </div>
</template>
