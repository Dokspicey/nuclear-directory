require "net/http"

# The polite HTTP client every plug-in fetches through:
# - identifies itself honestly (USER_AGENT); never pretends to be a browser
# - checks robots.txt before every URL, including redirect targets
# - waits between requests to the same host
# - sends ETag / Last-Modified back, so unchanged pages cost a 304
# - never retries: a block (401/403) is reported, not worked around
#
#   response = DataQuality::Fetcher.new.get(url, etag: source.etag)
#   response.kind # => :ok, :not_modified, :blocked, :disallowed or :error
class DataQuality::Fetcher
  USER_AGENT = "NuclearDirectoryBot/0.1 (+https://nuclear-directory.org)"
  AGENT_TOKEN = "NuclearDirectoryBot"
  HOST_INTERVAL = 3 # seconds between requests to one host
  MAX_REDIRECTS = 3
  NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED,
    Errno::EHOSTUNREACH, SocketError, EOFError, OpenSSL::SSL::SSLError ].freeze

  # kind:            :ok, :not_modified, :blocked, :disallowed or :error
  # reason:          why, in words, for anything but :ok / :not_modified
  # block_reference: the CDN's reference id on a block page (e.g. Akamai's
  #                  "Reference #18.…"), for asking the site owner about it
  Response = Data.define(:url, :kind, :status, :body, :etag, :last_modified, :reason, :block_reference)

  def initialize(sleeper: ->(seconds) { sleep seconds }, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
    open_timeout: 10, read_timeout: 60)
    @sleeper = sleeper
    @clock = clock
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @robots = {}
    @last_request_at = {}
  end

  def get(url, etag: nil, last_modified: nil)
    redirects = 0

    loop do
      uri = URI.parse(url)
      verdict = robots_verdict(uri)
      return verdict if verdict

      headers = { "If-None-Match" => etag, "If-Modified-Since" => last_modified }.compact
      http = request(uri, headers)

      if http.is_a?(Net::HTTPRedirection) && http["Location"] && redirects < MAX_REDIRECTS
        redirects += 1
        url = URI.join(url, http["Location"]).to_s
        next
      end

      return classify(url, http)
    end
  rescue *NETWORK_ERRORS => error
    response(url, :error, reason: "Network error: #{error.class}: #{error.message}")
  end

  private
    # nil when robots.txt allows the URL, else the Response to return.
    def robots_verdict(uri)
      robots = @robots[uri.host] ||= fetch_robots(uri)
      return robots if robots.is_a?(Response)
      return if robots.allowed?(uri.to_s, agent: AGENT_TOKEN)

      response(uri.to_s, :disallowed, reason: "robots.txt disallows #{uri.path} for #{AGENT_TOKEN}")
    end

    # A DataQuality::Robots, or a Response when robots.txt itself can't be read.
    # Per RFC 9309: missing (4xx) means everything is allowed; unreachable
    # (5xx, network) means nothing is. A 401/403 is a block, not "missing".
    def fetch_robots(uri)
      robots_uri = URI.join("#{uri.scheme}://#{uri.host}", "/robots.txt")
      http = request(robots_uri, {})
      status = http.code.to_i

      case status
      when 200..299 then DataQuality::Robots.parse(body_of(http))
      when 401, 403 then classify(robots_uri.to_s, http)
      when 400..499 then DataQuality::Robots.parse("")
      else response(robots_uri.to_s, :error, status:, reason: "robots.txt returned #{status}; not crawling #{uri.host}")
      end
    rescue *NETWORK_ERRORS => error
      response(robots_uri.to_s, :error, reason: "robots.txt unreachable (#{error.class}); not crawling #{uri.host}")
    end

    def request(uri, headers)
      wait_for(uri.host)
      get = Net::HTTP::Get.new(uri)
      get["User-Agent"] = USER_AGENT
      headers.each { |name, value| get[name] = value }

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: @open_timeout, read_timeout: @read_timeout) { |http| http.request(get) }
    end

    def wait_for(host)
      if (last = @last_request_at[host])
        remaining = HOST_INTERVAL - (@clock.call - last)
        @sleeper.call(remaining) if remaining.positive?
      end
      @last_request_at[host] = @clock.call
    end

    def classify(url, http)
      status = http.code.to_i

      case status
      when 200..299
        response(url, :ok, status:, body: body_of(http), etag: http["ETag"], last_modified: http["Last-Modified"])
      when 304
        response(url, :not_modified, status:, etag: http["ETag"], last_modified: http["Last-Modified"])
      when 401, 403
        reference = block_reference(http)
        response(url, :blocked, status:, block_reference: reference,
          reason: [ "HTTP #{status} from #{http['Server'] || 'the server'}", reference && "reference ##{reference}" ].compact.join(", "))
      else
        response(url, :error, status:, reason: "HTTP #{status}")
      end
    end

    def response(url, kind, status: nil, body: nil, etag: nil, last_modified: nil, reason: nil, block_reference: nil)
      Response.new(url:, kind:, status:, body:, etag:, last_modified:, reason:, block_reference:)
    end

    def body_of(http)
      body = http.body.to_s.dup
      charset = http.type_params["charset"]
      body.force_encoding(Encoding.find(charset)) rescue body.force_encoding(Encoding::UTF_8)
      body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end

    # Akamai puts the id in a header and in the page ("Reference&#32;&#35;18&#46;…").
    def block_reference(http)
      http["X-Reference-Error"].presence ||
        CGI.unescapeHTML(http.body.to_s)[/Reference\s*#\s*([\w.]+)/, 1]
    end
end
