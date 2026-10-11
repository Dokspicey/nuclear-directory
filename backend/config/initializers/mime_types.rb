# Serve public/manifest.webmanifest as a web app manifest, not plain text.
Rack::Mime::MIME_TYPES[".webmanifest"] = "application/manifest+json"
