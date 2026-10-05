# Prepended to DashboardController, which renders the Vue shell for both the sign-in screens
# and the dashboard, so everything here lands from the first byte (all of it reads
# `@global_config`; the layout inlines the colour ramps).
#
# Precedence:
# 1. An account's white label on its own domain (login, title, favicon, logos, accent ramp).
# 2. The installation login page (Super Admin → Login page): its identity and accent ramp for
#    the whole installation, and the sign-in screens' layout as FLOW_LOGIN_PAGE.
# 3. Chatwoot's own.
#
# The installation ramp gets its own <style>, so an account's white label applied after login
# (useWhiteLabel) sits on top of it and goes away without taking it along.
module Custom::DashboardController
  private

  def set_global_config
    super
    account = Custom::WhiteLabel::Resolver.account_for_host(request.host)
    account ? apply_account_white_label(account) : apply_login_page(Custom::LoginPage.live)
  end

  def apply_account_white_label(account)
    resolver = Custom::WhiteLabel::Resolver.new(account)
    @global_config = @global_config.merge(resolver.dashboard_config)
    @white_label_theme_css = resolver.theme_css
  end

  def apply_login_page(page)
    return unless page

    @global_config = @global_config.merge(page.global_config).merge('FLOW_LOGIN_PAGE' => page.client_payload)
    @flow_installation_theme_css = page.palette&.to_css
  end
end
