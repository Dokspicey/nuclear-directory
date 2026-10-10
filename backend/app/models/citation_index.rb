# Numbers the sources cited on one page, in order of first use, so each
# source chip matches an entry in the page's numbered source list.
#
#   index = CitationIndex.new
#   index.cite(fact.evidence)  # => [[1, source], [2, source]]
#   index.sources              # => [[1, source], [2, source], ...]
class CitationIndex
  def initialize
    @numbers = {}
    @sources = {}
  end

  # Evidence for one fact => [[number, source], ...], strongest first,
  # one entry per source.
  def cite(evidence)
    Array(evidence).sort_by { |e| -(e.confidence || 0) }.map(&:source).uniq(&:id).map do |source|
      @sources[source.id] ||= source
      [ @numbers[source.id] ||= @numbers.size + 1, source ]
    end
  end

  def sources = @numbers.map { |id, number| [ number, @sources[id] ] }
end
