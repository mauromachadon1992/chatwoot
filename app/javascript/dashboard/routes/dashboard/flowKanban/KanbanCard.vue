<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ConversationChips from './ConversationChips.vue';
import { useFlowKanban } from './useFlowKanban';

const props = defineProps({
  card: { type: Object, required: true },
});

defineEmits(['open']);

const { t } = useI18n();
const { cardFields, relativeTime, money } = useFlowKanban();

const contactLabel = computed(
  () =>
    props.card.contact.name ||
    props.card.contact.phone_number ||
    props.card.contact.email
);

// The freshest conversation stands for the deal's last activity, whatever its channel.
const lastActivityAt = computed(() =>
  Math.max(0, ...props.card.conversations.map(c => c.last_activity_at || 0))
);

const showValue = computed(
  () => cardFields.value.has('value') && props.card.value_cents > 0
);
const showAssignee = computed(
  () => cardFields.value.has('assignee') && props.card.assignee
);
const showConversations = computed(
  () => cardFields.value.has('conversations') && props.card.conversations.length
);
const showTimeInStage = computed(
  () => cardFields.value.has('time_in_stage') && props.card.stage_changed_at
);
const showLastActivity = computed(
  () => cardFields.value.has('last_activity') && lastActivityAt.value > 0
);
// Follow-ups are part of working the deal, not a field an account can switch off.
const tasks = computed(() => props.card.tasks || { open: 0, overdue: 0 });
const showTasks = computed(() => tasks.value.open > 0);
</script>

<template>
  <article
    role="button"
    tabindex="0"
    class="group flex flex-col gap-2 p-3 rounded-lg bg-n-solid-1 outline outline-1 outline-n-container shadow-sm cursor-grab select-none transition-shadow duration-150 hover:shadow-md active:cursor-grabbing focus-visible:outline-2 focus-visible:outline-n-brand"
    @click="$emit('open', card)"
    @keydown.enter.prevent="$emit('open', card)"
  >
    <div class="flex items-start gap-2">
      <h4
        class="flex-1 min-w-0 text-heading-3 break-words text-n-slate-12 line-clamp-2"
      >
        {{ card.title }}
      </h4>
      <Avatar
        v-if="showAssignee"
        v-tooltip.top="card.assignee.name"
        :src="card.assignee.thumbnail"
        :name="card.assignee.name"
        :size="20"
        rounded-full
        class="flex-shrink-0"
      />
    </div>

    <p
      v-if="showValue"
      v-tooltip.top="t('FLOW_KANBAN.CARD.VALUE')"
      class="text-label tabular-nums text-n-slate-12 w-fit"
    >
      <span class="sr-only">{{ t('FLOW_KANBAN.CARD.VALUE') }}</span>
      {{ money(card.value_cents, { whole: true }) }}
    </p>

    <div
      v-if="cardFields.has('contact')"
      class="flex items-center min-w-0 gap-1.5"
    >
      <Avatar
        :src="card.contact.thumbnail"
        :name="contactLabel || ''"
        :size="16"
        rounded-full
      />
      <span class="text-label-small truncate text-n-slate-11">{{
        contactLabel
      }}</span>
    </div>

    <ConversationChips
      v-if="showConversations"
      :conversations="card.conversations"
    />

    <div
      v-if="showTimeInStage || showLastActivity || showTasks"
      class="flex flex-wrap items-center gap-x-3 gap-y-1 text-label-small text-n-slate-10"
    >
      <span
        v-if="showTasks"
        v-tooltip.top="
          tasks.overdue
            ? t('FLOW_KANBAN.CARD.TASKS_OVERDUE', { count: tasks.overdue })
            : t('FLOW_KANBAN.CARD.TASKS_OPEN', { count: tasks.open })
        "
        class="inline-flex items-center gap-1 tabular-nums"
        :class="tasks.overdue ? 'text-n-ruby-11' : 'text-n-slate-11'"
      >
        <Icon
          :icon="
            tasks.overdue ? 'i-lucide-alarm-clock' : 'i-lucide-list-checks'
          "
          class="size-3.5"
        />
        {{ tasks.overdue || tasks.open }}
        <span class="sr-only">
          {{
            tasks.overdue
              ? t('FLOW_KANBAN.CARD.TASKS_OVERDUE', { count: tasks.overdue })
              : t('FLOW_KANBAN.CARD.TASKS_OPEN', { count: tasks.open })
          }}
        </span>
      </span>
      <span
        v-if="showTimeInStage"
        v-tooltip.top="t('FLOW_KANBAN.CARD.TIME_IN_STAGE')"
        class="inline-flex items-center gap-1"
      >
        <Icon icon="i-lucide-hourglass" class="size-3.5" />
        {{ relativeTime(card.stage_changed_at) }}
      </span>
      <span
        v-if="showLastActivity"
        v-tooltip.top="t('FLOW_KANBAN.CARD.LAST_ACTIVITY')"
        class="inline-flex items-center gap-1"
      >
        <Icon icon="i-lucide-message-circle" class="size-3.5" />
        {{ relativeTime(lastActivityAt) }}
      </span>
    </div>
  </article>
</template>
