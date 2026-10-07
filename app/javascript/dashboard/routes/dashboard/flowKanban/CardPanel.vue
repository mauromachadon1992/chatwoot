<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import RequiredComboBox from './RequiredComboBox.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CardValueSection from './CardValueSection.vue';
import CardTasksSection from './CardTasksSection.vue';
import CardHistorySection from './CardHistorySection.vue';
import CardAiSection from './CardAiSection.vue';
import { appendToDescription } from './aiSummary';
import StatePill from './StatePill.vue';
import LostReasonDialog from './LostReasonDialog.vue';
import { useFlowKanban } from './useFlowKanban';
import SkeletonRows from './SkeletonRows.vue';

const { t } = useI18n();
const kanban = useFlowKanbanStore();
const { isAdmin } = useAdmin();
const currentUser = useMapGetter('getCurrentUser');
const agents = useMapGetter('agents/getAgents');
const {
  inboxFor,
  inboxIcon,
  conversationPath,
  contactPath,
  relativeTime,
  hasFeature,
} = useFlowKanban();

const panelRef = ref(null);
const deleteDialogRef = ref(null);
const lostDialogRef = ref(null);
const card = ref(null);
const form = ref({
  title: '',
  description: '',
  assignee_id: '',
  stage_id: '',
  expected_close_on: '',
});
const isSaving = ref(false);
const isDeleting = ref(false);
const isReviewing = ref(false);
const tasksKey = ref(0);

// The accepted AI summary goes under the description in the form; the card's own Save keeps it.
const addSummary = summary => {
  form.value.description = appendToDescription(form.value.description, summary);
};

const staleDays = computed(() =>
  hasFeature('stale_alerts') ? card.value?.stale_days : null
);

// An automatic deal is reviewed by any change; this accepts it as it is.
const markReviewed = async () => {
  isReviewing.value = true;
  try {
    card.value = await kanban.updateCard(card.value.id, { reviewed: true });
  } catch {
    useAlert(t('FLOW_KANBAN.ERRORS.GENERIC'));
  } finally {
    isReviewing.value = false;
  }
};

const board = computed(() =>
  kanban.boards.find(item => item.id === card.value?.board_id)
);
const stageOptions = computed(() =>
  (board.value?.stages || []).map(stage => ({
    value: stage.id,
    label: stage.name,
  }))
);
const assigneeOptions = computed(() => [
  { value: '', label: t('FLOW_KANBAN.CARD_FORM.NO_ASSIGNEE') },
  ...agents.value.map(agent => ({ value: agent.id, label: agent.name })),
]);
const canDelete = computed(
  () => isAdmin.value || card.value?.created_by_id === currentUser.value.id
);
const isDirty = computed(() => {
  if (!card.value) return false;
  return (
    form.value.title !== card.value.title ||
    form.value.description !== (card.value.description || '') ||
    form.value.assignee_id !== (card.value.assignee?.id || '') ||
    form.value.expected_close_on !== (card.value.expected_close_on || '')
  );
});

const syncForm = source => {
  form.value = {
    title: source.title,
    description: source.description || '',
    assignee_id: source.assignee?.id || '',
    stage_id: source.stage_id,
    expected_close_on: source.expected_close_on || '',
  };
};

const refreshLines = async () => {
  const cardId = card.value.id;
  const { data } = await FlowKanbanAPI.getCard(cardId);
  if (card.value?.id === cardId)
    card.value = { ...card.value, ...data.payload };
};

// Changes made elsewhere while the panel is open (another agent, the conversation panel)
// arrive through the store; untouched fields follow them.
watch(
  () => kanban.lastCardEvent,
  event => {
    if (!event || event.card.id !== card.value?.id) return;
    if (event.deleted) {
      panelRef.value?.close();
      return;
    }
    // Board events carry the value but not the product lines: when the value or the line
    // count moved under us, the lines are fetched again.
    const linesChanged =
      !event.card.items &&
      (event.card.items_count !== card.value.items_count ||
        event.card.value_cents !== card.value.value_cents);
    const keepEdits = isDirty.value;
    card.value = { ...card.value, ...event.card };
    if (!keepEdits) syncForm(card.value);
    else form.value.stage_id = event.card.stage_id;
    if (linesChanged) refreshLines();
  }
);

const onValueChange = payload => {
  card.value = { ...card.value, ...payload };
};

const open = async cardId => {
  card.value = null;
  panelRef.value?.open();
  const { data } = await FlowKanbanAPI.getCard(cardId);
  card.value = data.payload;
  syncForm(card.value);
};

