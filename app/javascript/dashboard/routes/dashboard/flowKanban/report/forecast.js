// The label of a forecast row: a fixed word for the three that are not months, and the month name
// ("outubro de 2026") for "YYYY-MM", written in the viewer's language.
const SPECIAL_ROWS = ['overdue', 'later', 'no_date'];

// Intl writes months in lower case in Portuguese and Spanish: only the first letter is a capital.
export const upperFirst = text => text.charAt(0).toUpperCase() + text.slice(1);

export const forecastRowLabel = (key, locale, word) => {
  if (SPECIAL_ROWS.includes(key)) return word(key);
  const [year, month] = key.split('-').map(Number);
  // The 15th, so no time zone can move the date into the neighbouring month.
  return upperFirst(
    new Intl.DateTimeFormat(String(locale || 'en').replace('_', '-'), {
      month: 'long',
      year: 'numeric',
    }).format(new Date(year, month - 1, 15))
  );
};

// How much of the open pipeline the forecast can see: it is only as good as the dates on the deals.
export const forecastCoverage = forecast => ({
  withDate: forecast.with_date_count,
  total: forecast.open_count,
  partial:
    forecast.open_count > 0 && forecast.with_date_count < forecast.open_count,
});
