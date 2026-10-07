<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import { badgeLabel, describeNotification } from './notifications';
import { useFlowKanban } from './useFlowKanban';
import SkeletonRows from './SkeletonRows.vue';
import EmptyState from './EmptyState.vue';

// The bell of the Kanban: what happened on the agent's own deals while they were elsewhere.
// Opening a row marks it read and opens what it is about: the task in My tasks, or the deal;
// the badge counts what is still unread.
defineProps({
  // `md` in the mobile toolbar, where targets are larger.
  size: { type: String, default: 'sm' },
});

const emit = defineEmits(['openCard', 'openTask']);

const { t } = useI18n();
const kanban = useFlowKanbanStore();
const { relativeTime } = useFlowKanban();

const isLoading = ref(!kanban.notificationsLoaded);
const unread = computed(() => kanban.unreadCount);
const bellLabel = computed(() =>
  unread.value
    ? t('FLOW_KANBAN.NOTIFICATIONS.BELL_UNREAD', { count: unread.value })
    : t('FLOW_KANBAN.NOTIFICATIONS.BELL')
);
const rows = computed(() =>
  kanban.notifications.map(notification => ({
    notification,
    view: describeNotification(notification),
    isUnread: !notification.read_at,
  }))
);

const fail = () => useAlert(t('FLOW_KANBAN.ERRORS.GENERIC'));

const load = async () => {
  try {
    await kanban.fetchNotifications();
  } catch {
    fail();
  } finally {
    isLoading.value = false;
  }
};

const openRow = async (row, hide) => {
  hide();
  const { task_id: taskId, card_id: cardId } = row.notification;
  if (taskId) emit('openTask', { taskId, cardId });
  else emit('openCard', { id: cardId });
  try {
    await kanban.markNotificationRead(row.notification);
  } catch {
    fail();
  }
};

const readAll = async () => {
  try {
    await kanban.markAllNotificationsRead();
  } catch {
    fail();
  }
};

onMounted(load);
</script>

<template>
  <Popover align="end">
    <span class="relative inline-flex">
      <Button
        v-tooltip.bottom="t('FLOW_KANBAN.NOTIFICATIONS.TITLE')"
        ghost
        slate
        :size="size"
        icon="i-lucide-bell"
        :aria-label="bellLabel"
      />
      <span
        v-if="unread"
        aria-hidden="true"
        class="absolute -top-1 -end-1 min-w-4 h-4 px-1 text-center text-white rounded-full pointer-events-none text-label-small tabular-nums bg-n-brand"
      >
        {{ badgeLabel(unread) }}
      </span>
    </span>

    <template #content="{ hide }">
      <div class="flex flex-col w-[22rem] max-w-full">
        <div
          class="flex items-center justify-between gap-3 px-4 py-3 border-b border-n-weak"
        >
          <h4 class="text-heading-3 text-n-slate-12">
            {{ t('FLOW_KANBAN.NOTIFICATIONS.TITLE') }}
          </h4>
          <Button
            link
            blue
            sm
            type="button"
            :label="t('FLOW_KANBAN.NOTIFICATIONS.MARK_ALL')"
            :disabled="!unread"
            @click="readAll"
          />
        </div>

        <SkeletonRows v-if="isLoading" :rows="3" height="h-12" class="p-3" />

        <EmptyState
          v-else-if="!rows.length"
          size="compact"
          icon="i-lucide-bell"
          :title="t('FLOW_KANBAN.NOTIFICATIONS.EMPTY_TITLE')"
          :description="t('FLOW_KANBAN.NOTIFICATIONS.EMPTY_TEXT')"
        />

        <ul
          v-else
          class="flex flex-col max-h-[24rem] overflow-y-auto divide-y divide-n-weak"
        >
          <li
            v-for="row in rows"
            :key="row.notification.id"
            role="button"
            tabindex="0"
            class="flex items-start gap-3 px-4 py-3 cursor-pointer hover:bg-n-alpha-1 focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="openRow(row, hide)"
            @keydown.enter.prevent="openRow(row, hide)"
          >
            <span
              class="flex items-center justify-center flex-shrink-0 rounded-lg size-8 bg-n-alpha-2"
              :class="row.view.toneClass"
            >
              <Icon :icon="row.view.icon" class="size-4" />
            </span>
            <div class="flex flex-col flex-1 min-w-0">
              <span
                :class="
                  row.isUnread
                    ? 'text-label text-n-slate-12'
                    : 'text-body-main text-n-slate-11'
                "
              >
                {{ t(row.view.titleKey, row.view.titleParams) }}
              </span>
              <span class="text-label-small truncate text-n-slate-11">
                {{
                  row.view.isTask
                    ? t('FLOW_KANBAN.NOTIFICATIONS.TASK_ON_CARD', {
                        task: row.view.taskTitle,
                        card: row.view.cardTitle,
                      })
                    : row.view.cardTitle
                }}
              </span>
              <span class="text-label-small text-n-slate-10">
                {{ relativeTime(row.notification.created_at) }}
              </span>
            </div>
            <span v-if="row.isUnread" class="flex-shrink-0 mt-2">
              <span class="block rounded-full size-2 bg-n-brand" />
              <span class="sr-only">
                {{ t('FLOW_KANBAN.NOTIFICATIONS.UNREAD') }}
              </span>
            </span>
          </li>
        </ul>
      </div>
    </template>
  </Popover>
</template>
