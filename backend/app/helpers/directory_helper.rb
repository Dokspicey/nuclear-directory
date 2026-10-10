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
    "national_lab" => "National lab"
  }.freeze

  # Bars filled out of 3, and the word shown beside them.
  CONFIDENCE_LEVELS = [
    [ 0.9, 3, "High" ],
    [ 0.7, 2, "Medium" ],
    [ 0.0, 1, "Low" ]
  ].freeze

  # Public URLs. The routes arrive with their pages (#40 directory and search,
  # #42 company, #43 power plant); until then the paths are built here, in one
  # place, so those issues only swap in the route helpers.
  def directory_url_for(category: nil, q: nil)
    query = { category: category&.to_param, q: q.presence }.compact.to_query
    [ "/companies", query.presence ].compact.join("?")
  end

  def company_url_for(organization) = "/companies/#{organization.slug}"
  def plant_url_for(facility) = "/power-plants/#{facility.slug}"

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

  # Dates in data contexts are ISO; prose uses "October 2024".
  def data_date(date) = date&.to_date&.iso8601
  def prose_month(date) = date&.to_date&.strftime("%B %Y")

  # "kairospower.com" for a source, from its domain or URL.
  def source_domain(source)
    source.domain.presence || URI.parse(source.url.to_s).host.to_s.delete_prefix("www.")
  rescue URI::InvalidURIError
    source.url
  end
end
