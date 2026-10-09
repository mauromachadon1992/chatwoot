import { renderQuote, replyDraftKey } from '../quote';

describe('renderQuote', () => {
  it('fills the placeholders, with or without spaces inside the braces', () => {
    expect(
      renderQuote('Olá {{contact}}! Total: {{ total }}', {
        contact: 'Maria',
        total: 'R$ 10,00',
      })
    ).toBe('Olá Maria! Total: R$ 10,00');
  });

  it('keeps an unknown placeholder as written, so the preview shows the typo', () => {
    expect(renderQuote('Oi {{contato}}', { contact: 'Maria' })).toBe(
      'Oi {{contato}}'
    );
  });

  it('writes an empty value as nothing', () => {
    expect(renderQuote('Agente: {{agent}}.', { agent: null })).toBe(
      'Agente: .'
    );
  });
});

describe('replyDraftKey', () => {
  it('is the reply box draft of the conversation, by its display id', () => {
    // A card carries { display_id: 42 }: the reply box of /conversations/42 reads draft-42-REPLY.
    expect(replyDraftKey(42)).toBe('draft-42-REPLY');
  });

  it('never takes an internal id: the card only holds the display id', () => {
    const conversation = { display_id: 42, inbox_id: 3 };

    expect(replyDraftKey(conversation.display_id)).not.toBe(
      replyDraftKey(conversation.inbox_id)
    );
    expect(replyDraftKey(conversation.display_id)).toBe('draft-42-REPLY');
  });
});
