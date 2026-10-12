require "io/console"

namespace :metabase do
  desc "Create or update the read-only role local Metabase uses (#111). Prompts for its password; safe to rerun"
  task create_readonly_role: :environment do
    unless Metabase::ReadonlyRole.can_create_roles?
      abort "This database user can't create roles. Run this as the database owner (Render shell on the web service)."
    end

    password = ENV["METABASE_RO_PASSWORD"].presence || begin
      console = IO.console or abort "No terminal to type the password in; set METABASE_RO_PASSWORD instead."
      first = console.getpass("Password for #{Metabase::ReadonlyRole::NAME} (paste from your password manager): ")
      second = console.getpass("Same password again: ")
      abort "The two passwords don't match; nothing was changed." unless first == second
      first
    end

    Metabase::ReadonlyRole.apply!(password:)
    database = ActiveRecord::Base.connection.current_database
    puts "#{Metabase::ReadonlyRole::NAME} is ready: read-only on #{database}, no access to " \
      "#{Metabase::ReadonlyRole::PRIVATE_TABLES.join(' or ')}."
  end
end
