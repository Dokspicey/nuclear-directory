require "test_helper"

# The role Metabase reads production with (#111): reads work, writes and
# sign-in data don't. It runs outside a transaction, since the role's own
# connection must see the grants, and drops the role afterwards.
class Metabase::ReadonlyRoleTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  PASSWORD = "test-only-password-not-real-0123456789".freeze

  setup do
    @name = "metabase_ro_test_#{Process.pid}"
    Metabase::ReadonlyRole.apply!(name: @name, password: PASSWORD)
  end

  teardown do
    @session&.close
    connection = ActiveRecord::Base.connection
    role = connection.quote_column_name(@name)
    connection.execute("DROP TABLE IF EXISTS metabase_later_table")
    connection.execute("DROP OWNED BY #{role}")
    connection.execute("DROP ROLE IF EXISTS #{role}")
  end

  def session
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    @session ||= PG.connect(host: config[:host] || "localhost", port: config[:port], dbname: ActiveRecord::Base.connection.current_database,
      user: @name, password: PASSWORD)
  end

  def refused(sql)
    error = assert_raises(PG::Error) { session.exec(sql) }
    session.exec("ROLLBACK") if session.transaction_status != PG::PQTRANS_IDLE
    error
  end

  test "it reads the directory but can't write, change the schema or read sign-in data" do
    assert_equal "0", session.exec("SELECT count(*) FROM organizations WHERE slug = 'none'").getvalue(0, 0)

    assert_match "read-only transaction", refused("INSERT INTO organizations (name, slug, country_code, created_at, updated_at) " \
      "VALUES ('X', 'x', 'US', now(), now())").message
    assert_match "read-only transaction", refused("UPDATE organizations SET name = 'X'").message
    assert_match "read-only transaction", refused("DELETE FROM organizations").message
    assert_match "read-only transaction", refused("CREATE TABLE metabase_probe (id int)").message
    assert_match "permission denied", refused("SELECT * FROM users").message
    assert_match "permission denied", refused("SELECT * FROM sessions").message
  end

  test "writes stay refused even if a session turns read-only off" do
    session.exec("SET default_transaction_read_only = off")

    assert_match "permission denied", refused("INSERT INTO organizations (name, slug, country_code, created_at, updated_at) " \
      "VALUES ('X', 'x', 'US', now(), now())").message
    assert_match "permission denied", refused("CREATE TABLE metabase_probe (id int)").message
  end

  test "a table added later is readable, and rerunning updates the role" do
    ActiveRecord::Base.connection.execute("CREATE TABLE metabase_later_table (id int)")
    assert_equal "0", session.exec("SELECT count(*) FROM metabase_later_table").getvalue(0, 0)

    assert_nothing_raised { Metabase::ReadonlyRole.apply!(name: @name, password: PASSWORD) }
    assert_raises(ArgumentError) { Metabase::ReadonlyRole.apply!(name: @name, password: "short") }
  end
end
