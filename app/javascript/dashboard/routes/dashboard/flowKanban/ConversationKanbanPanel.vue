<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

import Button from 'dashboard/components-next/button/Button.vue';
import RequiredComboBox from './RequiredComboBox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useFlowKanban } from './useFlowKanban';

// The Kanban side of a conversation, for any channel: the cards it is on, the contact's
// other cards it can join, and a shortcut to open a new card from it.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  contactId: { type: Number, default: null },
});

const { t } = useI18n();
const router = useRouter();
const kanban = useFlowKanbanStore();
const { boardPath } = useFlowKanban();

const linked = ref([]);
const contactCards = ref([]);
const isLoading = ref(true);
const busyCardId = ref(null);
const newCard = ref({ board_id: '', stage_id: '' });
const isCreating = ref(false);

const displayId = computed(() => Number(props.conversationId));
const boardOptions = computed(() =>
  kanban.boards.map(board => ({ value: board.id, label: board.name }))
);
const stagesOf = boardId =>
  kanban.boards.find(board => board.id === boardId)?.stages || [];
const newCardStageOptions = computed(() =>
  stagesOf(newCard.value.board_id).map(stage => ({
    value: stage.id,
    label: stage.name,
  }))
);

const fetchCards = async () => {
  const { data } = await FlowKanbanAPI.getConversationCards(displayId.value);
  linked.value = data.payload.linked;
  contactCards.value = data.payload.contact_cards;
};

const load = async () => {
  isLoading.value = true;
  try {
    if (!kanban.boardsLoaded) await kanban.fetchBoards();
    await fetchCards();
    const firstBoard = kanban.boards[0];
    newCard.value = {
      board_id: firstBoard?.id || '',
      stage_id: firstBoard?.stages[0]?.id || '',
    };
  } finally {
    isLoading.value = false;
  }
};

watch(displayId, load, { immediate: true });

watch(
  () => newCard.value.board_id,
  boardId => {
    newCard.value.stage_id = stagesOf(boardId)[0]?.id || '';
  }
);

// Card changes made anywhere (the board, another agent) that touch this conversation or
// its contact refresh the panel.
watch(
  () => kanban.lastCardEvent,
  event => {
    if (!event) return;
    const { card } = event;
    const known = [...linked.value, ...contactCards.value].some(
      item => item.id === card.id
    );
    const touches =
      known ||
      card.contact?.id === props.contactId ||
      card.conversations?.some(c => c.display_id === displayId.value);
    if (touches) fetchCards();
  }
);

const run = async (cardId, action) => {
  busyCardId.value = cardId;
  try {
    await action();
    await fetchCards();
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));
  } finally {
    busyCardId.value = null;
  }
};

const changeStage = (card, stageId) =>
  run(card.id, async () => {
    const { data } = await FlowKanbanAPI.moveCard(card.id, { stageId });
    kanban.upsertCard(data.payload);
  });

const link = card =>
  run(card.id, () => kanban.linkConversation(card.id, displayId.value));

const unlink = card =>
  run(card.id, () => kanban.unlinkConversation(card.id, displayId.value));

const openBoard = async card => {
  await router.push(boardPath());
  kanban.selectBoard(card.board.id);
};

const create = async () => {
  isCreating.value = true;
  try {
    await kanban.createCard({
      stage_id: newCard.value.stage_id,
      conversation_id: displayId.value,
    });
    await fetchCards();
    useAlert(t('FLOW_KANBAN.CARD_FORM.CREATED'));
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));
  } finally {
    isCreating.value = false;
  }
};

const stageOptionsFor = card =>
  stagesOf(card.board.id).map(stage => ({
    value: stage.id,
    label: stage.name,
  }));
</script>

