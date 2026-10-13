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

  # EIA's Entity Name is the utility that reports a generator, not the
  # plant's operator (#227). Published "operates" links whose only evidence
  # is EIA's are listed. With BY=human:<name> APPLY=1, the ones whose plant
  # has a published operator from NRC's list are unpublished,
  # each recorded with who did it and why; the rest are left for a person.
  desc "List the published operates links only EIA backs; BY=human:<name> APPLY=1 unpublishes those another operator contradicts (#227)"
  task retire_eia_operators: :environment do
    by = ENV["BY"].to_s
    apply = ENV["APPLY"] == "1"
    abort "APPLY=1 needs BY=human:<name>" if apply && !by.match?(/\Ahuman:\S+\z/)

    backed_by = ->(kind) { Evidence.joins(:source).where(subject_type: "FacilityRelationship", sources: { source_kind: kind }).select(:subject_id) }
    other = Evidence.joins(:source).where(subject_type: "FacilityRelationship").where.not(sources: { source_kind: "eia_generators" }).select(:subject_id)
    links = FacilityRelationship.published.where(relationship_type: "operates", id: backed_by["eia_generators"]).where.not(id: other)
      .includes(:organization, :facility)
    reason = "EIA's Entity Name is the utility that reports the generator, not the plant's operator (#227)"

    found = links.map do |link|
      site = link.facility.parent || link.facility
      plant = [ site.id, *Facility.where(parent_id: site.id).ids ]
      # Only a published operator that NRC's list backs counts against EIA's.
      operators = FacilityRelationship.published.where(relationship_type: "operates", facility_id: plant, id: backed_by["nrc_reactor_list"])
        .where.not(id: link.id).where.not(organization_id: link.organization_id).includes(:organization).map { |o| o.organization.name }.uniq
      line = "FacilityRelationship #{link.id}: #{link.organization.name} operates #{link.facility.name}"
      if operators.empty?
        "#{line} (no published NRC operator; check by hand)"
      elsif apply
        result = DataQuality::Review.unpublish(type: "FacilityRelationship", id: link.id, by:, reason:)
        "#{line} -> #{result.errors.empty? ? 'unpublished' : "not unpublished: #{result.errors.join('; ')}"} (#{operators.join(', ')})"
      else
        "#{line} -> would unpublish (#{operators.join(', ')})"
      end
    end
    puts found.any? ? found : "No published operates links rest on EIA alone."
  end
end
