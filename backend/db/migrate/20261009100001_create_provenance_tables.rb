# Provenance and pipeline tables: where facts come from (sources, evidence)
# and the crawl → extract → match → verify workflow that produces them
# (crawl_runs, candidates). See planning/schema.md.
class CreateProvenanceTables < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.string :url, null: false
      t.string :domain
      t.string :title
      t.string :source_kind, null: false
      t.string :crawl_status, null: false, default: "pending"
      t.text :status_reason
      t.integer :http_status
      t.datetime :fetched_at
      t.string :content_sha256
      t.text :content_text
      t.timestamps

      t.index :url, unique: true
      t.index :domain
      t.index :source_kind
      t.check_constraint in_list(:crawl_status, %w[pending ok blocked needs_human]), name: "sources_crawl_status_check"
    end

    create_table :crawl_runs do |t|
      t.string :stage, null: false
      t.string :source_kind
      t.string :model
      t.string :prompt_version
      t.string :status, null: false, default: "running"
      t.jsonb :stats, null: false, default: {}
      t.text :error
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.timestamps

      t.index [ :stage, :started_at ]
      t.check_constraint in_list(:stage, %w[crawl extract match verify]), name: "crawl_runs_stage_check"
      t.check_constraint in_list(:status, %w[running succeeded failed]), name: "crawl_runs_status_check"
    end

    create_table :evidence do |t|
      t.references :subject, polymorphic: true, null: false
      t.references :source, null: false, foreign_key: true
      t.text :quote
      t.string :found_by, null: false
      t.references :crawl_run, foreign_key: true
      t.decimal :confidence, precision: 3, scale: 2
      t.datetime :created_at, null: false

      t.check_constraint in_list(:found_by, %w[crawler verifier human]), name: "evidence_found_by_check"
      t.check_constraint "confidence IS NULL OR (confidence >= 0 AND confidence <= 1)", name: "evidence_confidence_check"
    end

    create_table :candidates do |t|
      t.references :source, null: false, foreign_key: true
      t.references :crawl_run, foreign_key: true
      t.string :kind, null: false
      t.jsonb :payload, null: false, default: {}
      t.text :quote
      t.string :status, null: false, default: "new"
      t.references :subject, polymorphic: true
      t.text :notes
      t.timestamps

      t.index [ :status, :kind ]
      t.check_constraint in_list(:kind, %w[organization organization_alias organization_role organization_technology
        facility relationship facility_relationship]), name: "candidates_kind_check"
      t.check_constraint in_list(:status, %w[new matched merged rejected needs_review]), name: "candidates_status_check"
    end
  end

  private
    def in_list(column, values)
      "#{column} IN (#{values.map { |v| "'#{v}'" }.join(", ")})"
    end
end
