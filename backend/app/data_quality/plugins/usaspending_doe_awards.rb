require "csv"

# U.S. Department of Energy awards from USAspending.gov (#123), the first
# deals and funding source (M5). Proposes each recipient company and one
# "U.S. Department of Energy funds <company>" link per company, whose
# description sums up its awards; each award is cited on the recipient's
# USAspending page, where it's listed.
#
# Crawl asks USAspending's award search API (a JSON POST, through the
# shared Fetcher's rules) for three searches, businesses only, $1M or more,
# with activity in the last five years:
# - nuclear energy R&D grants and cooperative agreements (Assistance
#   Listing 81.121, which includes the ARDP demonstrations)
# - DOE contracts mentioning HALEU or nuclear fuel
# - fusion grants under the Office of Science (81.049, "fusion")
# The API's own fetch state (today's fetch, a block) is kept on an index
# source that's never extracted. Awards are stored as CSV rows, one source
# per recipient, with every field a later award table needs (#256): award
# ID, amount, dates, Assistance Listing, award type and its page.
#
# Extract reads those rows; no model is asked. Match, verify and a human's
# approval are shared, as for every source.
class DataQuality::Plugins::UsaspendingDoeAwards < DataQuality::Plugin
  API_URL = "https://api.usaspending.gov/api/v2/search/spending_by_award/"
  INDEX_SOURCE_KIND = "usaspending_api"
  FUNDER = "U.S. Department of Energy"
  YEARS = 5
  MIN_AMOUNT = 1_000_000
  PAGE_SIZE = 100
  MAX_PAGES = 10 # per search: 1,000 awards, far more than these searches hold
  ASSISTANCE = %w[02 03 04 05].freeze # grants and cooperative agreements
  CONTRACTS = %w[A B C D].freeze
  SEARCHES = {
    "nuclear_energy_rd" => { award_type_codes: ASSISTANCE, program_numbers: [ "81.121" ] },
    "haleu_fuel_contracts" => { award_type_codes: CONTRACTS, keywords: [ "HALEU", "nuclear fuel" ] },
    "fusion" => { award_type_codes: ASSISTANCE, program_numbers: [ "81.049" ], keywords: [ "fusion" ] }
  }.freeze
  FIELDS = [ "Award ID", "Recipient Name", "Award Amount", "Start Date", "End Date", "Description", "generated_internal_id", "recipient_id" ].freeze
  COLUMNS = %w[award_id recipient_name amount_usd start_date end_date award_type assistance_listing search award_url
    generated_award_id recipient_id description].freeze

  def initialize(fetcher: DataQuality::Fetcher.new)
    @fetcher = fetcher
  end

  def crawl(_run)
    index = Source.find_or_create_by!(url: API_URL) do |source|
      source.source_kind = INDEX_SOURCE_KIND
      source.title = "USAspending.gov award search API"
    end
    rows = nil
    # At most once a day, recorded on the index source under its lock, as Snapshot does for a page.
    result = DataQuality::Snapshot.claim(index) do
      next :skipped_recent if index.fetched_at&.to_date == Date.current

      rows, failure = search_all
      record(index, failure)
    end
    return { "api" => result.to_s } unless result == :ok

    { "api" => "ok", "awards" => rows.size }.merge(store_by_recipient(rows))
  end

  # The facts every row's source states, which a single row doesn't repeat.
  def source_facts(source)
    return unless source.source_kind == source_kind

    "Each row is one award from the U.S. Department of Energy to the company named in it, from USAspending.gov's " \
      "award search: its award ID, amount in US dollars, start and end dates, and whether it's financial assistance " \
      "(a grant or cooperative agreement, with its Assistance Listing: 81.121 is Nuclear Energy research, development " \
      "and demonstration, 81.049 is the Office of Science) or a contract."
  end

  def extract(source, _run)
    rows = CSV.parse(source.content_text.to_s, headers: true).select { |row| row["recipient_name"].present? }
    return [] if rows.empty?

    recipient = rows.first["recipient_name"]
    largest = rows.max_by { |row| row["amount_usd"].to_d }
    quote = largest.to_csv.chomp
    [
      { kind: "organization", payload: { "name" => recipient }, quote: },
      { kind: "relationship", quote:, payload: {
        "from_organization" => { "name" => FUNDER }, "to_organization" => { "name" => recipient },
        "relationship_type" => "funds", "description" => summary(rows),
        "started_on" => rows.filter_map { |row| row["start_date"].presence }.min
      }.compact }
    ]
  end

  private
    # [rows, nil], or [nil, the Response that stopped it].
    def search_all
      rows = {}
      SEARCHES.each do |name, filters|
        (1..MAX_PAGES).each do |page|
          response = @fetcher.post_json(API_URL, request_body(filters, page))
          return [ nil, response ] unless response.kind == :ok

          data = JSON.parse(response.body)
          data["results"].to_a.each do |award|
            row = row_for(award, name)
            rows[row["generated_award_id"]] ||= row # an award two searches find is kept once
          end
          break unless data.dig("page_metadata", "hasNext")
        end
      end
      [ rows.values, nil ]
    rescue JSON::ParserError => error
      [ nil, DataQuality::Fetcher::Response.new(url: API_URL, kind: :error, status: 200, body: nil, etag: nil, last_modified: nil,
        reason: "USAspending answered with something that isn't JSON (#{error.message.truncate(80)})", block_reference: nil,
        content_type: nil, truncated: false) ]
    end

    def request_body(filters, page)
      contract = filters[:award_type_codes] == CONTRACTS
      {
        filters: filters.merge(
          agencies: [ { type: "awarding", tier: "toptier", name: "Department of Energy" } ],
          time_period: [ { start_date: YEARS.years.ago.to_date.iso8601, end_date: Date.current.iso8601 } ],
          award_amounts: [ { lower_bound: MIN_AMOUNT } ],
          recipient_type_names: [ "category_business" ]
        ),
        fields: contract ? FIELDS : FIELDS + [ "CFDA Number" ],
        page:, limit: PAGE_SIZE, sort: "Award Amount", order: "desc"
      }
    end

    def row_for(award, search)
      id = award["generated_internal_id"].to_s
      {
        "award_id" => award["Award ID"], "recipient_name" => award["Recipient Name"].to_s.strip,
        "amount_usd" => BigDecimal(award["Award Amount"].to_s).round(2).to_s("F"),
        "start_date" => award["Start Date"], "end_date" => award["End Date"],
        "award_type" => id.start_with?("CONT_") ? "contract" : "assistance", "assistance_listing" => award["CFDA Number"],
        "search" => search, "award_url" => "https://www.usaspending.gov/award/#{id}",
        "generated_award_id" => id, "recipient_id" => award["recipient_id"].to_s,
        "description" => award["Description"].to_s.squish.truncate(200)
      }
    end

    # The API's fetch recorded on the index source; :ok, or why not.
    def record(index, failure)
      attempt = { fetched_at: Time.current, http_status: failure&.status || 200 }
      case failure&.kind
      when nil
        index.update!(attempt.merge(crawl_status: "ok", status_reason: nil, blocked_streak: 0))
        :ok
      when :blocked
        streak = index.blocked_streak + 1
        index.update!(attempt.merge(blocked_streak: streak, status_reason: failure.reason,
          crawl_status: streak >= DataQuality::Snapshot::BLOCKED_STREAK_LIMIT ? "needs_human" : "blocked"))
        :blocked
      when :disallowed
        index.update!(attempt.merge(crawl_status: "needs_human", status_reason: failure.reason))
        :disallowed
      else
        index.update!(attempt.merge(status_reason: failure.reason)) # temporary: try tomorrow
        :error
      end
    end

    # One source per recipient: its USAspending page, holding its awards' rows.
    # Rows are sorted, so the same awards give the same content (and hash).
    def store_by_recipient(rows)
      stats = { "recipients" => 0, "changed" => 0 }
      rows.group_by { |row| row["recipient_id"].presence || row["recipient_name"] }.each do |recipient_id, awards|
        awards = awards.sort_by { |row| [ row["start_date"].to_s, row["award_id"].to_s ] }
        text = CSV.generate { |csv| csv << COLUMNS; awards.each { |row| csv << row.values_at(*COLUMNS) } }
        sha = Digest::SHA256.hexdigest(text)
        source = Source.find_or_create_by!(url: "https://www.usaspending.gov/recipient/#{recipient_id}/latest") do |new_source|
          new_source.source_kind = source_kind
          new_source.title = "USAspending.gov: Department of Energy awards to #{awards.first['recipient_name']}"
        end
        changed = source.content_sha256 != sha
        source.update!({ fetched_at: Time.current, crawl_status: "ok", status_reason: nil, http_status: 200 }
          .merge(changed ? { content_text: text, content_sha256: sha } : {}))
        stats["recipients"] += 1
        stats["changed"] += 1 if changed
      end
      stats
    end

    # "3 awards from the U.S. Department of Energy totaling $2.62 billion,
    # 2019–2026: DENE0009054, DENE0009040 and DENE0008928."
    def summary(rows)
      total = rows.sum { |row| row["amount_usd"].to_d }
      years = rows.filter_map { |row| row["start_date"].to_s[0, 4].presence }.minmax.uniq.join("–")
      ids = rows.sort_by { |row| -row["amount_usd"].to_d }.map { |row| row["award_id"] }
      listed = ids.size > 3 ? "#{ids.first(3).join(', ')} and #{ids.size - 3} more" : ids.to_sentence(last_word_connector: " and ")
      noun = rows.size == 1 ? "award" : "awards"
      "#{rows.size} #{noun} from the #{FUNDER} totaling #{dollars(total)}#{", #{years}" if years.present?}: #{listed}."
    end

    def dollars(amount)
      if amount >= 1_000_000_000 then "$#{(amount / 1_000_000_000).round(2).to_s('F')} billion"
      elsif amount >= 1_000_000 then "$#{(amount / 1_000_000).round(1).to_s('F')} million"
      else "$#{amount.round.to_i.to_fs(:delimited)}"
      end
    end
end
