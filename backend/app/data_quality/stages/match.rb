# Links new candidates to records that already exist in the directory, so
# verify updates them instead of creating duplicates. Unmatched candidates
# stay new, which means "propose a new record". Shared by all plug-ins.
class DataQuality::Stages::Match < DataQuality::Stage
  private
    def perform(run)
      stats = { "candidates" => 0, "matched" => 0 }

      candidates.status_new.find_each do |candidate|
        stats["candidates"] += 1
        next unless (ref = directory.find(candidate.kind, candidate.payload))

        candidate.update!(status: "matched", subject_type: ref.type, subject_id: ref.id)
        stats["matched"] += 1
      end

      stats
    end
end
