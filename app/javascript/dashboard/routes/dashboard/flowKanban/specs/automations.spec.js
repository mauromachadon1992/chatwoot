import {
  MAX_ACTIONS,
  blankAction,
  blankRule,
  canSaveRule,
  describeAction,
  describeDue,
  describeResults,
  describeRule,
  describeTrigger,
  ruleProblems,
  starterRules,
  toPayload,
} from '../automations';

// A t that shows the key and its parameters, so the tests read what each sentence is built from.
const t = (key, params = {}) => {
  const shown = Object.entries(params)
    .filter(([, value]) => value !== undefined && value !== '')
    .map(([name, value]) => `${name}=${value}`)
    .join(',');
  return shown
    ? `${key.split('.').slice(-2).join('.')}(${shown})`
    : key.split('.').slice(-2).join('.');
};

const stages = [
  { id: 1, name: 'Lead', stage_type: 'open' },
  { id: 2, name: 'Proposta', stage_type: 'open' },
  { id: 3, name: 'Ganho', stage_type: 'won' },
];
const lookup = {
  stageName: id => stages.find(stage => stage.id === Number(id))?.name,
  agentName: id => ({ 7: 'Bruno' })[Number(id)],
};

describe('blank rules and actions', () => {
  it('starts a move on the first open stage, never on an empty choice', () => {
    expect(blankAction('move_to_stage', { stages })).toEqual({
      type: 'move_to_stage',
      stage_id: 1,
    });
    expect(blankAction('move_to_stage', { stages: [stages[2]] }).stage_id).toBe(
      3
    );
  });

  it('starts a task for the deal’s agent, a day from now', () => {
    expect(blankAction('create_task')).toMatchObject({
      assignee: 'deal_agent',
      due_in_hours: 24,
      task_type: 'follow_up',
    });
  });

  it('starts a rule that can be saved once its one choice is made', () => {
    expect(canSaveRule(blankRule({ stages }))).toBe(true);
  });
});

describe('what can be saved', () => {
  const rule = (overrides = {}) => ({ ...blankRule({ stages }), ...overrides });

  it('needs a label for a label trigger and hours in range for a silence trigger', () => {
    expect(
      ruleProblems(
        rule({ trigger_type: 'label_added', trigger_config: { label: '' } })
      ).trigger
    ).toEqual(['label']);
    expect(
      canSaveRule(
        rule({ trigger_type: 'label_added', trigger_config: { label: 'vip' } })
      )
    ).toBe(true);

    const silent = hours =>
      rule({
        trigger_type: 'no_reply',
        trigger_config: { hours, side: 'customer' },
      });
    expect([0, 721, 1.5, ''].map(hours => canSaveRule(silent(hours)))).toEqual([
      false,
      false,
      false,
      false,
    ]);
    expect([1, 24, 720].map(hours => canSaveRule(silent(hours)))).toEqual([
      true,
      true,
      true,
    ]);
  });

  it('names what is missing in each step', () => {
    const problems = ruleProblems(
      rule({
        actions: [
          blankAction('create_task'),
          { type: 'assign_agent', user_id: '' },
          { type: 'add_label', label: '' },
          { type: 'move_to_stage', stage_id: '' },
        ],
      })
    );

    expect(problems.actions).toEqual([
      ['title'],
      ['agent'],
      ['label'],
      ['stage'],
    ]);
  });

  it('wants at least one action and at most five', () => {
    expect(canSaveRule(rule({ actions: [] }))).toBe(false);
    const many = Array.from({ length: MAX_ACTIONS + 1 }, () =>
      blankAction('move_to_stage', { stages })
    );
    expect(canSaveRule(rule({ actions: many }))).toBe(false);
    expect(canSaveRule(rule({ actions: many.slice(0, MAX_ACTIONS) }))).toBe(
      true
    );
  });

  it('refuses a due time out of range', () => {
    const task = hours =>
      rule({
        actions: [
          { ...blankAction('create_task'), title: 'x', due_in_hours: hours },
        ],
      });
    expect([-1, 721, 'abc'].map(hours => canSaveRule(task(hours)))).toEqual([
      false,
      false,
      false,
    ]);
    expect([0, 720].map(hours => canSaveRule(task(hours)))).toEqual([
      true,
      true,
    ]);
  });
});

