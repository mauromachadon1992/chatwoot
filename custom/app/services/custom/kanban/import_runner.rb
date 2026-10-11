# Walks the rows of an import through its importer, either to report (the dry run, nothing is
# written) or to write. Messages are written in the account's language, because the error file
# is read outside the dashboard.
class Custom::Kanban::ImportRunner
  PREVIEW_ROWS = 5
  PROGRESS_EVERY = 25

  Analysis = Struct.new(:preview, :missing, keyword_init: true)

  def initialize(import)
    @import = import
    @parsed = Custom::Kanban::CsvFile.parse(import.source)
    @importer = import.importer_class.new(import)
  end

  # Fills the import's counts and errors from a read-only pass and returns the first rows as the
  # importer would treat them.
  def analyze
    mapping = @import.mapping
    missing = missing_fields(mapping)
    return Analysis.new(preview: [], missing: missing) if missing.any?

    counts = Hash.new(0)
    errors = []
    preview = []
    each_verdict(mapping) do |row, verdict|
      record(verdict, row, counts, errors)
      preview << preview_row(row, verdict) if preview.size < PREVIEW_ROWS
    end
    @import.update!(total_rows: @parsed.rows.size, created_count: counts[:create], updated_count: counts[:update],
                    skipped_count: counts[:skip], error_count: counts[:errors], errors_log: errors.first(Custom::Kanban::Import::ERRORS_KEPT))
    Analysis.new(preview: preview, missing: [])
  end

  # The real run: each row on its own, so one bad row never stops the others.
  def run
    counts = Hash.new(0)
    errors = []
    processed = 0
    each_verdict(@import.mapping, apply: true) do |row, verdict|
      record(verdict, row, counts, errors)
      processed += 1
      progress(processed, counts) if (processed % PROGRESS_EVERY).zero?
    end
    @import.update!(status: 'done', source: nil, processed_rows: processed, created_count: counts[:create], updated_count: counts[:update],
                    skipped_count: counts[:skip], error_count: counts[:errors], errors_log: errors.first(Custom::Kanban::Import::ERRORS_KEPT))
  end

  private

  def missing_fields(mapping)
    @import.importer_class.required_fields.reject { |field| mapping[field].present? && @parsed.headers.include?(mapping[field]) }
  end

  def each_verdict(mapping, apply: false)
    I18n.with_locale(@import.account.locale || I18n.default_locale) do
      @parsed.rows.each do |row|
        verdict = @importer.analyze(@importer.values(row[:cells], @parsed.headers, mapping))
        verdict = applied(verdict) if apply && !verdict.error? && verdict.action != :skip
        yield row, verdict
      end
    end
  end

  # A write that fails becomes the row's error, in words.
  def applied(verdict)
    @importer.apply(verdict)
    verdict
  rescue ActiveRecord::RecordInvalid => e
    Custom::Kanban::Importers::Base::Verdict.new(action: :skip, attrs: {}, messages: e.record.errors.full_messages)
  rescue StandardError => e
    Rails.logger.error("Kanban import #{@import.id}: #{e.class}: #{e.message}")
    Custom::Kanban::Importers::Base::Verdict.new(action: :skip, attrs: {}, messages: [I18n.t('flow_kanban.imports.errors.unexpected')])
  end

  def record(verdict, row, counts, errors)
    if verdict.error?
      errors << { line: row[:line], messages: verdict.messages, cells: row[:cells] } if errors.size < Custom::Kanban::Import::ERRORS_KEPT * 2
      counts[:errors] += 1
    else
      counts[verdict.action] += 1
    end
  end

  def preview_row(row, verdict)
    { line: row[:line], cells: row[:cells], action: verdict.error? ? 'error' : verdict.action.to_s, messages: verdict.messages }
  end

  def progress(processed, counts)
    @import.update_columns(processed_rows: processed, created_count: counts[:create], updated_count: counts[:update], # rubocop:disable Rails/SkipsModelValidations
                           skipped_count: counts[:skip], error_count: counts[:errors])
  end
end
