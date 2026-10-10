# Runs an analysed import in the background. It is claimed by moving the status from analyzed to
# running, so a doubled click or a retried job never imports the file twice.
class Custom::Kanban::ImportJob < ApplicationJob
  queue_as :low

  def perform(import_id)
    import = Custom::Kanban::Import.find_by(id: import_id)
    return unless import

    claimed = Custom::Kanban::Import.where(id: import.id, status: 'analyzed').update_all(status: 'running', processed_rows: 0) # rubocop:disable Rails/SkipsModelValidations
    return if claimed.zero?

    import.reload
    Current.user = import.user
    Custom::Kanban::ImportRunner.new(import).run
  rescue StandardError => e
    Rails.logger.error("Kanban import #{import_id} failed: #{e.class}: #{e.message}")
    Custom::Kanban::Import.where(id: import_id).update_all(status: 'failed', source: nil) # rubocop:disable Rails/SkipsModelValidations
    raise
  ensure
    Current.reset
  end
end
