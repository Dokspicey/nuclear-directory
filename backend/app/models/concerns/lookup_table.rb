# Lookup tables that grow as we learn (roles, technologies). Rows are keyed
# by a stable snake_case key and seeded from db/seeds.rb.
module LookupTable
  extend ActiveSupport::Concern

  included do
    include Hierarchical

    validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
    validates :name, presence: true
  end
end
