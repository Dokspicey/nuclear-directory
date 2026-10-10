require "test_helper"

# Other names a plant goes by (#65): found by Lookup, written by FactWriter.
class Directory::FacilityAliasesTest < ActiveSupport::TestCase
  def write(...) = Directory::FactWriter.write(...)

  setup do
    @crane = Facility.create!(name: "Crane Clean Energy Center")
    assert write(:facility, { id: @crane.id, aliases: [ "Three Mile Island Unit 1", "TMI-1" ] }).ok?
  end

  test "a plant is found under any of its other names, however they're spelled" do
    assert_equal @crane.id, Directory::Lookup.facility(name: "Three Mile Island Unit 1").id
    assert_equal @crane.id, Directory::Lookup.facility(name: "three mile island, unit 1").id
    assert_equal @crane.id, Directory::Lookup.facility(name: "TMI 1").id
    assert_nil Directory::Lookup.facility(name: "Three Mile Island")
    assert_nil Directory::Lookup.facility(name: "  ")
  end

  test "a facility's own name wins over another's alias" do
    other = Facility.create!(name: "TMI-1")

    assert_equal other.id, Directory::Lookup.facility(name: "TMI-1").id
  end

  test "writing under an alias updates that plant instead of creating another" do
    result = write(:facility, { name: "Three Mile Island Unit 1", state: "PA" })

    assert_equal [ @crane.id, false ], [ result.id, result.created ]
    assert_equal [ "PA", "Crane Clean Energy Center" ], [ @crane.reload.state, @crane.name ], "updated, not renamed"
    assert write(:facility, { id: @crane.id, name: "Crane Clean Energy Center at TMI" }).ok?
    assert_equal "Crane Clean Energy Center at TMI", @crane.reload.name, "a write by id may rename"
  end

  test "aliases are written once, and the plant's own name isn't stored" do
    write(:facility, { id: @crane.id, aliases: [ "Three Mile Island Unit 1", "Crane Clean Energy Center" ] })

    assert_equal [ "TMI-1", "Three Mile Island Unit 1" ], @crane.aliases.pluck(:alias).sort
  end

  test "a rename can't take another plant's alias; taking its own alias promotes it" do
    other = Facility.create!(name: "Peach Bottom")

    taken = write(:facility, { id: other.id, name: "TMI-1" })
    assert_match "name \"TMI-1\" is an alias of Crane Clean Energy Center", taken.errors.join
    assert_equal "Peach Bottom", other.reload.name

    assert write(:facility, { id: @crane.id, name: "Three Mile Island Unit 1" }).ok?
    assert_equal [ "TMI-1" ], @crane.reload.aliases.pluck(:alias), "the promoted alias is now the name"
  end

  test "an HTML-escaped ampersand is the same as a plain one" do
    write(:facility, { id: @crane.id, aliases: [ "Crane Units 1 & 2" ] })

    assert_equal "crane units 1 and 2", FacilityAlias.normalize("Crane Units 1 &amp; 2")
    assert_equal @crane.id, Directory::Lookup.facility(name: "Crane Units 1 &amp; 2").id
  end

  test "an alias can't belong to two plants, or be another plant's name" do
    other = Facility.create!(name: "Peach Bottom")

    taken = write(:facility, { id: other.id, aliases: [ "three mile island unit 1" ] })
    assert_match "already belongs to Crane Clean Energy Center", taken.errors.join
    named = write(:facility, { id: @crane.id, aliases: [ "Peach Bottom" ] })
    assert_match "is the name of another facility", named.errors.join
    assert_empty other.aliases
  end

  test "aliases go with their plant" do
    @crane.destroy!
    assert_equal 0, FacilityAlias.count
  end
end
