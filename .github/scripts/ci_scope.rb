# Decides which CI jobs a pull request needs, from the files it changes.
# lint and blueprint always run; this only decides test and lighthouse.
#
#   docs only (Markdown, planning/)                          -> neither
#   render.yaml, .github/ (except ci.yml), backup/, compose -> test only
#   anything else, or nothing listed                         -> both
#
# Run by CI (scope job) from the PR's base commit, so a PR can't edit its way
# out of tests: changed paths on stdin, one per line. Writes
# test=true|false and lighthouse=true|false to $GITHUB_OUTPUT (or stdout).
module CiScope
  DOCS = [
    /\.md\z/i,
    %r{\Aplanning/}
  ].freeze

  # Can't change the app or its pages, but tests still cover the scripts
  # and config around it. ci.yml and this classifier aren't here: a change
  # to how CI decides runs everything.
  INFRA = [
    %r{\Arender\.yaml\z},
    %r{\A\.github/(?!workflows/ci\.yml\z|scripts/ci_scope)},
    %r{\Abackup/},
    %r{\Adocker-compose[^/]*\.ya?ml\z},
    %r{\A\.env\.example\z},
    %r{\A\.gitignore\z}
  ].freeze

  module_function

  def kind(path)
    return :docs if DOCS.any? { |pattern| path.match?(pattern) }
    return :infra if INFRA.any? { |pattern| path.match?(pattern) }

    :app
  end

  def scope(paths)
    kinds = paths.map(&:strip).reject(&:empty?).map { |path| kind(path) }
    # Nothing to go on: run everything.
    return { test: true, lighthouse: true } if kinds.empty?

    app = kinds.include?(:app)
    { test: app || kinds.include?(:infra), lighthouse: app }
  end
end

if $PROGRAM_NAME == __FILE__
  result = CiScope.scope($stdin.each_line.to_a)
  lines = result.map { |job, needed| "#{job}=#{needed}" }
  output = ENV["GITHUB_OUTPUT"]
  output ? File.open(output, "a") { |file| file.puts(lines) } : puts(lines)
  warn "CI scope: #{lines.join(', ')}"
end
