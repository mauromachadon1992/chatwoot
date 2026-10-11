import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// The installation's own sign-in page (Super Admin → Login page), rendered by the server into
// window.globalConfig.FLOW_LOGIN_PAGE only while it is live and no account white label owns
// the host. Absent, every auth screen is exactly Chatwoot's.
export function useLoginPage() {
  const { locale } = useI18n();
  const page = window.globalConfig?.FLOW_LOGIN_PAGE || null;

  // Copy for the screen's language only: an empty field falls back to Chatwoot's own text.
  const copy = computed(() => page?.copy?.[locale.value] || {});

  return {
    page,
    enabled: Boolean(page),
    copy,
    // Hiding only hides: callers combine this with their own "is it configured" check.
    hidden: key => Boolean(page?.options?.[`hide_${key}`]),
  };
}
