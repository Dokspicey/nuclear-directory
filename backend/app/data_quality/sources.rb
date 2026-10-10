# The way code outside the module gets a sources row, e.g. the seed loader
# citing a page a human checked. Sources belong to DataQuality, so callers
# get a plain SourceRef back, never the model.
#
#   result = DataQuality::Sources.find_or_create(url: "https://…", published_on: Date.new(2026, 1, 2))
#   result.ok?    # => false for a URL that isn't an absolute http(s) address
#   result.ref.id # => use as evidence source_id
#   result.errors # => ["Url must be an absolute http or https address"]
module DataQuality::Sources
  SourceRef = Data.define(:id, :url, :source_kind)
  Result = Data.define(:ref, :errors) do
    def ok? = errors.empty?
  end

  # Finds the source for this URL or creates it. An existing source keeps
  # its kind and only gains a published_on it didn't have. An invalid URL
  # (javascript:, data:, relative, malformed) saves nothing and comes back
  # as errors.
  def self.find_or_create(url:, source_kind: "web_page", published_on: nil)
    source = Source.find_or_initialize_by(url: url)
    source.source_kind ||= source_kind
    source.published_on ||= published_on
    return Result.new(ref: nil, errors: source.errors.full_messages) unless source.save

    Result.new(ref: SourceRef.new(id: source.id, url: source.url, source_kind: source.source_kind), errors: [])
  end
end
