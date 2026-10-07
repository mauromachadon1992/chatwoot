<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import RequiredComboBox from './RequiredComboBox.vue';
import {
  QUOTE_MAX_LENGTH,
  quoteLines,
  renderQuote,
  replyDraftKey,
} from './quote';
import { useFlowKanban } from './useFlowKanban';

// "Send quote": the message is built from the deal's product lines, shown for review, and put
// in the reply box of the linked conversation as a draft. The agent reads it there and sends it;
// nothing leaves from here.
const props = defineProps({
  card: { type: Object, required: true },
});

const { t, locale } = useI18n();
const router = useRouter();
const store = useStore();
const currentUser = useMapGetter('getCurrentUser');
const { money, conversationPath } = useFlowKanban();

const dialogRef = ref(null);
const message = ref('');
const conversationId = ref('');
const isSending = ref(false);

const conversations = computed(() => props.card.conversations || []);
const hasLines = computed(() => (props.card.items || []).length > 0);

const conversationOptions = computed(() =>
  conversations.value.map(conversation => ({
    value: conversation.display_id,
    label: t('FLOW_KANBAN.QUOTE.CONVERSATION', {
      id: conversation.display_id,
      status: t(
        `FLOW_KANBAN.AUTOMATIONS.STATUSES.${conversation.status.toUpperCase()}`
      ),
    }),
  }))
);

// The account's own message (Settings → Kanban), or the default in this agent's language.
const template = computed(
  () =>
    store.getters.getCurrentAccount?.settings?.flow_kanban_quote_template ||
    t('FLOW_KANBAN.QUOTE.DEFAULT_TEMPLATE')
);

const build = () =>
  renderQuote(template.value, {
    contact: props.card.contact?.name || '',
    deal: props.card.title,
    items: quoteLines(props.card.items || [], {
      money,
      locale: locale.value,
      unitLabel: unit => t(`FLOW_KANBAN.UNITS.${unit}`),
      discountLabel: percent => t('FLOW_KANBAN.QUOTE.DISCOUNT', { percent }),
    }),
    total: money(props.card.value_cents),
    agent: currentUser.value?.name || '',
  });

const length = computed(() => message.value.length);
const tooLong = computed(() => length.value > QUOTE_MAX_LENGTH);
const canSend = computed(
  () => message.value.trim() && conversationId.value && !tooLong.value
);

const open = () => {
  message.value = build();
  conversationId.value = conversations.value[0]?.display_id ?? '';
  dialogRef.value?.open();
};

// The dashboard knows a conversation by its display_id (AGENTS.md, "Conversation ids"), and so
// does the reply box: its draft is stored under `draft-<display_id>-REPLY`.
const send = async () => {
  isSending.value = true;
  try {
    await store.dispatch('draftMessages/set', {
      key: replyDraftKey(conversationId.value),
      message: message.value,
    });
    FlowKanbanAPI.recordQuote(props.card.id, conversationId.value).catch(
      () => {}
    );
    dialogRef.value?.close();
    await router.push(conversationPath(conversationId.value));
  } catch {
    useAlert(t('FLOW_KANBAN.QUOTE.FAILED'));
  } finally {
    isSending.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('FLOW_KANBAN.QUOTE.TITLE')"
    :description="t('FLOW_KANBAN.QUOTE.DESCRIPTION')"
    :confirm-button-label="t('FLOW_KANBAN.QUOTE.CONFIRM')"
    :disable-confirm-button="!canSend"
    :is-loading="isSending"
    width="xl"
    @confirm="send"
  >
    <div class="flex flex-col gap-4">
      <p v-if="!hasLines" class="text-body-main text-n-amber-11">
        {{ t('FLOW_KANBAN.QUOTE.NO_LINES') }}
      </p>

      <label
        v-if="conversations.length > 1"
        class="flex flex-col gap-1.5 text-label text-n-slate-12"
      >
        {{ t('FLOW_KANBAN.QUOTE.SEND_TO') }}
        <RequiredComboBox
          v-model="conversationId"
          :options="conversationOptions"
        />
      </label>
      <p
        v-else-if="!conversations.length"
        class="text-body-main text-n-amber-11"
      >
        {{ t('FLOW_KANBAN.QUOTE.NO_CONVERSATION') }}
      </p>

      <TextArea
        v-model="message"
        :label="t('FLOW_KANBAN.QUOTE.MESSAGE')"
        :message="
          tooLong
            ? t('FLOW_KANBAN.QUOTE.TOO_LONG', { max: QUOTE_MAX_LENGTH })
            : t('FLOW_KANBAN.QUOTE.COUNT', {
                count: length,
                max: QUOTE_MAX_LENGTH,
              })
        "
        :message-type="tooLong ? 'error' : 'info'"
        auto-height
        min-height="12rem"
      />
    </div>
  </Dialog>
</template>
