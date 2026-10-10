# New types decided in the seed review (#1):
# - subsidiary_of relationship, pointing from the child to its parent, e.g.
#   Georgia Power subsidiary_of Southern Company
# - uranium_mine and mill facility types, for the front of the fuel chain
class AddRelationshipAndFacilityTypes < ActiveRecord::Migration[8.1]
  OLD_RELATIONSHIP_TYPES = %w[supplies invests_in funds offtake_with].freeze
  NEW_RELATIONSHIP_TYPES = (OLD_RELATIONSHIP_TYPES + %w[subsidiary_of]).freeze

  OLD_FACILITY_TYPES = %w[power_reactor research_reactor fuel_facility enrichment fusion_facility other].freeze
  NEW_FACILITY_TYPES = (OLD_FACILITY_TYPES + %w[uranium_mine mill]).freeze

  def up
    replace_check(:relationships, :relationship_type, NEW_RELATIONSHIP_TYPES)
    replace_check(:facilities, :facility_type, NEW_FACILITY_TYPES)
  end

  def down
    replace_check(:relationships, :relationship_type, OLD_RELATIONSHIP_TYPES)
    replace_check(:facilities, :facility_type, OLD_FACILITY_TYPES)
  end

  private
    def replace_check(table, column, values)
      name = "#{table}_#{column}_check"
      remove_check_constraint table, name: name
      add_check_constraint table, "#{column} IN (#{values.map { |v| "'#{v}'" }.join(", ")})", name: name
    end
end
