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
