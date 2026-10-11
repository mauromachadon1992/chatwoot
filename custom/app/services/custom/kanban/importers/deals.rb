# Deals, into one board. The contact is found by e-mail or phone (and created when neither is
# known), which is also what makes a re-import safe: a deal with the same title for the same
# contact on the board is skipped, not made again.
class Custom::Kanban::Importers::Deals < Custom::Kanban::Importers::Base
  PHONE_FORMAT = /\A\+[1-9]\d{1,14}\z/

  def self.aliases
    { title: %w[title titulo negocio deal],
      contact_name: %w[contact_name contact contato nome cliente name],
      contact_email: %w[contact_email email e_mail],
      contact_phone: %w[contact_phone phone telefone celular whatsapp],
      stage: %w[stage etapa estagio],
      value: %w[value valor],
      expected_close_on: %w[expected_close_on close_date previsao previsao_de_fechamento fechamento data_de_fechamento],
      assignee_email: %w[assignee_email assignee responsavel agente] }
  end

  def initialize(import)
    super
    @board = Custom::Kanban::Board.find(import.board_id)
    @stages = @board.stages.to_a
  end

  def analyze(values)
    attrs, messages = read(values)
    return invalid(messages) if messages.any?

    messages = card_problems(attrs)
    return invalid(messages) if messages.any?

    verdict_for(attrs)
  end

  def apply(verdict)
    attrs = verdict.attrs
    contact = find_contact(attrs[:contact]) || @account.contacts.create!(attrs[:contact].compact)
    Custom::Kanban::Card.create!(attrs.except(:contact).merge(account: @account, board: @board, contact: contact, created_by: @import.user))
  end

  private

  # The deal's attributes from a row, and what is wrong with it.
  def read(values)
    contact, contact_messages = contact_from(values)
    stage, stage_message = stage_from(values[:stage])
    value, value_message = value_from(values[:value])
    close_on, close_message = close_date_from(values[:expected_close_on])
    assignee, assignee_message = assignee_from(values[:assignee_email])
    messages = contact_messages + [stage_message, value_message, close_message, assignee_message].compact
    attrs = { contact: contact, stage_id: stage&.id, value_cents: value, expected_close_on: close_on, assignee_id: assignee&.id,
              title: values[:title] || contact.values_at(:name, :phone_number, :email).compact.first }
    [attrs, messages]
  end

  def verdict_for(attrs)
    key = "#{attrs[:contact][:email]&.downcase || attrs[:contact][:phone_number]}|#{attrs[:title].downcase}"
    return invalid(t(:repeated_in_file)) if repeat?(key)

    contact = find_contact(attrs[:contact])
    duplicate = contact && Custom::Kanban::Card.where(board: @board, contact: contact).exists?(['lower(title) = ?', attrs[:title].downcase])
    Verdict.new(action: duplicate ? :skip : :create, attrs: attrs, messages: [])
  end

  def find_contact(data)
    scope = @account.contacts
    (data[:email] && scope.find_by('lower(email) = ?', data[:email].downcase)) ||
      (data[:phone_number] && scope.find_by(phone_number: data[:phone_number]))
  end

  def contact_from(values)
    email = values[:contact_email]&.downcase
    phone = normalize_phone(values[:contact_phone])
    messages = [email_problem(email), phone_problem(values[:contact_phone], phone),
                (t(:contact_missing) if email.nil? && values[:contact_phone].nil?)].compact
    [{ name: values[:contact_name], email: email, phone_number: phone }, messages]
  end

  def email_problem(email)
    t(:email_invalid) if email && !email.match?(Devise.email_regexp)
  end

  def phone_problem(given, phone)
    t(:phone_invalid) if given && !phone.match?(PHONE_FORMAT)
  end

  def value_from(text)
    return [0, nil] if text.nil?

    cents = Custom::Kanban::MoneyParser.cents(text)
    cents ? [cents, nil] : [nil, t(:value_invalid)]
  end

  def normalize_phone(text)
    return nil if text.nil?

    digits = text.gsub(/[\s().-]/, '')
    digits.start_with?('+') ? digits : "+#{digits}"
  end

  def stage_from(name)
    return [@stages.find(&:stage_type_open?) || @stages.first, nil] if name.nil?

    stage = @stages.find { |candidate| candidate.name.casecmp?(name) }
    stage ? [stage, nil] : [nil, t(:stage_unknown, name: name, stages: @stages.map(&:name).join(', '))]
  end

  def close_date_from(text)
    return [nil, nil] if text.nil?

    date = parse_date(text)
    date ? [date, nil] : [nil, t(:date_invalid)]
  end

  def parse_date(text)
    return Date.iso8601(text) if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    return Date.strptime(text, '%d/%m/%Y') if text.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z})
  rescue Date::Error
    nil
  end

  def assignee_from(email)
    return [nil, nil] if email.nil?

    user = @account.users.find_by('lower(users.email) = ?', email.downcase)
    user ? [user, nil] : [nil, t(:assignee_unknown, email: email)]
  end

  # The model's own rules (title length, value ceiling, close date range), run without saving.
  def card_problems(attrs)
    contact = find_contact(attrs[:contact]) || @account.contacts.new(attrs[:contact].compact)
    card = Custom::Kanban::Card.new(attrs.except(:contact).merge(account: @account, board: @board, contact: contact))
    card.valid?
    card.errors.reject { |error| error.attribute == :contact && contact.new_record? }.map(&:full_message)
  end
end
