<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import {
  breakpointsTailwind,
  useBreakpoints,
  useDebounceFn,
} from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import KanbanColumn from './KanbanColumn.vue';
import CardPanel from './CardPanel.vue';
import CardCreateDialog from './CardCreateDialog.vue';
import BoardSettingsPanel from './BoardSettingsPanel.vue';
import KanbanNotifications from './KanbanNotifications.vue';
import KanbanFilters from './KanbanFilters.vue';
import MyTasks from './MyTasks.vue';
import EmptyState from './EmptyState.vue';
import LostReasonDialog from './LostReasonDialog.vue';
import KanbanReport from './report/KanbanReport.vue';
import { DEFAULT_PERIOD, PERIODS } from './report/useFlowKanbanReport';
import { useBoardFilters } from './useBoardFilters';
import { endOfLocalDay } from './tasks';

const { t } = useI18n();
const vuexStore = useStore();
const kanban = useFlowKanbanStore();
const { isAdmin } = useAdmin();
const { assigneeOptions, activeCount: activeFilterCount } = useBoardFilters();

// Below `md` the toolbar folds into two rows: board and alerts, then view, search, filters and
// the new card. Its controls grow to `md` (40 px), past the 24 px WCAG 2.2 AA minimum.
const isMobile = useBreakpoints(breakpointsTailwind).smaller('md');
const controlSize = computed(() => (isMobile.value ? 'md' : 'sm'));

const isBoardMenuOpen = ref(false);
const cardPanelRef = ref(null);
const createDialogRef = ref(null);
const settingsPanelRef = ref(null);
const lostDialogRef = ref(null);
const search = ref(kanban.filters.q);
const highlightTaskId = ref(null);

const boardMenuItems = computed(() => [
  ...kanban.boards.map(board => ({
    label: board.name,
    value: board.id,
    action: 'select',
    isSelected: board.id === kanban.activeBoardId,
  })),
  ...(isAdmin.value
    ? [
        {
          label: t('FLOW_KANBAN.NEW_BOARD'),
          value: 'new',
          action: 'new',
          icon: 'i-lucide-plus',
        },
      ]
    : []),
]);

const applySearch = useDebounceFn(value => {
  kanban.setFilters({ q: value.trim() });
}, 300);
watch(search, applySearch);

const clearFilters = () => {
  search.value = '';
  kanban.resetFilters();
};

// Board, my tasks or report, remembered per browser like the last board.
const VIEW_KEY = 'flow_kanban_view';
const VIEWS = ['board', 'tasks', 'report'];
const readView = () => {
  try {
    const stored = window.localStorage.getItem(VIEW_KEY);
    return VIEWS.includes(stored) ? stored : 'board';
  } catch {
    return 'board';
  }
};
const view = ref(readView());
const setView = value => {
  view.value = value;
  try {
    window.localStorage.setItem(VIEW_KEY, value);
  } catch {
    // Storage blocked: the view is simply not remembered.
  }
};
const viewOptions = computed(() => [
  {
    value: 'board',
    label: t('FLOW_KANBAN.VIEW.BOARD'),
    icon: 'i-lucide-columns-3',
  },
  {
    value: 'tasks',
    label: t('FLOW_KANBAN.VIEW.TASKS'),
    icon: 'i-lucide-list-checks',
  },
  {
    value: 'report',
    label: t('FLOW_KANBAN.VIEW.REPORT'),
    icon: 'i-lucide-chart-column',
  },
]);

// The My tasks badge: own tasks overdue or due today, in ruby when any is overdue.
const taskBadge = computed(
  () => kanban.taskCounts.overdue + kanban.taskCounts.dueToday
);
const taskBadgeLabel = computed(() =>
  t('FLOW_KANBAN.VIEW.TASKS_BADGE', {
    overdue: kanban.taskCounts.overdue,
    today: kanban.taskCounts.dueToday,
  })
);
const viewAriaLabel = option =>
  option.value === 'tasks' && taskBadge.value
    ? `${option.label}, ${taskBadgeLabel.value}`
    : option.label;
const refreshTaskCounts = () =>
  kanban.fetchTaskCounts(endOfLocalDay().toISOString()).catch(() => {});
watch(() => kanban.lastCardEvent, useDebounceFn(refreshTaskCounts, 1500));

