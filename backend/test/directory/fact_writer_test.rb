require "test_helper"

class Directory::FactWriterTest < ActiveSupport::TestCase
  setup do
    @role = Role.create!(key: "reactor_vendor", name: "Reactor vendor")
    @evidence = { source_id: sources(:press_release).id, quote: "TerraPower is a reactor vendor.", found_by: "crawler", confidence: 0.8 }
  end

  def write(...) = Directory::FactWriter.write(...)

  test "creates an organization with its name and aliases as aliases" do
    result = write(:organization, { name: "Kairos Power, LLC", website: "https://www.kairospower.com", aliases: [ "Kairos" ] })

    assert result.ok?
    assert result.created
    org = Organization.find(result.id)
    assert_equal "kairospower.com", org.domain
    assert_equal [ "kairos", "kairos power" ], org.aliases.pluck(:normalized_alias).sort
  end

  test "is idempotent: the same input updates instead of duplicating" do
    first = write(:organization, { name: "Kairos Power", aliases: [ "Kairos" ] }, evidence: [ @evidence ])
    second = write(:organization, { name: "Kairos Power", aliases: [ "Kairos" ], hq_city: "Alameda" }, evidence: [ @evidence ])

    assert_equal first.id, second.id
    assert_not second.created
    assert_equal "Alameda", Organization.find(second.id).hq_city
    assert_equal 1, Organization.where(name: "Kairos Power").count
    assert_equal 1, Evidence.where(subject_type: "Organization", subject_id: first.id).count
  end

  test "finds an existing organization by alias or domain" do
    assert_equal organizations(:terrapower).id, write(:organization, { name: "TerraPower, Inc." }).id
    assert_equal organizations(:terrapower).id, write(:organization, { name: "Brand New Name", website: "https://terrapower.com" }).id
  end

  test "domain can be left blank on purpose" do
    result = write(:organization, { name: "Urenco USA", website: "https://urenco.com", domain: nil })
    assert_nil Organization.find(result.id).domain
  end

  test "an alias can't point at two organizations" do
    result = write(:organization, { name: "Westinghouse Electric Company", aliases: [ "Westinghouse", "TerraPower" ],
      hq_city: "Cranberry Township" })

    assert_not result.ok?
    assert_match "already belongs to TerraPower", result.errors.first
    westinghouse = organizations(:westinghouse).reload
    assert_nil westinghouse.hq_city, "a failed write changes nothing"
    assert_equal [ "westinghouse electric" ], westinghouse.aliases.pluck(:normalized_alias)
  end

  test "writes evidence and derives confidence from it" do
    org = organizations(:terrapower)
    result = write(:organization_role, { organization_id: org.id, role: "reactor_vendor" }, evidence: [ @evidence ])

    assert result.ok?
    tag = OrganizationRole.find(result.id)
    assert_equal @role, tag.role
    assert_equal 0.8, tag.confidence
    assert tag.pending?
  end

  test "human verification sets status, who and confidence 1" do
    org = organizations(:terrapower)
    result = write(:organization_role, { organization_id: org.id, role: "reactor_vendor" },
      evidence: [ @evidence ], verification: { status: "verified", by: "human:tosin" })

    tag = OrganizationRole.find(result.id)
    assert tag.verified?
    assert_equal "human:tosin", tag.verified_by
    assert tag.verified_at
    assert_equal 1, tag.confidence
  end

  test "re-applying the same verification keeps the original verified_at" do
    args = [ :organization_role, { organization_id: organizations(:terrapower).id, role: "reactor_vendor" } ]
    id = write(*args, verification: { status: "verified", by: "human:tosin" }).id
    first_verified_at = OrganizationRole.find(id).verified_at

    travel 1.hour do
      write(*args, verification: { status: "verified", by: "human:tosin" })
    end
    assert_equal first_verified_at, OrganizationRole.find(id).verified_at
  end

  test "writes relationships, including subsidiary_of" do
    result = write(:relationship, { from_organization_id: organizations(:westinghouse).id,
      to_organization_id: organizations(:terrapower).id, relationship_type: "subsidiary_of", description: "test" })

    assert result.ok?
    assert Relationship.find(result.id).subsidiary_of?
    assert_equal result.id, write(:relationship, { from_organization_id: organizations(:westinghouse).id,
      to_organization_id: organizations(:terrapower).id, relationship_type: "subsidiary_of" }).id
  end

  test "writes facilities with unknown type and status, and links to them" do
    facility = write(:facility, { name: "Kemmerer Unit 1 (Natrium)", technology: nil })
    assert facility.ok?, facility.errors.inspect
    assert_nil Facility.find(facility.id).facility_type

    link = write(:facility_relationship, { organization_id: organizations(:terrapower).id, facility_id: facility.id,
      relationship_type: "owns", description: "Owned via subsidiary US SFR Owner." })
    assert link.ok?
    assert_equal "Owned via subsidiary US SFR Owner.", FacilityRelationship.find(link.id).description
  end

  test "returns errors instead of raising" do
    org_id = organizations(:terrapower).id

    assert_equal [ "unknown kind :gossip" ], write(:gossip, {}).errors
    assert_match "unknown attributes: colour", write(:organization, { name: "X", colour: "red" }).errors.first
    assert_match "unknown role", write(:organization_role, { organization_id: org_id, role: "wizard" }).errors.first
    assert_match "can't be the same", write(:relationship, { from_organization_id: org_id, to_organization_id: org_id,
      relationship_type: "supplies" }).errors.first
    assert_match "Found by", write(:organization_role, { organization_id: org_id, role: "reactor_vendor" },
      evidence: [ @evidence.merge(found_by: "rumour") ]).errors.first
  end

  test "a failed evidence write rolls back the fact too" do
    assert_no_difference "OrganizationRole.count" do
      write(:organization_role, { organization_id: organizations(:terrapower).id, role: "reactor_vendor" },
        evidence: [ @evidence.merge(source_id: nil) ])
    end
  end
end
