import { quoteLines, renderQuote, replyDraftKey } from '../quote';

const options = {
  money: cents => `R$ ${(cents / 100).toFixed(2).replace('.', ',')}`,
  locale: 'pt_BR',
  unitLabel: unit => ({ sc: 'sc', un: 'un' })[unit],
  discountLabel: percent => `${percent}% de desconto`,
};

describe('quoteLines', () => {
  it('writes one line per product, with the discount when there is one', () => {
    const lines = quoteLines(
      [
        {
          name: 'Cimento CP II',
          unit: 'sc',
          quantity: '2.0',
          discount_percent: '0.0',
          total_cents: 7980,
        },
        {
          name: 'Areia média',
          unit: 'un',
          quantity: '1.5',
          discount_percent: '10.0',
          total_cents: 13500,
        },
      ],
      options
    );

    expect(lines).toBe(
      '• 2 sc Cimento CP II — R$ 79,80\n• 1,5 un Areia média — R$ 135,00 (10% de desconto)'
    );
  });
});

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
