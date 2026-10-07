<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import RequiredComboBox from './RequiredComboBox.vue';
import SegmentedControl from './SegmentedControl.vue';

// Rules that move a card when its conversation changes. Each change saves at once, as the
// stages above do. The server applies them; here an administrator only writes them.
const props = defineProps({
  boardId: { type: Number, required: true },
  stages: { type: Array, required: true },
});

const { t } = useI18n();

// Mirrors Conversation.statuses.
const STATUSES = ['open', 'pending', 'resolved', 'snoozed'];

const rules = ref([]);
const isLoading = ref(true);
const isAdding = ref(false);
const form = ref({
  trigger_type: 'conversation_status_changed',
  status: 'resolved',
  label: '',
  stage_id: '',
});

const triggerOptions = computed(() =>
  ['conversation_status_changed', 'label_added'].map(type => ({
    value: type,
    label: t(`FLOW_KANBAN.AUTOMATIONS.TRIGGERS.${type.toUpperCase()}`),
  }))
);
const statusOptions = computed(() =>
  STATUSES.map(status => ({
    value: status,
    label: t(`FLOW_KANBAN.AUTOMATIONS.STATUSES.${status.toUpperCase()}`),
  }))
);
const stageOptions = computed(() =>
  props.stages.map(stage => ({ value: stage.id, label: stage.name }))
);
const isLabelRule = computed(() => form.value.trigger_type === 'label_added');
const canAdd = computed(
  () =>
    form.value.stage_id &&
    (isLabelRule.value ? form.value.label.trim() : form.value.status)
);

const stageName = id => props.stages.find(stage => stage.id === id)?.name || '';
const describe = rule =>
  rule.trigger_type === 'label_added'
    ? t('FLOW_KANBAN.AUTOMATIONS.RULE_LABEL', {
        label: rule.trigger_config.label,
        stage: stageName(rule.stage_id),
      })
    : t('FLOW_KANBAN.AUTOMATIONS.RULE_STATUS', {
        status: t(
          `FLOW_KANBAN.AUTOMATIONS.STATUSES.${rule.trigger_config.status.toUpperCase()}`
        ).toLowerCase(),
        stage: stageName(rule.stage_id),
      });

const fail = error =>
  useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await FlowKanbanAPI.getAutomations(props.boardId);
    rules.value = data.payload;
  } catch (error) {
    fail(error);
  } finally {
    isLoading.value = false;
  }
};

const add = async () => {
  if (!canAdd.value || isAdding.value) return;
  isAdding.value = true;
  try {
    const { data } = await FlowKanbanAPI.createAutomation(props.boardId, {
      trigger_type: form.value.trigger_type,
      trigger_config: isLabelRule.value
        ? { label: form.value.label.trim() }
        : { status: form.value.status },
      stage_id: form.value.stage_id,
    });
    rules.value = [...rules.value, data.payload];
    form.value.label = '';
  } catch (error) {
    fail(error);
  } finally {
    isAdding.value = false;
  }
};

const replace = payload => {
  rules.value = rules.value.map(rule =>
    rule.id === payload.id ? payload : rule
  );
};

const toggle = async (rule, active) => {
  try {
    const { data } = await FlowKanbanAPI.updateAutomation(
      props.boardId,
      rule.id,
      { active }
    );
    replace(data.payload);
  } catch (error) {
    fail(error);
  }
};

const remove = async rule => {
  try {
    await FlowKanbanAPI.removeAutomation(props.boardId, rule.id);
    rules.value = rules.value.filter(item => item.id !== rule.id);
  } catch (error) {
    fail(error);
  }
};

onMounted(load);
watch(() => props.boardId, load);
watch(
  () => props.stages,
  stages => {
    // A rule points at a stage; the form must not keep pointing at one that was deleted.
    if (!stages.some(stage => stage.id === form.value.stage_id))
      form.value.stage_id = stages[0]?.id || '';
  },
  { immediate: true }
);
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

    <div v-if="isLoading" class="flex flex-col gap-2" aria-hidden="true">
      <div class="h-10 rounded-lg bg-n-alpha-2 animate-pulse" />
    </div>

    <p v-else-if="!rules.length" class="text-body-main text-n-slate-11">
      {{ t('FLOW_KANBAN.AUTOMATIONS.EMPTY') }}
    </p>

    <ul
      v-if="rules.length"
      class="flex flex-col rounded-lg outline outline-1 outline-n-container divide-y divide-n-weak"
    >
      <li
        v-for="rule in rules"
        :key="rule.id"
        class="flex items-center gap-3 px-3 py-2"
      >
        <Icon
          icon="i-lucide-zap"
          class="flex-shrink-0 size-4"
          :class="rule.active ? 'text-n-slate-11' : 'text-n-slate-8'"
        />
        <span
          class="flex-1 min-w-0 text-body-main"
          :class="rule.active ? 'text-n-slate-12' : 'text-n-slate-10'"
        >
          {{ describe(rule) }}
        </span>
        <Switch
          :model-value="rule.active"
          :aria-label="t('FLOW_KANBAN.AUTOMATIONS.ACTIVE')"
          @update:model-value="toggle(rule, $event)"
        />
        <Button
          v-tooltip.top="t('FLOW_KANBAN.AUTOMATIONS.DELETE')"
          ghost
          slate
          xs
          type="button"
          icon="i-lucide-trash-2"
          :aria-label="t('FLOW_KANBAN.AUTOMATIONS.DELETE')"
          @click="remove(rule)"
        />
      </li>
    </ul>

    <div class="flex flex-col gap-3 p-3 rounded-lg bg-n-alpha-1">
      <div class="flex flex-col gap-1.5">
        <span class="text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.AUTOMATIONS.TRIGGER') }}
        </span>
        <SegmentedControl
          v-model="form.trigger_type"
          :options="triggerOptions"
          :aria-label="t('FLOW_KANBAN.AUTOMATIONS.TRIGGER')"
        />
      </div>
      <Input
        v-if="isLabelRule"
        v-model="form.label"
        :label="t('FLOW_KANBAN.AUTOMATIONS.LABEL')"
        :placeholder="t('FLOW_KANBAN.AUTOMATIONS.LABEL_PLACEHOLDER')"
        @keydown.enter.prevent="add"
      />
      <div v-else class="flex flex-col gap-1.5">
        <span class="text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.AUTOMATIONS.STATUS') }}
        </span>
        <SegmentedControl
          v-model="form.status"
          :options="statusOptions"
          :aria-label="t('FLOW_KANBAN.AUTOMATIONS.STATUS')"
        />
      </div>
      <div class="flex items-end gap-3">
        <label
          class="flex flex-col flex-1 min-w-0 gap-1.5 text-label text-n-slate-12"
        >
          {{ t('FLOW_KANBAN.AUTOMATIONS.MOVE_TO') }}
          <RequiredComboBox v-model="form.stage_id" :options="stageOptions" />
        </label>
        <Button
          faded
          blue
          sm
          type="button"
          icon="i-lucide-plus"
          :label="t('FLOW_KANBAN.AUTOMATIONS.ADD')"
          :is-loading="isAdding"
          :disabled="!canAdd || isAdding"
          @click="add"
        />
      </div>
    </div>
  </section>
</template>
