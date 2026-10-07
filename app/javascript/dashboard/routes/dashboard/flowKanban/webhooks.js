// The logic of the Webhooks section in Settings → Kanban. Pure, so it is tested without a screen.

// Mirrors Custom::Kanban::Webhook::EVENTS (the server also sends the list in `meta.events`).
export const EVENTS = [
  'deal.created',
  'deal.moved',
  'deal.won',
  'deal.lost',
  'deal.value_changed',
  'task.created',
];

export const URL_MAX_LENGTH = 2048;

// The same rule the server applies: a full https address with no user:password.
export const isValidUrl = value => {
  try {
    const url = new URL(String(value).trim());
    return (
      url.protocol === 'https:' &&
      Boolean(url.hostname) &&
      !url.username &&
      !url.password &&
      String(value).trim().length <= URL_MAX_LENGTH
    );
  } catch {
    return false;
  }
};

export const urlProblem = value => {
  if (!String(value).trim()) return 'empty';
  return isValidUrl(value) ? null : 'https';
};

export const canSave = ({ url, events }) =>
  isValidUrl(url) && events.length > 0;

// Delivery status as a state said three ways (tone, icon, word), see DESIGN.md.
const STATUS_VIEWS = {
  success: { tone: 'teal', icon: 'i-lucide-check', key: 'SUCCESS' },
  failed: { tone: 'ruby', icon: 'i-lucide-x', key: 'FAILED' },
  retrying: { tone: 'amber', icon: 'i-lucide-rotate-cw', key: 'RETRYING' },
  pending: { tone: 'slate', icon: 'i-lucide-clock', key: 'PENDING' },
};

export const statusView = delivery =>
  delivery
    ? STATUS_VIEWS[delivery.status] || STATUS_VIEWS.pending
    : { tone: 'slate', icon: 'i-lucide-minus', key: 'NONE' };

// "Deal created, Deal won +2": the first two names and how many more.
export const summarizeEvents = (events, name, limit = 2) => {
  const shown = events.slice(0, limit).map(name);
  const rest = events.length - shown.length;
  return { text: shown.join(', '), rest };
};

// What the server says went wrong with a delivery, in words a person can act on.
export const errorKey = error => {
  if (!error) return null;
  if (error === 'blocked_address') return 'BLOCKED_ADDRESS';
  if (error === 'unresolved_host') return 'UNRESOLVED_HOST';
  if (error === 'webhook_off') return 'WEBHOOK_OFF';
  return null;
};
