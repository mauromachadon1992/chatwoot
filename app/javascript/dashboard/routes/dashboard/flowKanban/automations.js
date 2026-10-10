// The logic of the rule editor and of the sentences that describe rules and their results. Pure,
// so it is tested without a screen; `t` is vue-i18n's, passed in.

// Mirrors Custom::Kanban::StageAutomation::TRIGGER_TYPES and AutomationAction::TYPES.
export const TRIGGERS = [
  'conversation_status_changed',
  'label_added',
  'deal_created',
  'deal_stalled',
  'no_reply',
];
export const ACTION_TYPES = [
  'move_to_stage',
  'create_task',
  'assign_agent',
  'add_label',
];
export const STATUSES = ['open', 'pending', 'resolved', 'snoozed'];
export const MAX_ACTIONS = 5;
export const NO_REPLY_HOURS = [1, 720];
export const DUE_HOURS = [0, 720];
export const DEAL_AGENT = 'deal_agent';
export const TASK_TYPES = ['call', 'meeting', 'email', 'follow_up', 'custom'];

const upper = value => String(value).toUpperCase();

export const blankTriggerConfig = type =>
  ({
    conversation_status_changed: { status: 'resolved' },
    label_added: { label: '' },
    no_reply: { hours: 24, side: 'customer' },
  })[type] || {};

// A fresh action of `type`; a move starts on the first open stage so the editor never shows an
// empty choice that cannot be saved.
export const blankAction = (type, { stages = [] } = {}) =>
  ({
    move_to_stage: {
      type,
      stage_id:
        stages.find(stage => stage.stage_type === 'open')?.id ??
        stages[0]?.id ??
        '',
    },
    create_task: {
      type,
      title: '',
      task_type: 'follow_up',
      due_in_hours: 24,
      assignee: DEAL_AGENT,
    },
    assign_agent: { type, user_id: '' },
    add_label: { type, label: '' },
  })[type];

export const blankRule = context => ({
  trigger_type: 'conversation_status_changed',
  trigger_config: blankTriggerConfig('conversation_status_changed'),
  actions: [blankAction('move_to_stage', context)],
  active: true,
});

const inRange = (value, [min, max]) =>
  Number.isInteger(value) && value >= min && value <= max;

// What is missing in a step, as keys, so the editor can say it next to the field.
export const actionProblems = action => {
  const problems = [];
  if (action.type === 'move_to_stage' && !action.stage_id)
    problems.push('stage');
  if (action.type === 'assign_agent' && !action.user_id) problems.push('agent');
  if (action.type === 'add_label' && !action.label) problems.push('label');
  if (action.type === 'create_task') {
    if (!String(action.title || '').trim()) problems.push('title');
    if (!inRange(Number(action.due_in_hours), DUE_HOURS)) problems.push('due');
    if (!action.assignee) problems.push('agent');
  }
  return problems;
};

export const triggerProblems = rule => {
  const config = rule.trigger_config || {};
  if (rule.trigger_type === 'label_added' && !config.label) return ['label'];
  if (
    rule.trigger_type === 'no_reply' &&
    (!inRange(Number(config.hours), NO_REPLY_HOURS) || !config.side)
  )
    return ['hours'];
  return [];
};

export const ruleProblems = rule => ({
  trigger: triggerProblems(rule),
  actions: rule.actions.map(actionProblems),
});

export const canSaveRule = rule => {
  const { trigger, actions } = ruleProblems(rule);
  return (
    rule.actions.length > 0 &&
    rule.actions.length <= MAX_ACTIONS &&
    trigger.length === 0 &&
    actions.every(list => list.length === 0)
  );
};

// What the server takes: numbers as numbers, only the keys each step uses.
export const toPayload = rule => ({
  trigger_type: rule.trigger_type,
  trigger_config: rule.trigger_config,
  active: rule.active,
  actions: rule.actions.map(action => {
    const step = { ...action };
    if ('stage_id' in step) step.stage_id = Number(step.stage_id);
    if ('user_id' in step) step.user_id = Number(step.user_id);
    if ('due_in_hours' in step) step.due_in_hours = Number(step.due_in_hours);
    if (step.assignee !== undefined && step.assignee !== DEAL_AGENT)
      step.assignee = Number(step.assignee);
    return step;
  }),
});

// --- sentences ---------------------------------------------------------------------------

const NS = 'FLOW_KANBAN.AUTOMATIONS';

