require "test_helper"

class DataQuality::Plugins::NrcReactorList::PageTest < ActiveSupport::TestCase
  Page = DataQuality::Plugins::NrcReactorList::Page
  StatusFile = DataQuality::Plugins::NrcReactorList::StatusFile

  test "reads every unit from the real NRC table" do
    units = Page.units(file_fixture("nrc/list-power-reactor-units.html").read)

    assert_equal 95, units.size
    assert_equal 95, units.map(&:nrc_docket).uniq.size
    assert_equal Page::Unit.new(
      name: "Arkansas Nuclear 1", nrc_docket: "05000313", license_number: "DPR-51", reactor_type: "PWR",
      location: "6 miles WNW of Russellville, AR", state: "AR", owner_operator: "Entergy Nuclear Operations, Inc.",
      nrc_region: "4", nrc_path: "/facilities-safety/facility-finder/reactors/ano1"
    ), units.first
    assert units.all? { |unit| unit.state.match?(/\A[A-Z]{2}\z/) }, "every location ends in a state"
    assert_equal %w[BWR PWR], units.map(&:reactor_type).uniq.sort
  end

  test "renders the table as one plain line per row, for the extractor model" do
    lines = Page.lines(file_fixture("nrc/list-power-reactor-units.html").read)

    assert_equal 96, lines.size, "the header plus 95 units"
    assert_equal "Plant Name | Docket Number | License Number | Reactor | Type | Location | Owner/Operator | NRC Region", lines.first
    assert_includes lines, "Vogtle 3 | 05200025 | NPF-91 | PWR | 26 miles SE of Augusta, GA | Southern Nuclear Operating Co. | 2"
  end

  test "no table, no units" do
    assert_empty Page.units("<html><body><table><tr><td>menu</td></tr></table></body></html>")
    assert_empty Page.units(nil)
  end

  test "the real status file's latest day has the 95 units" do
    units = StatusFile.latest_units(file_fixture("nrc/PowerReactorStatusForLast365Days.txt").read)

    assert_equal 95, units.size
    assert_includes units, "D.C. Cook 1"
    assert_includes units, "Vogtle 4"
  end

  test "the status file's latest units" do
    text = "ReportDt|Unit|Power\n10/8/2026 12:00:00 AM|Old Unit|0\n10/9/2026 12:00:00 AM|Byron 1|100\n" \
      "10/9/2026 12:00:00 AM|Byron 2|98\nnot a line\n"

    assert_equal [ "Byron 1", "Byron 2" ], StatusFile.latest_units(text)
    assert_empty StatusFile.latest_units("")
  end
end
