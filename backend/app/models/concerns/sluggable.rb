# Fills in a URL slug from the name when none is given, with "-2", "-3"...
# when that slug is taken (an EIA site and an NRC unit can share a name).
# A slug given explicitly must be free. Slugs are stable: renaming a record
# doesn't change its slug.
module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation { self.slug = free_slug(name.parameterize) if slug.blank? && name.present? }

    validates :slug, presence: true, uniqueness: true
  end

  def to_param
    slug
  end

  private
    def free_slug(base)
      taken = self.class.where.not(id:).where("slug = ? OR slug LIKE ?", base, "#{base}-%").pluck(:slug).to_set
      return base unless taken.include?(base)

      (2..).lazy.map { |n| "#{base}-#{n}" }.find { |slug| !taken.include?(slug) }
    end
end
