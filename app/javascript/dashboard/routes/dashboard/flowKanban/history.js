import { describeResults } from './automations';

// Mirrors Custom::Kanban::CardEvent::KINDS. Each event becomes an icon and a sentence; the
// sentence names who did it, or says a rule or the system did.
const KINDS = {
  created: { icon: 'i-lucide-plus' },
  stage_moved: { icon: 'i-lucide-arrow-right-left' },
  value_changed: { icon: 'i-lucide-circle-dollar-sign' },
  assignee_changed: { icon: 'i-lucide-user-round' },
  task_created: { icon: 'i-lucide-list-plus' },
  task_completed: { icon: 'i-lucide-list-checks' },
  conversation_linked: { icon: 'i-lucide-link' },
  quote_prepared: { icon: 'i-lucide-file-text' },
  task_reopened: { icon: 'i-lucide-rotate-ccw' },
  automation_ran: { icon: 'i-lucide-zap' },
};

// The i18n key (FLOW_KANBAN.HISTORY.*) for an event: the variant depends on what the data holds.
const keyFor = ({ kind, data }) => {
  if (kind === 'created')
    return data.source === 'automatic' ? 'CREATED_AUTOMATIC' : 'CREATED';
  if (kind === 'stage_moved') {
    if (data.stage_type === 'lost')
      return data.lost_reason ? 'LOST_WITH_REASON' : 'LOST';
    return 'MOVED';
  }
  if (kind === 'assignee_changed')
    return data.to_name ? 'ASSIGNED' : 'UNASSIGNED';
  return kind.toUpperCase();
};

// What a History row needs: icon, the key and its parameters, and the line under it.
// `money` formats cents in the account currency; `t` writes what a rule did.
export const describeEvent = (event, money, t) => {
  const data = event.data || {};
  return {
    icon: (KINDS[event.kind] || KINDS.created).icon,
    key: `FLOW_KANBAN.HISTORY.${keyFor(event)}`,
    params: {
      stage: data.to_stage_name || data.stage_name,
      from: data.from_stage_name,
      reason: data.lost_reason,
      assignee: data.to_name,
      task: data.title,
      conversation: data.display_id,
      fromValue: money(data.from_cents ?? 0),
      toValue: money(data.to_cents ?? data.total_cents ?? 0),
      results:
        event.kind === 'automation_ran' ? describeResults(data.results, t) : '',
    },
    note: data.lost_note || null,
    actor: event.user?.name || null,
    byRule: Boolean(data.by_rule) || event.kind === 'automation_ran',
    stageDeleted: Boolean(data.stage_deleted),
  };
};

// Day headings for the list, in the viewer's own day: events arrive newest first. Written in
// sentence case ("Quarta-feira, 7 de outubro"), as Intl writes it lower case.
export const groupByDay = (events, locale) => {
  const format = new Intl.DateTimeFormat(
    String(locale || 'en').replace('_', '-'),
    { weekday: 'long', day: 'numeric', month: 'long' }
  );
  return events.reduce((groups, event) => {
    const formatted = format.format(new Date(event.created_at * 1000));
    const label = formatted.charAt(0).toUpperCase() + formatted.slice(1);
    const last = groups[groups.length - 1];
    if (last?.label === label) last.events.push(event);
    else groups.push({ label, events: [event] });
    return groups;
  }, []);
};
