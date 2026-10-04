# Prepended to DashboardController. On a white-labelled account's own domain the page is
# rendered with that account's brand from the first byte: login screen, title, favicon,
# theme colour and every logo, since all of them read `@global_config`, plus the accent
# colour ramp, which the layout inlines from `@white_label_theme_css`.
module Custom::DashboardController
  private

  def set_global_config
    super
    account = Custom::WhiteLabel::Resolver.account_for_host(request.host)
    return unless account

    resolver = Custom::WhiteLabel::Resolver.new(account)
    @global_config = @global_config.merge(resolver.dashboard_config)
    @white_label_theme_css = resolver.theme_css
  end
end
