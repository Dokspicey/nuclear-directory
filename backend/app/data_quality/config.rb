# Settings for the module, read from the environment (see .env.example).
# Extract and verify use different models so the verifier is a genuinely
# independent second opinion.
class DataQuality::Config
  class ConfigurationError < StandardError; end

  ROLES = %i[extract verify].freeze

  # Model spend per calendar month, in US dollars, before model calls are
  # refused (DataQuality::Budget). Kept below the OpenRouter key's own cap.
  DEFAULT_MONTHLY_BUDGET = 5.0

  attr_reader :api_key, :extract_model, :verify_model, :monthly_budget,
    :open_timeout, :read_timeout, :max_attempts, :base_delay

  def self.from_env(env = ENV)
    new(
      api_key: env["OPENROUTER_API_KEY"],
      extract_model: env["OPENROUTER_EXTRACT_MODEL"],
      verify_model: env["OPENROUTER_VERIFY_MODEL"],
      monthly_budget: parse_budget(env["DATA_QUALITY_MONTHLY_BUDGET"])
    )
  end

  # A typo ("five") must not quietly become $0 and refuse every call as if
  # the budget were spent. 0 is allowed (no model calls at all); negative isn't.
  def self.parse_budget(value)
    return DEFAULT_MONTHLY_BUDGET if value.blank?

    budget = Float(value.strip)
    raise ConfigurationError, "DATA_QUALITY_MONTHLY_BUDGET can't be negative (got #{value.inspect})" if budget.negative?

    budget
  rescue ArgumentError
    raise ConfigurationError, "DATA_QUALITY_MONTHLY_BUDGET must be a number of US dollars, like 5 or 2.50 (got #{value.inspect})"
  end
  private_class_method :parse_budget

  def initialize(api_key:, extract_model:, verify_model:, monthly_budget: DEFAULT_MONTHLY_BUDGET,
    open_timeout: 10, read_timeout: 120, max_attempts: 3, base_delay: 1.0)
    @api_key = api_key.presence
    @extract_model = extract_model.presence
    @verify_model = verify_model.presence
    @monthly_budget = monthly_budget
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @max_attempts = max_attempts
    @base_delay = base_delay
  end

  def model_for(role)
    raise ArgumentError, "unknown role #{role.inspect}, expected one of #{ROLES}" unless ROLES.include?(role)

    public_send(:"#{role}_model")
  end

  # Raises with every problem at once, so a misconfigured .env is fixed in one go.
  def validate!
    problems = []
    problems << "OPENROUTER_API_KEY is not set" unless api_key
    problems << "OPENROUTER_EXTRACT_MODEL is not set" unless extract_model
    problems << "OPENROUTER_VERIFY_MODEL is not set" unless verify_model
    if extract_model && extract_model == verify_model
      problems << "OPENROUTER_EXTRACT_MODEL and OPENROUTER_VERIFY_MODEL must be different models"
    end
    raise ConfigurationError, problems.join("; ") if problems.any?

    self
  end
end
