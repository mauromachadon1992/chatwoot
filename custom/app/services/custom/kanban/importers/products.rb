# Products: matched by SKU, or by name when the row has no SKU, so importing the same file twice
# changes nothing the second time.
class Custom::Kanban::Importers::Products < Custom::Kanban::Importers::Base
  def self.aliases
    { name: %w[name nome produto descricao description],
      sku: %w[sku codigo cod code ref referencia],
      unit: %w[unit unidade un],
      price: %w[price preco valor valor_unitario] }
  end

  def self.required_fields
    ['name']
  end

  def analyze(values)
    attrs = attributes_from(values)
    messages = problems(attrs, values)
    return invalid(messages) if messages.any?
    return invalid(t(:repeated_in_file)) if repeat?(attrs[:sku] ? "sku:#{attrs[:sku].downcase}" : "name:#{attrs[:name].downcase}")

    existing = find_existing(attrs)
    return Verdict.new(action: :create, attrs: attrs, messages: []) unless existing

    changed = attrs.any? { |key, value| existing.public_send(key) != value }
    Verdict.new(action: changed ? :update : :skip, attrs: attrs.merge(id: existing.id), messages: [])
  end

  def apply(verdict)
    attrs = verdict.attrs
    if verdict.action == :create
      Custom::Kanban::Product.create!(attrs.merge(account: @account))
    else
      Custom::Kanban::Product.where(account: @account).find(attrs[:id]).update!(attrs.except(:id))
    end
  end

  private

  def attributes_from(values)
    price = values[:price].nil? ? 0 : Custom::Kanban::MoneyParser.cents(values[:price])
    { name: values[:name], sku: values[:sku], unit: (values[:unit] || 'un').downcase, price_cents: price }
  end

  def problems(attrs, values)
    [
      (t(:name_blank) if attrs[:name].blank?),
      (t(:name_too_long, max: 160) if attrs[:name].to_s.length > 160),
      (t(:sku_too_long, max: 60) if values[:sku].to_s.length > 60),
      (t(:unit_unknown, units: Custom::Kanban::Product::UNITS.join(', ')) unless Custom::Kanban::Product::UNITS.include?(attrs[:unit])),
      (t(:price_invalid) if attrs[:price_cents].nil?)
    ].compact
  end

  def find_existing(attrs)
    scope = Custom::Kanban::Product.where(account: @account)
    return scope.find_by('lower(sku) = ?', attrs[:sku].downcase) if attrs[:sku]

    scope.where(sku: nil).find_by('lower(name) = ?', attrs[:name].downcase)
  end
end
