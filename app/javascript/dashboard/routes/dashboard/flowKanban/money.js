// Deal values travel as integer minor units (cents), so sums are exact; these helpers turn
// them into the account's currency for display and turn what an agent types back into cents.

const intlLocale = locale => (locale || 'en').replace('_', '-');

export const formatMoney = (
  cents,
  { currency = 'BRL', locale = 'en', whole = false } = {}
) =>
  new Intl.NumberFormat(intlLocale(locale), {
    style: 'currency',
    currency,
    minimumFractionDigits: whole ? 0 : 2,
    maximumFractionDigits: whole ? 0 : 2,
  }).format((Number(cents) || 0) / 100);

// The number alone, as an agent would type it back ("1234,56" in pt_BR, "1234.56" in en).
export const formatPlainMoney = (cents, locale = 'en') =>
  new Intl.NumberFormat(intlLocale(locale), {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
    useGrouping: false,
  }).format((Number(cents) || 0) / 100);

export const currencySymbol = (currency = 'BRL', locale = 'en') =>
  new Intl.NumberFormat(intlLocale(locale), { style: 'currency', currency })
    .formatToParts(0)
    .find(part => part.type === 'currency')?.value || currency;

// The last "," or "." followed by up to `decimals` digits at the end is the decimal mark;
// every other one groups thousands. "1.234,5", "1,234.50" and "1234" all read as expected.
const readDecimal = (text, decimals) => {
  const cleaned = String(text ?? '')
    .replace(/[^\d.,-]/g, '')
    .trim();
  if (!/\d/.test(cleaned)) return null;
  const negative = cleaned.startsWith('-');
  const match = cleaned.match(new RegExp(`[.,](\\d{1,${decimals}})$`));
  const fraction = match ? match[1] : '';
  const integer = (match ? cleaned.slice(0, match.index) : cleaned).replace(
    /\D/g,
    ''
  );
  const value = Number(`${integer || '0'}.${fraction || '0'}`);
  return negative ? -value : value;
};

export const parseMoney = text => {
  const value = readDecimal(text, 2);
  return value === null ? null : Math.round(value * 100);
};

// Quantities keep up to three decimals (2,5 m³; 0,125 t).
export const parseQuantity = text => {
  const value = readDecimal(text, 3);
  return value === null ? null : Math.round(value * 1000) / 1000;
};

export const formatQuantity = (quantity, locale = 'en') =>
  new Intl.NumberFormat(intlLocale(locale), {
    maximumFractionDigits: 3,
  }).format(Number(quantity) || 0);

export const formatPercent = (value, locale = 'en') =>
  new Intl.NumberFormat(intlLocale(locale), {
    style: 'percent',
    maximumFractionDigits: 1,
  }).format((Number(value) || 0) / 100);
