# subsidiary_of points from the child to its parent, e.g.
# Georgia Power subsidiary_of Southern Company. Decided in the seed review (#1).
class AddSubsidiaryOfRelationshipType < ActiveRecord::Migration[8.1]
  OLD_TYPES = %w[supplies invests_in funds offtake_with].freeze
  NEW_TYPES = (OLD_TYPES + %w[subsidiary_of]).freeze

  def up
    replace_types(NEW_TYPES)
  end

  def down
    replace_types(OLD_TYPES)
  end

  private
    def replace_types(types)
      remove_check_constraint :relationships, name: "relationships_relationship_type_check"
      add_check_constraint :relationships, "relationship_type IN (#{types.map { |t| "'#{t}'" }.join(", ")})",
        name: "relationships_relationship_type_check"
    end
end
