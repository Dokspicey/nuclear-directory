# Base class for source plug-ins. Each source_kind (e.g. nrc_reactor_list)
# has one plug-in under app/data_quality/plugins, which knows how to crawl
# and extract that kind of source. Match and verify are shared.
#
# The plug-in for a source_kind is found by name:
#   "nrc_reactor_list" => DataQuality::Plugins::NrcReactorList
class DataQuality::Plugin
  class UnknownSourceKind < StandardError; end

  def self.for(source_kind)
    "DataQuality::Plugins::#{source_kind.to_s.camelize}".safe_constantize&.new or
      raise UnknownSourceKind, "No plug-in for source kind #{source_kind.inspect}"
  end

  def source_kind = self.class.name.demodulize.underscore

  # Fetch this plug-in's sources and store each snapshot on a Source row
  # (content_text, content_sha256, crawl_status, fetched_at).
  # Returns a stats hash for the crawl run.
  def crawl(run)
    raise NotImplementedError, "#{self.class} must implement #crawl"
  end

  # Turn one crawled Source into candidate facts. Returns an array of
  # { kind:, payload:, quote: } hashes; quote is the supporting text.
  def extract(source, run)
    raise NotImplementedError, "#{self.class} must implement #extract"
  end
end
