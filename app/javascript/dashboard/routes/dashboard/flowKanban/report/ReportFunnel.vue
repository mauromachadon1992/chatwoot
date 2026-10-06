<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useFlowKanban } from '../useFlowKanban';
import { formatPercent } from '../money';
import { useDuration } from './useDuration';

// The funnel as a table: one row per stage in board order, the bar showing how many of the
// period's deals got that far. Lost stages sit outside the funnel and keep only what they
// hold now and how long deals stayed.
const props = defineProps({
  stages: { type: Array, required: true },
  created: { type: Number, required: true },
  isLoading: { type: Boolean, default: false },
});

const { t, locale } = useI18n();
const { money } = useFlowKanban();
const { duration } = useDuration();

const NONE = '—';
const STAGE_TYPE_ICONS = {
  won: { icon: 'i-lucide-circle-check', tone: 'text-n-teal-11' },
  lost: { icon: 'i-lucide-circle-x', tone: 'text-n-ruby-11' },
};

const widest = computed(() =>
  Math.max(props.created, ...props.stages.map(stage => stage.reached || 0), 1)
);

const rows = computed(() =>
  props.stages.map(stage => ({
    ...stage,
    inFunnel: stage.stage_type !== 'lost',
    width: `${((stage.reached || 0) / widest.value) * 100}%`,
    conversion:
      stage.conversion_rate === null
        ? NONE
        : formatPercent(stage.conversion_rate, locale.value),
    time:
      stage.average_seconds === null ? NONE : duration(stage.average_seconds),
  }))
);

const COLUMNS = ['STAGE', 'REACHED', 'CONVERSION', 'NOW', 'TIME'];
const HINTS = { REACHED: true, CONVERSION: true, NOW: true, TIME: true };
</script>

<template>
  <div class="overflow-x-auto">
    <table
      class="w-full min-w-[44rem] table-fixed transition-opacity duration-150"
      :class="{ 'opacity-60': isLoading }"
      :aria-busy="isLoading"
    >
      <colgroup>
        <col class="w-[22%]" />
        <col class="w-[34%]" />
        <col class="w-[12%]" />
        <col class="w-[18%]" />
        <col class="w-[14%]" />
      </colgroup>
      <thead>
        <tr class="border-b border-n-weak">
          <th
            v-for="column in COLUMNS"
            :key="column"
            scope="col"
            class="pb-2 pe-4 text-label-small text-n-slate-11 font-normal"
            :class="
              column === 'STAGE' || column === 'REACHED'
                ? 'text-start'
                : 'text-end'
            "
          >
            <span class="inline-flex items-center gap-1 whitespace-nowrap">
              {{ t(`FLOW_KANBAN.REPORT.FUNNEL.${column}`) }}
              <Icon
                v-if="HINTS[column]"
                v-tooltip.top="t(`FLOW_KANBAN.REPORT.FUNNEL.${column}_HINT`)"
                icon="i-lucide-info"
                class="size-3.5 text-n-slate-10"
                tabindex="0"
                :aria-label="t(`FLOW_KANBAN.REPORT.FUNNEL.${column}_HINT`)"
              />
            </span>
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-n-weak">
        <tr v-for="row in rows" :key="row.id">
          <th scope="row" class="py-3 pe-4 text-start font-normal">
            <span class="flex items-center min-w-0 gap-2">
              <span
                class="flex-shrink-0 rounded-full size-2.5"
                :style="{ backgroundColor: row.color }"
              />
              <span class="text-body-main truncate text-n-slate-12">
                {{ row.name }}
              </span>
              <Icon
                v-if="STAGE_TYPE_ICONS[row.stage_type]"
                :icon="STAGE_TYPE_ICONS[row.stage_type].icon"
                class="flex-shrink-0 size-4"
                :class="STAGE_TYPE_ICONS[row.stage_type].tone"
                :aria-label="
                  t(
                    `FLOW_KANBAN.BOARD_FORM.STAGE_TYPES.${row.stage_type.toUpperCase()}`
                  )
                "
              />
            </span>
          </th>
          <td class="py-3 pe-4">
            <span
              v-if="row.inFunnel"
              class="flex items-center gap-3"
              :aria-label="
                t('FLOW_KANBAN.REPORT.FUNNEL.BAR_LABEL', {
                  stage: row.name,
                  reached: row.reached ?? 0,
                  total: created,
                })
              "
            >
              <span
                class="relative flex-1 h-2 overflow-hidden rounded-full bg-n-alpha-2"
                aria-hidden="true"
              >
                <span
                  class="absolute inset-y-0 start-0 rounded-full transition-[width] duration-300 ease-out"
                  :style="{ width: row.width, backgroundColor: row.color }"
                />
              </span>
              <span
                class="w-10 text-end text-label tabular-nums text-n-slate-12"
                aria-hidden="true"
              >
                {{ row.reached ?? 0 }}
              </span>
            </span>
            <span v-else class="text-label-small text-n-slate-10">
              {{ t('FLOW_KANBAN.REPORT.FUNNEL.OUT_OF_FUNNEL') }}
            </span>
          </td>
          <td
            class="py-3 pe-4 text-end text-body-main tabular-nums text-n-slate-12"
          >
            {{ row.conversion }}
          </td>
          <td class="py-3 pe-4 text-end">
            <span class="flex flex-col items-end">
              <span class="text-body-main tabular-nums text-n-slate-12">
                {{ money(row.value_cents, { whole: true }) }}
              </span>
              <span class="text-label-small text-n-slate-10 tabular-nums">
                {{
                  t(
                    'FLOW_KANBAN.REPORT.SUMMARY.DEALS',
                    { count: row.count },
                    row.count
                  )
                }}
              </span>
            </span>
          </td>
          <td
            class="py-3 pe-4 text-end text-body-main tabular-nums text-n-slate-11"
          >
            {{ row.time }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
