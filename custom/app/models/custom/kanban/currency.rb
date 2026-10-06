# The currency an account's deals are valued in, kept in accounts.settings. Values are
# stored in minor units, so only currencies with two decimal places are offered.
module Custom::Kanban::Currency
  SETTINGS_KEY = 'flow_kanban_currency'.freeze
  DEFAULT = 'BRL'.freeze
  SUPPORTED = %w[BRL USD EUR GBP ARS MXN COP PEN UYU].freeze

  def self.supported?(code)
    SUPPORTED.include?(code)
  end
end
