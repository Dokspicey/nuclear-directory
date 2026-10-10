# One piece of evidence for a fact, as plain values. Only the source's id:
# sources belong to the data quality module, which resolves their URL and
# title.
Directory::EvidenceRef = Data.define(:source_id, :quote, :found_by, :confidence, :crawl_run_id) do
  def self.from(evidence)
    new(source_id: evidence.source_id, quote: evidence.quote, found_by: evidence.found_by,
      confidence: evidence.confidence&.to_f, crawl_run_id: evidence.crawl_run_id)
  end
end
