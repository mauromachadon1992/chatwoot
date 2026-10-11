# Super Admin → Login page: the installation's own sign-in screens (see Custom::LoginPage).
#
# Served under /super_admin with the super admin's session and layout, but namespaced
# FlowAdmin: Administrate builds the super admin sidebar from every `super_admin/*`
# controller, so the sidebar entry is added by hand (super_admin/application/_flow_navigation).
class FlowAdmin::LoginPagesController < SuperAdmin::ApplicationController
  # Signing out of the dashboard ends every Devise scope, so a form left open in another tab
  # posts a token that no longer exists. Back to the form with a reason, not Rails' error page.
  rescue_from ActionController::InvalidAuthenticityToken do
    redirect_to super_admin_login_page_path, alert: t('flow_login_page.super_admin.session_expired')
  end

  helper_method :namespace, :default_titles

  def show
    @page = Custom::LoginPage.current
  end

  # The layout's sidebar lists the resources of this namespace: keep it the super admin's.
  def namespace
    'super_admin'
  end

  def update
    @page = Custom::LoginPage.current
    assign_page
    assign_images

    if @page.save
      purge_removed_images
      redirect_to super_admin_login_page_path, notice: t('flow_login_page.super_admin.saved')
    else
      flash.now[:alert] = t('flow_login_page.super_admin.not_saved')
      render :show, status: :unprocessable_content
    end
  end

  # Restore default: Chatwoot's screens again, settings and images gone.
  def destroy
    Custom::LoginPage.reset!
    redirect_to super_admin_login_page_path, notice: t('flow_login_page.super_admin.restored')
  end

  # What the dashboard makes of an accent colour, for the live preview (same palette code).
  def palette
    color = params[:color].to_s.strip
    return head :unprocessable_content unless color.match?(Custom::LoginPage::COLOR_FORMAT)

    render json: Custom::WhiteLabel::Palette.new(color).preview
  end

  # Chatwoot's own login title per language, so the preview shows what an empty field gives.
  def default_titles
    @default_titles ||= Custom::LoginPage::LOCALES.index_with do |locale|
      file = Rails.root.join("app/javascript/dashboard/i18n/locale/#{locale}/login.json")
      JSON.parse(file.read).dig('LOGIN', 'TITLE') if file.exist?
    rescue JSON::ParserError
      nil
    end
  end

  private

  def page_params
    params.fetch(:login_page, {})
  end

  def assign_page
    scalars = page_params.permit(:enabled, :name, :accent_color, :layout, :background_kind, :animation, :overlay)
    @page.assign_attributes(scalars.to_h.transform_values { |value| value.is_a?(String) ? value.strip : value })
    @page.gradient = cleaned(page_params.fetch(:gradient, {}).permit(:from, :via, :to, :angle).to_h)
    @page.copy = assigned_copy
    @page.options = assigned_options
  end

  # Only filled fields are kept, so an empty language falls back to Chatwoot's own text.
  def assigned_copy
    raw = page_params.fetch(:copy, {})
    Custom::LoginPage::LOCALES.index_with do |locale|
      cleaned(raw.fetch(locale, {}).permit(*Custom::LoginPage::COPY_LIMITS.keys).to_h)
    end.compact_blank
  end

  def assigned_options
    raw = page_params.fetch(:options, {}).permit(*Custom::LoginPage::TOGGLES, *Custom::LoginPage::LINKS, :support_label).to_h
    toggles = Custom::LoginPage::TOGGLES.index_with { |key| ActiveModel::Type::Boolean.new.cast(raw[key]) == true }
    toggles.merge(cleaned(raw.except(*Custom::LoginPage::TOGGLES)))
  end

  def cleaned(hash)
    hash.transform_values { |value| value.to_s.strip }.compact_blank
  end

  # A new file replaces the current one; it is only stored if the page saves.
  def assign_images
    Custom::LoginPage::IMAGES.each_key do |name|
      file = page_params[name]
      @page.public_send("#{name}=", file) if file.present?
    end
    @page.background_image_removed = Array(page_params[:remove]).include?('background_image') && page_params[:background_image].blank?
  end

  def purge_removed_images
    Array(page_params[:remove]).each do |name|
      next unless Custom::LoginPage::IMAGES.key?(name.to_sym)
      next if page_params[name].present? # replaced, not removed

      @page.public_send(name).purge_later
    end
  end
end
