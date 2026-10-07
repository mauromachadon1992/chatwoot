# The CSV an administrator or agent downloads: the catalog, or the deals of a board with the
# filters it was viewed with. The first columns are the ones the importers read, so an export
# can be edited and imported back. Money is a plain decimal in the account's currency.
class Custom::Kanban::CsvExport
  LIMIT = 20_000

  PRODUCT_HEADERS = %w[name sku unit price active].freeze
  DEAL_HEADERS = %w[title contact_name contact_email contact_phone stage value expected_close_on assignee_email board source created_at].freeze

  def self.products(products)
    rows = products.limit(LIMIT).map do |product|
      [product.name, product.sku, product.unit, Custom::Kanban::MoneyParser.decimal(product.price_cents), product.active]
    end
    Custom::Kanban::CsvFile.generate(PRODUCT_HEADERS, rows)
  end

  # `cards` is already filtered and limited to boards the person can see.
  def self.deals(cards)
    rows = cards.includes(:contact, :stage, :assignee, :board).limit(LIMIT).map do |card|
      [card.title, card.contact.name, card.contact.email, card.contact.phone_number, card.stage.name,
       Custom::Kanban::MoneyParser.decimal(card.value_cents), card.expected_close_on&.iso8601, card.assignee&.email,
       card.board.name, card.source, card.created_at.utc.iso8601]
    end
    Custom::Kanban::CsvFile.generate(DEAL_HEADERS, rows)
  end

  # The rows that did not import, with why, in the same columns as the file plus the line.
  def self.import_errors(import)
    headers = %w[line error] + import.headers
    rows = import.errors_log.map { |error| [error['line'], error['messages'].join(' | ')] + error['cells'] }
    Custom::Kanban::CsvFile.generate(headers, rows)
  end
end
