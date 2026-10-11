"""Draw the site icon: a nucleus with two crossed orbits, paper on ink. The
one place an atom is allowed (DESIGN.md, Iconography).

Two steps, from backend/. First the SVGs:
  python script/build_site_icon.py svg public/icon.svg icon-maskable.svg
then a 1024px PNG of each (macOS):
  qlmanage -t -s 1024 -o . public/icon.svg icon-maskable.svg
and the sized files, with Pillow (pip install Pillow):
  python script/build_site_icon.py png icon.svg.png icon-maskable.svg.png public
That writes favicon.ico (16, 32, 48), apple-touch-icon.png (180),
icon-192.png, icon-512.png and icon-maskable-512.png.
"""
import sys

PAPER, INK = "#f7f7f5", "#121212"  # tokens.css --nd-paper and --nd-ink, light theme


def svg(scale=1.0):
    # The maskable icon keeps the atom inside the central safe circle (80%)
    # that Android may crop to, so it's drawn smaller on the same square.
    atom = (f'<g fill="none" stroke="{PAPER}" stroke-width="40">'
            f'<ellipse cx="256" cy="256" rx="200" ry="84" transform="rotate(45 256 256)"/>'
            f'<ellipse cx="256" cy="256" rx="200" ry="84" transform="rotate(-45 256 256)"/></g>'
            f'<circle cx="256" cy="256" r="56" fill="{PAPER}"/>')
    if scale != 1.0:
        offset = 256 * (1 - scale)
        atom = f'<g transform="translate({offset:g} {offset:g}) scale({scale:g})">{atom}</g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
            f'<rect width="512" height="512" fill="{INK}"/>{atom}</svg>\n')


def pngs(icon_png, maskable_png, out):
    from PIL import Image

    icon = Image.open(icon_png).convert("RGB")
    maskable = Image.open(maskable_png).convert("RGB")

    def sized(image, size):
        return image.resize((size, size), Image.LANCZOS)

    sized(icon, 180).save(f"{out}/apple-touch-icon.png", optimize=True)
    sized(icon, 192).save(f"{out}/icon-192.png", optimize=True)
    sized(icon, 512).save(f"{out}/icon-512.png", optimize=True)
    sized(maskable, 512).save(f"{out}/icon-maskable-512.png", optimize=True)
    sized(icon, 256).save(f"{out}/favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])


if __name__ == "__main__":
    if sys.argv[1] == "svg":
        open(sys.argv[2], "w").write(svg())
        open(sys.argv[3], "w").write(svg(scale=0.8))
    else:
        pngs(*sys.argv[2:5])
