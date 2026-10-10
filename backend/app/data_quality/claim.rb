# A candidate as a plain-English claim, for the verifier model to check
# against its source and for the admin to show. Visitors' words (VOICE.md):
# company, not organization; plant, not facility.
#   facility: "There is a plant named "Vogtle 3", with NRC docket 05200025,
#              plant type power reactor, and status operating."
#   facility_relationship: "Southern Nuclear Operating Co. operates the
#              plant Vogtle 3 (NRC docket 05200025)."
module DataQuality::Claim
  RELATIONSHIP_VERBS = {
    "supplies" => "supplies", "invests_in" => "invests in", "funds" => "funds",
    "offtake_with" => "has an offtake agreement with", "subsidiary_of" => "is a subsidiary of",
    "owns" => "owns", "operates" => "operates", "vendor_for" => "is a vendor for", "offtakes_from" => "offtakes from"
  }.freeze
  # Roles in visitors' words (VOICE.md), as the directory's review labels say them.
  ROLE_WORDS = { "reactor_vendor" => "reactor developer", "reactor_services" => "repair and services company",
    "data_center_offtaker" => "power buyer" }.freeze
  LABELS = { "nrc_docket" => "NRC docket", "facility_type" => "plant type", "ownership_pct" => "ownership",
    "hq_city" => "headquarters city", "hq_state" => "headquarters state", "capacity_mw" => "capacity" }.freeze

  def self.describe(candidate)
    payload = candidate.payload

    case candidate.kind
    when "organization"
      "There is a company named “#{payload['name']}”#{details(payload.except('name'))}."
    when "organization_alias"
      "#{name_of(payload['organization'])} is also known as “#{payload['alias']}”."
    when "facility"
      "There is a plant named “#{payload['name']}”#{details(payload.except('name'))}."
    # Links carry every detail approval would publish (ownership %, dates,
    # description), so nothing is published that the verifier didn't check.
    when "facility_relationship"
      "#{name_of(payload['organization'])} #{verb(payload['relationship_type'])} the plant " \
        "#{facility_name(payload['facility'])}#{details(payload.except('organization', 'facility', 'relationship_type'))}."
    when "relationship"
      "#{name_of(payload['from_organization'])} #{verb(payload['relationship_type'])} #{name_of(payload['to_organization'])}" \
        "#{details(payload.except('from_organization', 'to_organization', 'relationship_type'))}."
    when "organization_role"
      "#{name_of(payload['organization'])} is #{with_article(role_words(payload['role']))}."
    when "organization_technology"
      "#{name_of(payload['organization'])} works on #{humanize(payload['technology'])}."
    else
      "#{candidate.kind.humanize}: #{payload.to_json}"
    end
  end

  def self.details(attributes)
    pairs = attributes.compact_blank.map { |key, value| "#{LABELS.fetch(key) { key.humanize(capitalize: false) }} #{value_text(key, value)}" }
    pairs.empty? ? "" : ", with #{pairs.to_sentence}"
  end

  def self.value_text(key, value)
    case key
    when "facility_type", "status" then humanize(value)
    when "ownership_pct" then "#{value}%"
    when "capacity_mw" then "#{value} MW"
    else value.to_s
    end
  end

  def self.name_of(ends) = ends.is_a?(Hash) ? (ends["name"] || ends["domain"]).to_s : ends.to_s

  def self.facility_name(ends)
    docket = ends.is_a?(Hash) && ends["nrc_docket"]
    docket ? "#{name_of(ends)} (NRC docket #{docket})" : name_of(ends)
  end

  def self.verb(type) = RELATIONSHIP_VERBS.fetch(type.to_s, humanize(type))
  def self.role_words(key) = ROLE_WORDS.fetch(key.to_s, humanize(key))
  def self.with_article(words) = "#{words.match?(/\A[aeiou]/i) ? 'an' : 'a'} #{words}"
  def self.humanize(value) = value.to_s.humanize(capitalize: false)
  private_class_method :details, :value_text, :name_of, :facility_name, :verb, :role_words, :with_article, :humanize
end