describe('toPayload', () => {
  it('sends numbers as numbers and keeps the deal-agent word', () => {
    const payload = toPayload({
      trigger_type: 'deal_created',
      trigger_config: {},
      active: true,
      actions: [
        { type: 'move_to_stage', stage_id: '3' },
        {
          type: 'create_task',
          title: 'x',
          task_type: 'call',
          due_in_hours: '48',
          assignee: 'deal_agent',
        },
        {
          type: 'create_task',
          title: 'y',
          task_type: 'call',
          due_in_hours: 1,
          assignee: '7',
        },
        { type: 'assign_agent', user_id: '7' },
      ],
    });

    expect(payload.actions).toEqual([
      { type: 'move_to_stage', stage_id: 3 },
      {
        type: 'create_task',
        title: 'x',
        task_type: 'call',
        due_in_hours: 48,
        assignee: 'deal_agent',
      },
      {
        type: 'create_task',
        title: 'y',
        task_type: 'call',
        due_in_hours: 1,
        assignee: 7,
      },
      { type: 'assign_agent', user_id: 7 },
    ]);
  });
});

describe('sentences', () => {
  it('says a due time in whole days when the hours make whole days', () => {
    expect(describeDue(0, t)).toBe('DUE.NOW');
    expect(describeDue(6, t)).toBe('DUE.HOURS(n=6)');
    expect(describeDue(48, t)).toBe('DUE.DAYS(n=2)');
    expect(describeDue(25, t)).toBe('DUE.HOURS(n=25)');
  });

  it('says which side is silent', () => {
    const silent = side =>
      describeTrigger(
        { trigger_type: 'no_reply', trigger_config: { hours: 24, side } },
        t
      );
    expect(silent('customer')).toBe('TRIGGER_TEXT.NO_REPLY_CUSTOMER(hours=24)');
    expect(silent('agent')).toBe('TRIGGER_TEXT.NO_REPLY_AGENT(hours=24)');
  });

  it('describes each action with the stage or agent by name, and the deal’s agent by word', () => {
    expect(
      describeAction({ type: 'move_to_stage', stage_id: 3 }, lookup, t)
    ).toBe('ACTION_TEXT.MOVE(stage=Ganho)');
    expect(
      describeAction({ type: 'assign_agent', user_id: 7 }, lookup, t)
    ).toBe('ACTION_TEXT.ASSIGN(agent=Bruno)');
    expect(describeAction({ type: 'add_label', label: 'vip' }, lookup, t)).toBe(
      'ACTION_TEXT.LABEL(label=vip)'
    );
    expect(
      describeAction(
        {
          type: 'create_task',
          title: 'Ligar',
          due_in_hours: 48,
          assignee: 'deal_agent',
        },
        lookup,
        t
      )
    ).toBe(
      'ACTION_TEXT.TASK(title=Ligar,due=DUE.DAYS(n=2),agent=ACTION_TEXT.DEAL_AGENT)'
    );
  });

  it('joins a rule’s actions into one sentence, in order', () => {
    const sentence = describeRule(
      {
        trigger_type: 'deal_created',
        trigger_config: {},
        actions: [
          { type: 'move_to_stage', stage_id: 2 },
          { type: 'assign_agent', user_id: 7 },
        ],
      },
      lookup,
      t
    );

    expect(sentence).toContain(
      'actions=ACTION_TEXT.MOVE(stage=Proposta); ACTION_TEXT.ASSIGN(agent=Bruno)'
    );
  });
});

describe('what a rule did', () => {
  it('says what was done, what was skipped and why, and what failed', () => {
    const text = describeResults(
      [
        { type: 'move_to_stage', status: 'done', stage_name: 'Ganho' },
        { type: 'create_task', status: 'skipped', reason: 'no_agent' },
        { type: 'add_label', status: 'failed' },
      ],
      t
    );

    expect(text).toBe(
      'RESULT.MOVE_TO_STAGE(stage=Ganho) · RESULT.SKIPPED(reason=REASONS.NO_AGENT) · RESULT.FAILED'
    );
  });

  it('is empty for no results', () => {
    expect(describeResults(undefined, t)).toBe('');
  });
});

describe('starter rules', () => {
  it('offers a move to Won only when the board has a won stage, and fills task titles', () => {
    const withWon = starterRules({ stages }, t).map(starter => starter.key);
    expect(withWon).toEqual([
      'WON_WHEN_RESOLVED',
      'CHASE_SILENT_CUSTOMER',
      'FIRST_CONTACT',
    ]);
    expect(
      starterRules({ stages: [stages[0]] }, t).map(starter => starter.key)
    ).toEqual(['CHASE_SILENT_CUSTOMER', 'FIRST_CONTACT']);

    const chase = starterRules({ stages }, t)[1].rule;
    expect(chase.actions[0].title).toBe('STARTERS.CHASE_SILENT_CUSTOMER_TASK');
    expect(chase.trigger_config).toEqual({ hours: 24, side: 'customer' });
  });

  it('gives starters that are ready to save once the board needs nothing more', () => {
    starterRules({ stages }, t).forEach(({ rule }) =>
      expect(canSaveRule(rule)).toBe(true)
    );
  });
});
