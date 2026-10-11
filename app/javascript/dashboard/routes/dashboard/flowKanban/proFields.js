// The logic of the card's Pro fields in the panel: priority, dates, labels and attributes. Pure, so it
// is tested without a screen. The limits mirror Custom::Kanban::CardProFields.
import { dueInputToISO, toDateTimeInput } from './tasks';

export const PRIORITIES = ['urgent', 'high', 'medium', 'low'];
export const LABELS_MAX = 20;
export const LABEL_MAX_LENGTH = 50;
export const ATTRIBUTES_MAX = 50;
export const ATTRIBUTE_KEY_MAX_LENGTH = 60;
export const ATTRIBUTES_MAX_BYTES = 10000;

// A priority said three ways (tone, icon, word key), see DESIGN.md.
const PRIORITY_VIEWS = {
  urgent: { tone: 'ruby', icon: 'i-lucide-flame', key: 'URGENT' },
  high: { tone: 'amber', icon: 'i-lucide-arrow-up', key: 'HIGH' },
  medium: { tone: 'blue', icon: 'i-lucide-equal', key: 'MEDIUM' },
  low: { tone: 'slate', icon: 'i-lucide-arrow-down', key: 'LOW' },
};

export const priorityView = priority => PRIORITY_VIEWS[priority] || null;

// --- attributes ------------------------------------------------------------------------------

const isPlain = value =>
  ['string', 'number', 'boolean'].includes(typeof value) || value === null;

// A row per attribute. Text, numbers and booleans can be edited; an object or a list is shown as
// it is and kept untouched (`editable: false`), since a form cannot say what it means.
export const attributeRows = attributes =>
  Object.entries(attributes || {}).map(([key, value]) => ({
    key,
    value: isPlain(value) ? String(value ?? '') : JSON.stringify(value),
    editable: isPlain(value),
    original: value,
  }));

export const blankRow = () => ({
  key: '',
  value: '',
  editable: true,
  original: undefined,
});

// A value typed in a row keeps the kind it had (a number stays a number, true/false a boolean).
const readValue = row => {
  if (!row.editable) return row.original;
  if (typeof row.original === 'number' && row.value.trim() !== '') {
    const number = Number(row.value);
    if (Number.isFinite(number)) return number;
  }
  if (
    typeof row.original === 'boolean' &&
    ['true', 'false'].includes(row.value)
  )
    return row.value === 'true';
  return row.value;
};

export const rowsToAttributes = rows =>
  rows
    .filter(row => row.key.trim() !== '')
    .reduce((attributes, row) => {
      attributes[row.key.trim()] = readValue(row);
      return attributes;
    }, {});

// What is wrong with the rows, as keys (FLOW_KANBAN.DETAILS.PROBLEMS.*), or an empty list.
export const attributeProblems = rows => {
  const problems = [];
  const keys = rows.map(row => row.key.trim()).filter(Boolean);
  if (rows.some(row => row.key.trim() === '' && row.value.trim() !== ''))
    problems.push('KEY_EMPTY');
  if (new Set(keys).size !== keys.length) problems.push('DUPLICATE');
  if (keys.some(key => key.length > ATTRIBUTE_KEY_MAX_LENGTH))
    problems.push('KEY_LONG');
  if (keys.length > ATTRIBUTES_MAX) problems.push('TOO_MANY');
  if (JSON.stringify(rowsToAttributes(rows)).length > ATTRIBUTES_MAX_BYTES)
    problems.push('TOO_BIG');
  return problems;
};

// --- labels ----------------------------------------------------------------------------------

export const normalizeLabels = labels => [
  ...new Set(
    (labels || [])
      .map(label => String(label).replace(/\s+/g, ' ').trim())
      .filter(Boolean)
  ),
];

export const labelProblems = labels => {
  const problems = [];
  if (labels.length > LABELS_MAX) problems.push('LABELS_TOO_MANY');
  if (labels.some(label => label.length > LABEL_MAX_LENGTH))
    problems.push('LABEL_LONG');
  return problems;
};

// --- the form --------------------------------------------------------------------------------

const toInput = iso => (iso ? toDateTimeInput(new Date(iso)) : '');

export const detailsFromCard = card => ({
  priority: card.priority || '',
  start_at: toInput(card.start_at),
  due_at: toInput(card.due_at),
  labels: normalizeLabels(card.labels),
  rows: attributeRows(card.custom_attributes),
});

// What the server takes: empty fields are sent as null, which clears them.
export const detailsPayload = details => ({
  priority: details.priority || null,
  start_at: details.start_at ? dueInputToISO(details.start_at) : null,
  due_at: details.due_at ? dueInputToISO(details.due_at) : null,
  labels: normalizeLabels(details.labels),
  custom_attributes: rowsToAttributes(details.rows),
});

const sameInstant = (isoA, isoB) =>
  (isoA ? new Date(isoA).getTime() : null) ===
  (isoB ? new Date(isoB).getTime() : null);

// Has anything the person can edit changed since the card was loaded?
export const detailsChanged = (details, card) => {
  const payload = detailsPayload(details);
  return (
    payload.priority !== (card.priority || null) ||
    !sameInstant(payload.start_at, card.start_at) ||
    !sameInstant(payload.due_at, card.due_at) ||
    JSON.stringify(payload.labels) !==
      JSON.stringify(normalizeLabels(card.labels)) ||
    JSON.stringify(payload.custom_attributes) !==
      JSON.stringify(card.custom_attributes || {})
  );
};

// Problems by field: the start after the due date, the labels, the attributes.
export const detailsProblems = details => ({
  dates:
    details.start_at && details.due_at && details.start_at > details.due_at
      ? 'DATES_ORDER'
      : null,
  labels: labelProblems(normalizeLabels(details.labels)),
  attributes: attributeProblems(details.rows),
});

export const canSaveDetails = details => {
  const problems = detailsProblems(details);
  return (
    !problems.dates && !problems.labels.length && !problems.attributes.length
  );
};
