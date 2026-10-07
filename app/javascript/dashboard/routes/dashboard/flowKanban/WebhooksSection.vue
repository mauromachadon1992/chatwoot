<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import EmptyState from './EmptyState.vue';
import SkeletonRows from './SkeletonRows.vue';
import StatePill from './StatePill.vue';
import {
  EVENTS,
  URL_MAX_LENGTH,
  canSave,
  errorKey,
  statusView,
  summarizeEvents,
  urlProblem,
} from './webhooks';

// Settings → Kanban → Webhooks: addresses told about deals. Administrators only. A webhook
// hears about every board of the account, so the section says so.
const { t, locale } = useI18n();

const webhooks = ref([]);
const maxWebhooks = ref(10);
const isLoading = ref(true);
const hasError = ref(false);

const editing = ref(null); // { id?, url, events, active }
const triedToSave = ref(false);
const isSaving = ref(false);
const formDialogRef = ref(null);

const secret = ref('');
const secretDialogRef = ref(null);
const copied = ref(false);

const toDelete = ref(null);
const isDeleting = ref(false);
const deleteDialogRef = ref(null);

const testingId = ref(null);

const logFor = ref(null);
const deliveries = ref([]);
const isLoadingLog = ref(true);
const logDialogRef = ref(null);

const eventName = event =>
  t(
    `FLOW_KANBAN.SETTINGS.WEBHOOKS.EVENTS.${event.replace('.', '_').toUpperCase()}`
  );
const canAdd = computed(() => webhooks.value.length < maxWebhooks.value);
const formProblem = computed(() => urlProblem(editing.value?.url || ''));
const showUrlError = computed(() => triedToSave.value && formProblem.value);
const showEventsError = computed(
  () => triedToSave.value && !editing.value?.events.length
);

const fail = error =>
  useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));

const when = seconds =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(seconds * 1000));

const statusLabel = delivery =>
  t(`FLOW_KANBAN.SETTINGS.WEBHOOKS.STATUS.${statusView(delivery).key}`);

// What went wrong, in words: the server's own reasons are translated, an HTTP answer or a
// network error is shown as it came.
const errorText = delivery => {
  const key = errorKey(delivery.error);
  if (key) return t(`FLOW_KANBAN.SETTINGS.WEBHOOKS.ERRORS.${key}`);
  return delivery.error || '';
};

// "7 Oct, 14:13 · 200 · 120 ms · 1 attempt": the parts that exist, joined.
const logDetail = delivery =>
  [
    when(delivery.created_at),
    delivery.http_status,
    delivery.duration_ms ? `${delivery.duration_ms} ms` : null,
    t(
      'FLOW_KANBAN.SETTINGS.WEBHOOKS.LOG.ATTEMPTS',
      { count: delivery.attempts },
      delivery.attempts
    ),
  ]
    .filter(Boolean)
    .join(' · ');

const load = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await FlowKanbanAPI.getWebhooks();
    webhooks.value = data.payload;
    maxWebhooks.value = data.meta.max;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const openForm = hook => {
  triedToSave.value = false;
  editing.value = hook
    ? { id: hook.id, url: hook.url, events: [...hook.events] }
    : { url: '', events: [...EVENTS] };
  formDialogRef.value?.open();
};

const toggleEvent = (event, on) => {
  const list = editing.value.events.filter(item => item !== event);
  editing.value.events = on
    ? EVENTS.filter(e => [...list, event].includes(e))
    : list;
};

const save = async () => {
  triedToSave.value = true;
  if (isSaving.value || !canSave(editing.value)) return;
  isSaving.value = true;
  const { id, url, events } = editing.value;
  try {
    if (id) {
      const { data } = await FlowKanbanAPI.updateWebhook(id, {
        url: url.trim(),
        events,
      });
      webhooks.value = webhooks.value.map(hook =>
        hook.id === id ? data.payload : hook
      );
      formDialogRef.value?.close();
    } else {
      const { data } = await FlowKanbanAPI.createWebhook({
        url: url.trim(),
        events,
      });
      webhooks.value = [...webhooks.value, data.payload];
      formDialogRef.value?.close();
      secret.value = data.secret;
      copied.value = false;
      secretDialogRef.value?.open();
    }
  } catch (error) {
    fail(error);
  } finally {
    isSaving.value = false;
  }
};

