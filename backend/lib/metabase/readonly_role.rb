# The read-only Postgres role local Metabase uses on production (#111).
# Tosin creates it from the Render shell with `bin/rails
# metabase:create_readonly_role` (see docs/metabase.md); the password is typed
# there and kept only in his password manager.
#
# Writes fail twice over: its transactions are read-only by default, and the
# role has no INSERT, UPDATE, DELETE or DDL grants anyway (so turning
# read-only off doesn't help). It can't read private tables (PRIVATE_TABLES:
# sign-in data, visitors' correction messages and contacts, and the job,
# cache and cable tables, whose rows can carry those), and it's granted
# nothing on any other database (e.g. the preview's). Safe to rerun: it updates the password
# and reapplies the grants. A restore from backup (pg_dump --no-owner
# --no-acl) doesn't carry roles or grants, so rerun it after one.
module Metabase
  module ReadonlyRole
    NAME = "metabase_ro"
    # Never readable through Metabase. Tables are granted when this runs, not
    # by default privileges, so a table added later stays unreadable until
    # it's rerun; a new table with sign-in or personal data goes here before
    # that.
    PRIVATE_TABLES = %w[users sessions correction_reports].freeze
    # Rails' own Solid Queue, Cache and Cable tables (job arguments can hold
    # an email address).
    PRIVATE_PREFIXES = %w[solid_].freeze
    # Attributes the role must never have; checked on an existing role, since
    # Render's owner (not a superuser) may not set them, and so can't clear them.
    UNSAFE_ATTRIBUTES = %w[rolsuper rolcreaterole rolcreatedb rolreplication rolbypassrls].freeze

    class Unsafe < StandardError; end

    module_function

    # Creates or updates the role in the current database. owner: the role
    # that creates the app's tables, so future tables are readable too.
    def apply!(password:, name: NAME, connection: ActiveRecord::Base.connection)
      raise ArgumentError, "a password of at least 20 characters" if password.to_s.length < 20

      role = connection.quote_column_name(name)
      database = connection.quote_column_name(connection.current_database)
      owner = connection.quote_column_name(connection.select_value("SELECT current_user"))

      connection.transaction do
        ActiveRecord::Base.logger.silence { account_statements(name:, password:, connection:).each { |sql| connection.execute(sql) } }
        # A rerun starts from nothing, so a right granted by hand in between
        # (INSERT on a table, CREATE on the schema) doesn't survive it.
        connection.execute("REVOKE ALL ON ALL TABLES IN SCHEMA public FROM #{role}")
        connection.execute("REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM #{role}")
        connection.execute("REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM #{role}")
        connection.execute("REVOKE ALL ON SCHEMA public FROM #{role}")
        connection.execute("REVOKE ALL ON DATABASE #{database} FROM #{role}")
        connection.execute("ALTER DEFAULT PRIVILEGES FOR ROLE #{owner} IN SCHEMA public REVOKE ALL ON TABLES FROM #{role}")

        connection.execute("GRANT CONNECT ON DATABASE #{database} TO #{role}")
        connection.execute("GRANT USAGE ON SCHEMA public TO #{role}")
        readable = connection.tables - private_tables(connection)
        connection.execute("GRANT SELECT ON #{readable.map { |t| connection.quote_table_name(t) }.join(', ')} TO #{role}") if readable.any?
      end
    end

    # Creates the role if it's new, then sets its password and limits. It
    # names no privileged attributes at all: a new role starts without them,
    # and an existing one that has any is refused, not reused (Render's
    # owner, not a superuser, couldn't take them away). Only a
    # SCRAM-SHA-256 verifier, computed here, is sent: the password itself
    # never reaches Postgres, so no server log can hold it.
    def account_statements(name:, password:, connection:)
      role = connection.quote_column_name(name)
      existing = connection.select_one("SELECT #{UNSAFE_ATTRIBUTES.join(', ')} FROM pg_roles WHERE rolname = #{connection.quote(name)}")
      unsafe = existing.to_h.select { |_, value| value }.keys
      raise Unsafe, "#{name} already exists with #{unsafe.join(', ')}; drop it as a superuser and run this again" if unsafe.any?
      # A member of another role (the app's owner, say) inherits its rights.
      member_of = connection.select_values("SELECT r.rolname FROM pg_auth_members m JOIN pg_roles r ON r.oid = m.roleid " \
        "JOIN pg_roles u ON u.oid = m.member WHERE u.rolname = #{connection.quote(name)}")
      raise Unsafe, "#{name} is a member of #{member_of.join(', ')}; drop the role and run this again" if member_of.any?

      verifier = connection.raw_connection.encrypt_password(password, name, "scram-sha-256")
      [
        ("CREATE ROLE #{role} LOGIN" unless existing),
        "ALTER ROLE #{role} WITH LOGIN CONNECTION LIMIT 5 PASSWORD #{connection.quote(verifier)}",
        "ALTER ROLE #{role} SET default_transaction_read_only = on",
        "ALTER ROLE #{role} SET statement_timeout = '60s'"
      ].compact
    end

    def private_tables(connection)
      connection.tables.select { |table| PRIVATE_TABLES.include?(table) || table.start_with?(*PRIVATE_PREFIXES) }
    end

    # Whether the current user may create roles (Render's database owner
    # should); a clear message beats a Postgres error in the shell.
    def can_create_roles?(connection: ActiveRecord::Base.connection)
      connection.select_value("SELECT rolcreaterole OR rolsuper FROM pg_roles WHERE rolname = current_user")
    end
  end
end
