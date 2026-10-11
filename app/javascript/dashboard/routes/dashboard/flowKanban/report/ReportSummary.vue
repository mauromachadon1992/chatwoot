<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useFlowKanban } from '../useFlowKanban';
import { formatPercent } from '../money';
import { useDuration } from './useDuration';

// The period at a glance, in one strip like Chatwoot's own report metrics: each figure with
// its definition a hover away, since "won" and "win rate" can be read more than one way.
const props = defineProps({
  summary: { type: Object, default: null },
  isLoading: { type: Boolean, default: false },
});

const { t, locale } = useI18n();
const { money } = useFlowKanban();
const { duration } = useDuration();

const deals = count => t('FLOW_KANBAN.REPORT.SUMMARY.DEALS', { count }, count);
const NONE = '—';

const metrics = computed(() => {
  const s = props.summary;
  if (!s) return [];
  return [
    {
      key: 'OPEN',
      value: money(s.open.value_cents, { whole: true }),
      detail: deals(s.open.count),
    },
    {
      key: 'WON',
      value: money(s.won.value_cents, { whole: true }),
      detail: deals(s.won.count),
    },
    {
      key: 'LOST',
      value: money(s.lost.value_cents, { whole: true }),
      detail: deals(s.lost.count),
    },
    {
      key: 'WIN_RATE',
      value:
        s.win_rate === null ? NONE : formatPercent(s.win_rate, locale.value),
      detail:
        s.win_rate === null
          ? t('FLOW_KANBAN.REPORT.SUMMARY.NO_CLOSED')
          : deals(s.won.count + s.lost.count),
    },
    {
      key: 'AVERAGE_WON',
      value:
        s.average_won_cents === null
          ? NONE
          : money(s.average_won_cents, { whole: true }),
    },
    {
      key: 'CYCLE',
      value:
        s.average_cycle_seconds === null
          ? NONE
          : duration(s.average_cycle_seconds),
    },
  ];
});
</script>

<template>
  <section
    :aria-label="t('FLOW_KANBAN.REPORT.SUMMARY.LABEL')"
    :aria-busy="isLoading"
    class="grid grid-cols-2 gap-y-5 px-6 py-5 sm:grid-cols-3 xl:grid-cols-6 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
  >
    <template v-if="!summary">
      <div
        v-for="index in 6"
        :key="index"
        class="flex flex-col gap-2 ps-4 border-s border-n-weak"
      >
        <!-- design-audit-allow: hand-built-skeleton (label and figure of a report metric) -->
        <span class="w-20 h-3 rounded bg-n-alpha-2 animate-pulse" />
        <!-- design-audit-allow: hand-built-skeleton (label and figure of a report metric) -->
        <span class="h-6 rounded w-28 bg-n-alpha-2 animate-pulse" />
      </div>
    </template>
    <template v-else>
      <div
        v-for="metric in metrics"
        :key="metric.key"
        class="flex flex-col min-w-0 gap-1 ps-4 border-s border-n-weak transition-opacity duration-150"
        :class="{ 'opacity-60': isLoading }"
      >
        <span class="flex items-center gap-1 text-label-small text-n-slate-11">
          {{ t(`FLOW_KANBAN.REPORT.SUMMARY.${metric.key}`) }}
          <Icon
            v-tooltip.top="t(`FLOW_KANBAN.REPORT.SUMMARY.${metric.key}_HINT`)"
            icon="i-lucide-info"
            class="size-3.5 text-n-slate-10"
            tabindex="0"
            :aria-label="t(`FLOW_KANBAN.REPORT.SUMMARY.${metric.key}_HINT`)"
          />
        </span>
        <span class="text-2xl tabular-nums truncate text-n-slate-12">
          {{ metric.value }}
        </span>
        <span v-if="metric.detail" class="text-label-small text-n-slate-11">
          {{ metric.detail }}
        </span>
      </div>
    </template>
  </section>
</template>
