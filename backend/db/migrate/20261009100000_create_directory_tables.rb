# Directory tables: organizations, facilities, the lookup tables (roles,
# technologies) and the links between them. See planning/schema.md.
#
# Enum-like columns are strings guarded by check constraints, so adding a
# value is a one-line migration. Every fact table gets the same verification
# columns (see Verifiable).
class CreateDirectoryTables < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :legal_name
      t.string :website
      t.string :domain
      t.text :description
      t.string :hq_city
      t.string :hq_state
      t.string :country_code, limit: 2, null: false, default: "US"
      t.integer :founded_year
      t.string :status, null: false, default: "active"
      verification_columns(t)
      t.timestamps

      t.index :slug, unique: true
      t.index :domain, unique: true
      t.check_constraint in_list(:status, %w[active acquired defunct]), name: "organizations_status_check"
      verification_checks(t, :organizations)
    end

    create_table :organization_aliases do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :alias, null: false
      t.string :normalized_alias, null: false
      t.timestamps

      t.index :normalized_alias, unique: true
    end

    %i[roles technologies].each do |table|
      create_table table do |t|
        t.string :key, null: false
        t.string :name, null: false
        t.references :parent, foreign_key: { to_table: table }
        t.text :description
        t.timestamps

        t.index :key, unique: true
      end
    end

    { organization_roles: :role, organization_technologies: :technology }.each do |table, lookup|
      create_table table do |t|
        t.references :organization, null: false, foreign_key: true
        t.references lookup, null: false, foreign_key: true
        verification_columns(t)
        t.timestamps

        t.index [ :organization_id, :"#{lookup}_id" ], unique: true
        verification_checks(t, table)
      end
    end

    create_table :facilities do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.references :parent, foreign_key: { to_table: :facilities }
      t.string :facility_type, null: false
      t.string :status, null: false
      t.references :technology, foreign_key: true
      t.string :reactor_type
      t.decimal :capacity_mw, precision: 8, scale: 2
      t.string :nrc_docket
      t.string :city
      t.string :state
      t.string :country_code, limit: 2, null: false, default: "US"
      t.decimal :latitude, precision: 9, scale: 6
      t.decimal :longitude, precision: 9, scale: 6
      verification_columns(t)
      t.timestamps

      t.index :slug, unique: true
      t.index :nrc_docket, unique: true, where: "nrc_docket IS NOT NULL"
      t.check_constraint in_list(:facility_type, %w[power_reactor research_reactor fuel_facility enrichment fusion_facility other]),
        name: "facilities_facility_type_check"
      t.check_constraint in_list(:status, %w[operating under_construction planned shut_down decommissioning]),
        name: "facilities_status_check"
      verification_checks(t, :facilities)
    end

    create_table :relationships do |t|
      t.references :from_organization, null: false, foreign_key: { to_table: :organizations }
      t.references :to_organization, null: false, foreign_key: { to_table: :organizations }
      t.string :relationship_type, null: false
      t.text :description
      t.date :started_on
      t.date :ended_on
      verification_columns(t)
      t.timestamps

      t.index [ :from_organization_id, :to_organization_id, :relationship_type ], unique: true,
        name: "index_relationships_uniqueness"
      t.check_constraint "from_organization_id <> to_organization_id", name: "relationships_not_self_check"
      t.check_constraint in_list(:relationship_type, %w[supplies invests_in funds offtake_with]),
        name: "relationships_relationship_type_check"
      verification_checks(t, :relationships)
    end

    create_table :facility_relationships do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :facility, null: false, foreign_key: true
      t.string :relationship_type, null: false
      t.decimal :ownership_pct, precision: 5, scale: 2
      t.date :started_on
      t.date :ended_on
      verification_columns(t)
      t.timestamps

      t.index [ :organization_id, :facility_id, :relationship_type ], unique: true,
        name: "index_facility_relationships_uniqueness"
      t.check_constraint in_list(:relationship_type, %w[owns operates vendor_for offtakes_from]),
        name: "facility_relationships_relationship_type_check"
      t.check_constraint "ownership_pct IS NULL OR (ownership_pct >= 0 AND ownership_pct <= 100)",
        name: "facility_relationships_ownership_pct_check"
      verification_checks(t, :facility_relationships)
    end
  end

  private
    def verification_columns(t)
      t.decimal :confidence, precision: 3, scale: 2
      t.string :verification_status, null: false, default: "pending"
      t.datetime :verified_at
      t.string :verified_by
      t.index :verification_status
    end

    def verification_checks(t, table)
      t.check_constraint "confidence IS NULL OR (confidence >= 0 AND confidence <= 1)", name: "#{table}_confidence_check"
      t.check_constraint in_list(:verification_status, %w[pending verified rejected]), name: "#{table}_verification_status_check"
    end

    def in_list(column, values)
      "#{column} IN (#{values.map { |v| "'#{v}'" }.join(", ")})"
    end
end
