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

blueprint = YAML.load_file(File.expand_path("../../render.yaml", __dir__))
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

blueprint["databases"].each do |database|
  unless database["ipAllowList"] == []
    problems << "database #{database["name"]} must keep ipAllowList: [] (no access from the internet)"
  end
end

if problems.empty?
  puts "render.yaml OK"
else
  problems.each { |problem| puts "::error file=render.yaml::#{problem}" }
  exit 1
end