const toggleActive = async (hook, active) => {
  try {
    const { data } = await FlowKanbanAPI.updateWebhook(hook.id, { active });
    webhooks.value = webhooks.value.map(item =>
      item.id === hook.id ? data.payload : item
    );
  } catch (error) {
    fail(error);
  }
};

const copySecret = async () => {
  try {
    await navigator.clipboard.writeText(secret.value);
    copied.value = true;
  } catch {
    useAlert(t('FLOW_KANBAN.SETTINGS.WEBHOOKS.SECRET.COPY_FAILED'));
  }
};

const closeSecret = () => {
  secret.value = '';
  secretDialogRef.value?.close();
};

const sendTest = async hook => {
  if (testingId.value) return;
  testingId.value = hook.id;
  try {
    const { data } = await FlowKanbanAPI.testWebhook(hook.id);
    webhooks.value = webhooks.value.map(item =>
      item.id === hook.id ? { ...item, last_delivery: data.payload } : item
    );
    useAlert(
      data.payload.status === 'success'
        ? t('FLOW_KANBAN.SETTINGS.WEBHOOKS.TEST.OK', {
            status: data.payload.http_status,
            ms: data.payload.duration_ms,
          })
        : t('FLOW_KANBAN.SETTINGS.WEBHOOKS.TEST.FAILED', {
            reason: errorText(data.payload),
          })
    );
  } catch (error) {
    fail(error);
  } finally {
    testingId.value = null;
  }
};

const openLog = async hook => {
  logFor.value = hook;
  deliveries.value = [];
  isLoadingLog.value = true;
  logDialogRef.value?.open();
  try {
    const { data } = await FlowKanbanAPI.getWebhookDeliveries(hook.id);
    deliveries.value = data.payload;
  } catch (error) {
    fail(error);
  } finally {
    isLoadingLog.value = false;
  }
};

const askDelete = hook => {
  toDelete.value = hook;
  deleteDialogRef.value?.open();
};

const confirmDelete = async () => {
  isDeleting.value = true;
  try {
    await FlowKanbanAPI.deleteWebhook(toDelete.value.id);
    webhooks.value = webhooks.value.filter(h => h.id !== toDelete.value.id);
    deleteDialogRef.value?.close();
  } catch (error) {
    fail(error);
  } finally {
    isDeleting.value = false;
  }
};

onMounted(load);
</script>

