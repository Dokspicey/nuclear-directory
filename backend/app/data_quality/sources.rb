# The way code outside the module gets a sources row, e.g. the seed loader
# citing a page a human checked. Sources belong to DataQuality, so callers
# get a plain SourceRef back, never the model.
#
#   ref = DataQuality::Sources.find_or_create(url: "https://…", published_on: Date.new(2026, 1, 2))
#   ref.id # => use as evidence source_id
module DataQuality::Sources
  SourceRef = Data.define(:id, :url, :source_kind)

  # Finds the source for this URL or creates it. An existing source keeps
  # its kind and only gains a published_on it didn't have. Raises
  # ActiveRecord::RecordInvalid on a bad URL.
  def self.find_or_create(url:, source_kind: "web_page", published_on: nil)
    source = Source.find_or_initialize_by(url: url)
    source.source_kind ||= source_kind
    source.published_on ||= published_on
    source.save!

    SourceRef.new(id: source.id, url: source.url, source_kind: source.source_kind)
  end
end
