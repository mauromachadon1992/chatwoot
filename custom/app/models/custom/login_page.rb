# The installation's own sign-in page, edited at Super Admin → Login page. One row.
#
# It brands every auth screen (login, SSO, forgot and reset password, signup, the MFA step)
# for the whole installation: identity (name, logos, icon, accent colour), the copy above the
# form in each language, a background (brand aurora, gradient or image, optionally animated)
# or a side panel, which buttons to hide and the links under the form. Nothing configured, or
# disabled, the screens are exactly Chatwoot's. An account's white label on its own domain
# wins over this (see Custom::DashboardController).
#
# Stored here rather than in installation_configs: the Enterprise plan reconciliation resets
# INSTALLATION_NAME, LOGO and BRAND_COLOR to Chatwoot's defaults every day on a `community`
# installation (Internal::ReconcilePlanConfigService).
class Custom::LoginPage < ApplicationRecord
  self.table_name = 'flow_login_pages'

  LAYOUTS = %w[background split].freeze
  BACKGROUNDS = %w[brand gradient image].freeze
  # Which animation suits which background: a drifting gradient, a slow zoom on a photo.
  ANIMATIONS = { 'none' => BACKGROUNDS, 'drift' => %w[brand gradient], 'zoom' => %w[image] }.freeze
  LOCALES = %w[pt_BR en es].freeze
  COPY_LIMITS = { 'title' => 60, 'subtitle' => 140, 'panel_message' => 160 }.freeze
  TOGGLES = %w[hide_signup hide_sso hide_google].freeze
  LINKS = %w[support_url terms_url privacy_url].freeze
  SUPPORT_LABEL_LIMIT = 40
  OVERLAY_RANGE = (0..80)

  # name => [accepted content types, max bytes]
  IMAGES = {
    logo: [%w[image/png image/jpeg image/svg+xml image/webp], 2.megabytes],
    logo_dark: [%w[image/png image/jpeg image/svg+xml image/webp], 2.megabytes],
    icon: [%w[image/png image/svg+xml], 1.megabyte],
    background_image: [%w[image/png image/jpeg image/webp], 5.megabytes]
  }.freeze

  COLOR_FORMAT = /\A#\h{6}\z/
  URL_FORMAT = %r{\A(https?://[^\s]+|mailto:[^\s@]+@[^\s@]+)\z}

  IMAGES.each_key { |image| has_one_attached image }

  # Set by the form when the background image is being removed, which only happens after save.
  attr_accessor :background_image_removed

  validates :layout, inclusion: { in: LAYOUTS }
  validates :background_kind, inclusion: { in: BACKGROUNDS }
  validates :animation, inclusion: { in: ANIMATIONS.keys }
  validates :overlay, inclusion: { in: OVERLAY_RANGE }
  validates :name, length: { maximum: 80 }
  validates :accent_color, format: { with: COLOR_FORMAT }, allow_blank: true
  validate :validate_background, :validate_copy, :validate_options, :validate_images

  # The page as stored, or an unsaved one with the defaults so the form always has something.
  def self.current
    first || new
  end

  # The page the auth screens wear, or nil when there is none to apply.
  def self.live
    find_by(enabled: true)
  end

  # Back to Chatwoot's screens: settings and images gone.
  def self.reset!
    first&.tap { |page| IMAGES.each_key { |image| page.public_send(image).purge } }&.destroy!
  end

  def option(key)
    options.to_h[key.to_s]
  end

  def toggle?(key)
    ActiveModel::Type::Boolean.new.cast(option(key)) == true
  end

  def copy_for(locale, field)
    copy.to_h.dig(locale.to_s, field.to_s).presence
  end

  # Relative, so it works on whichever host serves the login. Served by
  # LoginPageImagesController, which lets an SVG logo render (Active Storage does not).
  def image_path(image)
    attachment = public_send(image)
    return unless attachment.attached?

    Rails.application.routes.url_helpers.flow_login_page_image_path(name: image, version: attachment.blob_id)
  end

  # The accent ramp in the page's colour, contrast-checked (see Custom::WhiteLabel::Palette).
  def palette
    @palette ||= Custom::WhiteLabel::Palette.new(accent_color) if accent_color.to_s.match?(COLOR_FORMAT)
  end

  # Installation config keys the dashboard already reads, so the login, the title, the favicon
  # and the logos pick the identity up. Only what was set: an empty field keeps Chatwoot's.
  def global_config
    {
      'INSTALLATION_NAME' => name.presence,
      'LOGO' => image_path(:logo),
      'LOGO_DARK' => image_path(:logo_dark) || image_path(:logo),
      'LOGO_THUMBNAIL' => image_path(:icon),
      'BRAND_COLOR' => palette&.action_hex,
      'DISPLAY_MANIFEST' => (false if icon.attached?)
    }.compact
  end

  # What the auth screens need, as window.globalConfig.FLOW_LOGIN_PAGE.
  def client_payload
    {
      layout: layout,
      background: { kind: background_kind, css: background_css, image: image_path(:background_image),
                    animation: animation, overlay: overlay },
      copy: LOCALES.index_with { |locale| COPY_LIMITS.keys.index_with { |field| copy_for(locale, field) }.compact },
      options: TOGGLES.index_with { |key| toggle?(key) }
                      .merge(LINKS.index_with { |key| option(key).presence })
                      .merge('support_label' => option(:support_label).presence)
    }
  end

  # The CSS background for the brand aurora and gradients; an image is drawn from image_path.
  # The aurora reads the accent ramp, so it follows the page's colour and the theme.
  def background_css
    case background_kind
    when 'brand'
      [
        'radial-gradient(at 18% 12%, rgb(var(--blue-7)) 0, transparent 55%)',
        'radial-gradient(at 86% 82%, rgb(var(--blue-9) / 0.55) 0, transparent 50%)',
        'radial-gradient(at 70% 20%, rgb(var(--blue-5)) 0, transparent 45%)',
        'rgb(var(--blue-3))'
      ].join(', ')
    when 'gradient'
      stops = gradient.to_h.values_at('from', 'via', 'to').compact_blank
      "linear-gradient(#{gradient_angle}deg, #{stops.join(', ')})"
    end
  end

  def gradient_angle
    gradient.to_h['angle'].to_i.clamp(0, 360)
  end

  private

  def validate_background
    errors.add(:animation, :invalid) unless ANIMATIONS.fetch(animation, []).include?(background_kind)
    validate_gradient if background_kind == 'gradient'
    return unless background_kind == 'image'

    errors.add(:background_image, :blank) if !background_image.attached? || background_image_removed
  end

  def validate_gradient
    values = gradient.to_h
    %w[from to].each { |stop| errors.add(:gradient, :invalid) unless values[stop].to_s.match?(COLOR_FORMAT) }
    errors.add(:gradient, :invalid) if values['via'].present? && !values['via'].to_s.match?(COLOR_FORMAT)
    errors.add(:gradient, :invalid) unless values['angle'].to_s.match?(/\A\d{1,3}\z/) && values['angle'].to_i <= 360
  end

  def validate_copy
    copy.to_h.each do |locale, fields|
      next errors.add(:copy, :invalid) unless LOCALES.include?(locale) && fields.is_a?(Hash)

      fields.each do |field, text|
        limit = COPY_LIMITS[field]
        next errors.add(:copy, :invalid) unless limit

        errors.add(:"copy_#{locale}_#{field}", :too_long, count: limit) if text.to_s.length > limit
      end
    end
  end

  def validate_options
    LINKS.each do |key|
      value = option(key)
      errors.add(key.to_sym, :invalid) if value.present? && !value.to_s.match?(URL_FORMAT)
    end
    label = option(:support_label).to_s
    errors.add(:support_label, :too_long, count: SUPPORT_LABEL_LIMIT) if label.length > SUPPORT_LABEL_LIMIT
  end

  def validate_images
    IMAGES.each do |image, (types, max_size)|
      attachment = public_send(image)
      next unless attachment.attached? && attachment_changes[image.to_s]

      errors.add(image, :invalid) unless types.include?(attachment.content_type)
      errors.add(image, :too_large) if attachment.byte_size > max_size
    end
  end
end
