# The admin login on the UI preview (render.yaml, nuclear-directory-preview),
# so admin screens can be tried there. bin/preview-start calls it after every
# reset via `bin/rails preview:admin`. It refuses to run anywhere but the
# preview: NOINDEX must be "1" and the database must be
# nuclear_directory_preview. The live site never sets NOINDEX, and the
# blueprint check refuses PREVIEW_ADMIN_PASSWORD on any other service.
module PreviewAdmin
  EMAIL = "preview@nuclear-directory.org".freeze
  HANDLE = "preview".freeze
  DATABASE = "nuclear_directory_preview".freeze

  class NotPreview < StandardError; end

  module_function

  # Creates or updates the preview admin. Returns a line to log; never the
  # password.
  def ensure!(env: ENV, connection: ActiveRecord::Base.connection)
    unless env["NOINDEX"] == "1" && connection.current_database == DATABASE
      raise NotPreview, "preview:admin only runs on the preview (NOINDEX=1, database #{DATABASE}); " \
        "this is #{connection.current_database.inspect}. Nothing changed."
    end

    password = env["PREVIEW_ADMIN_PASSWORD"].to_s
    return "preview:admin: PREVIEW_ADMIN_PASSWORD isn't set, so the preview has no admin login." if password.empty?

    user = User.find_or_initialize_by(email_address: EMAIL)
    user.update!(handle: HANDLE, password:)
    "preview:admin: #{EMAIL} can sign in to the preview's admin."
  end
end
