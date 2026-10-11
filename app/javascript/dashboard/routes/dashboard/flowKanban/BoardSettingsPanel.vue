<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useDebounceFn } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';

import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import RequiredComboBox from './RequiredComboBox.vue';
import BoardAutomationsSection from './BoardAutomationsSection.vue';
import BoardAutoCreateSection from './BoardAutoCreateSection.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import { STAGE_COLORS, useFlowKanban } from './useFlowKanban';

const { t } = useI18n();
const kanban = useFlowKanbanStore();
const { hasFeature } = useFlowKanban();
const inboxes = useMapGetter('inboxes/getInboxes');
const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getAgents');

const panelRef = ref(null);
const deleteBoardDialogRef = ref(null);
const deleteStageDialogRef = ref(null);

const boardId = ref(null);
const form = ref({
  name: '',
  description: '',
  inbox_ids: [],
  team_ids: [],
  agent_ids: [],
});
const stages = ref([]);
const colorPickerFor = ref(null);
const stageToDelete = ref(null);
const moveToStageId = ref('');
const isSaving = ref(false);
const isDeleting = ref(false);

const isCreating = computed(() => !boardId.value);
const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
);
const agentOptions = computed(() =>
  agents.value.map(agent => ({ value: agent.id, label: agent.name }))
);
const teamOptions = computed(() =>
  teams.value.map(team => ({ value: team.id, label: team.name }))
);
const STAGE_TYPE_STYLES = {
  open: { icon: 'i-lucide-circle-dot', color: 'blue' },
  won: { icon: 'i-lucide-circle-check', color: 'teal' },
  lost: { icon: 'i-lucide-circle-x', color: 'ruby' },
};
const stageTypeOptions = computed(() =>
  Object.entries(STAGE_TYPE_STYLES).map(([type, style]) => ({
    value: type,
    label: t(`FLOW_KANBAN.BOARD_FORM.STAGE_TYPES.${type.toUpperCase()}`),
    ...style,
  }))
);
const stageToDeleteHasCards = computed(
  () => (kanban.columns[stageToDelete.value?.id]?.total || 0) > 0
);
const moveTargetOptions = computed(() =>
  stages.value
    .filter(stage => stage.id !== stageToDelete.value?.id)
    .map(stage => ({ value: stage.id, label: stage.name }))
);

const loadStages = () => {
  const board = kanban.boards.find(item => item.id === boardId.value);
  stages.value = (board?.stages || []).map(stage => ({
    ...stage,
    staleDraft: stage.stale_after_days ? String(stage.stale_after_days) : '',
    staleInvalid: false,
    chanceDraft: stage.win_probability ?? '',
    chanceInvalid: false,
    descriptionDraft: stage.description || '',
  }));
};

const open = board => {
  boardId.value = board?.id || null;
  form.value = {
    name: board?.name || '',
    description: board?.description || '',
    inbox_ids: [...(board?.inbox_ids || [])],
    team_ids: [...(board?.team_ids || [])],
    agent_ids: [...(board?.agent_ids || [])],
  };
  colorPickerFor.value = null;
  loadStages();
  panelRef.value?.open();
};

const withFeedback = async (action, successKey) => {
  try {
    await action();
    if (successKey) useAlert(t(successKey));
    return true;
  } catch (error) {
    useAlert(parseAPIErrorResponse(error) || t('FLOW_KANBAN.ERRORS.GENERIC'));
    return false;
  }
};

const saveBoard = async () => {
  if (!form.value.name.trim()) return;
  isSaving.value = true;
  const payload = { ...form.value, name: form.value.name.trim() };
  const saved = await withFeedback(
    async () => {
      if (isCreating.value) {
        const board = await kanban.createBoard(payload);
        boardId.value = board.id;
        loadStages();
      } else {
        await kanban.updateBoard(boardId.value, payload);
      }
    },
    isCreating.value
      ? 'FLOW_KANBAN.BOARD_FORM.CREATED'
      : 'FLOW_KANBAN.BOARD_FORM.SAVED'
  );
  isSaving.value = false;
  if (saved && !isCreating.value) panelRef.value?.close();
};

