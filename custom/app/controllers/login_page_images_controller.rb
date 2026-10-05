# Serves the installation login page's images (see Custom::LoginPage::IMAGES and
# FlowImageResponse). Public while the page is live, since the sign-in screen shows them before
# anyone is signed in; otherwise only to a super admin, for the form's preview.
class LoginPageImagesController < ActionController::Base # rubocop:disable Rails/ApplicationController
  include FlowImageResponse

  def show
    name = params[:name].to_s.to_sym
    page = Custom::LoginPage.first
    return head :not_found unless page && Custom::LoginPage::IMAGES.key?(name) && (page.enabled? || super_admin_signed_in?)

    blob = accepted_blob(page.public_send(name), Custom::LoginPage::IMAGES[name].first)
    return head :not_found unless blob

    send_brand_image(blob, public: page.enabled?)
  end
end
