require "test_helper"
require "rake"

# Change status (#316): a plant's or unit's status from its page, with
# evidence, through the same code as `directory:set_status`.
class Admin::StatusChangesControllerTest < ActionDispatch::IntegrationTest
  VERIFIED = { verification_status: "verified", verified_by: "agent:verify" }.freeze
  NRC_LINE = "10/14/2026 12:00:00 AM|Palisades|0".freeze

  setup do
    sign_in_as users(:admin)
    @file = Source.create!(url: "https://www.nrc.gov/status-#{SecureRandom.hex(3)}.txt", source_kind: "nrc_power_status", fetched_at: Time.current,
      content_text: "ReportDt|Unit|Power\n10/13/2026 12:00:00 AM|Palisades|0\n#{NRC_LINE}\n")
    @site = Facility.create!(name: "Palisades", facility_type: "power_reactor", status: "operating", **VERIFIED)
    @unit = Facility.create!(name: "Palisades", parent: @site, nrc_docket: "05000255", status: "operating", **VERIFIED)
  end

  def preview(**params) = get admin_facility_status_path(id: @site.id), params: { status: "not_operating", unit_ids: [ @unit.id ], **params }
  def confirm(**params) = patch admin_facility_status_path(id: @site.id), params: { status: "not_operating", evidence: "nrc", unit_ids: [ @unit.id ], **params }

  test "the Record and a unit's fact page offer Change status; Edit no longer changes it" do
    get admin_record_path(type: "Facility", id: @site.id)
    assert_select "a.nd-btn[href=?]", admin_facility_status_path(id: @site.id), "Change status"
    get admin_fact_path(type: "Facility", id: @unit.id)
    assert_select "a.nd-btn[href=?]", admin_facility_status_path(id: @unit.id), "Change status"
    get admin_record_edit_path(type: "Facility", id: @site.id)
    assert_select "input[name='values[status]']", false
  end

  test "the form offers NRC's newest line for the plant, and the site's units, ticked" do
    get admin_facility_status_path(id: @site.id)

    assert_response :success
    assert_select "h1", "Change status"
    assert_select "input[name=evidence][value=nrc][checked]"
    assert_select "label", /#{Regexp.escape(NRC_LINE)}/
    assert_select "input[name='unit_ids[]'][value=?][checked]", @unit.id.to_s
    assert_select "button", { text: "Change status", count: 0 }, "nothing to confirm before a preview"
  end

  test "the preview says what changes and changes nothing" do
    before = Facility.published.where(parent_id: nil, status: "operating").count
    assert_no_difference(-> { VerificationEvent.count }) { preview(evidence: "nrc") }

    assert_response :success
    assert_select "#preview-heading", "What changes"
    assert_select "li", { text: "Palisades: Operating → Not operating", count: 2 }
    assert_select "p", /operating plants go from #{before} to #{before - 1}/
    assert_select "form[method=post] button", "Change status"
    assert @site.reload.operating?
  end

  test "confirming writes the status as the person, with NRC's line as evidence, for good" do
    confirm(note: "Shut since 2022")

    assert_redirected_to admin_record_path(type: "Facility", id: @site.id)
    assert_equal "Status changed to not operating for 2 records.", flash[:notice]
    [ @site, @unit ].each do |facility|
      facility.reload
      assert facility.not_operating?
      assert_equal users(:admin).actor, facility.verified_by
      assert_equal [ NRC_LINE ], facility.evidence.where(source: @file).pluck(:quote)
      event = VerificationEvent.where(subject: facility).order(:id).last
      assert_equal "NRC's 365-day power status file: #{NRC_LINE}. Shut since 2022", event.reason
    end

    result = Directory::FactWriter.write(:facility, { id: @unit.id, status: "operating" }, protect_human_verified: true)
    assert result.conflicts.present?, "a crawler's value is overruled"
    assert @unit.reload.not_operating?
  end

  test "a link and a quote become the evidence, the link saved as a source" do
    confirm(evidence: "link", url: "https://example.com/palisades", quote: "Palisades is not operating.", unit_ids: [])

    assert @site.reload.not_operating?
    assert @unit.reload.operating?, "an unticked unit is left as it was"
    assert_equal [ "Palisades is not operating." ], @site.evidence.joins(:source).where(sources: { url: "https://example.com/palisades" }).pluck(:quote)
  end

  test "a note alone stands for what a person knows" do
    confirm(evidence: "note", note: "Told by the operator on a site visit")

    assert @site.reload.not_operating?
    assert_equal "Told by the operator on a site visit", VerificationEvent.where(subject: @site).order(:id).last.reason
  end

  test "missing evidence is refused, and nothing changes" do
    confirm(evidence: "link", url: "", quote: "")
    assert_response :unprocessable_content
    assert_select ".nd-alert li", "Enter a link to a public source, starting with https://"
    assert_select ".nd-alert li", "Copy the sentence from the source that states the status"

    confirm(evidence: "link", url: "javascript:alert(1)", quote: "q")
    assert_response :unprocessable_content
    assert_select ".nd-alert li", "Enter a link to a public source, starting with https://"

    confirm(evidence: "note", note: " ")
    assert_select ".nd-alert li", "Say how you know, in the note"
    assert @site.reload.operating?
  end

  test "a unit from another plant can't ride along" do
    other = Facility.create!(name: "Other Plant", status: "operating", **VERIFIED)
    other_unit = Facility.create!(name: "Other 1", parent: other, status: "operating", **VERIFIED)
    confirm(unit_ids: [ @unit.id, other_unit.id ])

    assert other_unit.reload.operating?
    assert @unit.reload.not_operating?
  end

  test "the admin action and the rake task give the same result" do
    # A second Palisades, set from the console.
    site = Facility.create!(name: "Palisades", facility_type: "power_reactor", status: "operating", **VERIFIED)
    unit = Facility.create!(name: "Palisades", parent: site, status: "operating", **VERIFIED)
    confirm
    Rails.application.load_tasks unless Rake::Task.task_defined?("directory:set_status")
    ENV["BY"] = users(:admin).actor
    ENV["APPLY"] = "1"
    capture_io { Rake::Task["directory:set_status"].execute(Rake::TaskArguments.new(%i[status ids], [ "not_operating", "#{site.id} #{unit.id}" ])) }

    state = ->(facility) { facility.reload.slice(:status, :verification_status, :verified_by).merge(quotes: facility.evidence.pluck(:quote)) }
    assert_equal [ @site, @unit ].map(&state), [ site, unit ].map(&state)
    last_reason = ->(facility) { VerificationEvent.where(subject: facility).order(:id).last.reason }
    assert_equal last_reason.(@unit), last_reason.(unit)
  ensure
    ENV.delete("BY")
    ENV.delete("APPLY")
  end
end
