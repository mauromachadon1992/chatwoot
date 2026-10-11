// The logic of the AI summary in the card panel. Pure, so it is tested without a screen.
import { toDateTimeInput } from './tasks';

// Mirrors Custom::Kanban::DealSummaryService.
export const SUMMARY_MAX = 4000;
export const DESCRIPTION_MAX = 5000;

// What the server said went wrong, as a key of FLOW_KANBAN.AI.ERRORS.* (the server's own words
// are shown when it sent them; these cover a missing answer, such as no network).
export const errorKind = error => {
  const code = error?.response?.data?.code;
  if (code) return code;
  return error?.response ? 'failed' : 'network';
};

// The message to show: the server's (already in the account's language), or ours.
export const errorMessage = (error, t) =>
  error?.response?.data?.error ||
  t(`FLOW_KANBAN.AI.ERRORS.${errorKind(error).toUpperCase()}`);

// A retry helps when the failure may pass; asking again after "no messages" or "not set up" does not.
export const canRetry = error =>
  ['failed', 'network'].includes(errorKind(error));

// The datetime-local value for "in N days": 9:00 on that day, or in an hour for "today".
export const dueInput = (days, now = new Date()) => {
  const due = new Date(now);
  if (Number(days) > 0) {
    due.setDate(due.getDate() + Number(days));
    due.setHours(9, 0, 0, 0);
  } else {
    due.setHours(due.getHours() + 1, 0, 0, 0);
  }
  return toDateTimeInput(due);
};

// The summary added under what the description already says, or alone when it is empty.
export const appendToDescription = (description, summary) => {
  const current = String(description || '').trimEnd();
  const added = String(summary || '').trim();
  return current ? `${current}\n\n${added}` : added;
};

export const fitsDescription = (description, summary) =>
  appendToDescription(description, summary).length <= DESCRIPTION_MAX;

// What the draft is based on, said in a sentence (FLOW_KANBAN.AI.USED / USED_PARTIAL).
export const usedNote = used => ({
  key: used.truncated ? 'USED_PARTIAL' : 'USED',
  count: used.messages,
  params: { conversations: used.conversations, messages: used.messages },
});

// A suggestion the agent can still schedule: it has a title.
export const canSchedule = task => Boolean(task && String(task.title).trim());
