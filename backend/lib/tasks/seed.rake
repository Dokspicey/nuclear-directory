namespace :seed do
  desc "Dry run: list names, aliases and domains the seed would collide on in this database"
  task check: :environment do
    collisions = Seed::OrganizationLoader.new(Rails.root.join("db/seeds/organizations")).collisions
    puts collisions.any? ? collisions : "No collisions: the seed's names, aliases and domains are free or already its own."
    exit 1 if collisions.any?
  end
end
