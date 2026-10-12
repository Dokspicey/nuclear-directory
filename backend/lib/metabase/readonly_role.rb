# The read-only Postgres role local Metabase uses on production (#111).
# Tosin creates it from the Render shell with `bin/rails
# metabase:create_readonly_role` (see README.md); the password is typed
# there and kept only in his password manager.
#
# Writes fail twice over: every transaction is read-only, and the role has
# no INSERT, UPDATE, DELETE or DDL grants anyway. It can't read users or
# sessions (password digests, sign-in data), and it's granted nothing on any
# other database (e.g. the preview's). Safe to rerun: it updates the password
# and reapplies the grants. A restore from backup (pg_dump --no-owner
# --no-acl) doesn't carry roles or grants, so rerun it after one.
module Metabase
  module ReadonlyRole
    NAME = "metabase_ro"
    # Tables holding sign-in data, never readable through Metabase.
    PRIVATE_TABLES = %w[users sessions].freeze

    module_function

    # Creates or updates the role in the current database. owner: the role
    # that creates the app's tables, so future tables are readable too.
    def apply!(password:, name: NAME, connection: ActiveRecord::Base.connection)
      raise ArgumentError, "a password of at least 20 characters" if password.to_s.length < 20

      role = connection.quote_column_name(name)
      database = connection.quote_column_name(connection.current_database)
      owner = connection.quote_column_name(connection.select_value("SELECT current_user"))

      connection.transaction do
        unless connection.select_value("SELECT 1 FROM pg_roles WHERE rolname = #{connection.quote(name)}")
          connection.execute("CREATE ROLE #{role} LOGIN")
        end
        # The password never goes to the log.
        ActiveRecord::Base.logger.silence do
          connection.execute("ALTER ROLE #{role} WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION " \
            "CONNECTION LIMIT 5 PASSWORD #{connection.quote(password)}")
        end
        connection.execute("ALTER ROLE #{role} SET default_transaction_read_only = on")
        connection.execute("ALTER ROLE #{role} SET statement_timeout = '60s'")
        connection.execute("GRANT CONNECT ON DATABASE #{database} TO #{role}")
        connection.execute("GRANT USAGE ON SCHEMA public TO #{role}")
        connection.execute("GRANT SELECT ON ALL TABLES IN SCHEMA public TO #{role}")
        connection.execute("ALTER DEFAULT PRIVILEGES FOR ROLE #{owner} IN SCHEMA public GRANT SELECT ON TABLES TO #{role}")
        private_tables = PRIVATE_TABLES.select { |table| connection.table_exists?(table) }
        connection.execute("REVOKE ALL ON #{private_tables.map { |t| connection.quote_table_name(t) }.join(', ')} FROM #{role}") if private_tables.any?
      end
    end

    # Whether the current user may create roles (Render's database owner
    # should); a clear message beats a Postgres error in the shell.
    def can_create_roles?(connection: ActiveRecord::Base.connection)
      connection.select_value("SELECT rolcreaterole OR rolsuper FROM pg_roles WHERE rolname = current_user")
    end
  end
end
