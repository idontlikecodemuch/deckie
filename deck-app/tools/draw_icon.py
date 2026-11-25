#!/usr/bin/env python3
"""draw_icon.py: Deckie's icon pictures, drawn from the site's vector icon, with Python's standard library only.

    python3 deck-app/tools/draw_icon.py                  both committed pictures, as shipped:
        deck-app/tools/icon-base1024.png                 the plain icon, no word (Desk's Windows icon, the Desk film)
        deck-app/Deck/Assets.xcassets/AppIcon.appiconset/icon1024.png   the iPad app's icon: the plain one + "Booth"
    python3 deck-app/tools/draw_icon.py --layout a --angle 10 [--font sans] [--size 152] [--out <png>]
        one picture: a candidate layout (below), to look at or to ship (with no --out it replaces the iPad's icon)

Layouts ("Booth" is set in the brand's script face, Pacifico, from site/fonts/pacifico.woff2, as the font's own
outlines; --font sans sets it in the site's plain face, Inter, for comparison only):
    base   the plain icon: site/icon.svg with its ground filling the whole square
    a      the word large across the record, flat off-white, its ink centred on the icon (shipped, at 10 degrees)
    a-outline the same with a 3-unit hairline in the ground's colour round the letters (an alternative, not shipped)
    a-shadow  the same with a soft dark edge, lower and right of centre (the first sheet's A, 13 degrees)
    bthe record moved up and made smaller, the word beneath it on the dark ground, its end over the record's rim
    c      the word on a dark sticker strip laid across the lower half of the record, overlapping its edge
The word always rises from left to right (--angle, in degrees; each layout has its own default). The shipped layout
and angle are SHIP below.

Why a full square: Apple wants the App Store icon opaque, with no corners drawn in; iOS and the App Store round the
corners themselves. So the SVG's corner rounding (rx on the ground) is left out on purpose, and the word is kept
inside a margin clear of the corners Apple's mask cuts (the script checks this and stops if it is not).

What it reads from the SVG: its viewBox; the ground (the first <rect>, its fill); filled <circle>s; and <circle>s
stroked inside a <g> (fill none, stroke, stroke-width), drawn in document order. That is all site/icon.svg uses;
anything else stops the script, so a change to the drawing is not silently dropped.

How: the record's pixels are mixed by how much of each shape covers them (a 16 by 16 grid of points, only where an
edge crosses); the word's outlines (woff2_outlines.py) are filled with the non-zero rule, 16 lines a pixel down and
exact coverage across. Colours are mixed as sRGB values, as a browser does. The PNG is 8-bit RGB (no alpha channel),
marked sRGB. The same input gives the same bytes on every machine. Brotli, which unpacks the font file, is run as
the `brotli` program (see woff2_outlines.py); the base picture needs no font.
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
BASE_OUT = os.path.join(HERE, "icon-base1024.png")
IPAD_OUT = os.path.join(REPO, "deck-app", "Deck", "Assets.xcassets", "AppIcon.appiconset", "icon1024.png")
FONTS = {"script": os.path.join(REPO, "site", "fonts", "pacifico.woff2"),
         "sans": os.path.join(REPO, "site", "fonts", "inter.woff2")}
GRID = 16                      # sample points across (and down) an edge pixel of the record
WORD = "Booth"
INK = (0xF2, 0xED, 0xF9)       # the site's off-white (--tx), the colour "Deckie" is written in on the site
SHIP = ("a", 10.0)             # the layout and angle of the iPad app's icon (chosen Nov 25, 2026; see the README)
# Each layout, in the SVG's 1024 units: where the record sits (scale about its centre, then moved down by dy), the
# word's size (font size), the point the word is centred on (its outline's box before the slant, or with ink=True
# the box of the ink as drawn, after the slant), its default angle, and its effects.
LAYOUTS = {
    "a": dict(record=(1.0, 0), font=318, centre=(512, 512), angle=10.0, ink=True),
    "a-outline": dict(record=(1.0, 0), font=318, centre=(512, 512), angle=10.0, ink=True, outline=3),
    "a-shadow": dict(record=(1.0, 0), font=318, centre=(520, 548), angle=13.0, halo=True),
    "b": dict(record=(0.77, -100), font=246, centre=(534, 796), angle=13.0, halo=True),
    "c": dict(record=(1.0, 0), font=206, centre=(560, 772), angle=12.0, strip=True),
}
SAFE = (230.0, 40.0)           # Apple's corner radius in 1024 (about), and the margin the word keeps inside it


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
    found = {"ground": None}
    shapes = []

    def visit(node, stroke=None, width_=None, fill=None):
        for el in node:
            tag = el.tag.replace(ns, "")
            f = el.get("fill", fill)
            s = el.get("stroke", stroke)
            w = el.get("stroke-width", width_)
            sw = float(w) if w is not None else None
            if tag == "g":
                visit(el, s, sw, f)
            elif tag == "rect":
                if found["ground"] is not None or shapes:
                    raise SystemExit(f"draw_icon: {path}: only the first shape may be a <rect> (the ground)")
                if float(el.get("x", 0)) or float(el.get("y", 0)) or float(el.get("width")) != width \
                        or float(el.get("height")) != height:
                    raise SystemExit(f"draw_icon: {path}: the ground <rect> must cover the whole viewBox")
                found["ground"] = colour(f, "the ground")   # rx (the rounded corners) is left out on purpose
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

    visit(root)
    if found["ground"] is None:
        raise SystemExit(f"draw_icon: {path}: no ground <rect>")
    return width, height, found["ground"], shapes


def place(shapes, width, height, scale, dy):
    """The record's shapes scaled about the picture's centre and moved down by dy (SVG units)."""
    mx, my = width / 2, height / 2
    return [(mx + (cx - mx) * scale, my + (cy - my) * scale + dy, a * scale, b * scale, c)
            for cx, cy, a, b, c in shapes]


def draw(width, height, ground, shapes, size):
    """size x size pixels, as a list of bytearrays (r, g, b per pixel)."""
    sx, sy = width / size, height / size          # SVG units per pixel
    half = 0.5 * math.hypot(sx, sy)                # from a pixel's centre to its corner, in SVG units
    centres = sorted({(cx, cy) for cx, cy, _, _, _ in shapes})
    radii = {c: sorted({r for (x, y, a, b, _) in shapes if (x, y) == c for r in (a, b) if r > 0}) for c in centres}
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
    n = GRID * GRID
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
                    r += c[0]
                    g += c[1]
                    b += c[2]
            line += bytes(((r + n // 2) // n, (g + n // 2) // n, (b + n // 2) // n))
        rows.append(line)
    return rows


# --- The word -------------------------------------------------------------------------------------------------------

def flatten(contour, steps=12):
    """A TrueType contour (quadratic, with implied on-curve points between two off-curve ones) as a polygon."""
    pts = list(contour)
    if not pts:
        return []
    if not pts[0][2]:   # start on an on-curve point
        k = next((i for i, p in enumerate(pts) if p[2]), None)
        if k is None:
            a, b = pts[0], pts[1]
            pts.insert(0, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, True))
        else:
            pts = pts[k:] + pts[:k]
    out = [(pts[0][0], pts[0][1])]
    n = len(pts)
    i = 1
    cur = pts[0]
    while i <= n:
        p = pts[i % n]
        if p[2]:
            out.append((p[0], p[1]))
            cur = p
            i += 1
            continue
        q = pts[(i + 1) % n]
        end = q if q[2] else ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2, True)
        for s in range(1, steps + 1):
            t = s / steps
            u = 1 - t
            out.append((u * u * cur[0] + 2 * u * t * p[0] + t * t * end[0],
                        u * u * cur[1] + 2 * u * t * p[1] + t * t * end[1]))
        cur = end
        i += 2 if q[2] else 1
    return out


def fill(polys, size, sub=16):
    """Coverage (0 to 1) of polygons in pixel space, non-zero rule, as a list of rows of floats."""
    buckets = [[] for _ in range(size * sub)]
    for poly in polys:
        for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
            if y0 == y1:
                continue
            d = 1 if y1 > y0 else -1
            ya, yb = (y0, y1) if y0 < y1 else (y1, y0)
            first = max(0, math.ceil(ya * sub - 0.5))
            last = min(size * sub - 1, math.ceil(yb * sub - 0.5) - 1)
            for k in range(first, last + 1):
                y = (k + 0.5) / sub
                buckets[k].append((x0 + (y - y0) * (x1 - x0) / (y1 - y0), d))
    mask = []
    w = 1.0 / sub
    for row in range(size):
        acc = [0.0] * (size + 2)
        diff = [0.0] * (size + 2)
        for k in range(row * sub, row * sub + sub):
            xs = sorted(buckets[k])
            wind = 0
            for j, (x, d) in enumerate(xs):
                before = wind
                wind += d
                if before == 0 and wind != 0:
                    start = x
                elif before != 0 and wind == 0:
                    a, b = max(0.0, start), min(float(size), x)
                    if b <= a:
                        continue
                    ia, ib = int(a), int(b)
                    if ia == ib:
                        acc[ia] += (b - a) * w
                    else:
                        acc[ia] += (ia + 1 - a) * w
                        diff[ia + 1] += w
                        diff[ib] -= w
                        acc[ib] += (b - ib) * w
        run = 0.0
        line = []
        for x in range(size):
            run += diff[x]
            line.append(min(1.0, acc[x] + run))
        mask.append(line)
    return mask


def blur(mask, radius):
    """Three box blurs (close to a Gaussian) of a coverage mask, radius in pixels."""
    if radius < 1:
        return mask
    size = len(mask)
    r = int(radius)
    out = [list(line) for line in mask]
    for _ in range(3):
        for horizontal in (True, False):
            src = out if horizontal else [list(c) for c in zip(*out)]
            res = []
            for line in src:
                pre = [0.0]
                for v in line:
                    pre.append(pre[-1] + v)
                res.append([(pre[min(size, i + r + 1)] - pre[max(0, i - r)]) / (2 * r + 1) for i in range(size)])
            out = res if horizontal else [list(c) for c in zip(*res)]
    return out


def grow(mask, radius):
    """The mask grown by `radius` pixels (a round pen: each pixel takes the most of any pixel within the radius)."""
    size = len(mask)
    r = int(math.ceil(radius))
    offs = [(dx, dy) for dy in range(-r, r + 1) for dx in range(-r, r + 1) if dx * dx + dy * dy <= radius * radius]
    out = [list(line) for line in mask]
    rows = [y for y, line in enumerate(mask) if any(v > 0 for v in line)]
    if not rows:
        return out
    for y in range(max(0, rows[0] - r), min(size, rows[-1] + r + 1)):
        for x in range(size):
            best = 0.0
            for dx, dy in offs:
                yy, xx = y + dy, x + dx
                if 0 <= yy < size and 0 <= xx < size:
                    v = mask[yy][xx]
                    if v > best:
                        best = v
                        if best >= 1.0:
                            break
            out[y][x] = best
    return out


def word_polys(font, size, centre, angle, scale, ink_centre=False):
    """The word's outlines as pixel-space polygons: `size` px font size, its box centred on `centre`, risen by angle."""
    sys.path.insert(0, HERE)
    import woff2_outlines
    upem, contours, advance, _ = woff2_outlines.words(FONTS[font], WORD)
    k = size / upem
    flat = [flatten(c) for c in contours]
    xs = [x for p in flat for x, _ in p]
    ys = [y for p in flat for _, y in p]
    mx, my = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    th = math.radians(angle)
    cos, sin = math.cos(th), math.sin(th)
    polys = []
    for p in flat:
        out = []
        for x, y in p:
            X, Y = (x - mx) * k, -(y - my) * k          # font units (y up) to picture units (y down), box-centred
            out.append(((centre[0] + X * cos + Y * sin) * scale, (centre[1] - X * sin + Y * cos) * scale))
        polys.append(out)
    if ink_centre:   # the box of the ink as drawn (after the slant), centred on `centre`
        xs = [x for p in polys for x, _ in p]
        ys = [y for p in polys for _, y in p]
        dx = centre[0] * scale - (min(xs) + max(xs)) / 2
        dy = centre[1] * scale - (min(ys) + max(ys)) / 2
        polys = [[(x + dx, y + dy) for x, y in p] for p in polys]
    return polys


