# Fetches one Source and records the result on it: a new snapshot
# (content, hash, ETag, and the page's title when it has one) on success,
# or crawl_status blocked / needs_human with the reason. Shared by all
# plug-ins.
#
#   DataQuality::Snapshot.take(source, fetcher: fetcher)
#   # => :changed, :unchanged, :skipped_recent, :blocked, :disallowed or :error
class DataQuality::Snapshot
  # Blocked this many fetches in a row: stop treating it as temporary.
  BLOCKED_STREAK_LIMIT = 3

  # binary: fetch raw bytes. With a block, the block turns the fetched body
  # into the text that's stored (e.g. the rows of a spreadsheet that matter),
  # and the hash is of that text, so unrelated changes to the file don't
  # count as changes.
  # same_origin: don't follow a redirect to another site (see Fetcher#get).
  def self.take(source, fetcher:, binary: false, same_origin: false, &to_text)
    # At most one fetch per source per calendar day (in the app's time zone).
    return :skipped_recent if source.fetched_at&.to_date == Date.current

    response = fetcher.get(source.url, etag: source.etag, last_modified: source.last_modified, binary:, same_origin:)
    attempt = { fetched_at: Time.current, http_status: response.status }

    case response.kind
    when :ok
      if response.truncated
        # Half a page would look like a changed page; keep the last good snapshot.
        source.update!(attempt.merge(status_reason: "Larger than #{DataQuality::Fetcher::MAX_BYTES / 1.megabyte} MB; not stored"))
        return :error
      end

      text = convert(response.body, source, attempt, &to_text)
      sha = Digest::SHA256.hexdigest(text)
      changed = sha != source.content_sha256
      title = DataQuality::PageTitle.from(response.body, content_type: response.content_type) unless binary
      source.update!(attempt.merge(fresh(source, response))
        .merge(content_text: text, content_sha256: sha, title: title || source.title))
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

  # The body as the text to store. A conversion that fails still counts as
  # today's fetch, so a rerun the same day doesn't download the file again.
  def self.convert(body, source, attempt)
    block_given? ? yield(body) : body
  rescue StandardError
    source.update!(attempt)
    raise
  end
  private_class_method :convert

  # A successful fetch clears any block. Validators are only replaced when
  # the server sends new ones (a 304 may omit them).
  def self.fresh(source, response)
    { crawl_status: "ok", status_reason: nil, blocked_streak: 0,
      etag: response.etag || source.etag, last_modified: response.last_modified || source.last_modified }
  end
  private_class_method :fresh
end
