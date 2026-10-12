namespace :data_quality do
  desc "Put NRC units already enriched by EIA under their EIA plant's site (#73, one-off)"
  task group_units: :environment do
    directory = DataQuality::DirectoryClient.new
    grouped = Candidate.status_merged.where(kind: "facility").where("payload ? 'identify'").filter_map do |candidate|
      result = directory.group_unit(candidate) or next
      puts "#{candidate.subject_type} #{candidate.subject_id}: #{result.errors.join('; ')}" unless result.success?
      result if result.success?
    end
    puts "Grouped #{grouped.size} units under their sites."
  end

  report = ->(runs) do
    runs.each { |run| puts "#{run.stage.ljust(8)} #{run.status.ljust(10)} #{run.stats.to_json}" }
  end

  desc "Run the whole pipeline for a source kind: bin/rails data_quality:run[nrc_reactor_list]"
  task :run, [ :source_kind ] => :environment do |_task, args|
    abort "Usage: bin/rails data_quality:run[source_kind]" if args[:source_kind].blank?

    report.call DataQuality::Pipeline.run(args[:source_kind])
  end

  desc "Run one stage for a source kind: bin/rails data_quality:stage[extract,nrc_reactor_list]"
  task :stage, [ :stage, :source_kind ] => :environment do |_task, args|
    abort "Usage: bin/rails data_quality:stage[stage,source_kind]" if args[:stage].blank? || args[:source_kind].blank?

    report.call DataQuality::Pipeline.run(args[:source_kind], only: args[:stage])
  end

  # Queued for the background worker rather than run here: on Render a second
  # Rails process doing the work would share the instance's 512 MB (#188).
  desc "Re-run extract, match and verify from the stored snapshot, no fetch: bin/rails data_quality:rerun[nrc_reactor_list]"
  task :rerun, [ :source_kind ] => :environment do |_task, args|
    abort "Usage: bin/rails data_quality:rerun[source_kind]" if args[:source_kind].blank?

    DataQuality::Plugin.for(args[:source_kind]) # an unknown kind fails here, not in the job
    DataQuality::RunJob.perform_later(args[:source_kind], only: DataQuality::Pipeline::FROM_SNAPSHOT)
    puts "Queued #{DataQuality::Pipeline::FROM_SNAPSHOT.join(', ')} for #{args[:source_kind]} " \
      "from its stored snapshot. Follow it with: bin/rails data_quality:status"
  end

  # #197: units approved with NRC's state, which is its reference city's.
  # Goes through the Review API as the named person, so the change and its
  # reason are in the unit's history like any admin decision.
  desc "Correct an NRC unit's state, audited: BY=human:tosin bin/rails \"data_quality:correct_unit_state[05000354,NJ]\""
  task :correct_unit_state, [ :nrc_docket, :state ] => :environment do |_task, args|
    by = ENV["BY"].to_s
    abort "Usage: BY=human:<handle> bin/rails \"data_quality:correct_unit_state[nrc_docket,STATE]\"" unless
      by.match?(/\Ahuman:\S+\z/) && args[:nrc_docket].present? && args[:state].to_s.match?(/\A[A-Z]{2}\z/)

    directory = DataQuality::DirectoryClient.new
    unit = directory.facility(nrc_docket: args[:nrc_docket]) or abort "No unit with NRC docket #{args[:nrc_docket]}"
    # A published unit only: approving would also publish a pending or taken-down one.
    unless unit.verification_status == "verified"
      abort "#{unit.name} isn't published (#{unit.verification_status}), so its state isn't corrected here"
    end
    reason = "State corrected from #{unit.state.presence || 'blank'} to #{args[:state]}: NRC's Location is measured from a " \
      "nearby city in another state; EIA-860M lists the plant in #{args[:state]} (#197)"
    result = DataQuality::Review.approve_fact(type: "Facility", id: unit.id, by:, reason:, attributes: { "state" => args[:state] },
      directory:)
    abort "#{unit.name}: #{result.errors.to_sentence}" unless result.ok?

    puts "#{unit.name} (#{unit.nrc_docket}): state #{directory.facility(id: unit.id).state}, recorded as #{by}"
  end

  desc "Check the OpenRouter key works, without a model call: bin/rails data_quality:check_key"
  task check_key: :environment do
    key = DataQuality::OpenRouter::Client.new.check_key
    limit = key[:limit] ? format("$%.2f", key[:limit]) : "no limit"
    puts "OpenRouter key OK (#{key[:label] || 'unlabelled'}): used #{format('$%.2f', key[:usage].to_f)} of #{limit}"
  rescue DataQuality::OpenRouter::Client::Error, DataQuality::Config::ConfigurationError => error
    abort "OpenRouter key check failed: #{error.message}"
  end

  desc "How the pipeline is doing: blocked sources, last runs, review queue, model spend"
  task status: :environment do
    puts DataQuality::StatusReport.call
  end

  desc "One-off: fetch a title for every source that has none (#64), politely"
  task backfill_titles: :environment do
    stats = DataQuality::TitleBackfill.run(log: ->(line) { puts line })
    puts stats.to_json
  end
end
