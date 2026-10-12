# A slug a record used to have (#143): renamed records, and companies merged
# into another, keep their old addresses working by redirecting to the
# record's current page.
class FormerSlug < ApplicationRecord
  belongs_to :sluggable, polymorphic: true

  validates :slug, presence: true, uniqueness: { scope: :sluggable_type }
end
