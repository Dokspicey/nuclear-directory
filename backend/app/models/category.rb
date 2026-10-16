# The eight groups visitors browse by on the home page and the directory.
# A category is presentation only: a saved filter over roles, a technology
# or plants. The mapping is documented in DESIGN.md under "Categories".
#
#   Category.all          # in display order
#   Category.find("fuel") # => Category or nil
#
# name is the short heading; title is the page's <title>, in the words people
# search with (#290); about is what the count in the description counts:
# "11 companies developing nuclear reactors in the US".
Category = Data.define(:key, :name, :title, :about, :role_keys, :technology_key, :plants, :investors) do
  def self.all = self::ALL
  def self.find(key) = self::ALL.find { |category| category.key == key.to_s }

  def initialize(key:, name:, title:, about:, role_keys: [], technology_key: nil, plants: false, investors: false)
    super
  end

  def to_param = key

  # One plain sentence with the count, for the meta and link-preview
  # description: "11 companies developing nuclear reactors in the US,
  # including small modular reactors." It says what's on the page, not how
  # it's sourced (Tosin, #249). With fewer than two, the same words uncounted.
  def description(count)
    "#{count.to_i > 1 ? "#{count} #{about}" : about.upcase_first}."
  end
end

class Category
  # Child roles (enrichment, fabrication under fuel) are matched through their parent.
  # Investors also includes any company with a verified invests_in relationship.
  ALL = [
    new(key: "fuel", name: "Fuel suppliers", role_keys: %w[fuel],
      title: "Uranium and nuclear fuel suppliers in the US",
      about: "companies supplying uranium and nuclear fuel in the US"),
    new(key: "reactor-developers", name: "Reactor developers", role_keys: %w[reactor_vendor],
      title: "Advanced reactor and SMR developers in the US",
      about: "companies developing nuclear reactors in the US, including small modular reactors"),
    # Every kind of site: power plants, test reactors, fuel plants, mines (VOICE.md).
    new(key: "plants", name: "Plants and sites", plants: true,
      title: "US nuclear power plants and sites: owners and operators",
      about: "US nuclear power plants, test reactors, fuel plants and mines, with their owners and operators"),
    new(key: "utilities", name: "Utilities and operators", role_keys: %w[utility operator],
      title: "US nuclear utilities and plant operators",
      about: "utilities and plant operators in the US nuclear industry"),
    new(key: "services", name: "Repair and services", role_keys: %w[reactor_services],
      title: "Nuclear plant repair and services companies in the US",
      about: "companies that repair and service US nuclear plants"),
    new(key: "power-buyers", name: "Power buyers", role_keys: %w[data_center_offtaker],
      title: "Companies buying nuclear power in the US",
      about: "companies buying nuclear power in the US, such as data center operators"),
    new(key: "investors", name: "Investors", role_keys: %w[venture_capital], investors: true,
      title: "Investors in US nuclear and fusion companies",
      about: "investors in US nuclear and fusion companies"),
    new(key: "fusion", name: "Fusion", technology_key: "fusion",
      title: "Fusion energy companies in the US",
      about: "fusion energy companies in the US")
  ].freeze
end
