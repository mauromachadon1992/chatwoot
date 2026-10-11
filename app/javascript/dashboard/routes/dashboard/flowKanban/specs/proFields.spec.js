import {
  ATTRIBUTES_MAX,
  LABELS_MAX,
  attributeProblems,
  attributeRows,
  blankRow,
  canSaveDetails,
  detailsChanged,
  detailsFromCard,
  detailsPayload,
  detailsProblems,
  normalizeLabels,
  priorityView,
  rowsToAttributes,
} from '../proFields';

const card = (overrides = {}) => ({
  priority: 'high',
  start_at: '2026-10-10T12:00:00Z',
  due_at: '2026-10-30T21:00:00Z',
  labels: ['vip', 'quente'],
  custom_attributes: { orcamento: 2000, produto: 'Plano Pro', ativo: true },
  ...overrides,
});

describe('priorityView', () => {
  it('says each priority with a tone, an icon and a word', () => {
    ['urgent', 'high', 'medium', 'low'].forEach(priority => {
      const view = priorityView(priority);
      expect(view.icon).toMatch(/^i-lucide-/);
      expect(view.key).toBe(priority.toUpperCase());
      expect(view.tone).toBeTruthy();
    });
    expect(priorityView('urgent').tone).toBe('ruby');
  });

  it('has nothing to say about no priority', () => {
    expect(priorityView(null)).toBeNull();
    expect(priorityView('')).toBeNull();
  });
});

describe('attribute rows', () => {
  it('makes a row per attribute and keeps objects and lists as they are', () => {
    const rows = attributeRows({
      a: 'x',
      n: 5,
      ok: true,
      nested: { b: [1, 2] },
    });
    expect(rows.map(row => [row.key, row.value, row.editable])).toEqual([
      ['a', 'x', true],
      ['n', '5', true],
      ['ok', 'true', true],
      ['nested', '{"b":[1,2]}', false],
    ]);
    expect(rowsToAttributes(rows)).toEqual({
      a: 'x',
      n: 5,
      ok: true,
      nested: { b: [1, 2] },
    });
  });

  it('keeps a number a number and a boolean a boolean when edited, and a new row text', () => {
    const rows = attributeRows({ n: 5, ok: true });
    rows[0].value = '7.5';
    rows[1].value = 'false';
    rows.push({ ...blankRow(), key: ' novo ', value: '42' });
    expect(rowsToAttributes(rows)).toEqual({ n: 7.5, ok: false, novo: '42' });

    rows[0].value = 'abc';
    expect(rowsToAttributes(rows).n).toBe('abc');
  });

  it('leaves out a row with no name', () => {
    expect(
      rowsToAttributes([{ ...blankRow(), key: '  ', value: 'x' }])
    ).toEqual({});
  });
});

describe('attributeProblems', () => {
  it('names what is wrong', () => {
    expect(attributeProblems([{ ...blankRow(), key: '', value: 'x' }])).toEqual(
      ['KEY_EMPTY']
    );
    expect(
      attributeProblems([
        { ...blankRow(), key: 'a' },
        { ...blankRow(), key: ' a ' },
      ])
    ).toEqual(['DUPLICATE']);
    expect(attributeProblems([{ ...blankRow(), key: 'k'.repeat(61) }])).toEqual(
      ['KEY_LONG']
    );
    expect(
      attributeProblems(
        Array.from({ length: ATTRIBUTES_MAX + 1 }, (_, i) => ({
          ...blankRow(),
          key: `k${i}`,
        }))
      )
    ).toContain('TOO_MANY');
    expect(
      attributeProblems([
        { ...blankRow(), key: 'big', value: 'x'.repeat(10001) },
      ])
    ).toContain('TOO_BIG');
  });

  it('is empty for good rows, and for an empty blank row', () => {
    expect(attributeProblems(attributeRows(card().custom_attributes))).toEqual(
      []
    );
    expect(attributeProblems([blankRow()])).toEqual([]);
  });
});

describe('normalizeLabels', () => {
  it('trims, squeezes spaces and drops blanks and repeats, in order', () => {
    expect(
      normalizeLabels([' vip ', 'muito  quente', '', 'vip', 'frio'])
    ).toEqual(['vip', 'muito quente', 'frio']);
    expect(normalizeLabels(undefined)).toEqual([]);
  });
});

describe('the details form', () => {
  it('reads a card and sends it back unchanged', () => {
    const details = detailsFromCard(card());
    expect(details.priority).toBe('high');
    expect(details.start_at).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/);
    expect(detailsChanged(details, card())).toBe(false);

    const payload = detailsPayload(details);
    expect(new Date(payload.start_at).toISOString()).toBe(
      '2026-10-10T12:00:00.000Z'
    );
    expect(payload).toMatchObject({
      priority: 'high',
      labels: ['vip', 'quente'],
      custom_attributes: { orcamento: 2000, produto: 'Plano Pro', ativo: true },
    });
  });

  it('sends empty fields as null so they clear', () => {
    const details = detailsFromCard(card());
    details.priority = '';
    details.start_at = '';
    details.due_at = '';
    expect(detailsPayload(details)).toMatchObject({
      priority: null,
      start_at: null,
      due_at: null,
    });
    expect(detailsChanged(details, card())).toBe(true);
    expect(
      detailsChanged(
        detailsFromCard(card({ priority: null, start_at: null, due_at: null })),
        card({ priority: null, start_at: null, due_at: null })
      )
    ).toBe(false);
  });

  it('notices each kind of change', () => {
    const change = edit => {
      const details = detailsFromCard(card());
      edit(details);
      return detailsChanged(details, card());
    };
    expect(
      change(d => {
        d.priority = 'low';
      })
    ).toBe(true);
    expect(
      change(d => {
        d.labels = ['vip'];
      })
    ).toBe(true);
    expect(
      change(d => {
        d.rows[0].value = '2500';
      })
    ).toBe(true);
    expect(
      change(d => {
        d.rows.push({ ...blankRow(), key: 'novo', value: '1' });
      })
    ).toBe(true);
    expect(
      change(d => {
        d.due_at = '2026-11-01T10:00';
      })
    ).toBe(true);
    expect(change(() => {})).toBe(false);
  });

  it('refuses a start after the due date, too many labels and bad attributes', () => {
    const details = detailsFromCard(card());
    expect(canSaveDetails(details)).toBe(true);

    details.start_at = '2026-12-01T10:00';
    details.due_at = '2026-11-01T10:00';
    expect(detailsProblems(details).dates).toBe('DATES_ORDER');
    expect(canSaveDetails(details)).toBe(false);

    const more = detailsFromCard(card());
    more.labels = Array.from({ length: LABELS_MAX + 1 }, (_, i) => `l${i}`);
    expect(detailsProblems(more).labels).toEqual(['LABELS_TOO_MANY']);

    const bad = detailsFromCard(card());
    bad.rows.push({ ...blankRow(), key: 'produto', value: 'x' });
    expect(canSaveDetails(bad)).toBe(false);
  });
});
