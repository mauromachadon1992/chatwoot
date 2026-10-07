import {
  defaultDueInput,
  dueInputToISO,
  dueState,
  toDateTimeInput,
} from '../tasks';

const NOW = new Date(2026, 9, 7, 14, 30);
const at = (day, hour) =>
  Math.floor(new Date(2026, 9, day, hour).getTime() / 1000);

describe('dueState', () => {
  it('calls an open task past its time overdue', () => {
    expect(dueState({ due_at: at(7, 9) }, NOW)).toBe('overdue');
  });

  it('calls an open task later today, today, and one on another day, later', () => {
    expect(dueState({ due_at: at(7, 18) }, NOW)).toBe('today');
    expect(dueState({ due_at: at(8, 9) }, NOW)).toBe('later');
  });

  it('is done once completed, however late it was', () => {
    expect(dueState({ due_at: at(1, 9), completed_at: at(2, 9) }, NOW)).toBe(
      'done'
    );
  });
});

describe('due date inputs', () => {
  it('writes a datetime-local value in local time', () => {
    expect(toDateTimeInput(new Date(2026, 0, 5, 7, 3))).toBe(
      '2026-01-05T07:03'
    );
  });

  it('defaults to tomorrow at 9:00, across a month end', () => {
    expect(defaultDueInput(new Date(2026, 9, 31, 22, 15))).toBe(
      '2026-11-01T09:00'
    );
  });

  it('sends the instant, not the wall clock, and nothing when empty', () => {
    expect(dueInputToISO('2026-10-08T09:00')).toBe(
      new Date(2026, 9, 8, 9).toISOString()
    );
    expect(dueInputToISO('')).toBeNull();
  });
});
