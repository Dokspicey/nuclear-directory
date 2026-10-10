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
end
