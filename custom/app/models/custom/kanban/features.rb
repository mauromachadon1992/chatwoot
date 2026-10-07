# Kanban behaviours a super admin switches per account (Super Admin → Accounts → Edit), so a
# behaviour that changes how deals arrive or who is told can be piloted, and turned off.
module Custom::Kanban::Features
  ALL = %w[auto_create stale_alerts webhooks].freeze
  # An account that never chose gets these. Stalled-deal alerts only fire on stages an
  # administrator gave a limit to, so they start on; automatic deals change how cards arrive, so
  # they start off until a super admin turns them on. Webhooks send nothing until an
  # administrator adds an address, so they start on.
  DEFAULTS = %w[stale_alerts webhooks].freeze
  SETTINGS_KEY = 'flow_kanban_features'.freeze

  def self.enabled?(account, feature)
    account.present? && account.flow_kanban_features.include?(feature.to_s)
  end
end
