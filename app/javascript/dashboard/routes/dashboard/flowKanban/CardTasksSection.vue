<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import RequiredComboBox from './RequiredComboBox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import {
  TASK_TYPES,
  TASK_TYPE_ICONS,
  defaultDueInput,
  dueInputToISO,
  dueState,
  formatDue,
  DUE_PILLS,
} from './tasks';
import SkeletonRows from './SkeletonRows.vue';
import StatePill from './StatePill.vue';

// The deal's follow-ups. Each change saves at once; the board is told by the server, so the
// card on the board and the badge here always agree.
const props = defineProps({
  card: { type: Object, required: true },
});

const { t, locale } = useI18n();
const currentUser = useMapGetter('getCurrentUser');
const agents = useMapGetter('agents/getAgents');

const tasks = ref([]);
const isLoading = ref(true);
const isAdding = ref(false);
const form = ref({ title: '', task_type: 'call', due: '', user_id: '' });

const resetForm = () => {
  form.value = {
    title: '',
    task_type: form.value.task_type,
    due: defaultDueInput(),
    user_id: currentUser.value.id,
  };
};

const typeOptions = computed(() =>
  TASK_TYPES.map(type => ({
    value: type,
    label: t(`FLOW_KANBAN.TASKS.TYPES.${type.toUpperCase()}`),
  }))
);
const assigneeOptions = computed(() =>
  agents.value.map(agent => ({ value: agent.id, label: agent.name }))
);
const openCount = computed(
  () => tasks.value.filter(task => !task.completed_at).length
);

const dueLabel = task => formatDue(task.due_at, locale.value);
const pillOf = task => DUE_PILLS[dueState(task)];

const fail = error =>
  useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.TASKS.FAILED'));

const load = async () => {
  const cardId = props.card.id;
  try {
    const { data } = await FlowKanbanAPI.getCardTasks(cardId);
    if (props.card.id === cardId) tasks.value = data.payload;
  } catch (error) {
    fail(error);
  } finally {
    isLoading.value = false;
  }
};

// What the server says the card holds, against what this list shows: a mismatch means
// someone else changed the tasks while the panel was open.
const summary = list => {
  const open = list.filter(task => !task.completed_at);
  return [
    open.length,
    open.filter(task => task.overdue).length,
    open.length ? Math.min(...open.map(task => task.due_at)) : null,
  ].join();
};
watch(
  () => props.card.tasks,
  server => {
    if (!server || isLoading.value) return;
    const mine = [server.open, server.overdue, server.next_due_at].join();
    if (mine !== summary(tasks.value)) load();
  }
);
watch(() => props.card.id, load);

const add = async () => {
  const title = form.value.title.trim();
  if (!title || !form.value.due || isAdding.value) return;
  isAdding.value = true;
  try {
    const { data } = await FlowKanbanAPI.createCardTask(props.card.id, {
      title,
      task_type: form.value.task_type,
      due_at: dueInputToISO(form.value.due),
      user_id: form.value.user_id,
    });
    tasks.value = [...tasks.value, data.payload].sort(
      (a, b) => a.due_at - b.due_at
    );
    resetForm();
  } catch (error) {
    fail(error);
  } finally {
    isAdding.value = false;
  }
};

const toggle = async (task, done) => {
  try {
    const { data } = await FlowKanbanAPI.updateCardTask(
      props.card.id,
      task.id,
      {
        completed: done,
      }
    );
    tasks.value = tasks.value.map(item =>
      item.id === task.id ? data.payload : item
    );
  } catch (error) {
    fail(error);
  }
};

const remove = async task => {
  try {
    await FlowKanbanAPI.removeCardTask(props.card.id, task.id);
    tasks.value = tasks.value.filter(item => item.id !== task.id);
  } catch (error) {
    fail(error);
  }
};

onMounted(() => {
  resetForm();
  load();
});
</script>

