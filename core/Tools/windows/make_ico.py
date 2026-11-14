#!/usr/bin/env python3
"""make_ico.py: Deckie's Windows icon file (.ico) from the app's icon picture, with Python's standard library only.

    python make_ico.py <icon1024.png> <out.ico> [--corner 230/1024] [--sizes 16,20,24,32,40,48,64,256]

An .ico is one file holding the same picture at several sizes; Windows picks the size it needs (16 pixels in a title
bar, 32 to 48 on the taskbar and in a folder, 256 for large views). No .ico is committed (the repository holds no
binaries that can be made): package.sh makes it from the iPad app's picture each time, with this file.

What it does, and nothing else:
  1. reads the PNG (8 bits a channel, RGB or RGBA, not interlaced) with zlib and the PNG filters undone by hand;
  2. scales it to each size by area averaging: each small pixel is the exact average of the square of large pixels
     it covers (whole-number arithmetic, so the result is the same on every machine);
  3. rounds the corners as the site's icon does (site/icon.svg: a corner radius of 230 in 1024), since the iPad
     picture is a full square that iOS rounds itself, and Windows shows a picture as it is;
  4. writes the .ico: the 256-pixel picture as a PNG inside it, the smaller ones as plain 32-bit bitmaps with their
     masks, which is the layout every Windows since Vista and both resource compilers read.
"""
import itertools
import struct
import sys
import zlib


