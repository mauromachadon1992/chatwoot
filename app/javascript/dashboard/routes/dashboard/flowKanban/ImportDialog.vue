<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SkeletonRows from './SkeletonRows.vue';
import StatePill from './StatePill.vue';
import {
  MAX_BYTES,
  MAX_ROWS,
  actionView,
  canRun,
  fileProblem,
  filenameFrom,
  isFinished,
  saveBlob,
  visibleCells,
  writableRows,
} from './csv';

// One import, in one dialog: choose the file, check how its columns were read and what would
// happen to each row (nothing is written yet), run it, and see the result. `kind` is
// "products" or "deals"; deals go into `boardId`.
const props = defineProps({
  kind: { type: String, required: true },
  boardId: { type: [Number, String], default: null },
});

const emit = defineEmits(['imported']);

const { t } = useI18n();

const POLL_MS = 1500;
const REQUIRED_MARK = '*';
const dialogRef = ref(null);
const fileInput = ref(null);

// choose | analyzing | review | running | done
const step = ref('choose');
const chooseError = ref('');
const payload = ref(null);
const analysis = ref(null);
const isRemapping = ref(false);
let pollTimer = null;

const sizeMb = Math.round(MAX_BYTES / (1024 * 1024));
const fieldLabel = field =>
  t(
    `FLOW_KANBAN.SETTINGS.IMPORT.FIELDS.${props.kind.toUpperCase()}.${field.toUpperCase()}`
  );
const headerOptions = computed(() =>
  (payload.value?.headers || []).map(header => ({
    value: header,
    label: header,
  }))
);
const runnable = computed(
  () => payload.value && analysis.value && canRun(payload.value, analysis.value)
);
const isRequired = field => analysis.value?.required.includes(field);
const actionLabel = action =>
  t(`FLOW_KANBAN.SETTINGS.IMPORT.ACTIONS.${actionView(action).key}`);

const stopPolling = () => {
  clearTimeout(pollTimer);
  pollTimer = null;
};

const reset = () => {
  stopPolling();
  step.value = 'choose';
  chooseError.value = '';
  payload.value = null;
  analysis.value = null;
};

const open = () => {
  reset();
  dialogRef.value?.open();
};

const fail = error =>
  useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));

const pickFile = () => fileInput.value?.click();

const onFile = async event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  const problem = fileProblem(file);
  if (problem) {
    chooseError.value = t(
      `FLOW_KANBAN.SETTINGS.IMPORT.FILE_PROBLEM.${problem.toUpperCase()}`,
      {
        max: sizeMb,
      }
    );
    return;
  }
  chooseError.value = '';
  step.value = 'analyzing';
  try {
    const { data } = await FlowKanbanAPI.createImport({
      file,
      kind: props.kind,
      boardId: props.boardId,
    });
    payload.value = data.payload;
    analysis.value = data.analysis;
    step.value = 'review';
  } catch (error) {
    step.value = 'choose';
    chooseError.value =
      error.response?.data?.error ||
      parseAPIErrorResponse(error) ||
      t('FLOW_KANBAN.ERRORS.GENERIC');
  }
};

// The administrator says which column is which field; the server reads the file again.
const remap = async (field, header) => {
  const mapping = { ...payload.value.mapping };
  if (header) mapping[field] = header;
  else delete mapping[field];
  isRemapping.value = true;
  try {
    const { data } = await FlowKanbanAPI.updateImport(
      payload.value.id,
      mapping
    );
    payload.value = data.payload;
    analysis.value = data.analysis;
  } catch (error) {
    fail(error);
  } finally {
    isRemapping.value = false;
  }
};

const poll = async () => {
  try {
    const { data } = await FlowKanbanAPI.getImport(payload.value.id);
    payload.value = data.payload;
    if (isFinished(data.payload.status)) {
      step.value = 'done';
      if (data.payload.status === 'done') emit('imported', data.payload);
      return;
    }
  } catch {
    // A missed poll is not a failed import: ask again.
  }
  pollTimer = setTimeout(poll, POLL_MS);
};

