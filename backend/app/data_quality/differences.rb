# Where a candidate disagrees with a value a human verified on its record.
# Verify sends such candidates to review; the admin shows both values before
# a human approves one (approving applies the source's value).
#
#   DataQuality::Differences.with_human_verified(candidate, record)
#   # => { "state" => ["NJ", "DE"] }   # [verified, this source]
module DataQuality::Differences
  # Compared per kind. Names aren't: spelling and legal-form variants are
  # expected, and aliases cover them.
  COMPARED = {
    "organization" => %w[domain],
    "facility" => %w[nrc_docket facility_type status state country_code]
  }.freeze

  # record: a DirectoryClient::Record (or nil). Only a record a human
  # verified counts; anything else has no human value to protect.
  def self.with_human_verified(candidate, record)
    return {} unless record && record.verification_status == "verified" && record.verified_by.to_s.start_with?("human:")

    COMPARED.fetch(candidate.kind, []).each_with_object({}) do |name, differences|
      stored = comparable(name, record.public_send(name))
      incoming = comparable(name, incoming_value(candidate, name))
      next if stored.blank? || incoming.blank? || stored == incoming

      differences[name] = [ stored, incoming ]
    end
  end

  # "human-verified state is NJ; this source says DE"
  def self.describe(differences)
    differences.map { |name, (stored, incoming)| "human-verified #{name.humanize(capitalize: false)} is #{stored}; this source says #{incoming}" }
      .join("; ")
  end

  # An organization's domain may arrive as domain or only as website.
  def self.incoming_value(candidate, name)
    name == "domain" ? candidate.payload["domain"].presence || candidate.payload["website"] : candidate.payload[name]
  end

  # Domains compare as hosts: "https://WWW.TerraPower.com/news" is "terrapower.com".
  def self.comparable(name, value)
    return value.to_s unless name == "domain" && value.present?

    text = value.to_s.strip
    host = URI.parse(text.match?(%r{\A[a-z][a-z0-9+.-]*://}i) ? text : "https://#{text}").host
    host.to_s.downcase.delete_prefix("www.")
  rescue URI::InvalidURIError
    text.downcase.delete_prefix("www.")
  end
  private_class_method :incoming_value, :comparable
end
