namespace :directory do
  desc "Keep the old slugs of plants and companies renamed or merged before #143 (one-off, safe to rerun)"
  task backfill_former_slugs: :environment do
    kept = []
    # A rename a human made is in the audit trail as a slug change.
    VerificationEvent.where(subject_type: %w[Facility Organization]).where("changed_values ? 'slug'").find_each do |event|
      old = Array(event.changed_values["slug"]).first
      record = event.subject_type.constantize.find_by(id: event.subject_id) or next
      next if old.blank? || old == record.slug || record.class.exists?(slug: old) || record.former_slugs.exists?(slug: old)

      record.remember_slug(old) && kept << "#{event.subject_type} #{old} -> #{record.slug}"
    end
    # A merged company's unpublish reason names the company it went into.
    Organization.unpublished.find_each do |merged|
      into_id = merged.verification_events.order(:id).last&.reason.to_s[/Merged into .+? \(#(\d+)\)/, 1] or next
      into = Organization.find_by(id: into_id) or next
      next if into.former_slugs.exists?(slug: merged.slug)

      into.remember_slug(merged.slug) && kept << "Organization #{merged.slug} -> #{into.slug}"
    end
    puts kept.any? ? kept : "Nothing to backfill."
  end

  # Merges one plant site or company into another (#229), as the named
  # person. Without APPLY=1 it's a dry run: the merge runs, prints what it
  # would move, and is rolled back.
  merge = lambda do |model, method, args|
    by = ENV["BY"].to_s
    apply = ENV["APPLY"] == "1"
    from_id, into_id = args[:from].to_s, args[:into].to_s
    abort "Usage: BY=human:<handle> [APPLY=1] bin/rails \"directory:#{method}[from_id,into_id]\"" unless
      by.match?(/\Ahuman:\S+\z/) && [ from_id, into_id ].all? { |id| id.match?(/\A\d+\z/) }

    names = model.where(id: [ from_id, into_id ]).pluck(:id, :name).to_h
    ActiveRecord::Base.transaction(requires_new: true) do
      result = Directory::FactWriter.public_send(method, from_id: from_id.to_i, into_id: into_id.to_i, by:, reason: ENV["REASON"].presence)
      abort "#{names[from_id.to_i] || from_id} -> #{names[into_id.to_i] || into_id}: #{result.errors.to_sentence}" unless result.ok?

      moved = VerificationEvent.where(subject_type: model.name, subject_id: from_id.to_i).order(:id).last.reason
      puts "#{apply ? 'Merged' : 'Would merge'} #{names[from_id.to_i]} (##{from_id}) into #{names[into_id.to_i]} (##{into_id}): #{moved}"
      raise ActiveRecord::Rollback unless apply
    end
    puts "Dry run: nothing changed. Add APPLY=1 to merge." unless apply
  end

  desc "Merge a duplicate plant site into the one kept, audited: BY=human:tosin [APPLY=1] bin/rails \"directory:merge_facility[173,13]\""
  task :merge_facility, %i[from into] => :environment do |_task, args|
    merge.call(Facility, :merge_facility, args)
  end

  desc "Merge a duplicate company into the one kept, audited: BY=human:tosin [APPLY=1] bin/rails \"directory:merge_organization[80,34]\""
  task :merge_organization, %i[from into] => :environment do |_task, args|
    merge.call(Organization, :merge_organization, args)
  end
end
