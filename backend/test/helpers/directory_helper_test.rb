require "test_helper"

class DirectoryHelperTest < ActionView::TestCase
  test "relationship verbs read left to right in visitors' words" do
    assert_equal "offtakes from", relationship_verb("offtake_with")
    assert_equal "invests in", relationship_verb(:invests_in)
    assert_equal "is a subsidiary of", relationship_verb("subsidiary_of")
    assert_equal "is the reactor vendor for", facility_relationship_verb("vendor_for")
    assert_raises(KeyError) { relationship_verb("partners_with") }
  end

  test "every data type has a label" do
    assert_equal Facility.facility_types.keys.sort, FACILITY_TYPE_LABELS.keys.sort
    assert_equal Facility.statuses.keys.sort, FACILITY_STATUS_LABELS.keys.sort
    assert_equal Relationship.relationship_types.keys.sort, RELATIONSHIP_VERBS.keys.sort
    assert_equal FacilityRelationship.relationship_types.keys.sort, FACILITY_RELATIONSHIP_VERBS.keys.sort
  end

  test "labels use the words in VOICE.md" do
    assert_equal "Power plant", facility_type_label("power_reactor")
    assert_equal "Reactor developer", role_label("reactor_vendor")
    assert_equal "Power buyer", role_label("data_center_offtaker")
    assert_nil facility_type_label(nil)
    assert_nil facility_status_label(nil)
  end

  test "confidence becomes bars and a word, and nothing when unknown" do
    assert_equal({ bars: 3, word: "High" }, confidence_level(1.0))
    assert_equal({ bars: 3, word: "High" }, confidence_level(0.9))
    assert_equal({ bars: 2, word: "Medium" }, confidence_level(0.8))
    assert_equal({ bars: 1, word: "Low" }, confidence_level(0.4))
    assert_nil confidence_level(nil)
  end

  test "initials take the first two words" do
    assert_equal "KP", initials("Kairos Power")
    assert_equal "XE", initials("X-energy")
    assert_equal "WE", initials("Westinghouse Electric Company")
    assert_equal "TV", initials("The Tennessee Valley Authority")
    assert_equal "O", initials("Oklo")
  end

  test "place joins what is known and is nil when nothing is" do
    assert_equal "Alameda, CA", place("Alameda", "CA")
    assert_equal "CA", place(nil, "CA")
    assert_nil place("", nil)
  end

  test "public URLs" do
    assert_equal "/companies", directory_url_for
    assert_equal "/companies?category=fuel&q=haleu", directory_url_for(category: Category.find("fuel"), q: "haleu")
    assert_equal "/companies/terrapower", company_url_for(organizations(:terrapower))
    assert_equal "/plants/vogtle", plant_url_for(facilities(:vogtle))
  end

  test "dates" do
    assert_equal "2024-10-14", data_date(Date.new(2024, 10, 14))
    assert_equal "October 2024", prose_month(Date.new(2024, 10, 14))
    assert_nil data_date(nil)
  end
end
