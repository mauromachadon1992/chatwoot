# Serves a white label's images (see Custom::WhiteLabel::IMAGES).
#
# Active Storage deliberately serves SVG as `application/octet-stream`, because an SVG opened
# on its own can run script; browsers then refuse to draw it in an <img>, so an SVG logo
# simply disappeared. Only a super admin can upload these files, and this response neutralises
# the risk anyway: the content type is whitelisted per image, `nosniff` stops the browser from
# guessing, and a sandboxing CSP keeps any script in the file from running when it is opened
# directly. Every other upload in Chatwoot keeps Active Storage's protection.
#
# A public asset, like Active Storage's own controllers: none of ApplicationController's token
# auth or session tracking applies.
class WhiteLabelImagesController < ActionController::Base # rubocop:disable Rails/ApplicationController
  SANDBOX_POLICY = "default-src 'none'; style-src 'unsafe-inline'; img-src data:; sandbox".freeze

  before_action :set_account

  def show
    blob = current_blob
    return head :not_found unless blob

    response.headers['Content-Security-Policy'] = SANDBOX_POLICY
    response.headers['X-Content-Type-Options'] = 'nosniff'
    # The URL changes with every upload, so the bytes behind it never do.
    expires_in 1.year, public: @account.white_label_enabled?, immutable: true

    send_data blob.download, type: blob.content_type, disposition: 'inline', filename: blob.filename.to_s
  end

  private

  def set_account
    @account = Account.find_by(id: params[:account_id])
    @name = params[:name].to_s.to_sym
    head :not_found unless @account && Custom::WhiteLabel::IMAGES.key?(@name) && visible?
  end

  # A disabled white label is only shown in the super admin's form.
  def visible?
    @account.white_label_enabled? || request.env['warden']&.authenticated?(:super_admin)
  end

  # Only the image attached right now, and only in a type accepted for it.
  def current_blob
    attachment = @account.public_send(@name)
    return unless attachment.attached? && attachment.blob_id.to_s == params[:version]

    attachment.blob if Custom::WhiteLabel::IMAGES[@name].first.include?(attachment.blob.content_type)
  end
end
