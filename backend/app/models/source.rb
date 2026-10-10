# A page or dataset we crawl. source_kind names the crawler plug-in that
# handles it (e.g. nrc_reactor_list, web_page).
class Source < ApplicationRecord
  enum :crawl_status, %w[pending ok blocked needs_human].index_by(&:itself), default: "pending", validate: true,
    prefix: :crawl

  has_many :evidence, dependent: :restrict_with_error
  has_many :candidates, dependent: :restrict_with_error

  normalizes :url, with: ->(url) { url.strip }

  before_validation { self.domain ||= domain_from_url }

  validates :url, presence: true, uniqueness: true
  validates :source_kind, presence: true

  private
    def domain_from_url
      URI.parse(url.to_s).host&.downcase&.delete_prefix("www.")
    rescue URI::InvalidURIError
      nil
    end
end
