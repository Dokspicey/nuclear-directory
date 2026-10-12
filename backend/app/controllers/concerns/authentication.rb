# Sign-in for the admin (Rails 8's generated authentication). Only the admin
# controllers include it; the public site has no accounts. There's one admin
# account, made with `bin/rails admin:create`; there's no sign-up and no
# password reset by email (run admin:create again to set a new password).
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    # Admin pages stay out of search engines.
    after_action { response.set_header("X-Robots-Tag", "noindex, nofollow") }
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.where(created_at: 30.days.ago..).find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      # Only a page can be returned to; a form's POST can't be replayed as a GET.
      session[:return_to_after_authenticating] = request.url if request.get?
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || admin_root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed[:session_id] = { value: session.id, httponly: true, same_site: :lax, expires: 30.days }
        # Marks this browser as ours in analytics; signing out leaves it (#211).
        AdminVisitor.mark!(cookies, secure: request.ssl?)
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
