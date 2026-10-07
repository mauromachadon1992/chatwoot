// Mirrors Custom::Kanban::CardTask::TASK_TYPES.
export const TASK_TYPES = ['call', 'meeting', 'email', 'follow_up', 'custom'];

export const TASK_TYPE_ICONS = {
  call: 'i-lucide-phone',
  meeting: 'i-lucide-users',
  email: 'i-lucide-mail',
  follow_up: 'i-lucide-repeat',
  custom: 'i-lucide-list-checks',
};

const pad = number => String(number).padStart(2, '0');

// The value of an <input type="datetime-local">, in the browser's own time zone.
export const toDateTimeInput = date =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;

// Tomorrow at 9:00: a follow-up is rarely meant for the minute it is written.
export const defaultDueInput = (now = new Date()) => {
  const due = new Date(now);
  due.setDate(due.getDate() + 1);
  due.setHours(9, 0, 0, 0);
  return toDateTimeInput(due);
};

export const dueInputToISO = value =>
  value ? new Date(value).toISOString() : null;

// 'done' | 'overdue' | 'today' | 'later', for the colour and the wording of a due date.
export const dueState = (task, now = new Date()) => {
  if (task.completed_at) return 'done';
  const due = new Date(task.due_at * 1000);
  if (due < now) return 'overdue';
  return due.toDateString() === now.toDateString() ? 'today' : 'later';
};
