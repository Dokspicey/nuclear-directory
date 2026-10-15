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

  # "<company> <verb> <plant>", e.g. "Westinghouse is the reactor developer for Plant Vogtle".
  FACILITY_RELATIONSHIP_VERBS = {
    "owns" => "owns",
    "operates" => "operates",
    "vendor_for" => "is the reactor developer for",
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
  # A plant's link preview and meta description (#246), from published facts
  # only, each left out when it isn't known:
  #   "Plant Vogtle: Operating power plant in Waynesboro, GA. 4 units, 4,536 MWe.
  #    Owned by Georgia Power and 3 others; operated by Southern Nuclear."
  # Kept under PREVIEW_LIMIT characters: a long owner list becomes "<first>
  # and <n> others", then the units and capacity go, then owners.
  PREVIEW_LIMIT = 160

  def plant_preview(profile)
    kind = [ facility_status_label(profile.status), (profile.status ? facility_type_label(profile.facility_type)&.downcase : facility_type_label(profile.facility_type)) ]
      .compact.join(" ").presence
    where = place(profile.city, profile.state)
    what = kind ? [ kind, (where && "in #{where}") ].compact.join(" ") : (where && "In #{where}")
    units = profile.units.size
    capacity = "#{number_with_precision(profile.capacity_mw, precision: 2, strip_insignificant_zeros: true, delimiter: ",")} MWe" if profile.capacity_mw
    size = [ (pluralize(units, "unit") if units.positive?), capacity ].compact.join(", ").presence
    owners = profile.current_companies_for("owns").map(&:name)
    operators = profile.current_companies_for("operates").map(&:name)
    # Lists as the site writes them, without a serial comma ("A, B and C").
    listed = ->(names) { names.to_sentence(last_word_connector: " and ") }
    run_by = ->(owned) { [ (owned && "Owned by #{owned}"), (operators.any? && "operated by #{listed.call(operators)}") ].select(&:itself).join("; ").upcase_first.presence }
    few_owners = owners.many? ? "#{owners.first} and #{pluralize(owners.size - 1, 'other')}" : owners.first

    lines = [
      [ what, size, run_by.call(listed.call(owners).presence) ],
      [ what, size, run_by.call(few_owners) ],
      [ what, nil, run_by.call(few_owners) ],
      [ what, nil, run_by.call(nil) ],
      [ what, nil, nil ]
    ].map do |parts|
      body = parts.compact.map { |part| part.end_with?(".") ? part : "#{part}." }.join(" ")
      body.present? ? "#{profile.name}: #{body}" : profile.name
    end
    lines.find { |line| line.length <= PREVIEW_LIMIT } || lines.last.truncate(PREVIEW_LIMIT, separator: " ")
  end

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
