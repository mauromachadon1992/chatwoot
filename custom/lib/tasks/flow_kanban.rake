# The Kanban's usage numbers for one account; see Custom::Kanban::Metrics.
namespace :flow do
  namespace :kanban do
    desc 'Usage numbers of the Kanban for an account over the last DAYS days (default 30): rake "flow:kanban:metrics[1,30]"'
    task :metrics, [:account_id, :days] => :environment do |_task, args|
      account = Account.find_by(id: args[:account_id])
      abort 'Usage: rake "flow:kanban:metrics[ACCOUNT_ID,DAYS]"' unless account

      days = (args[:days].presence || 30).to_i
      abort 'DAYS must be between 1 and 365' unless days.between?(1, 365)

      puts JSON.pretty_generate(Custom::Kanban::Metrics.new(account, since: days.days.ago).to_h)
    end

    desc 'Marks a user as the fazer.ai agents\' service user, or with UNMARK=1 clears it: rake "flow:kanban:agent_bot[agents@example.com]"'
    task :agent_bot, [:email] => :environment do |_task, args|
      user = User.from_email(args[:email].to_s)
      abort 'Usage: rake "flow:kanban:agent_bot[EMAIL]" (UNMARK=1 to clear)' unless user

      ENV['UNMARK'].present? ? Custom::Kanban::ServiceUser.unmark!(user) : Custom::Kanban::ServiceUser.mark!(user)
      puts "#{user.email}: agent_bot=#{Custom::Kanban::ServiceUser.agent_bot?(user)}"
    end
  end
end
