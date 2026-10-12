# Checks render.yaml for mistakes that would deploy without an error but
# break backups or expose the database. Run by CI (blueprint job).
require "yaml"

# age public keys are Bech32 (BIP 173) with the "age" prefix. Checking the
# checksum catches a mistyped key before the weekly backup fails on it.
BECH32 = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

def bech32_valid?(string)
  hrp, data = string.downcase.match(/\A(.+)1([#{BECH32}]{6,})\z/)&.captures
  return false if hrp.nil? || string != string.downcase

  values = hrp.bytes.map { |b| b >> 5 } + [ 0 ] + hrp.bytes.map { |b| b & 31 } + data.chars.map { |c| BECH32.index(c) }
  generators = [ 0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3 ]
  checksum = values.reduce(1) do |chk, value|
    top = chk >> 25
    chk = ((chk & 0x1ffffff) << 5) ^ value
    5.times.reduce(chk) { |acc, i| top[i] == 1 ? acc ^ generators[i] : acc }
  end
  checksum == 1
end

# A database may allow single IPv4 hosts (/32) that say whose they are, e.g.
# Tosin's home IP for local Metabase (#111). Anything wider stays blocked.
def allowed_ip_entry?(entry)
  return false unless entry.is_a?(Hash) && entry["description"].to_s.strip != ""

  octets = entry["source"].to_s.match(/\A(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\/32\z/)&.captures&.map(&:to_i)
  !octets.nil? && octets.all? { |octet| octet <= 255 } && octets != [ 0, 0, 0, 0 ]
end

# RENDER_YAML lets the test point this at sample blueprints.
blueprint = YAML.load_file(ENV.fetch("RENDER_YAML", File.expand_path("../../render.yaml", __dir__)))
problems = []

backup = blueprint["services"].find { |service| service["name"] == "nuclear-directory-backup" }
if backup.nil?
  problems << "the nuclear-directory-backup cron job is missing"
else
  recipient = backup["envVars"].find { |var| var["key"] == "BACKUP_AGE_RECIPIENT" }&.dig("value").to_s
  # An age X25519 public key: "age1" plus 58 bech32 characters.
  unless recipient.match?(/\Aage1[#{BECH32}]{58}\z/) && bech32_valid?(recipient)
    problems << "BACKUP_AGE_RECIPIENT is #{recipient.inspect}, not an age public key (age1...)"
  end
end

# The UI preview must never reach production data or carry production secrets.
preview = blueprint["services"].find { |service| service["name"] == "nuclear-directory-preview" }
if preview
  entries = preview.fetch("envVars", [])
  # Only these keys, each a plain value, generated, or (DATABASE_URL) set by
  # hand. No fromDatabase, fromService or fromGroup anywhere: any of them could
  # hand production's connection string or secrets to preview code, under
  # whatever name.
  allowed = %w[DATABASE_URL NOINDEX DISABLE_DATABASE_ENVIRONMENT_CHECK SECRET_KEY_BASE RAILS_MAX_THREADS]
  references = %w[fromDatabase fromService fromGroup]
  entries.each do |var|
    if !var.is_a?(Hash) || var["key"].to_s.empty? || references.any? { |ref| var.key?(ref) }
      problems << "the preview may not take values from other services, databases or environment groups " \
        "(fromDatabase, fromService, fromGroup): #{var.inspect}"
    elsif !allowed.include?(var["key"])
      problems << "the preview must not set #{var["key"]} (allowed: #{allowed.join(", ")})"
    end
  end
  vars = entries.select { |var| var.is_a?(Hash) && var["key"] }.to_h { |var| [ var["key"], var ] }
  database_url = vars["DATABASE_URL"]
  unless database_url && database_url["sync"] == false && !database_url.key?("value")
    problems << "the preview's DATABASE_URL must be sync: false (set by hand to the preview database), never fromDatabase or a value"
  end
  problems << "the preview must set NOINDEX to \"1\"" unless vars.dig("NOINDEX", "value").to_s == "1"
  problems << "the preview must not have custom domains" if preview["domains"]
end

blueprint["databases"].each do |database|
  allow_list = database["ipAllowList"]
  # At most one host: Tosin's Mac for local Metabase (#111), nothing else.
  unless allow_list.is_a?(Array) && allow_list.size <= 1 && allow_list.all? { |entry| allowed_ip_entry?(entry) }
    problems << "database #{database["name"]} may only allow one IPv4 host (x.x.x.x/32) with a description; " \
      "use ipAllowList: [] for no access from the internet"
  end
end

if problems.empty?
  puts "render.yaml OK"
else
  problems.each { |problem| puts "::error file=render.yaml::#{problem}" }
  exit 1
end
