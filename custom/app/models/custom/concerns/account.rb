# Included through `Account.include_mod_with('Concerns::Account')`. The settings jsonb accepts
# extra keys, so the Flow additions need no column and no schema change.
module Custom::Concerns::Account
  extend ActiveSupport::Concern

  included do
    Custom::WhiteLabel::IMAGES.each_key { |name| has_one_attached name }

    validate :validate_white_label
    before_save :normalize_white_label
  end

  def flow_kanban_card_fields
    stored = settings&.dig(Custom::Kanban::CardFields::SETTINGS_KEY)
    stored.nil? ? Custom::Kanban::CardFields::ALL.dup : stored
  end

  def flow_kanban_card_fields=(fields)
    self.settings = (settings || {}).merge(
      Custom::Kanban::CardFields::SETTINGS_KEY => Custom::Kanban::CardFields::ALL & Array(fields).compact_blank
    )
  end

  def white_label_enabled?
    ActiveModel::Type::Boolean.new.cast(settings&.dig('white_label_enabled')) == true
  end
  # Read by FlowWhiteLabelField on the super admin account page.
  alias flow_white_label white_label_enabled?

  def white_label_value(key)
    settings&.dig(key.to_s).presence
  end

  # Readers for every key, so validation errors on them can be built and shown like on columns.
  (Custom::WhiteLabel::SETTINGS - %w[white_label_enabled]).each do |key|
    define_method(key) { white_label_value(key) }
  end

  def assign_white_label(attributes)
    values = attributes.to_h.slice(*Custom::WhiteLabel::SETTINGS).transform_values { |value| value.is_a?(String) ? value.strip : value }
    values['white_label_enabled'] = ActiveModel::Type::Boolean.new.cast(values['white_label_enabled']) if values.key?('white_label_enabled')
    self.settings = (settings || {}).merge(values)
  end

  # Relative, so the dashboard uses it on whichever domain it is served from. Served by
  # WhiteLabelImagesController, which unlike Active Storage lets an SVG render.
  def white_label_image_path(name)
    image = public_send(name)
    return nil unless image.attached?

    Rails.application.routes.url_helpers.flow_white_label_image_path(account_id: id, name: name, version: image.blob_id)
  end

  # Absolute, for email and the CSAT page, which are opened outside the dashboard.
  def white_label_image_url(name)
    path = white_label_image_path(name)
    "#{ENV.fetch('FRONTEND_URL', '').chomp('/')}#{path}" if path
  end

  private

  def normalize_white_label
    return unless settings.is_a?(Hash) && settings.key?('white_label_domain')

    settings['white_label_domain'] = Custom::WhiteLabel.normalize_domain(settings['white_label_domain']).presence
  end

  def validate_white_label
    validate_white_label_settings
    validate_white_label_domain
    validate_white_label_images
  end

  def validate_white_label_settings
    color = white_label_value(:white_label_color)
    errors.add(:white_label_color, :invalid) if color && !color.match?(Custom::WhiteLabel::COLOR_FORMAT)
    %i[white_label_terms_url white_label_privacy_url white_label_powered_by_url].each do |key|
      url = white_label_value(key)
      errors.add(key, :invalid) if url && !url.match?(Custom::WhiteLabel::URL_FORMAT)
    end
    errors.add(:white_label_name, :too_long, count: 80) if white_label_value(:white_label_name).to_s.length > 80
  end

  # A domain serves one brand: not the installation's own host, not a help center portal,
  # and not another account.
  def validate_white_label_domain
    domain = Custom::WhiteLabel.normalize_domain(white_label_value(:white_label_domain))
    return if domain.blank?
    return errors.add(:white_label_domain, :invalid) unless domain.match?(Custom::WhiteLabel::DOMAIN_FORMAT)

    taken = domain == URI.parse(ENV.fetch('FRONTEND_URL', '')).host ||
            Portal.exists?(custom_domain: domain) ||
            Account.where.not(id: id).exists?(["settings->>'white_label_domain' = ?", domain])
    errors.add(:white_label_domain, :taken) if taken
  end

  def validate_white_label_images
    Custom::WhiteLabel::IMAGES.each do |name, (types, max_size)|
      image = public_send(name)
      next unless image.attached? && attachment_changes[name.to_s]

      errors.add(name, :invalid) unless types.include?(image.content_type)
      errors.add(name, :too_large) if image.byte_size > max_size
    end
  end
end
