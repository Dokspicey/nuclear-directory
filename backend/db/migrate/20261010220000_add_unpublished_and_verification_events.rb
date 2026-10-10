# Unpublishing (Tosin's decision): a human can take a verified fact off the
# public site with its own status, "unpublished", which records who and when
# and which the pipeline treats as a human decision. Every change of
# verification is kept in verification_events (who, when, from -> to, why).
class AddUnpublishedAndVerificationEvents < ActiveRecord::Migration[8.1]
  FACT_TABLES = %i[organizations organization_roles organization_technologies facilities relationships
    facility_relationships].freeze
  OLD = %w[pending verified rejected].freeze
  NEW = %w[pending verified rejected unpublished].freeze

  def up
    FACT_TABLES.each { |table| replace_check(table, NEW) }

    create_table :verification_events do |t|
      t.references :subject, polymorphic: true, null: false, index: false
      t.string :from_status
      t.string :to_status, null: false
      t.string :by
      t.text :reason
      # e.g. { "candidate_id" => 12, "crawl_run_id" => 4 } for an approval; no
      # foreign keys, since candidates belong to the data quality module.
      t.jsonb :context, null: false, default: {}
      t.datetime :created_at, null: false

      t.index [ :subject_type, :subject_id, :created_at ], name: "index_verification_events_on_subject_and_time"
    end
  end

  def down
    drop_table :verification_events
    FACT_TABLES.each { |table| replace_check(table, OLD) }
  end

  private
    def replace_check(table, statuses)
      name = "#{table}_verification_status_check"
      remove_check_constraint table, name: name
      add_check_constraint table, "verification_status IN (#{statuses.map { |s| "'#{s}'" }.join(', ')})", name: name
    end
end
