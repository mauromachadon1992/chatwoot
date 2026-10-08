namespace :flow do
  namespace :identity do
    desc 'Applies the Flow identity (name, logos, icon, accent) to this installation: rake "flow:identity:apply"'
    task apply: :environment do
      page = Custom::Identity.apply!
      puts "identity applied: #{page.name} #{page.accent_color} (sign-in page enabled: #{page.enabled})"
    end

    desc 'Back to the Chatwoot screens: rake "flow:identity:reset"'
    task reset: :environment do
      Custom::Identity.reset!
      puts 'identity reset: the sign-in page settings and images are gone'
    end
  end
end
