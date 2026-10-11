<script setup>
import { useI18n } from 'vue-i18n';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';

import Button from 'dashboard/components-next/button/Button.vue';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import { useBoardFilters } from './useBoardFilters';

// The board filters: in a row in the desktop toolbar, stacked in the mobile Filters popover.
defineProps({
  stacked: { type: Boolean, default: false },
});

const emit = defineEmits(['clear']);

const { t } = useI18n();
const kanban = useFlowKanbanStore();
const {
  assigneeOptions,
  inboxOptions,
  statusOptions,
  filterModel,
  activeCount,
} = useBoardFilters();

const statusFilter = filterModel('status');
const assigneeFilter = filterModel('assignee_id');
const inboxFilter = filterModel('inbox_id');
</script>

<template>
  <div
    class="flex gap-2"
    :class="stacked ? 'flex-col items-stretch' : 'flex-wrap items-center'"
  >
    <SingleSelect
      v-model="statusFilter"
      :options="statusOptions"
      :placeholder="t('FLOW_KANBAN.FILTERS.ALL_STATUSES')"
      disable-search
      placeholder-icon="i-lucide-chevron-down"
      placeholder-trailing-icon
    />
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
      v-if="kanban.hasActiveFilters || activeCount"
      link
      slate
      sm
      :class="{ 'self-start': stacked }"
      :label="t('FLOW_KANBAN.FILTERS.CLEAR')"
      @click="emit('clear')"
    />
  </div>
</template>
