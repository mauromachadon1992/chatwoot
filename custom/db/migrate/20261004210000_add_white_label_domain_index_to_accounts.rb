# Every dashboard request on a non-default host looks an account up by its white label domain.
class AddWhiteLabelDomainIndexToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_index :accounts, "(settings->>'white_label_domain')",
              name: 'index_accounts_on_white_label_domain',
              unique: true,
              where: "settings->>'white_label_domain' IS NOT NULL"
  end
end