def read_png(path):
    """The picture as (width, height, channels, rows); each row a bytes of width * channels values."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"make_ico: {path} is not a PNG")
    at, idat, header = 8, [], None
    while at < len(data):
        length, kind = struct.unpack(">I4s", data[at:at + 8])
        body = data[at + 8:at + 8 + length]
        if zlib.crc32(kind + body) != struct.unpack(">I", data[at + 8 + length:at + 12 + length])[0]:
            raise SystemExit(f"make_ico: {path} is damaged (a checksum does not match)")
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        at += 12 + length
    if header is None:
        raise SystemExit(f"make_ico: {path} has no header")
    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or colour not in (2, 6) or interlace != 0:
        raise SystemExit(f"make_ico: {path} must be 8-bit RGB or RGBA, not interlaced (it is depth {depth}, "
                         f"colour type {colour}, interlace {interlace})")
    channels = 3 if colour == 2 else 4
    stride = width * channels
    raw = zlib.decompress(b"".join(idat))
    if len(raw) != height * (stride + 1):
        raise SystemExit(f"make_ico: {path} holds {len(raw)} bytes of picture, expected {height * (stride + 1)}")
    rows, before = [], bytes(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        if kind == 1:      # Sub: each value is given as its difference from the pixel to the left
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 255
        elif kind == 2:    # Up: from the pixel above
            line = bytearray((a + b) & 255 for a, b in zip(line, before))
        elif kind == 3:    # Average of left and above
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + before[i]) >> 1)) & 255
        elif kind == 4:    # Paeth: whichever of left, above, above-left is nearest to left + above - above-left
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = before[i]
                c = before[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        elif kind != 0:
            raise SystemExit(f"make_ico: {path} uses a filter this does not know ({kind})")
        before = bytes(line)
        rows.append(before)
    return width, height, channels, rows


def area_average(width, height, channels, rows, size):
    """The picture scaled to size x size: each output value is the exact average of the source area it covers.

    Returned as rows of lists of `channels` integers per pixel, each the sum over the area times size * size, so a
    value is the average times (width * height); the caller divides once, at the end.
    """
    # Across: for each source row, the running sum of each channel, so any span's sum is one subtraction.
    across = []
    for line in rows:
        out = []
        sums = [[0] + list(itertools.accumulate(line[c::channels])) for c in range(channels)]
        for x in range(size):
            a, b = x * width, (x + 1) * width           # the span, in source pixels times `size`
            fa, ra, fb, rb = a // size, a % size, b // size, b % size
            for c in range(channels):
                s = size * (sums[c][fb] - sums[c][fa]) - ra * line[fa * channels + c]
                if rb:
                    s += rb * line[fb * channels + c]
                out.append(s)
        across.append(out)
    # Down: the same over the rows of that.
    result = []
    for y in range(size):
        a, b = y * height, (y + 1) * height
        fa, ra, fb, rb = a // size, a % size, b // size, b % size
        total = [0] * (size * channels)
        for r in range(fa, fb):
            total = [t + size * v for t, v in zip(total, across[r])]
        if ra:
            total = [t - ra * v for t, v in zip(total, across[fa])]
        if rb:
            total = [t + rb * v for t, v in zip(total, across[fb])]
        result.append(total)
    return result


def corner_cover(size, radius, x, y, steps=8):
    """How much of pixel (x, y) lies inside a size x size square with corners rounded to `radius`: 0 to 1."""
    lo, hi = radius, size - radius
    # Well inside the cross that the corner circles do not touch: all of it.
    if (lo <= x and x + 1 <= hi) or (lo <= y and y + 1 <= hi):
        return 1.0
    inside = 0
    for j in range(steps):
        py = y + (j + 0.5) / steps
        for i in range(steps):
            px = x + (i + 0.5) / steps
            cx = lo if px < lo else hi if px > hi else px
            cy = lo if py < lo else hi if py > hi else py
            if (px - cx) ** 2 + (py - cy) ** 2 <= radius * radius:
                inside += 1
    return inside / (steps * steps)


def picture(width, height, channels, rows, size, corner):
    """size x size pixels as rows of (r, g, b, a) with straight (not premultiplied) colour, corners rounded."""
    scaled = area_average(width, height, channels, rows, size)
    whole = width * height   # what area_average's sums are divided by to give the average
    radius = corner * size
    out = []
    for y in range(size):
        line = []
        for x in range(size):
            v = scaled[y][x * channels:(x + 1) * channels]
            r, g, b = (min(255, (t + whole // 2) // whole) for t in v[:3])
            alpha = min(255, (v[3] + whole // 2) // whole) if channels == 4 else 255
            cover = corner_cover(size, radius, x, y) if radius > 0 else 1.0
            line.append((r, g, b, int(alpha * cover + 0.5)))
        out.append(line)
    return out


def as_png(pixels):
    size = len(pixels)
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    raw = b"".join(b"\x00" + bytes(v for p in line for v in p) for line in pixels)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def as_bitmap(pixels):
    """An icon's bitmap: a 40-byte header (height doubled, for the mask), 32-bit rows from the bottom up as blue,
    green, red, alpha, then the one-bit mask (set where the pixel is fully transparent), rows padded to 4 bytes."""
    size = len(pixels)
    colour = b"".join(bytes(v for (r, g, b, a) in line for v in (b, g, r, a)) for line in reversed(pixels))
    mask_stride = ((size + 31) // 32) * 4
    mask = bytearray()
    for line in reversed(pixels):
        bits = bytearray(mask_stride)
        for x, p in enumerate(line):
            if p[3] == 0:
                bits[x // 8] |= 0x80 >> (x % 8)
        mask += bits
    header = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, len(colour) + len(mask), 0, 0, 0, 0)
    return header + colour + bytes(mask)


def as_ico(images):
    """images: (size, bytes) pairs. The .ico: a 6-byte header, a 16-byte entry for each picture, then the pictures."""
    out = struct.pack("<HHH", 0, 1, len(images))
    at = 6 + 16 * len(images)
    for size, body in images:
        out += struct.pack("<BBBBHHII", size & 255, size & 255, 0, 0, 1, 32, len(body), at)   # 256 is written as 0
        at += len(body)
    return out + b"".join(body for _, body in images)


def main(argv):
    args, corner, sizes = [], (230, 1024), [16, 20, 24, 32, 40, 48, 64, 256]
    i = 1
    while i < len(argv):
        if argv[i] == "--corner" and i + 1 < len(argv):
            n, d = argv[i + 1].split("/")
            corner = (int(n), int(d))
            i += 2
        elif argv[i] == "--sizes" and i + 1 < len(argv):
            sizes = [int(s) for s in argv[i + 1].split(",")]
            i += 2
        else:
            args.append(argv[i])
            i += 1
    if len(args) != 2 or any(s < 1 or s > 256 for s in sizes):
        raise SystemExit("usage: make_ico.py <picture.png> <out.ico> [--corner 230/1024] [--sizes 16,...,256]")
    width, height, channels, rows = read_png(args[0])
    if width != height:
        raise SystemExit(f"make_ico: {args[0]} is {width} x {height}; an icon is square")
    images = []
    for size in sorted(sizes):
        if size > width:
            raise SystemExit(f"make_ico: {args[0]} is smaller than {size} pixels")
        pixels = picture(width, height, channels, rows, size, corner[0] / corner[1])
        images.append((size, as_png(pixels) if size >= 256 else as_bitmap(pixels)))
    open(args[1], "wb").write(as_ico(images))
    print(f"make_ico: {args[1]}: {', '.join(str(s) for s, _ in images)} pixels, {sum(len(b) for _, b in images) + 6 + 16 * len(images)} bytes")


if __name__ == "__main__":
    main(sys.argv)