<template>
  <div class="flex flex-col gap-4 px-2 pb-2">
    <div v-if="isLoading" class="flex justify-center py-4">
      <Spinner :size="20" />
    </div>

    <template v-else>
      <section class="flex flex-col gap-2">
        <h5 class="text-label-small text-n-slate-11">
          {{ t('FLOW_KANBAN.PANEL.LINKED') }}
        </h5>
        <p v-if="!linked.length" class="text-body-main text-n-slate-11">
          {{ t('FLOW_KANBAN.PANEL.NONE') }}
        </p>
        <article
          v-for="card in linked"
          :key="card.id"
          class="flex flex-col gap-2 p-2.5 rounded-lg outline outline-1 outline-n-container bg-n-solid-1"
          :class="{ 'opacity-60': busyCardId === card.id }"
        >
          <div class="flex items-start gap-2">
            <div class="flex flex-col flex-1 min-w-0">
              <span class="text-heading-3 truncate text-n-slate-12">
                {{ card.title }}
              </span>
              <span class="text-label-small truncate text-n-slate-11">
                {{ card.board.name }}
              </span>
            </div>
            <Button
              v-tooltip.top="t('FLOW_KANBAN.PANEL.OPEN_BOARD')"
              ghost
              slate
              xs
              icon="i-lucide-columns-3"
              :aria-label="t('FLOW_KANBAN.PANEL.OPEN_BOARD')"
              @click="openBoard(card)"
            />
            <Button
              v-tooltip.top="t('FLOW_KANBAN.PANEL.UNLINK')"
              ghost
              slate
              xs
              icon="i-lucide-unlink"
              :aria-label="t('FLOW_KANBAN.PANEL.UNLINK')"
              :disabled="busyCardId === card.id"
              @click="unlink(card)"
            />
          </div>
          <div class="flex items-center gap-2">
            <span
              class="flex-shrink-0 rounded-full size-2.5"
              :style="{ backgroundColor: card.stage.color }"
            />
            <RequiredComboBox
              :model-value="card.stage_id"
              :options="stageOptionsFor(card)"
              :disabled="busyCardId === card.id"
              @update:model-value="changeStage(card, $event)"
            />
          </div>
        </article>
      </section>

      <section v-if="contactCards.length" class="flex flex-col gap-2">
        <h5 class="text-label-small text-n-slate-11">
          {{ t('FLOW_KANBAN.PANEL.CONTACT_CARDS') }}
        </h5>
        <div
          v-for="card in contactCards"
          :key="card.id"
          class="flex items-center gap-2 px-2.5 py-2 rounded-lg bg-n-alpha-1"
        >
          <span
            class="flex-shrink-0 rounded-full size-2.5"
            :style="{ backgroundColor: card.stage.color }"
          />
          <div class="flex flex-col flex-1 min-w-0">
            <span class="text-body-main truncate text-n-slate-12">{{
              card.title
            }}</span>
            <span class="text-label-small truncate text-n-slate-11">
              {{ card.board.name }} · {{ card.stage.name }}
            </span>
          </div>
          <Button
            faded
            slate
            xs
            icon="i-lucide-link"
            :label="t('FLOW_KANBAN.PANEL.LINK')"
            :is-loading="busyCardId === card.id"
            @click="link(card)"
          />
        </div>
      </section>

      <section class="flex flex-col gap-2 pt-3 border-t border-n-weak">
        <h5 class="text-label-small text-n-slate-11">
          {{ t('FLOW_KANBAN.PANEL.CREATE_IN') }}
        </h5>
        <p v-if="!kanban.boards.length" class="text-body-main text-n-slate-11">
          {{ t('FLOW_KANBAN.PANEL.NO_BOARDS') }}
        </p>
        <template v-else>
          <div class="grid grid-cols-2 gap-2">
            <RequiredComboBox
              v-model="newCard.board_id"
              :options="boardOptions"
            />
            <RequiredComboBox
              v-model="newCard.stage_id"
              :options="newCardStageOptions"
            />
          </div>
          <Button
            faded
            blue
            sm
            icon="i-lucide-plus"
            :label="t('FLOW_KANBAN.PANEL.CREATE')"
            :is-loading="isCreating"
            :disabled="!newCard.stage_id || isCreating"
            @click="create"
          />
        </template>
      </section>
    </template>
  </div>
</template>