// Stage edits are saved as they happen; the panel says so under the list.
const saveStage = async (stage, changes) => {
  Object.assign(stage, changes);
  await withFeedback(async () => {
    await kanban.updateStage(stage.id, changes);
  });
  loadStages();
};

// A short note on what the stage means (at most 120 characters); empty clears it.
const DESCRIPTION_MAX = 120;
const commitDescription = stage => {
  const text = String(stage.descriptionDraft ?? '').trim();
  if (text.length > DESCRIPTION_MAX || text === (stage.description || ''))
    return;
  saveStage(stage, { description: text });
};

// Days a deal may stay in an open stage before it counts as stalled; empty means no alert.
const STALE_MIN = 1;
const STALE_MAX = 365;
const commitStaleLimit = stage => {
  const text = String(stage.staleDraft ?? '').trim();
  const value = text === '' ? null : Number(text);
  stage.staleInvalid =
    value !== null &&
    (!Number.isInteger(value) || value < STALE_MIN || value > STALE_MAX);
  if (stage.staleInvalid || value === (stage.stale_after_days ?? null)) return;
  saveStage(stage, { stale_after_days: value });
};

// The chance a deal in an open stage is won, 0 to 100, for the forecast; empty means the default.
const CHANCE_MAX = 100;
const commitWinChance = stage => {
  const text = String(stage.chanceDraft ?? '').trim();
  const value = text === '' ? null : Number(text);
  stage.chanceInvalid =
    value !== null &&
    (!Number.isInteger(value) || value < 0 || value > CHANCE_MAX);
  if (stage.chanceInvalid || value === (stage.win_probability ?? null)) return;
  saveStage(stage, { win_probability: value });
};

// InlineInput edits stage.name in place; an empty or unchanged name puts the saved one back.
const renameStage = stage => {
  const saved = kanban.stages.find(s => s.id === stage.id)?.name;
  const name = stage.name.trim();
  if (!name || name === saved) {
    stage.name = saved;
    return;
  }
  saveStage(stage, { name });
};

// The picker reports every step of a drag: preview at once, save once the hand rests.
const saveColor = useDebounceFn(
  (stage, color) => saveStage(stage, { color }),
  400
);
const pickColor = (stage, color) => {
  stage.color = color;
  saveColor(stage, color);
};

const addStage = async () => {
  await withFeedback(async () => {
    await kanban.createStage({
      name: t('FLOW_KANBAN.BOARD_FORM.NEW_STAGE'),
      color: STAGE_COLORS[stages.value.length % STAGE_COLORS.length],
    });
  });
  loadStages();
};

const reorderStages = async () => {
  await withFeedback(async () => {
    await kanban.reorderStages(stages.value.map(stage => stage.id));
  });
  loadStages();
};

const askDeleteStage = stage => {
  stageToDelete.value = stage;
  moveToStageId.value = moveTargetOptions.value[0]?.value || '';
  deleteStageDialogRef.value?.open();
};

const confirmDeleteStage = async () => {
  isDeleting.value = true;
  const deleted = await withFeedback(async () => {
    await kanban.deleteStage(
      stageToDelete.value.id,
      stageToDeleteHasCards.value ? moveToStageId.value : undefined
    );
  });
  isDeleting.value = false;
  if (deleted) deleteStageDialogRef.value?.close();
  loadStages();
};

const confirmDeleteBoard = async () => {
  isDeleting.value = true;
  const deleted = await withFeedback(
    () => kanban.deleteBoard(boardId.value),
    'FLOW_KANBAN.BOARD_FORM.DELETED'
  );
  isDeleting.value = false;
  if (!deleted) return;
  deleteBoardDialogRef.value?.close();
  panelRef.value?.close();
};

defineExpose({ open });
</script>

