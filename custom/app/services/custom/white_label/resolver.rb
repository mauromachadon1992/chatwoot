# Turns an account's white label into the installation config keys the dashboard already reads
# (`window.globalConfig`), so the login page, the title, the favicon and every logo pick it up
# without the dashboard knowing white label exists.
class Custom::WhiteLabel::Resolver
  def self.account_for_host(host)
    domain = Custom::WhiteLabel.normalize_domain(host)
    return if domain.blank? || domain == URI.parse(ENV.fetch('FRONTEND_URL', '')).host

    account = Account.where("settings->>'white_label_domain' = ?", domain).first
    account if account&.white_label_enabled?
  end

  def initialize(account)
    @account = account
  end

  # Only what the account set: an empty field keeps the installation's value. DISPLAY_MANIFEST
  # goes off because it is what renders the installation's own favicons and upgrade notices.
  def dashboard_config
    return {} unless @account&.white_label_enabled?

    {
      'INSTALLATION_NAME' => value(:white_label_name),
      'BRAND_NAME' => value(:white_label_powered_by_name) || value(:white_label_name),
      'WIDGET_BRAND_URL' => value(:white_label_powered_by_url),
      'BRAND_COLOR' => palette&.action_hex,
      'LOGO' => image(:white_label_logo),
      'LOGO_DARK' => image(:white_label_logo_dark) || image(:white_label_logo),
      'LOGO_THUMBNAIL' => image(:white_label_icon),
      'TERMS_URL' => value(:white_label_terms_url),
      'PRIVACY_URL' => value(:white_label_privacy_url),
      'DISPLAY_MANIFEST' => false
    }.compact
  end

  # What the dashboard needs to re-brand itself after login, on the installation's own domain.
  def dashboard_payload
    return { enabled: false } unless @account&.white_label_enabled?

    config = dashboard_config
    {
      enabled: true,
      installation_name: config['INSTALLATION_NAME'],
      brand_name: config['BRAND_NAME'],
      widget_brand_url: config['WIDGET_BRAND_URL'],
      brand_color: config['BRAND_COLOR'],
      logo: config['LOGO'],
      logo_dark: config['LOGO_DARK'],
      logo_thumbnail: config['LOGO_THUMBNAIL'],
      terms_url: config['TERMS_URL'],
      privacy_url: config['PRIVACY_URL'],
      theme_css: theme_css
    }.compact
  end

  # The accent ramp in the account's colour, as a stylesheet (see Custom::WhiteLabel::Palette).
  def theme_css
    palette&.to_css if @account&.white_label_enabled?
  end

  private

  def palette
    color = value(:white_label_color)
    @palette ||= Custom::WhiteLabel::Palette.new(color) if color&.match?(Custom::WhiteLabel::COLOR_FORMAT)
  end

  def value(key)
    @account.white_label_value(key)
  end

  def image(name)
    @account.white_label_image_path(name)
  end
end
