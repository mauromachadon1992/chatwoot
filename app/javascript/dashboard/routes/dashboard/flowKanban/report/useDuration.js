import { useI18n } from 'vue-i18n';

// Seconds as the report reads them: days with one decimal from a day up, whole hours below.
export function useDuration() {
  const { t, locale } = useI18n();

  const duration = seconds => {
    const days = seconds / 86400;
    if (days >= 1) {
      const rounded = Math.round(days * 10) / 10;
      const n = new Intl.NumberFormat(locale.value.replace('_', '-'), {
        maximumFractionDigits: 1,
      }).format(rounded);
      return t(
        'FLOW_KANBAN.REPORT.DURATION.DAYS',
        { n },
        rounded === 1 ? 1 : 2
      );
    }
    const hours = Math.round(seconds / 3600);
    if (hours < 1) return t('FLOW_KANBAN.REPORT.DURATION.LESS_THAN_HOUR');
    return t('FLOW_KANBAN.REPORT.DURATION.HOURS', { n: hours });
  };

  return { duration };
}
