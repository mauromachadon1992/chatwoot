/* global axios */
import { watch } from 'vue';
import { useStore } from 'vuex';
import { useAccount } from 'dashboard/composables/useAccount';

// After login the account is known, so the dashboard re-brands itself for it on any domain:
// the global config the whole app reads (name, logos, links), the tab title, the favicon and
// the theme colour. Switching to an account without a white label puts everything back.
// On the account's own domain the server already rendered the brand; this keeps it in sync.

const CONFIG_KEYS = {
  installationName: 'installation_name',
  brandName: 'brand_name',
  widgetBrandURL: 'widget_brand_url',
  logo: 'logo',
  logoDark: 'logo_dark',
  logoThumbnail: 'logo_thumbnail',
  termsURL: 'terms_url',
  privacyURL: 'privacy_url',
};

const BRAND_ICON_ID = 'flow-white-label-icon';
// Same id the server uses when it renders the account's own domain, so this replaces it.
const THEME_STYLE_ID = 'flow-white-label-theme';

const fetchWhiteLabel = accountId =>
  axios.get(`/api/v1/accounts/${accountId}/white_label`);

export function useWhiteLabel() {
  const store = useStore();
  const { accountId } = useAccount();
  const config = store?.state?.globalConfig;
  // No global config to re-brand (a store mocked in a spec, an embedded view): leave the page alone.
  if (!config) return;

  const original = {
    config: Object.fromEntries(
      Object.keys(CONFIG_KEYS).map(key => [key, config[key]])
    ),
    title: document.title,
    themeColor: document
      .querySelector('meta[name="theme-color"]')
      ?.getAttribute('content'),
    // The installation's own favicons; the unread badge swaps these, so they go away while a
    // brand icon is shown and come back with the installation brand.
    favicons: [...document.querySelectorAll('link.favicon')],
  };

  const setThemeColor = color => {
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta && color) meta.setAttribute('content', color);
  };

  const setBrandIcon = href => {
    document.getElementById(BRAND_ICON_ID)?.remove();
    if (!href) {
      original.favicons.forEach(link => document.head.appendChild(link));
      return;
    }
    original.favicons.forEach(link => link.remove());
    const link = document.createElement('link');
    link.id = BRAND_ICON_ID;
    link.rel = 'icon';
    link.href = href;
    document.head.appendChild(link);
  };

  // The accent ramp in the brand's colour (`--blue-1..12`, which `n-brand` reads), built by
  // the server so the contrast rules live in one place.
  const setThemeStyle = css => {
    let style = document.getElementById(THEME_STYLE_ID);
    if (!css) {
      style?.remove();
      return;
    }
    if (!style) {
      style = document.createElement('style');
      style.id = THEME_STYLE_ID;
      document.head.appendChild(style);
    }
    style.textContent = css;
  };

  const restore = () => {
    Object.assign(config, original.config);
    document.title = original.title;
    setThemeColor(original.themeColor);
    setBrandIcon(null);
    setThemeStyle(null);
  };

  const apply = brand => {
    Object.entries(CONFIG_KEYS).forEach(([key, field]) => {
      config[key] = brand[field] || original.config[key];
    });
    if (brand.installation_name) document.title = brand.installation_name;
    setThemeColor(brand.brand_color);
    setBrandIcon(brand.logo_thumbnail);
    setThemeStyle(brand.theme_css);
  };

  watch(
    accountId,
    async id => {
      if (!id) return;
      try {
        const { data } = await fetchWhiteLabel(id);
        if (id !== accountId.value) return;
        if (data.payload.enabled) apply(data.payload);
        else restore();
      } catch {
        restore();
      }
    },
    { immediate: true }
  );
}
