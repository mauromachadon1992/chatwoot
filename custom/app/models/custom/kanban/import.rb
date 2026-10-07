# One CSV import. It is analysed first (a dry run that writes nothing and reports every problem
# by line), then run in the background. The file is kept only until the run ends: what remains
# is the counts and the rows that failed, for the error file.
class Custom::Kanban::Import < ApplicationRecord
  KINDS = %w[products deals].freeze
  STATUSES = %w[analyzed running done failed].freeze
  ERRORS_KEPT = 1000
  KEPT_FOR = 7.days

  belongs_to :account
  belongs_to :user

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def self.importer_for(kind)
    { 'products' => Custom::Kanban::Importers::Products, 'deals' => Custom::Kanban::Importers::Deals }.fetch(kind)
  end

  def importer_class
    self.class.importer_for(kind)
  end

  def kind_products?
    kind == 'products'
  end

  def finished?
    %w[done failed].include?(status)
  end

  def progress
    total_rows.zero? ? 0 : (processed_rows * 100 / total_rows)
  end

  def push_event_data
    { id: id, kind: kind, filename: filename, status: status, board_id: board_id, total_rows: total_rows,
      processed_rows: processed_rows, progress: progress, created: created_count, updated: updated_count,
      skipped: skipped_count, errors: error_count, headers: headers, mapping: mapping, created_at: created_at.to_i }
  end
end
