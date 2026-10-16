require "test_helper"

# Corrections email Tosin through Resend (#317): queued, plain text, and
# skipped (logged) when the address or Resend's key isn't set.
class CorrectionMailerTest < ActionMailer::TestCase
  NEEDS = CorrectionMailer::NEEDS

  def with_env(values)
    saved = NEEDS.to_h { |name| [ name, ENV[name] ] }
    NEEDS.each { |name| ENV.delete(name) }
    values.each { |name, value| ENV[name] = value }
    yield
  ensure
    saved.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end

  def report = CorrectionReport.create!(subject: "Plant Vogtle", page_path: "/plants/plant-vogtle", message: "Unit 4 started in 2024.",
    contact: "reader@example.com")

  test "it's queued for later, to the address in CORRECTIONS_NOTIFY_TO, with the page, message, contact and admin link" do
    sent = report

    with_env("CORRECTIONS_NOTIFY_TO" => "alerts-to@example.com", "RESEND_API_KEY" => "re_test") do
      assert_enqueued_emails(1) { CorrectionMailer.notify(sent) }
    end
    email = CorrectionMailer.with(report: sent).submitted
    with_env("CORRECTIONS_NOTIFY_TO" => "alerts-to@example.com", "RESEND_API_KEY" => "re_test") { email.deliver_now }

    assert_equal [ "alerts-to@example.com" ], email.to
    assert_equal "Nuclear Directory <alerts@mail.nuclear-directory.org>", email[:from].to_s
    assert_equal "Correction: Plant Vogtle", email.subject
    body = email.body.to_s
    assert_match "Unit 4 started in 2024.", body
    assert_match "reader@example.com", body
    assert_match "/plants/plant-vogtle", body
    assert_match "/admin/corrections#report-#{sent.id}", body
  end

  test "without the address or Resend's key, nothing is queued and the skip is logged" do
    sent = report
    [ { "RESEND_API_KEY" => "re_test" }, { "CORRECTIONS_NOTIFY_TO" => "alerts-to@example.com" } ].each do |only_one|
      with_env(only_one) do
        logged = StringIO.new
        logger, Rails.logger = Rails.logger, ActiveSupport::Logger.new(logged)
        assert_no_enqueued_emails { CorrectionMailer.notify(sent) }
        assert_match "no email for correction #{sent.id}", logged.string
      ensure
        Rails.logger = logger
      end
    end
  end
end
