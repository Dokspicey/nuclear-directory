# Checks render.yaml for mistakes that would deploy without an error but
# break backups or expose the database. Run by CI (blueprint job).
require "yaml"

blueprint = YAML.load_file(File.expand_path("../../render.yaml", __dir__))
problems = []

backup = blueprint["services"].find { |service| service["name"] == "nuclear-directory-backup" }
if backup.nil?
  problems << "the nuclear-directory-backup cron job is missing"
else
  recipient = backup["envVars"].find { |var| var["key"] == "BACKUP_AGE_RECIPIENT" }&.dig("value").to_s
  # An age X25519 public key: "age1" plus 58 bech32 characters.
  unless recipient.match?(/\Aage1[02-9ac-hj-np-z]{58}\z/)
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
