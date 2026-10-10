<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import {
  ATTRIBUTES_MAX,
  PRIORITIES,
  blankRow,
  detailsProblems,
} from './proFields';

// The deal's priority, start and due time, labels and free attributes: what the fazer.ai agents read
// and write on a deal, edited here by hand. The parent owns the form and saves it with the card.
const details = defineModel('details', { type: Object, required: true });

const { t } = useI18n();
const accountLabels = useMapGetter('labels/getLabels');

const problems = computed(() => detailsProblems(details.value));
const priorityOptions = computed(() => [
  { value: '', label: t('FLOW_KANBAN.DETAILS.NO_PRIORITY') },
  ...PRIORITIES.map(priority => ({
    value: priority,
    label: t(`FLOW_KANBAN.DETAILS.PRIORITIES.${priority.toUpperCase()}`),
  })),
]);
// The account's labels, and any the deal already carries that the account does not list (an agent
// may have typed it): a label on the deal is never hidden from the picker.
const labelOptions = computed(() => {
  const titles = accountLabels.value.map(label => label.title);
  const extra = details.value.labels.filter(label => !titles.includes(label));
  return [...titles, ...extra].map(title => ({ value: title, label: title }));
});
const canAddRow = computed(() => details.value.rows.length < ATTRIBUTES_MAX);

const addRow = () => {
  if (canAddRow.value) details.value.rows.push(blankRow());
};
const removeRow = index => details.value.rows.splice(index, 1);
const problemText = key => t(`FLOW_KANBAN.DETAILS.PROBLEMS.${key}`);
</script>

<template>
  <section class="flex flex-col gap-4" aria-labelledby="flow-details-title">
    <h4 id="flow-details-title" class="text-heading-3 text-n-slate-12">
      {{ t('FLOW_KANBAN.DETAILS.SECTION') }}
    </h4>

    <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
      {{ t('FLOW_KANBAN.DETAILS.PRIORITY') }}
      <ComboBox v-model="details.priority" :options="priorityOptions" />
    </label>

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <Input
        v-model="details.start_at"
        type="datetime-local"
        :label="t('FLOW_KANBAN.DETAILS.START')"
        :message-type="problems.dates ? 'error' : 'info'"
      />
      <Input
        v-model="details.due_at"
        type="datetime-local"
        :label="t('FLOW_KANBAN.DETAILS.DUE')"
        :message="problems.dates ? problemText(problems.dates) : ''"
        :message-type="problems.dates ? 'error' : 'info'"
      />
    </div>

    <div class="flex flex-col gap-1.5">
      <label class="flex flex-col gap-1.5 text-label text-n-slate-12">
        {{ t('FLOW_KANBAN.DETAILS.LABELS') }}
        <TagMultiSelectComboBox
          v-model="details.labels"
          :options="labelOptions"
          :placeholder="t('FLOW_KANBAN.DETAILS.LABELS_PLACEHOLDER')"
        />
      </label>
      <p
        v-for="problem in problems.labels"
        :key="problem"
        role="alert"
        class="text-label-small text-n-ruby-11"
      >
        {{ problemText(problem) }}
      </p>
    </div>

    <fieldset class="flex flex-col gap-3 p-0 m-0 border-0 min-w-0">
      <legend class="mb-1 text-label text-n-slate-12">
        {{ t('FLOW_KANBAN.DETAILS.ATTRIBUTES') }}
      </legend>
      <p class="text-label-small text-n-slate-11">
        {{ t('FLOW_KANBAN.DETAILS.ATTRIBUTES_HINT') }}
      </p>
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="(row, index) in details.rows"
          :key="index"
          class="flex items-start gap-2"
        >
          <Input
            v-model="row.key"
            class="flex-1 min-w-0"
            size="sm"
            :placeholder="t('FLOW_KANBAN.DETAILS.ATTRIBUTE_NAME')"
            :aria-label="t('FLOW_KANBAN.DETAILS.ATTRIBUTE_NAME')"
          />
          <Input
            v-model="row.value"
            class="flex-1 min-w-0"
            size="sm"
            :disabled="!row.editable"
            :placeholder="t('FLOW_KANBAN.DETAILS.ATTRIBUTE_VALUE')"
            :aria-label="t('FLOW_KANBAN.DETAILS.ATTRIBUTE_VALUE')"
            :title="
              row.editable ? undefined : t('FLOW_KANBAN.DETAILS.READ_ONLY')
            "
          />
          <Button
            ghost
            slate
            sm
            type="button"
            icon="i-lucide-x"
            :aria-label="t('FLOW_KANBAN.DETAILS.REMOVE_ATTRIBUTE')"
            @click="removeRow(index)"
          />
        </li>
      </ul>
      <p
        v-for="problem in problems.attributes"
        :key="problem"
        role="alert"
        class="text-label-small text-n-ruby-11"
      >
        {{ problemText(problem) }}
      </p>
      <Button
        faded
        slate
        sm
        type="button"
        class="self-start"
        icon="i-lucide-plus"
        :label="t('FLOW_KANBAN.DETAILS.ADD_ATTRIBUTE')"
        :disabled="!canAddRow"
        @click="addRow"
      />
    </fieldset>
  </section>
</template>
