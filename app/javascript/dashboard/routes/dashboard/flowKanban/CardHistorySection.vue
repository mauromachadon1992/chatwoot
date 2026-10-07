<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import FlowKanbanAPI from 'dashboard/api/flowKanban';
import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SkeletonRows from './SkeletonRows.vue';
import { describeEvent, groupByDay } from './history';
import { useFlowKanban } from './useFlowKanban';

// What happened to the deal, newest first, grouped by day. Collapsed to the latest few, with the
// rest a click away. It follows the card: a change made anywhere puts a new line on top.
const props = defineProps({
  card: { type: Object, required: true },
});

const COLLAPSED = 5;

const { t, locale } = useI18n();
const kanban = useFlowKanbanStore();
const { money } = useFlowKanban();

const events = ref([]);
const page = ref(1);
const hasMore = ref(false);
const isLoading = ref(true);
const isLoadingMore = ref(false);
const hasError = ref(false);
const expanded = ref(false);

const shown = computed(() =>
  expanded.value ? events.value : events.value.slice(0, COLLAPSED)
);
const groups = computed(() => groupByDay(shown.value, locale.value));
const hiddenCount = computed(() =>
  Math.max(events.value.length - COLLAPSED, 0)
);
const rowOf = event => ({ event, view: describeEvent(event, money, t) });

const load = async ({ quiet = false } = {}) => {
  if (!quiet) isLoading.value = true;
  hasError.value = false;
  const cardId = props.card.id;
  try {
    const { data } = await FlowKanbanAPI.getCardEvents(cardId);
    if (props.card.id !== cardId) return;
    events.value = data.payload;
    page.value = 1;
    hasMore.value = data.meta.has_more;
  } catch {
    if (!quiet) hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const loadMore = async () => {
  isLoadingMore.value = true;
  try {
    const { data } = await FlowKanbanAPI.getCardEvents(props.card.id, {
      page: page.value + 1,
    });
    const known = new Set(events.value.map(event => event.id));
    events.value = [
      ...events.value,
      ...data.payload.filter(event => !known.has(event.id)),
    ];
    page.value += 1;
    hasMore.value = data.meta.has_more;
  } catch {
    hasError.value = true;
  } finally {
    isLoadingMore.value = false;
  }
};

const showAll = async () => {
  expanded.value = true;
  if (hasMore.value && events.value.length <= COLLAPSED) await loadMore();
};

// A card event from the server (any change to this deal) refreshes the list quietly.
watch(
  () => kanban.lastCardEvent,
  event => {
    if (event?.card?.id === props.card.id) load({ quiet: true });
  }
);
watch(
  () => props.card.id,
  () => {
    expanded.value = false;
    load();
  }
);

onMounted(load);
</script>

<template>
  <section class="flex flex-col gap-3">
    <h4 class="text-heading-3 text-n-slate-12">
      {{ t('FLOW_KANBAN.HISTORY.SECTION') }}
    </h4>

    <SkeletonRows v-if="isLoading" :rows="3" />

    <div v-else-if="hasError && !events.length" class="flex items-center gap-3">
      <p class="text-body-main text-n-slate-11">
        {{ t('FLOW_KANBAN.HISTORY.ERROR') }}
      </p>
      <Button
        link
        blue
        sm
        type="button"
        :label="t('FLOW_KANBAN.HISTORY.RETRY')"
        @click="load()"
      />
    </div>

    <template v-else>
      <div
        v-for="group in groups"
        :key="group.label"
        class="flex flex-col gap-2"
      >
        <h5 class="text-label-small text-n-slate-11">
          {{ group.label }}
        </h5>
        <ol class="flex flex-col gap-3">
          <li
            v-for="row in group.events.map(rowOf)"
            :key="row.event.id"
            class="flex items-start gap-3"
          >
            <span
              class="flex items-center justify-center flex-shrink-0 rounded-lg size-7 bg-n-alpha-2 text-n-slate-11"
            >
              <Icon :icon="row.view.icon" class="size-4" />
            </span>
            <div class="flex flex-col flex-1 min-w-0 gap-0.5">
              <p class="text-body-main text-n-slate-12">
                {{ t(row.view.key, row.view.params) }}
              </p>
              <p v-if="row.view.note" class="text-label-small text-n-slate-11">
                {{ t('FLOW_KANBAN.HISTORY.NOTE', { note: row.view.note }) }}
              </p>
              <p
                class="flex flex-wrap items-center gap-x-1 text-label-small text-n-slate-10"
              >
                <Avatar
                  v-if="row.event.user"
                  :src="row.event.user.thumbnail"
                  :name="row.event.user.name"
                  :size="14"
                  rounded-full
                />
                <span>
                  {{
                    row.view.actor ||
                    (row.view.byRule
                      ? t('FLOW_KANBAN.HISTORY.BY_RULE')
                      : t('FLOW_KANBAN.HISTORY.BY_SYSTEM'))
                  }}
                </span>
                <span aria-hidden="true">·</span>
                <time class="tabular-nums">
                  {{
                    new Intl.DateTimeFormat(locale.replace('_', '-'), {
                      hour: '2-digit',
                      minute: '2-digit',
                    }).format(new Date(row.event.created_at * 1000))
                  }}
                </time>
              </p>
            </div>
          </li>
        </ol>
      </div>

      <Button
        v-if="!expanded && (hiddenCount > 0 || hasMore)"
        faded
        slate
        sm
        type="button"
        class="self-start"
        :label="t('FLOW_KANBAN.HISTORY.SHOW_ALL')"
        @click="showAll"
      />
      <Button
        v-else-if="expanded && hasMore"
        faded
        slate
        sm
        type="button"
        class="self-start"
        :label="t('FLOW_KANBAN.HISTORY.LOAD_MORE')"
        :is-loading="isLoadingMore"
        @click="loadMore"
      />
    </template>
  </section>
</template>
