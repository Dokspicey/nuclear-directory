module ApplicationHelper
  # The browser bar colour on phones: --nd-paper from tokens.css, light and
  # dark. Meta tags can't read CSS custom properties, so it's repeated here
  # (and in public/manifest.webmanifest).
  THEME_COLORS = { light: "#f7f7f5", dark: "#0c0c0d" }.freeze
end
