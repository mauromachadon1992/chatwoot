class CreateFlowKanbanImports < ActiveRecord::Migration[7.0]
  def change
    # One CSV import: what was uploaded (kept only until it has run), how its columns map to
    # fields, the dry-run summary, and the progress and errors of the real run.
    create_table :flow_kanban_imports do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: false
      t.bigint :board_id
      t.string :kind, null: false
      t.string :filename, null: false
      t.string :status, null: false, default: 'analyzed'
      t.text :source
      t.string :delimiter, null: false, default: ','
      t.jsonb :headers, null: false, default: []
      t.jsonb :mapping, null: false, default: {}
      %i[total_rows processed_rows created_count updated_count skipped_count error_count].each do |counter|
        t.integer counter, null: false, default: 0
      end
      t.jsonb :errors_log, null: false, default: []
      t.timestamps
    end
  end
end
