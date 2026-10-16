# Tells Tosin a correction came in (#317), in plain text, through Resend.
# The address is ENV["CORRECTIONS_NOTIFY_TO"], set in Render; nothing is
# hardcoded. Sent later (Solid Queue), so a Resend outage never blocks the
# form, and skipped (and logged) when the address or Resend's key is missing.
#
#   CorrectionMailer.notify(report)
class CorrectionMailer < ApplicationMailer
  FROM = "Nuclear Directory <alerts@mail.nuclear-directory.org>"
  NEEDS = %w[CORRECTIONS_NOTIFY_TO RESEND_API_KEY].freeze

  # Queues the email, or logs why it isn't sent. The correction is saved either way.
  def self.notify(report)
    missing = NEEDS.select { |name| ENV[name].blank? }
    return Rails.logger.info("[corrections] no email for correction #{report.id}: #{missing.join(' and ')} not set") if missing.any?

    with(report:).submitted.deliver_later
  end

  def submitted
    @report = params[:report]
    mail(from: FROM, to: ENV["CORRECTIONS_NOTIFY_TO"], subject: "Correction: #{@report.subject.truncate(80)}") do |format|
      format.text
    end
  end
end
