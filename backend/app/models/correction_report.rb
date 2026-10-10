# A correction a visitor sent about a fact or a page (#44). Stored without
# any IP address; contact is only there if they want a reply.
class CorrectionReport < ApplicationRecord
  enum :status, %w[open reviewed closed].index_by(&:itself), default: "open"

  normalizes :subject, :page_path, :contact, with: ->(value) { value.strip.presence }
  normalizes :message, with: ->(value) { value.strip }

  validates :subject, presence: true, length: { maximum: 300 }
  LOCAL_PATH = %r{\A/(?![/\\])[^\s\\]{0,299}\z}

  # A path on this site: one leading slash, no backslashes or whitespace.
  def self.local_path?(path) = path.to_s.match?(LOCAL_PATH)

  validates :page_path, presence: true, format: { with: LOCAL_PATH }
  validates :message, presence: { message: "Say what should change before sending." },
    length: { maximum: 5000, message: "Keep it to 5,000 characters or fewer." }
  validates :contact, length: { maximum: 200, message: "Keep the email to 200 characters or fewer." },
    format: { with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, message: "Enter an email like name@example.com, or leave it empty." },
    allow_nil: true

  # How a closed report ended (#86's inbox): the record was changed, or not.
  RESOLUTIONS = %w[fixed dismissed].freeze
  validates :resolution, inclusion: { in: RESOLUTIONS }, allow_nil: true
  validates :decided_by, format: { with: /\Ahuman:\S+\z/ }, allow_nil: true

  # A report changed from a stale page (already closed, say) is refused.
  class InvalidTransition < StandardError; end

  # Closes an open or in-progress report as fixed or dismissed, by a human ("human:tosin").
  def close!(resolution, by:)
    transition(from: %w[open reviewed]) { update!(status: "closed", resolution:, decided_by: by, decided_at: Time.current) }
  end

  # Someone is looking at an open report (it stays in the open list).
  def start!(by:) = transition(from: %w[open]) { update!(status: "reviewed", decided_by: by) }

  def reopen! = transition(from: %w[closed]) { update!(status: "open", resolution: nil, decided_by: nil, decided_at: nil) }

  private
    def transition(from:)
      with_lock do
        raise InvalidTransition, "it's already #{status == 'reviewed' ? 'in progress' : status}" unless from.include?(status)

        yield
      end
    end
end
