# Be sure to restart your server when you modify this file.

ActiveSupport::Inflector.inflections(:en) do |inflect|
  # One table and model for all evidence rows: Evidence, `evidence`.
  inflect.uncountable %w[evidence]
end
