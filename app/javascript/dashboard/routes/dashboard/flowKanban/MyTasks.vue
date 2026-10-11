<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import EmptyState from './EmptyState.vue';
import SegmentedControl from './SegmentedControl.vue';
import SkeletonRows from './SkeletonRows.vue';
import StatePill from './StatePill.vue';
import {
  DUE_PILLS,
  TASK_TYPE_ICONS,
  dueState,
  formatDue,
  groupOpenTasks,
} from './tasks';
import { useFlowKanban } from './useFlowKanban';

// My tasks: the follow-ups of every deal the agent can see, grouped by the agent's own day.
// Completing one moves it to "Done recently", where ticking it again reopens it: every change
// stays visible and reversible without a dialog.
const props = defineProps({
  // A task to bring into view (from the bell).
  highlightTaskId: { type: Number, default: null },
});

const emit = defineEmits(['openCard', 'changed']);

const { t, locale } = useI18n();
const { isAdmin } = useAdmin();
const kanban = useFlowKanbanStore();
const { relativeTime } = useFlowKanban();

const scope = ref('mine');
const openTasks = ref([]);
const doneTasks = ref([]);
const page = ref(1);
const hasMore = ref(false);
const isLoading = ref(true);
const isLoadingMore = ref(false);
const hasError = ref(false);
const highlighted = ref(null);
const busy = ref(new Set());

const scopeOptions = computed(() => [
  { value: 'mine', label: t('FLOW_KANBAN.MY_TASKS.SCOPE_MINE') },
  { value: 'all', label: t('FLOW_KANBAN.MY_TASKS.SCOPE_ALL') },
]);
const showAssignee = computed(() => scope.value === 'all');
const showBoard = computed(() => kanban.boards.length > 1);

const openGroups = computed(() => groupOpenTasks(openTasks.value));
const overdueCount = computed(() => openGroups.value.overdue.length);
const groups = computed(() =>
  [
    { key: 'overdue', tasks: openGroups.value.overdue },
    { key: 'today', tasks: openGroups.value.today },
    { key: 'upcoming', tasks: openGroups.value.upcoming },
    { key: 'done', tasks: doneTasks.value },
  ].filter(group => group.tasks.length)
);
// "Load more" closes the open part of the list, whichever open group comes last.
const lastOpenGroup = computed(
  () => groups.value.filter(group => group.key !== 'done').pop()?.key
);
const hasOpen = computed(() => openTasks.value.length > 0);

const pillOf = task => DUE_PILLS[dueState(task)];

const fetchPage = (status, pageNumber) =>
  FlowKanbanAPI.getTasks({ scope: scope.value, status, page: pageNumber });

const load = async ({ quiet = false } = {}) => {
  if (!quiet) isLoading.value = true;
  hasError.value = false;
  try {
    const [open, done] = await Promise.all([
      fetchPage('open', 1),
      fetchPage('done', 1),
    ]);
    openTasks.value = open.data.payload;
    doneTasks.value = done.data.payload;
    page.value = 1;
    hasMore.value = open.data.meta.has_more;
  } catch {
    if (!quiet) hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const loadMore = async () => {
  isLoadingMore.value = true;
  try {
    const { data } = await fetchPage('open', page.value + 1);
    const known = new Set(openTasks.value.map(task => task.id));
    openTasks.value = [
      ...openTasks.value,
      ...data.payload.filter(task => !known.has(task.id)),
    ];
    page.value += 1;
    hasMore.value = data.meta.has_more;
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));
  } finally {
    isLoadingMore.value = false;
  }
};

const byDue = (a, b) => a.due_at - b.due_at || a.id - b.id;

const toggle = async (task, done) => {
  if (busy.value.has(task.id)) return;
  busy.value = new Set([...busy.value, task.id]);
  try {
    const { data } = await FlowKanbanAPI.updateCardTask(task.card.id, task.id, {
      completed: done,
    });
    const updated = { ...task, ...data.payload, card: task.card };
    if (done) {
      openTasks.value = openTasks.value.filter(item => item.id !== task.id);
      doneTasks.value = [updated, ...doneTasks.value];
    } else {
      doneTasks.value = doneTasks.value.filter(item => item.id !== task.id);
      openTasks.value = [...openTasks.value, updated].sort(byDue);
    }
    emit('changed');
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.TASKS.FAILED'));
  } finally {
    const next = new Set(busy.value);
    next.delete(task.id);
    busy.value = next;
  }
};

const bringIntoView = async taskId => {
  if (!taskId || isLoading.value) return;
  await nextTick();
  const row = document.getElementById(`flow-task-${taskId}`);
  if (!row) return;
  row.scrollIntoView({ block: 'center', behavior: 'smooth' });
  row.focus({ preventScroll: true });
  highlighted.value = taskId;
  setTimeout(() => {
    if (highlighted.value === taskId) highlighted.value = null;
  }, 2500);
};

// Tasks changed elsewhere (the card panel, another agent) arrive as card events: the list
// follows them quietly, without a skeleton.
const followCardEvents = useDebounceFn(() => load({ quiet: true }), 1500);
watch(() => kanban.lastCardEvent, followCardEvents);
watch(scope, () => load());
watch(
  () => [props.highlightTaskId, isLoading.value],
  ([taskId]) => bringIntoView(taskId)
);

onMounted(load);
</script>

