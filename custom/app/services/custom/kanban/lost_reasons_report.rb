# Why a board's deals were lost in a period: the deals now in a lost stage that got there in the
# period, by reason, with the deals lost without one counted as "no reason" rather than left out.
class Custom::Kanban::LostReasonsReport
  def initialize(board:, since:, until_time:, assignee_id: nil)
    @board = board
    @range = since..until_time
    @assignee_id = assignee_id
  end

  def call
    grouped = lost_cards.group(:lost_reason_id).pluck(:lost_reason_id, Arel.sql('COUNT(*)'), Arel.sql('SUM(value_cents)'))
    names = Custom::Kanban::LostReason.where(id: grouped.filter_map(&:first)).pluck(:id, :name).to_h
    rows = grouped.map { |id, count, value| { reason_id: id, name: names[id], count: count, value_cents: value.to_i } }
    { rows: rows.sort_by { |row| [row[:reason_id].nil? ? 1 : 0, -row[:count], row[:name].to_s] }, total: rows.sum { |row| row[:count] } }
  end

  private

  def lost_cards
    scope = @board.cards.where(stage_id: @board.stages.select(&:stage_type_lost?).map(&:id), stage_changed_at: @range)
    return scope if @assignee_id.blank?

    scope.where(assignee_id: @assignee_id == 'none' ? nil : @assignee_id)
  end
end
