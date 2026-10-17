require "test_helper"
require_relative "../support/directory_builders"

# The bucket rules in docs/DATA.md section 4 (#281).
class BucketTest < ActiveSupport::TestCase
  include DirectoryBuilders

  def in_bucket(key) = Organization.where(id: Bucket.organization_ids(Category.find(key))).order(:name).pluck(:name)

  setup do
    @utility = role("utility")
    @vogtle = cite!(plant("Plant Vogtle", facility_type: "power_reactor", status: "operating"))
    @shut = cite!(plant("Old Station", facility_type: "power_reactor", status: "shut_down"))
  end

  test "a role puts a company in its bucket, child roles included, once it has a source" do
    fuel = role("fuel")
    cite!(company("Centrus Energy", roles: [ role("enrichment", parent: fuel) ]))
    cite!(company("Holtec", roles: [ role("waste_decommissioning") ]))
    company("Unsourced Fuel Co", roles: [ fuel ])
    company("Pending Fuel Co", roles: [ fuel ], verified: false).then { |org| cite!(org) }

    assert_equal [ "Centrus Energy" ], in_bucket("fuel")
    assert_equal [ "Holtec" ], in_bucket("waste-decommissioning")
    assert_empty in_bucket("components"), "no company has the role yet"
  end

  test "utilities and operators: the role, or a current owns or operates link to an operating power plant" do
    cite!(company("Duke Energy", roles: [ @utility ]))
    cite!(link(company("Southern Nuclear").then { |org| cite!(org) }, "operates", @vogtle))
    unit = cite!(plant("Vogtle Unit 3", parent: cite!(plant("Vogtle Site")), facility_type: "power_reactor", status: "operating"))
    cite!(link(cite!(company("MEAG Power")), "owns", unit.parent)) # a site with an operating unit counts
    cite!(link(cite!(company("Old Owner")), "owns", @shut))
    link(cite!(company("Unsourced Operator")), "operates", @vogtle)
    cite!(link(cite!(company("Former Operator")), "operates", @vogtle)).update!(ended_on: 1.year.ago.to_date)
    cite!(link(cite!(company("Future Owner")), "owns", @vogtle)).update!(started_on: 1.year.from_now.to_date)
    fuel_plant = cite!(plant("Fuel Plant", facility_type: "fuel_facility", status: "operating"))
    cite!(link(cite!(company("Fuel Plant Operator")), "operates", fuel_plant))

    assert_equal [ "Duke Energy", "MEAG Power", "Southern Nuclear" ], in_bucket("utilities")
  end

  test "power buyers: the role, or the buyer in a power deal, unless the buyer is a utility" do
    kairos = cite!(company("Kairos Power"))
    cite!(company("Switch", roles: [ role("data_center_offtaker") ]))
    cite!(link(cite!(company("Google")), "offtake_with", kairos))
    cite!(link(cite!(company("Amazon")), "offtakes_from", @vogtle))
    cite!(link(cite!(company("TVA", roles: [ @utility ])), "offtake_with", kairos))
    link(cite!(company("Quiet Buyer")), "offtake_with", kairos)

    assert_equal [ "Amazon", "Google", "Switch" ], in_bucket("power-buyers")
  end

  test "investors: the role, or the funder in an invests_in or funds link, unless it's government" do
    kairos = cite!(company("Kairos Power"))
    cite!(company("Khosla Ventures", roles: [ role("venture_capital") ]))
    cite!(link(cite!(company("Amazon")), "invests_in", kairos))
    cite!(link(cite!(company("Bill Fund")), "funds", kairos))
    doe = cite!(company("US Department of Energy", roles: [ role("government_agency") ]))
    cite!(link(doe, "funds", kairos))

    assert_equal [ "Amazon", "Bill Fund", "Khosla Ventures" ], in_bucket("investors")
    assert_equal [ "US Department of Energy" ], in_bucket("government-research")
  end

  test "a company is in every bucket it qualifies for, in display order, and totals count it once" do
    westinghouse = cite!(company("Westinghouse", roles: [ role("reactor_vendor"), role("fuel"), role("reactor_services") ]))
    cite!(company("Oklo", roles: [ Role.find_by!(key: "reactor_vendor") ]))

    assert_equal [ "Reactor developers", "Fuel and materials", "Services and engineering" ], Bucket.for(westinghouse).map(&:name)
    counts = Bucket.counts
    assert_equal({ "reactor-developers" => 2, "fuel" => 1, "services" => 1 }, counts.select { |_, n| n.positive? })
    assert_operator counts.values.sum, :>, Organization.published.count, "buckets overlap"
    assert_equal 2, DirectoryListing.new.companies.size, "the full list counts each company once"
  end

  test "tags list companies by technology or role, sourced and published only" do
    cite!(company("Helion", techs: [ technology("fusion") ]))
    company("Unsourced Fusion", techs: [ Technology.find_by!(key: "fusion") ])
    cite!(company("Energy Fuels", roles: [ role("mining", parent: role("fuel")) ]))

    assert_equal [ "Helion" ], Organization.where(id: Tag.find("fusion").organization_ids).pluck(:name)
    assert_equal [ "Energy Fuels" ], Organization.where(id: Tag.find("uranium").organization_ids).pluck(:name)
    assert_empty Organization.where(id: Tag.find("isotopes").organization_ids)
  end
end
