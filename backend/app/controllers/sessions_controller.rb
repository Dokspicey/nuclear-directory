# Admin sign-in and sign-out (/admin/sign-in).
class SessionsController < ApplicationController
  include Authentication
  allow_unauthenticated_access only: %i[ new create ]
  # The app's cache in production; tests use their own store, since the test
  # cache keeps nothing (as CorrectionsController does).
  RATE_LIMIT_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  rate_limit to: 10, within: 3.minutes, only: :create, store: RATE_LIMIT_STORE,
    with: -> { redirect_to new_session_path, alert: "Too many attempts. Try again in a few minutes." }
  layout "admin"

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "That email address and password don't match."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
