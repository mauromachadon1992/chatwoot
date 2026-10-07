import { badgeLabel, describeNotification, UNREAD_CAP } from '../notifications';

const notification = (kind, data = {}) => ({ kind, data, card_id: 1 });

describe('describeNotification', () => {
  it('names the person when one handed the task or the deal over, and not when none did', () => {
    expect(
      describeNotification(notification('task_assigned', { actor_name: 'Ana' }))
        .titleKey
    ).toBe('FLOW_KANBAN.NOTIFICATIONS.KINDS.TASK_ASSIGNED_BY');
    expect(describeNotification(notification('task_assigned')).titleKey).toBe(
      'FLOW_KANBAN.NOTIFICATIONS.KINDS.TASK_ASSIGNED'
    );
    expect(
      describeNotification(notification('card_assigned', { actor_name: 'Ana' }))
        .titleKey
    ).toBe('FLOW_KANBAN.NOTIFICATIONS.KINDS.CARD_ASSIGNED_BY');
  });

  it('marks the task kinds, which show the task above the deal', () => {
    const kinds = ['task_due', 'task_overdue', 'task_assigned'];
    kinds.forEach(kind =>
      expect(describeNotification(notification(kind)).isTask).toBe(true)
    );
    expect(describeNotification(notification('card_moved')).isTask).toBe(false);
  });

  it('keeps colour for states the title already names', () => {
    expect(describeNotification(notification('task_overdue')).toneClass).toBe(
      'text-n-ruby-11'
    );
    expect(describeNotification(notification('task_due')).toneClass).toBe(
      'text-n-amber-11'
    );
    expect(describeNotification(notification('card_assigned')).toneClass).toBe(
      'text-n-slate-11'
    );
  });

  it('gives a deal an automation sent to Won or Lost that stage’s tone', () => {
    const moved = type =>
      describeNotification(
        notification('card_moved', { stage_type: type, stage_name: 'X' })
      ).toneClass;

    expect(moved('won')).toBe('text-n-teal-11');
    expect(moved('lost')).toBe('text-n-ruby-11');
    expect(moved('open')).toBe('text-n-slate-11');
  });

  it('falls back to a plain deal notification for a kind it does not know yet', () => {
    expect(describeNotification(notification('something_new')).icon).toBe(
      'i-lucide-user-plus'
    );
  });
});

describe('badgeLabel', () => {
  it('caps the count so the badge keeps its width', () => {
    expect(badgeLabel(3)).toBe('3');
    expect(badgeLabel(UNREAD_CAP)).toBe('99');
    expect(badgeLabel(UNREAD_CAP + 1)).toBe('99+');
  });
});