<template>
  <section class="flex flex-col gap-4" aria-labelledby="flow-webhooks-title">
    <div class="flex items-start justify-between gap-3">
      <div class="flex flex-col gap-1">
        <h2 id="flow-webhooks-title" class="text-heading-2 text-n-slate-12">
          {{ t('FLOW_KANBAN.SETTINGS.WEBHOOKS.TITLE') }}
        </h2>
        <p class="text-body-main text-n-slate-11">
          {{ t('FLOW_KANBAN.SETTINGS.WEBHOOKS.DESCRIPTION') }}
        </p>
      </div>
      <Button
        v-if="webhooks.length && canAdd"
        faded
        blue
        sm
        type="button"
        class="flex-shrink-0"
        icon="i-lucide-plus"
        :label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.ADD')"
        @click="openForm()"
      />
    </div>

    <SkeletonRows v-if="isLoading" :rows="2" />

    <EmptyState
      v-else-if="hasError"
      framed
      size="compact"
      icon="i-lucide-cloud-off"
      :title="t('FLOW_KANBAN.SETTINGS.LOAD_FAILED')"
    >
      <Button
        faded
        slate
        sm
        icon="i-lucide-rotate-cw"
        :label="t('FLOW_KANBAN.MY_TASKS.RETRY')"
        @click="load"
      />
    </EmptyState>

    <EmptyState
      v-else-if="!webhooks.length"
      framed
      size="compact"
      icon="i-lucide-webhook"
      :title="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.EMPTY_TITLE')"
      :description="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.EMPTY_BODY')"
    >
      <Button
        faded
        blue
        sm
        type="button"
        icon="i-lucide-plus"
        :label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.ADD')"
        @click="openForm()"
      />
    </EmptyState>

    <ul
      v-else
      class="flex flex-col p-0 m-0 list-none rounded-lg outline outline-1 outline-n-container divide-y divide-n-weak bg-n-solid-1"
    >
      <li
        v-for="hook in webhooks"
        :key="hook.id"
        class="flex flex-col gap-2 px-3 py-3"
      >
        <div class="flex items-start gap-3">
          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <span
              class="text-body-main break-all"
              :class="hook.active ? 'text-n-slate-12' : 'text-n-slate-11'"
            >
              {{ hook.url }}
            </span>
            <span class="text-label-small text-n-slate-11">
              {{ summarizeEvents(hook.events, eventName).text }}
              <template v-if="summarizeEvents(hook.events, eventName).rest">
                {{
                  t('FLOW_KANBAN.SETTINGS.WEBHOOKS.MORE_EVENTS', {
                    count: summarizeEvents(hook.events, eventName).rest,
                  })
                }}
              </template>
            </span>
          </div>
          <Switch
            :model-value="hook.active"
            :aria-label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.ACTIVE')"
            @update:model-value="toggleActive(hook, $event)"
          />
        </div>

        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex flex-wrap items-center gap-2">
            <StatePill
              :tone="statusView(hook.last_delivery).tone"
              :icon="statusView(hook.last_delivery).icon"
              :label="statusLabel(hook.last_delivery)"
            />
            <span
              v-if="hook.last_delivery"
              class="text-label-small tabular-nums text-n-slate-11"
            >
              {{ when(hook.last_delivery.created_at) }}
              <template v-if="hook.last_delivery.http_status">
                · {{ hook.last_delivery.http_status }}
              </template>
            </span>
          </div>
          <div class="flex items-center gap-1">
            <Button
              ghost
              slate
              xs
              type="button"
              icon="i-lucide-send"
              :label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.TEST.BUTTON')"
              :is-loading="testingId === hook.id"
              :disabled="!!testingId"
              @click="sendTest(hook)"
            />
            <Button
              v-tooltip.top="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.LOG.OPEN')"
              ghost
              slate
              xs
              type="button"
              icon="i-lucide-list"
              :aria-label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.LOG.OPEN')"
              @click="openLog(hook)"
            />
            <Button
              v-tooltip.top="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.EDIT')"
              ghost
              slate
              xs
              type="button"
              icon="i-lucide-pencil"
              :aria-label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.EDIT')"
              @click="openForm(hook)"
            />
            <Button
              v-tooltip.top="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.DELETE')"
              ghost
              ruby
              xs
              type="button"
              icon="i-lucide-trash-2"
              :aria-label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.DELETE')"
              @click="askDelete(hook)"
            />
          </div>
        </div>
      </li>
    </ul>

    <p v-if="!isLoading && !canAdd" class="text-label-small text-n-slate-11">
      {{ t('FLOW_KANBAN.SETTINGS.WEBHOOKS.LIMIT', { max: maxWebhooks }) }}
    </p>
  </section>

  <Dialog
    ref="formDialogRef"
    :title="
      editing?.id
        ? t('FLOW_KANBAN.SETTINGS.WEBHOOKS.EDIT')
        : t('FLOW_KANBAN.SETTINGS.WEBHOOKS.ADD')
    "
    :confirm-button-label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.SAVE')"
    :cancel-button-label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.CANCEL')"
    :is-loading="isSaving"
    overflow-y-auto
    @confirm="save"
  >
    <div v-if="editing" class="flex flex-col gap-4">
      <Input
        v-model="editing.url"
        type="url"
        inputmode="url"
        autocomplete="off"
        :maxlength="URL_MAX_LENGTH"
        :label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.URL')"
        placeholder="https://"
        :message="
          showUrlError
            ? t(
                `FLOW_KANBAN.SETTINGS.WEBHOOKS.PROBLEMS.URL_${formProblem.toUpperCase()}`
              )
            : t('FLOW_KANBAN.SETTINGS.WEBHOOKS.URL_HINT')
        "
        :message-type="showUrlError ? 'error' : 'info'"
      />

      <fieldset class="flex flex-col gap-2 p-0 m-0 border-0 min-w-0">
        <legend class="mb-2 text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.SETTINGS.WEBHOOKS.EVENTS_LABEL') }}
        </legend>
        <label
          v-for="event in EVENTS"
          :key="event"
          class="flex items-center gap-3 text-body-main text-n-slate-12 cursor-pointer"
        >
          <Checkbox
            :model-value="editing.events.includes(event)"
            @update:model-value="toggleEvent(event, $event)"
          />
          {{ eventName(event) }}
        </label>
        <p
          v-if="showEventsError"
          role="alert"
          class="text-label-small text-n-ruby-11"
        >
          {{ t('FLOW_KANBAN.SETTINGS.WEBHOOKS.PROBLEMS.EVENTS') }}
        </p>
      </fieldset>
    </div>
  </Dialog>

  <Dialog
    ref="secretDialogRef"
    :title="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.SECRET.TITLE')"
    :description="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.SECRET.DESCRIPTION')"
    :confirm-button-label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.SECRET.DONE')"
    :show-cancel-button="false"
    @confirm="closeSecret"
    @close="secret = ''"
  >
    <div class="flex flex-col gap-3">
      <div class="flex items-center gap-2">
        <code
          class="flex-1 min-w-0 px-3 py-2 text-body-main break-all rounded-lg bg-n-alpha-2 text-n-slate-12"
        >
          {{ secret }}
        </code>
        <Button
          faded
          slate
          sm
          type="button"
          :icon="copied ? 'i-lucide-check' : 'i-lucide-copy'"
          :label="
            copied
              ? t('FLOW_KANBAN.SETTINGS.WEBHOOKS.SECRET.COPIED')
              : t('FLOW_KANBAN.SETTINGS.WEBHOOKS.SECRET.COPY')
          "
          @click="copySecret"
        />
      </div>
      <p class="text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.SETTINGS.WEBHOOKS.SECRET.HOW') }}
      </p>
    </div>
  </Dialog>

  <Dialog
    ref="logDialogRef"
    width="2xl"
    :title="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.LOG.TITLE')"
    :description="logFor?.url"
    :show-confirm-button="false"
    :cancel-button-label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.LOG.CLOSE')"
    overflow-y-auto
  >
    <SkeletonRows v-if="isLoadingLog" :rows="3" />
    <p v-else-if="!deliveries.length" class="text-body-main text-n-slate-11">
      {{ t('FLOW_KANBAN.SETTINGS.WEBHOOKS.LOG.EMPTY') }}
    </p>
    <ul v-else class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
      <li
        v-for="delivery in deliveries"
        :key="delivery.id"
        class="flex flex-col gap-1 py-2"
      >
        <div class="flex flex-wrap items-center gap-2">
          <StatePill
            :tone="statusView(delivery).tone"
            :icon="statusView(delivery).icon"
            :label="statusLabel(delivery)"
          />
          <span class="text-body-main text-n-slate-12">
            {{
              delivery.event === 'ping'
                ? t('FLOW_KANBAN.SETTINGS.WEBHOOKS.LOG.PING')
                : eventName(delivery.event)
            }}
          </span>
        </div>
        <span class="text-label-small tabular-nums text-n-slate-11">
          {{ logDetail(delivery) }}
        </span>
        <span
          v-if="delivery.status !== 'success' && errorText(delivery)"
          class="text-label-small text-n-slate-11 break-words"
        >
          {{ errorText(delivery) }}
        </span>
      </li>
    </ul>
  </Dialog>

  <Dialog
    ref="deleteDialogRef"
    type="alert"
    :title="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.DELETE')"
    :description="
      t('FLOW_KANBAN.SETTINGS.WEBHOOKS.DELETE_CONFIRM', { url: toDelete?.url })
    "
    :confirm-button-label="t('FLOW_KANBAN.SETTINGS.WEBHOOKS.DELETE')"
    :is-loading="isDeleting"
    @confirm="confirmDelete"
  />
</template>
