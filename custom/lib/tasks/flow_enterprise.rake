# Chatwoot Enterprise in development and test; see Custom::EnterpriseDev.
namespace :flow do
  namespace :enterprise do
    desc 'Development: enterprise plan and every feature flag (except internal and deprecated) on every account'
    task dev_enable: :environment do
      Custom::EnterpriseDev.new.enable(seats: ENV.fetch('SEATS', '100').to_i)
      puts "Plan: #{ChatwootHub.pricing_plan} (#{ChatwootHub.pricing_plan_quantity} seats)"
      puts "Enabled on #{Account.count} account(s): #{Custom::EnterpriseDev.features.size} features"
      puts "Left as they were (internal or deprecated): #{Custom::EnterpriseDev.skipped_features.join(', ')}"
    rescue Custom::EnterpriseDev::NotAllowed => e
      abort e.message
    end

    desc 'Development: back to the community plan, premium features off (what an unlicensed installation sees)'
    task dev_disable: :environment do
      Custom::EnterpriseDev.new.disable
      puts "Plan: #{ChatwootHub.pricing_plan}; premium features switched off on every account"
    rescue Custom::EnterpriseDev::NotAllowed => e
      abort e.message
    end
  end
end
