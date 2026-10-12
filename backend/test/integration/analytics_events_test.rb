require "test_helper"
require_relative "../support/directory_builders"
require_relative "../support/fake_posthog"

# The server-side events the real pages send (#68): a company or plant page
# viewed, and a correction sent. They were defined but never called.
class AnalyticsEventsTest < ActionDispatch::IntegrationTest
  include DirectoryBuilders
  include AnalyticsTestHelper

  BROWSER = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"

  def visit(path) = get(path, headers: { "User-Agent" => BROWSER })

  test "a company page sends company_viewed with its slug" do
    kairos = cite!(company("Kairos Power"))

    visit company_path(slug: kairos.slug)

    assert_response :success
    assert_equal [ [ "company_viewed", kairos.slug ] ], posthog.events.map { |e| [ e[:event], e[:properties]["slug"] ] }
  end

  test "a plant page sends power_plant_viewed with its slug" do
    vogtle = plant("Plant Vogtle", facility_type: "power_reactor")
    vogtle.evidence.create!(source: default_source, found_by: "human", confidence: 1)

    visit plant_path(slug: vogtle.slug)

    assert_response :success
    assert_equal [ [ "power_plant_viewed", vogtle.slug ] ], posthog.events.map { |e| [ e[:event], e[:properties]["slug"] ] }
  end

  test "a page that isn't found, or that moves, sends nothing" do
    visit company_path(slug: "no-such-company")
    assert_response :not_found
    assert_empty posthog.events
  end

  test "a correction sent sends correction_submitted with only what it's about" do
    post corrections_path, params: { subject: "Plant Vogtle", page_path: "/plants/plant-vogtle", message: "Unit 4 started in 2024.",
      contact: "a@example.com" }, headers: { "User-Agent" => BROWSER }

    event = posthog.events.sole
    assert_equal [ "correction_submitted", "plant" ], [ event[:event], event[:properties]["subject_type"] ]
    assert_not event[:properties].values.any? { |value| value.to_s.include?("Unit 4") || value.to_s.include?("a@example.com") },
      "never the message or contact"
  end

  test "a correction that doesn't save sends nothing" do
    post corrections_path, params: { subject: "Plant Vogtle", page_path: "/plants/plant-vogtle", message: "" },
      headers: { "User-Agent" => BROWSER }

    assert_response :unprocessable_entity
    assert_empty posthog.events
  end
end