<template>
  <section class="flex flex-col gap-3">
    <div class="flex items-baseline justify-between gap-3">
      <h4 class="text-heading-3 text-n-slate-12">
        {{ t('FLOW_KANBAN.TASKS.SECTION') }}
      </h4>
      <span v-if="openCount" class="text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.TASKS.OPEN_COUNT', { count: openCount }) }}
      </span>
    </div>

    <SkeletonRows v-if="isLoading" />

    <p v-else-if="!tasks.length" class="text-body-main text-n-slate-11">
      {{ t('FLOW_KANBAN.TASKS.EMPTY') }}
    </p>

    <ul
      v-if="tasks.length"
      class="flex flex-col rounded-lg outline outline-1 outline-n-container divide-y divide-n-weak"
    >
      <li
        v-for="task in tasks"
        :key="task.id"
        class="flex items-center gap-3 px-3 py-2"
      >
        <label class="flex">
          <span class="sr-only">
            {{
              task.completed_at
                ? t('FLOW_KANBAN.TASKS.REOPEN')
                : t('FLOW_KANBAN.TASKS.COMPLETE')
            }}
          </span>
          <Checkbox
            :model-value="!!task.completed_at"
            @update:model-value="toggle(task, $event)"
          />
        </label>
        <Icon
          :icon="TASK_TYPE_ICONS[task.task_type]"
          class="flex-shrink-0 size-4 text-n-slate-10"
        />
        <div class="flex flex-col flex-1 min-w-0">
          <span
            class="text-body-main truncate"
            :class="
              task.completed_at
                ? 'line-through text-n-slate-11'
                : 'text-n-slate-12'
            "
          >
            {{ task.title }}
          </span>
          <span class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <StatePill
              v-if="pillOf(task)"
              :tone="pillOf(task).tone"
              :icon="pillOf(task).icon"
              :label="t(`FLOW_KANBAN.TASKS.${pillOf(task).key}`)"
            />
            <span
              class="text-label-small tabular-nums"
              :class="task.completed_at ? 'text-n-slate-11' : 'text-n-slate-11'"
            >
              {{ dueLabel(task) }}
            </span>
          </span>
        </div>
        <Avatar
          v-tooltip.top="task.user.name"
          :src="task.user.thumbnail"
          :name="task.user.name"
          :size="20"
          rounded-full
          aria-hidden="true"
          class="flex-shrink-0"
        />
        <span class="sr-only">{{ task.user.name }}</span>
        <Button
          v-tooltip.top="t('FLOW_KANBAN.TASKS.DELETE')"
          ghost
          slate
          xs
          type="button"
          icon="i-lucide-trash-2"
          :aria-label="t('FLOW_KANBAN.TASKS.DELETE')"
          @click="remove(task)"
        />
      </li>
    </ul>

    <div class="flex flex-col gap-3">
      <Input
        v-model="form.title"
        :label="t('FLOW_KANBAN.TASKS.TITLE')"
        :placeholder="t('FLOW_KANBAN.TASKS.TITLE_PLACEHOLDER')"
        @keydown.enter.prevent="add"
      />
      <div class="grid grid-cols-2 gap-3">
        <Input
          v-model="form.due"
          type="datetime-local"
          :label="t('FLOW_KANBAN.TASKS.DUE')"
          @keydown.enter.prevent="add"
        />
        <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.TASKS.TYPE') }}
          <RequiredComboBox v-model="form.task_type" :options="typeOptions" />
        </label>
      </div>
      <div class="flex items-end gap-3">
        <label
          class="flex flex-col flex-1 min-w-0 gap-1.5 text-label text-n-slate-12"
        >
          {{ t('FLOW_KANBAN.TASKS.ASSIGNEE') }}
          <RequiredComboBox v-model="form.user_id" :options="assigneeOptions" />
        </label>
        <Button
          faded
          blue
          sm
          type="button"
          icon="i-lucide-plus"
          :label="t('FLOW_KANBAN.TASKS.ADD')"
          :is-loading="isAdding"
          :disabled="!form.title.trim() || !form.due || isAdding"
          @click="add"
        />
      </div>
    </div>
  </section>
</template>
