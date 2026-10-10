import { cardTabs, nextTabIndex, panelId, tabCount, tabId } from '../panelTabs';

const t = key => key.split('.').pop();

describe('nextTabIndex', () => {
  it('moves along the row and wraps at the ends', () => {
    expect(nextTabIndex('ArrowRight', 0, 5)).toBe(1);
    expect(nextTabIndex('ArrowRight', 4, 5)).toBe(0);
    expect(nextTabIndex('ArrowLeft', 2, 5)).toBe(1);
    expect(nextTabIndex('ArrowLeft', 0, 5)).toBe(4);
  });

  it('jumps to the ends with Home and End', () => {
    expect(nextTabIndex('Home', 3, 5)).toBe(0);
    expect(nextTabIndex('End', 1, 5)).toBe(4);
  });

  it('mirrors the arrows in a right-to-left layout', () => {
    expect(nextTabIndex('ArrowLeft', 0, 5, true)).toBe(1);
    expect(nextTabIndex('ArrowRight', 0, 5, true)).toBe(4);
  });

  it('leaves every other key, and an empty row, alone', () => {
    expect(nextTabIndex('Enter', 0, 5)).toBeNull();
    expect(nextTabIndex('a', 0, 5)).toBeNull();
    expect(nextTabIndex('ArrowRight', 0, 0)).toBeNull();
  });
});

describe('tab ids', () => {
  it('ties a tab to its panel by the same prefix and id', () => {
    expect(tabId('card', 'tasks')).toBe('card-tab-tasks');
    expect(panelId('card', 'tasks')).toBe('card-panel-tasks');
  });
});

describe('cardTabs', () => {
  it('lists the five sections in order, with a count only where a number says something', () => {
    const card = {
      items_count: 3,
      tasks: { open: 2 },
      conversations: [{ display_id: 1 }],
    };
    const tabs = cardTabs(card, t);

    expect(tabs.map(tab => tab.id)).toEqual([
      'details',
      'value',
      'tasks',
      'conversations',
      'history',
    ]);
    expect(tabs.map(tab => tab.count)).toEqual([undefined, 3, 2, 1, undefined]);
  });

  it('shows no count for an empty or missing card', () => {
    expect(cardTabs(null, t).map(tab => tab.count)).toEqual([
      undefined,
      null,
      null,
      null,
      undefined,
    ]);
    expect(tabCount(0)).toBeNull();
    expect(tabCount('3')).toBeNull();
    expect(tabCount(7)).toBe(7);
  });
});
