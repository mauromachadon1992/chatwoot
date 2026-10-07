<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import SettingsLayout from '../settings/SettingsLayout.vue';
import BaseSettingsHeader from '../settings/components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import EmptyState from './EmptyState.vue';
import SkeletonRows from './SkeletonRows.vue';
import DataSection from './DataSection.vue';
import WebhooksSection from './WebhooksSection.vue';
import { QUOTE_PLACEHOLDERS, placeholderText, renderQuote } from './quote';
import { useFlowKanban } from './useFlowKanban';

// Settings → Kanban: why deals are lost, the message a quote is composed from, and the webhooks.
// Administrators only (the route's permissions). Each change saves at once.
const { t } = useI18n();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const { money } = useFlowKanban();

const QUOTE_MAX_LENGTH = 2000;
const NAME_MAX_LENGTH = 80;

const reasons = ref([]);
const isLoading = ref(true);
const hasError = ref(false);
const newName = ref('');
const isAdding = ref(false);
const toDelete = ref(null);
const isDeleting = ref(false);
const deleteDialogRef = ref(null);

const quoteDraft = ref('');
const isSavingQuote = ref(false);

const savedQuote = computed(
  () =>
    store.getters.getCurrentAccount?.settings?.flow_kanban_quote_template || ''
);
const defaultQuote = computed(() => t('FLOW_KANBAN.QUOTE.DEFAULT_TEMPLATE'));
const quoteDirty = computed(() => quoteDraft.value.trim() !== savedQuote.value);
const quoteTooLong = computed(() => quoteDraft.value.length > QUOTE_MAX_LENGTH);

// The preview uses example values, so an administrator sees the message as an agent would.
const preview = computed(() =>
  renderQuote(quoteDraft.value.trim() || defaultQuote.value, {
    contact: t('FLOW_KANBAN.SETTINGS.EXAMPLE.CONTACT'),
    deal: t('FLOW_KANBAN.SETTINGS.EXAMPLE.DEAL'),
    items: t('FLOW_KANBAN.SETTINGS.EXAMPLE.ITEMS'),
    total: money(123450),
    agent: t('FLOW_KANBAN.SETTINGS.EXAMPLE.AGENT'),
  })
);

const fail = error =>
  useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));

const load = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await FlowKanbanAPI.getLostReasons();
    reasons.value = data.payload;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const addReason = async () => {
  const name = newName.value.trim();
  if (!name || isAdding.value) return;
  isAdding.value = true;
  try {
    const { data } = await FlowKanbanAPI.createLostReason(name);
    reasons.value = [...reasons.value, data.payload].sort((a, b) =>
      a.name.localeCompare(b.name)
    );
    newName.value = '';
  } catch (error) {
    fail(error);
  } finally {
    isAdding.value = false;
  }
};

// InlineInput edits `reason.name` in place; an empty or unchanged name puts the saved one back.
const renameReason = async reason => {
  const saved = reasons.value.find(item => item.id === reason.id);
  const name = reason.name.trim();
  if (!name || name === reason.savedName) {
    reason.name = reason.savedName;
    return;
  }
  try {
    const { data } = await FlowKanbanAPI.updateLostReason(saved.id, name);
    Object.assign(saved, data.payload, { savedName: data.payload.name });
  } catch (error) {
    reason.name = reason.savedName;
    fail(error);
  }
};

const askDelete = reason => {
  toDelete.value = reason;
  deleteDialogRef.value?.open();
};

const confirmDelete = async () => {
  isDeleting.value = true;
  try {
    await FlowKanbanAPI.deleteLostReason(toDelete.value.id);
    reasons.value = reasons.value.filter(item => item.id !== toDelete.value.id);
    deleteDialogRef.value?.close();
  } catch (error) {
    fail(error);
  } finally {
    isDeleting.value = false;
  }
};

const saveQuote = async () => {
  if (quoteTooLong.value || isSavingQuote.value) return;
  isSavingQuote.value = true;
  try {
    await FlowKanbanAPI.updateSettings({
      quote_template: quoteDraft.value.trim(),
    });
    await store.dispatch('accounts/get', {
      silent: true,
      accountId: accountId.value,
    });
    useAlert(t('FLOW_KANBAN.SETTINGS.QUOTE.SAVED'));
  } catch (error) {
    fail(error);
  } finally {
    isSavingQuote.value = false;
  }
};

const useDefault = () => {
  quoteDraft.value = '';
};

watch(
  savedQuote,
  value => {
    quoteDraft.value = value;
  },
  { immediate: true }
);

const rows = computed(() =>
  reasons.value.map(reason => ({
    ...reason,
    savedName: reason.savedName ?? reason.name,
  }))
);

