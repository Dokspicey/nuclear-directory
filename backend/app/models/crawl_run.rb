# One execution of one pipeline stage, so every stage is traceable and can
# be rerun. stats holds counts in / out / errors.
class CrawlRun < ApplicationRecord
  enum :stage, %w[crawl extract match verify].index_by(&:itself), validate: true, prefix: true
  enum :status, %w[running succeeded failed].index_by(&:itself), default: "running", validate: true

  has_many :evidence, dependent: :nullify
  has_many :candidates, dependent: :nullify

  attribute :started_at, default: -> { Time.current }

  def finish!(stats: {})
    update!(status: "succeeded", stats: self.stats.merge(stats), finished_at: Time.current)
  end

  def fail!(error)
    update!(status: "failed", error: error.to_s, finished_at: Time.current)
  end
end
