import {
  formatMoney,
  parseMoney,
  parseQuantity,
  formatQuantity,
  formatPercent,
  currencySymbol,
} from '../money';

// Intl separates the symbol with a non-breaking space; compare on plain spaces.
const plain = text => text.replace(/\s/g, ' ');

describe('money', () => {
  it('formats cents in the account currency and the agent locale', () => {
    expect(
      plain(formatMoney(123456, { currency: 'BRL', locale: 'pt_BR' }))
    ).toBe('R$ 1.234,56');
    expect(formatMoney(123456, { currency: 'USD', locale: 'en' })).toBe(
      '$1,234.56'
    );
    expect(
      plain(
        formatMoney(123456, { currency: 'BRL', locale: 'pt_BR', whole: true })
      )
    ).toBe('R$ 1.235');
  });

  it('names the currency symbol', () => {
    expect(currencySymbol('BRL', 'pt_BR')).toBe('R$');
    expect(currencySymbol('EUR', 'en')).toBe('€');
  });

  it('reads money typed with either decimal mark', () => {
    expect(parseMoney('1.234,56')).toBe(123456);
    expect(parseMoney('1,234.56')).toBe(123456);
    expect(parseMoney('R$ 1.234')).toBe(123400);
    expect(parseMoney('1234,5')).toBe(123450);
    expect(parseMoney('39,90')).toBe(3990);
    expect(parseMoney('')).toBeNull();
    expect(parseMoney('abc')).toBeNull();
  });

  it('reads quantities with up to three decimals', () => {
    expect(parseQuantity('2,5')).toBe(2.5);
    expect(parseQuantity('0,125')).toBe(0.125);
    expect(parseQuantity('1.000')).toBe(1);
    expect(parseQuantity('10')).toBe(10);
    expect(formatQuantity('2.500', 'pt_BR')).toBe('2,5');
  });

  it('formats rates the API sends as percentages', () => {
    expect(formatPercent(66.7, 'pt_BR')).toBe('66,7%');
    expect(formatPercent(100, 'en')).toBe('100%');
  });
});
