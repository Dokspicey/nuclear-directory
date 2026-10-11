module ApplicationHelper
  # The browser bar colour on phones: --nd-paper from tokens.css, light and
  # dark. Meta tags can't read CSS custom properties, so it's repeated here
  # (and in public/manifest.webmanifest).
  THEME_COLORS = { light: "#f7f7f5", dark: "#0c0c0d" }.freeze

  # public/ files are cached for a year and the icons keep their names, so
  # the links carry a version. Bump it, and the ?v= in
  # public/manifest.webmanifest, whenever the icon changes.
  SITE_ICON_VERSION = 2

  def site_icon_path(file)
    "/#{file}?v=#{SITE_ICON_VERSION}"
  end
end
