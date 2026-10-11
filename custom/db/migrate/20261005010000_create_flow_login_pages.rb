# The installation's own sign-in page (Super Admin → Login page). One row: settings that
# describe the page, plus four image attachments on the model. Kept out of
# installation_configs on purpose: the Enterprise plan reconciliation resets INSTALLATION_NAME,
# LOGO and BRAND_COLOR to Chatwoot's defaults every day on a `community` installation.
class CreateFlowLoginPages < ActiveRecord::Migration[7.1]
  def change
    create_table :flow_login_pages do |t|
      t.boolean :enabled, null: false, default: false
      t.string :name
      t.string :accent_color
      t.string :layout, null: false, default: 'background'
      t.string :background_kind, null: false, default: 'brand'
      t.jsonb :gradient, null: false, default: {}
      t.string :animation, null: false, default: 'none'
      t.integer :overlay, null: false, default: 30
      t.jsonb :copy, null: false, default: {}
      t.jsonb :options, null: false, default: {}
      t.timestamps
    end
  end
end
