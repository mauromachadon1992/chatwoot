# The Flow customizations live under `custom/` so a merge from fazer-ai/chatwoot never has
# to touch them. Chatwoot already treats `custom` as an extension next to `enterprise`
# (`ChatwootApp.extensions`), so `prepend_mod_with('Foo')` picks up a `Custom::Foo` module
# defined here. This engine adds what that mechanism does not: autoloading `custom/app`,
# our migrations, locales, initializers and routes.
#
# It is deliberately not an isolated engine: the models share the host's tables, policies
# and API namespace, exactly as the code under `enterprise/` does.
module FlowCustom; end

require_relative 'routes'

class FlowCustom::Engine < Rails::Engine
  # name => [cron, job class], registered when a Sidekiq server starts.
  CRON_JOBS = {
    'flow_kanban_task_reminders' => ['* * * * *', 'Custom::Kanban::TaskReminderJob'],
    'flow_kanban_notification_cleanup' => ['30 3 * * *', 'Custom::Kanban::NotificationCleanupJob'],
    'flow_kanban_stale_cards' => ['15 * * * *', 'Custom::Kanban::StaleCardsJob']
  }.freeze

  initializer 'flow_custom.migrations' do |app|
    config.paths['db/migrate'].expanded.each do |path|
      app.config.paths['db/migrate'] << path unless app.config.paths['db/migrate'].include?(path)
    end
  end

  # The Kanban's recurring jobs (task reminders every minute, stalled deals hourly, notification
  # cleanup daily). Registered here, as dynamic cron entries, instead of in config/schedule.yml,
  # so a merge from upstream never conflicts with them and the host's cleanup of `schedule`
  # entries leaves them alone. Creating them again on each worker start is a no-op.
  initializer 'flow_custom.cron' do
    Sidekiq.configure_server do |config|
      config.on(:startup) do
        CRON_JOBS.each do |name, (cron, job)|
          # (sidekiq-cron has no bang version of create.)
          Sidekiq::Cron::Job.create(name: name, cron: cron, queue: 'scheduled_jobs', class: job)
        end
      end
    end
  end

  # Prepended so these routes are matched before any catch-all the host declares.
  initializer 'flow_custom.routes' do |app|
    app.routes.prepend(&FlowCustom::Routes::DRAW)
  end
end
