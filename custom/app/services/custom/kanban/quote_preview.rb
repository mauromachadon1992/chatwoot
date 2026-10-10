# The quote message of a deal, built on the server so the dashboard and an agent's HTTP tool read the same text and the same
# totals (capability `deal.quote`). The template is the account's own (Settings > Kanban) or the default in the reader's
# language; `{{contact}}`, `{{deal}}`, `{{items}}`, `{{total}}` and `{{agent}}` are filled the way the dashboard always did.
# An unknown placeholder stays as written, so a typo shows in the preview instead of vanishing.
class Custom::Kanban::QuotePreview
  MAX_LENGTH = 4096 # WhatsApp cuts a text message here
  PLACEHOLDER = /\{\{\s*(\w+)\s*\}\}/
  SYMBOLS = { 'BRL' => 'R$', 'USD' => '$', 'EUR' => '€', 'GBP' => '£', 'ARS' => '$', 'MXN' => '$', 'COP' => '$', 'PEN' => 'S/',
              'UYU' => '$' }.freeze
  NBSP = [0xA0].pack('U').freeze
  LANGUAGES = %w[en es].freeze

  def initialize(card, account:, user:, locale: nil)
    @card = card
    @account = account
    @user = user
    @locale = Custom::Kanban::QuotePreview.supported_locale(locale, account)
  end

  # The asked-for locale, else the account's; anything we have no words for reads in English.
  def self.supported_locale(requested, account)
    [requested, account.locale].each do |value|
      code = value.to_s.tr('-', '_')
      language = code.split('_').first
      return 'pt_BR' if language == 'pt'
      return language if LANGUAGES.include?(language)
    end
    'en'
  end

  def as_json(*)
    text = I18n.with_locale(@locale) { render }
    { text: text, length: text.length, too_long: text.length > MAX_LENGTH, total_cents: @card.value_cents, currency: currency,
      locale: @locale, lines: @card.items.map { |item| line_data(item) } }
  end

  private

  def render
    values = { 'contact' => @card.contact&.name.to_s, 'deal' => @card.title.to_s, 'items' => item_lines, 'total' => money(@card.value_cents),
               'agent' => @user&.name.to_s }
    template.gsub(PLACEHOLDER) { |match| values.fetch(Regexp.last_match(1), match) }
  end

  def template
    @account.flow_kanban_quote_template.presence || I18n.t('flow_kanban.quote.default_template')
  end

  def item_lines
    @card.items.map do |item|
      discount = item.discount_percent.to_d.positive? ? " (#{I18n.t('flow_kanban.quote.discount', percent: quantity(item.discount_percent))})" : ''
      "• #{quantity(item.quantity)} #{I18n.t("flow_kanban.quote.units.#{item.unit}")} #{item.name} — #{money(item.total_cents)}#{discount}"
    end.join("\n")
  end

  def line_data(item)
    { name: item.name, unit: item.unit, quantity: item.quantity.to_d.to_s('F'), unit_price_cents: item.unit_price_cents,
      discount_percent: item.discount_percent.to_d.to_s('F'), total_cents: item.total_cents }
  end

  def currency
    @account.flow_kanban_currency
  end

  def separators
    @locale == 'en' ? { delimiter: ',', separator: '.' } : { delimiter: '.', separator: ',' }
  end

  # "R$ 1.234,56" in Portuguese and Spanish, "R$1,234.56" in English; cents stay integers until here.
  def money(cents)
    number = ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', cents.to_i / 100.0), **separators)
    symbol = SYMBOLS.fetch(currency, currency)
    @locale == 'en' ? "#{symbol}#{number}" : "#{symbol}#{NBSP}#{number}"
  end

  # Up to three decimals, trailing zeros dropped: 2,5 m³; 12 sc; 0,125 t.
  def quantity(value)
    text = format('%.3f', value.to_d).sub(/\.?0+\z/, '')
    ActiveSupport::NumberHelper.number_to_delimited(text, **separators)
  end
end
