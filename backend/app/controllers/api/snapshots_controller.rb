# GET /api/snapshot.json (#193): a public summary of the directory for
# other sites (DirectorySnapshot). Read-only, no session or cookies, open to
# any origin, cached by browsers and shared caches, and served from memory.
class Api::SnapshotsController < ActionController::API
  RATE_LIMIT = 60
  # In this process's memory, like the snapshot: a request never touches the
  # database. A fresh store per process is fine for a per-minute limit.
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 2.megabytes)

  rate_limit to: RATE_LIMIT, within: 1.minute, store: RATE_LIMIT_STORE,
    by: -> { Digest::SHA256.hexdigest("#{request.remote_ip}:#{Rails.application.secret_key_base}") },
    with: -> { head :too_many_requests, "Retry-After" => "60", "Access-Control-Allow-Origin" => "*" }

  def show
    response.headers["Access-Control-Allow-Origin"] = "*"
    expires_in 5.minutes, public: true, "s-maxage": 1.hour.to_i, stale_while_revalidate: 1.day
    render json: DirectorySnapshot.current(base_url: request.base_url)
  end
end
