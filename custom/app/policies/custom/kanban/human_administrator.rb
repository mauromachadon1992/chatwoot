# "Administrator" for the policies that reach outside the installation (webhooks, imports) or change
# the rules that act on deals (automations): an administrator who is a person. The agents' service
# user (Custom::Kanban::ServiceUser) is an administrator by role, so a leaked or misled agent token
# could otherwise point a webhook at an attacker or rewrite the funnel's rules.
module Custom::Kanban::HumanAdministrator
  private

  def administrator?
    account_user&.administrator? && !Custom::Kanban::ServiceUser.agent_bot?(user)
  end
end
