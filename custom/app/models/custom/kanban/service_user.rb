# The account user the fazer.ai agents work through: an administrator by role (the Pro dialect needs
# one to create boards and steps) that is marked `flow_service: agent_bot` in its custom attributes.
# The mark can only be set from the console or `rake "flow:kanban:agent_bot[EMAIL]"`; the profile
# endpoint permits no custom attribute but the phone number, so the account cannot unset it for itself.
# A marked user does everything an administrator does on the deals, and nothing on the endpoints
# that reach outside the installation or change the rules (see Custom::Kanban::HumanAdministrator).
module Custom::Kanban::ServiceUser
  ATTRIBUTE = 'flow_service'.freeze
  AGENT_BOT = 'agent_bot'.freeze

  def self.agent_bot?(user)
    user.respond_to?(:custom_attributes) && user.custom_attributes.to_h[ATTRIBUTE] == AGENT_BOT
  end

  def self.mark!(user)
    user.update!(custom_attributes: user.custom_attributes.to_h.merge(ATTRIBUTE => AGENT_BOT))
  end

  def self.unmark!(user)
    user.update!(custom_attributes: user.custom_attributes.to_h.except(ATTRIBUTE))
  end
end
