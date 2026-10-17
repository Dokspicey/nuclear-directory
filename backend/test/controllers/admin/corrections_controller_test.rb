require "test_helper"

# The corrections inbox (#86): reports visitors sent from the public pages.
class Admin::CorrectionsControllerTest < ActionDispatch::IntegrationTest
  def report(**attributes)
    CorrectionReport.create!(subject: "TerraPower", page_path: "/companies/#{organizations(:terrapower).slug}",
      message: "The headquarters moved to Everett.", **attributes)
  end

  test "the email's link finds a report where it is now: its tab and page, at its row (#317)" do
    sign_in_as users(:admin)
    stub_const(Admin::CorrectionsController, :PAGE, 2) do
      first, second, third = 3.times.map { |n| travel_to(n.hours.ago - 1.day) { report } }.reverse

      get admin_corrections_path(report: third.id)
      assert_redirected_to admin_corrections_path(page: 2, anchor: "report-#{third.id}")

      get admin_corrections_path(report: first.id)
      assert_redirected_to admin_corrections_path(anchor: "report-#{first.id}")

      second.close!("fixed", by: "human:tosin")
      get admin_corrections_path(report: second.id)
      assert_redirected_to admin_corrections_path(tab: "closed", anchor: "report-#{second.id}")
    end
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
      assert_select ".type-subject", "TerraPower"
      assert_select ".type-kicker", /New/
      assert_select "button", "Fix"
      assert_select ".nd-quote", /headquarters moved to Everett/
      assert_select "a[href=?]", r.page_path
      assert_select "a[href=?]", admin_fact_path(type: "Organization", id: organizations(:terrapower).id), text: "Open record"
      assert_select "a[href^=?][href*=?]", "mailto:reader@example.com?", "subject=Your%20correction%20on%20Nuclear%20Directory", text: "Reply to reader@example.com"
    end
    assert_select ".nd-fchip[aria-current=page]", /Open\s+1/
    assert_select "h1", /Correction requests\s+1/
    assert_select ".nd-shell__nav a[title=?]", "From visitors", /Correction requests\s+1/
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
    assert_select "#report-#{fixed.id} .type-kicker", /Fixed · tosin ·/
    assert_select "#report-#{fixed.id} button", "Reopen"

    post reopen_admin_correction_path(fixed, tab: "closed")
    assert_equal [ "open", nil, nil ], [ fixed.reload.status, fixed.resolution, fixed.decided_by ]
  end

  test "a visitor's markup is shown as text, and a crafted address can't add recipients to the reply" do
    r = report(message: 'See <a href="https://evil.example">this</a>', contact: "reader@example.com?bcc=attacker%40evil.com&x=x")
    sign_in_as users(:admin)

    get admin_corrections_path

    assert_select "#report-#{r.id}" do
      assert_select ".nd-quote a", 0
      assert_select ".nd-quote", /<a href=/
      reply = css_select("a[href^='mailto:']").first["href"]
      assert_match %r{\Amailto:reader@example.com%3Fbcc%3Dattacker%2540evil.com%26x%3Dx\?}, reply
      assert_no_match(/[?&]bcc=/, reply)
    end
  end

  test "a change from a stale page is refused, not applied" do
    closed = report
    closed.close!("fixed", by: "human:tosin")
    sign_in_as users(:admin)

    post start_admin_correction_path(closed)

    assert_match "Not changed: it's already closed", flash[:alert]
    assert_equal [ "closed", "fixed" ], [ closed.reload.status, closed.resolution ]
  end

  test "more than a page of reports pages on" do
    (Admin::CorrectionsController::PAGE + 1).times { report }
    sign_in_as users(:admin)

    get admin_corrections_path
    assert_select ".nd-wait", Admin::CorrectionsController::PAGE
    assert_select "a[href=?]", admin_corrections_path(tab: "open", page: 2)

    get admin_corrections_path(tab: "open", page: 2)
    assert_select ".nd-wait", 1
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
