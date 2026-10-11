# CSV imports of products and deals (administrators only; see Custom::Kanban::Import). The upload
# is analysed at once and nothing is written until `run`: the client shows the columns, a few rows
# and every problem by line, lets the administrator fix the column mapping, then starts the run.
class Api::V1::Accounts::Kanban::ImportsController < Api::V1::Accounts::Kanban::BaseController
  ERRORS_SHOWN = 50

  before_action :import, only: [:show, :update, :run, :errors]

  def show
    render json: { payload: @import.push_event_data }
  end

  def create
    authorize Custom::Kanban::Import
    kind = params.require(:kind)
    return head(:unprocessable_entity) unless Custom::Kanban::Import::KINDS.include?(kind)

    @import = build_import(params.require(:file), kind)
    render_analysis
  rescue Custom::Kanban::CsvFile::Invalid => e
    render json: { error: I18n.t("flow_kanban.imports.file.#{e.code}", **e.params) }, status: :unprocessable_entity
  end

  # The administrator corrected which column is which field.
  def update
    return head(:conflict) unless @import.status == 'analyzed'

    @import.update!(mapping: sanitized_mapping)
    render_analysis
  end

  def run
    return head(:conflict) unless @import.status == 'analyzed' && @import.error_count < @import.total_rows

    Custom::Kanban::ImportJob.perform_later(@import.id)
    render json: { payload: @import.push_event_data.merge(status: 'running') }
  end

  def errors
    send_data Custom::Kanban::CsvExport.import_errors(@import), type: 'text/csv; charset=utf-8',
                                                                filename: "#{File.basename(@import.filename, '.*')}-errors.csv"
  end

  private

  def import
    @import = Custom::Kanban::Import.where(account: Current.account).find(params[:id])
    authorize @import
  end

  # Reads the upload (Invalid when it is not a usable CSV) and keeps it, with the guessed mapping.
  def build_import(file, kind)
    content = file.read
    parsed = Custom::Kanban::CsvFile.parse(content)
    Custom::Kanban::Import.create!(
      account: Current.account, user: Current.user, kind: kind, filename: file.original_filename.to_s.truncate(120),
      board_id: board_for(kind)&.id, source: content.dup.force_encoding(Encoding::UTF_8),
      delimiter: parsed.delimiter, headers: parsed.headers,
      mapping: Custom::Kanban::Import.importer_for(kind).auto_mapping(parsed.headers)
    )
  end

  def board_for(kind)
    return unless kind == 'deals'

    find_visible_board(params.require(:board_id))
  end

  def sanitized_mapping
    fields = @import.importer_class.aliases.keys.map(&:to_s)
    given = params.fetch(:mapping, {}).permit(*fields).to_h
    given.select { |_field, header| @import.headers.include?(header) }
  end

  def render_analysis
    analysis = Custom::Kanban::ImportRunner.new(@import).analyze
    errors = @import.errors_log.first(ERRORS_SHOWN).map { |error| error.slice('line', 'messages') }
    render json: { payload: @import.reload.push_event_data,
                   analysis: { preview: analysis.preview, missing: analysis.missing, errors: errors,
                               fields: @import.importer_class.aliases.keys, required: @import.importer_class.required_fields } }
  end
end