def strip_poly(polys, angle, scale, pad=(46, 26)):
    """A rounded strip (a sticker) around the word, along its slant."""
    th = math.radians(angle)
    cos, sin = math.cos(th), math.sin(th)
    pts = [p for poly in polys for p in poly]
    # the word's box in its own frame (unrotated)
    us = [x * cos - y * sin for x, y in pts]
    vs = [x * sin + y * cos for x, y in pts]
    u0, u1 = min(us) - pad[0] * scale, max(us) + pad[0] * scale
    v0, v1 = min(vs) - pad[1] * scale, max(vs) + pad[1] * scale
    r = (v1 - v0) / 2
    outline = []
    for cu, a0 in ((u1 - r, -90), (u0 + r, 90)):
        for s in range(0, 37):
            a = math.radians(a0 + s * 5)
            outline.append((cu + r * math.cos(a), (v0 + v1) / 2 - r * math.sin(a)))
    return [[(u * cos + v * sin, -u * sin + v * cos) for u, v in outline]]


def check_safe(mask, size):
    """Stop if anything of the word lies outside the rounded square Apple's mask leaves, less a margin."""
    radius, margin = SAFE[0] * size / 1024, SAFE[1] * size / 1024
    lo, hi = radius, size - radius
    worst = None
    for y, line in enumerate(mask):
        for x, v in enumerate(line):
            if v <= 0.02:
                continue
            px, py = x + 0.5, y + 0.5
            cx, cy = min(max(px, lo), hi), min(max(py, lo), hi)
            inside = radius - math.hypot(px - cx, py - cy)       # distance inside the rounded square
            inside = min(inside, px, py, size - px, size - py)
            if worst is None or inside < worst:
                worst = inside
    if worst is not None and worst < margin:
        raise SystemExit(f"draw_icon: the word comes within {worst:.0f} px of Apple's rounded corner or edge "
                         f"(keep {margin:.0f}); make it smaller or move it in")
    return worst


