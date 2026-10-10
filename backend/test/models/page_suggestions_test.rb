require "test_helper"
require_relative "../support/directory_builders"

class PageSuggestionsTest < ActiveSupport::TestCase
  include DirectoryBuilders

  def names(path) = PageSuggestions.new(path).matches.map { |_, record| record.name }

  test "words come from the path, without section names, numbers or short words" do
    assert_equal %w[kairos powr], PageSuggestions.new("/companies/kairos-powr").words
    assert_equal %w[vogtle units], PageSuggestions.new("/plants/plant-vogtle-units-3-4?x=1").words
    assert_nil PageSuggestions.new("/companies/42").query
  end

  test "names matching more words come first" do
    company("Kairos Power")
    company("Kairos Holdings")

    assert_equal [ "Kairos Power", "Kairos Holdings" ], names("/companies/kairos-power")
  end

  test "on a tie, the address's kind comes first, then the shorter name" do
    company("Hermes Energy")
    plant("Hermes")
    plant("Hermes Test Reactor")

    assert_equal [ "Hermes", "Hermes Test Reactor", "Hermes Energy" ], names("/plants/hermes")
    assert_equal [ "Hermes Energy", "Hermes", "Hermes Test Reactor" ], names("/companies/hermes")
  end

  test "at most three suggestions, however many names match" do
    5.times { |i| company("Fusion Works #{i}") }
    3.times { |i| plant("Fusion Site #{i}") }

    assert_equal PageSuggestions::LIMIT, PageSuggestions.new("/companies/fusion").matches.size
    assert_equal [ :company ] * 3, PageSuggestions.new("/companies/fusion").matches.map(&:first)
  end

  test "nothing is suggested for an address with no usable words" do
    company("Kairos Power")

    assert_empty PageSuggestions.new("/").matches
    assert_empty PageSuggestions.new("/zzzz-qqqq").matches
  end
end