// "in 2 days", "in 6 hours" or "now": whole days when the hours make whole days.
export const describeDue = (hours, t) => {
  const value = Number(hours);
  if (value === 0) return t(`${NS}.DUE.NOW`);
  if (value % 24 === 0) {
    const days = value / 24;
    return t(`${NS}.DUE.DAYS`, { n: days }, days);
  }
  return t(`${NS}.DUE.HOURS`, { n: value }, value);
};

export const describeTrigger = (rule, t) => {
  const config = rule.trigger_config || {};
  const key = {
    conversation_status_changed: 'CONVERSATION_STATUS_CHANGED',
    label_added: 'LABEL_ADDED',
    deal_created: 'DEAL_CREATED',
    deal_stalled: 'DEAL_STALLED',
    no_reply: config.side === 'agent' ? 'NO_REPLY_AGENT' : 'NO_REPLY_CUSTOMER',
  }[rule.trigger_type];
  return t(`${NS}.TRIGGER_TEXT.${key}`, {
    status: config.status
      ? t(`${NS}.STATUSES.${upper(config.status)}`).toLowerCase()
      : '',
    label: config.label,
    hours: config.hours,
  });
};

// `lookup`: { stageName(id), agentName(id) }.
export const describeAction = (action, lookup, t) => {
  switch (action.type) {
    case 'move_to_stage':
      return t(`${NS}.ACTION_TEXT.MOVE`, {
        stage: lookup.stageName(action.stage_id),
      });
    case 'create_task':
      return t(`${NS}.ACTION_TEXT.TASK`, {
        title: action.title,
        due: describeDue(action.due_in_hours, t),
        agent:
          action.assignee === DEAL_AGENT
            ? t(`${NS}.ACTION_TEXT.DEAL_AGENT`)
            : lookup.agentName(action.assignee),
      });
    case 'assign_agent':
      return t(`${NS}.ACTION_TEXT.ASSIGN`, {
        agent: lookup.agentName(action.user_id),
      });
    default:
      return t(`${NS}.ACTION_TEXT.LABEL`, { label: action.label });
  }
};

export const describeRule = (rule, lookup, t) =>
  t(`${NS}.SENTENCE`, {
    trigger: describeTrigger(rule, t),
    actions: rule.actions
      .map(action => describeAction(action, lookup, t))
      .join('; '),
  });

// What a rule did on a deal, from the result the server stored (names as they were then).
export const describeResult = (result, t) => {
  if (result.status === 'failed') return t(`${NS}.RESULT.FAILED`);
  if (result.status === 'skipped')
    return t(`${NS}.RESULT.SKIPPED`, {
      reason: t(`${NS}.REASONS.${upper(result.reason)}`),
    });
  return t(`${NS}.RESULT.${upper(result.type)}`, {
    stage: result.stage_name,
    title: result.title,
    agent: result.agent_name,
    label: result.label,
  });
};

export const describeResults = (results, t) =>
  (results || []).map(result => describeResult(result, t)).join(' · ');

// --- starters ----------------------------------------------------------------------------

// Three rules an administrator can start from; they fill the editor and are not saved. The task
// titles are written in the viewer's language.
export const starterRules = (context, t) => {
  const stages = context?.stages || [];
  const won = stages.find(stage => stage.stage_type === 'won');
  const starters = [];
  if (won)
    starters.push({
      key: 'WON_WHEN_RESOLVED',
      rule: {
        trigger_type: 'conversation_status_changed',
        trigger_config: { status: 'resolved' },
        actions: [{ type: 'move_to_stage', stage_id: won.id }],
        active: true,
      },
    });
  starters.push(
    {
      key: 'CHASE_SILENT_CUSTOMER',
      rule: {
        trigger_type: 'no_reply',
        trigger_config: { hours: 24, side: 'customer' },
        actions: [
          {
            ...blankAction('create_task'),
            title: t(`${NS}.STARTERS.CHASE_SILENT_CUSTOMER_TASK`),
            due_in_hours: 2,
          },
        ],
        active: true,
      },
    },
    {
      key: 'FIRST_CONTACT',
      rule: {
        trigger_type: 'deal_created',
        trigger_config: {},
        actions: [
          {
            ...blankAction('create_task'),
            title: t(`${NS}.STARTERS.FIRST_CONTACT_TASK`),
            due_in_hours: 1,
          },
        ],
        active: true,
      },
    }
  );
  return starters;
};
