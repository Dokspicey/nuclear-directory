# Fills in a URL slug from the name when none is given. Slugs are stable:
# renaming a record doesn't change its slug.
module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation { self.slug = name.parameterize if slug.blank? && name.present? }

    validates :slug, presence: true, uniqueness: true
  end

  def to_param
    slug
  end
end
