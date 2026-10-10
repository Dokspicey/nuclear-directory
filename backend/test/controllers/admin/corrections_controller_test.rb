require "test_helper"

# The corrections inbox (#86): reports visitors sent from the public pages.
class Admin::CorrectionsControllerTest < ActionDispatch::IntegrationTest
  def report(**attributes)
    CorrectionReport.create!(subject: "TerraPower", page_path: "/companies/#{organizations(:terrapower).slug}",
      message: "The headquarters moved to Everett.", **attributes)
  end

  test "needs a signed-in admin" do
    get admin_corrections_path
    assert_redirected_to new_session_path
  end

  test "lists open reports with the message, the page, the record and a reply address" do
    r = report(contact: "reader@example.com")
    sign_in_as users(:admin)

    get admin_corrections_path

    assert_response :success
    assert_select "#report-#{r.id}" do
      assert_select ".nd-item__claim", "TerraPower"
      assert_select ".nd-quote", /headquarters moved to Everett/
      assert_select "a[href=?]", r.page_path
      assert_select "a[href=?]", admin_fact_path(type: "Organization", id: organizations(:terrapower).id), text: "Open record"
      assert_select "a[href=?]", "mailto:reader@example.com"
    end
    assert_select ".nd-pill[aria-current=page]", /Open\s+1/
  end

  test "close as fixed, dismiss, mark as being looked at, reopen: each records who decided" do
    fixed = report
    dismissed = report
    looked_at = report
    sign_in_as users(:admin)

    post start_admin_correction_path(looked_at)
    post fix_admin_correction_path(fixed)
    post dismiss_admin_correction_path(dismissed)

    assert_equal [ "reviewed", "human:tosin" ], [ looked_at.reload.status, looked_at.decided_by ]
    assert_equal [ "closed", "fixed", "human:tosin" ], [ fixed.reload.status, fixed.resolution, fixed.decided_by ]
    assert_equal [ "closed", "dismissed" ], [ dismissed.reload.status, dismissed.resolution ]
    assert fixed.decided_at

    get admin_corrections_path(tab: "closed")
    assert_select "#report-#{fixed.id} .nd-item__why", /Fixed by human:tosin/

    post reopen_admin_correction_path(fixed, tab: "closed")
    assert_equal [ "open", nil, nil ], [ fixed.reload.status, fixed.resolution, fixed.decided_by ]
  end

  test "a report from a page that isn't a record has no record link; a stale id is an error, not a crash" do
    r = CorrectionReport.create!(subject: "Home page", page_path: "/", message: "Typo in the intro.")
    sign_in_as users(:admin)

    get admin_corrections_path
    assert_select "#report-#{r.id} a", text: "Open record", count: 0

    post fix_admin_correction_path(id: 0)
    assert_redirected_to admin_corrections_path
    assert_equal "That report no longer exists; refresh the inbox.", flash[:alert]
  end
end
