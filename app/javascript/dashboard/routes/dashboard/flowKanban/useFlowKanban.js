import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { formatDistanceToNow, fromUnixTime } from 'date-fns';
import { enUS, es, ptBR } from 'date-fns/locale';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { getInboxIconByType } from 'dashboard/helper/inbox';

const DATE_LOCALES = { en: enUS, es, pt_BR: ptBR };

export const STAGE_COLORS = [
  '#3B82F6',
  '#8B5CF6',
  '#EC4899',
  '#F59E0B',
  '#10B981',
  '#14B8A6',
  '#EF4444',
  '#6B7280',
];

// Mirrors Custom::Kanban::CardFields::ALL; a super admin picks them per account.
export const CARD_FIELDS = [
  'contact',
  'conversations',
  'assignee',
  'time_in_stage',
  'last_activity',
];

export function useFlowKanban() {
  const { locale } = useI18n();
  const { currentAccount } = useAccount();
  const accountId = useMapGetter('getCurrentAccountId');
  const inboxes = useMapGetter('inboxes/getInboxes');

  const cardFields = computed(() => {
    const chosen = currentAccount.value?.settings?.flow_kanban_card_fields;
    return new Set(Array.isArray(chosen) ? chosen : CARD_FIELDS);
  });

  const relativeTime = timestamp =>
    timestamp
      ? formatDistanceToNow(fromUnixTime(timestamp), {
          addSuffix: true,
          locale: DATE_LOCALES[locale.value] || enUS,
        })
      : '';

  // The inbox store only holds the inboxes this user can access, so a conversation whose
  // inbox is missing here is one the user cannot open: it is shown, but not linked.
  const inboxFor = inboxId => inboxes.value.find(inbox => inbox.id === inboxId);

  const inboxIcon = inbox =>
    inbox
      ? getInboxIconByType(inbox.channel_type, inbox.medium, 'line')
      : 'i-lucide-lock';

  const conversationPath = displayId =>
    frontendURL(conversationUrl({ accountId: accountId.value, id: displayId }));

  const contactPath = contactId =>
    frontendURL(`accounts/${accountId.value}/contacts/${contactId}`);

  const boardPath = () => frontendURL(`accounts/${accountId.value}/kanban`);

  return {
    cardFields,
    relativeTime,
    inboxFor,
    inboxIcon,
    conversationPath,
    contactPath,
    boardPath,
  };
}
