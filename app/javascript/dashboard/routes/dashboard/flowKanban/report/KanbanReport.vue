<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ReportSummary from './ReportSummary.vue';
import ReportFunnel from './ReportFunnel.vue';
import { useFlowKanbanReport } from './useFlowKanbanReport';

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

          <div v-if="!report" class="flex flex-col gap-3" aria-busy="true">
            <div
              v-for="row in SKELETON_ROWS"
              :key="row"
              class="h-10 rounded-lg bg-n-alpha-2 animate-pulse"
            />
          </div>

          <div
            v-else-if="!report.summary.created"
            class="flex flex-col items-center gap-4 px-6 py-12 text-center rounded-xl outline outline-1 outline-dashed outline-n-container"
          >
            <span
              class="flex items-center justify-center rounded-xl size-12 bg-n-alpha-2 text-n-slate-11"
            >
              <Icon icon="i-lucide-filter" class="size-6" />
            </span>
            <div class="flex flex-col gap-1 max-w-md">
              <h3 class="text-heading-2 text-n-slate-12">
                {{ t('FLOW_KANBAN.REPORT.EMPTY_TITLE') }}
              </h3>
              <p class="text-body-main text-n-slate-11">
                {{ t('FLOW_KANBAN.REPORT.EMPTY_BODY') }}
              </p>
            </div>
          </div>

          <ReportFunnel
            v-else
            :stages="report.stages"
            :created="report.summary.created"
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
