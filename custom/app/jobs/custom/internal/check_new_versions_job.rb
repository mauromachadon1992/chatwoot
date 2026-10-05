# Prepended to Internal::CheckNewVersionsJob (after Enterprise::Internal::CheckNewVersionsJob,
# so it runs first).
#
# A Chatwoot Enterprise license is not code: Chatwoot Inc ties it to the installation's
# INSTALLATION_IDENTIFIER, and this daily job asks the Chatwoot Hub for the plan, which
# Enterprise::Internal::CheckNewVersionsJob then stores (INSTALLATION_PRICING_PLAN and
# _QUANTITY). fazer.ai replaced the Hub call with a GitHub release lookup (fazer-ai/chatwoot
# #105), so the plan never arrives and the installation stays `community`, which also makes
# the Enterprise job switch premium features off every day.
#
# CHATWOOT_HUB_SYNC=true puts the Hub call back, in production with Enterprise on. It is
# opt-in: the call sends the installation's identifier, version and host, plus usage counts
# unless DISABLE_TELEMETRY=true (see ChatwootHub.sync_with_hub), so it is turned on only for
# an installation that holds a Chatwoot Inc license.
module Custom::Internal::CheckNewVersionsJob
  def perform
    @instance_info = ChatwootHub.sync_with_hub if hub_sync?
    super
  end

  private

  def hub_sync?
    Rails.env.production? && ChatwootApp.enterprise? && ActiveModel::Type::Boolean.new.cast(ENV.fetch('CHATWOOT_HUB_SYNC', nil))
  end
end
