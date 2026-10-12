require "net/http"

# /relay/* (#205): the browser's PostHog traffic goes through our site, so
# ad blockers don't drop page views and each event gets the visitor's
# country, looked up here (GeoCountry). The path is neutral on purpose:
# blockers catch "analytics", "posthog", "track" and "ingest".
#
# - Only PostHog's capture and flag endpoints and its scripts are passed on
#   (PATHS); anything else is 404, so this is no open proxy.
# - Event bodies are plain JSON (analytics.js turns compression off). Each
#   event gets the country, and any "$ip" property is removed.
# - The visitor's IP goes to PostHog only in X-Forwarded-For, because
#   cookieless mode counts unique visitors from a daily hash of IP and
#   browser; PostHog drops it after hashing (#48660), and nothing here
#   stores or logs it. Cookies aren't passed either way.
# - 1 MB per request, a 3-second timeout, 120 requests a minute per visitor.
class RelayController < ActionController::API
  INGEST = URI("https://us.i.posthog.com")
  ASSETS = URI("https://us-assets.i.posthog.com")
  # What posthog-js calls: events, flags/config, and its own scripts.
  PATHS = %r{\A(e|i/v0/e|batch|capture|flags|decide|static/[\w./-]+|array/[\w./-]+)/?\z}
  EVENT_PATHS = %r{\A(e|i/v0/e|batch|capture)/?\z}
  MAX_BODY = 1.megabyte
  TIMEOUT = 3
  RATE_LIMIT = 120
  # In this process's memory: a request never touches the database.
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 4.megabytes)
  # Response headers worth passing back; the rest (cookies included) aren't.
  PASSED_BACK = %w[Content-Type Cache-Control ETag Last-Modified].freeze

  rate_limit to: RATE_LIMIT, within: 1.minute, store: RATE_LIMIT_STORE,
    by: -> { Digest::SHA256.hexdigest("#{request.remote_ip}:#{Rails.application.secret_key_base}") },
    with: -> { head :too_many_requests }

  def forward
    # As the browser sent it: the router drops the trailing slash PostHog's
    # endpoints use ("/e/") from params[:path] and request.path.
    path = request.original_fullpath.split("?", 2).first.delete_prefix("/relay/")
    return head(:not_found) unless path.match?(PATHS) && !path.include?("..")
    return head(:content_too_large) if request.content_length.to_i > MAX_BODY

    # At most one byte past the cap, so a chunked upload with no length can't
    # make us hold more than that.
    body = request.body&.tap(&:rewind)&.read(MAX_BODY + 1).to_s
    return head(:content_too_large) if body.bytesize > MAX_BODY

    # TEMPORARY (#211 preview check, Infra): which address Rails sees behind
    # Cloudflare and Render. Removed before merge.
    Rails.logger.info("[relay-ip] remote_ip=#{request.remote_ip} xff=#{request.headers['X-Forwarded-For']} " \
      "cf=#{request.headers['CF-Connecting-IP']} tci=#{request.headers['True-Client-IP']}")
    body = with_country(body) if request.post? && path.match?(EVENT_PATHS)
    upstream = send_upstream(path, body)
    PASSED_BACK.each { |name| response.headers[name] = upstream[name] if upstream[name] }
    render body: upstream.body, status: upstream.code.to_i
  rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError
    head :bad_gateway
  end

  private
    def send_upstream(path, body)
      host = path.start_with?("static/", "array/") ? ASSETS : INGEST
      uri = URI.join(host, "/#{path}")
      uri.query = request.query_string.presence

      upstream = request.post? ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      upstream["Content-Type"] = request.content_type if request.content_type
      upstream["User-Agent"] = request.user_agent.to_s
      upstream["X-Forwarded-For"] = request.remote_ip
      upstream.body = body if request.post?

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT,
        write_timeout: TIMEOUT) { |http| http.request(upstream) }
    end

    # The events, with the country added and any IP removed, in the format
    # they came in: plain JSON, or the "data=<base64 JSON>" form posthog-js
    # uses for sendBeacon (page leaves), whatever its compression setting.
    # Anything else (gzip from a client that ignores disable_compression) is
    # passed on unchanged.
    def with_country(body)
      if body.start_with?("data=")
        json = Base64.decode64(URI.decode_www_form_component(body.delete_prefix("data="))).force_encoding(Encoding::UTF_8)
        "data=#{URI.encode_www_form_component(Base64.strict_encode64(add_country(json)))}"
      else
        add_country(body)
      end
    rescue JSON::ParserError, ArgumentError
      body
    end

    def add_country(json)
      payload = JSON.parse(json)
      events = payload.is_a?(Hash) && payload["batch"].is_a?(Array) ? payload["batch"] : Array.wrap(payload)
      added = GeoCountry.properties(request.remote_ip)
      events.each do |event|
        next unless event.is_a?(Hash)

        # A client's properties that aren't an object are replaced, not trusted.
        event["properties"] = {} unless event["properties"].is_a?(Hash)
        properties = event["properties"]
        properties.delete("$ip")
        properties.merge!(added)
      end
      payload.to_json
    end
end
