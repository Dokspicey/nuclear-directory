# Whether the match stage created the candidate's subject (proposed a new
# record) rather than attaching it to one that already existed. A rejected
# proposal is retired; a rejected attachment leaves the existing record alone.
class AddProposedSubjectToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :candidates, :proposed_subject, :boolean, null: false, default: false
  end
end
