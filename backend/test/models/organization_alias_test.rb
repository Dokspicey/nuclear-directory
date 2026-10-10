require "test_helper"

class OrganizationAliasTest < ActiveSupport::TestCase
  test "normalize lowercases and strips punctuation and company suffixes" do
    assert_equal "westinghouse electric", OrganizationAlias.normalize("Westinghouse Electric Company, LLC")
    assert_equal "terrapower", OrganizationAlias.normalize("TerraPower, Inc.")
    assert_equal "x energy", OrganizationAlias.normalize("X-energy LLC")
    assert_equal "babcock and wilcox", OrganizationAlias.normalize("Babcock & Wilcox Co.")
    assert_equal "ge hitachi nuclear energy", OrganizationAlias.normalize("GE-Hitachi Nuclear Energy")
  end

  test "normalize keeps a name that is only a suffix" do
    assert_equal "co", OrganizationAlias.normalize("Co.")
  end

  test "normalized_alias is set on save" do
    a = organizations(:terrapower).aliases.create!(alias: "TerraPower LLC")
    assert_equal "terrapower", a.normalized_alias
  end

  test "two spellings of the same name can't both be aliases" do
    organizations(:terrapower).aliases.create!(alias: "TerraPower, Inc.")
    dup = organizations(:westinghouse).aliases.build(alias: "terrapower inc")
    assert_not dup.valid?
    assert_includes dup.errors[:normalized_alias], "has already been taken"
  end
end
