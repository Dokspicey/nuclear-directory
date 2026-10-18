require "application_system_test_case"
require_relative "../support/directory_builders"

# Tosin's rule (DESIGN.md, #365): text in a box, chip, button or list row
# never wraps or hyphenates, and a source number never starts a line on its
# own. Checked with the live site's problem cases at phone widths, since
# iOS renders a little wider than Chrome.
class NoWrapTest < ApplicationSystemTestCase
  include DirectoryBuilders

  # Capybara returns the script's value, so the file's comment lines go.
  AUDIT = File.readlines(File.expand_path("../support/no_wrap_audit.js", __dir__)).reject { |line| line.start_with?("//") }.join

  setup do
    services = role("reactor_services")
    utility = role("utility")
    @parent = cite!(company("Bernhard Capital Partners Management"))
    @allied = cite!(company("Allied Power Services Holdings", roles: [ services ], website: "https://www.alliedpowerservices.com",
      city: "Baton Rouge", state: "LA", description: "Company that provides maintenance, modification and staffing services to power plants, including nuclear plants."))
    cite!(link(@allied, "subsidiary_of", @parent))
    @plant = cite!(plant("Calvert Cliffs Nuclear Power Plant", facility_type: "power_reactor", status: "operating", city: "Lusby", state: "MD"))
    cite!(plant("Calvert Cliffs Unit 1", parent: @plant, status: "operating", reactor_type: "PWR", capacity_mw: 884))
    cite!(plant("Calvert Cliffs Unit 2", parent: @plant, status: "operating", reactor_type: "PWR", capacity_mw: 862))
    [ "Constellation Energy Generation", "Oglethorpe Power Corporation", "Southern Nuclear Operating Co., Inc.", "Municipal Electric Authority of Georgia" ]
      .each { |name| cite!(link(cite!(company(name, roles: [ utility ])), "owns", @plant)) }
    cite!(company("Metropolis Works Uranium Conversion Facility Operator LLC", roles: [ role("fuel") ],
      description: "Company that supplies uranium hexafluoride conversion services to nuclear power plants worldwide."))
  end

  PAGES = ->(test) { [ "/", "/companies", "/companies?category=services", "/companies?category=plants",
    "/companies/#{test.instance_variable_get(:@allied).slug}", "/plants/#{test.instance_variable_get(:@plant).slug}" ] }

  [ [ 360, 800 ], [ 390, 844 ] ].each do |width, height|
    test "nothing wraps and no source number stands alone at #{width}" do
      resize_viewport(width, height)
      problems = PAGES.call(self).flat_map do |path|
        visit path
        page.evaluate_script(AUDIT).map { |problem| "#{path}: #{problem}" }
      end

      assert_empty problems, problems.join("\n")
    end
  end
end