// Report filters: a period that is always set, and the same assignee choices as the board.
const periodOptions = computed(() =>
  Object.keys(PERIODS).map(id => ({
    id,
    name: t(`FLOW_KANBAN.REPORT.PERIOD.${id}`),
    icon: 'i-lucide-calendar',
  }))
);
const reportPeriod = ref({ id: DEFAULT_PERIOD });
const reportAssignee = ref(null);
// The count on the mobile Filters button, for the view it filters.
const filterCount = computed(() => {
  if (view.value === 'report') return reportAssignee.value ? 1 : 0;
  return activeFilterCount.value;
});

const onBoardMenuAction = ({ action, value }) => {
  isBoardMenuOpen.value = false;
  if (action === 'new') settingsPanelRef.value?.open(null);
  else kanban.selectBoard(value);
};

const openCard = card => cardPanelRef.value?.open(card.id);
const openCreate = stage => createDialogRef.value?.open(stage?.id);
const openTask = ({ taskId }) => {
  setView('tasks');
  highlightTaskId.value = taskId;
};

const onMove = async move => {
  const target = kanban.stages.find(stage => stage.id === move.toStageId);
  let lost = {};
  if (target?.stage_type === 'lost' && move.fromStageId !== move.toStageId) {
    const answer = await lostDialogRef.value?.ask();
    if (!answer) {
      // Cancelled: the card was dragged already, so the board is read again to put it back.
      await kanban.fetchCards();
      return;
    }
    lost = answer;
  }
  try {
    await kanban.moveCard({ ...move, ...lost });
  } catch {
    useAlert(t('FLOW_KANBAN.ERRORS.MOVE'));
  }
};

onMounted(async () => {
  vuexStore.dispatch('agents/get');
  vuexStore.dispatch('inboxes/get');
  vuexStore.dispatch('teams/get');
  refreshTaskCounts();
  await kanban.fetchBoards();
  await kanban.fetchCards();
});

const SKELETON_COLUMNS = 4;
const SKELETON_CARDS = [3, 2, 4, 1];
</script>

