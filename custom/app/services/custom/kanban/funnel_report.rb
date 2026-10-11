# The numbers behind a board's report, for a period and optionally one assignee.
#
# - summary: what is open now, what was won or lost in the period (a card counts by the stage it
#   is in now and when it got there), the win rate, the average won deal and how long won deals
#   took from creation.
# - stages, in board order: what each stage holds now; how long deals stayed in it before
#   leaving during the period; and the funnel of the deals created in the period: how many
#   reached each stage, or passed it (a won deal passed every open stage), and the share of the
#   previous step that got there.
class Custom::Kanban::FunnelReport
  def initialize(board:, since:, until_time:, assignee_id: nil)
    @board = board
    @range = since..until_time
    @assignee_id = assignee_id
    @stages = board.stages.to_a
  end

  def call
    {
      currency: @board.account.flow_kanban_currency,
      since: @range.begin.to_i,
      until: @range.end.to_i,
      summary: summary,
      stages: stage_rows
    }
  end

  private

  def cards
    scope = @board.cards
    return scope if @assignee_id.blank?

    scope.where(assignee_id: @assignee_id == 'none' ? nil : @assignee_id)
  end

  def stage_ids(type)
    @stages.select { |stage| stage.stage_type == type }.map(&:id)
  end

  def open_stages
    @open_stages ||= @stages.select(&:stage_type_open?)
  end

  # --- summary ---------------------------------------------------------------------------

  def summary
    won = closed_in_period('won')
    lost = closed_in_period('lost')
    closed = won.count + lost.count
    {
      created: cards.where(created_at: @range).count,
      open: totals(cards.where(stage_id: stage_ids('open'))),
      won: totals(won),
      lost: totals(lost),
      win_rate: closed.zero? ? nil : percent(won.count, closed),
      average_won_cents: won.count.zero? ? nil : (won.sum(:value_cents) / won.count),
      average_cycle_seconds: average_seconds(won.pick(Arel.sql('AVG(EXTRACT(EPOCH FROM (stage_changed_at - created_at)))')))
    }
  end

  def closed_in_period(type)
    cards.where(stage_id: stage_ids(type), stage_changed_at: @range)
  end

  def totals(scope)
    count, value = scope.pick(Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(value_cents), 0)'))
    { count: count.to_i, value_cents: value.to_i }
  end

  # --- stages ----------------------------------------------------------------------------

  def stage_rows
    current = current_totals
    durations = average_durations
    funnel = funnel_rows

    @stages.map do |stage|
      { id: stage.id, name: stage.name, color: stage.color, stage_type: stage.stage_type,
        average_seconds: durations[stage.id], reached: nil, conversion_rate: nil }
        .merge(current.fetch(stage.id, { count: 0, value_cents: 0 }))
        .merge(funnel.fetch(stage.id, {}))
    end
  end

  def current_totals
    cards.group(:stage_id).pluck(:stage_id, Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(value_cents), 0)'))
         .to_h { |stage_id, count, value| [stage_id, { count: count.to_i, value_cents: value.to_i }] }
  end

  # Time from entering a stage to leaving it, for the stays that ended in the period.
  def average_durations
    sql = <<~SQL.squish
      SELECT to_stage_id, AVG(EXTRACT(EPOCH FROM (left_at - entered_at)))
      FROM (
        SELECT t.to_stage_id, t.created_at AS entered_at,
               LEAD(t.created_at) OVER (PARTITION BY t.card_id ORDER BY t.created_at, t.id) AS left_at
        FROM flow_kanban_stage_transitions t
        WHERE t.board_id = :board_id AND t.card_id IN (#{cards.select(:id).to_sql})
      ) stays
      WHERE left_at BETWEEN :since AND :until
      GROUP BY to_stage_id
    SQL
    rows = ActiveRecord::Base.connection.select_rows(
      ActiveRecord::Base.sanitize_sql([sql, { board_id: @board.id, since: @range.begin, until: @range.end }])
    )
    rows.to_h { |stage_id, seconds| [stage_id.to_i, average_seconds(seconds)] }
  end

  # Open stages first, each against the one before it (the first against every deal created);
  # then each won stage against the last open one.
  def funnel_rows
    visits = cohort_visits
    return {} if visits.empty?

    depths = visits.map { |visited| furthest_step(visited) }
    previous = visits.size
    rows = open_stages.each_with_index.to_h do |stage, index|
      reached = depths.count { |depth| depth >= index }
      row = funnel_row(reached, previous)
      previous = reached
      [stage.id, row]
    end
    won_stages.each { |stage| rows[stage.id] = funnel_row(visits.count { |visited| visited.include?(stage.id) }, previous) }
    rows
  end

  # The stages each deal created in the period entered, one set per deal.
  def cohort_visits
    cohort = cards.where(created_at: @range).pluck(:id)
    entered = Custom::Kanban::StageTransition.where(card_id: cohort).pluck(:card_id, :to_stage_id)
                                             .group_by(&:first).transform_values { |rows| rows.to_set(&:last) }
    cohort.map { |card_id| entered.fetch(card_id, Set.new) }
  end

  def funnel_row(reached, previous)
    { reached: reached, conversion_rate: previous.zero? ? nil : percent(reached, previous) }
  end

  def won_stages
    @won_stages ||= @stages.select(&:stage_type_won?)
  end

  # The furthest open stage a deal entered, by board order; a won deal passed them all.
  def furthest_step(visited)
    return open_stages.size if won_stages.any? { |stage| visited.include?(stage.id) }

    open_stages.each_index.select { |index| visited.include?(open_stages[index].id) }.max || -1
  end

  def percent(part, whole)
    (part * 100.0 / whole).round(1)
  end

  def average_seconds(value)
    value&.to_f&.round
  end
end
