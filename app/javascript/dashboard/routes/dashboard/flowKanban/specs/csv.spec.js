import {
  MAX_BYTES,
  actionView,
  canRun,
  fileProblem,
  filenameFrom,
  isFinished,
  visibleCells,
  writableRows,
} from '../csv';

const file = (name, size = 100, type = 'text/csv') => ({ name, size, type });

describe('fileProblem', () => {
  it('takes a csv or txt file of a sensible size', () => {
    expect(fileProblem(file('produtos.csv'))).toBeNull();
    expect(fileProblem(file('PRODUTOS.CSV', 10, ''))).toBeNull();
    expect(fileProblem(file('dados.txt', 10, 'text/plain'))).toBeNull();
  });

  it('says what is wrong', () => {
    expect(fileProblem(null)).toBe('none');
    expect(fileProblem(file('foto.png', 10, 'image/png'))).toBe('type');
    expect(fileProblem(file('big.csv', MAX_BYTES + 1))).toBe('size');
    expect(fileProblem(file('vazio.csv', 0))).toBe('empty');
  });
});

describe('filenameFrom', () => {
  it('reads the name the server gave', () => {
    expect(
      filenameFrom('attachment; filename="deals-vendas.csv"', 'x.csv')
    ).toBe('deals-vendas.csv');
    expect(
      filenameFrom("attachment; filename*=UTF-8''pre%C3%A7os.csv", 'x')
    ).toBe('preços.csv');
  });

  it('falls back when there is none', () => {
    expect(filenameFrom(undefined, 'products.csv')).toBe('products.csv');
    expect(filenameFrom('attachment', 'products.csv')).toBe('products.csv');
  });
});

describe('actionView', () => {
  it('gives every action a tone, an icon and a word', () => {
    ['create', 'update', 'skip', 'error'].forEach(action => {
      const view = actionView(action);
      expect(view.icon).toMatch(/^i-lucide-/);
      expect(view.key).toBeTruthy();
      expect(view.tone).toBeTruthy();
    });
    expect(actionView('error').tone).toBe('ruby');
    expect(actionView('weird').key).toBe('SKIP');
  });
});

describe('canRun', () => {
  const payload = (overrides = {}) => ({
    status: 'analyzed',
    created: 3,
    updated: 1,
    errors: 2,
    ...overrides,
  });
  const analysis = (missing = []) => ({ missing });

  it('runs when something can be written, even if some rows have errors', () => {
    expect(writableRows(payload())).toBe(4);
    expect(canRun(payload(), analysis())).toBe(true);
  });

  it('does not run without a required column, without rows to write, or twice', () => {
    expect(canRun(payload(), analysis(['name']))).toBe(false);
    expect(canRun(payload({ created: 0, updated: 0 }), analysis())).toBe(false);
    expect(canRun(payload({ status: 'running' }), analysis())).toBe(false);
  });
});

describe('isFinished', () => {
  it('is true for done and failed only', () => {
    expect(['done', 'failed'].map(isFinished)).toEqual([true, true]);
    expect(['analyzed', 'running'].map(isFinished)).toEqual([false, false]);
  });
});

describe('visibleCells', () => {
  it('keeps the first cells of a wide row', () => {
    expect(visibleCells([1, 2, 3, 4, 5, 6, 7, 8])).toHaveLength(6);
    expect(visibleCells([1, 2], 6)).toEqual([1, 2]);
  });
});