def over(rows, mask, rgb, opacity=1.0):
    for y, line in enumerate(mask):
        row = rows[y]
        for x, v in enumerate(line):
            a = v * opacity
            if a <= 0.0005:
                continue
            i = 3 * x
            for c in range(3):
                row[i + c] = int(row[i + c] * (1 - a) + rgb[c] * a + 0.5)


def write_png(path, rows):
    size = len(rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    raw = b"".join(b"\x00" + bytes(line) for line in rows)
    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))   # 8-bit RGB, no alpha
            + chunk(b"sRGB", b"\x00")                                              # sRGB, perceptual
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(data)


def picture(layout, angle, font, size):
    width, height, ground, shapes = read_svg(SVG)
    if width != height:
        raise SystemExit(f"draw_icon: {SVG} is {width} by {height}; an icon is square")
    if layout == "base":
        return draw(width, height, ground, shapes, size), None
    spec = LAYOUTS[layout]
    if angle is None:
        angle = spec["angle"]
    if not 0 < angle < 45:
        raise SystemExit("draw_icon: the word rises from left to right: an angle above 0 and below 45 degrees")
    scale = size / width
    rows = draw(width, height, ground, place(shapes, width, height, *spec["record"]), size)
    # A steeper angle pushes the word's ends towards the corners: it is made smaller, 3 percent at a time, until it
    # (or its strip) keeps the margin inside Apple's rounded square.
    font_size = spec["font"]
    while True:
        polys = word_polys(font, font_size, spec["centre"], angle, scale, spec.get("ink", False))
        word = fill(polys, size)
        strip = fill(strip_poly(polys, angle, scale), size) if spec.get("strip") else None
        try:
            safe = check_safe(strip if strip else word, size)
            break
        except SystemExit:
            if font_size < 0.7 * spec["font"]:
                raise
            font_size *= 0.97
    if strip:
        over(rows, blur(strip, 14 * scale), (0, 0, 0), 0.45)       # its shadow on the record
        over(rows, strip, ground)
    if spec.get("halo"):
        over(rows, blur(word, 12 * scale), ground, 0.85)           # a soft dark edge, so it reads over the rings
    if spec.get("outline"):
        over(rows, grow(word, spec["outline"] * scale), ground)    # a hairline in the ground's colour
    over(rows, word, INK)
    return rows, (angle, safe, font_size)


