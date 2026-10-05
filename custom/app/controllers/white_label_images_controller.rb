# Serves a white label's images (see Custom::WhiteLabel::IMAGES and FlowImageResponse).
#
# A public asset, like Active Storage's own controllers: none of ApplicationController's token
# auth or session tracking applies.
class WhiteLabelImagesController < ActionController::Base # rubocop:disable Rails/ApplicationController
  include FlowImageResponse

  before_action :set_account

  def show
    blob = accepted_blob(@account.public_send(@name), Custom::WhiteLabel::IMAGES[@name].first)
    return head :not_found unless blob

    send_brand_image(blob, public: @account.white_label_enabled?)
  end

  private

  def set_account
    @account = Account.find_by(id: params[:account_id])
    @name = params[:name].to_s.to_sym
    head :not_found unless @account && Custom::WhiteLabel::IMAGES.key?(@name) && visible?
  end

  # A disabled white label is only shown in the super admin's form.
  def visible?
    @account.white_label_enabled? || super_admin_signed_in?
  end
end
