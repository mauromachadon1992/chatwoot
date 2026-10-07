<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useDebounceFn } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import KanbanColumn from './KanbanColumn.vue';
import CardPanel from './CardPanel.vue';
import CardCreateDialog from './CardCreateDialog.vue';
import BoardSettingsPanel from './BoardSettingsPanel.vue';
import KanbanNotifications from './KanbanNotifications.vue';
import KanbanReport from './report/KanbanReport.vue';
import { DEFAULT_PERIOD, PERIODS } from './report/useFlowKanbanReport';

const { t } = useI18n();
const vuexStore = useStore();
const kanban = useFlowKanbanStore();
const { isAdmin } = useAdmin();

const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');

const isBoardMenuOpen = ref(false);
const cardPanelRef = ref(null);
const createDialogRef = ref(null);
const settingsPanelRef = ref(null);
const search = ref(kanban.filters.q);

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

// Header filters use Chatwoot's filter dropdown (SingleSelect): it works with
// { id, name, icon } objects, and clearing the selection means "all".
const assigneeOptions = computed(() => [
  {
    id: 'none',
    name: t('FLOW_KANBAN.FILTERS.UNASSIGNED'),
    icon: 'i-lucide-user-x',
  },
  ...agents.value.map(agent => ({
    id: agent.id,
    name: agent.name,
    icon: 'i-lucide-user',
  })),
]);

const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({
    id: inbox.id,
    name: inbox.name,
    icon: getInboxIconByType(inbox.channel_type, inbox.medium, 'line'),
  }))
);

const filterModel = key =>
  computed({
    get: () => {
      const value = kanban.filters[key];
      return value === '' ? null : { id: value };
    },
    set: option => kanban.setFilters({ [key]: option?.id ?? '' }),
  });

const assigneeFilter = filterModel('assignee_id');
const inboxFilter = filterModel('inbox_id');

const applySearch = useDebounceFn(value => {
  kanban.setFilters({ q: value.trim() });
}, 300);
watch(search, applySearch);

const clearFilters = () => {
  search.value = '';
  kanban.resetFilters();
};

// Board or report, remembered per browser like the last board.
const VIEW_KEY = 'flow_kanban_view';
const readView = () => {
  try {
    return window.localStorage.getItem(VIEW_KEY) === 'report'
      ? 'report'
      : 'board';
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
    value: 'report',
    label: t('FLOW_KANBAN.VIEW.REPORT'),
    icon: 'i-lucide-chart-column',
  },
]);

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

const onBoardMenuAction = ({ action, value }) => {
  isBoardMenuOpen.value = false;
  if (action === 'new') settingsPanelRef.value?.open(null);
  else kanban.selectBoard(value);
};

const openCard = card => cardPanelRef.value?.open(card.id);
const openCreate = stage => createDialogRef.value?.open(stage?.id);

const onMove = async move => {
  try {
    await kanban.moveCard(move);
  } catch {
    useAlert(t('FLOW_KANBAN.ERRORS.MOVE'));
  }
};

onMounted(async () => {
  vuexStore.dispatch('agents/get');
  vuexStore.dispatch('inboxes/get');
  vuexStore.dispatch('teams/get');
  await kanban.fetchBoards();
  await kanban.fetchCards();
});

const SKELETON_COLUMNS = 4;
const SKELETON_CARDS = [3, 2, 4, 1];
</script>

