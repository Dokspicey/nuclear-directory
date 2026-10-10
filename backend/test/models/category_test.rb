require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "eight categories in display order" do
    assert_equal [ "Fuel suppliers", "Reactor developers", "Plants and sites", "Utilities and operators",
      "Repair and services", "Power buyers", "Investors", "Fusion" ], Category.all.map(&:name)
  end

  test "find by key" do
    assert_equal "Fuel suppliers", Category.find("fuel").name
    assert_equal "fuel", Category.find("fuel").to_param
    assert_nil Category.find("nope")
  end

  test "every role key a category uses is a seeded role" do
    roles_block = File.read(Rails.root.join("db/seeds.rb"))[/^ROLES = \[(.*?)^\]\.freeze/m, 1]
    seeded_roles = roles_block.scan(/\[ "([a-z_]+)", /).flatten

    assert_includes seeded_roles, "reactor_vendor"
    assert_not_includes seeded_roles, "fusion"
    Category.all.flat_map(&:role_keys).each { |key| assert_includes seeded_roles, key }
  end
end
