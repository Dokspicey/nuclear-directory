# Tests for ci_scope.rb. Run by CI (blueprint job):
#   ruby .github/scripts/ci_scope_test.rb
require "minitest/autorun"
require "open3"
require_relative "ci_scope"

class CiScopeTest < Minitest::Test
  def scope(*paths)
    CiScope.scope(paths)
  end

  def test_docs_only_skips_test_and_lighthouse
    assert_equal({ test: false, lighthouse: false },
      scope("README.md", "DESIGN.md", "backend/app/data_quality/README.md", "planning/prd.md",
        "ops/metabase/questions/01_companies_by_status.sql"))
  end

  def test_render_yaml_or_github_only_skips_lighthouse
    assert_equal({ test: true, lighthouse: false }, scope("render.yaml"))
    assert_equal({ test: true, lighthouse: false }, scope(".github/scripts/check_blueprint.rb", ".github/workflows/preview.yml"))
    assert_equal({ test: true, lighthouse: false }, scope("backup/backup.sh", "docker-compose.metabase.yml", "README.md"))
  end

  def test_a_change_to_ci_itself_runs_everything
    assert_equal({ test: true, lighthouse: true }, scope(".github/workflows/ci.yml"))
  end

  def test_app_changes_run_everything
    %w[
      backend/app/views/companies/show.html.erb backend/app/assets/stylesheets/application.css
      backend/app/javascript/controllers/search_controller.js backend/config/routes.rb
      backend/db/migrate/20261011030000_add_decision.rb backend/lib/analytics.rb backend/public/robots.txt
      backend/Gemfile backend/Gemfile.lock backend/Dockerfile backend/test/models/organization_test.rb
    ].each do |path|
      assert_equal({ test: true, lighthouse: true }, scope(path), path)
    end
  end

  def test_one_app_file_among_docs_runs_everything
    assert_equal({ test: true, lighthouse: true }, scope("README.md", "backend/app/models/organization.rb"))
  end

  def test_unknown_or_empty_runs_everything
    assert_equal({ test: true, lighthouse: true }, scope("some/new/thing.txt"))
    assert_equal({ test: true, lighthouse: true }, scope)
    assert_equal({ test: true, lighthouse: true }, scope("", "  "))
  end

  def test_the_command_line_writes_github_outputs
    output, status = Open3.capture2e({ "GITHUB_OUTPUT" => nil }, "ruby", File.expand_path("ci_scope.rb", __dir__),
      stdin_data: "README.md\nrender.yaml\n")
    assert status.success?, output
    assert_includes output, "test=true"
    assert_includes output, "lighthouse=false"
  end
end