<template>
  <section class="flex flex-col w-full h-full min-w-0 bg-n-surface-1">
    <header
      class="flex flex-wrap items-center flex-shrink-0 gap-3 px-6 py-3 border-b border-n-weak"
    >
      <div class="relative">
        <Button
          ghost
          slate
          sm
          trailing-icon
          icon="i-lucide-chevrons-up-down"
          :label="kanban.activeBoard?.name || t('FLOW_KANBAN.TITLE')"
          :disabled="!kanban.boards.length && !isAdmin"
          class="!text-heading-2 !text-n-slate-12"
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

      <ButtonGroup
        v-if="kanban.activeBoard"
        role="radiogroup"
        :aria-label="t('FLOW_KANBAN.VIEW.LABEL')"
        class="flex items-center gap-0.5 p-0.5 rounded-lg bg-n-alpha-1"
      >
        <Button
          v-for="option in viewOptions"
          :key="option.value"
          ghost
          xs
          type="button"
          role="radio"
          :aria-checked="view === option.value"
          :icon="option.icon"
          :label="option.label"
          :color="view === option.value ? 'blue' : 'slate'"
          :class="{ 'bg-n-solid-1 shadow-sm': view === option.value }"
          @click="setView(option.value)"
        />
      </ButtonGroup>

      <div
        v-if="kanban.activeBoard && view === 'report'"
        class="flex flex-wrap items-center gap-2 ms-auto"
      >
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
        <KanbanNotifications @open-card="openCard" />
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
      </div>

      <template v-else-if="kanban.activeBoard">
        <div class="flex flex-wrap items-center gap-2 ms-auto">
          <Input
            v-model="search"
            type="search"
            size="sm"
            class="w-56 xl:w-64"
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
          <SingleSelect
            v-model="assigneeFilter"
            :options="assigneeOptions"
            :placeholder="t('FLOW_KANBAN.FILTERS.ALL_AGENTS')"
            :search-placeholder="t('FLOW_KANBAN.FILTERS.SEARCH_AGENT')"
            placeholder-icon="i-lucide-chevron-down"
            placeholder-trailing-icon
          />
          <SingleSelect
            v-model="inboxFilter"
            :options="inboxOptions"
            :placeholder="t('FLOW_KANBAN.FILTERS.ALL_INBOXES')"
            :search-placeholder="t('FLOW_KANBAN.FILTERS.SEARCH_INBOX')"
            placeholder-icon="i-lucide-chevron-down"
            placeholder-trailing-icon
          />
          <Button
            v-if="kanban.hasActiveFilters"
            link
            slate
            sm
            :label="t('FLOW_KANBAN.FILTERS.CLEAR')"
            @click="clearFilters"
          />
          <KanbanNotifications @open-card="openCard" />
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
          <Button
            solid
            blue
            sm
            icon="i-lucide-plus"
            :label="t('FLOW_KANBAN.NEW_CARD')"
            @click="openCreate(kanban.stages[0])"
          />
        </div>
      </template>
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
        <div class="w-24 h-4 mb-1 rounded bg-n-alpha-2 animate-pulse" />
        <div
          v-for="card in SKELETON_CARDS[column - 1]"
          :key="card"
          class="h-20 rounded-lg bg-n-alpha-2 animate-pulse"
        />
      </div>
    </div>

    <div
      v-else-if="!kanban.boards.length"
      class="flex flex-col items-center justify-center flex-1 gap-4 px-6 text-center"
    >
      <span
        class="flex items-center justify-center rounded-xl size-12 bg-n-alpha-2 text-n-slate-11"
      >
        <Icon icon="i-lucide-columns-3" class="size-6" />
      </span>
      <div class="flex flex-col gap-1 max-w-md">
        <h2 class="text-heading-2 text-n-slate-12">
          {{ t('FLOW_KANBAN.EMPTY.NO_BOARDS_TITLE') }}
        </h2>
        <p class="text-body-main text-n-slate-11">
          {{
            isAdmin
              ? t('FLOW_KANBAN.EMPTY.NO_BOARDS_ADMIN')
              : t('FLOW_KANBAN.EMPTY.NO_BOARDS_AGENT')
          }}
        </p>
      </div>
      <Button
        v-if="isAdmin"
        solid
        blue
        sm
        icon="i-lucide-plus"
        :label="t('FLOW_KANBAN.NEW_BOARD')"
        @click="settingsPanelRef?.open(null)"
      />
    </div>

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
    <CardCreateDialog ref="createDialogRef" />
    <BoardSettingsPanel ref="settingsPanelRef" />
  </section>
</template>
