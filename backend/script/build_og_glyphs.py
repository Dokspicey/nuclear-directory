"""Export the glyph outlines the link-preview cards are drawn with (#245).

Each page's card is laid out by LinkCard (app/models/link_card.rb) as SVG
paths and rasterized with libvips, so the server needs no fonts and no
browser. This writes, for each face, its units per em and, for each
character, its advance width and its outline as SVG path data in font units
(y up), from the site's own font files.

Needs fonttools with woff2 support (pip install "fonttools[woff]==4.54.1").
From backend/:
  python script/build_og_glyphs.py app/assets/fonts lib/link_card/glyphs.json
Run it again when the fonts change. The same inputs give the same file.
"""
import json
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools.pens.svgPathPen import SVGPathPen

src, out = sys.argv[1], sys.argv[2]

# Printable ASCII, Latin-1 (accented names) and the punctuation cards use.
CHARS = [chr(c) for c in range(0x20, 0x7F)] + [chr(c) for c in range(0xA0, 0x100)] + list("‘’“”–—…•")


def mono(weight):
    return instancer.instantiateVariableFont(TTFont(f"{src}/roboto-mono-latin.woff2"), {"wght": weight})


FACES = {
    "anton": TTFont(f"{src}/anton-latin.woff2"),
    "mono": mono(400),
    "mono_medium": mono(500),
    "serif": instancer.instantiateVariableFont(TTFont(f"{src}/roboto-serif-latin.woff2"), {"wght": 400}),
}


def export(font):
    glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
    found = {}
    for char in CHARS:
        name = cmap.get(ord(char))
        if name is None:
            continue
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(pen)
        found[char] = [glyphs[name].width, pen.getCommands()]
    hhea = font["hhea"]
    return {"upm": font["head"].unitsPerEm, "ascent": hhea.ascent, "descent": hhea.descent, "glyphs": found}


with open(out, "w") as file:
    json.dump({name: export(font) for name, font in FACES.items()}, file, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
print("ok")
