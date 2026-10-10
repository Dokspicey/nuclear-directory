require "test_helper"

class ErrorsTest < ActionDispatch::IntegrationTest
  # Tests normally show Rails' debug page for errors. Turn it off so the
  # request goes through the exceptions app, as it does in production.
  setup do
    @env_config = Rails.application.env_config.slice("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
    Rails.application.env_config.merge!("action_dispatch.show_exceptions" => :all, "action_dispatch.show_detailed_exceptions" => false)
  end

  teardown { Rails.application.env_config.merge!(@env_config) }

  test "an unknown page shows Page not found in the site layout" do
    get "/no-such-page"

    assert_response :not_found
    assert_select "h1", "Page not found"
    assert_select "form[role=search][action='/companies']"
    assert_select "a[href='/']", "go to the home page"
  end

  test "non-HTML requests get a bare 404" do
    get "/no-such-page.json"

    assert_response :not_found
    assert_empty response.body
  end
end
