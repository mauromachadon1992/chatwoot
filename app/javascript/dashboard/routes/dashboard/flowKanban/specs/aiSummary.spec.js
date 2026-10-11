import {
  DESCRIPTION_MAX,
  appendToDescription,
  canRetry,
  canSchedule,
  dueInput,
  errorKind,
  errorMessage,
  fitsDescription,
  usedNote,
} from '../aiSummary';

const failure = (status, data) => ({ response: { status, data } });

describe('errorKind and errorMessage', () => {
  it('uses the code the server gave, or says failed for an answer without one', () => {
    expect(errorKind(failure(429, { code: 'rate_limited' }))).toBe(
      'rate_limited'
    );
    expect(errorKind(failure(500, {}))).toBe('failed');
  });

  it('says network when there was no answer at all', () => {
    expect(errorKind(new Error('Network Error'))).toBe('network');
  });

  it('shows the server’s sentence, or ours when it sent none', () => {
    const t = key => key;
    expect(
      errorMessage(failure(422, { code: 'x', error: 'Sem mensagens.' }), t)
    ).toBe('Sem mensagens.');
    expect(errorMessage(new Error('x'), t)).toBe(
      'FLOW_KANBAN.AI.ERRORS.NETWORK'
    );
  });

  it('offers a retry only when asking again may help', () => {
    expect(canRetry(failure(502, { code: 'failed' }))).toBe(true);
    expect(canRetry(new Error('offline'))).toBe(true);
    [
      'nothing_to_summarize',
      'not_configured',
      'rate_limited',
      'disabled',
      'quota',
    ].forEach(code => expect(canRetry(failure(400, { code }))).toBe(false));
  });
});

describe('dueInput', () => {
  const now = new Date(2026, 9, 7, 14, 30);

  it('is 9:00 on the day for a number of days', () => {
    expect(dueInput(2, now)).toBe('2026-10-09T09:00');
    expect(dueInput('1', now)).toBe('2026-10-08T09:00');
  });

  it('is in an hour for today', () => {
    expect(dueInput(0, now)).toBe('2026-10-07T15:00');
  });
});

describe('appendToDescription', () => {
  it('adds the summary under what is there, or alone', () => {
    expect(appendToDescription('Cliente antigo.  ', ' Resumo. ')).toBe(
      'Cliente antigo.\n\nResumo.'
    );
    expect(appendToDescription('', 'Resumo.')).toBe('Resumo.');
    expect(appendToDescription(null, 'Resumo.')).toBe('Resumo.');
  });

  it('says whether the result still fits the description', () => {
    expect(fitsDescription('a', 'b')).toBe(true);
    expect(fitsDescription('a'.repeat(DESCRIPTION_MAX), 'b')).toBe(false);
  });
});

describe('usedNote', () => {
  it('says how much was read, and when only part of it was', () => {
    expect(
      usedNote({ conversations: 2, messages: 48, truncated: false })
    ).toMatchObject({ key: 'USED', count: 48 });
    expect(
      usedNote({ conversations: 1, messages: 9, truncated: true }).key
    ).toBe('USED_PARTIAL');
  });
});

describe('canSchedule', () => {
  it('needs a suggestion with a title', () => {
    expect(canSchedule({ title: 'Ligar' })).toBe(true);
    expect(canSchedule({ title: '  ' })).toBe(false);
    expect(canSchedule(null)).toBe(false);
  });
});
