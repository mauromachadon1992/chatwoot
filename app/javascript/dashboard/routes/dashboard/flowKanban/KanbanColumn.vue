<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useIntersectionObserver } from '@vueuse/core';
import Draggable from 'vuedraggable';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import KanbanCard from './KanbanCard.vue';
import { useFlowKanban } from './useFlowKanban';

const props = defineProps({
  stage: { type: Object, required: true },
  column: { type: Object, required: true },
});

const emit = defineEmits(['open', 'add', 'move', 'loadMore']);

const { t } = useI18n();
const { cardFields, money } = useFlowKanban();

const showTotalValue = computed(
  () => cardFields.value.has('value') && props.column.totalValue > 0
);

const STAGE_TYPE_ICONS = {
  won: 'i-lucide-circle-check',
  lost: 'i-lucide-circle-x',
};

const hasMore = computed(() => props.column.cards.length < props.column.total);

// Loads the next page as the agent scrolls near the end of the column.
const sentinel = ref(null);
useIntersectionObserver(sentinel, ([entry]) => {
  if (entry?.isIntersecting && hasMore.value) emit('loadMore', props.stage.id);
});

// vuedraggable reports a drop into this column as `added` (from another column) or
// `moved` (within it). The card still carries its old stage_id at this point.
const onChange = event => {
  const change = event.added || event.moved;
  if (!change) return;
  emit('move', {
    card: change.element,
    fromStageId: change.element.stage_id,
    toStageId: props.stage.id,
    newIndex: change.newIndex,
  });
};
</script>

<template>
  <section
    class="flex flex-col flex-shrink-0 w-72 max-h-full rounded-xl bg-n-alpha-1"
    :aria-label="stage.name"
  >
    <header
      class="grid grid-cols-[auto_minmax(0,1fr)] items-center gap-x-2 px-3 pt-3 pb-2"
    >
      <span
        class="flex-shrink-0 rounded-full size-2.5"
        :style="{ backgroundColor: stage.color }"
      />
      <div class="flex items-center min-w-0 gap-2">
        <h3 class="min-w-0 text-heading-3 truncate text-n-slate-12">
          {{ stage.name }}
        </h3>
        <Icon
          v-if="STAGE_TYPE_ICONS[stage.stage_type]"
          v-tooltip.top="
            t(
              `FLOW_KANBAN.BOARD_FORM.STAGE_TYPES.${stage.stage_type.toUpperCase()}`
            )
          "
          :icon="STAGE_TYPE_ICONS[stage.stage_type]"
          class="flex-shrink-0 size-4"
          :class="
            stage.stage_type === 'won' ? 'text-n-teal-11' : 'text-n-ruby-11'
          "
        />
        <span
          class="px-1.5 text-label-small rounded-md tabular-nums bg-n-alpha-2 text-n-slate-11"
        >
          {{ column.total }}
        </span>
        <Button
          v-tooltip.top="t('FLOW_KANBAN.COLUMN.ADD_CARD')"
          ghost
          slate
          xs
          icon="i-lucide-plus"
          class="ms-auto"
          :aria-label="t('FLOW_KANBAN.COLUMN.ADD_CARD')"
          @click="emit('add', stage)"
        />
      </div>
      <p
        v-if="showTotalValue"
        v-tooltip.bottom="t('FLOW_KANBAN.COLUMN.TOTAL_VALUE')"
        class="col-start-2 text-label-small tabular-nums text-n-slate-11 w-fit"
      >
        <span class="sr-only">{{ t('FLOW_KANBAN.COLUMN.TOTAL_VALUE') }}</span>
        {{ money(column.totalValue, { whole: true }) }}
      </p>
    </header>

    <div class="flex-1 min-h-0 px-2 pb-2 overflow-y-auto">
      <Draggable
        :list="column.cards"
        group="flow-kanban-cards"
        item-key="id"
        ghost-class="opacity-40"
        :animation="150"
        class="flex flex-col gap-2 min-h-24"
        @change="onChange"
      >
        <template #item="{ element }">
          <KanbanCard :card="element" @open="emit('open', $event)" />
        </template>
        <template #footer>
          <div
            v-if="!column.cards.length"
            class="flex items-center justify-center h-24 text-label-small text-center border border-dashed rounded-lg border-n-slate-6 text-n-slate-10"
          >
            {{ t('FLOW_KANBAN.EMPTY.COLUMN') }}
          </div>
          <div
            v-if="hasMore"
            ref="sentinel"
            class="flex items-center justify-center h-10"
          >
            <Spinner v-if="column.isLoading" :size="16" />
          </div>
        </template>
      </Draggable>
    </div>
  </section>
</template>
