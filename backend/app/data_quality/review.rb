# How a human decides on what the pipeline found. The verifier only
# recommends; publishing happens here, by a person, from the admin (#86).
#
# This is the start of the Review API (#85): approve is here because publish
# moved out of verify (#15). Listing, reject, unpublish and pending
# directory facts follow in #85.
#
#   DataQuality::Review.approve([ 12, 13 ], by: "human:tosin")
#   # => [ Result(candidate_id: 12, ok?: true, ...), ... ]
module DataQuality::Review
  Result = Data.define(:candidate_id, :ref, :errors) do
    def ok? = errors.empty?
  end

  # Publishes each candidate as a fact verified by `by`, with its quote as
  # evidence (confidence: the verifier's, when it gave one). A human's write
  # isn't protected, so approving a candidate that disagrees with a
  # human-verified value applies the new value; the admin shows both first.
  # A verified unit then fills its site's blank fields. Candidates that
  # aren't waiting (already merged, rejected) are refused, never rewritten.
  def self.approve(candidate_ids, by:, reason: nil, directory: DataQuality::DirectoryClient.new)
    raise ArgumentError, "only a human approves (by: \"human:…\")" unless by.to_s.start_with?("human:")

    Candidate.where(id: candidate_ids).includes(:crawl_run, :verify_run).order(:id).map do |candidate|
      approve_one(candidate, by:, reason:, directory:)
    end
  end

  def self.approve_one(candidate, by:, reason:, directory:)
    unless candidate.status_new? || candidate.status_matched? || candidate.status_needs_review?
      return Result.new(candidate_id: candidate.id, ref: nil, errors: [ "it's already #{candidate.status.humanize(capitalize: false)}" ])
    end

    # The evidence belongs to the run that judged it (verify), else the one that found it.
    run = candidate.verify_run || candidate.crawl_run
    result = directory.write_fact(candidate, confidence: candidate.ai_confidence, crawl_run: run, by:, reason:)
    return Result.new(candidate_id: candidate.id, ref: nil, errors: result.errors) unless result.success?

    candidate.update!(status: "merged", subject_type: result.ref.type, subject_id: result.ref.id)
    fill_site(candidate, result.ref.id, run, directory) if candidate.kind_facility?
    Result.new(candidate_id: candidate.id, ref: result.ref, errors: [])
  end

  # A published unit completes its site's missing details (see
  # DirectoryClient#fill_site_from_unit). The unit stays published if the
  # site refuses (a human rejected it); the candidate notes why.
  def self.fill_site(candidate, unit_id, run, directory)
    filled = directory.fill_site_from_unit(unit_id, candidate, crawl_run: run)
    return if filled.nil? || filled.success?

    candidate.update!(notes: [ candidate.notes, "Site not filled: #{filled.errors.join('; ')}" ].compact_blank.join(". "))
  end
  private_class_method :approve_one, :fill_site
end