<template>
  <section class="flex flex-col flex-1 min-h-0 overflow-y-auto">
    <div
      class="flex flex-col w-full max-w-3xl gap-6 px-4 py-6 mx-auto md:px-6"
      :aria-busy="isLoading"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex flex-col gap-1 min-w-0">
          <h2 class="text-heading-1 text-n-slate-12">
            {{
              scope === 'all'
                ? t('FLOW_KANBAN.MY_TASKS.TITLE_ALL')
                : t('FLOW_KANBAN.MY_TASKS.TITLE_MINE')
            }}
          </h2>
          <p v-if="!isLoading" class="text-body-main text-n-slate-11">
            {{
              t('FLOW_KANBAN.MY_TASKS.SUMMARY', {
                open: openTasks.length + (hasMore ? '+' : ''),
                overdue: overdueCount,
              })
            }}
          </p>
        </div>
        <SegmentedControl
          v-if="isAdmin"
          v-model="scope"
          :options="scopeOptions"
          :aria-label="t('FLOW_KANBAN.MY_TASKS.SCOPE')"
          class="w-full sm:w-auto sm:min-w-[16rem]"
        />
      </div>

      <SkeletonRows v-if="isLoading" :rows="4" height="h-14" />

      <EmptyState
        v-else-if="hasError"
        framed
        icon="i-lucide-cloud-off"
        :title="t('FLOW_KANBAN.MY_TASKS.ERROR_TITLE')"
        :description="t('FLOW_KANBAN.MY_TASKS.ERROR_TEXT')"
      >
        <Button
          faded
          slate
          sm
          icon="i-lucide-rotate-cw"
          :label="t('FLOW_KANBAN.MY_TASKS.RETRY')"
          @click="load()"
        />
      </EmptyState>

      <template v-else>
        <EmptyState
          v-if="!hasOpen"
          framed
          icon="i-lucide-list-checks"
          :title="t('FLOW_KANBAN.MY_TASKS.EMPTY_TITLE')"
          :description="t('FLOW_KANBAN.MY_TASKS.EMPTY_TEXT')"
        />

        <section
          v-for="group in groups"
          :key="group.key"
          class="flex flex-col gap-2"
          :aria-labelledby="`flow-tasks-${group.key}`"
        >
          <h3
            :id="`flow-tasks-${group.key}`"
            class="flex items-center gap-2 text-heading-3 text-n-slate-12"
          >
            {{ t(`FLOW_KANBAN.MY_TASKS.GROUPS.${group.key.toUpperCase()}`) }}
            <span
              class="px-1.5 rounded-md tabular-nums text-label-small bg-n-alpha-2 text-n-slate-11"
            >
              {{ group.tasks.length }}
            </span>
          </h3>

          <ul
            class="flex flex-col rounded-lg outline outline-1 outline-n-container divide-y divide-n-weak bg-n-solid-1"
          >
            <li
              v-for="task in group.tasks"
              :id="`flow-task-${task.id}`"
              :key="task.id"
              tabindex="-1"
              class="flex items-center gap-3 px-3 py-3 transition-colors duration-500 focus-visible:outline-2 focus-visible:outline-n-brand"
              :class="{ 'bg-n-blue-3': highlighted === task.id }"
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
                  :disabled="busy.has(task.id)"
                  @update:model-value="toggle(task, $event)"
                />
              </label>
              <Icon
                :icon="TASK_TYPE_ICONS[task.task_type]"
                class="flex-shrink-0 size-4 text-n-slate-10"
              />
              <div class="flex flex-col flex-1 min-w-0 gap-1">
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
                <div
                  class="flex flex-wrap items-center gap-x-2 gap-y-1 text-label-small text-n-slate-11"
                >
                  <StatePill
                    v-if="pillOf(task)"
                    :tone="pillOf(task).tone"
                    :icon="pillOf(task).icon"
                    :label="t(`FLOW_KANBAN.TASKS.${pillOf(task).key}`)"
                  />
                  <span v-if="task.completed_at" class="tabular-nums">
                    {{
                      t('FLOW_KANBAN.MY_TASKS.DONE_AT', {
                        time: relativeTime(task.completed_at),
                      })
                    }}
                  </span>
                  <span v-else class="tabular-nums">
                    {{ formatDue(task.due_at, locale) }}
                  </span>
                  <span aria-hidden="true">·</span>
                  <Button
                    link
                    slate
                    sm
                    type="button"
                    class="min-w-0 !text-label-small"
                    :label="task.card.title"
                    @click="emit('openCard', { id: task.card.id })"
                  />
                  <template v-if="showBoard">
                    <span aria-hidden="true">·</span>
                    <span class="truncate">{{ task.card.board_name }}</span>
                  </template>
                </div>
              </div>
              <Avatar
                v-if="showAssignee"
                v-tooltip.top="task.user.name"
                :src="task.user.thumbnail"
                :name="task.user.name"
                :size="24"
                rounded-full
                aria-hidden="true"
                class="flex-shrink-0"
              />
              <span v-if="showAssignee" class="sr-only">{{
                task.user.name
              }}</span>
            </li>
          </ul>

          <Button
            v-if="group.key === lastOpenGroup && hasMore"
            faded
            slate
            sm
            class="self-center"
            :label="t('FLOW_KANBAN.MY_TASKS.LOAD_MORE')"
            :is-loading="isLoadingMore"
            @click="loadMore"
          />
        </section>
      </template>
    </div>
  </section>
</template>
