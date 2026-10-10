# Sends an uploaded brand image (white label, login page) so that an SVG renders.
#
# Active Storage deliberately serves SVG as `application/octet-stream`, because an SVG opened
# on its own can run script; browsers then refuse to draw it in an <img>. Only a super admin
# uploads these files, and this response neutralises the risk anyway: the content type is
# whitelisted per image, `nosniff` stops the browser from guessing, and a sandboxing CSP keeps
# any script in the file from running when it is opened directly. Every other upload in
# Chatwoot keeps Active Storage's protection.
module FlowImageResponse
  extend ActiveSupport::Concern

  SANDBOX_POLICY = "default-src 'none'; style-src 'unsafe-inline'; img-src data:; sandbox".freeze

  private

  # The blob behind `attachment` when it is the version the URL names and an accepted type.
  def accepted_blob(attachment, types)
    return unless attachment.attached? && attachment.blob_id.to_s == params[:version]

    attachment.blob if types.include?(attachment.blob.content_type)
  end

  # The URL changes with every upload (it carries the blob id), so the bytes behind it never do.
  def send_brand_image(blob, public:)
    response.headers['Content-Security-Policy'] = SANDBOX_POLICY
    response.headers['X-Content-Type-Options'] = 'nosniff'
    expires_in 1.year, public: public, immutable: true
    send_data blob.download, type: blob.content_type, disposition: 'inline', filename: blob.filename.to_s
  end

  def super_admin_signed_in?
    request.env['warden']&.authenticated?(:super_admin)
  end
end
