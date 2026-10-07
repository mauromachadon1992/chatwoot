import { describeEvent, groupByDay } from '../history';

const money = cents => `R$ ${(cents / 100).toFixed(2)}`;
const event = (kind, data = {}, extra = {}) => ({
  id: 1,
  kind,
  data,
  created_at: 1791450000,
  user: null,
  ...extra,
});

describe('describeEvent', () => {
  it('tells an automatic deal from one an agent created', () => {
    expect(
      describeEvent(event('created', { source: 'automatic' }), money).key
    ).toBe('FLOW_KANBAN.HISTORY.CREATED_AUTOMATIC');
    expect(
      describeEvent(event('created', { source: 'manual' }), money).key
    ).toBe('FLOW_KANBAN.HISTORY.CREATED');
  });

  it('says a lost deal was lost, with its reason and note when it has them', () => {
    const lost = describeEvent(
      event('stage_moved', {
        stage_type: 'lost',
        to_stage_name: 'Perdido',
        lost_reason: 'Preço',
        lost_note: 'Achou mais barato',
      }),
      money
    );

    expect(lost.key).toBe('FLOW_KANBAN.HISTORY.LOST_WITH_REASON');
    expect(lost.params).toMatchObject({ stage: 'Perdido', reason: 'Preço' });
    expect(lost.note).toBe('Achou mais barato');
    expect(
      describeEvent(event('stage_moved', { stage_type: 'lost' }), money).key
    ).toBe('FLOW_KANBAN.HISTORY.LOST');
  });

  it('names who did it, or says a rule did', () => {
    const byAgent = describeEvent(
      event(
        'stage_moved',
        { to_stage_name: 'Proposta' },
        { user: { name: 'Ana' } }
      ),
      money
    );
    const byRule = describeEvent(
      event('stage_moved', { to_stage_name: 'Ganho', by_rule: true }),
      money
    );

    expect([byAgent.actor, byAgent.byRule]).toEqual(['Ana', false]);
    expect([byRule.actor, byRule.byRule]).toEqual([null, true]);
  });

  it('formats the values of a value change, and of a quote', () => {
    const changed = describeEvent(
      event('value_changed', { from_cents: 0, to_cents: 150000 }),
      money
    );
    expect(changed.params).toMatchObject({
      fromValue: 'R$ 0.00',
      toValue: 'R$ 1500.00',
    });
    expect(
      describeEvent(
        event('quote_prepared', { total_cents: 999, display_id: 7 }),
        money
      ).params
    ).toMatchObject({ toValue: 'R$ 9.99', conversation: 7 });
  });

  it('tells an unassignment from an assignment', () => {
    expect(describeEvent(event('assignee_changed', {}), money).key).toBe(
      'FLOW_KANBAN.HISTORY.UNASSIGNED'
    );
  });
});

describe('groupByDay', () => {
  it('puts events of the same day under one heading, keeping their order', () => {
    const day = new Date(2026, 9, 8, 10).getTime() / 1000;
    const events = [
      { id: 3, created_at: day + 3600 },
      { id: 2, created_at: day },
      { id: 1, created_at: day - 86400 },
    ];

    const groups = groupByDay(events, 'en');

    expect(groups.map(group => group.events.map(item => item.id))).toEqual([
      [3, 2],
      [1],
    ]);
  });
});
