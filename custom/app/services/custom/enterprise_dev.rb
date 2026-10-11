# Chatwoot Enterprise in development and test, which its license allows without a
# subscription (enterprise/LICENSE). Production gets its plan from the Chatwoot Hub, for an
# installation with a Chatwoot Inc license (see Custom::Internal::CheckNewVersionsJob), so
# this refuses to run there. Used by the flow:enterprise rake tasks.
class Custom::EnterpriseDev
  class NotAllowed < StandardError; end

  # Feature flags that only make sense on Chatwoot's own cloud, or that are retired.
  SKIPPED_FEATURE_KEYS = %w[chatwoot_internal deprecated].freeze

  def self.features
    Featurable::FEATURE_LIST.reject { |feature| SKIPPED_FEATURE_KEYS.any? { |key| feature[key] } }.pluck('name')
  end

  def self.skipped_features
    Featurable::FEATURE_LIST.pluck('name') - features
  end

  def initialize
    raise NotAllowed, 'Only in development or test.' unless Rails.env.local?
    raise NotAllowed, 'Enterprise is off: unset DISABLE_ENTERPRISE and restart.' unless ChatwootApp.enterprise?
  end

  # The enterprise plan, and every feature flag but the skipped ones on every account.
  def enable(seats: 100)
    store_plan('enterprise', seats)
    Account.find_each { |account| account.enable_features!(*self.class.features) }
  end

  # What an unlicensed installation sees: the community plan, premium features off.
  def disable
    store_plan('community', 0)
    Internal::ReconcilePlanConfigService.new.perform
  end

  private

  # Locked, like Enterprise::Internal::CheckNewVersionsJob stores them.
  def store_plan(plan, quantity)
    { 'INSTALLATION_PRICING_PLAN' => plan, 'INSTALLATION_PRICING_PLAN_QUANTITY' => quantity }.each do |name, value|
      InstallationConfig.find_or_initialize_by(name: name).update!(value: value, locked: true)
    end
    GlobalConfig.clear_cache
  end
end
