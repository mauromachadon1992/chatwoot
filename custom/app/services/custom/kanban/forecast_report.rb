# What a board's open deals should bring in, by the month they are expected to close.
#
# Each row has the deals, their value, and the value weighted by the chance of their stage
# (Stage#effective_probability). Rows: past the expected date and still open ("overdue"), each
# of the next MONTHS months, anything after them ("later"), and deals without a date ("no_date"),
# which are shown, never dropped: how many open deals carry a date is part of the answer.
class Custom::Kanban::ForecastReport
  MONTHS = 6

  def initialize(board:, assignee_id: nil, today: Time.zone.today)
    @board = board
    @assignee_id = assignee_id
    @today = today
  end

  def call
    rows = row_keys.index_with { { count: 0, value_cents: 0, weighted_cents: 0 } }
    open_deals.each { |deal| add(rows[key_for(deal[:close_on])], deal) }
    {
      rows: rows.map { |key, figures| figures.merge(key: key, weighted_cents: figures[:weighted_cents].round) },
      totals: totals(rows.values),
      open_count: open_deals.size,
      with_date_count: open_deals.count { |deal| deal[:close_on] }
    }
  end

  private

  def open_deals
    @open_deals ||= begin
      probabilities = @board.stages.select(&:stage_type_open?).to_h { |stage| [stage.id, stage.effective_probability] }
      scope = @board.cards.where(stage_id: probabilities.keys)
      scope = scope.where(assignee_id: @assignee_id == 'none' ? nil : @assignee_id) if @assignee_id.present?
      scope.pluck(:stage_id, :value_cents, :expected_close_on).map do |stage_id, value, close_on|
        { value_cents: value, probability: probabilities[stage_id], close_on: close_on }
      end
    end
  end

  def months
    (0...MONTHS).map { |offset| @today.beginning_of_month.next_month(offset) }
  end

  def row_keys
    ['overdue', *months.map { |month| month.strftime('%Y-%m') }, 'later', 'no_date']
  end

  def key_for(close_on)
    return 'no_date' if close_on.nil?
    return 'overdue' if close_on < @today
    return 'later' if close_on >= months.last.next_month

    close_on.strftime('%Y-%m')
  end

  def add(row, deal)
    row[:count] += 1
    row[:value_cents] += deal[:value_cents]
    row[:weighted_cents] += deal[:value_cents] * deal[:probability] / 100.0
  end

  def totals(rows)
    { count: rows.sum { |row| row[:count] }, value_cents: rows.sum { |row| row[:value_cents] },
      weighted_cents: rows.sum { |row| row[:weighted_cents] }.round }
  end
end
