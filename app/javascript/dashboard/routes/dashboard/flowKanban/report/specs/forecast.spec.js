import { forecastCoverage, forecastRowLabel, upperFirst } from '../forecast';

const word = key =>
  ({ overdue: 'Data já passou', later: 'Depois', no_date: 'Sem data' })[key];

describe('forecastRowLabel', () => {
  it('writes a month with only its first letter in capitals, as Portuguese does', () => {
    expect(forecastRowLabel('2026-10', 'pt_BR', word)).toBe('Outubro de 2026');
    expect(forecastRowLabel('2027-02', 'pt_BR', word)).toBe(
      'Fevereiro de 2027'
    );
  });

  it('writes it in the language of the dashboard', () => {
    expect(forecastRowLabel('2026-10', 'en', word)).toBe('October 2026');
    expect(forecastRowLabel('2026-10', 'es', word)).toBe('Octubre de 2026');
  });

  it('uses the fixed words for the rows that are not months', () => {
    expect(forecastRowLabel('overdue', 'pt_BR', word)).toBe('Data já passou');
    expect(forecastRowLabel('later', 'pt_BR', word)).toBe('Depois');
    expect(forecastRowLabel('no_date', 'pt_BR', word)).toBe('Sem data');
  });

  it('does not move December into January or the reverse', () => {
    expect(forecastRowLabel('2026-12', 'en', word)).toBe('December 2026');
    expect(forecastRowLabel('2027-01', 'en', word)).toBe('January 2027');
  });
});

describe('upperFirst', () => {
  it('capitalises the first letter and leaves the rest alone', () => {
    expect(upperFirst('quarta-feira, 7 de outubro')).toBe(
      'Quarta-feira, 7 de outubro'
    );
    expect(upperFirst('')).toBe('');
  });
});

describe('forecastCoverage', () => {
  it('is partial only when some open deals lack a date', () => {
    expect(forecastCoverage({ open_count: 5, with_date_count: 3 })).toEqual({
      withDate: 3,
      total: 5,
      partial: true,
    });
    expect(
      forecastCoverage({ open_count: 5, with_date_count: 5 }).partial
    ).toBe(false);
    expect(
      forecastCoverage({ open_count: 0, with_date_count: 0 }).partial
    ).toBe(false);
  });
});
