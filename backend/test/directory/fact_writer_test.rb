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

  test "fill_blank sets only fields that are blank on an existing record" do
    site = facilities(:vogtle)
    site.update!(state: "GA")

    result = write(:facility, { id: site.id, state: "TX", status: "operating" }, fill_blank: true)

    assert result.ok?
    site.reload
    assert_equal [ "GA", "operating" ], [ site.state, site.status ]
  end

  test "protect_human_verified fills blanks when the values agree, and keeps a human's decision" do
    site = facilities(:vogtle)
    site.update!(state: "GA")
    site.verify!(by: "human:tosin")

    result = write(:facility, { id: site.id, state: "GA", status: "operating" }, protect_human_verified: true,
      evidence: [ @evidence ], verification: { status: "verified", by: "agent:verifier/x" })

    assert result.ok?
    site.reload
    assert_equal [ "GA", "operating" ], [ site.state, site.status ]
    assert_equal "human:tosin", site.verified_by
    assert_equal 1, site.evidence.count
  end

  test "protect_human_verified reports a disagreement and writes nothing" do
    site = facilities(:vogtle)
    site.update!(state: "NJ", capacity_mw: 1150)
    site.verify!(by: "human:tosin")

    result = write(:facility, { id: site.id, state: "DE", capacity_mw: "1150.0", city: "Waynesboro", country_code: " us " },
      protect_human_verified: true, evidence: [ @evidence ])

    assert_not result.ok?
    assert result.conflict?
    assert_equal({ "state" => [ "NJ", "DE" ] }, result.conflicts,
      "equal numbers in another form, and values equal once normalized, aren't conflicts")
    assert_equal site.id, result.id
    site.reload
    assert_nil site.city, "not even the blanks are filled"
    assert_empty site.evidence
  end

  test "a rejected fact isn't changed by an automated write, whoever rejected it" do
    org = organizations(:terrapower)
    org.reject!(by: "agent:verifier/x")

    result = write(:organization, { id: org.id, hq_city: "Bellevue" }, protect_human_verified: true, evidence: [ @evidence ],
      verification: { status: "verified", by: "agent:verifier/x" })

    assert_not result.ok?
    assert_match "was rejected by agent:verifier/x", result.errors.join
    org.reload
    assert org.rejected?
    assert_nil org.hq_city
    assert_empty org.evidence
  end

  test "websites agree when their domains do; unreadable ones only when identical" do
    org = organizations(:terrapower)
    org.update!(website: "https://www.terrapower.com/about")
    org.verify!(by: "human:tosin")

    same = write(:organization, { id: org.id, website: "https://terrapower.com/news" }, protect_human_verified: true)
    assert same.ok?, same.errors.inspect

    org.update_column(:website, "https://bad host one")
    identical = write(:organization, { id: org.id, website: "https://bad host one" }, protect_human_verified: true)
    assert identical.ok?, identical.errors.inspect
    clash = write(:organization, { id: org.id, website: "https://bad host two" }, protect_human_verified: true)
    assert_equal({ "website" => [ "https://bad host one", "https://bad host two" ] }, clash.conflicts)
  end

  test "names never count as conflicts" do
    org = organizations(:terrapower)
    org.verify!(by: "human:tosin")

    assert write(:organization, { id: org.id, name: "TerraPower, LLC" }, protect_human_verified: true).ok?
    assert_equal "TerraPower", org.reload.name
  end

  test "values equal once the model normalizes them aren't conflicts" do
    site = facilities(:vogtle)
    site.update!(country_code: "US", nrc_docket: "05000424")
    site.verify!(by: "human:tosin")

    assert write(:facility, { id: site.id, country_code: " us ", nrc_docket: " 05000424 " }, protect_human_verified: true).ok?
  end

  test "a site fill rechecks the unit and the site's blanks with both locked" do
    site = facilities(:vogtle)
    site.update!(state: nil, status: "operating")
    unit = Facility.create!(name: "Vogtle 3", parent: site, state: "GA", status: "planned")
    fill = -> { Directory::FactWriter.fill_site_from_unit(unit.id, fields: %w[state status], evidence: [ @evidence ]) }

    unit.reject!(by: "human:tosin")
    assert_nil fill.call, "a unit that isn't verified (any more) fills nothing"

    unit.verify!(by: "human:tosin")
    assert fill.call.ok?
    site.reload
    assert_equal [ "GA", "operating" ], [ site.state, site.status ], "only the blank field is filled"
    assert_nil fill.call, "nothing left to fill"
  end

  test "no automated unit under a rejected site, checked inside the write" do
    site = facilities(:vogtle)
    site.reject!(by: "human:tosin")

    result = write(:facility, { name: "Vogtle 3", nrc_docket: "05200025", parent_id: site.id }, protect_human_verified: true)

    assert_match "site #{site.name} was rejected by human:tosin; no units under it", result.errors.join
    assert_not Facility.exists?(nrc_docket: "05200025")
    assert write(:facility, { name: "Vogtle 3", nrc_docket: "05200025", parent_id: site.id }).ok?, "a human may still"
  end

  test "protect_human_verified doesn't hold back records no human has reviewed" do
    site = facilities(:vogtle)
    site.update!(state: "GA")

    write(:facility, { id: site.id, state: "AL" }, protect_human_verified: true, verification: { status: "verified", by: "agent:verifier/x" })

    assert_equal [ "AL", "agent:verifier/x" ], [ site.reload.state, site.verified_by ]
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
