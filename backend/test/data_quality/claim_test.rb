require "test_helper"

class DataQuality::ClaimTest < ActiveSupport::TestCase
  def claim(kind, payload) = DataQuality::Claim.describe(Candidate.new(kind:, payload:))

  test "records name every attribute" do
    assert_equal "There is a plant named “Vogtle 3”, with NRC docket 05200025, plant type power reactor, and status operating.",
      claim("facility", { "name" => "Vogtle 3", "nrc_docket" => "05200025", "facility_type" => "power_reactor", "status" => "operating" })
  end

  test "roles and technologies are in visitors' words" do
    assert_equal "Kairos Power is a reactor developer.",
      claim("organization_role", { "organization" => { "name" => "Kairos Power" }, "role" => "reactor_vendor" })
    assert_equal "Constellation is an operator.",
      claim("organization_role", { "organization" => { "name" => "Constellation" }, "role" => "operator" })
    assert_equal "Oklo works on sodium fast reactor.",
      claim("organization_technology", { "organization" => { "name" => "Oklo" }, "technology" => "sodium_fast_reactor" })
  end

  test "links include every detail approval would publish" do
    text = claim("facility_relationship", { "organization" => { "name" => "Southern Company" },
      "facility" => { "name" => "Vogtle 3", "nrc_docket" => "05200025" }, "relationship_type" => "owns",
      "ownership_pct" => 45.7, "started_on" => "2023-07-31", "description" => "Majority owner" })

    assert_equal "Southern Company owns the plant Vogtle 3 (NRC docket 05200025), with ownership 45.7%, " \
      "started on 2023-07-31, and description Majority owner.", text

    assert_match "with description Series B lead",
      claim("relationship", { "from_organization" => { "name" => "Khosla Ventures" },
        "to_organization" => { "name" => "Oklo" }, "relationship_type" => "invests_in", "description" => "Series B lead" })
  end
end
