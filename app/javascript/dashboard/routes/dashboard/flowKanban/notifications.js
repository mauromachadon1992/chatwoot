// Mirrors Custom::Kanban::Notification::KINDS. Each kind says what it is (icon and words), never
// by colour alone: the tone only reinforces a state the title already names.
const KINDS = {
  task_due: { icon: 'i-lucide-clock', tone: 'amber', task: true },
  task_overdue: { icon: 'i-lucide-alarm-clock', tone: 'ruby', task: true },
  task_assigned: { icon: 'i-lucide-list-plus', tone: 'slate', task: true },
  card_assigned: { icon: 'i-lucide-user-plus', tone: 'slate', task: false },
  card_moved: { icon: 'i-lucide-zap', tone: 'slate', task: false },
};

const TONE_CLASSES = {
  amber: 'text-n-amber-11',
  ruby: 'text-n-ruby-11',
  teal: 'text-n-teal-11',
  slate: 'text-n-slate-11',
};

// A deal an automation sent to Won or Lost is a result, so it takes that stage's tone.
const toneOf = ({ kind, data }) => {
  if (kind === 'card_moved') {
    if (data.stage_type === 'won') return 'teal';
    if (data.stage_type === 'lost') return 'ruby';
  }
  return (KINDS[kind] || KINDS.card_assigned).tone;
};

// What the bell row needs from a notification: icon, tone classes, the i18n key of the title
// with its parameters, and the line under it.
export const describeNotification = notification => {
  const data = notification.data || {};
  const known = KINDS[notification.kind] || KINDS.card_assigned;
  const hasActor = Boolean(data.actor_name);
  const titleKey = `FLOW_KANBAN.NOTIFICATIONS.KINDS.${notification.kind.toUpperCase()}${
    hasActor &&
    (notification.kind === 'task_assigned' ||
      notification.kind === 'card_assigned')
      ? '_BY'
      : ''
  }`;
  return {
    icon: known.icon,
    toneClass: TONE_CLASSES[toneOf({ kind: notification.kind, data })],
    titleKey,
    titleParams: { actor: data.actor_name, stage: data.stage_name },
    isTask: known.task,
    taskTitle: data.task_title,
    cardTitle: data.card_title,
  };
};

export const UNREAD_CAP = 99;

// The number on the bell: capped, so a long absence does not widen the button.
export const badgeLabel = count =>
  count > UNREAD_CAP ? `${UNREAD_CAP}+` : String(count);
