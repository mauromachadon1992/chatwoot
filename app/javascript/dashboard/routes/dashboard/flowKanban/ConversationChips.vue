<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useFlowKanban } from './useFlowKanban';

defineProps({
  conversations: { type: Array, default: () => [] },
});

const { t } = useI18n();
const { inboxFor, inboxIcon, conversationPath } = useFlowKanban();

const STATUS_DOT = {
  open: 'bg-n-teal-9',
  pending: 'bg-n-amber-9',
  snoozed: 'bg-n-slate-9',
  resolved: 'bg-n-slate-7',
};
</script>

<template>
  <div class="flex flex-wrap gap-1">
    <template
      v-for="conversation in conversations"
      :key="conversation.display_id"
    >
      <router-link
        v-if="inboxFor(conversation.inbox_id)"
        :to="conversationPath(conversation.display_id)"
        :title="
          conversation.handled_by_agent
            ? `${inboxFor(conversation.inbox_id).name} · ${t('FLOW_KANBAN.CARD.HANDLED_BY_AGENT')}`
            : inboxFor(conversation.inbox_id).name
        "
        class="inline-flex items-center gap-1 px-1.5 py-0.5 min-h-6 rounded-md bg-n-alpha-2 text-label-small text-n-slate-11 hover:text-n-slate-12"
        @click.stop
      >
        <Icon
          v-if="conversation.handled_by_agent"
          icon="i-lucide-bot"
          class="size-3 text-n-amber-11"
        />
        <span
          v-else
          class="size-1.5 rounded-full"
          :class="STATUS_DOT[conversation.status]"
        />
        <span v-if="conversation.handled_by_agent" class="sr-only">
          {{ t('FLOW_KANBAN.CARD.HANDLED_BY_AGENT') }}
        </span>
        <Icon
          :icon="inboxIcon(inboxFor(conversation.inbox_id))"
          class="size-3"
        />
        #{{ conversation.display_id }}
      </router-link>
      <span
        v-else
        :title="t('FLOW_KANBAN.CARD.RESTRICTED_CONVERSATION')"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md bg-n-alpha-1 text-label-small text-n-slate-11"
      >
        <Icon :icon="inboxIcon(null)" class="size-3" />
        #{{ conversation.display_id }}
      </span>
    </template>
  </div>
</template>
