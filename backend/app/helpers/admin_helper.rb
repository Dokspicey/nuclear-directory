# Wording for the admin screens (#86), in visitors' words where a fact is
# described (VOICE.md) and plainly elsewhere.
module AdminHelper
  KIND_LABELS = {
    "organization" => "Companies", "facility" => "Plants and sites", "organization_role" => "Company roles",
    "organization_technology" => "Company technologies", "relationship" => "Deals between companies",
    "facility_relationship" => "Plant owners and operators"
  }.freeze
  TYPE_LABELS = {
    "Organization" => "Company", "Facility" => "Plant or site", "OrganizationRole" => "Company role",
    "OrganizationTechnology" => "Company technology", "Relationship" => "Deal between companies",
    "FacilityRelationship" => "Plant owner or operator"
  }.freeze
  STATUS_WORDS = { "verified" => "Verified", "pending" => "Pending", "rejected" => "Rejected", "unpublished" => "Unpublished" }.freeze

  # Who decided, as the screen shows it: "tosin" for "human:tosin", "the
  # verifier (model)" for an agent. The data keeps the prefix.
  def who(by)
    by = by.to_s
    return by.delete_prefix("human:") if by.start_with?("human:")
    return "the verifier (#{by.delete_prefix('agent:verifier/')})" if by.start_with?("agent:verifier/")

    by
  end

  # Reply to a visitor's correction: their address, a subject, and the page.
  def correction_reply_mailto(report)
    "mailto:#{report.contact}?" + { subject: "Your correction on Nuclear Directory",
      body: "About #{request.base_url}#{report.page_path}\n\n" }.to_query.gsub("+", "%20")
  end

  # Ids of linked records; their names are shown instead.
  HIDDEN_FIELDS = %i[organization_id facility_id from_organization_id to_organization_id parent_id].freeze

  def kind_label(kind) = KIND_LABELS.fetch(kind.to_s, kind.to_s.humanize)

  # The admin fact page for the company or plant a correction came from
  # (its page_path, e.g. "/companies/terrapower"), or nil.
  def correction_record_path(report)
    path = report.page_path.to_s.split(/[?#]/).first
    type, slug = path.match(%r{\A/(companies|plants)/([^/]+)\z})&.captures
    return unless slug

    record = type == "companies" ? Directory::Lookup.organization(slug:) : Directory::Lookup.facility(slug:)
    admin_fact_path(type: type == "companies" ? "Organization" : "Facility", id: record.id) if record
  end

  # The public page of a published company or plant, or nil.
  def public_page_path(fact)
    slug = fact.values["slug"].presence
    return unless fact.published && slug

    case fact.type
    when "Organization" then company_path(slug:)
    when "Facility" then plant_path(slug:)
    end
  end

  # A pending fact as one line: its name, or the link in words
  # ("Southern Company owns Vogtle 3").
  def fact_heading(fact)
    values = fact.attributes.symbolize_keys
    verb = ->(type) { DataQuality::Claim::RELATIONSHIP_VERBS.fetch(type.to_s, type.to_s.humanize(capitalize: false)) }
    case fact.kind
    when "organization", "facility" then values[:name]
    when "organization_role" then "#{values[:organization_name]}: #{role_label(values[:role]).downcase_first}"
    when "organization_technology" then "#{values[:organization_name]}: #{values[:technology].to_s.humanize(capitalize: false)}"
    when "relationship" then "#{values[:from_organization_name]} #{verb.(values[:relationship_type])} #{values[:to_organization_name]}"
    when "facility_relationship" then "#{values[:organization_name]} #{verb.(values[:relationship_type])} #{values[:facility_name]}"
    else "#{type_label(fact.type)} #{fact.id}"
    end
  end
  def type_label(type) = TYPE_LABELS.fetch(type.to_s, type.to_s.titleize)

  # Status in words and shape (DESIGN.md): verified solid, pending dashed,
  # rejected struck through in critical, unpublished dashed with its word.
  def status_badge(status)
    word = STATUS_WORDS.fetch(status.to_s, status.to_s.humanize)
    case status.to_s
    when "verified" then tag.span(safe_join([ icon("check", weight: :bold, size: 12), word ]), class: "nd-badge nd-badge--verified")
    when "rejected" then tag.span(safe_join([ icon("x", weight: :bold, size: 12), word ]), class: "nd-badge nd-badge--rejected")
    when "pending" then tag.span(safe_join([ icon("clock", size: 12), word ]), class: "nd-badge nd-badge--pending")
    else tag.span(word, class: "nd-badge nd-badge--pending")
    end
  end

  def field_label(name) = DataQuality::Claim::LABELS.fetch(name.to_s) { name.to_s.humanize }

  # A value for its field: a role in visitors' words ("Reactor developer").
  def field_display(name, value) = name.to_s == "role" && value.present? ? role_label(value) : field_value(value)

  # What a decision changed: "state DE to NJ; aliases …".
  def changes_text(changed_values)
    changed_values.to_h.map do |name, (before, after)|
      "#{field_label(name).downcase_first} #{before.presence || 'blank'} to #{after.presence || 'blank'}"
    end.join("; ")
  end

  def field_value(value)
    case value
    when nil, "" then tag.span("Not set", class: "text-ink-muted")
    when Array then value.empty? ? tag.span("None", class: "text-ink-muted") : value.join(", ")
    when Hash then value.values_at("name", "domain", "nrc_docket").compact.join(", ")
    when Date, Time then tag.span(data_date(value), class: "nd-num")
    when Numeric then tag.span(value.to_s, class: "nd-num")
    # Stored keys such as "power_reactor" or "active" read as words.
    when /\A[a-z]+(_[a-z]+)*\z/ then value.humanize
    else value.to_s
    end
  end

  # "nrc.gov" from a source URL; the URL is shown as text when it isn't http(s).
  def source_host(url)
    URI.parse(url.to_s).host.to_s.delete_prefix("www.").presence || url.to_s
  rescue URI::InvalidURIError
    url.to_s
  end

  def safe_url(url)
    uri = URI.parse(url.to_s.strip)
    url.to_s.strip if %w[http https].include?(uri.scheme&.downcase) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  def percent(confidence) = confidence && "#{(confidence.to_d * 100).floor}%"

  # Model spend: cents, but a few calls' worth reads "under $0.01", not $0.00.
  def money(amount)
    amount = amount.to_d
    amount.positive? && amount < 0.01.to_d ? "under $0.01" : format("$%.2f", amount)
  end

  ACRONYMS = { "ai" => "AI", "nrc" => "NRC", "eia" => "EIA", "llm" => "LLM", "url" => "URL" }.freeze

  # A stats key in words, acronyms kept: "ai_check" => "AI check".
  def stat_label(key)
    key.to_s.humanize(capitalize: false).split.map { |word| ACRONYMS.fetch(word, word) }.join(" ").upcase_first
  end

  # A run's stats in words: "Sources 1; AI check: agreed 95, missed 0".
  def run_detail(stats)
    stats.map do |key, value|
      value = value.map { |k, v| "#{stat_label(k).downcase_first} #{v}" }.join(", ") if value.is_a?(Hash)
      "#{stat_label(key)}#{':' if stats[key].is_a?(Hash)} #{value}"
    end.join("; ").truncate(200)
  end

  # "42.9 s", "72 min", "1 h 12 min".
  def run_duration(seconds)
    return "running" if seconds.nil?
    return "#{seconds} s" if seconds <= 90

    minutes = (seconds / 60.0).round
    minutes < 90 ? "#{minutes} min" : "#{minutes / 60} h #{minutes % 60} min"
  end

  # What happened, in a history row: "Pending to verified".
  def change_text(event)
    [ event.from_status, event.to_status ].compact.map { |status| STATUS_WORDS.fetch(status, status.humanize) }.join(" to ")
  end
end
