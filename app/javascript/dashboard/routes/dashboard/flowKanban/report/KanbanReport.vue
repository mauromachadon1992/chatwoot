<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ReportSummary from './ReportSummary.vue';
import ReportFunnel from './ReportFunnel.vue';
import ReportForecast from './ReportForecast.vue';
import ReportLostReasons from './ReportLostReasons.vue';
import { useFlowKanbanReport } from './useFlowKanbanReport';
import SkeletonRows from '../SkeletonRows.vue';
import EmptyState from '../EmptyState.vue';

// The board's report view. The period and assignee filters live in the Kanban header.
const props = defineProps({
  boardId: { type: Number, required: true },
  period: { type: String, required: true },
  assigneeId: { type: [String, Number], default: '' },
});

const { t } = useI18n();
const { report, isLoading, hasError, load } = useFlowKanbanReport({
  boardId: () => props.boardId,
  period: () => props.period,
  assigneeId: () => props.assigneeId,
});

const SKELETON_ROWS = 4;
</script>

<template>
  <div class="flex-1 min-h-0 overflow-y-auto">
    <div class="flex flex-col w-full max-w-6xl gap-8 px-6 py-6 mx-auto">
      <div
        v-if="hasError && !report"
        class="flex flex-col items-center gap-3 py-16 text-center"
        role="alert"
      >
        <p class="text-body-main text-n-slate-11">
          {{ t('FLOW_KANBAN.REPORT.ERROR') }}
        </p>
        <Button
          faded
          slate
          sm
          icon="i-lucide-refresh-cw"
          :label="t('FLOW_KANBAN.REPORT.RETRY')"
          @click="load"
        />
      </div>

      <template v-else>
        <ReportSummary :summary="report?.summary" :is-loading="isLoading" />

        <section class="flex flex-col gap-4">
          <div class="flex flex-col gap-1">
            <h2 class="text-heading-2 text-n-slate-12">
              {{ t('FLOW_KANBAN.REPORT.FUNNEL.TITLE') }}
            </h2>
            <p v-if="report" class="text-body-main text-n-slate-11">
              {{
                t('FLOW_KANBAN.REPORT.FUNNEL.DESCRIPTION', {
                  count: report.summary.created,
                })
              }}
            </p>
          </div>

          <div v-if="!report" aria-busy="true">
            <SkeletonRows :rows="SKELETON_ROWS" />
          </div>

          <EmptyState
            v-else-if="!report.summary.created"
            framed
            icon="i-lucide-filter"
            :title="t('FLOW_KANBAN.REPORT.EMPTY_TITLE')"
            :description="t('FLOW_KANBAN.REPORT.EMPTY_BODY')"
          />

          <ReportFunnel
            v-else
            :stages="report.stages"
            :created="report.summary.created"
            :is-loading="isLoading"
          />
        </section>

        <section
          class="flex flex-col gap-4"
          aria-labelledby="flow-forecast-title"
        >
          <div class="flex flex-col gap-1">
            <h2 id="flow-forecast-title" class="text-heading-2 text-n-slate-12">
              {{ t('FLOW_KANBAN.REPORT.FORECAST.TITLE') }}
            </h2>
            <p class="text-body-main text-n-slate-11">
              {{ t('FLOW_KANBAN.REPORT.FORECAST.DESCRIPTION') }}
            </p>
          </div>

          <SkeletonRows v-if="!report" :rows="SKELETON_ROWS" />

          <EmptyState
            v-else-if="!report.forecast.open_count"
            framed
            icon="i-lucide-trending-up"
            :title="t('FLOW_KANBAN.REPORT.FORECAST.EMPTY_TITLE')"
            :description="t('FLOW_KANBAN.REPORT.FORECAST.EMPTY_BODY')"
          />

          <ReportForecast
            v-else
            :forecast="report.forecast"
            :is-loading="isLoading"
          />
        </section>

        <section class="flex flex-col gap-4" aria-labelledby="flow-lost-title">
          <div class="flex flex-col gap-1">
            <h2 id="flow-lost-title" class="text-heading-2 text-n-slate-12">
              {{ t('FLOW_KANBAN.REPORT.LOST_REASONS.TITLE') }}
            </h2>
            <p class="text-body-main text-n-slate-11">
              {{ t('FLOW_KANBAN.REPORT.LOST_REASONS.DESCRIPTION') }}
            </p>
          </div>

          <SkeletonRows v-if="!report" :rows="2" />

          <EmptyState
            v-else-if="!report.lost_reasons.total"
            framed
            icon="i-lucide-circle-x"
            :title="t('FLOW_KANBAN.REPORT.LOST_REASONS.EMPTY_TITLE')"
            :description="t('FLOW_KANBAN.REPORT.LOST_REASONS.EMPTY_BODY')"
          />

          <ReportLostReasons
            v-else
            :lost-reasons="report.lost_reasons"
            :is-loading="isLoading"
          />
        </section>

        <p class="flex items-start gap-2 text-label-small text-n-slate-10">
          <Icon icon="i-lucide-history" class="flex-shrink-0 mt-0.5 size-3.5" />
          {{ t('FLOW_KANBAN.REPORT.HISTORY_NOTE') }}
        </p>
      </template>
    </div>
  </div>
</template>
