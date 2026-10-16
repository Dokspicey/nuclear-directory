# One-time repair of the 16 Oct 2026 20:41 UTC "Approve all", which
# published the DOE crawl's first batch (#302) before it was reviewed:
# - 3 hand-written link descriptions (TerraPower, X-energy, CFS) were
#   replaced by award summaries, with a crawler start date: restored from
#   db/seeds/organizations/us-department-of-energy.yml, start date cleared
# - BWXT (company 98) was published under its award spelling, and its link
#   (72) lost its 2018 award: renamed "BWXT", the link sums up both awards
# - 23 companies were published under all-capitals award spellings:
#   renamed with the plug-in's display name, the spelling kept as an alias
# - 20 one-award links read "…, 2021: ID": reworded "… (2021): ID"
# - National Academy of Sciences (107) is out of scope: taken off
#
# The USAspending evidence stays on every fact as another source.
#
# Data Quality pinned every value the approve-all left. Each fact is checked
# first: one already repaired is skipped; one that's neither (someone fixed
# it by hand) stops the repair, which then changes nothing at all. It runs
# as human:tosin (his approval of the PR), at the start of the DOE crawl, so
# it needs no shell; once its reason is in the history it does nothing.
# dry_run: everything is checked and written, then rolled back.
class DataQuality::Repairs::ApproveAll20261016
  BY = "human:tosin"
  REASON = "Repair after the 16 Oct 20:41 approve-all of DOE awards (#302)"
  FUNDER = "1 award from the U.S. Department of Energy totaling "

  # Link id => [the approve-all's description (its start), the hand-written one].
  RESTORE = {
    45 => [ "#{FUNDER}$1.7 billion, 2021: DENE0009054.",
      "ARDP award (Oct 2020): $80M initial funding to demonstrate Natrium; cost-shared, DOE total up to $3.2B over seven years across both ARDP demos subject to appropriations." ],
    46 => [ "4 awards from the U.S. Department of Energy totaling $967.5 million, 2016–2023:",
      "ARDP award (Oct 2020): $80M initial funding for a four-unit Xe-100 plant and TRISO fuel fabrication facility; cost-shared." ],
    48 => [ "#{FUNDER}$1.5 million, 2021: DESC0021623.",
      "Selected (May 2023) in the $46M Milestone-Based Fusion Development Program; payments only on verified milestones." ]
  }.freeze
  BWXT = { id: 98, was: "BWXT NUCLEAR ENERGY, INC.", name: "BWXT", aliases: [ "BWXT NUCLEAR ENERGY, INC.", "BWXT NUCLEAR OPERATIONS GROUP, INC." ] }.freeze
  BWXT_LINK = { id: 72, was: "#{FUNDER}$99.9 million, 2023: 89233123FNA400535", started_on: Date.new(2018, 8, 1),
    description: "2 awards from the U.S. Department of Energy totaling $102.6 million (first in 2018, latest in 2023): 89233123FNA400535 and DENE0008744." }.freeze
  RENAME = [ 92, 93, 94, 95, 96, 97, 99, 100, 101, 102, 103, 104, 105, 106, 108, 109, 110, 111, 112, 113, 114, 115, 116 ].freeze
  REWORD = [ 63, 65, 66, 69, 70, 75, 76, 77, 79, 81, 82, 84, 85, 86, 87, 88, 89, 90, 91, 92 ].freeze
  OUT_OF_SCOPE = 107
  ONE_AWARD = /\A#{Regexp.escape(FUNDER)}(?<amount>.+?), (?<year>\d{4}): (?<id>[^\s.]+)\.\z/
  REWORDED = /\A#{Regexp.escape(FUNDER)}.+ \(\d{4}\): \S+\.\z/

  # A value that's neither what the approve-all left nor the repaired one.
  class Mismatch < StandardError; end

  # One write: kind and id, the attributes it sets, the status it leaves.
  Change = Data.define(:kind, :id, :attributes, :status, :note)

  def self.call(...) = new(...).call

  def initialize(dry_run: false, directory: DataQuality::DirectoryClient.new, plugin: DataQuality::Plugin.for("usaspending_doe_awards"))
    @dry_run = dry_run
    @directory = directory
    @plugin = plugin
  end

  # The changes made (or, in a dry run, that would be). [] once done.
  def call
    return [] if done?

    changes = plan
    ActiveRecord::Base.transaction(requires_new: true) do
      changes.each do |change|
        result = @directory.decide_fact(change.kind, id: change.id, status: change.status, by: BY, reason: REASON, attributes: change.attributes)
        raise Mismatch, "#{change.kind} #{change.id}: #{result.errors.to_sentence}" if result.errors.any?
      end
      raise ActiveRecord::Rollback if @dry_run
    end
    changes
  end

  # Every change, checked against what the approve-all left; raises Mismatch first.
  def plan
    [ *RESTORE.filter_map { |id, (was, written)| restore(id, was, written) }, *bwxt, *RENAME.filter_map { |id| rename(id) },
      *REWORD.filter_map { |id| reword(id) }, take_down ].compact
  end

  private
    # Done, or not this database (a test or local one without these facts).
    def done?
      link = @directory.fact(type: "Relationship", id: RESTORE.keys.first) or return true
      link.values["from_organization_name"] != "U.S. Department of Energy" ||
        @directory.verification_history(type: "Relationship", id: link.id).any? { |event| event.reason.to_s.start_with?(REASON) }
    end

    def fact(type, id) = @directory.fact(type:, id:) || raise(Mismatch, "#{type} #{id} is gone")

    def restore(id, was, written)
      link = fact("Relationship", id)
      description = link.values["description"].to_s
      return if description == written && link.values["started_on"].nil?
      raise Mismatch, "link #{id} reads #{description.inspect}, not the approve-all's #{was.inspect}" unless description.start_with?(was)

      Change.new(kind: "relationship", id:, attributes: { description: written, started_on: nil }, status: link.verification_status,
        note: "restores the hand-written description")
    end

    def bwxt
      company = fact("Organization", BWXT[:id])
      link = fact("Relationship", BWXT_LINK[:id])
      changes = []
      unless company.name == BWXT[:name]
        raise Mismatch, "company #{BWXT[:id]} is #{company.name.inspect}, not #{BWXT[:was].inspect}" unless company.name == BWXT[:was]

        changes << Change.new(kind: "organization", id: BWXT[:id], attributes: { name: BWXT[:name], aliases: BWXT[:aliases] },
          status: company.verification_status, note: "renamed BWXT")
      end
      description = link.values["description"].to_s
      unless description == BWXT_LINK[:description]
        raise Mismatch, "link #{BWXT_LINK[:id]} reads #{description.inspect}" unless description.start_with?(BWXT_LINK[:was])

        changes << Change.new(kind: "relationship", id: BWXT_LINK[:id], status: link.verification_status, note: "both awards",
          attributes: { description: BWXT_LINK[:description], started_on: BWXT_LINK[:started_on] })
      end
      changes
    end

    def rename(id)
      company = fact("Organization", id)
      name = @plugin.display_name(company.name)
      return if name == company.name
      raise Mismatch, "company #{id} is #{company.name.inspect}, not an award spelling" unless company.name == company.name.upcase

      Change.new(kind: "organization", id:, attributes: { name:, aliases: [ company.name ] }, status: company.verification_status,
        note: "#{company.name} -> #{name}")
    end

    def reword(id)
      link = fact("Relationship", id)
      description = link.values["description"].to_s
      return if description.match?(REWORDED)
      found = description.match(ONE_AWARD) or raise Mismatch, "link #{id} reads #{description.inspect}"

      Change.new(kind: "relationship", id:, attributes: { description: "#{FUNDER}#{found[:amount]} (#{found[:year]}): #{found[:id]}." },
        status: link.verification_status, note: "reworded")
    end

    def take_down
      company = fact("Organization", OUT_OF_SCOPE)
      return if company.verification_status == "unpublished"
      raise Mismatch, "company #{OUT_OF_SCOPE} is #{company.verification_status}" unless company.verification_status == "verified"

      Change.new(kind: "organization", id: OUT_OF_SCOPE, attributes: {}, status: "unpublished", note: "taken off: out of scope")
    end
end
