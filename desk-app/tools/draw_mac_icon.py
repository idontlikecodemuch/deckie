#!/usr/bin/env python3
"""draw_mac_icon.py: Deckie Desk for Mac's app icon, drawn from the site's vector icon, with Python's standard library.

    python3 desk-app/tools/draw_mac_icon.py      the ten pictures of desk-app/Desk/Assets.xcassets/AppIcon.appiconset

Desk for Mac uses the same picture as Desk for Windows: the plain record with no word on it (decided Nov 25, 2026;
the iPad app's icon adds "Booth", Desk's never carries a word). The record is drawn here from site/icon.svg at each
size by deck-app/tools/draw_icon.py's own drawing code, not scaled from icon-base1024.png, so every size is as sharp
as it can be and the look is the base picture's exactly: the ground #160f2b, the orange record, the violet label.

The shape is Apple's for a macOS app icon (the macOS 11 and later template): on a transparent 1024 by 1024 canvas, a
square of 824 centred (100 clear on each side), its corners rounded with Apple's continuous corner (a curve that eases
into the straight edge rather than a quarter circle meeting it) of radius 185.4, and under it the template's shadow:
black at 30 percent, 10 down, blurred about 10 (a Gaussian of about 5 standard deviation). Every number is in the
1024 canvas and scaled to each size; the record fills the shape as site/icon.svg fills its square. At 128 pixels and
below the shape's edges are put on whole pixels (at 16 it is 12 pixels square, 2 clear), so they stay crisp.

How: the record's colours come from draw_icon.draw (each edge pixel mixed from a grid of points; a finer grid at the
small sizes, where many rings share a pixel); the shape's coverage from draw_icon.fill (exact across, 16 lines a
pixel down); the shadow is the shape's coverage moved down and blurred with draw_icon.blur. The picture is laid over
the shadow and written as an 8-bit RGBA PNG marked sRGB. The same input gives the same bytes on every machine.
"""
import json
import math
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, "deck-app", "tools"))
import draw_icon  # noqa: E402  (the iPad's and Windows' icon tools; their drawing code is reused as it is)

OUT = os.path.join(REPO, "desk-app", "Desk", "Assets.xcassets", "AppIcon.appiconset")
CANVAS = 1024.0
INSET = 100.0                 # the shape: 824 square, 100 clear on each side (Apple's macOS template)
RADIUS = 185.4                # its continuous corner
SHADOW = (10.0, 5.0, 0.30)    # the template's shadow: 10 down, a Gaussian of about 5 standard deviation, 30 percent
# The macOS icon set: each point size at 1x and 2x.
POINTS = (16, 32, 128, 256, 512)

# Apple's continuous corner, as the shape of the top-right corner from the top edge to the right edge: Bezier curves
# in units of the radius, each point given as (distance in from the right edge, distance down from the top edge).
# These are the widely published measurements of the corner UIKit and AppKit draw.
CORNER = [
    (1.52866483, 0.0),
    ((1.08849323, 0.0), (0.86840689, 0.0), (0.63149399, 0.07491100)),
    ((0.37282392, 0.16905227), (0.16905227, 0.37282392), (0.07491100, 0.63149399)),
    ((0.0, 0.86840689), (0.0, 1.08849323), (0.0, 1.52866483)),
]


def frame(size):
    """Where the shape sits in a size-by-size picture: (its inset, its side), in pixels. At 128 and below its edges are
    put on whole pixels (the inset rounded to the nearest pixel), so a small icon's edge is one crisp line rather than
    a row of half-covered pixels; the record and the corners are scaled with it. Above 128 the template's numbers are
    used as they are."""
    inset = INSET * size / CANVAS
    if size <= 128:
        inset = float(round(inset))
    return inset, size - 2 * inset


