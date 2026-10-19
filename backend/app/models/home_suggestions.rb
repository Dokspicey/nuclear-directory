# The searches suggested under the home page's search box. Change the list
# here; nothing else needs to. A suggestion is a search (query) or a
# category's list (category, a Category key). Searches from these links are
# tracked with source "suggestion", so they don't look like typed demand.
module HomeSuggestions
  Suggestion = Data.define(:label, :query, :category) do
    def initialize(label:, query: nil, category: nil) = super
  end

  ALL = [
    Suggestion.new(label: "HALEU", query: "HALEU"),
    Suggestion.new(label: "SMR", query: "SMR"),
    Suggestion.new(label: "Plant Vogtle", query: "Vogtle"),
    Suggestion.new(label: "Power deals", category: "power-buyers")
  ].freeze
end
