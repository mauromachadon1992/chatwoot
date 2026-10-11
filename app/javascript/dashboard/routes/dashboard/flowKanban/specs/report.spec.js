import { getUnixTime } from 'date-fns';
import { periodRange, DEFAULT_PERIOD } from '../report/useFlowKanbanReport';

describe('periodRange', () => {
  // Wednesday 15 October 2026, 14:30 local time.
  const now = new Date(2026, 9, 15, 14, 30);
  const at = (...args) => getUnixTime(new Date(...args));

  it('counts the last days including today, from local midnight', () => {
    expect(periodRange('LAST_7', now)).toEqual([
      at(2026, 9, 9),
      at(2026, 9, 15, 14, 30),
    ]);
    expect(periodRange('LAST_30', now)[0]).toBe(at(2026, 8, 16));
  });

  it('covers whole calendar months and the year so far', () => {
    expect(periodRange('THIS_MONTH', now)[0]).toBe(at(2026, 9, 1));
    expect(periodRange('LAST_MONTH', now)).toEqual([
      at(2026, 8, 1),
      at(2026, 8, 30, 23, 59, 59, 999),
    ]);
    expect(periodRange('THIS_YEAR', now)[0]).toBe(at(2026, 0, 1));
  });

  it('falls back to the default period for an unknown one', () => {
    expect(periodRange('NOPE', now)).toEqual(periodRange(DEFAULT_PERIOD, now));
  });
});
