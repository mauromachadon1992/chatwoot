# Account-wide Kanban settings an administrator changes from the dashboard: for now, the
# currency deals are valued in. The dashboard reads it from the account's settings.
class Api::V1::Accounts::Kanban::SettingsController < Api::V1::Accounts::Kanban::BaseController
  def show
    render json: { payload: payload }
  end

  def update
    # Changing it is changing the account, so it takes what Chatwoot asks for that.
    authorize Current.account, :update?

    currency = params.require(:currency)
    unless Custom::Kanban::Currency.supported?(currency)
      return render json: { message: I18n.t('flow_kanban.settings.unsupported_currency') }, status: :unprocessable_content
    end

    Current.account.update!(flow_kanban_currency: currency)
    render json: { payload: payload }
  end

  private

  def payload
    { currency: Current.account.flow_kanban_currency, currencies: Custom::Kanban::Currency::SUPPORTED }
  end
end
