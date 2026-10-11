import {
  canSave,
  errorKey,
  isValidUrl,
  statusView,
  summarizeEvents,
  urlProblem,
} from '../webhooks';

describe('isValidUrl', () => {
  it('takes a full https address and nothing else', () => {
    expect(isValidUrl('https://hooks.example.com/flow')).toBe(true);
    expect(isValidUrl('  https://hooks.example.com  ')).toBe(true);
    [
      'http://hooks.example.com',
      'ftp://hooks.example.com',
      'hooks.example.com',
      'https://',
      'https://user:pass@hooks.example.com',
      '',
    ].forEach(bad => expect(isValidUrl(bad)).toBe(false));
  });

  it('refuses an address longer than the server accepts', () => {
    expect(isValidUrl(`https://example.com/${'a'.repeat(2048)}`)).toBe(false);
  });

  it('says why: empty, or not https', () => {
    expect(urlProblem('  ')).toBe('empty');
    expect(urlProblem('http://example.com')).toBe('https');
    expect(urlProblem('https://example.com')).toBeNull();
  });
});

describe('canSave', () => {
  it('needs a valid address and at least one event', () => {
    const url = 'https://example.com';
    expect(canSave({ url, events: ['deal.won'] })).toBe(true);
    expect(canSave({ url, events: [] })).toBe(false);
    expect(canSave({ url: 'http://x', events: ['deal.won'] })).toBe(false);
  });
});

describe('statusView', () => {
  it('gives each status a tone, an icon and a word key', () => {
    expect(statusView({ status: 'success' })).toMatchObject({
      tone: 'teal',
      key: 'SUCCESS',
    });
    expect(statusView({ status: 'failed' })).toMatchObject({
      tone: 'ruby',
      key: 'FAILED',
    });
    expect(statusView({ status: 'retrying' })).toMatchObject({
      tone: 'amber',
      key: 'RETRYING',
    });
    expect(statusView(null)).toMatchObject({ tone: 'slate', key: 'NONE' });
  });

  it('never leaves a state with only a colour', () => {
    ['success', 'failed', 'retrying', 'pending', undefined].forEach(status => {
      const view = statusView(status && { status });
      expect(view.icon).toMatch(/^i-lucide-/);
      expect(view.key).toBeTruthy();
    });
  });
});

describe('summarizeEvents', () => {
  const name = event => event.toUpperCase();

  it('names the first two events and counts the rest', () => {
    expect(summarizeEvents(['a', 'b', 'c', 'd'], name)).toEqual({
      text: 'A, B',
      rest: 2,
    });
    expect(summarizeEvents(['a'], name)).toEqual({ text: 'A', rest: 0 });
  });
});

describe('errorKey', () => {
  it('translates the server’s own reasons and leaves free text alone', () => {
    expect(errorKey('blocked_address')).toBe('BLOCKED_ADDRESS');
    expect(errorKey('unresolved_host')).toBe('UNRESOLVED_HOST');
    expect(errorKey('webhook_off')).toBe('WEBHOOK_OFF');
    expect(errorKey('HTTP 500')).toBeNull();
    expect(errorKey(null)).toBeNull();
  });
});
