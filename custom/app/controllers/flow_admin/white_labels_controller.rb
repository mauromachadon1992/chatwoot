# Super Admin → Accounts → White label. Only a super admin brands an account; the account's
# own administrators see the result, not the controls.
#
# Served under /super_admin with the super admin's session and layout, but namespaced
# FlowAdmin: Administrate builds the super admin sidebar from every `super_admin/*`
# controller, and this page is reached from an account, not from the sidebar.
class FlowAdmin::WhiteLabelsController < SuperAdmin::ApplicationController
  before_action :set_account

  # Signing out of the dashboard ends every Devise scope (`sign_out_all_scopes`), the super
  # admin's too, so a form left open in another tab posts a token that no longer exists. Send
  # the admin back to the form with a reason instead of Rails' error page.
  rescue_from ActionController::InvalidAuthenticityToken do
    redirect_to super_admin_account_white_label_path(params[:account_id]), alert: t('flow_white_label.super_admin.session_expired')
  end

  helper_method :namespace

  def show; end

  # The layout's sidebar lists the resources of this namespace: keep it the super admin's.
  def namespace
    'super_admin'
  end

  def update
    @account.assign_white_label(white_label_params)
    assign_images

    if @account.save
      purge_removed_images
      redirect_to super_admin_account_white_label_path(@account), notice: t('flow_white_label.super_admin.saved')
    else
      flash.now[:alert] = t('flow_white_label.super_admin.not_saved')
      render :show, status: :unprocessable_entity
    end
  end

  # What the dashboard will make of a colour, for the form's live preview: the same
  # Custom::WhiteLabel::Palette the dashboard uses, so the preview never guesses.
  def palette
    color = params[:color].to_s.strip
    return head :unprocessable_content unless color.match?(Custom::WhiteLabel::COLOR_FORMAT)

    palette = Custom::WhiteLabel::Palette.new(color)
    render json: {
      action: palette.action_hex,
      adjusted: palette.adjusted?,
      white_contrast: palette.brand.contrast(Custom::WhiteLabel::Palette::WHITE).round(1),
      ramp: palette.variables[:light].values_at(*(1..12).map { |step| "--blue-#{step}" }).map { |rgb| "rgb(#{rgb})" }
    }
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
  end

  def white_label_params
    params.fetch(:white_label, {}).permit(*Custom::WhiteLabel::SETTINGS)
  end

  # A new file replaces the current one; it is only stored if the account saves.
  def assign_images
    Custom::WhiteLabel::IMAGES.each_key do |name|
      file = params.dig(:white_label, name)
      @account.public_send("#{name}=", file) if file.present?
    end
  end

  def purge_removed_images
    Array(params.dig(:white_label, :remove)).each do |name|
      next unless Custom::WhiteLabel::IMAGES.key?(name.to_sym)
      next if params.dig(:white_label, name).present? # replaced, not removed

      @account.public_send(name).purge_later
    end
  end
end
