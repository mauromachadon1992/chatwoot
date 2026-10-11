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

// A due state worth naming, as a StatePill: tone, icon and the word (FLOW_KANBAN.TASKS.*).
// Later and done dates are plain text.
export const DUE_PILLS = {
  overdue: { tone: 'ruby', icon: 'i-lucide-alarm-clock', key: 'OVERDUE' },
  today: { tone: 'amber', icon: 'i-lucide-clock', key: 'TODAY' },
};

// "Wed, 8 Oct, 09:00" in the dashboard's language (pt_BR → pt-BR for Intl).
export const formatDue = (seconds, locale) =>
  new Intl.DateTimeFormat(String(locale || 'en').replace('_', '-'), {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(seconds * 1000));

// 'done' | 'overdue' | 'today' | 'later', for the colour and the wording of a due date.
export const dueState = (task, now = new Date()) => {
  if (task.completed_at) return 'done';
  const due = new Date(task.due_at * 1000);
  if (due < now) return 'overdue';
  return due.toDateString() === now.toDateString() ? 'today' : 'later';
};

// The last instant of the viewer's day, which the server needs to count "today".
export const endOfLocalDay = (now = new Date()) => {
  const end = new Date(now);
  end.setHours(23, 59, 59, 999);
  return end;
};

// My tasks: open tasks split by the viewer's own day, each group keeping the server's order.
export const groupOpenTasks = (tasks, now = new Date()) => {
  const groups = { overdue: [], today: [], upcoming: [] };
  tasks.forEach(task => {
    const state = dueState(task, now);
    if (state === 'overdue') groups.overdue.push(task);
    else if (state === 'today') groups.today.push(task);
    else if (state === 'later') groups.upcoming.push(task);
  });
  return groups;
};
