# A super admin can give an account its own brand: the dashboard, the login page on the
# account's own domain, the browser tab, outgoing email, the CSAT page and the widget's
# "Powered by" line. Everything lives in `accounts.settings` (keys below) plus four image
# attachments, so it needs no column and no change to the settings JSON schema.
module Custom::WhiteLabel
  SETTINGS = %w[
    white_label_enabled
    white_label_name
    white_label_color
    white_label_domain
    white_label_terms_url
    white_label_privacy_url
    white_label_powered_by_name
    white_label_powered_by_url
  ].freeze

  # name => [accepted content types, max bytes]
  IMAGES = {
    white_label_logo: [%w[image/png image/jpeg image/svg+xml image/webp], 2.megabytes],
    white_label_logo_dark: [%w[image/png image/jpeg image/svg+xml image/webp], 2.megabytes],
    white_label_icon: [%w[image/png image/svg+xml], 1.megabyte],
    # Email clients render no vector format, so this one is raster only.
    white_label_logo_email: [%w[image/png image/jpeg image/gif], 2.megabytes]
  }.freeze

  COLOR_FORMAT = /\A#\h{6}\z/
  DOMAIN_FORMAT = /\A(?=.{4,253}\z)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/
  URL_FORMAT = %r{\Ahttps?://[^\s]+\z}

  def self.normalize_domain(value)
    value.to_s.strip.downcase.sub(%r{\Ahttps?://}, '').split('/').first.to_s.delete_suffix('.')
  end
end
