# "This source supports this fact." A fact can have many; its confidence is
# derived from them (see .combined_confidence).
class Evidence < ApplicationRecord
  # When two or more independent sources (different domains) back a fact,
  # its confidence goes up by this much, capped at 1.
  AGREEMENT_BONUS = 0.1

  enum :found_by, %w[crawler verifier human].index_by(&:itself), validate: true, prefix: true

  belongs_to :subject, polymorphic: true
  belongs_to :source
  belongs_to :crawl_run, optional: true

  validates :confidence, numericality: { in: 0..1 }, allow_nil: true

  after_save :refresh_subject_confidence
  after_destroy :refresh_subject_confidence, unless: :destroyed_by_association

  # The v1 confidence rule, kept in one place so it is easy to change:
  # the strongest single piece of evidence, bumped when independent sources
  # agree. Returns nil when no evidence has a confidence.
  def self.combined_confidence(evidence)
    scored = evidence.reject { |e| e.confidence.nil? }
    return if scored.empty?

    best = scored.map(&:confidence).max
    independent_sources = scored.map { |e| e.source.domain || e.source_id }.uniq.size
    best += AGREEMENT_BONUS if independent_sources >= 2
    [ best, 1 ].min.to_d
  end

  private
    def refresh_subject_confidence
      subject.recompute_confidence! if subject.respond_to?(:recompute_confidence!)
    end
end
