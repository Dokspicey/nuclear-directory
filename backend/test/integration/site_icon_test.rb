require "test_helper"

# The site icon set: tab icons, the iPhone home-screen icon and the install
# manifest, all pointing at files that exist.
class SiteIconTest < ActionDispatch::IntegrationTest
  test "every page links the full icon set, the manifest and both theme colours" do
    get root_path

    version = "?v=#{ApplicationHelper::SITE_ICON_VERSION}"
    assert_select "link[rel=icon][href=?]", "/favicon.ico#{version}", 1
    assert_select "link[rel=icon][type='image/svg+xml'][href=?]", "/icon.svg#{version}", 1
    assert_select "link[rel=apple-touch-icon][href=?]", "/apple-touch-icon.png#{version}", 1
    assert_select "link[rel=manifest][href=?]", "/manifest.webmanifest#{version}", 1
    assert_select "meta[name=theme-color][media='(prefers-color-scheme: light)'][content=?]", ApplicationHelper::THEME_COLORS[:light]
    assert_select "meta[name=theme-color][media='(prefers-color-scheme: dark)'][content=?]", ApplicationHelper::THEME_COLORS[:dark]
  end

  test "the manifest names the site and lists versioned icons that exist, one of them maskable" do
    manifest = JSON.parse(Rails.public_path.join("manifest.webmanifest").read)

    assert_equal "Nuclear Directory", manifest["name"]
    assert_equal ApplicationHelper::THEME_COLORS[:light], manifest["theme_color"]
    assert_includes manifest["icons"].map { |icon| icon["sizes"] }, "192x192"
    assert_includes manifest["icons"].map { |icon| icon["sizes"] }, "512x512"
    assert manifest["icons"].any? { |icon| icon["purpose"] == "maskable" }
    manifest["icons"].each do |icon|
      path, version = icon["src"].delete_prefix("/").split("?")
      assert Rails.public_path.join(path).file?, icon["src"]
      # Same version as the layout's links, so a new icon reaches installed copies too.
      assert_equal "v=#{ApplicationHelper::SITE_ICON_VERSION}", version, icon["src"]
    end
  end

  test "no layout links an icon without the version, the admin's included" do
    Rails.root.glob("app/views/layouts/*.html.erb").each do |layout|
      assert_no_match %r{href="/(favicon|icon|apple-touch-icon|manifest)}, layout.read, layout.basename.to_s
    end
  end

  test "the manifest is served as a web app manifest" do
    get "/manifest.webmanifest"

    assert_response :success
    assert_equal "application/manifest+json", response.media_type
  end

  test "the icon files linked from the layout exist, with the starter red dot gone" do
    %w[favicon.ico icon.svg apple-touch-icon.png].each { |file| assert Rails.public_path.join(file).file?, file }
    assert_not Rails.public_path.join("icon.png").exist?
    assert_no_match(/red/, Rails.public_path.join("icon.svg").read)
  end
end
