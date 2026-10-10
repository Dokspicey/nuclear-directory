require "test_helper"

class DataQuality::RobotsTest < ActiveSupport::TestCase
  AGENT = "NuclearDirectoryBot"

  def allowed?(robots_txt, url) = DataQuality::Robots.parse(robots_txt).allowed?(url, agent: AGENT)

  test "nrc.gov's real robots.txt, with rules written as full URLs" do
    nrc = file_fixture("nrc/robots.txt").read

    assert allowed?(nrc, "https://www.nrc.gov/facilities-safety/operating-reactors/list-power-reactor-units")
    assert allowed?(nrc, "https://www.nrc.gov/docs/ML2401/ML24010A001.pdf"), "the /docs/ rule is only for other bots"
    assert_not allowed?(nrc, "https://www.nrc.gov/site-help/search?q=vogtle")
  end

  test "our own group wins over *" do
    txt = "User-agent: *\nDisallow: /\n\nUser-agent: NuclearDirectoryBot\nDisallow: /private/\n"

    assert allowed?(txt, "https://example.com/reactors")
    assert_not allowed?(txt, "https://example.com/private/x")
  end

  test "the longest match wins and Allow wins a tie" do
    txt = "User-agent: *\nDisallow: /data/\nAllow: /data/public/\nDisallow: /x\nAllow: /x\n"

    assert allowed?(txt, "https://example.com/data/public/list.csv")
    assert_not allowed?(txt, "https://example.com/data/secret.csv")
    assert allowed?(txt, "https://example.com/x")
  end

  test "wildcards, end anchors, empty Disallow and comments" do
    txt = "User-agent: * # everyone\nDisallow: /*.pdf$\nDisallow:\n"

    assert_not allowed?(txt, "https://example.com/files/report.pdf")
    assert allowed?(txt, "https://example.com/files/report.pdf.html")
    assert allowed?(txt, "https://example.com/anything")
  end

  test "agents listed together share their rules" do
    txt = "User-agent: OtherBot\nUser-agent: NuclearDirectoryBot\nDisallow: /shared/\n"

    assert_not allowed?(txt, "https://example.com/shared/page")
  end

  test "every group naming us counts, not just the first (RFC 9309)" do
    txt = "User-agent: NuclearDirectoryBot\nDisallow: /a/\n\nUser-agent: *\nDisallow: /\n\n" \
      "User-agent: NuclearDirectoryBot\nDisallow: /b/\n"

    assert_not allowed?(txt, "https://example.com/a/1")
    assert_not allowed?(txt, "https://example.com/b/1"), "a later group for us still applies"
    assert allowed?(txt, "https://example.com/c/1"), "and the * group doesn't, since we have our own"
  end

  test "every * group counts when none names us" do
    txt = "User-agent: *\nDisallow: /a/\n\nUser-agent: OtherBot\nDisallow: /\n\nUser-agent: *\nDisallow: /b/\n"

    assert_not allowed?(txt, "https://example.com/b/1")
    assert allowed?(txt, "https://example.com/c/1")
  end

  test "an empty robots.txt allows everything" do
    assert allowed?("", "https://example.com/anything")
  end
end
