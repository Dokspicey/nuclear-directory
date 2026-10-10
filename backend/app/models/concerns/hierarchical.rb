# A record that can have sub-types of the same kind via parent_id,
# e.g. the smr technology under fission, or a reactor unit under its site.
module Hierarchical
  extend ActiveSupport::Concern

  included do
    belongs_to :parent, class_name: name, optional: true, inverse_of: :children
    has_many :children, class_name: name, foreign_key: :parent_id, inverse_of: :parent, dependent: :restrict_with_error

    validate :parent_is_not_self
  end

  private
    def parent_is_not_self
      errors.add(:parent, "can't be itself") if parent_id.present? && parent_id == id
    end
end
