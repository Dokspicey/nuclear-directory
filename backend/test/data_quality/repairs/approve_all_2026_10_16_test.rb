require "test_helper"

# The one-time repair of the 16 Oct approve-all (#302): pinned values only,
# all or nothing, as human:tosin, once.
class DataQuality::Repairs::ApproveAll20261016Test < ActiveSupport::TestCase
  Repair = DataQuality::Repairs::ApproveAll20261016
  VERIFIED = { verification_status: "verified", verified_by: "agent:approve-all" }.freeze

  setup do
    @doe = Organization.create!(name: "U.S. Department of Energy", **VERIFIED)
    @terrapower = Organization.create!(name: "TerraPower", **VERIFIED)
    @restored = link(@terrapower, "#{Repair::FUNDER}$1.7 billion, 2021: DENE0009054.", started_on: Date.new(2021, 1, 1))
    @bwxt = Organization.create!(name: "BWXT NUCLEAR ENERGY, INC.", **VERIFIED)
    @bwxt_link = link(@bwxt, "#{Repair::FUNDER}$99.9 million, 2023: 89233123FNA400535.", started_on: Date.new(2023, 1, 1))
    @caps = Organization.create!(name: "BROOKHAVEN TECHNOLOGY GROUP INC", **VERIFIED)
    @reworded = link(@caps, "#{Repair::FUNDER}$1.2 million, 2018: DESC0018737.")
    @nas = Organization.create!(name: "National Academy of Sciences", **VERIFIED)
  end

  def link(to, description, started_on: nil) = Relationship.create!(from_organization: @doe, to_organization: to, relationship_type: "funds", description:, started_on:, **VERIFIED)

  # The production ids pinned in the repair, pointed at this test's records.
  def with_ids(&)
    stub_const(Repair, :RESTORE, { @restored.id => [ "#{Repair::FUNDER}$1.7 billion, 2021: DENE0009054.", "ARDP award (Oct 2020): hand-written." ] }) do
      stub_const(Repair, :BWXT, Repair::BWXT.merge(id: @bwxt.id)) do
        stub_const(Repair, :BWXT_LINK, Repair::BWXT_LINK.merge(id: @bwxt_link.id)) do
          stub_const(Repair, :RENAME, { @caps.id => [ "BROOKHAVEN TECHNOLOGY GROUP INC", "Brookhaven Technology Group" ] }) do
            stub_const(Repair, :REWORD, { @reworded.id => [ "$1.2 million", "2018", "DESC0018737" ] }) do
              stub_const(Repair, :OUT_OF_SCOPE, @nas.id, &)
            end
          end
        end
      end
    end
  end

  test "a dry run changes nothing; then every pinned value is repaired as human:tosin, once" do
    with_ids do
      assert_equal 6, Repair.call(dry_run: true).size
      assert_equal "TerraPower", @terrapower.reload.name
      assert_equal Date.new(2021, 1, 1), @restored.reload.started_on, "a dry run changes nothing"

      Repair.call

      assert_equal [ "ARDP award (Oct 2020): hand-written.", nil ], [ @restored.reload.description, @restored.started_on ]
      assert_equal "human:tosin", @restored.verified_by
      assert_equal Repair::REASON, @restored.verification_events.order(:id).last.reason
      assert_equal "BWXT", @bwxt.reload.name
      assert_equal [ Repair::BWXT_LINK[:description], Date.new(2018, 8, 1) ], [ @bwxt_link.reload.description, @bwxt_link.started_on ]
      assert_equal "Brookhaven Technology Group", @caps.reload.name
      assert_equal @caps.id, Directory::Lookup.organization(name: "BROOKHAVEN TECHNOLOGY GROUP INC")&.id
      assert_equal "#{Repair::FUNDER}$1.2 million (2018): DESC0018737.", @reworded.reload.description
      assert @nas.reload.unpublished?

      assert_empty Repair.call, "once"
    end
  end

  test "a value someone fixed by hand stops the repair, and nothing at all is changed" do
    @reworded.update!(description: "Hand-fixed by Tosin.", decided_by: "human:tosin")

    with_ids do
      assert_raises(Repair::Mismatch) { Repair.call }
    end

    assert_equal "TerraPower", @terrapower.reload.name
    assert_equal "#{Repair::FUNDER}$1.7 billion, 2021: DENE0009054.", @restored.reload.description
    assert @nas.reload.verified?
  end

  test "a database without these facts is left alone" do
    assert_empty Repair.call
  end
end