const run = async () => {
  if (!runnable.value) return;
  try {
    const { data } = await FlowKanbanAPI.runImport(payload.value.id);
    payload.value = data.payload;
    step.value = 'running';
    pollTimer = setTimeout(poll, POLL_MS);
  } catch (error) {
    fail(error);
  }
};

const downloadErrors = async () => {
  try {
    const response = await FlowKanbanAPI.downloadImportErrors(payload.value.id);
    saveBlob(
      response.data,
      filenameFrom(response.headers['content-disposition'], 'errors.csv')
    );
  } catch (error) {
    fail(error);
  }
};

const close = () => {
  stopPolling();
  dialogRef.value?.close();
};

onBeforeUnmount(stopPolling);
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    :title="t(`FLOW_KANBAN.SETTINGS.IMPORT.TITLE.${kind.toUpperCase()}`)"
    :show-confirm-button="step === 'review' || step === 'done'"
    :confirm-button-label="
      step === 'done'
        ? t('FLOW_KANBAN.SETTINGS.IMPORT.CLOSE')
        : t('FLOW_KANBAN.SETTINGS.IMPORT.RUN', {
            count: payload ? writableRows(payload) : 0,
          })
    "
    :disable-confirm-button="step === 'review' && !runnable"
    :show-cancel-button="step !== 'done'"
    :cancel-button-label="
      step === 'running'
        ? t('FLOW_KANBAN.SETTINGS.IMPORT.HIDE')
        : t('FLOW_KANBAN.SETTINGS.IMPORT.CANCEL')
    "
    overflow-y-auto
    @confirm="step === 'done' ? close() : run()"
    @close="stopPolling"
  >
    <!-- design-audit-allow: native-element (a file picker has no components-next version; it stays hidden and a Button opens it) -->
    <input
      ref="fileInput"
      type="file"
      accept=".csv,.txt,text/csv,text/plain"
      class="sr-only"
      tabindex="-1"
      @change="onFile"
    />

    <div v-if="step === 'choose'" class="flex flex-col gap-3">
      <p class="text-body-main text-n-slate-11">
        {{ t(`FLOW_KANBAN.SETTINGS.IMPORT.INTRO.${kind.toUpperCase()}`) }}
      </p>
      <ul
        class="flex flex-col gap-1 p-0 m-0 list-none text-label-small text-n-slate-11"
      >
        <li>
          {{
            t('FLOW_KANBAN.SETTINGS.IMPORT.LIMITS', {
              mb: sizeMb,
              rows: MAX_ROWS,
            })
          }}
        </li>
        <li>{{ t('FLOW_KANBAN.SETTINGS.IMPORT.NOTHING_YET') }}</li>
      </ul>
      <div class="flex flex-col items-start gap-2">
        <Button
          faded
          blue
          sm
          type="button"
          icon="i-lucide-upload"
          :label="t('FLOW_KANBAN.SETTINGS.IMPORT.CHOOSE')"
          @click="pickFile"
        />
        <p
          v-if="chooseError"
          role="alert"
          class="text-label-small text-n-ruby-11"
        >
          {{ chooseError }}
        </p>
      </div>
    </div>

    <div v-else-if="step === 'analyzing'" aria-live="polite">
      <p class="mb-3 text-body-main text-n-slate-11">
        {{ t('FLOW_KANBAN.SETTINGS.IMPORT.READING') }}
      </p>
      <SkeletonRows :rows="3" />
    </div>

    <div v-else-if="step === 'review' && payload" class="flex flex-col gap-5">
      <p class="text-body-main text-n-slate-12 break-all">
        {{ payload.filename }}
        <span class="text-n-slate-11">
          ·
          {{
            t(
              'FLOW_KANBAN.SETTINGS.IMPORT.ROWS',
              { count: payload.total_rows },
              payload.total_rows
            )
          }}
        </span>
      </p>

      <fieldset class="flex flex-col gap-3 p-0 m-0 border-0 min-w-0">
        <legend class="mb-1 text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.SETTINGS.IMPORT.COLUMNS') }}
        </legend>
        <p class="text-label-small text-n-slate-11">
          {{ t('FLOW_KANBAN.SETTINGS.IMPORT.COLUMNS_HINT') }}
        </p>
        <div
          v-for="field in analysis.fields"
          :key="field"
          class="grid items-center grid-cols-1 gap-1 sm:grid-cols-2 sm:gap-3"
        >
          <span class="text-body-main text-n-slate-12">
            {{ fieldLabel(field) }}
            <span
              v-if="isRequired(field)"
              class="text-n-ruby-11"
              aria-hidden="true"
            >
              {{ REQUIRED_MARK }}
            </span>
            <span v-if="isRequired(field)" class="sr-only">
              {{ t('FLOW_KANBAN.SETTINGS.IMPORT.REQUIRED') }}
            </span>
          </span>
          <ComboBox
            :model-value="payload.mapping[field] || ''"
            :options="headerOptions"
            :placeholder="t('FLOW_KANBAN.SETTINGS.IMPORT.NOT_IMPORTED')"
            :disabled="isRemapping"
            :has-error="analysis.missing.includes(field)"
            @update:model-value="remap(field, $event)"
          />
        </div>
        <p
          v-if="analysis.missing.length"
          role="alert"
          class="text-label-small text-n-ruby-11"
        >
          {{
            t('FLOW_KANBAN.SETTINGS.IMPORT.MISSING', {
              fields: analysis.missing.map(fieldLabel).join(', '),
            })
          }}
        </p>
      </fieldset>

      <template v-if="!analysis.missing.length">
        <div class="flex flex-wrap items-center gap-2" aria-live="polite">
          <StatePill
            tone="teal"
            icon="i-lucide-plus"
            :label="
              t('FLOW_KANBAN.SETTINGS.IMPORT.SUMMARY.CREATE', {
                count: payload.created,
              })
            "
          />
          <StatePill
            v-if="kind === 'products'"
            tone="blue"
            icon="i-lucide-pencil"
            :label="
              t('FLOW_KANBAN.SETTINGS.IMPORT.SUMMARY.UPDATE', {
                count: payload.updated,
              })
            "
          />
          <StatePill
            tone="slate"
            icon="i-lucide-minus"
            :label="
              t('FLOW_KANBAN.SETTINGS.IMPORT.SUMMARY.SKIP', {
                count: payload.skipped,
              })
            "
          />
          <StatePill
            v-if="payload.errors"
            tone="ruby"
            icon="i-lucide-x"
            :label="
              t('FLOW_KANBAN.SETTINGS.IMPORT.SUMMARY.ERROR', {
                count: payload.errors,
              })
            "
          />
        </div>

        <div class="flex flex-col gap-2">
          <h4 class="text-label text-n-slate-12">
            {{ t('FLOW_KANBAN.SETTINGS.IMPORT.PREVIEW') }}
          </h4>
          <div
            class="overflow-x-auto rounded-lg outline outline-1 outline-n-container"
          >
            <table class="w-full text-start text-label-small">
              <caption class="sr-only">
                {{
                  t('FLOW_KANBAN.SETTINGS.IMPORT.PREVIEW')
                }}
              </caption>
              <thead class="bg-n-alpha-1 text-n-slate-11">
                <tr>
                  <th scope="col" class="px-2 py-1.5 text-start font-medium">
                    {{ t('FLOW_KANBAN.SETTINGS.IMPORT.LINE') }}
                  </th>
                  <th
                    v-for="header in visibleCells(payload.headers)"
                    :key="header"
                    scope="col"
                    class="px-2 py-1.5 text-start font-medium"
                  >
                    {{ header }}
                  </th>
                  <th scope="col" class="px-2 py-1.5 text-start font-medium">
                    {{ t('FLOW_KANBAN.SETTINGS.IMPORT.RESULT') }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr v-for="row in analysis.preview" :key="row.line">
                  <td class="px-2 py-1.5 tabular-nums text-n-slate-11">
                    {{ row.line }}
                  </td>
                  <td
                    v-for="(cell, index) in visibleCells(row.cells)"
                    :key="index"
                    class="px-2 py-1.5 text-n-slate-12 max-w-48 truncate"
                  >
                    {{ cell }}
                  </td>
                  <td class="px-2 py-1.5">
                    <StatePill
                      :tone="actionView(row.action).tone"
                      :icon="actionView(row.action).icon"
                      :label="actionLabel(row.action)"
                    />
                    <span
                      v-if="row.messages.length"
                      class="block mt-1 text-n-ruby-11 whitespace-normal"
                    >
                      {{ row.messages.join('; ') }}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div v-if="analysis.errors.length" class="flex flex-col gap-2">
          <h4 class="text-label text-n-slate-12">
            {{
              t(
                'FLOW_KANBAN.SETTINGS.IMPORT.PROBLEMS',
                { count: payload.errors },
                payload.errors
              )
            }}
          </h4>
          <p class="text-label-small text-n-slate-11">
            {{ t('FLOW_KANBAN.SETTINGS.IMPORT.PROBLEMS_HINT') }}
          </p>
          <ul
            class="flex flex-col gap-1 p-0 m-0 list-none max-h-48 overflow-y-auto"
          >
            <li
              v-for="error in analysis.errors"
              :key="error.line"
              class="text-label-small text-n-slate-12"
            >
              <span class="tabular-nums text-n-slate-11">
                {{
                  t('FLOW_KANBAN.SETTINGS.IMPORT.AT_LINE', { line: error.line })
                }}
              </span>
              {{ error.messages.join('; ') }}
            </li>
          </ul>
          <p
            v-if="payload.errors > analysis.errors.length"
            class="text-label-small text-n-slate-11"
          >
            {{
              t('FLOW_KANBAN.SETTINGS.IMPORT.MORE_PROBLEMS', {
                count: payload.errors - analysis.errors.length,
              })
            }}
          </p>
        </div>
      </template>
    </div>

    <div
      v-else-if="step === 'running' && payload"
      class="flex flex-col gap-3"
      aria-live="polite"
    >
      <p class="text-body-main text-n-slate-12">
        {{
          t('FLOW_KANBAN.SETTINGS.IMPORT.RUNNING', {
            done: payload.processed_rows,
            total: payload.total_rows,
          })
        }}
      </p>
      <div
        role="progressbar"
        aria-valuemin="0"
        aria-valuemax="100"
        :aria-valuenow="payload.progress"
        :aria-label="t('FLOW_KANBAN.SETTINGS.IMPORT.PROGRESS')"
        class="h-2 rounded-full bg-n-alpha-2 overflow-hidden"
      >
        <div
          class="h-full rounded-full bg-n-brand transition-all duration-300"
          :style="{ width: `${payload.progress}%` }"
        />
      </div>
      <p class="text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.SETTINGS.IMPORT.CAN_LEAVE') }}
      </p>
    </div>

    <div
      v-else-if="step === 'done' && payload"
      class="flex flex-col gap-3"
      aria-live="polite"
    >
      <StatePill
        :tone="payload.status === 'done' ? 'teal' : 'ruby'"
        :icon="payload.status === 'done' ? 'i-lucide-check' : 'i-lucide-x'"
        :label="
          t(
            `FLOW_KANBAN.SETTINGS.IMPORT.FINISHED.${payload.status.toUpperCase()}`
          )
        "
      />
      <p
        v-if="payload.status === 'done'"
        class="text-body-main text-n-slate-12"
      >
        {{
          t('FLOW_KANBAN.SETTINGS.IMPORT.RESULT_SUMMARY', {
            created: payload.created,
            updated: payload.updated,
            skipped: payload.skipped,
            errors: payload.errors,
          })
        }}
      </p>
      <p v-else class="text-body-main text-n-slate-11">
        {{ t('FLOW_KANBAN.SETTINGS.IMPORT.FAILED_BODY') }}
      </p>
      <Button
        v-if="payload.errors"
        faded
        slate
        sm
        type="button"
        class="self-start"
        icon="i-lucide-download"
        :label="
          t('FLOW_KANBAN.SETTINGS.IMPORT.DOWNLOAD_ERRORS', {
            count: payload.errors,
          })
        "
        @click="downloadErrors"
      />
    </div>
  </Dialog>
</template>
