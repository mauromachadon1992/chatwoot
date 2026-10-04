# Prepended to Brand (lib/brand.rb), which resolves the brand of outgoing email and of the
# public CSAT page. A white-labelled account wins over both the installation and the
# account-level email branding: a super admin set it, and it is meant to be the last word.
#
# "Powered by" is the provider's line, so BRAND_NAME / BRAND_URL carry the custom powered-by
# name and link, falling back to the account's own brand name.
module Custom::Brand
  def name
    return super unless white_label?

    white_label(:white_label_powered_by_name) || white_label(:white_label_name) || super
  end

  def url
    return super unless white_label?

    white_label(:white_label_powered_by_url) || super
  end

  def color
    return super unless white_label?

    white_label(:white_label_color) || super
  end

  def web_config
    config = super
    return config unless white_label?

    config.merge(
      'INSTALLATION_NAME' => white_label(:white_label_name) || config['INSTALLATION_NAME'],
      'WIDGET_BRAND_URL' => white_label(:white_label_powered_by_url) || config['WIDGET_BRAND_URL'],
      'LOGO_THUMBNAIL' => account.white_label_image_url(:white_label_icon) || config['LOGO_THUMBNAIL'],
      'BRAND_FROM_ACCOUNT' => true
    )
  end

  private

  def account_logo_url
    return super unless white_label?

    account.white_label_image_url(:white_label_logo_email) || super
  end

  def white_label?
    account.present? && account.white_label_enabled?
  end

  def white_label(key)
    account.white_label_value(key)
  end
end
