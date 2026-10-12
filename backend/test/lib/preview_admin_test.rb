require "test_helper"

# The preview's admin login (#187 follow-up): made only on the preview, from
# PREVIEW_ADMIN_PASSWORD, and never anywhere else.
class PreviewAdminTest < ActiveSupport::TestCase
  PASSWORD = "preview-only-test-password".freeze

  # The test database stands in for the preview's.
  def preview_connection
    connection = ActiveRecord::Base.connection
    connection.define_singleton_method(:current_database) { PreviewAdmin::DATABASE }
    connection
  ensure
    @patched = connection
  end

  teardown { @patched&.singleton_class&.send(:remove_method, :current_database) }

  def preview_env(**extra) = { "NOINDEX" => "1", "PREVIEW_ADMIN_PASSWORD" => PASSWORD }.merge(extra.transform_keys(&:to_s))

  test "on the preview it creates the admin, who can sign in" do
    message = PreviewAdmin.ensure!(env: preview_env, connection: preview_connection)

    user = User.find_by!(email_address: PreviewAdmin::EMAIL)
    assert_equal "preview", user.handle
    assert user.authenticate(PASSWORD)
    assert_not_includes message, PASSWORD
  end

  test "running it again updates the password instead of adding a user" do
    PreviewAdmin.ensure!(env: preview_env, connection: preview_connection)
    assert_no_difference("User.count") do
      PreviewAdmin.ensure!(env: preview_env("PREVIEW_ADMIN_PASSWORD" => "#{PASSWORD}-new"), connection: preview_connection)
    end
    assert User.find_by!(email_address: PreviewAdmin::EMAIL).authenticate("#{PASSWORD}-new")
  end

  test "without a password it skips and says so" do
    message = assert_no_difference("User.count") do
      PreviewAdmin.ensure!(env: preview_env("PREVIEW_ADMIN_PASSWORD" => ""), connection: preview_connection)
    end
    assert_match "isn't set", message
  end

  test "it refuses anywhere but the preview" do
    # The real test database isn't nuclear_directory_preview (checked before
    # the connection is made to look like the preview's).
    assert_raises(PreviewAdmin::NotPreview) { PreviewAdmin.ensure!(env: preview_env) }
    assert_raises(PreviewAdmin::NotPreview) { PreviewAdmin.ensure!(env: preview_env("NOINDEX" => nil), connection: preview_connection) }
    assert_nil User.find_by(email_address: PreviewAdmin::EMAIL)
  end

  test "a password the model rejects fails loudly" do
    assert_raises(ActiveRecord::RecordInvalid) do
      PreviewAdmin.ensure!(env: preview_env("PREVIEW_ADMIN_PASSWORD" => "short"), connection: preview_connection)
    end
  end
end
