#!/usr/bin/env python3
"""draw_icon.py: the iPad app's icon picture, drawn from the site's vector icon, with Python's standard library only.

    python3 deck-app/tools/draw_icon.py [--svg site/icon.svg] [--out <png>] [--size 1024]

With no options it reads site/icon.svg and writes deck-app/Deck/Assets.xcassets/AppIcon.appiconset/icon1024.png.

Why: Apple wants the App Store icon as a full square, opaque, with no corners drawn in; iOS and the App Store round
the corners themselves, with their own corner shape. So the picture here is site/icon.svg's drawing with its ground
filling the whole square: the SVG's corner rounding (rx on the ground) is left out on purpose, and nothing else is
changed. The Windows icon (core/Tools/windows/make_ico.py) and the Desk film (desk-quickstart/film.js) are made from
this picture and round the corners themselves, as site/icon.svg has them.

What it reads from the SVG: its viewBox; the ground (the first <rect>, its fill); filled <circle>s; and <circle>s
stroked inside a <g> (fill none, stroke, stroke-width), drawn in document order, later over earlier. That is all
site/icon.svg uses; anything else in it stops the script, so a change to the drawing is not silently dropped.

How: each pixel's colour is the average of the colours at the points of a 16 by 16 grid inside it (so an edge pixel
is mixed in proportion to how much of each shape covers it, to within 1/256), worked out only for the pixels an edge
crosses; every other pixel is one colour. Colours are mixed as sRGB values, as a browser draws the SVG. The PNG is
8-bit RGB (no alpha channel), marked sRGB, not interlaced. The same input gives the same bytes on every machine.
"""
import math
import os
import struct
import sys
import xml.etree.ElementTree as ET
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SVG = os.path.join(REPO, "site", "icon.svg")
OUT = os.path.join(REPO, "deck-app", "Deck", "Assets.xcassets", "AppIcon.appiconset", "icon1024.png")
GRID = 16   # sample points across (and down) an edge pixel


def colour(text, where):
    text = (text or "").strip()
    if len(text) == 7 and text[0] == "#":
        return tuple(int(text[i:i + 2], 16) for i in (1, 3, 5))
    raise SystemExit(f"draw_icon: {where}: colour {text!r} is not #rrggbb")


def read_svg(path):
    """(viewBox width, height, ground colour, shapes); each shape (cx, cy, inner radius, outer radius, colour)."""
    root = ET.parse(path).getroot()
    ns = "{http://www.w3.org/2000/svg}"
    vb = [float(v) for v in root.get("viewBox", "").split()]
    if len(vb) != 4 or vb[0] or vb[1]:
        raise SystemExit(f"draw_icon: {path}: needs a viewBox of the form '0 0 w h'")
    width, height = vb[2], vb[3]
    ground, shapes = None, []

    def visit(node, stroke=None, width_=None, fill=None):
        for el in node:
            tag = el.tag.replace(ns, "")
            f = el.get("fill", fill)
            s = el.get("stroke", stroke)
            sw = float(el.get("stroke-width", width_)) if el.get("stroke-width", width_) is not None else None
            if tag == "g":
                visit(el, s, sw, f)
            elif tag == "rect":
                if ground is not None or shapes:
                    raise SystemExit(f"draw_icon: {path}: only the first shape may be a <rect> (the ground)")
                if float(el.get("x", 0)) or float(el.get("y", 0)) or float(el.get("width")) != width \
                        or float(el.get("height")) != height:
                    raise SystemExit(f"draw_icon: {path}: the ground <rect> must cover the whole viewBox")
                set_ground(colour(f, "the ground"))   # rx (the rounded corners) is left out on purpose
            elif tag == "circle":
                cx, cy, r = float(el.get("cx")), float(el.get("cy")), float(el.get("r"))
                if f and f != "none":
                    shapes.append((cx, cy, 0.0, r, colour(f, "a circle's fill")))
                if s and s != "none":
                    if sw is None:
                        raise SystemExit(f"draw_icon: {path}: a stroked circle has no stroke-width")
                    shapes.append((cx, cy, max(0.0, r - sw / 2), r + sw / 2, colour(s, "a circle's stroke")))
            else:
                raise SystemExit(f"draw_icon: {path}: <{tag}> is not something this script draws")

    def set_ground(c):
        nonlocal ground
        ground = c

    visit(root)
    if ground is None:
        raise SystemExit(f"draw_icon: {path}: no ground <rect>")
    return width, height, ground, shapes


def draw(width, height, ground, shapes, size):
    """size x size pixels, as rows of bytes (r, g, b per pixel)."""
    sx, sy = width / size, height / size          # SVG units per pixel
    half = 0.5 * math.hypot(sx, sy)                # from a pixel's centre to its corner, in SVG units
    # Every edge, as (cx, cy, radius): a pixel whose centre is further than `half` from all of them is one colour.
    edges = sorted({(cx, cy, r) for cx, cy, a, b, _ in shapes for r in (a, b) if r > 0})
    centres = sorted({(cx, cy) for cx, cy, _, _, _ in shapes})
    radii = {c: sorted(r for (x, y, r) in edges if (x, y) == c) for c in centres}
    top = list(reversed(shapes))

    def at(px, py):   # the colour at one point: the last-drawn shape that covers it, else the ground
        for cx, cy, a, b, c in top:
            d2 = (px - cx) ** 2 + (py - cy) ** 2
            if a * a <= d2 <= b * b:
                return c
        return ground

    def near_edge(px, py):
        for (cx, cy) in centres:
            d = math.hypot(px - cx, py - cy)
            for r in radii[(cx, cy)]:
                if abs(d - r) <= half:
                    return True
        return False

    offsets = [(i + 0.5) / GRID for i in range(GRID)]
    rows = []
    for y in range(size):
        line = bytearray()
        for x in range(size):
            cxp, cyp = (x + 0.5) * sx, (y + 0.5) * sy
            if not near_edge(cxp, cyp):
                line += bytes(at(cxp, cyp))
                continue
            r = g = b = 0
            for oy in offsets:
                py = (y + oy) * sy
                for ox in offsets:
                    c = at((x + ox) * sx, py)
                    r += c[0]; g += c[1]; b += c[2]
            n = GRID * GRID
            line += bytes(((r + n // 2) // n, (g + n // 2) // n, (b + n // 2) // n))
        rows.append(bytes(line))
    return rows


def write_png(path, rows):
    size = len(rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    raw = b"".join(b"\x00" + line for line in rows)
    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))   # 8-bit RGB, no alpha
            + chunk(b"sRGB", b"\x00")                                              # sRGB, perceptual
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(data)


def main(argv):
    svg, out, size = SVG, OUT, 1024
    i = 1
    while i < len(argv):
        if argv[i] in ("--svg", "--out", "--size") and i + 1 < len(argv):
            if argv[i] == "--svg":
                svg = argv[i + 1]
            elif argv[i] == "--out":
                out = argv[i + 1]
            else:
                size = int(argv[i + 1])
            i += 2
        else:
            raise SystemExit("usage: draw_icon.py [--svg site/icon.svg] [--out <png>] [--size 1024]")
    width, height, ground, shapes = read_svg(svg)
    if width != height:
        raise SystemExit(f"draw_icon: {svg} is {width} by {height}; an icon is square")
    write_png(out, draw(width, height, ground, shapes, size))
    print(f"draw_icon: {out}: {size} x {size}, RGB, no alpha, from {os.path.relpath(svg, REPO)} "
          f"({len(shapes)} shapes on a full-square ground)")


if __name__ == "__main__":
    main(sys.argv)
