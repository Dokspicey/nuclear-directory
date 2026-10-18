require "test_helper"
require_relative "../support/directory_builders"

# Which names each home page card shows (#362; Tosin, 17 Oct).
class HomeCategoriesTest < ActiveSupport::TestCase
  include DirectoryBuilders

  def card(key) = HomeCategories.cards.find { |c| c.category.key == key }
  def names(key) = card(key).records.map(&:name)

  setup do
    @vendor = role("reactor_vendor")
    @plant = cite!(plant("Plant Vogtle", facility_type: "power_reactor", status: "operating"))
  end

  test "the three companies with the most sourced links, ties by name" do
    big = cite!(company("Westinghouse", roles: [ @vendor ]))
    %w[Alpha Beta Gamma].each { |name| cite!(link(big, "supplies", cite!(company(name)))) }
    mid = cite!(company("Kairos Power", roles: [ @vendor ]))
    cite!(link(mid, "owns", @plant))
    cite!(company("Oklo", roles: [ @vendor ]))
    cite!(company("NuScale Power", roles: [ @vendor ]))

    assert_equal [ "Westinghouse", "Kairos Power", "NuScale Power" ], names("reactor-developers"), "Oklo ties NuScale on 0 and loses on name"
    assert_equal 4, card("reactor-developers").count
    assert card("reactor-developers").more?
  end

  test "unsourced or unpublished links don't count" do
    quiet = cite!(company("Quiet Co", roles: [ @vendor ]))
    link(quiet, "owns", @plant) # no source
    3.times { |i| link(quiet, "supplies", cite!(company("Hidden #{i}", verified: false))) }
    loud = cite!(company("Loud Co", roles: [ @vendor ]))
    cite!(link(loud, "owns", @plant))

    assert_equal [ "Loud Co", "Quiet Co" ], names("reactor-developers")
  end

  test "investors rank by how many companies they fund, not by their links" do
    a, b, c = %w[A B C].map { |name| cite!(company("Startup #{name}")) }
    big = cite!(company("Big Fund"))
    cite!(link(big, "funds", a), link(big, "invests_in", a), link(big, "supplies", b), link(big, "supplies", c)) # 4 links, funds 1
    spread = cite!(company("Spread Ventures"))
    cite!(link(spread, "invests_in", a), link(spread, "invests_in", b)) # 2 links, funds 2

    assert_equal [ "Spread Ventures", "Big Fund" ], names("investors")
  end

  test "Plants and sites is the last card, ranked by sourced links" do
    cite!(company("Kairos Power", roles: [ @vendor ]))
    quiet = cite!(plant("Quiet Plant"))
    busy = cite!(plant("Busy Plant"))
    2.times { |i| cite!(link(cite!(company("Owner #{i}")), "owns", busy)) }

    assert_equal "plants", HomeCategories.cards.last.category.key
    assert_equal [ "Busy Plant", "Plant Vogtle", "Quiet Plant" ], names("plants")
    assert_not_includes HomeCategories.cards.map { |c| c.category.key }, "components", "an empty bucket has no card"
    assert_equal "Quiet Plant", quiet.name
  end

  test "only records with a public page" do
    cite!(company("Pending Co", roles: [ @vendor ], verified: false))
    plant("Hidden Site", verified: false)
    cite!(company("Kairos Power", roles: [ @vendor ]))

    assert_equal [ "Kairos Power" ], names("reactor-developers")
    assert_not_includes names("plants"), "Hidden Site"
    assert_not card("reactor-developers").more?
  end
end
