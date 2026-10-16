# Text for link cards (#245), measured and drawn from glyph outlines
# exported from the site's fonts (lib/link_card/glyphs.json, written by
# script/build_og_glyphs.py). Faces: :anton, :mono, :mono_medium, :serif.
# tracking is letter-spacing in ems, as in CSS. No kerning, as in the
# site's wordmark.
module LinkCard::Font
  GLYPHS = Rails.root.join("lib/link_card/glyphs.json")
  ELLIPSIS = "…"

  def self.faces = @faces ||= JSON.parse(GLYPHS.read)

  def self.face(font) = faces.fetch(font.to_s)

  # A character the face lacks is drawn as "?".
  def self.glyph(face, char) = face["glyphs"][char] || face["glyphs"]["?"]

  def self.width(text, font:, size:, tracking: 0)
    face = face(font)
    scale = size.to_f / face["upm"]
    text.each_char.sum { |char| glyph(face, char)[0] * scale + tracking * size }
  end

  # The baseline that centres a line's ascent and descent on center.
  def self.centered_baseline(center, font:, size:, **)
    face = face(font)
    (center + (face["ascent"] + face["descent"]) / 2.0 * size / face["upm"]).round(2)
  end

  # One <g> of glyph paths, its left edge at x and baseline at baseline.
  def self.path(text, x, baseline, font:, size:, fill:, tracking: 0)
    face = face(font)
    scale = size.to_f / face["upm"]
    cursor = x.to_f
    glyphs = text.each_char.filter_map do |char|
      advance, outline = glyph(face, char)
      drawn = %(<path transform="translate(#{cursor.round(2)} #{baseline}) scale(#{scale.round(6)} #{(-scale).round(6)})" d="#{outline}"/>) if outline.present?
      cursor += advance * scale + tracking * size
      drawn
    end
    %(<g fill="#{fill}">#{glyphs.join}</g>)
  end

  # Words in lines no wider than max, or nil when a word alone is wider.
  # hard: such a word gets a line of its own instead (cut later with fit).
  def self.wrap(text, max, hard: false, **style)
    lines = []
    text.split.each do |word|
      return nil if !hard && width(word, **style) > max

      if lines.any? && width("#{lines.last} #{word}", **style) <= max
        lines[-1] = "#{lines.last} #{word}"
      else
        lines << word
      end
    end
    lines
  end

  # The text, or as much of it as fits with "…" after it: whole words when a
  # word boundary fits, else characters.
  def self.fit(text, max, force_ellipsis: false, **style)
    return text if !force_ellipsis && width(text, **style) <= max

    words = text.split
    words.pop until words.size <= 1 || width("#{words.join(' ')}#{ELLIPSIS}", **style) <= max
    # "Susquehanna Nuclear…", not "Susquehanna Nuclear,…".
    return "#{words.join(' ').sub(/[[:punct:]]+\z/, '')}#{ELLIPSIS}" if words.size > 1 || (words.any? && width("#{words.first}#{ELLIPSIS}", **style) <= max)

    cut = text.dup
    cut = cut[0...-1].rstrip until cut.empty? || width("#{cut}#{ELLIPSIS}", **style) <= max
    "#{cut}#{ELLIPSIS}"
  end
end
