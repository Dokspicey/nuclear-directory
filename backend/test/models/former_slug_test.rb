require "test_helper"

class FormerSlugTest < ActiveSupport::TestCase
  test "changing a slug keeps the old one, and a record that takes it back clears it" do
    plant = Facility.create!(name: "Advanced Test Reactor (ATR)")
    plant.update!(name: "Advanced Test Reactor", slug: "advanced-test-reactor")

    assert_equal plant, Facility.find_by_former_slug("advanced-test-reactor-atr")
    assert_nil Organization.find_by_former_slug("advanced-test-reactor-atr"), "per type"

    other = Facility.create!(name: "Another", slug: "advanced-test-reactor-atr")
    assert_nil Facility.find_by_former_slug("advanced-test-reactor-atr"), "a live slug wins"
    assert other.persisted?
  end

  test "a slug changed back and forth keeps each old one once" do
    plant = Facility.create!(name: "Acme Plant")
    plant.update!(slug: "acme")
    plant.update!(slug: "acme-plant")

    assert_equal [ "acme" ], plant.former_slugs.pluck(:slug)
  end
end