const save = async () => {
  if (!form.value.title.trim()) return;
  isSaving.value = true;
  try {
    card.value = await kanban.updateCard(card.value.id, {
      title: form.value.title.trim(),
      description: form.value.description,
      assignee_id: form.value.assignee_id || null,
      expected_close_on: form.value.expected_close_on || null,
    });
    syncForm(card.value);
    useAlert(t('FLOW_KANBAN.CARD_FORM.SAVED'));
  } catch {
    useAlert(t('FLOW_KANBAN.ERRORS.GENERIC'));
  } finally {
    isSaving.value = false;
  }
};

// A stage picked here sends the card to the top of that column.
const changeStage = async stageId => {
  if (!stageId || stageId === card.value.stage_id) return;
  const target = board.value?.stages.find(stage => stage.id === stageId);
  let lost = {};
  if (target?.stage_type === 'lost') {
    const answer = await lostDialogRef.value?.ask();
    if (!answer) {
      form.value.stage_id = card.value.stage_id;
      return;
    }
    lost = answer;
  }
  try {
    const { data } = await FlowKanbanAPI.moveCard(card.value.id, {
      stageId,
      ...lost,
    });
    kanban.upsertCard(data.payload);
  } catch {
    form.value.stage_id = card.value.stage_id;
    useAlert(t('FLOW_KANBAN.ERRORS.GENERIC'));
  }
};

const unlink = async conversation => {
  try {
    card.value = await kanban.unlinkConversation(
      card.value.id,
      conversation.display_id
    );
  } catch {
    useAlert(t('FLOW_KANBAN.ERRORS.GENERIC'));
  }
};

