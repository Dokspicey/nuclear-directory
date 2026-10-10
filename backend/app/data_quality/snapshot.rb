# Fetches one Source and records the result on it: a new snapshot
# (content, hash, ETag) on success, or crawl_status blocked / needs_human
# with the reason. Shared by all plug-ins.
#
#   DataQuality::Snapshot.take(source, fetcher: fetcher)
#   # => :changed, :unchanged, :skipped_recent, :blocked, :disallowed or :error
class DataQuality::Snapshot
  # Fetch each source at most once per calendar day.
  # Blocked this many fetches in a row: stop treating it as temporary.
  BLOCKED_STREAK_LIMIT = 3

  def self.take(source, fetcher:)
    return :skipped_recent if source.fetched_at&.to_date == Date.current

    response = fetcher.get(source.url, etag: source.etag, last_modified: source.last_modified)
    attempt = { fetched_at: Time.current, http_status: response.status }

    case response.kind
    when :ok
      sha = Digest::SHA256.hexdigest(response.body)
      changed = sha != source.content_sha256
      source.update!(attempt.merge(fresh(source, response)).merge(content_text: response.body, content_sha256: sha))
      changed ? :changed : :unchanged
    when :not_modified
      source.update!(attempt.merge(fresh(source, response)))
      :unchanged
    when :blocked
      streak = source.blocked_streak + 1
      reason = response.reason
      reason = "Blocked #{streak} fetches in a row; last: #{reason}" if streak >= BLOCKED_STREAK_LIMIT
      source.update!(attempt.merge(blocked_streak: streak, status_reason: reason,
        crawl_status: streak >= BLOCKED_STREAK_LIMIT ? "needs_human" : "blocked"))
      :blocked
    when :disallowed
      source.update!(attempt.merge(crawl_status: "needs_human", status_reason: response.reason))
      :disallowed
    else
      # Temporary (server error, timeout): keep the last good snapshot and try tomorrow.
      source.update!(attempt.merge(status_reason: response.reason))
      :error
    end
  end

  # A successful fetch clears any block. Validators are only replaced when
  # the server sends new ones (a 304 may omit them).
  def self.fresh(source, response)
    { crawl_status: "ok", status_reason: nil, blocked_streak: 0,
      etag: response.etag || source.etag, last_modified: response.last_modified || source.last_modified }
  end
  private_class_method :fresh
end
