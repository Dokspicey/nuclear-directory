"""Draw the default link-preview image (#90) as an SVG of outlines, so it
renders the same anywhere without the fonts installed.

Same font sources and fonttools as script/build_fonts.py. From backend/:
  python script/build_og_image.py <font source dir> og-default.svg
  qlmanage -t -s 1200 -o . og-default.svg            # macOS: a 1200x1200 PNG
  sips --cropToHeightWidth 630 1200 og-default.svg.png
then save it as app/assets/images/og-default.png.
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

src, out = sys.argv[1], sys.argv[2]
PAPER, INK, MUTED, RULE = "#f7f7f5", "#121212", "#57575a", "#e2e2df"

anton = TTFont(f"{src}/Anton-Regular.ttf")
serif = instancer.instantiateVariableFont(TTFont(f"{src}/RobotoSerif.ttf"), {"wght": 400, "opsz": 28, "GRAD": 0, "wdth": 100})
mono = instancer.instantiateVariableFont(TTFont(f"{src}/RobotoMono.ttf"), {"wght": 400})


def text_path(font, text, x, baseline, size, tracking=0.0):
    """Outlines for one line of text, its left edge at x and baseline at y."""
    glyphs, cmap, upm = font.getGlyphSet(), font.getBestCmap(), font["head"].unitsPerEm
    scale = size / upm
    pen = SVGPathPen(glyphs)
    cursor = 0
    for char in text:
        name = cmap.get(ord(char), ".notdef")
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x + cursor * scale, baseline)))
        cursor += glyphs[name].width + tracking * upm
    return pen.getCommands(), cursor * scale


parts = []
# Wordmark, Anton uppercase, with the site's 0.01em tracking.
d, _ = text_path(anton, "NUCLEAR DIRECTORY", 80, 196, 96, tracking=0.01)
parts.append(f'<path fill="{INK}" d="{d}"/>')
# A rule under it, as on the site's section headings.
parts.append(f'<rect x="80" y="244" width="1040" height="3" fill="{INK}"/>')
# The one-line promise, in Roboto Serif (VOICE.md: says what it is).
for i, line in enumerate([ "Who makes the fuel, builds the reactors,", "runs the plants, buys the power and funds it." ]):
    d, _ = text_path(serif, line, 80, 338 + i * 58, 44)
    parts.append(f'<path fill="{INK}" d="{d}"/>')
# The colophon, in mono.
d, _ = text_path(mono, "Every fact links to its source  ·  nuclear-directory.org", 80, 548, 26)
parts.append(f'<path fill="{MUTED}" d="{d}"/>')

# Drawn centred on a 1200x1200 canvas: QuickLook renders squares without
# rescaling, and a centre crop to 1200x630 then gives the card exactly.
svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1200" viewBox="0 0 1200 1200">'
       f'<rect width="1200" height="1200" fill="{PAPER}"/><g transform="translate(0,285)">'
       f'<rect x="0.5" y="0.5" width="1199" height="629" fill="none" stroke="{RULE}"/>'
       + "".join(parts) + "</g></svg>")
open(out, "w").write(svg)
print("ok")
