# A candidate as a plain-English claim, for the verifier model to check
# against its source:
#   facility: "There is a facility "Vogtle 3" with NRC docket 05200025,
#              facility type power reactor, status operating, …"
#   facility_relationship: "Southern Nuclear Operating Co. operates the
#              facility Vogtle 3 (NRC docket 05200025)."
module DataQuality::Claim
  RELATIONSHIP_VERBS = {
    "supplies" => "supplies", "invests_in" => "invests in", "funds" => "funds",
    "offtake_with" => "has an offtake agreement with", "subsidiary_of" => "is a subsidiary of",
    "owns" => "owns", "operates" => "operates", "vendor_for" => "is the vendor for", "offtakes_from" => "buys power from"
  }.freeze

  def self.describe(candidate)
    payload = candidate.payload

    case candidate.kind
    when "organization"
      "There is an organization named #{payload['name'].inspect}#{details(payload.except('name'))}."
    when "organization_alias"
      "#{name_of(payload['organization'])} is also known as #{payload['alias'].inspect}."
    when "facility"
      "There is a facility named #{payload['name'].inspect}#{details(payload.except('name'))}."
    # Links carry every detail approval would publish (ownership %, dates,
    # description), so nothing is published that the verifier didn't check.
    when "facility_relationship"
      "#{name_of(payload['organization'])} #{verb(payload['relationship_type'])} the facility " \
        "#{facility_name(payload['facility'])}#{details(payload.except('organization', 'facility', 'relationship_type'))}."
    when "relationship"
      "#{name_of(payload['from_organization'])} #{verb(payload['relationship_type'])} #{name_of(payload['to_organization'])}" \
        "#{details(payload.except('from_organization', 'to_organization', 'relationship_type'))}."
    when "organization_role"
      "#{name_of(payload['organization'])} has the role #{humanize(payload['role'])}."
    when "organization_technology"
      "#{name_of(payload['organization'])} works with the technology #{humanize(payload['technology'])}."
    else
      "#{candidate.kind.humanize}: #{payload.to_json}"
    end
  end

  def self.details(attributes)
    pairs = attributes.compact_blank.map { |key, value| "#{key.humanize(capitalize: false)} #{value_text(key, value)}" }
    pairs.empty? ? "" : ", with #{pairs.to_sentence}"
  end

  def self.value_text(key, value)
    %w[facility_type status].include?(key) ? humanize(value) : value.to_s
  end

  def self.name_of(ends) = ends.is_a?(Hash) ? (ends["name"] || ends["domain"]).to_s : ends.to_s

  def self.facility_name(ends)
    docket = ends.is_a?(Hash) && ends["nrc_docket"]
    docket ? "#{name_of(ends)} (NRC docket #{docket})" : name_of(ends)
  end

  def self.verb(type) = RELATIONSHIP_VERBS.fetch(type.to_s, humanize(type))
  def self.humanize(value) = value.to_s.humanize(capitalize: false)
  private_class_method :details, :value_text, :name_of, :facility_name, :verb, :humanize
end
