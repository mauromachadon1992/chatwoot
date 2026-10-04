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
  initializer 'flow_custom.migrations' do |app|
    config.paths['db/migrate'].expanded.each do |path|
      app.config.paths['db/migrate'] << path unless app.config.paths['db/migrate'].include?(path)
    end
  end

  # Prepended so these routes are matched before any catch-all the host declares.
  initializer 'flow_custom.routes' do |app|
    app.routes.prepend(&FlowCustom::Routes::DRAW)
  end
end