def outline(size, dy=0.0, steps=24):
    """The shape's outline as one polygon in pixels of a size-by-size picture, moved down by dy (in pixels)."""
    inset, side = frame(size)
    x1, y0 = inset + side, inset
    r = RADIUS * side / (CANVAS - 2 * INSET)
    c = size / 2

    def at(a, b):
        return (x1 - a * r, y0 + b * r)
    pts = [at(*CORNER[0])]
    cur = CORNER[0]
    for p1, p2, p3 in CORNER[1:]:
        for s in range(1, steps + 1):
            t = s / steps
            u = 1 - t
            a = u ** 3 * cur[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0]
            b = u ** 3 * cur[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]
            pts.append(at(a, b))
        cur = p3
    # The other three corners: the first turned a quarter about the centre each time (clockwise, y down); the
    # straight edges join them.
    poly = []
    quarter = list(pts)
    for _ in range(4):
        poly += quarter
        quarter = [(c - (y - c), c + (x - c)) for x, y in quarter]
    return [(x, y + dy) for x, y in poly]


def record(size):
    """The record, as draw_icon draws it, placed in the shape's square: a list of RGB bytearrays, size by size."""
    width, height, ground, shapes = draw_icon.read_svg(draw_icon.SVG)
    if width != height:
        raise SystemExit(f"draw_mac_icon: {draw_icon.SVG} is {width} by {height}; an icon is square")
    inset, side = frame(size)
    px = CANVAS / size                       # canvas units a pixel
    k = side * px / width                    # SVG units to canvas units
    placed = [(inset * px + cx * k, inset * px + cy * k, a * k, b * k, col) for cx, cy, a, b, col in shapes]
    # Where many rings share a pixel, a finer grid of points keeps their mix even (the rings are 11 units wide with
    # 11 between, so at 16 pixels some 40 of them would cross each pixel's grid of 16 points).
    grid = draw_icon.GRID
    draw_icon.GRID = 64 if size <= 32 else 32 if size <= 128 else grid
    try:
        return draw_icon.draw(CANVAS, CANVAS, ground, placed, size)
    finally:
        draw_icon.GRID = grid


def gaussian_radius(sigma):
    """The radius of the three box blurs draw_icon.blur makes, closest to a Gaussian of this standard deviation."""
    # Three boxes of 2r+1 pixels have a variance of r(r+1); the nearest whole r, none below 1 pixel of sigma.
    return int(round((math.sqrt(1 + 4 * sigma * sigma) - 1) / 2))


def picture(size):
    """The icon at size by size pixels, as a list of RGBA bytearrays."""
    k = size / CANVAS
    art = record(size)
    shape = draw_icon.fill([outline(size)], size)
    shadow = draw_icon.fill([outline(size, dy=SHADOW[0] * k)], size)
    radius = gaussian_radius(SHADOW[1] * k)
    if radius >= 1:
        shadow = draw_icon.blur(shadow, radius)
    rows = []
    for y in range(size):
        line = bytearray()
        src = art[y]
        for x in range(size):
            a = shape[y][x]
            s = SHADOW[2] * shadow[y][x] * (1 - a)           # the shadow shows only where the shape does not cover
            out = a + s
            if out <= 0.0:
                line += b"\x00\x00\x00\x00"
                continue
            i = 3 * x
            # straight (not premultiplied) alpha: the shape's colour over black, divided back by the total cover
            line += bytes((int(src[i] * a / out + 0.5), int(src[i + 1] * a / out + 0.5),
                           int(src[i + 2] * a / out + 0.5), int(out * 255 + 0.5)))
        rows.append(line)
    return rows


def write_png(path, rows):
    size = len(rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    raw = b"".join(b"\x00" + bytes(line) for line in rows)
    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))   # 8-bit RGBA
            + chunk(b"sRGB", b"\x00")                                              # sRGB, perceptual
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(data)


def main(argv):
    if len(argv) > 1:
        raise SystemExit("usage: draw_mac_icon.py   (writes desk-app/Desk/Assets.xcassets/AppIcon.appiconset)")
    os.makedirs(OUT, exist_ok=True)
    images, made = [], {}
    for pt in POINTS:
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            if px not in made:
                made[px] = picture(px)
            write_png(os.path.join(OUT, name), made[px])
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
            print(f"draw_mac_icon: {name}: {px} x {px}, RGBA")
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    with open(os.path.join(os.path.dirname(OUT), "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv)
