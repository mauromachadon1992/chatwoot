import { ref, toValue, watch } from 'vue';
import {
  endOfMonth,
  getUnixTime,
  startOfDay,
  startOfMonth,
  startOfYear,
  subDays,
  subMonths,
} from 'date-fns';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

// Periods are computed in the agent's own time zone and sent as unix timestamps.
export const PERIODS = {
  LAST_7: now => [startOfDay(subDays(now, 6)), now],
  LAST_30: now => [startOfDay(subDays(now, 29)), now],
  LAST_90: now => [startOfDay(subDays(now, 89)), now],
  THIS_MONTH: now => [startOfMonth(now), now],
  LAST_MONTH: now => {
    const previous = subMonths(now, 1);
    return [startOfMonth(previous), endOfMonth(previous)];
  },
  THIS_YEAR: now => [startOfYear(now), now],
};

export const DEFAULT_PERIOD = 'LAST_30';

export const periodRange = (period, now = new Date()) =>
  (PERIODS[period] || PERIODS[DEFAULT_PERIOD])(now).map(getUnixTime);

// Loads a board's report and reloads it whenever the board, period or assignee (refs or
// getters) change. A response that arrives after a newer request is dropped.
export function useFlowKanbanReport({ boardId, period, assigneeId }) {
  const report = ref(null);
  const isLoading = ref(false);
  const hasError = ref(false);
  let latest = 0;

  const load = async () => {
    const board = toValue(boardId);
    if (!board) return;
    latest += 1;
    const request = latest;
    const [since, until] = periodRange(toValue(period));
    isLoading.value = true;
    hasError.value = false;
    try {
      const { data } = await FlowKanbanAPI.getReport(board, {
        since,
        until,
        assigneeId: toValue(assigneeId) || undefined,
      });
      if (request === latest) report.value = data.payload;
    } catch {
      if (request === latest) hasError.value = true;
    } finally {
      if (request === latest) isLoading.value = false;
    }
  };

  watch(() => [toValue(boardId), toValue(period), toValue(assigneeId)], load, {
    immediate: true,
  });

  return { report, isLoading, hasError, load };
}