const confirmDelete = async () => {
  isDeleting.value = true;
  try {
    await kanban.deleteCard(card.value);
    deleteDialogRef.value?.close();
    panelRef.value?.close();
    useAlert(t('FLOW_KANBAN.CARD_FORM.DELETED'));
  } catch {
    useAlert(t('FLOW_KANBAN.ERRORS.GENERIC'));
  } finally {
    isDeleting.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <SidePanel
    ref="panelRef"
    :title="card?.title || t('FLOW_KANBAN.CARD_FORM.EDIT_TITLE')"
    width="lg"
  >
    <SkeletonRows v-if="!card" :height="['h-10', 'h-10', 'h-24']" />

    <form v-else class="flex flex-col gap-8" @submit.prevent="save">
      <div v-if="card.needs_review || staleDays" class="flex flex-col gap-3">
        <div
          v-if="card.needs_review"
          class="flex flex-wrap items-start gap-3 p-3 rounded-lg bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-container"
        >
          <Icon
            icon="i-lucide-message-square-plus"
            class="flex-shrink-0 mt-0.5 size-4 text-n-slate-11"
          />
          <p class="flex-1 min-w-[12rem] text-body-main text-n-slate-12">
            {{ t('FLOW_KANBAN.CARD_FORM.AUTOMATIC_NOTICE') }}
          </p>
          <Button
            faded
            blue
            sm
            type="button"
            icon="i-lucide-check"
            :label="t('FLOW_KANBAN.CARD_FORM.MARK_REVIEWED')"
            :is-loading="isReviewing"
            @click="markReviewed"
          />
        </div>
        <StatePill
          v-if="staleDays"
          tone="amber"
          icon="i-lucide-hourglass"
          :label="t('FLOW_KANBAN.CARD_FORM.STALE', { days: staleDays })"
        />
      </div>

      <div class="flex flex-col gap-4">
        <Input
          v-model="form.title"
          :label="t('FLOW_KANBAN.CARD_FORM.TITLE')"
          :message-type="form.title.trim() ? 'info' : 'error'"
        />
        <div class="grid grid-cols-2 gap-4">
          <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
            {{ t('FLOW_KANBAN.CARD_FORM.STAGE') }}
            <RequiredComboBox
              v-model="form.stage_id"
              :options="stageOptions"
              @update:model-value="changeStage"
            />
          </label>
          <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
            {{ t('FLOW_KANBAN.CARD_FORM.ASSIGNEE') }}
            <ComboBox v-model="form.assignee_id" :options="assigneeOptions" />
          </label>
        </div>
        <TextArea
          v-model="form.description"
          :label="t('FLOW_KANBAN.CARD_FORM.DESCRIPTION')"
          :placeholder="t('FLOW_KANBAN.CARD_FORM.DESCRIPTION_PLACEHOLDER')"
          :max-length="5000"
          auto-height
          min-height="6rem"
        />
      </div>

      <div class="flex flex-col gap-4">
        <Input
          v-model="form.expected_close_on"
          type="date"
          :label="t('FLOW_KANBAN.CARD_FORM.EXPECTED_CLOSE')"
          :message="t('FLOW_KANBAN.CARD_FORM.EXPECTED_CLOSE_HINT')"
        />
      </div>

      <CardValueSection :card="card" @update:card="onValueChange" />

      <CardTasksSection :key="tasksKey" :card="card" />

      <CardAiSection
        v-if="hasFeature('ai_summary')"
        :card="card"
        :description="form.description"
        @accept-summary="addSummary"
        @task-created="tasksKey += 1"
      />

      <section class="flex flex-col gap-3">
        <h4 class="text-heading-3 text-n-slate-12">
          {{ t('FLOW_KANBAN.CARD_FORM.CONTACT') }}
        </h4>
        <div class="flex items-center gap-3">
          <Avatar
            :src="card.contact.thumbnail"
            :name="card.contact.name || ''"
            :size="36"
            rounded-full
          />
          <div class="flex flex-col flex-1 min-w-0">
            <span class="text-heading-3 truncate text-n-slate-12">
              {{ card.contact.name || card.contact.phone_number }}
            </span>
            <span class="text-label-small truncate text-n-slate-11">
              {{
                [card.contact.phone_number, card.contact.email]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </span>
          </div>
          <router-link :to="contactPath(card.contact.id)">
            <Button
              link
              blue
              sm
              type="button"
              :label="t('FLOW_KANBAN.CARD_FORM.OPEN_CONTACT')"
            />
          </router-link>
        </div>
      </section>

      <section class="flex flex-col gap-3">
        <h4 class="text-heading-3 text-n-slate-12">
          {{ t('FLOW_KANBAN.CARD_FORM.CONVERSATIONS') }}
        </h4>
        <p
          v-if="!card.conversations.length"
          class="text-body-main text-n-slate-11"
        >
          {{ t('FLOW_KANBAN.CARD.NO_CONVERSATIONS') }}
        </p>
        <ul v-else class="flex flex-col divide-y divide-n-weak">
          <li
            v-for="conversation in card.conversations"
            :key="conversation.display_id"
            class="flex items-center gap-3 py-2"
          >
            <span
              class="flex items-center justify-center flex-shrink-0 rounded-lg size-8 bg-n-alpha-2 text-n-slate-11"
            >
              <Icon
                :icon="inboxIcon(inboxFor(conversation.inbox_id))"
                class="size-4"
              />
            </span>
            <div class="flex flex-col flex-1 min-w-0">
              <span class="text-body-main truncate text-n-slate-12">
                {{
                  inboxFor(conversation.inbox_id)?.name ||
                  t('FLOW_KANBAN.CARD.RESTRICTED_CONVERSATION')
                }}
              </span>
              <span class="text-label-small text-n-slate-11">
                #{{ conversation.display_id }} ·
                {{
                  t(
                    `CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${conversation.status}.TEXT`
                  )
                }}
                · {{ relativeTime(conversation.last_activity_at) }}
              </span>
            </div>
            <router-link
              v-if="inboxFor(conversation.inbox_id)"
              v-tooltip.top="t('FLOW_KANBAN.CARD_FORM.OPEN_CONVERSATION')"
              :to="conversationPath(conversation.display_id)"
            >
              <Button
                ghost
                slate
                xs
                type="button"
                icon="i-lucide-external-link"
                :aria-label="t('FLOW_KANBAN.CARD_FORM.OPEN_CONVERSATION')"
              />
            </router-link>
            <Button
              v-tooltip.top="t('FLOW_KANBAN.CARD_FORM.UNLINK')"
              ghost
              slate
              xs
              type="button"
              icon="i-lucide-unlink"
              :aria-label="t('FLOW_KANBAN.CARD_FORM.UNLINK')"
              @click="unlink(conversation)"
            />
          </li>
        </ul>
      </section>

      <CardHistorySection :card="card" />
    </form>

    <template v-if="card" #footer>
      <div class="flex items-center justify-between gap-3">
        <Button
          v-if="canDelete"
          ghost
          ruby
          sm
          icon="i-lucide-trash-2"
          :label="t('FLOW_KANBAN.CARD_FORM.DELETE')"
          @click="deleteDialogRef?.open()"
        />
        <Button
          solid
          blue
          sm
          class="ms-auto"
          :label="t('FLOW_KANBAN.CARD_FORM.SAVE')"
          :is-loading="isSaving"
          :disabled="!isDirty || !form.title.trim() || isSaving"
          @click="save"
        />
      </div>
    </template>
  </SidePanel>

  <LostReasonDialog ref="lostDialogRef" />

  <Dialog
    ref="deleteDialogRef"
    type="alert"
    :title="t('FLOW_KANBAN.CARD_FORM.DELETE')"
    :description="t('FLOW_KANBAN.CARD_FORM.DELETE_CONFIRM')"
    :confirm-button-label="t('FLOW_KANBAN.CARD_FORM.DELETE')"
    :is-loading="isDeleting"
    @confirm="confirmDelete"
  />
</template>
