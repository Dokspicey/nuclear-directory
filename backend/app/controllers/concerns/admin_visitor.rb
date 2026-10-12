# Whether this browser is ours (#211): its visits to the public site are
# marked internal: true in analytics. Tosin's home IP changes, so
# INTERNAL_IPS alone can't catch them.
#
# Signing in to the admin sets INTERNAL_COOKIE (signed, HttpOnly, a year),
# and signing out leaves it, so the browser stays marked. A browser signed
# in before that cookie existed is caught by its live admin session.
# Visitors have neither, so for them nothing is looked up and nothing
# changes.
module AdminVisitor
  extend ActiveSupport::Concern

  INTERNAL_COOKIE = :nd_internal

  # Set on every admin sign-in (Authentication#start_new_session_for).
  def self.mark!(cookies, secure:)
    cookies.signed[INTERNAL_COOKIE] = { value: "1", httponly: true, secure:, same_site: :lax, expires: 1.year }
  end

  private
    def admin_visitor?
      return @admin_visitor if defined?(@admin_visitor)

      @admin_visitor = cookies.signed[INTERNAL_COOKIE] == "1" || live_admin_session?
    end

    def live_admin_session?
      id = cookies.signed[:session_id]
      id.present? && Session.where(created_at: 30.days.ago..).exists?(id:)
    end
end
