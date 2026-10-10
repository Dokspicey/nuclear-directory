require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup do
    @user = users(:admin)
    SessionsController::RATE_LIMIT_STORE.clear
  end

  test "the sign-in page isn't indexed" do
    get new_session_path

    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select "meta[name=robots][content=?]", "noindex, nofollow"
    assert_select "meta[name=posthog-key]", count: 0
  end

  test "signing in goes to the admin" do
    post session_path, params: { email_address: @user.email_address, password: PASSWORD }

    assert_redirected_to admin_root_path
    assert cookies[:session_id]
  end

  test "a wrong password doesn't sign in" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
    follow_redirect!
    assert_select ".nd-flash[role=alert]", /don't match/
  end

  test "signing out" do
    sign_in_as(@user)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  test "a session older than 30 days no longer signs in" do
    sign_in_as(@user)
    Current.session.update!(created_at: 31.days.ago)

    get admin_root_path

    assert_redirected_to new_session_path
  end

  test "after 10 tries in 3 minutes, sign-in is refused for a while" do
    10.times { post session_path, params: { email_address: @user.email_address, password: "wrong" } }

    post session_path, params: { email_address: @user.email_address, password: PASSWORD }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id], "even the right password waits"
    assert_equal "Too many attempts. Try again in a few minutes.", flash[:alert]
  end

  test "only a page is remembered for after sign-in, not a form's POST" do
    post approve_admin_candidates_path, params: { candidate_id: 1 }
    post session_path, params: { email_address: @user.email_address, password: PASSWORD }
    assert_redirected_to admin_root_path

    sign_out
    get admin_pending_facts_path
    post session_path, params: { email_address: @user.email_address, password: PASSWORD }
    assert_redirected_to admin_pending_facts_url
  end

  test "an account needs a real email address" do
    assert_not User.new(email_address: "not an email", handle: "x", password: "a long enough password").valid?
  end

  test "the public site needs no sign-in" do
    get root_path
    assert_response :success
  end
end