<template>
  <SidePanel
    ref="panelRef"
    :title="
      isCreating
        ? t('FLOW_KANBAN.BOARD_FORM.CREATE_TITLE')
        : t('FLOW_KANBAN.BOARD_FORM.EDIT_TITLE')
    "
    width="lg"
  >
    <form class="flex flex-col gap-8" @submit.prevent="saveBoard">
      <div class="flex flex-col gap-4">
        <Input
          v-model="form.name"
          :label="t('FLOW_KANBAN.BOARD_FORM.NAME')"
          :placeholder="t('FLOW_KANBAN.BOARD_FORM.NAME_PLACEHOLDER')"
          autofocus
        />
        <Input
          v-model="form.description"
          :label="t('FLOW_KANBAN.BOARD_FORM.DESCRIPTION')"
        />
      </div>

      <section class="flex flex-col gap-3">
        <div class="flex flex-col gap-1">
          <h4 class="text-heading-3 text-n-slate-12">
            {{ t('FLOW_KANBAN.BOARD_FORM.VISIBILITY') }}
          </h4>
          <p class="text-label-small text-n-slate-11">
            {{ t('FLOW_KANBAN.BOARD_FORM.VISIBILITY_HINT') }}
          </p>
        </div>
        <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.BOARD_FORM.INBOXES') }}
          <TagMultiSelectComboBox
            v-model="form.inbox_ids"
            :options="inboxOptions"
            :placeholder="t('FLOW_KANBAN.BOARD_FORM.INBOXES_PLACEHOLDER')"
          />
        </label>
        <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.BOARD_FORM.TEAMS') }}
          <TagMultiSelectComboBox
            v-model="form.team_ids"
            :options="teamOptions"
            :placeholder="t('FLOW_KANBAN.BOARD_FORM.TEAMS_PLACEHOLDER')"
          />
        </label>
        <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
          {{ t('FLOW_KANBAN.BOARD_FORM.AGENTS') }}
          <TagMultiSelectComboBox
            v-model="form.agent_ids"
            :options="agentOptions"
            :placeholder="t('FLOW_KANBAN.BOARD_FORM.AGENTS_PLACEHOLDER')"
          />
        </label>
      </section>

      <p v-if="isCreating" class="text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.BOARD_FORM.DEFAULT_STAGES_HINT') }}
      </p>
      <section v-else class="flex flex-col gap-3">
        <div class="flex flex-col gap-1">
          <h4 class="text-heading-3 text-n-slate-12">
            {{ t('FLOW_KANBAN.BOARD_FORM.STAGES') }}
          </h4>
          <p class="text-label-small text-n-slate-11">
            {{ t('FLOW_KANBAN.BOARD_FORM.STAGES_HINT') }}
          </p>
        </div>
        <Draggable
          v-model="stages"
          item-key="id"
          handle=".drag-handle"
          ghost-class="opacity-40"
          :animation="150"
          class="flex flex-col gap-2"
          @end="reorderStages"
        >
          <template #item="{ element: stage }">
            <div
              class="flex flex-col gap-2 p-2 rounded-lg outline outline-1 outline-n-container bg-n-solid-1"
            >
              <div class="flex items-center gap-2">
                <Button
                  v-tooltip.top="t('FLOW_KANBAN.BOARD_FORM.DRAG_STAGE')"
                  ghost
                  slate
                  xs
                  type="button"
                  icon="i-lucide-grip-vertical"
                  class="drag-handle cursor-grab active:cursor-grabbing"
                  :aria-label="t('FLOW_KANBAN.BOARD_FORM.DRAG_STAGE')"
                />
                <Button
                  v-tooltip.top="t('FLOW_KANBAN.BOARD_FORM.STAGE_COLOR')"
                  ghost
                  slate
                  xs
                  type="button"
                  :aria-label="t('FLOW_KANBAN.BOARD_FORM.STAGE_COLOR')"
                  :aria-expanded="colorPickerFor === stage.id"
                  @click="
                    colorPickerFor =
                      colorPickerFor === stage.id ? null : stage.id
                  "
                >
                  <span
                    class="rounded-full size-3.5"
                    :style="{ backgroundColor: stage.color }"
                  />
                </Button>
                <InlineInput
                  v-model="stage.name"
                  :placeholder="t('FLOW_KANBAN.BOARD_FORM.STAGE_NAME')"
                  :max-length="80"
                  class="flex-1 min-w-0 px-2 py-1 rounded-md hover:bg-n-alpha-1 focus-within:bg-n-alpha-2"
                  @blur="renameStage(stage)"
                  @enter-press="renameStage(stage)"
                />
                <ButtonGroup
                  role="radiogroup"
                  :aria-label="t('FLOW_KANBAN.BOARD_FORM.STAGE_TYPE')"
                  class="flex items-center gap-0.5 p-0.5 rounded-lg bg-n-alpha-1"
                >
                  <Button
                    v-for="option in stageTypeOptions"
                    :key="option.value"
                    v-tooltip.top="option.label"
                    ghost
                    xs
                    type="button"
                    role="radio"
                    :aria-checked="stage.stage_type === option.value"
                    :aria-label="option.label"
                    :icon="option.icon"
                    :color="
                      stage.stage_type === option.value ? option.color : 'slate'
                    "
                    :class="{
                      'bg-n-solid-1 shadow-sm':
                        stage.stage_type === option.value,
                    }"
                    @click="
                      stage.stage_type !== option.value &&
                        saveStage(stage, { stage_type: option.value })
                    "
                  />
                </ButtonGroup>
                <Button
                  v-tooltip.top="t('FLOW_KANBAN.BOARD_FORM.DELETE_STAGE')"
                  ghost
                  slate
                  xs
                  type="button"
                  icon="i-lucide-trash-2"
                  :disabled="stages.length <= 1"
                  :aria-label="t('FLOW_KANBAN.BOARD_FORM.DELETE_STAGE')"
                  @click="askDeleteStage(stage)"
                />
              </div>
              <div class="ps-9">
                <Input
                  v-model="stage.descriptionDraft"
                  size="sm"
                  :maxlength="String(DESCRIPTION_MAX)"
                  :placeholder="t('FLOW_KANBAN.BOARD_FORM.STAGE_DESCRIPTION')"
                  :aria-label="t('FLOW_KANBAN.BOARD_FORM.STAGE_DESCRIPTION')"
                  @blur="commitDescription(stage)"
                  @keydown.enter.prevent="commitDescription(stage)"
                />
              </div>
              <div v-if="colorPickerFor === stage.id" class="ps-9">
                <ColorPicker
                  :model-value="stage.color"
                  @update:model-value="pickColor(stage, $event)"
                />
              </div>
              <div
                v-if="stage.stage_type === 'open'"
                class="flex flex-wrap items-center gap-x-4 gap-y-2 ps-9"
              >
                <div class="flex flex-wrap items-center gap-2">
                  <Icon
                    icon="i-lucide-percent"
                    class="flex-shrink-0 size-3.5 text-n-slate-10"
                  />
                  <label
                    :for="`flow-chance-${stage.id}`"
                    class="text-label-small text-n-slate-11"
                  >
                    {{ t('FLOW_KANBAN.BOARD_FORM.CHANCE_LABEL') }}
                  </label>
                  <Input
                    :id="`flow-chance-${stage.id}`"
                    v-model="stage.chanceDraft"
                    type="number"
                    min="0"
                    max="100"
                    size="sm"
                    class="w-20"
                    :placeholder="String(stage.effective_probability)"
                    :message-type="stage.chanceInvalid ? 'error' : 'info'"
                    @blur="commitWinChance(stage)"
                    @keydown.enter.prevent="commitWinChance(stage)"
                  />
                  <span class="text-label-small text-n-slate-11">%</span>
                  <span
                    v-if="stage.chanceInvalid"
                    role="alert"
                    class="w-full text-label-small text-n-ruby-11"
                  >
                    {{ t('FLOW_KANBAN.BOARD_FORM.CHANCE_INVALID') }}
                  </span>
                </div>
              </div>
              <div
                v-if="hasFeature('stale_alerts') && stage.stage_type === 'open'"
                class="flex flex-wrap items-center gap-2 ps-9"
              >
                <Icon
                  icon="i-lucide-hourglass"
                  class="flex-shrink-0 size-3.5 text-n-slate-10"
                />
                <label
                  :for="`flow-stale-${stage.id}`"
                  class="text-label-small text-n-slate-11"
                >
                  {{ t('FLOW_KANBAN.BOARD_FORM.STALE_LABEL') }}
                </label>
                <Input
                  :id="`flow-stale-${stage.id}`"
                  v-model="stage.staleDraft"
                  type="number"
                  :min="String(STALE_MIN)"
                  :max="String(STALE_MAX)"
                  size="sm"
                  class="w-20"
                  :placeholder="t('FLOW_KANBAN.BOARD_FORM.STALE_NONE')"
                  :message-type="stage.staleInvalid ? 'error' : 'info'"
                  @blur="commitStaleLimit(stage)"
                  @keydown.enter.prevent="commitStaleLimit(stage)"
                />
                <span class="text-label-small text-n-slate-11">
                  {{ t('FLOW_KANBAN.BOARD_FORM.STALE_DAYS') }}
                </span>
                <span
                  v-if="stage.staleInvalid"
                  role="alert"
                  class="w-full text-label-small text-n-ruby-11"
                >
                  {{ t('FLOW_KANBAN.BOARD_FORM.STALE_INVALID') }}
                </span>
              </div>
            </div>
          </template>
        </Draggable>
        <Button
          type="button"
          faded
          slate
          sm
          icon="i-lucide-plus"
          :label="t('FLOW_KANBAN.BOARD_FORM.ADD_STAGE')"
          class="self-start"
          @click="addStage"
        />
        <p class="text-label-small text-n-slate-11">
          {{ t('FLOW_KANBAN.BOARD_FORM.STAGES_AUTOSAVE') }}
        </p>
      </section>

      <BoardAutoCreateSection
        v-if="!isCreating && hasFeature('auto_create')"
        :board-id="boardId"
      />

      <BoardAutomationsSection
        v-if="!isCreating"
        :board-id="boardId"
        :stages="stages"
      />
    </form>

    <template #footer>
      <div class="flex items-center justify-between gap-3">
        <Button
          v-if="!isCreating"
          ghost
          ruby
          sm
          icon="i-lucide-trash-2"
          :label="t('FLOW_KANBAN.BOARD_FORM.DELETE')"
          @click="deleteBoardDialogRef?.open()"
        />
        <Button
          solid
          blue
          sm
          class="ms-auto"
          :label="
            isCreating
              ? t('FLOW_KANBAN.BOARD_FORM.CREATE')
              : t('FLOW_KANBAN.BOARD_FORM.SAVE')
          "
          :is-loading="isSaving"
          :disabled="!form.name.trim() || isSaving"
          @click="saveBoard"
        />
      </div>
    </template>
  </SidePanel>

  <Dialog
    ref="deleteBoardDialogRef"
    type="alert"
    :title="t('FLOW_KANBAN.BOARD_FORM.DELETE')"
    :description="
      t('FLOW_KANBAN.BOARD_FORM.DELETE_CONFIRM', { name: form.name })
    "
    :confirm-button-label="t('FLOW_KANBAN.BOARD_FORM.DELETE')"
    :is-loading="isDeleting"
    @confirm="confirmDeleteBoard"
  />

  <Dialog
    ref="deleteStageDialogRef"
    type="alert"
    :title="t('FLOW_KANBAN.BOARD_FORM.DELETE_STAGE')"
    :confirm-button-label="t('FLOW_KANBAN.BOARD_FORM.DELETE_STAGE_CONFIRM')"
    :is-loading="isDeleting"
    @confirm="confirmDeleteStage"
  >
    <label v-if="stageToDeleteHasCards" class="flex flex-col gap-1">
      <span class="text-body-main text-n-slate-11">
        {{ t('FLOW_KANBAN.BOARD_FORM.DELETE_STAGE_MOVE_TO') }}
      </span>
      <RequiredComboBox v-model="moveToStageId" :options="moveTargetOptions" />
    </label>
    <p v-else class="text-body-main text-n-slate-11">
      {{ t('FLOW_KANBAN.BOARD_FORM.DELETE_STAGE_EMPTY') }}
    </p>
  </Dialog>
</template>