def main(argv):
    opts = {"--layout": None, "--angle": None, "--font": "script", "--size": "1024", "--out": None}
    i = 1
    while i < len(argv):
        if argv[i] in opts and i + 1 < len(argv):
            opts[argv[i]] = argv[i + 1]
            i += 2
        else:
            raise SystemExit("usage: draw_icon.py [--layout base|a|a-shadow|b|c] [--angle deg] [--font script|sans] "
                             "[--size 1024] [--out <png>]")
    size = int(opts["--size"])
    if opts["--font"] not in FONTS:
        raise SystemExit("draw_icon: --font is script (Pacifico) or sans (Inter)")
    if opts["--layout"] is None:   # both committed pictures, as shipped
        jobs = [("base", None, BASE_OUT), (SHIP[0], SHIP[1], IPAD_OUT)]
        if opts["--out"] or opts["--angle"] or size != 1024:
            raise SystemExit("draw_icon: --out, --angle and --size go with --layout")
    else:
        if opts["--layout"] not in ("base",) + tuple(LAYOUTS):
            raise SystemExit("draw_icon: --layout is base or one of " + ", ".join(LAYOUTS))
        jobs = [(opts["--layout"], float(opts["--angle"]) if opts["--angle"] else None,
                 opts["--out"] or (BASE_OUT if opts["--layout"] == "base" else IPAD_OUT))]
    for layout, angle, out in jobs:
        rows, info = picture(layout, angle, opts["--font"] if layout != "base" else None, size)
        write_png(out, rows)
        what = "the plain icon" if info is None else \
            f"layout {layout}, \"{WORD}\" in {'Pacifico' if opts['--font'] == 'script' else 'Inter'} rising " \
            f"{info[0]:g} degrees at a font size of {info[2]:.0f} (in 1024), {info[1] * 1024 / size:.0f} (in 1024) clear of " \
            f"Apple's corners"
        print(f"draw_icon: {os.path.relpath(out, REPO) if out.startswith(REPO) else out}: {size} x {size}, RGB, "
              f"no alpha; {what}")


if __name__ == "__main__":
    main(sys.argv)
