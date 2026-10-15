# #240: a source that still says what a decided fact records re-confirms it
# instead of queueing it for review again.
# - candidates.status "confirmed": closed by the pipeline, identical to the
#   decided fact (or a duplicate of one already waiting); nothing written.
# - evidence.last_confirmed_at / confirmed_sha256: when that source last said
#   it, and the rows it said it in. Updated quietly, never audited.
# - sources.extracted_rows_sha256: the rows extract last read, so a page whose
#   table didn't change (only its date stamp) isn't extracted again.
class ReconfirmIdenticalFacts < ActiveRecord::Migration[8.1]
  STATUSES = %w[new matched merged rejected needs_review].freeze

  def up
    remove_check_constraint :candidates, name: "candidates_status_check"
    add_check_constraint :candidates, "status IN (#{(STATUSES + %w[confirmed]).map { |s| "'#{s}'" }.join(', ')})",
      name: "candidates_status_check"
    add_column :evidence, :last_confirmed_at, :datetime
    add_column :evidence, :confirmed_sha256, :string
    add_column :sources, :extracted_rows_sha256, :string
  end

  def down
    execute "UPDATE candidates SET status = 'merged' WHERE status = 'confirmed'"
    remove_check_constraint :candidates, name: "candidates_status_check"
    add_check_constraint :candidates, "status IN (#{STATUSES.map { |s| "'#{s}'" }.join(', ')})", name: "candidates_status_check"
    remove_column :evidence, :last_confirmed_at
    remove_column :evidence, :confirmed_sha256
    remove_column :sources, :extracted_rows_sha256
  end
end
