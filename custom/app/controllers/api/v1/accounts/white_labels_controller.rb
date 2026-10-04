# The brand the dashboard wears for this account once the user is signed in, on any domain.
# Any member of the account may read it: it is what the account's own screens display.
class Api::V1::Accounts::WhiteLabelsController < Api::V1::Accounts::BaseController
  def show
    render json: { payload: Custom::WhiteLabel::Resolver.new(Current.account).dashboard_payload }
  end
end
