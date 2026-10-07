import { formatQuantity } from './money';

// The placeholders a quote message may use, in the order the settings page offers them.
export const QUOTE_PLACEHOLDERS = [
  'contact',
  'deal',
  'items',
  'total',
  'agent',
];

// WhatsApp cuts a text message at 4,096 characters; the dialog warns before that.
export const QUOTE_MAX_LENGTH = 4096;

// One line per product: "2 sc Cimento CP II 50kg — R$ 79,80", with the discount when there is one.
export const quoteLines = (
  items,
  { money, locale, unitLabel, discountLabel }
) =>
  items
    .map(item => {
      const quantity = formatQuantity(item.quantity, locale);
      const unit = unitLabel(item.unit);
      const discount =
        Number(item.discount_percent) > 0
          ? ` (${discountLabel(formatQuantity(item.discount_percent, locale))})`
          : '';
      return `• ${quantity} ${unit} ${item.name} — ${money(item.total_cents)}${discount}`;
    })
    .join('\n');

// Fills `{{placeholder}}` with the deal's values; an unknown placeholder stays as written, so a
// typo shows in the preview instead of vanishing.
export const renderQuote = (template, values) =>
  String(template || '').replace(/\{\{\s*(\w+)\s*\}\}/g, (match, name) =>
    Object.prototype.hasOwnProperty.call(values, name)
      ? String(values[name] ?? '')
      : match
  );

// Where the conversation's reply box keeps its draft (ReplyBox#getDraftKey): by the conversation's
// display_id, the id the dashboard uses everywhere. The card's `conversations[].display_id` is
// that id; the internal id is not sent to the dashboard at all.
export const replyDraftKey = displayId => `draft-${displayId}-REPLY`;

// A placeholder as the agent types it: {{contact}}. Written here, not in a template, where the
// double braces would be read as an interpolation.
export const placeholderText = name => `{{${name}}}`;
