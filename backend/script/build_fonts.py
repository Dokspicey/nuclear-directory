"""Subset the site's fonts to Latin woff2 and draw the wordmark as SVG (#90).

Sources (SIL Open Font License, licences in app/assets/fonts/OFL-*.txt), from
https://github.com/google/fonts: ofl/anton/Anton-Regular.ttf,
ofl/robotoserif/RobotoSerif[GRAD,opsz,wdth,wght].ttf saved as RobotoSerif.ttf,
ofl/robotomono/RobotoMono[wght].ttf saved as RobotoMono.ttf.

Needs fonttools with woff2 support (pip install "fonttools[woff]==4.54.1").
Usage:
  python build_fonts.py <source dir> app/assets/fonts <wordmark.svg>
then paste the SVG into app/views/shared/_wordmark.html.erb.
"""
import io
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

src, out, wordmark_out = sys.argv[1], sys.argv[2], sys.argv[3]

# Google Fonts' "latin" range.
LATIN = ("U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,"
         "U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD")


def subset_to_woff2(font, path):
    # Round-trip through bytes so the subsetter sees a freshly compiled font.
    buffer = io.BytesIO()
    font.save(buffer)
    buffer.seek(0)
    font = TTFont(buffer, recalcTimestamp=False)
    options = subset.Options()
    options.flavor = "woff2"
    options.layout_features = ["kern", "liga", "calt", "tnum", "lnum", "pnum", "onum", "case", "ccmp", "locl", "mark", "mkmk"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    sub = subset.Subsetter(options)
    sub.populate(unicodes=subset.parse_unicodes(LATIN))
    sub.subset(font)
    font.flavor = "woff2"
    font.save(path)


# Roboto Serif: weights 400-700 stay variable; optical size is fixed at 14 (body text), grade
# and width are fixed at their defaults.
serif = TTFont(f"{src}/RobotoSerif.ttf", recalcTimestamp=False)
serif = instancer.instantiateVariableFont(serif, {"wght": (400, 700), "opsz": 14, "GRAD": 0, "wdth": 100})
subset_to_woff2(serif, f"{out}/roboto-serif-latin.woff2")

# Roboto Mono: 400-500.
mono = TTFont(f"{src}/RobotoMono.ttf", recalcTimestamp=False)
mono = instancer.instantiateVariableFont(mono, {"wght": (400, 500)})
subset_to_woff2(mono, f"{out}/roboto-mono-latin.woff2")

# Anton: one weight.
subset_to_woff2(TTFont(f"{src}/Anton-Regular.ttf", recalcTimestamp=False), f"{out}/anton-latin.woff2")

# The wordmark: "NUCLEAR DIRECTORY" in Anton with 0.01em tracking, cropped
# to cap height so it lines up with text set beside it.
anton = TTFont(f"{src}/Anton-Regular.ttf")
glyphs = anton.getGlyphSet()
cmap = anton.getBestCmap()
upm = anton["head"].unitsPerEm
cap = anton["OS/2"].sCapHeight
tracking = 0.01 * upm
x = 0
paths = []
for char in "NUCLEAR DIRECTORY":
    name = cmap[ord(char)]
    pen = SVGPathPen(glyphs)
    # Flip y (fonts draw upwards) and move each glyph along the line.
    glyphs[name].draw(TransformPen(pen, (1, 0, 0, -1, x, cap)))
    if pen.getCommands():
        paths.append(pen.getCommands())
    x += glyphs[name].width + tracking
width = round(x - tracking)
svg = (f'<svg class="nd-wordmark__svg" viewBox="0 0 {width} {cap}" aria-hidden="true" focusable="false" '
       f'xmlns="http://www.w3.org/2000/svg"><path fill="currentColor" d="{" ".join(paths)}"/></svg>')
open(wordmark_out, "w").write(svg)
print(f"upm={upm} cap={cap} width={width} ratio={width / cap:.4f} cap/upm={cap / upm:.4f}")
