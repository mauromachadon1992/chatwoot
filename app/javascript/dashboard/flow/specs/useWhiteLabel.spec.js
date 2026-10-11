import { ref, nextTick } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { useWhiteLabel } from '../useWhiteLabel';

const accountId = ref(1);
const globalConfig = {
  installationName: 'Chatwoot',
  logoThumbnail: '/logo.svg',
};

vi.mock('vuex', () => ({
  useStore: () => ({ state: { globalConfig } }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId }),
}));

const BRAND = {
  enabled: true,
  installation_name: 'Clínica Sorriso',
  logo_thumbnail: '/flow/brand/1/white_label_icon/7',
  brand_color: '#0F766E',
  theme_css: ':root{--blue-9:15 118 110;}body.dark{--blue-9:15 118 110;}',
};

const themeStyle = () => document.getElementById('flow-white-label-theme');

describe('useWhiteLabel', () => {
  beforeEach(() => {
    accountId.value = 1;
    Object.assign(globalConfig, {
      installationName: 'Chatwoot',
      logoThumbnail: '/logo.svg',
    });
    document.head.innerHTML = '<meta name="theme-color" content="#2781F6">';
    document.title = 'Chatwoot';
    window.axios = { get: vi.fn() };
  });

  it('re-brands the dashboard and re-colours its accent ramp', async () => {
    window.axios.get.mockResolvedValue({ data: { payload: BRAND } });

    useWhiteLabel();
    await flushPromises();

    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/white_label'
    );
    expect(globalConfig.installationName).toBe('Clínica Sorriso');
    expect(globalConfig.logoThumbnail).toBe(BRAND.logo_thumbnail);
    expect(document.title).toBe('Clínica Sorriso');
    expect(themeStyle().textContent).toBe(BRAND.theme_css);
    expect(
      document.querySelector('meta[name="theme-color"]').getAttribute('content')
    ).toBe('#0F766E');
  });

  it('puts the installation brand back for an account without a white label', async () => {
    window.axios.get
      .mockResolvedValueOnce({ data: { payload: BRAND } })
      .mockResolvedValueOnce({ data: { payload: { enabled: false } } });

    useWhiteLabel();
    await flushPromises();
    accountId.value = 2;
    await nextTick();
    await flushPromises();

    expect(globalConfig.installationName).toBe('Chatwoot');
    expect(document.title).toBe('Chatwoot');
    expect(themeStyle()).toBeNull();
  });

  it('replaces the stylesheet the server rendered on the account domain', async () => {
    document.head.insertAdjacentHTML(
      'beforeend',
      '<style id="flow-white-label-theme">:root{--blue-9:1 2 3;}</style>'
    );
    window.axios.get.mockResolvedValue({ data: { payload: BRAND } });

    useWhiteLabel();
    await flushPromises();

    expect(document.querySelectorAll('#flow-white-label-theme')).toHaveLength(
      1
    );
    expect(themeStyle().textContent).toBe(BRAND.theme_css);
  });
});
