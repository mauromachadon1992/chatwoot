# What a Kanban card shows on the board without being opened. A super admin picks them per
# account (Super Admin → Accounts → Edit); an account that never chose shows them all.
module Custom::Kanban::CardFields
  ALL = %w[contact value conversations assignee time_in_stage last_activity].freeze
  SETTINGS_KEY = 'flow_kanban_card_fields'.freeze
end
