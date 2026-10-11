import { mount } from '@vue/test-utils';
import ConversationChips from '../ConversationChips.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('../useFlowKanban', () => ({
  useFlowKanban: () => ({
    inboxFor: id => ({ id, name: 'Vendas' }),
    inboxIcon: () => 'i-lucide-inbox',
    conversationPath: id => `/conversations/${id}`,
  }),
}));

const chips = conversations =>
  mount(ConversationChips, {
    props: { conversations },
    global: {
      stubs: {
        RouterLink: { props: ['to'], template: '<a><slot /></a>' },
        Icon: { props: ['icon'], template: '<i :data-icon="icon" />' },
      },
    },
  });

const conversation = extra => ({
  display_id: 7,
  inbox_id: 3,
  status: 'pending',
  ...extra,
});

describe('ConversationChips', () => {
  it('shows a robot and says so when an AI agent is handling a pending conversation', () => {
    const wrapper = chips([conversation({ handled_by_agent: true })]);

    expect(wrapper.find('[data-icon="i-lucide-bot"]').exists()).toBe(true);
    expect(wrapper.find('.bg-n-amber-9').exists()).toBe(false);
    expect(wrapper.find('a').attributes('title')).toContain(
      'FLOW_KANBAN.CARD.HANDLED_BY_AGENT'
    );
    expect(wrapper.find('.sr-only').text()).toBe(
      'FLOW_KANBAN.CARD.HANDLED_BY_AGENT'
    );
  });

  it('keeps the plain status dot for a conversation nobody automated', () => {
    const wrapper = chips([conversation({ handled_by_agent: false })]);

    expect(wrapper.find('[data-icon="i-lucide-bot"]').exists()).toBe(false);
    expect(wrapper.find('.bg-n-amber-9').exists()).toBe(true);
    expect(wrapper.find('a').attributes('title')).toBe('Vendas');
  });
});
