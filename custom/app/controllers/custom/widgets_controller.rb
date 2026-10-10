# Prepended to WidgetsController. The widget's "Powered by" line and title follow the brand of
# the account that owns the inbox. set_global_config runs before the inbox is known, so the
# override happens once set_web_widget has loaded it.
module Custom::WidgetsController
  private

  def set_web_widget
    super
    account = @web_widget&.inbox&.account
    return unless account&.white_label_enabled?

    config = Custom::WhiteLabel::Resolver.new(account).dashboard_config
    @global_config = @global_config.merge(config.slice('INSTALLATION_NAME', 'BRAND_NAME', 'WIDGET_BRAND_URL', 'LOGO_THUMBNAIL'))
  end
end
