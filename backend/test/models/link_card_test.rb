require "test_helper"

# The link-preview cards (#245), to Design's spec on #245 (direction E).
class LinkCardTest < ActiveSupport::TestCase
  # Stands in for PlantProfile: only what for_plant reads.
  Plant = Struct.new(:name, :facility_type, :state, :units, :capacity_mw, :operators, :owners, keyword_init: true) do
    def current_companies_for(type) = { "operates" => operators, "owns" => owners }.fetch(type).to_a.map { |name| Struct.new(:name).new(name) }
  end

  def vogtle(**overrides)
    Plant.new(name: "Plant Vogtle", facility_type: "power_reactor", state: "GA", units: Array.new(4), capacity_mw: BigDecimal("4530"),
      operators: [ "Southern Nuclear" ], owners: [ "Georgia Power", "Oglethorpe Power", "MEAG Power", "Dalton Utilities" ], **overrides)
  end

  def name_lines(name) = LinkCard.new(squares: [ "#fff" ], name:).send(:name_lines)

  test "the name takes the largest step at which it fits two lines" do
    assert_equal [ 190, [ "KAIROS POWER" ] ], name_lines("Kairos Power")
    assert_equal [ 190, [ "PLANT VOGTLE" ] ], name_lines("Plant Vogtle")
    assert_equal [ 132, [ "SUSQUEHANNA STEAM", "ELECTRIC STATION" ] ], name_lines("Susquehanna Steam Electric Station")
  end

  test "a name too long even at the smallest step ends its second line with '…' at a word" do
    size, lines = name_lines("A Name So Extraordinarily Long That It Cannot Possibly Fit On Two Lines At Any Of The Sizes")

    assert_equal 92, size
    assert_equal 2, lines.size
    assert lines.last.end_with?("…")
    assert_match(/\w…\z/, lines.last)
  end

  test "a plant card: type and state, role line with '+N', reactors and capacity as the page shows them" do
    card = LinkCard.for_plant(vogtle)

    assert_equal "Power plant · Georgia", card.label
    assert_equal "Operated by Southern Nuclear · Owned by Georgia Power + 3", card.role_text
    assert_equal "4 reactors · 4,530 MWe", card.footer_right
    assert_equal [ LinkCard::CATEGORY_COLORS["plants"] ], card.squares
    assert_equal "Plant Vogtle: Power plant · Georgia. Operated by Southern Nuclear · Owned by Georgia Power, Oglethorpe Power, " \
      "MEAG Power and Dalton Utilities. 4 reactors · 4,530 MWe.", card.alt
  end

  test "a role line too long even with one name each keeps its counts and shortens the longest name" do
    card = LinkCard.for_plant(vogtle(name: "Susquehanna", operators: [ "Susquehanna Nuclear, LLC" ],
      owners: [ "Talen Energy", "Allegheny Electric Cooperative" ]))

    assert_equal "Operated by Susquehanna Nuclear… · Owned by Talen Energy + 1", card.role_text
  end

  test "what isn't known is left off, never shown as 0 or blank" do
    card = LinkCard.for_plant(vogtle(facility_type: "fuel_facility", state: nil, units: [], capacity_mw: nil, operators: [], owners: [ "Orano" ]))
    assert_equal [ "Fuel plant", "Owned by Orano", nil ], [ card.label, card.role_text, card.footer_right ]

    bare = LinkCard.for_plant(vogtle(facility_type: nil, state: nil, units: [ 1 ], capacity_mw: nil, operators: [], owners: []))
    assert_equal [ nil, nil, "1 unit" ], [ bare.label, bare.subline, bare.footer_right ]
    assert_equal "Plant Vogtle. 1 unit.", bare.alt
  end

  test "a company card: role and HQ, then up to two facts in order" do
    profile = Struct.new(:organization, :shown_roles, :plant_links, :deals, :category).new(
      Organization.new(name: "Kairos Power", hq_city: "Alameda", hq_state: "CA"),
      [ Struct.new(:role).new(Role.new(key: "reactor_vendor", name: "Reactor vendor")) ],
      [ "operates", "owns", "owns" ].map { |type| Struct.new(:relationship_type, :facility).new(type, Facility.new(name: "Site #{type}")) },
      Array.new(3), Category.find("reactor-developers"))

    card = LinkCard.for_company(profile)

    assert_equal [ "Reactor developer · Alameda, CA", "Operates 1 plant · Owns stakes in 2 plants" ], [ card.label, card.footer_right ]
    assert_equal [ LinkCard::CATEGORY_COLORS["reactor-developers"] ], card.squares
  end

  test "a category card counts what the category lists" do
    assert_equal "11 companies", LinkCard.for_category(Category.find("reactor-developers"), 11).footer_right
    assert_equal "1 plant or site", LinkCard.for_category(Category.find("plants"), 1).footer_right
    assert_equal "88 plants and sites", LinkCard.for_category(Category.find("plants"), 88).footer_right
  end

  test "the default card: three squares, the tagline as Tosin wrote it, no wordmark" do
    card = LinkCard.default

    assert_equal 3, card.squares.size
    assert_equal "Who's behind the Nuclear Supply Chain", card.alt
    assert_equal [ "Companies · plants and sites · deals", "nuclear-directory.org" ], [ card.footer_left, card.footer_right ]
  end

  test "the digest changes when anything drawn changes, and only then" do
    assert_equal LinkCard.for_plant(vogtle).digest, LinkCard.for_plant(vogtle).digest
    assert_not_equal LinkCard.for_plant(vogtle).digest, LinkCard.for_plant(vogtle(capacity_mw: BigDecimal("4536"))).digest
    assert_match(/\A\h{16}\z/, LinkCard.default.digest)
  end

  test "a card is outlines, not text, and rasterizes to a 1200×630 PNG" do
    card = LinkCard.for_plant(vogtle)

    assert_no_match(/<text/, card.svg)
    image = Vips::Image.new_from_buffer(card.png, "")
    assert_equal [ 1200, 630 ], [ image.width, image.height ]
  end
end
