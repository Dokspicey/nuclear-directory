# Asks the extractor model to read NRC's reactor table and return one
# record per unit, each with the row it came from quoted exactly.
# The plug-in then checks every answer against the exact parse (Page.units).
class DataQuality::Plugins::NrcReactorList::Extractor
  # Bump when the prompt or schema changes; stored on the crawl run so
  # results can be traced to the prompt that produced them.
  PROMPT_VERSION = "nrc-extract-v1"
  # Rows per model call: small enough to keep answers short and complete.
  BATCH_SIZE = 25

  SCHEMA = {
    "type" => "object",
    "properties" => {
      "units" => {
        "type" => "array",
        "items" => {
          "type" => "object",
          "properties" => {
            "name" => { "type" => "string", "description" => "Unit name, e.g. \"Vogtle 3\"" },
            "nrc_docket" => { "type" => "string", "pattern" => "^[0-9]{8}$", "description" => "8-digit docket number" },
            "reactor_type" => { "type" => "string", "enum" => %w[PWR BWR] },
            "state" => { "type" => "string", "pattern" => "^[A-Z]{2}$", "description" => "2-letter state from Location" },
            "operator" => { "type" => "string", "description" => "Owner/Operator, exactly as written" },
            "quote" => { "type" => "string", "description" => "The whole input line for this unit, copied exactly" }
          },
          "required" => %w[name nrc_docket reactor_type state operator quote],
          "additionalProperties" => false
        }
      }
    },
    "required" => [ "units" ],
    "additionalProperties" => false
  }.freeze

  INSTRUCTIONS = <<~TEXT.freeze
    You extract facts from a table published by the US Nuclear Regulatory Commission
    (NRC): its list of operating power reactor units. Each input line is one table row,
    with cells separated by " | ". The first line names the columns.

    Return one record per unit row, in the order given. Copy every value exactly as it
    appears; never guess, correct, expand abbreviations or add information that isn't
    in the line. The state is the two-letter code at the end of Location. The quote must
    be the unit's entire input line, character for character.
  TEXT

  def initialize(llm: nil)
    @llm = llm
  end

  # lines: Page.lines (header first). Returns an array of unit hashes with
  # string keys, as the model returned them.
  def call(lines, run:)
    header, *rows = lines
    run.update!(prompt_version: PROMPT_VERSION)

    rows.each_slice(BATCH_SIZE).flat_map do |batch|
      response = llm.structured(
        role: :extract,
        schema: SCHEMA,
        schema_name: "nrc_reactor_units",
        crawl_run: run,
        # Copying a table needs little thought; reasoning tokens are billed.
        reasoning_effort: "low",
        messages: [
          { role: "system", content: INSTRUCTIONS },
          { role: "user", content: [ header, *batch ].join("\n") }
        ]
      )
      response.data.fetch("units")
    end
  end

  private
    # Built on first use, so crawling never needs an OpenRouter key.
    def llm = @llm ||= DataQuality::OpenRouter::Client.new
end
