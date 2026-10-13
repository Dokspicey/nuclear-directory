require "test_helper"

# Directory::FactWriter.merge_organization: one company per brand (#23).
class Directory::MergeOrganizationTest < ActiveSupport::TestCase
  BY = "human:tosin"

  setup do
    @into = Organization.create!(name: "Acme")
    @into.aliases.create!(alias: "Acme")
    @from = Organization.create!(name: "Acme USA", domain: "acme-usa.com")
    @from.aliases.create!(alias: "Acme USA")
    @from.aliases.create!(alias: "AUSA")
    @role = Role.create!(key: "fuel", name: "Fuel")
    @tech = Technology.create!(key: "smr", name: "Small modular reactor")
    @plant = Facility.create!(name: "Acme Plant")
    @other = Organization.create!(name: "Other Co")
  end

  def merge(**) = Directory::FactWriter.merge_organization(from_id: @from.id, into_id: @into.id, by: BY, **)

  test "aliases, the domain, roles, technologies, links, evidence and candidates move" do
    role = @from.organization_roles.create!(role: @role)
    tech = @from.organization_technologies.create!(technology: @tech)
    link = @from.facility_relationships.create!(facility: @plant, relationship_type: "operates")
    deal = Relationship.create!(from_organization: @other, to_organization: @from, relationship_type: "supplies")
    evidence = Evidence.create!(subject: @from, source: sources(:press_release), quote: "Acme USA runs it.", found_by: "human", confidence: 1)
    candidate = Candidate.create!(source: sources(:press_release), kind: "organization", quote: "q", status: "matched",
      payload: { "name" => "Acme USA" }, subject_type: "Organization", subject_id: @from.id)

    assert merge.ok?

    assert_equal [ "acme", "acme usa", "ausa" ], @into.aliases.pluck(:normalized_alias).sort
    assert_equal "acme-usa.com", @into.reload.domain
    assert_nil @from.reload.domain
    assert_equal [ @into.id ] * 4, [ role, tech, link, evidence ].map { |row| row.reload.public_send(row.is_a?(Evidence) ? :subject_id : :organization_id) }
    assert_equal @into.id, deal.reload.to_organization_id
    assert_equal @into.id, candidate.reload.subject_id
    assert_equal @into.id, Directory::Lookup.organization(name: "Acme USA").id
  end

  test "what into already has, and a link to itself, stay behind rejected" do
    @into.organization_roles.create!(role: @role)
    @into.facility_relationships.create!(facility: @plant, relationship_type: "operates")
    Relationship.create!(from_organization: @other, to_organization: @into, relationship_type: "supplies")
    role = @from.organization_roles.create!(role: @role)
    link = @from.facility_relationships.create!(facility: @plant, relationship_type: "operates")
    duplicate = Relationship.create!(from_organization: @other, to_organization: @from, relationship_type: "supplies")
    itself = Relationship.create!(from_organization: @from, to_organization: @into, relationship_type: "subsidiary_of")

    assert merge.ok?

    [ role, link, duplicate, itself ].each do |row|
      row.reload
      assert row.rejected?, row.inspect
      assert_equal BY, row.verified_by
    end
    assert_equal @from.id, role.organization_id, "left on the merged company"
    assert_equal [ @from.id, @into.id ], [ itself.from_organization_id, itself.to_organization_id ]
  end

  test "a link someone took down stays with the merged company (#229)" do
    # TalenEnergy operates Susquehanna, from EIA, unpublished by #227's task before the merge.
    operates = @from.facility_relationships.create!(facility: @plant, relationship_type: "operates",
      verification_status: "verified", verified_by: BY)
    operates.unpublish!(by: BY, reason: "EIA's Entity Name isn't the operator (#227)")
    deal = Relationship.create!(from_organization: @other, to_organization: @from, relationship_type: "supplies")
    deal.reject!(by: BY, reason: "no source")

    assert merge.ok?

    assert_equal [ @from.id, "unpublished" ], [ operates.reload.organization_id, operates.verification_status ]
    assert_equal [ @from.id, "rejected" ], [ deal.reload.to_organization_id, deal.verification_status ]
    assert_empty @into.facility_relationships
  end

  test "the merged company is unpublished, saying where it went and what moved" do
    @from.organization_roles.create!(role: @role)

    assert merge(reason: "One company per brand").ok?

    @from.reload
    assert @from.unpublished?
    assert_equal BY, @from.verified_by
    assert_empty @from.aliases
    reason = @from.verification_events.order(:id).last.reason
    assert_match "One company per brand. Merged into Acme (##{@into.id}). Moved: 2 aliases, 1 domain, 1 organization role", reason
  end

  test "an evidence row into already has isn't duplicated" do
    Evidence.create!(subject: @into, source: sources(:press_release), quote: "Same quote.", found_by: "human", confidence: 1)
    Evidence.create!(subject: @from, source: sources(:press_release), quote: "Same quote.", found_by: "human", confidence: 1)

    assert merge.ok?
    assert_equal 1, Evidence.where(subject: @into, quote: "Same quote.").count
    assert_empty Evidence.where(subject: @from)
  end

  test "only a human merges, never into itself or into a closed company" do
    assert_match "a human's decision", Directory::FactWriter.merge_organization(from_id: @from.id, into_id: @into.id, by: "agent:x").errors.join
    assert_match "into itself", Directory::FactWriter.merge_organization(from_id: @from.id, into_id: @from.id, by: BY).errors.join
    @into.reject!(by: BY)
    assert_match "merge into a live organization", merge.errors.join
    assert @from.reload.pending?, "nothing changed"
  end

  test "a company already merged away isn't merged again (#229)" do
    assert merge.ok?

    assert_match "already unpublished", merge.errors.join
  end
end
