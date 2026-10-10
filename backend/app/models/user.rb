# An admin account (#86). Made with `bin/rails admin:create`.
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :handle, with: ->(h) { h.strip.downcase }

  validates :handle, presence: true, uniqueness: true, format: { with: /\A[a-z][a-z0-9_-]*\z/ }
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :email_address, presence: true, uniqueness: true, format: { with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/ }

  # Who decided, in the audit trail: "human:tosin".
  def actor = "human:#{handle}"
end
