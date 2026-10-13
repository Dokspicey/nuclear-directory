# One-off repair for #226: link candidates approved before their company or
# plant was resolved were written onto an unrelated "operates" link, with
# their quote as its evidence. For each (candidate, evidence, link) listed,
# this removes that evidence from the link (as a human, with a reason in the
# link's history) and reopens the candidate as new, so the next match run
# resolves its ends and proposes the link properly.
#
# Every item is checked first and skipped with a reason unless it is exactly
# the misplacement found: the candidate is a merged plant link attached to
# that link, the link's plant isn't the candidate's plant, and the evidence
# has the candidate's source and quote. Each item is its own transaction, and
# an item already repaired is reported, not repeated, so a re-run is safe.
# dry_run (the default) checks everything and changes nothing.
class DataQuality::Repairs::MisplacedLinkEvidence
  # From the 12 Oct 2026 production audit: [candidate id, evidence id, link id].
  ISSUE_226 = [
    [ 91, 1092, 159 ], [ 93, 1093, 90 ], [ 103, 1094, 3 ], [ 105, 1095, 160 ], [ 141, 1097, 111 ], [ 205, 1099, 111 ],
    [ 207, 1098, 111 ], [ 209, 1100, 161 ], [ 211, 1101, 91 ], [ 321, 1108, 91 ], [ 324, 1110, 91 ], [ 330, 1112, 91 ],
    [ 336, 1114, 112 ], [ 345, 1116, 112 ], [ 351, 1118, 112 ], [ 354, 1120, 112 ], [ 366, 1122, 112 ], [ 378, 1124, 112 ],
    [ 393, 1127, 112 ], [ 396, 1130, 112 ], [ 444, 1129, 112 ], [ 450, 1132, 112 ], [ 465, 1134, 112 ], [ 471, 1136, 112 ]
  ].freeze
  LINK = "FacilityRelationship"
  NOTE = "Reopened (#226): its approval was written onto another link"

  # status: :repaired, :would_repair (dry run), :already_repaired or :skipped.
  Outcome = Data.define(:candidate_id, :status, :message)

  def self.call(...) = new(...).call

  def initialize(items:, by:, dry_run: true, directory: DataQuality::DirectoryClient.new)
    raise ArgumentError, "a repair is a human's decision (by: \"human:…\")" unless by.to_s.match?(/\Ahuman:\S+\z/)

    @items = items
    @by = by
    @dry_run = dry_run
    @directory = directory
  end

  def call = @items.map { |candidate_id, evidence_id, link_id| repair(candidate_id, evidence_id, link_id) }

  private
    def repair(candidate_id, evidence_id, link_id)
      outcome = nil
      Candidate.transaction do
        candidate = Candidate.find_by(id: candidate_id) or next outcome = skipped(candidate_id, "no such candidate")
        # Locked in Review's order (source, then candidate), then the link inside FactWriter.
        ::Source.lock.find(candidate.source_id)
        candidate.lock!
        next outcome = Outcome.new(candidate_id:, status: :already_repaired, message: "reopened before") if repaired?(candidate)

        problem = mismatch(candidate, link_id) and next outcome = skipped(candidate_id, problem)
        claim = "#{candidate.payload.dig('organization', 'name')} operates #{candidate.payload.dig('facility', 'name')}"
        next outcome = Outcome.new(candidate_id:, status: :would_repair, message: "#{claim}: off link #{link_id}") if @dry_run

        removed = @directory.remove_evidence(type: LINK, id: link_id, evidence_id:, source_id: candidate.source_id,
          quote: candidate.quote, by: @by, reason: "Evidence for \"#{claim}\" (candidate #{candidate.id}) was attached " \
          "to this link by mistake; removed (#226)")
        unless removed.success?
          outcome = skipped(candidate_id, removed.errors.join("; "))
          raise ActiveRecord::Rollback
        end

        candidate.update!(status: "new", subject_type: nil, subject_id: nil, proposed_subject: false,
          reviewed_by: nil, reviewed_at: nil, notes: [ candidate.notes, "#{NOTE} #{link_id} (by #{@by})" ].compact_blank.join(". "))
        outcome = Outcome.new(candidate_id:, status: :repaired, message: "#{claim}: evidence #{evidence_id} removed from link #{link_id}")
      end
      outcome
    end

    def repaired?(candidate) = candidate.status_new? && candidate.subject_id.nil? && candidate.notes.to_s.include?(NOTE)

    # Why this item isn't the misplacement found in #226, or nil when it is.
    def mismatch(candidate, link_id)
      return "is a #{candidate.kind} candidate, not a plant link" unless candidate.kind_facility_relationship?
      return "is #{candidate.status}, not merged" unless candidate.status_merged?
      return "is attached to #{candidate.subject_type} #{candidate.subject_id}, not link #{link_id}" unless
        candidate.subject_type == LINK && candidate.subject_id == link_id

      link = @directory.fact(type: LINK, id: link_id) or return "link #{link_id} doesn't exist"
      plant = @directory.facility(id: link.values["facility_id"])
      "link #{link_id} is the candidate's own plant (#{plant&.name})" if own_plant?(plant, candidate.payload["facility"].to_h)
    end

    # The claim's plant by docket (a unit, or a site with that unit) or EIA plant ID.
    def own_plant?(plant, named)
      return false unless plant

      docket, eia_plant_id = named.values_at("nrc_docket", "eia_plant_id").map(&:presence)
      return true if docket && plant.nrc_docket == docket
      return true if docket && @directory.facility(nrc_docket: docket)&.parent_id == plant.id
      eia_plant_id.present? && plant.eia_plant_id == eia_plant_id
    end

    def skipped(candidate_id, message) = Outcome.new(candidate_id:, status: :skipped, message:)
end
