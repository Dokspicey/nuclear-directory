namespace :data_quality do
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
end
