# Words and small formats the public pages share. The wording follows
# VOICE.md: visitors see "company" and "power plant", never the data model's
# "organization" and "facility". Change a label here and every page follows.
module DirectoryHelper
  # Read left to right: "<from> <verb> <to>", e.g. "Google offtakes from Kairos Power".
  RELATIONSHIP_VERBS = {
    "supplies" => "supplies",
    "invests_in" => "invests in",
    "funds" => "funds",
    "offtake_with" => "offtakes from",
    "subsidiary_of" => "is a subsidiary of"
  }.freeze

  # "<company> <verb> <plant>", e.g. "Westinghouse is the reactor vendor for Plant Vogtle".
  FACILITY_RELATIONSHIP_VERBS = {
    "owns" => "owns",
    "operates" => "operates",
    "vendor_for" => "is the reactor vendor for",
    "offtakes_from" => "offtakes from"
  }.freeze

  FACILITY_TYPE_LABELS = {
    "power_reactor" => "Power plant",
    "research_reactor" => "Test reactor",
    "fuel_facility" => "Fuel plant",
    "enrichment" => "Enrichment plant",
    "fusion_facility" => "Fusion plant",
    "uranium_mine" => "Uranium mine",
    "mill" => "Uranium mill",
    "other" => "Site"
  }.freeze

  FACILITY_STATUS_LABELS = {
    "operating" => "Operating",
    "under_construction" => "Under construction",
    "planned" => "Planned",
    "shut_down" => "Shut down",
    "decommissioning" => "Being decommissioned"
  }.freeze

  ROLE_LABELS = {
    "fuel" => "Fuel supplier",
    "mining" => "Uranium mining and milling",
    "conversion" => "Uranium conversion",
    "enrichment" => "Enrichment",
    "fabrication" => "Fuel fabrication",
    "reactor_vendor" => "Reactor developer",
    "reactor_services" => "Repair and services",
    "utility" => "Utility",
    "operator" => "Plant operator",
    "data_center_offtaker" => "Power buyer",
    "coolant" => "Coolant",
    "regulatory_consultant" => "Regulatory consultant",
    "venture_capital" => "Investor",
    "government_agency" => "Government agency",
    "national_lab" => "National lab",
    "molten_salt" => "Molten salt coolant",
    "water" => "Water coolant",
    "helium" => "Helium coolant",
    "sodium" => "Sodium coolant",
    "lead" => "Lead coolant",
    "heavy_water" => "Heavy water"
  }.freeze

  # Bars filled out of 3, and the word shown beside them.
  CONFIDENCE_LEVELS = [
    [ 0.9, 3, "High" ],
    [ 0.7, 2, "Medium" ],
    [ 0.0, 1, "Low" ]
  ].freeze

  # Public URLs, so views link to pages without knowing the routes.
  def directory_url_for(category: nil, q: nil, **filters)
    companies_path({ category: category&.to_param, q: q.presence }.merge(filters).compact_blank)
  end

  def company_url_for(organization) = company_path(slug: organization.slug)

  # "Report a correction", prefilled with what it's about and where it was.
  CORRECTIONS_EMAIL = "hello@nuclear-directory.org".freeze
  def correction_url_for(subject, page: request.path) = new_correction_path(subject:, page:)

  def correction_mailto(subject, page)
    "mailto:#{CORRECTIONS_EMAIL}?" + { subject: "Correction: #{subject}", body: "Page: #{request.base_url}#{page}\n\nWhat should change:\n" }
      .to_query.gsub("+", "%20")
  end
  def plant_url_for(facility) = plant_path(slug: facility.slug)

  def relationship_verb(type) = RELATIONSHIP_VERBS.fetch(type.to_s)
  def facility_relationship_verb(type) = FACILITY_RELATIONSHIP_VERBS.fetch(type.to_s)
  def facility_type_label(type) = FACILITY_TYPE_LABELS[type.to_s]
  def facility_status_label(status) = FACILITY_STATUS_LABELS[status.to_s]

  # Roles whose parent is shown instead (enrichment under fuel) are left to the caller.
  def role_label(role)
    key = role.respond_to?(:key) ? role.key : role.to_s
    ROLE_LABELS[key] || (role.respond_to?(:name) ? role.name : key.humanize)
  end

  # nil confidence gives nil: show nothing rather than a guess.
  def confidence_level(confidence)
    return if confidence.nil?

    _, bars, word = CONFIDENCE_LEVELS.find { |threshold, *| confidence.to_d >= threshold }
    { bars: bars, word: word }
  end

  # "Kairos Power" => "KP", "X-energy" => "XE", "Westinghouse Electric Company" => "WE".
  def initials(name)
    words = name.to_s.split(/[\s\-]+/).reject { |word| word.casecmp?("the") || word.blank? }
    words.first(2).map { |word| word[0] }.join.upcase
  end

  # "Alameda, CA", "CA" or nil when neither is known.
  def place(city, state)
    [ city.presence, state.presence ].compact.join(", ").presence
  end

  # Two sentences, with a full stop between them unless the first has one.
  def sentence_join(first, second)
    first = first.to_s.strip
    first.match?(/[.!?]\z/) ? "#{first} #{second}" : "#{first}. #{second}"
  end

  # Dates in data contexts are ISO; prose uses "October 2024".
  def data_date(date) = date&.to_date&.iso8601
  def prose_month(date) = date&.to_date&.strftime("%B %Y")

  # The URL if it's a web address we can safely link to, else nil. Source
  # URLs come from crawled and imported data, so anything that isn't plain
  # http(s) (e.g. "javascript:") is shown as text, never as a link.
  def safe_source_url(source)
    uri = URI.parse(source.url.to_s.strip)
    source.url.to_s.strip if %w[http https].include?(uri.scheme&.downcase) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  # "kairospower.com" for a source, from its domain or URL.
  # A URL with no host (a bad import such as "javascript:...") reads
  # "unlinked source", so chips and their labels are never blank.
  def source_domain(source)
    source.domain.presence || URI.parse(source.url.to_s).host.to_s.delete_prefix("www.").presence || "unlinked source"
  rescue URI::InvalidURIError
    "unlinked source"
  end
end
