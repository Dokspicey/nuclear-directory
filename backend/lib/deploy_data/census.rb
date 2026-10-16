module DeployData
  # Counts read before and after the data step, so the report shows what it
  # did and a rehearsal on a restored backup can be compared line for line.
  module Census
    # Tables the seed and data migrations write.
    TABLES = %w[organizations organization_aliases organization_roles organization_technologies relationships
      facilities facility_aliases facility_relationships former_slugs evidence sources roles technologies].freeze

    module_function

    def rows
      connection = ActiveRecord::Base.connection
      TABLES.index_with { |table| connection.select_value("SELECT count(*) FROM #{connection.quote_table_name(table)}").to_i }
    end

    # What the public sees.
    def public_totals
      {
        "companies" => Organization.published.count,
        "plants and sites" => DirectoryListing.new.public_sites.count,
        "reactors" => Facility.published.where.not(parent_id: nil).count,
        "facts" => [ OrganizationRole, OrganizationTechnology, Relationship, FacilityRelationship ].sum { |model| model.published.count },
        "quotes" => Evidence.count,
        "sources" => Source.count
      }
    end

    def last_event_id = VerificationEvent.maximum(:id).to_i
  end
end