onMounted(load);
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        :title="t('FLOW_KANBAN.SETTINGS.HEADER')"
        :description="t('FLOW_KANBAN.SETTINGS.DESCRIPTION')"
        :show-search="false"
      />
    </template>

    <template #body>
      <div class="flex flex-col gap-10 max-w-3xl pb-12">
        <section
          class="flex flex-col gap-4"
          aria-labelledby="flow-lost-reasons-title"
        >
          <div class="flex flex-col gap-1">
            <h2
              id="flow-lost-reasons-title"
              class="text-heading-2 text-n-slate-12"
            >
              {{ t('FLOW_KANBAN.SETTINGS.LOST_REASONS.TITLE') }}
            </h2>
            <p class="text-body-main text-n-slate-11">
              {{ t('FLOW_KANBAN.SETTINGS.LOST_REASONS.DESCRIPTION') }}
            </p>
          </div>

          <SkeletonRows v-if="isLoading" :rows="3" />

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

          <template v-else>
            <EmptyState
              v-if="!rows.length"
              framed
              size="compact"
              icon="i-lucide-circle-x"
              :title="t('FLOW_KANBAN.SETTINGS.LOST_REASONS.EMPTY_TITLE')"
              :description="t('FLOW_KANBAN.SETTINGS.LOST_REASONS.EMPTY_BODY')"
            />

            <ul
              v-else
              class="flex flex-col rounded-lg outline outline-1 outline-n-container divide-y divide-n-weak bg-n-solid-1"
            >
              <li
                v-for="reason in rows"
                :key="reason.id"
                class="flex items-center gap-3 px-3 py-2"
              >
                <InlineInput
                  v-model="reason.name"
                  :max-length="NAME_MAX_LENGTH"
                  :placeholder="t('FLOW_KANBAN.SETTINGS.LOST_REASONS.NAME')"
                  class="flex-1 min-w-0 px-2 py-1 rounded-md hover:bg-n-alpha-1 focus-within:bg-n-alpha-2"
                  @blur="renameReason(reason)"
                  @enter-press="renameReason(reason)"
                />
                <span
                  class="text-label-small tabular-nums text-n-slate-11 whitespace-nowrap"
                >
                  {{
                    t(
                      'FLOW_KANBAN.SETTINGS.LOST_REASONS.USED',
                      { count: reason.deals_count },
                      reason.deals_count
                    )
                  }}
                </span>
                <Button
                  v-tooltip.top="t('FLOW_KANBAN.SETTINGS.LOST_REASONS.DELETE')"
                  ghost
                  ruby
                  xs
                  type="button"
                  icon="i-lucide-trash-2"
                  :aria-label="t('FLOW_KANBAN.SETTINGS.LOST_REASONS.DELETE')"
                  @click="askDelete(reason)"
                />
              </li>
            </ul>

            <div class="flex items-end gap-3">
              <Input
                v-model="newName"
                class="flex-1 min-w-0"
                :label="t('FLOW_KANBAN.SETTINGS.LOST_REASONS.NEW')"
                :placeholder="
                  t('FLOW_KANBAN.SETTINGS.LOST_REASONS.PLACEHOLDER')
                "
                @keydown.enter.prevent="addReason"
              />
              <Button
                faded
                blue
                sm
                type="button"
                icon="i-lucide-plus"
                :label="t('FLOW_KANBAN.SETTINGS.LOST_REASONS.ADD')"
                :is-loading="isAdding"
                :disabled="!newName.trim() || isAdding"
                @click="addReason"
              />
            </div>
          </template>
        </section>

        <section class="flex flex-col gap-4" aria-labelledby="flow-quote-title">
          <div class="flex flex-col gap-1">
            <h2 id="flow-quote-title" class="text-heading-2 text-n-slate-12">
              {{ t('FLOW_KANBAN.SETTINGS.QUOTE.TITLE') }}
            </h2>
            <p class="text-body-main text-n-slate-11">
              {{ t('FLOW_KANBAN.SETTINGS.QUOTE.DESCRIPTION') }}
            </p>
          </div>

          <TextArea
            v-model="quoteDraft"
            :label="t('FLOW_KANBAN.SETTINGS.QUOTE.MESSAGE')"
            :placeholder="defaultQuote"
            :message="
              quoteTooLong
                ? t('FLOW_KANBAN.SETTINGS.QUOTE.TOO_LONG', {
                    max: QUOTE_MAX_LENGTH,
                  })
                : t('FLOW_KANBAN.SETTINGS.QUOTE.EMPTY_IS_DEFAULT')
            "
            :message-type="quoteTooLong ? 'error' : 'info'"
            auto-height
            min-height="8rem"
          />

          <p class="text-label-small text-n-slate-11">
            {{ t('FLOW_KANBAN.SETTINGS.QUOTE.PLACEHOLDERS') }}
            <code
              v-for="name in QUOTE_PLACEHOLDERS"
              :key="name"
              class="px-1 mx-0.5 rounded bg-n-alpha-2 text-n-slate-12"
              >{{ placeholderText(name) }}</code
            >
          </p>

          <div class="flex flex-col gap-1.5">
            <span class="text-label text-n-slate-12">
              {{ t('FLOW_KANBAN.SETTINGS.QUOTE.PREVIEW') }}
            </span>
            <p
              class="p-3 text-body-main whitespace-pre-wrap break-words rounded-lg bg-n-alpha-1 text-n-slate-12"
              aria-live="polite"
            >
              {{ preview }}
            </p>
          </div>

          <div class="flex items-center gap-3">
            <Button
              solid
              blue
              sm
              type="button"
              :label="t('FLOW_KANBAN.SETTINGS.QUOTE.SAVE')"
              :is-loading="isSavingQuote"
              :disabled="!quoteDirty || quoteTooLong || isSavingQuote"
              @click="saveQuote"
            />
            <Button
              v-if="quoteDraft.trim()"
              link
              slate
              sm
              type="button"
              :label="t('FLOW_KANBAN.SETTINGS.QUOTE.USE_DEFAULT')"
              @click="useDefault"
            />
          </div>
        </section>

        <DataSection />

        <WebhooksSection />
      </div>
    </template>
  </SettingsLayout>

  <Dialog
    ref="deleteDialogRef"
    type="alert"
    :title="t('FLOW_KANBAN.SETTINGS.LOST_REASONS.DELETE')"
    :description="
      t('FLOW_KANBAN.SETTINGS.LOST_REASONS.DELETE_CONFIRM', {
        name: toDelete?.name,
      })
    "
    :confirm-button-label="t('FLOW_KANBAN.SETTINGS.LOST_REASONS.DELETE')"
    :is-loading="isDeleting"
    @confirm="confirmDelete"
  />
</template>
