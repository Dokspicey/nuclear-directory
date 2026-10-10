# Renders every design system component with real markup, so a screen can be
# built by copying from /design. Only routed in development and test.
#
# The "Page parts" section renders the shared partials with MOCK records:
# built in memory, never saved, never in seeds or production. They show both
# states every page must handle: a field present, and the same field missing.
class DesignSystemController < ApplicationController
  def show
    @mock = mock_records
  end

  private
    def mock_records
      sources = [
        Source.new(url: "https://kairospower.com/external_updates/google-and-kairos-power-partner-to-deploy-500-mw-of-clean-electricity-generation/",
          domain: "kairospower.com", title: "Google and Kairos Power partner to deploy 500 MW of clean electricity generation",
          published_on: Date.new(2024, 10, 14)),
        Source.new(url: "https://www.energy.gov/node/4845535", domain: "energy.gov", published_on: Date.new(2024, 10, 3))
      ]

      {
        sources: sources,
        company: Organization.new(name: "Kairos Power", slug: "kairos-power", hq_city: "Alameda", hq_state: "CA",
          description: "Develops the KP-FHR, a fluoride salt-cooled, high-temperature reactor."),
        company_sparse: Organization.new(name: "Lowercarbon Capital", slug: "lowercarbon-capital"),
        plant: Facility.new(name: "Plant Vogtle", slug: "plant-vogtle", verification_status: "verified", facility_type: "power_reactor", status: "operating",
          city: "Waynesboro", state: "GA"),
        # Plant Vogtle is the site; its four reactor units sit under it as children.
        plant_sparse: Facility.new(name: "Hermes 2", slug: "hermes-2"),
        verified_at: Time.zone.parse("2026-10-09 12:00")
      }
    end
end
