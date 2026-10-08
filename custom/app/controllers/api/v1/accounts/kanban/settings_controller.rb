# Account-wide Kanban settings an administrator changes from the dashboard: the currency deals
# are valued in, and the message a quote is composed from. The dashboard reads both from the
# account's settings; an empty quote template means the dashboard's default, in the agent's
# language.
class Api::V1::Accounts::Kanban::SettingsController < Api::V1::Accounts::Kanban::BaseController
  QUOTE_TEMPLATE_MAX_LENGTH = 2_000
  # What the Pro dialect already answers (contract operations): a client reads this instead of probing.
  CAPABILITIES = %w[boards.read boards.write boards.bindings steps.read steps.write tasks.read tasks.create tasks.move tasks.update
                    conversation.kanban_task webhook.kanban_task].freeze

  def show
    render json: { payload: payload }
  end

  def update
    # Changing it is changing the account, so it takes what Chatwoot asks for that.
    authorize Current.account, :update?
    problem = invalid_message
    return render json: { message: problem }, status: :unprocessable_content if problem

    Current.account.flow_kanban_currency = params[:currency] if params.key?(:currency)
    Current.account.flow_kanban_quote_template = quote_template if params.key?(:quote_template)
    Current.account.save!
    render json: { payload: payload }
  end

  private

  def currency_supported?
    Custom::Kanban::Currency.supported?(params[:currency])
  end

  def quote_template
    params[:quote_template].to_s.strip.presence
  end

  def invalid_message
    return I18n.t('flow_kanban.settings.unsupported_currency') if params.key?(:currency) && !currency_supported?

    I18n.t('flow_kanban.settings.quote_template_too_long') if quote_template.to_s.length > QUOTE_TEMPLATE_MAX_LENGTH
  end

  def payload
    { currency: Current.account.flow_kanban_currency, currencies: Custom::Kanban::Currency::SUPPORTED,
      quote_template: Current.account.flow_kanban_quote_template, api_version: 1, dialect: DIALECT, capabilities: CAPABILITIES }
  end
end
