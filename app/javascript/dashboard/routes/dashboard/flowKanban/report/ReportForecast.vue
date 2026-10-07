<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import StatePill from '../StatePill.vue';
import { useFlowKanban } from '../useFlowKanban';
import { forecastRowLabel, forecastCoverage } from './forecast';

// What the open deals should bring in, by the month they are expected to close, beside the
// same deals weighted by the chance of their stage. A deal without a date is a row of its own,
// never dropped: how many open deals carry a date is part of the answer.
const props = defineProps({
  forecast: { type: Object, required: true },
  isLoading: { type: Boolean, default: false },
});

const { t, locale } = useI18n();
const { money } = useFlowKanban();

const rows = computed(() =>
  props.forecast.rows.map(row => ({
    ...row,
    label: forecastRowLabel(row.key, locale.value, key =>
      t(`FLOW_KANBAN.REPORT.FORECAST.ROWS.${key.toUpperCase()}`)
    ),
    muted: row.count === 0,
    needsAttention: row.key === 'overdue' && row.count > 0,
  }))
);
const coverage = computed(() => forecastCoverage(props.forecast));
</script>

<template>
  <div class="flex flex-col gap-3">
    <StatePill
      v-if="coverage.partial"
      tone="amber"
      icon="i-lucide-calendar-x"
      :label="
        t('FLOW_KANBAN.REPORT.FORECAST.COVERAGE', {
          withDate: coverage.withDate,
          total: coverage.total,
        })
      "
    />

    <div class="overflow-x-auto">
      <table
        class="w-full min-w-[34rem] table-fixed transition-opacity duration-150"
        :class="{ 'opacity-60': isLoading }"
        :aria-busy="isLoading"
      >
        <colgroup>
          <col class="w-[34%]" />
          <col class="w-[14%]" />
          <col class="w-[26%]" />
          <col class="w-[26%]" />
        </colgroup>
        <thead>
          <tr class="border-b border-n-weak">
            <th
              scope="col"
              class="pb-2 pe-4 font-normal text-start text-label-small text-n-slate-11"
            >
              {{ t('FLOW_KANBAN.REPORT.FORECAST.MONTH') }}
            </th>
            <th
              v-for="column in ['DEALS', 'VALUE', 'WEIGHTED']"
              :key="column"
              scope="col"
              class="pb-2 pe-4 font-normal text-end text-label-small text-n-slate-11"
            >
              <span class="inline-flex items-center gap-1 whitespace-nowrap">
                {{ t(`FLOW_KANBAN.REPORT.FORECAST.${column}`) }}
                <Icon
                  v-if="column === 'WEIGHTED'"
                  v-tooltip.top="t('FLOW_KANBAN.REPORT.FORECAST.WEIGHTED_HINT')"
                  icon="i-lucide-info"
                  class="size-3.5 text-n-slate-10"
                  tabindex="0"
                  :aria-label="t('FLOW_KANBAN.REPORT.FORECAST.WEIGHTED_HINT')"
                />
              </span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr v-for="row in rows" :key="row.key">
            <th
              scope="row"
              class="py-3 pe-4 font-normal text-start text-body-main"
              :class="row.muted ? 'text-n-slate-10' : 'text-n-slate-12'"
            >
              <span class="inline-flex items-center gap-2">
                {{ row.label }}
                <StatePill
                  v-if="row.needsAttention"
                  tone="ruby"
                  icon="i-lucide-alarm-clock"
                  :label="t('FLOW_KANBAN.REPORT.FORECAST.PAST_DATE')"
                />
              </span>
            </th>
            <td
              class="py-3 pe-4 text-end text-body-main tabular-nums"
              :class="row.muted ? 'text-n-slate-10' : 'text-n-slate-12'"
            >
              {{ row.count }}
            </td>
            <td
              class="py-3 pe-4 text-end text-body-main tabular-nums"
              :class="row.muted ? 'text-n-slate-10' : 'text-n-slate-12'"
            >
              {{ money(row.value_cents, { whole: true }) }}
            </td>
            <td
              class="py-3 pe-4 text-end text-body-main tabular-nums"
              :class="row.muted ? 'text-n-slate-10' : 'text-n-slate-12'"
            >
              {{ money(row.weighted_cents, { whole: true }) }}
            </td>
          </tr>
        </tbody>
        <tfoot>
          <tr class="border-t border-n-strong">
            <th
              scope="row"
              class="py-3 pe-4 font-normal text-start text-label text-n-slate-12"
            >
              {{ t('FLOW_KANBAN.REPORT.FORECAST.TOTAL') }}
            </th>
            <td
              class="py-3 pe-4 text-end text-label tabular-nums text-n-slate-12"
            >
              {{ forecast.totals.count }}
            </td>
            <td
              class="py-3 pe-4 text-end text-label tabular-nums text-n-slate-12"
            >
              {{ money(forecast.totals.value_cents, { whole: true }) }}
            </td>
            <td
              class="py-3 pe-4 text-end text-label tabular-nums text-n-slate-12"
            >
              {{ money(forecast.totals.weighted_cents, { whole: true }) }}
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
  </div>
</template>
