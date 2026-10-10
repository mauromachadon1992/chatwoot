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

describe('describeEvent for a rule that ran', () => {
  it('writes what the rule did and credits the automation, not the system', () => {
    const t = key => key.split('.').pop();
    const view = describeEvent(
      event('automation_ran', {
        results: [
          { type: 'move_to_stage', status: 'done', stage_name: 'Ganho' },
        ],
      }),
      money,
      t
    );

    expect(view.key).toBe('FLOW_KANBAN.HISTORY.AUTOMATION_RAN');
    expect(view.icon).toBe('i-lucide-zap');
    expect(view.params.results).toBe('MOVE_TO_STAGE');
    expect(view.byRule).toBe(true);
  });
});

describe('describeEvent for the Pro fields and who did them', () => {
  const t = key => key.split('.').pop();

  it('says a priority change with both names, and no priority as a name too', () => {
    const view = describeEvent(
      event('priority_changed', { from: null, to: 'high' }),
      money,
      t
    );
    expect(view.key).toBe('FLOW_KANBAN.HISTORY.PRIORITY_CHANGED');
    expect(view.icon).toBe('i-lucide-flag');
    expect(view.params.from).toBe('NO_PRIORITY');
    expect(view.params.priority).toBe('HIGH');
  });

  it('lists the labels added and removed, and the names of the attributes, never values', () => {
    const labels = describeEvent(
      event('labels_changed', { added: ['vip', 'frio'], removed: ['quente'] }),
      money,
      t
    );
    expect(labels.params).toMatchObject({
      added: 'vip, frio',
      removed: 'quente',
    });
    expect(labels.key).toBe('FLOW_KANBAN.HISTORY.LABELS_CHANGED');

    const onlyAdded = describeEvent(
      event('labels_changed', { added: ['vip'], removed: [] }),
      money,
      t
    );
    const onlyRemoved = describeEvent(
      event('labels_changed', { added: [], removed: ['vip'] }),
      money,
      t
    );
    expect([onlyAdded.key, onlyRemoved.key]).toEqual([
      'FLOW_KANBAN.HISTORY.LABELS_ADDED',
      'FLOW_KANBAN.HISTORY.LABELS_REMOVED',
    ]);

    const attributes = describeEvent(
      event('attributes_changed', { keys: ['cpf', 'origem'] }),
      money,
      t
    );
    expect(attributes.params.keys).toBe('cpf, origem');
    expect(attributes.icon).toBe('i-lucide-braces');
  });

  it('tells the agents’ service user, a rule and a person apart', () => {
    const agent = describeEvent(
      event(
        'stage_moved',
        {},
        {
          actor_kind: 'agent_bot',
          actor_name: 'Agente IA',
          user: { name: 'Agente IA' },
        }
      ),
      money,
      t
    );
    expect(agent.agentBot).toBe(true);
    expect(agent.actor).toBe('Agente IA');

    const rule = describeEvent(
      event('stage_moved', {}, { actor_kind: 'rule' }),
      money,
      t
    );
    expect(rule.byRule).toBe(true);
    expect(rule.agentBot).toBe(false);

    const person = describeEvent(
      event('stage_moved', {}, { actor_kind: 'user', user: { name: 'Ana' } }),
      money,
      t
    );
    expect([person.agentBot, person.byRule, person.actor]).toEqual([
      false,
      false,
      'Ana',
    ]);
  });
});
