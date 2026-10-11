// Keyboard model of a tab list (WAI-ARIA tabs, automatic activation): the arrow keys move along the
// row (mirrored in a right-to-left layout), Home and End jump to the ends. The index to focus and
// select, or null for any other key.
export const nextTabIndex = (key, current, count, rtl = false) => {
  if (!count) return null;
  const forward = rtl ? 'ArrowLeft' : 'ArrowRight';
  const back = rtl ? 'ArrowRight' : 'ArrowLeft';
  if (key === forward || key === 'ArrowDown') return (current + 1) % count;
  if (key === back || key === 'ArrowUp') return (current - 1 + count) % count;
  if (key === 'Home') return 0;
  if (key === 'End') return count - 1;
  return null;
};

// The ids that tie a tab to its panel (aria-controls / aria-labelledby).
export const tabId = (prefix, id) => `${prefix}-tab-${id}`;
export const panelId = (prefix, id) => `${prefix}-panel-${id}`;

// A count worth a pill: zero, absent or not a number shows nothing.
export const tabCount = value =>
  Number.isFinite(value) && value > 0 ? value : null;

// The tabs the card panel offers, in order, with the numbers that tell what is behind each one.
export const cardTabs = (card, t) => [
  { id: 'details', label: t('FLOW_KANBAN.CARD_FORM.TABS.DETAILS') },
  {
    id: 'value',
    label: t('FLOW_KANBAN.CARD_FORM.TABS.VALUE'),
    count: tabCount(card?.items_count),
  },
  {
    id: 'tasks',
    label: t('FLOW_KANBAN.CARD_FORM.TABS.TASKS'),
    count: tabCount(card?.tasks?.open),
  },
  {
    id: 'conversations',
    label: t('FLOW_KANBAN.CARD_FORM.TABS.CONVERSATIONS'),
    count: tabCount(card?.conversations?.length),
  },
  { id: 'history', label: t('FLOW_KANBAN.CARD_FORM.TABS.HISTORY') },
];