<template>
  <section class="flex flex-col w-full h-full min-w-0 bg-n-surface-1">
    <header
      class="flex flex-shrink-0 gap-2 border-b border-n-weak"
      :class="
        isMobile
          ? 'flex-col px-4 py-3'
          : 'flex-wrap items-center gap-3 px-6 py-3'
      "
    >
      <div
        class="flex items-center min-w-0 gap-1"
        :class="{ 'w-full': isMobile }"
      >
        <div class="relative min-w-0" :class="{ 'flex-1': isMobile }">
          <Button
            ghost
            slate
            :size="controlSize"
            trailing-icon
            icon="i-lucide-chevrons-up-down"
            :label="kanban.activeBoard?.name || t('FLOW_KANBAN.TITLE')"
            :disabled="!kanban.boards.length && !isAdmin"
            class="!text-heading-2 !text-n-slate-12 max-w-full"
            @click="isBoardMenuOpen = !isBoardMenuOpen"
          />
          <DropdownMenu
            v-if="isBoardMenuOpen"
            v-on-click-outside="() => (isBoardMenuOpen = false)"
            :menu-items="boardMenuItems"
            :show-search="kanban.boards.length > 6"
            :search-placeholder="t('FLOW_KANBAN.SELECT_BOARD')"
            class="top-full mt-1 start-0 z-20 w-64 max-h-96"
            @action="onBoardMenuAction"
          />
        </div>
        <template v-if="isMobile && kanban.activeBoard">
          <KanbanNotifications
            size="md"
            @open-card="openCard"
            @open-task="openTask"
          />
          <Button
            v-if="isAdmin"
            v-tooltip.bottom="t('FLOW_KANBAN.BOARD_SETTINGS')"
            ghost
            slate
            md
            icon="i-lucide-settings-2"
            :aria-label="t('FLOW_KANBAN.BOARD_SETTINGS')"
            @click="settingsPanelRef?.open(kanban.activeBoard)"
          />
        </template>
      </div>

      <div
        v-if="kanban.activeBoard"
        class="flex items-center min-w-0 gap-2"
        :class="isMobile ? 'w-full' : 'flex-1'"
      >
        <ButtonGroup
          role="radiogroup"
          :aria-label="t('FLOW_KANBAN.VIEW.LABEL')"
          class="flex items-center flex-shrink-0 gap-0.5 p-0.5 rounded-lg bg-n-alpha-1"
        >
          <Button
            v-for="option in viewOptions"
            :key="option.value"
            v-tooltip.bottom="isMobile ? option.label : null"
            ghost
            :size="isMobile ? 'sm' : 'xs'"
            type="button"
            role="radio"
            :aria-checked="view === option.value"
            :aria-label="viewAriaLabel(option)"
            :icon="option.icon"
            :color="view === option.value ? 'blue' : 'slate'"
            :class="{ 'bg-n-solid-1 shadow-sm': view === option.value }"
            @click="setView(option.value)"
          >
            <span v-if="!isMobile" class="min-w-0 truncate">
              {{ option.label }}
            </span>
            <span
              v-if="option.value === 'tasks' && taskBadge"
              aria-hidden="true"
              class="px-1 rounded-md tabular-nums text-label-small"
              :class="
                kanban.taskCounts.overdue
                  ? 'bg-n-ruby-3 text-n-ruby-11'
                  : 'bg-n-alpha-2 text-n-slate-11'
              "
            >
              {{ taskBadge }}
            </span>
          </Button>
        </ButtonGroup>

        <div
          class="flex items-center min-w-0 gap-2 ms-auto"
          :class="isMobile ? 'flex-1' : 'flex-wrap justify-end'"
        >
          <template v-if="view === 'board'">
            <Input
              v-model="search"
              type="search"
              :size="controlSize"
              :class="isMobile ? 'flex-1 min-w-0' : 'w-56 xl:w-64'"
              :placeholder="t('FLOW_KANBAN.FILTERS.SEARCH')"
              custom-input-class="!ps-8"
            >
              <template #prefix>
                <Icon
                  icon="i-lucide-search"
                  class="absolute z-10 -translate-y-1/2 pointer-events-none size-3.5 text-n-slate-10 top-1/2 start-2.5"
                />
              </template>
            </Input>
            <KanbanFilters
              v-if="!isMobile"
              class="flex-shrink-0"
              @clear="clearFilters"
            />
          </template>

          <template v-else-if="view === 'report' && !isMobile">
            <SingleSelect
              v-model="reportPeriod"
              :options="periodOptions"
              disable-search
              disable-deselect
              placeholder-icon="i-lucide-chevron-down"
              placeholder-trailing-icon
            />
            <SingleSelect
              v-model="reportAssignee"
              :options="assigneeOptions"
              :placeholder="t('FLOW_KANBAN.FILTERS.ALL_AGENTS')"
              :search-placeholder="t('FLOW_KANBAN.FILTERS.SEARCH_AGENT')"
              placeholder-icon="i-lucide-chevron-down"
              placeholder-trailing-icon
            />
          </template>

          <span v-else-if="isMobile" class="flex-1" />

          <Popover v-if="isMobile && view !== 'tasks'" align="end">
            <span class="relative inline-flex">
              <Button
                v-tooltip.bottom="t('FLOW_KANBAN.FILTERS.BUTTON')"
                faded
                slate
                md
                icon="i-lucide-sliders-horizontal"
                :aria-label="
                  t('FLOW_KANBAN.FILTERS.BUTTON_COUNT', { count: filterCount })
                "
              />
              <span
                v-if="filterCount"
                aria-hidden="true"
                class="absolute -top-1 -end-1 min-w-4 h-4 px-1 text-center text-white rounded-full pointer-events-none text-label-small tabular-nums bg-n-brand"
              >
                {{ filterCount }}
              </span>
            </span>
            <template #content>
              <div class="flex flex-col gap-3 p-4">
                <h4 class="text-heading-3 text-n-slate-12">
                  {{ t('FLOW_KANBAN.FILTERS.BUTTON') }}
                </h4>
                <KanbanFilters
                  v-if="view === 'board'"
                  stacked
                  @clear="clearFilters"
                />
                <div v-else class="flex flex-col items-stretch gap-2">
                  <SingleSelect
                    v-model="reportPeriod"
                    :options="periodOptions"
                    disable-search
                    disable-deselect
                    placeholder-icon="i-lucide-chevron-down"
                    placeholder-trailing-icon
                  />
                  <SingleSelect
                    v-model="reportAssignee"
                    :options="assigneeOptions"
                    :placeholder="t('FLOW_KANBAN.FILTERS.ALL_AGENTS')"
                    :search-placeholder="t('FLOW_KANBAN.FILTERS.SEARCH_AGENT')"
                    placeholder-icon="i-lucide-chevron-down"
                    placeholder-trailing-icon
                  />
                </div>
              </div>
            </template>
          </Popover>

          <template v-if="!isMobile">
            <KanbanNotifications @open-card="openCard" @open-task="openTask" />
            <Button
              v-if="isAdmin"
              v-tooltip.bottom="t('FLOW_KANBAN.BOARD_SETTINGS')"
              ghost
              slate
              sm
              icon="i-lucide-settings-2"
              :aria-label="t('FLOW_KANBAN.BOARD_SETTINGS')"
              @click="settingsPanelRef?.open(kanban.activeBoard)"
            />
          </template>

          <Button
            v-if="view === 'board'"
            v-tooltip.bottom="isMobile ? t('FLOW_KANBAN.NEW_CARD') : null"
            solid
            blue
            :size="controlSize"
            icon="i-lucide-plus"
            :label="isMobile ? '' : t('FLOW_KANBAN.NEW_CARD')"
            :aria-label="t('FLOW_KANBAN.NEW_CARD')"
            class="flex-shrink-0"
            @click="openCreate(kanban.stages[0])"
          />
        </div>
      </div>
    </header>

    <div
      v-if="
        !kanban.boardsLoaded ||
        (kanban.isLoadingCards && !Object.keys(kanban.columns).length)
      "
      class="flex flex-1 min-h-0 gap-3 p-4 overflow-hidden"
      aria-busy="true"
      :aria-label="t('FLOW_KANBAN.LOADING')"
    >
      <div
        v-for="column in SKELETON_COLUMNS"
        :key="column"
        class="flex flex-col flex-shrink-0 gap-2 p-3 w-72 rounded-xl bg-n-alpha-1"
      >
        <!-- design-audit-allow: hand-built-skeleton (column header shape) -->
        <div class="w-24 h-4 mb-1 rounded bg-n-alpha-2 animate-pulse" />
        <!-- design-audit-allow: hand-built-skeleton (card shapes of the board) -->
        <div
          v-for="card in SKELETON_CARDS[column - 1]"
          :key="card"
          class="h-20 rounded-lg bg-n-alpha-2 animate-pulse"
        />
      </div>
    </div>

    <EmptyState
      v-else-if="!kanban.boards.length"
      class="justify-center flex-1"
      title-tag="h2"
      icon="i-lucide-columns-3"
      :title="t('FLOW_KANBAN.EMPTY.NO_BOARDS_TITLE')"
      :description="
        isAdmin
          ? t('FLOW_KANBAN.EMPTY.NO_BOARDS_ADMIN')
          : t('FLOW_KANBAN.EMPTY.NO_BOARDS_AGENT')
      "
    >
      <Button
        v-if="isAdmin"
        solid
        blue
        sm
        icon="i-lucide-plus"
        :label="t('FLOW_KANBAN.NEW_BOARD')"
        @click="settingsPanelRef?.open(null)"
      />
    </EmptyState>

    <MyTasks
      v-else-if="view === 'tasks'"
      :highlight-task-id="highlightTaskId"
      @open-card="openCard"
      @changed="refreshTaskCounts"
    />

    <KanbanReport
      v-else-if="view === 'report' && kanban.activeBoardId"
      :board-id="kanban.activeBoardId"
      :period="reportPeriod?.id || DEFAULT_PERIOD"
      :assignee-id="reportAssignee?.id ?? ''"
    />

    <div
      v-else
      class="flex items-start flex-1 min-h-0 gap-3 p-4 overflow-x-auto transition-opacity duration-150"
      :class="{ 'opacity-60': kanban.isLoadingCards }"
    >
      <KanbanColumn
        v-for="stage in kanban.stages"
        :key="stage.id"
        :stage="stage"
        :column="kanban.columns[stage.id] || { cards: [], total: 0 }"
        class="h-full"
        @open="openCard"
        @add="openCreate"
        @move="onMove"
        @load-more="kanban.loadMore"
      />
    </div>

    <CardPanel ref="cardPanelRef" />
    <LostReasonDialog ref="lostDialogRef" />
    <CardCreateDialog ref="createDialogRef" />
    <BoardSettingsPanel ref="settingsPanelRef" />
  </section>
</template>
