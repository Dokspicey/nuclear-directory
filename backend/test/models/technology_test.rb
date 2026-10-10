require "test_helper"

class TechnologyTest < ActiveSupport::TestCase
  test "sub-types point at their parent" do
    fission = Technology.create!(key: "fission", name: "Fission")
    smr = Technology.create!(key: "smr", name: "Small modular reactor", parent: fission)
    assert_includes fission.children, smr
  end

  test "key is unique and snake_case" do
    Technology.create!(key: "fusion", name: "Fusion")
    assert_not Technology.new(key: "fusion", name: "Fusion again").valid?
    assert_not Technology.new(key: "Fusion Power", name: "Bad key").valid?
  end

  test "a parent with children can't be deleted" do
    fission = Technology.create!(key: "fission", name: "Fission")
    Technology.create!(key: "smr", name: "SMR", parent: fission)
    assert_not fission.destroy
  end
end
