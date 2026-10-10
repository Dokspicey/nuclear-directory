# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Anonymous page views (#66): loaded lazily by app/javascript/analytics.js.
pin "analytics"
pin "posthog-js", to: "https://cdn.jsdelivr.net/npm/posthog-js@1.438.7/dist/module.mjs", preload: false
