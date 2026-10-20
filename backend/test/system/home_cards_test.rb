require "application_system_test_case"
require_relative "../support/directory_builders"

# The home page's category cards (#362), against the spec's acceptance tests.
class HomeCardsTest < ApplicationSystemTestCase
  include DirectoryBuilders

  AUDIT = File.readlines(File.expand_path("../support/no_wrap_audit.js", __dir__)).reject { |line| line.start_with?("//") }.join

  # Every bucket full, with long names, as on production.
  setup do
    %w[reactor_vendor fuel components waste_decommissioning utility data_center_offtaker reactor_services venture_capital government_agency]
      .each_with_index do |key, index|
        bucket_role = role(key)
        4.times { |n| cite!(company("#{key.humanize} Company Number #{n} Holdings International #{index}", roles: [ bucket_role ])) }
      end
    4.times { |n| cite!(plant("Long Named Generating Station Number #{n}", facility_type: "power_reactor", status: "operating")) }
  end

  def cards = page.evaluate_script("[...document.querySelectorAll('section.nd-catcard')].map((c) => [c.dataset.key, c.querySelectorAll('a.nd-catcard__row').length])")

  test "phones keep the suggested searches: one 28px row under the search box, scrolling inside itself, never the page" do
    [ [ 360, 780 ], [ 390, 844 ] ].each do |width, height|
      resize_viewport(width, height)
      visit root_path

      row = page.evaluate_script(<<~JS)
        (() => {
          const row = document.querySelector(".nd-home .nd-suggs"), pills = [...row.querySelectorAll(".nd-sugg")]
          const tops = new Set(pills.map((pill) => Math.round(pill.getBoundingClientRect().top)))
          return [pills.length, tops.size, Math.max(...pills.map((pill) => Math.round(pill.getBoundingClientRect().height))),
            parseFloat(getComputedStyle(pills[0]).fontSize), document.documentElement.scrollWidth <= innerWidth]
        })()
      JS
      assert_equal [ 4, 1, 28, 13.0, true ], row, "at #{width}: four pills, one row, 28px, 13px, no sideways page scroll"
      assert_empty page.evaluate_script(AUDIT), "at #{width}"
    end
  end

  test "on a phone the whole card header is the button, edge to edge" do
    resize_viewport(390, 844)
    visit root_path
    edges = page.evaluate_script(<<~JS)
      (() => {
        const head = document.querySelector(".nd-catcard__head--toggle"), button = head.querySelector(".nd-catcard__toggle")
        const h = head.getBoundingClientRect(), b = button.getBoundingClientRect()
        return [Math.round(b.left - h.left), Math.round(h.right - b.right)]
      })()
    JS
    assert_equal [ 0, 0 ], edges, "no untappable strip at either edge"
  end

  test "a category title is never cut short: it fits, and it isn't excused from being cut" do
    visit root_path
    titles = page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".nd-catcard__name")].map((name) => [name.textContent.trim(), name.hasAttribute("data-truncate"), name.scrollWidth <= name.clientWidth + 1])
    JS
    assert_not_empty titles
    titles.each do |text, excused, fits|
      assert_not excused, "#{text} is marked as allowed to be cut short"
      assert fits, "#{text} is cut short"
    end
  end

  test "on a phone the focus ring on a card row is drawn inside the row, so the card can't cut it" do
    resize_viewport(390, 844)
    visit root_path

    page.execute_script(<<~JS)
      const row = [...document.querySelectorAll(".nd-catstack a.nd-catcard__row")].find((r) => r.getBoundingClientRect().height > 0)
      row.focus()
    JS
    page.send_keys(:tab, [ :shift, :tab ]) # keyboard focus, so :focus-visible applies
    style, offset, inset = page.evaluate_script(<<~JS)
      (() => {
        const row = document.activeElement, box = row.getBoundingClientRect()
        const inner = row.closest(".nd-catcard__inner").getBoundingClientRect()
        return [getComputedStyle(row).outlineStyle, parseFloat(getComputedStyle(row).outlineOffset), Math.round(box.left - inner.left)]
      })()
    JS
    assert_equal "solid", style, "the row shows a focus ring"
    assert_operator offset, :<=, 0, "the ring is drawn inside the row"
    assert_equal 0, inset, "the row runs edge to edge, so only an inside ring survives"
  end

  test "on a phone the focus ring on a suggestion pill is drawn inside the pill, so the scrolling row can't cut it" do
    resize_viewport(390, 844)
    visit root_path

    page.execute_script("document.querySelector('.nd-home .nd-sugg').focus()")
    page.send_keys(:tab, [ :shift, :tab ]) # keyboard focus, so :focus-visible applies
    style, offset, edges = page.evaluate_script(<<~JS)
      (() => {
        const pill = document.activeElement, box = pill.getBoundingClientRect()
        const row = pill.closest(".nd-suggs").getBoundingClientRect()
        return [getComputedStyle(pill).outlineStyle, parseFloat(getComputedStyle(pill).outlineOffset),
          [Math.round(box.top - row.top), Math.round(row.bottom - box.bottom)]]
      })()
    JS
    assert_equal "solid", style, "the pill shows a focus ring"
    assert_operator offset, :<=, 0, "the ring is drawn inside the pill"
    assert_equal [ 0, 0 ], edges, "the pill fills the row's height, so only an inside ring survives"
  end

  test "the /design example cards are as wide as on the home page, and nothing in them is cut" do
    visit "/design"
    widths = page.evaluate_script("[...document.querySelectorAll('.nd-catgrid--example .nd-catcard')].map((card) => Math.round(card.getBoundingClientRect().width))")
    assert widths.all? { |width| width >= 190 }, widths.inspect
    problems = page.evaluate_script(AUDIT).grep(/nd-catcard/)
    assert_empty problems, problems.join("\n")
  end

  [ [ 1440, 900 ], [ 1280, 800 ] ].each do |width, height|
    test "the whole page fits #{width}x#{height} with no scroll, one line everywhere" do
      resize_viewport(width, height)
      visit root_path

      assert_operator page.evaluate_script("document.documentElement.scrollHeight"), :<=, height, "the page scrolls at #{width}x#{height}"
      assert_equal 10, cards.size
      assert_equal "plants", cards.last.first, "Plants and sites is the last card"
      assert(cards.all? { |_, rows| rows <= 3 })
      assert_empty page.evaluate_script(AUDIT)
      assert page.evaluate_script("[...document.querySelectorAll('.nd-catcard__chev')].every((c) => c.offsetParent)"), "every row shows its › at rest"
    end
  end

  test "on a phone: no sideways scroll, 44px links, sticky headers, cards that collapse and stay collapsed" do
    resize_viewport(390, 844)
    visit root_path

    assert_empty page.evaluate_script(AUDIT)
    short = page.evaluate_script("[...document.querySelectorAll('.nd-catstack a, .nd-catstack button')].filter((el) => el.offsetParent && el.getBoundingClientRect().height < 44).map((el) => el.textContent.trim())")
    assert_empty short, "links under 44px tall"
    assert_equal "plants", cards.last.first
    assert_equal 0, page.evaluate_script("document.querySelectorAll('.nd-catstack .nd-catcard__count').length - document.querySelectorAll('.nd-catcard__head--link .nd-catcard__count').length"), "no counts in phone headers"

    # Scroll into the second card: its header sits at the top.
    top = page.evaluate_script("(() => { const card = document.querySelectorAll('section.nd-catcard')[1]; window.scrollTo(0, card.getBoundingClientRect().top + scrollY + 60); return Math.round(card.querySelector('.nd-catcard__head--toggle').getBoundingClientRect().top) })()")
    assert_equal 0, top, "the header sticks at the top while its rows scroll under it"

    toggle = find("section[data-key=fuel] .nd-catcard__toggle")
    assert_equal "true", toggle["aria-expanded"]
    assert_equal "Fuel and materials, 4 companies", toggle["aria-label"], "the count is in the button's name on phones"
    toggle.click
    assert_equal "false", toggle["aria-expanded"]
    assert_no_selector "section[data-key=fuel] a.nd-catcard__row", visible: true

    visit root_path
    assert_equal "false", find("section[data-key=fuel] .nd-catcard__toggle")["aria-expanded"], "the choice is remembered"
    click_on "Collapse all"
    assert_equal [ "false" ], all(".nd-catcard__toggle").map { |t| t["aria-expanded"] }.uniq, "every card closes"
    click_on "Expand all"
    assert_equal [ "true" ], all(".nd-catcard__toggle").map { |t| t["aria-expanded"] }.uniq, "every card opens"
    assert_button "Collapse all"
  end
end
