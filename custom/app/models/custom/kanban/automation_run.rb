# The claim that a rule has already acted on a deal in a trigger episode (a status change, a
# stall, the last message of a conversation...). The unique index is what makes "once per episode"
# true under retries and concurrent workers.
class Custom::Kanban::AutomationRun < ApplicationRecord
  belongs_to :automation, class_name: 'Custom::Kanban::StageAutomation'
  belongs_to :card, class_name: 'Custom::Kanban::Card'

  RETENTION = 90.days

  # True for the one caller that got the claim, false when the episode was already taken.
  def self.claim(automation, card, episode_key)
    result = insert({ automation_id: automation.id, card_id: card.id, episode_key: episode_key.to_s, created_at: Time.current }, # rubocop:disable Rails/SkipsModelValidations
                    unique_by: :index_flow_kanban_automation_runs_on_episode)
    result.rows.any?
  end
end
