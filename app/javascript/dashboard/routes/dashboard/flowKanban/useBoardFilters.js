import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import { useFlowKanban } from './useFlowKanban';

// The board's filters, shared by the desktop toolbar and the mobile Filters popover. They use
// Chatwoot's filter dropdown (SingleSelect): { id, name, icon } options, clearing means "all".
export function useBoardFilters() {
  const { t } = useI18n();
  const kanban = useFlowKanbanStore();
  const agents = useMapGetter('agents/getAgents');
  const inboxes = useMapGetter('inboxes/getInboxes');
  const { hasFeature } = useFlowKanban();

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

  // The Situation filter. Stalled deals only exist where the account has the alerts on.
  const statusOptions = computed(() => [
    ...(hasFeature('stale_alerts')
      ? [
          {
            id: 'stale',
            name: t('FLOW_KANBAN.FILTERS.STATUS_STALE'),
            icon: 'i-lucide-hourglass',
          },
        ]
      : []),
    {
      id: 'overdue_tasks',
      name: t('FLOW_KANBAN.FILTERS.STATUS_OVERDUE_TASKS'),
      icon: 'i-lucide-alarm-clock',
    },
  ]);

  const filterModel = key =>
    computed({
      get: () => {
        const value = kanban.filters[key];
        return value === '' ? null : { id: value };
      },
      set: option => kanban.setFilters({ [key]: option?.id ?? '' }),
    });

  // The search box sits outside the filters, so it does not count here.
  const activeCount = computed(
    () =>
      Object.entries(kanban.filters).filter(
        ([key, value]) => key !== 'q' && value !== ''
      ).length
  );

  return {
    assigneeOptions,
    inboxOptions,
    statusOptions,
    filterModel,
    activeCount,
  };
}
