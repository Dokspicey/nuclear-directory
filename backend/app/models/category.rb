# The eight groups visitors browse by on the home page and the directory.
# A category is presentation only: a saved filter over roles, a technology
# or plants. The mapping is documented in DESIGN.md under "Categories".
#
#   Category.all          # in display order
#   Category.find("fuel") # => Category or nil
Category = Data.define(:key, :name, :role_keys, :technology_key, :plants, :investors) do
  def self.all = self::ALL
  def self.find(key) = self::ALL.find { |category| category.key == key.to_s }

  def initialize(key:, name:, role_keys: [], technology_key: nil, plants: false, investors: false)
    super
  end

  def to_param = key
end

class Category
  # Child roles (enrichment, fabrication under fuel) are matched through their parent.
  # Investors also includes any company with a verified invests_in relationship.
  ALL = [
    new(key: "fuel", name: "Fuel suppliers", role_keys: %w[fuel]),
    new(key: "reactor-developers", name: "Reactor developers", role_keys: %w[reactor_vendor]),
    new(key: "power-plants", name: "Power plants", plants: true),
    new(key: "utilities", name: "Utilities and operators", role_keys: %w[utility operator]),
    new(key: "services", name: "Repair and services", role_keys: %w[reactor_services]),
    new(key: "power-buyers", name: "Power buyers", role_keys: %w[data_center_offtaker]),
    new(key: "investors", name: "Investors", role_keys: %w[venture_capital], investors: true),
    new(key: "fusion", name: "Fusion", technology_key: "fusion")
  ].freeze
end
