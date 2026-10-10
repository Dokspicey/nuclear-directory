# A correction a visitor sent about a fact or a page (#44). Stored without
# any IP address; contact is only there if they want a reply.
class CorrectionReport < ApplicationRecord
  enum :status, %w[open reviewed closed].index_by(&:itself), default: "open"

  normalizes :subject, :page_path, :contact, with: ->(value) { value.strip.presence }
  normalizes :message, with: ->(value) { value.strip }

  validates :subject, presence: true, length: { maximum: 300 }
  validates :page_path, presence: true, length: { maximum: 300 }, format: { with: %r{\A/(?!/)\S*\z} }
  validates :message, presence: { message: "Say what should change before sending." },
    length: { maximum: 5000, message: "Keep it under 5,000 characters." }
  validates :contact, length: { maximum: 200, message: "Keep the email under 200 characters." },
    format: { with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, message: "Enter an email like name@example.com, or leave it empty." },
    allow_nil: true
end
