require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  def load_seeds
    silence_warnings { load Rails.root.join("db/seeds.rb") }
  end

  test "seeds roles and technologies" do
    load_seeds

    assert Role.find_by!(key: "reactor_vendor").description.present?
    assert_equal Role.find_by!(key: "coolant"), Role.find_by!(key: "molten_salt").parent
    assert_equal Technology.find_by!(key: "fission"), Technology.find_by!(key: "smr").parent
    assert_nil Technology.find_by!(key: "fusion").parent
  end

  test "is safe to re-run" do
    load_seeds
    Role.find_by!(key: "fuel").update!(name: "Edited")

    assert_no_difference([ "Role.count", "Technology.count" ]) { load_seeds }
    assert_equal "Fuel", Role.find_by!(key: "fuel").name
  end
end
