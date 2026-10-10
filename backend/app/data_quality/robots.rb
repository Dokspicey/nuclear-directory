# Reads a robots.txt and answers "may this crawler fetch this URL?"
# (RFC 9309): the group for our user agent applies, else the "*" group; the
# longest matching rule wins, Allow beats Disallow on a tie; * and $ work as
# wildcards. Rules may be full URLs (nrc.gov writes them that way), which
# are reduced to their path.
class DataQuality::Robots
  class Rule
    attr_reader :allow, :length

    def initialize(allow:, pattern:)
      @allow = allow
      @length = pattern.length
      @regex = Regexp.new("\\A" + Regexp.escape(pattern).gsub("\\*", ".*").sub(/\\\$\z/, "\\z"))
    end

    def matches?(path) = @regex.match?(path)
  end

  def self.parse(text) = new(text)

  def initialize(text)
    @groups = parse_groups(text.to_s)
  end

  # agent is our product token, e.g. "NuclearDirectoryBot".
  def allowed?(url, agent:)
    uri = URI.parse(url)
    path = [ uri.path.presence || "/", uri.query ].compact.join("?")
    rules = rules_for(agent)
    match = rules.select { |rule| rule.matches?(path) }.max_by { |rule| [ rule.length, rule.allow ? 1 : 0 ] }
    match.nil? || match.allow
  end

  private
    def rules_for(agent)
      agent = agent.downcase
      @groups.find { |agents, _| agents.any? { |name| name != "*" && agent.include?(name) } }&.last ||
        @groups.find { |agents, _| agents.include?("*") }&.last || []
    end

    # => [ [ ["agent", ...], [Rule, ...] ], ... ]
    def parse_groups(text)
      groups = []
      collecting_agents = false

      text.each_line do |line|
        key, value = line.sub(/#.*/, "").split(":", 2).map { |part| part.to_s.strip }
        next if key.blank? || value.nil?

        case key.downcase
        when "user-agent"
          groups << [ [], [] ] unless collecting_agents
          groups.last.first << value.downcase
          collecting_agents = true
        when "allow", "disallow"
          collecting_agents = false
          next if groups.empty?

          pattern = rule_path(value)
          # An empty Disallow means "allow everything", so it adds no rule.
          groups.last.last << Rule.new(allow: key.casecmp?("allow"), pattern:) if pattern.present?
        else
          collecting_agents = false
        end
      end

      groups
    end

    def rule_path(value)
      return value unless value.match?(%r{\Ahttps?://}i)

      uri = URI.parse(value)
      [ uri.path.presence || "/", uri.query ].compact.join("?")
    rescue URI::InvalidURIError
      nil
    end
end
