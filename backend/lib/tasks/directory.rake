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
end
