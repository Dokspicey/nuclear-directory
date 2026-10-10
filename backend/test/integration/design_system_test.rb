require "test_helper"

class DesignSystemTest < ActionDispatch::IntegrationTest
  test "the design reference page renders every component" do
    get design_system_path
    assert_response :success

    %w[nd-btn nd-search nd-az nd-filterbar nd-card nd-table nd-empty nd-banner nd-tabs nd-overview nd-src nd-badge nd-conf nd-graph].each do |component|
      assert_select ".#{component}", { minimum: 1 }, "missing #{component}"
    end
    assert_select "svg.nd-ic", minimum: 20
  end

  test "it renders every shared page part with mock records" do
    get design_system_path

    within_parts = "#page-parts"
    %w[nd-sitebar nd-pills nd-cats nd-listrow nd-profile nd-factrow nd-gaps nd-sources nd-notice nd-overview].each do |part|
      assert_select "#{within_parts} .#{part}", { minimum: 1 }, "missing #{part}"
    end
    assert_select "#{within_parts} .nd-listrow", 4
  end
end
