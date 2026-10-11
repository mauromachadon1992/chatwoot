import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import FlowAuthShell from '../FlowAuthShell.vue';

const store = createStore({
  modules: {
    globalConfig: {
      namespaced: true,
      getters: {
        get: () => ({
          logo: '/logo.svg',
          logoDark: '',
          installationName: 'Flow Agents',
        }),
      },
    },
  },
});

const mountShell = ({
  props = {},
  locale = 'pt_BR',
  slot = '<form class="shadow p-11">form</form>',
} = {}) =>
  mount(FlowAuthShell, {
    props: { title: 'Entrar no Flow Agents', ...props },
    slots: {
      default: slot,
      'after-title': '<p class="text-center">ou crie uma conta</p>',
    },
    global: {
      plugins: [
        store,
        createI18n({
          legacy: false,
          locale,
          messages: {
            [locale]: {
              FLOW_LOGIN_PAGE: {
                LINKS: 'Links',
                SUPPORT: 'Suporte',
                TERMS: 'Termos',
                PRIVACY: 'Privacidade',
              },
            },
          },
        }),
      ],
    },
  });

const PAGE = {
  layout: 'background',
  background: {
    kind: 'gradient',
    css: 'linear-gradient(135deg, #111111, #222222)',
    image: null,
    animation: 'drift',
    overlay: 30,
  },
  copy: {
    pt_BR: { title: 'Bem-vindo à Flow', subtitle: 'Entre com seu e-mail' },
    en: {},
    es: {},
  },
  options: {
    hide_signup: true,
    support_url: 'mailto:help@flow.example',
    support_label: 'Ajuda',
    terms_url: 'https://flow.example/terms',
    privacy_url: null,
  },
};

describe('FlowAuthShell', () => {
  afterEach(() => {
    delete window.globalConfig;
  });

  describe('without an installation login page', () => {
    it("renders Chatwoot's own header page, unchanged", () => {
      const wrapper = mountShell();

      expect(wrapper.find('main').classes()).toEqual(
        expect.arrayContaining(['py-20', 'bg-n-brand/5'])
      );
      expect(wrapper.find('h2').text()).toBe('Entrar no Flow Agents');
      expect(wrapper.find('.flow-auth').exists()).toBe(false);
      expect(wrapper.text()).toContain('ou crie uma conta');
    });

    it("renders Chatwoot's own card-only wrapper for the password screens", () => {
      const wrapper = mountShell({ props: { variant: 'plain' } });

      expect(wrapper.find('div').classes()).toEqual(
        expect.arrayContaining(['justify-center', 'py-12'])
      );
      expect(wrapper.find('h2').exists()).toBe(false);
    });
  });

  describe('with an installation login page', () => {
    beforeEach(() => {
      window.globalConfig = { FLOW_LOGIN_PAGE: PAGE };
    });

    it("puts the screen in one surface, with the copy for its language over Chatwoot's title", () => {
      const wrapper = mountShell();

      expect(wrapper.find('.flow-auth--background').exists()).toBe(true);
      expect(wrapper.find('.flow-auth__surface h1').text()).toBe(
        'Bem-vindo à Flow'
      );
      expect(wrapper.find('.flow-auth__surface').text()).toContain(
        'Entre com seu e-mail'
      );
      expect(wrapper.find('.flow-auth__surface form').exists()).toBe(true);
    });

    it("keeps Chatwoot's title in a language with no copy", () => {
      const wrapper = mountShell({ locale: 'en' });

      expect(wrapper.find('h1').text()).toBe('Entrar no Flow Agents');
    });

    it('draws the background, animated, behind everything and out of reach of assistive tech', () => {
      const wrapper = mountShell();
      const bg = wrapper.find('.flow-auth__bg');

      // jsdom serialises the colours as rgb(); the gradient itself is what matters.
      expect(bg.attributes('style')).toContain('linear-gradient(135deg');
      expect(bg.classes()).toContain('flow-auth__bg--drift');
      expect(wrapper.find('.flow-auth__visual').attributes('aria-hidden')).toBe(
        'true'
      );
    });

    it('lists only the links that were set, in a labelled nav', () => {
      const wrapper = mountShell();
      const links = wrapper.findAll('nav a');

      expect(links.map(link => link.text())).toEqual(['Ajuda', 'Termos']);
      expect(links[0].attributes('href')).toBe('mailto:help@flow.example');
      expect(wrapper.find('nav').attributes('aria-label')).toBe('Links');
    });

    it('shows the panel message only in the side panel layout', () => {
      window.globalConfig = {
        FLOW_LOGIN_PAGE: {
          ...PAGE,
          layout: 'split',
          copy: { pt_BR: { panel_message: 'Atendimento que resolve.' } },
        },
      };
      const wrapper = mountShell();

      expect(wrapper.find('.flow-auth--split').exists()).toBe(true);
      expect(wrapper.find('.flow-auth__message').text()).toBe(
        'Atendimento que resolve.'
      );
    });
  });
});
