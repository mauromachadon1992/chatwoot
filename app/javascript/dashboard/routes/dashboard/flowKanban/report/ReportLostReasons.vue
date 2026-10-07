<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlowKanban } from '../useFlowKanban';

// Why deals were lost in the period, most common first, the ones lost without a reason counted
// as "No reason" rather than left out. The bar is the reason's share of the lost deals.
const props = defineProps({
  lostReasons: { type: Object, required: true },
  isLoading: { type: Boolean, default: false },
});

const { t } = useI18n();
const { money } = useFlowKanban();

const rows = computed(() =>
  props.lostReasons.rows.map(row => ({
    ...row,
    label: row.name || t('FLOW_KANBAN.REPORT.LOST_REASONS.NO_REASON'),
    share: props.lostReasons.total ? row.count / props.lostReasons.total : 0,
  }))
);
</script>

<template>
  <div class="overflow-x-auto">
    <table
      class="w-full min-w-[30rem] table-fixed transition-opacity duration-150"
      :class="{ 'opacity-60': isLoading }"
      :aria-busy="isLoading"
    >
      <colgroup>
        <col class="w-[30%]" />
        <col class="w-[40%]" />
        <col class="w-[30%]" />
      </colgroup>
      <thead>
        <tr class="border-b border-n-weak">
          <th
            scope="col"
            class="pb-2 pe-4 font-normal text-start text-label-small text-n-slate-11"
          >
            {{ t('FLOW_KANBAN.REPORT.LOST_REASONS.REASON') }}
          </th>
          <th
            scope="col"
            class="pb-2 pe-4 font-normal text-start text-label-small text-n-slate-11"
          >
            {{ t('FLOW_KANBAN.REPORT.LOST_REASONS.DEALS') }}
          </th>
          <th
            scope="col"
            class="pb-2 pe-4 font-normal text-end text-label-small text-n-slate-11"
          >
            {{ t('FLOW_KANBAN.REPORT.LOST_REASONS.VALUE') }}
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-n-weak">
        <tr v-for="row in rows" :key="row.reason_id ?? 'none'">
          <th
            scope="row"
            class="py-3 pe-4 font-normal text-start text-body-main truncate"
            :class="row.reason_id ? 'text-n-slate-12' : 'text-n-slate-11'"
          >
            {{ row.label }}
          </th>
          <td class="py-3 pe-4">
            <span
              class="flex items-center gap-3"
              :aria-label="
                t('FLOW_KANBAN.REPORT.LOST_REASONS.BAR_LABEL', {
                  reason: row.label,
                  count: row.count,
                  total: lostReasons.total,
                })
              "
            >
              <span
                class="relative flex-1 h-2 overflow-hidden rounded-full bg-n-alpha-2"
                aria-hidden="true"
              >
                <span
                  class="absolute inset-y-0 start-0 rounded-full bg-n-slate-9"
                  :style="{ width: `${row.share * 100}%` }"
                />
              </span>
              <span
                class="w-8 text-end text-label tabular-nums text-n-slate-12"
                aria-hidden="true"
              >
                {{ row.count }}
              </span>
            </span>
          </td>
          <td
            class="py-3 pe-4 text-end text-body-main tabular-nums text-n-slate-12"
          >
            {{ money(row.value_cents, { whole: true }) }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
