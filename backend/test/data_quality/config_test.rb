require "test_helper"

class DataQuality::ConfigTest < ActiveSupport::TestCase
  def config(**overrides)
    DataQuality::Config.new(api_key: "test-key", extract_model: "vendor/extractor", verify_model: "vendor/verifier", **overrides)
  end

  test "reads settings from the environment" do
    config = DataQuality::Config.from_env(
      "OPENROUTER_API_KEY" => "test-key", "OPENROUTER_EXTRACT_MODEL" => "a/x", "OPENROUTER_VERIFY_MODEL" => "b/y"
    )

    assert_equal "a/x", config.model_for(:extract)
    assert_equal "b/y", config.model_for(:verify)
  end

  test "extract and verify must use different models" do
    error = assert_raises(DataQuality::Config::ConfigurationError) { config(verify_model: "vendor/extractor").validate! }
    assert_match "must be different", error.message
  end

  test "reports every missing setting at once" do
    error = assert_raises(DataQuality::Config::ConfigurationError) do
      DataQuality::Config.from_env({}).validate!
    end

    assert_match "OPENROUTER_API_KEY", error.message
    assert_match "OPENROUTER_EXTRACT_MODEL", error.message
    assert_match "OPENROUTER_VERIFY_MODEL", error.message
  end

  test "rejects unknown roles" do
    assert_raises(ArgumentError) { config.model_for(:summarize) }
  end
end
