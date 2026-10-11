require 'administrate/field/base'

# Shown on Super Admin → Accounts → show: the account's white label status and the way into
# its settings page. The settings themselves live on that page, not in the account form.
class FlowWhiteLabelField < Administrate::Field::Base
  def enabled?
    resource.white_label_enabled?
  end

  def brand_name
    resource.white_label_value(:white_label_name)
  end

  def domain
    resource.white_label_value(:white_label_domain)
  end

  def icon_path
    resource.white_label_image_path(:white_label_icon)
  end

  def to_s
    enabled? ? I18n.t('flow_white_label.field.enabled') : I18n.t('flow_white_label.field.disabled')
  end
end
