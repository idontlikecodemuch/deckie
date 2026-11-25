#!/usr/bin/env python3
"""woff2_outlines.py: the outlines of a word in a WOFF2 font, with Python's standard library and the brotli program.

Used by draw_icon.py to set "Booth" in the site's own font files (site/fonts/pacifico.woff2, site/fonts/inter.woff2)
as real outlines. A WOFF2 file is a TrueType font whose tables are packed with Brotli, the glyph table rewritten into
separate streams; this undoes both and reads only what setting one line of text needs:

  cmap (letter to glyph), hmtx (advance widths), head (units per em), glyf (the outlines: quadratic curves), and
  GPOS pair kerning ('kern' feature, pair adjustments, formats 1 and 2, extension lookups followed).

  GSUB: the features a browser applies to Latin text by default (ccmp, liga, calt), in the forms these fonts use
  (single substitutions, ligatures, chained contexts by coverage).

Not applied: the variation tables of a variable font such as Inter: its outlines are the font's default instance.

Brotli is not in Python's standard library, so the packed tables are unpacked by the `brotli` program (Homebrew's
`brotli`, already on the Mac this was written on); nothing is downloaded.

    words(path, text) -> (units_per_em, contours, advance, glyph ids)
    contours: a list of closed contours in font units (y up, the baseline at 0, the pen starting at x 0), each a list
    of (x, y, on_curve) points as in the font; advance: the line's whole advance width in font units.
"""
import os
import shutil
import struct
import subprocess
import tempfile

KNOWN = ["cmap", "head", "hhea", "hmtx", "maxp", "name", "OS/2", "post", "cvt ", "fpgm", "glyf", "loca", "prep",
         "CFF ", "VORG", "EBDT", "EBLC", "gasp", "hdmx", "kern", "LTSH", "PCLT", "VDMX", "vhea", "vmtx", "BASE", "GDEF",
         "GPOS", "GSUB", "EBSC", "JSTF", "MATH", "CBDT", "CBLC", "COLR", "CPAL", "SVG ", "sbix", "acnt", "avar", "bdat",
         "bloc", "bsln", "cvar", "fdsc", "feat", "fmtx", "fvar", "gvar", "hsty", "just", "lcar", "mort", "morx", "opbd",
         "prop", "trak", "Zapf", "Silf", "Glat", "Gloc", "Feat", "Sill"]


def brotli_program():
    for p in (shutil.which("brotli"), "/opt/homebrew/bin/brotli", "/usr/local/bin/brotli"):
        if p and os.path.exists(p):
            return p
    raise SystemExit("woff2_outlines: needs the brotli program (Homebrew: brotli) to unpack a WOFF2 font")


def unpack(path):
    """The font's tables as {tag: bytes}; glyf stays in its WOFF2 form under 'glyf' (see glyphs())."""
    d = open(path, "rb").read()
    sig, flavor, _, num, _, _, comp = struct.unpack(">4sIIHHII", d[:24])
    if sig != b"wOF2":
        raise SystemExit(f"woff2_outlines: {path} is not a WOFF2 font")
    p = 48

    def base128(p):
        v = 0
        for _ in range(5):
            c = d[p]
            p += 1
            v = (v << 7) | (c & 0x7F)
            if not c & 0x80:
                return v, p
        raise SystemExit(f"woff2_outlines: {path}: a bad length in the table directory")
    entries = []
    for _ in range(num):
        flags = d[p]
        p += 1
        if flags & 63 == 63:
            tag = d[p:p + 4].decode("latin-1")
            p += 4
        else:
            tag = KNOWN[flags & 63]
        length, p = base128(p)
        version = flags >> 6
        transformed = (version != 3) if tag in ("glyf", "loca") else (version != 0)
        if transformed:
            length, p = base128(p)
        entries.append((tag, length, transformed))
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "tables.br")
        open(src, "wb").write(d[p:p + comp])
        raw = subprocess.run([brotli_program(), "-d", "-c", src], check=True, capture_output=True).stdout
    tables, at = {}, 0
    for tag, length, transformed in entries:
        tables[tag] = raw[at:at + length]
        at += length
        if transformed and tag not in ("glyf", "loca"):
            raise SystemExit(f"woff2_outlines: {path}: table {tag} is transformed in a way this does not read")
    return tables


def u255(b, p):
    c = b[p]
    if c == 253:
        return struct.unpack(">H", b[p + 1:p + 3])[0], p + 3
    if c == 255:
        return b[p + 1] + 253, p + 2
    if c == 254:
        return b[p + 1] + 506, p + 2
    return c, p + 1


def glyphs(glyf):
    """WOFF2's transformed glyf: every glyph as ('simple', contours) or ('composite', components) or None."""
    _, options, count, _ = struct.unpack(">HHHH", glyf[:8])
    sizes = struct.unpack(">7I", glyf[8:36])
    starts, at = [], 36
    for s in sizes:
        starts.append(at)
        at += s
    nc, npts, flg, gly, comp, bbox, ins = starts
    bbox_bitmap = ((count + 31) >> 5) * 4
    out = []
    for _ in range(count):
        contours_n = struct.unpack(">h", glyf[nc:nc + 2])[0]
        nc += 2
        if contours_n == 0:
            out.append(None)
            continue
        if contours_n < 0:
            parts, more, instructions = [], True, False
            while more:
                f, g = struct.unpack(">HH", glyf[comp:comp + 4])
                comp += 4
                if f & 1:
                    a, b = struct.unpack(">hh", glyf[comp:comp + 4])
                    comp += 4
                else:
                    a, b = struct.unpack(">bb", glyf[comp:comp + 2])
                    comp += 2
                m = (1.0, 0.0, 0.0, 1.0)
                if f & 0x8:
                    s = struct.unpack(">h", glyf[comp:comp + 2])[0] / 16384
                    comp += 2
                    m = (s, 0.0, 0.0, s)
                elif f & 0x40:
                    sx, sy = (v / 16384 for v in struct.unpack(">hh", glyf[comp:comp + 4]))
                    comp += 4
                    m = (sx, 0.0, 0.0, sy)
                elif f & 0x80:
                    m = tuple(v / 16384 for v in struct.unpack(">hhhh", glyf[comp:comp + 8]))
                    comp += 8
                if not f & 2:
                    raise SystemExit("woff2_outlines: a composite glyph placed by point numbers is not read")
                parts.append((g, a, b, m))
                instructions |= bool(f & 0x100)
                more = bool(f & 0x20)
            if instructions:
                n, gly = u255(glyf, gly)
                ins += n
            out.append(("composite", parts))
            continue
        ends = []
        total = 0
        for _ in range(contours_n):
            n, npts = u255(glyf, npts)
            total += n
            ends.append(total)
        x = y = 0
        points = []
        for _ in range(total):
            f = glyf[flg]
            flg += 1
            on = not f & 0x80
            f &= 0x7F
            sign = lambda fl, v: v if fl & 1 else -v
            if f < 10:
                dx, dy, n = 0, sign(f, ((f & 14) << 7) + glyf[gly]), 1
            elif f < 20:
                dx, dy, n = sign(f, (((f - 10) & 14) << 7) + glyf[gly]), 0, 1
            elif f < 84:
                b0, b1 = f - 20, glyf[gly]
                dx = sign(f, 1 + (b0 & 0x30) + (b1 >> 4))
                dy = sign(f >> 1, 1 + ((b0 & 0x0C) << 2) + (b1 & 0x0F))
                n = 1
            elif f < 120:
                b0 = f - 84
                dx = sign(f, 1 + ((b0 // 12) << 8) + glyf[gly])
                dy = sign(f >> 1, 1 + (((b0 % 12) >> 2) << 8) + glyf[gly + 1])
                n = 2
            elif f < 124:
                b1, b2, b3 = glyf[gly], glyf[gly + 1], glyf[gly + 2]
                dx, dy, n = sign(f, (b1 << 4) + (b2 >> 4)), sign(f >> 1, ((b2 & 0x0F) << 8) + b3), 3
            else:
                b = glyf[gly:gly + 4]
                dx, dy, n = sign(f, (b[0] << 8) + b[1]), sign(f >> 1, (b[2] << 8) + b[3]), 4
            gly += n
            x += dx
            y += dy
            points.append((x, y, on))
        n, gly = u255(glyf, gly)
        ins += n
        contours, start = [], 0
        for e in ends:
            contours.append(points[start:e])
            start = e
        out.append(("simple", contours))
    return out


def outline(table, g, dx=0.0, dy=0.0, m=(1.0, 0.0, 0.0, 1.0)):
    entry = table[g]
    if entry is None:
        return []
    kind, body = entry
    if kind == "simple":
        a, b, c, d = m
        return [[(a * x + c * y + dx, b * x + d * y + dy, on) for x, y, on in contour] for contour in body]
    result = []
    for sub, ox, oy, sm in body:
        a, b, c, d = m
        sa, sb, sc, sd = sm
        mm = (a * sa + c * sb, b * sa + d * sb, a * sc + c * sd, b * sc + d * sd)
        result += outline(table, sub, a * ox + c * oy + dx, b * ox + d * oy + dy, mm)
    return result


def cmap(t):
    best = None
    count = struct.unpack(">H", t[2:4])[0]
    for i in range(count):
        plat, enc, off = struct.unpack(">HHI", t[4 + 8 * i:12 + 8 * i])
        fmt = struct.unpack(">H", t[off:off + 2])[0]
        if (plat, enc) in ((3, 10), (0, 4)) and fmt == 12:
            best = (fmt, off)
            break
        if (plat, enc) in ((3, 1), (0, 3)) and fmt == 4 and best is None:
            best = (fmt, off)
    if best is None:
        raise SystemExit("woff2_outlines: no Unicode cmap")
    fmt, off = best
    table = {}
    if fmt == 4:
        segs = struct.unpack(">H", t[off + 6:off + 8])[0] // 2
        ends = struct.unpack(f">{segs}H", t[off + 14:off + 14 + 2 * segs])
        p = off + 16 + 2 * segs
        starts = struct.unpack(f">{segs}H", t[p:p + 2 * segs])
        deltas = struct.unpack(f">{segs}h", t[p + 2 * segs:p + 4 * segs])
        rbase = p + 4 * segs
        ranges = struct.unpack(f">{segs}H", t[rbase:rbase + 2 * segs])
        for i in range(segs):
            for c in range(starts[i], ends[i] + 1):
                if c == 0xFFFF:
                    continue
                if ranges[i] == 0:
                    g = (c + deltas[i]) & 0xFFFF
                else:
                    q = rbase + 2 * i + ranges[i] + 2 * (c - starts[i])
                    g = struct.unpack(">H", t[q:q + 2])[0]
                    g = (g + deltas[i]) & 0xFFFF if g else 0
                table[c] = g
    else:
        n = struct.unpack(">I", t[off + 12:off + 16])[0]
        for i in range(n):
            s, e, g = struct.unpack(">III", t[off + 16 + 12 * i:off + 28 + 12 * i])
            for c in range(s, e + 1):
                table[c] = g + c - s
    return table


def coverage(t, off):
    fmt = struct.unpack(">H", t[off:off + 2])[0]
    n = struct.unpack(">H", t[off + 2:off + 4])[0]
    if fmt == 1:
        return {g: i for i, g in enumerate(struct.unpack(f">{n}H", t[off + 4:off + 4 + 2 * n]))}
    cov = {}
    for i in range(n):
        s, e, idx = struct.unpack(">HHH", t[off + 4 + 6 * i:off + 10 + 6 * i])
        for g in range(s, e + 1):
            cov[g] = idx + g - s
    return cov


def classdef(t, off):
    fmt = struct.unpack(">H", t[off:off + 2])[0]
    if fmt == 1:
        start, n = struct.unpack(">HH", t[off + 2:off + 6])
        return {start + i: c for i, c in enumerate(struct.unpack(f">{n}H", t[off + 6:off + 6 + 2 * n]))}
    n = struct.unpack(">H", t[off + 2:off + 4])[0]
    cls = {}
    for i in range(n):
        s, e, c = struct.unpack(">HHH", t[off + 4 + 6 * i:off + 10 + 6 * i])
        for g in range(s, e + 1):
            cls[g] = c
    return cls


def value_size(fmt):
    return 2 * bin(fmt & 0xFF).count("1")


def x_advance(t, p, fmt):
    """The XAdvance of a value record at p, or 0."""
    if not fmt & 4:
        return 0
    skip = 2 * bin(fmt & 3).count("1")
    return struct.unpack(">h", t[p + skip:p + skip + 2])[0]


def kerning(t, left, right):
    """GPOS 'kern' pair adjustment between two glyphs, in font units (0 when none)."""
    if not t:
        return 0
    _, feat_off, lookup_off = struct.unpack(">HHH", t[4:10])
    nfeat = struct.unpack(">H", t[feat_off:feat_off + 2])[0]
    lookups = set()
    for i in range(nfeat):
        tag = t[feat_off + 2 + 6 * i:feat_off + 6 + 6 * i]
        off = struct.unpack(">H", t[feat_off + 6 + 6 * i:feat_off + 8 + 6 * i])[0]
        if tag == b"kern":
            f = feat_off + off
            n = struct.unpack(">H", t[f + 2:f + 4])[0]
            lookups.update(struct.unpack(f">{n}H", t[f + 4:f + 4 + 2 * n]))
    nlook = struct.unpack(">H", t[lookup_off:lookup_off + 2])[0]
    offs = struct.unpack(f">{nlook}H", t[lookup_off + 2:lookup_off + 2 + 2 * nlook])
    total = 0
    for li in sorted(lookups):
        L = lookup_off + offs[li]
        kind, _, nsub = struct.unpack(">HHH", t[L:L + 6])
        for s in struct.unpack(f">{nsub}H", t[L + 6:L + 6 + 2 * nsub]):
            S, k = L + s, kind
            if k == 9:   # extension: the real subtable is further on
                k, ext = struct.unpack(">HI", t[S + 2:S + 8])
                S += ext
            if k != 2:
                continue
            fmt, cov_off, vf1, vf2 = struct.unpack(">HHHH", t[S:S + 8])
            cov = coverage(t, S + cov_off)
            if left not in cov:
                continue
            found = None
            if fmt == 1:
                ps = S + struct.unpack(">H", t[S + 10 + 2 * cov[left]:S + 12 + 2 * cov[left]])[0]
                n = struct.unpack(">H", t[ps:ps + 2])[0]
                rec = 2 + value_size(vf1) + value_size(vf2)
                for i in range(n):
                    p = ps + 2 + rec * i
                    if struct.unpack(">H", t[p:p + 2])[0] == right:
                        found = x_advance(t, p + 2, vf1)
                        break
            elif fmt == 2:
                c1off, c2off, n1, n2 = struct.unpack(">HHHH", t[S + 8:S + 16])
                c1 = classdef(t, S + c1off).get(left, 0)
                c2 = classdef(t, S + c2off).get(right, 0)
                rec = value_size(vf1) + value_size(vf2)
                p = S + 16 + (c1 * n2 + c2) * rec
                found = x_advance(t, p, vf1)
            if found is not None:
                total += found
                break   # the first subtable that covers the pair decides, for this lookup
    return total


def feature_lookups(t, want):
    """The lookup indices of the features named in `want`, in lookup order (as a shaper applies them)."""
    feat_off = struct.unpack(">H", t[6:8])[0]
    n = struct.unpack(">H", t[feat_off:feat_off + 2])[0]
    found = set()
    for i in range(n):
        tag = t[feat_off + 2 + 6 * i:feat_off + 6 + 6 * i].decode("latin-1")
        if tag in want:
            f = feat_off + struct.unpack(">H", t[feat_off + 6 + 6 * i:feat_off + 8 + 6 * i])[0]
            k = struct.unpack(">H", t[f + 2:f + 4])[0]
            found.update(struct.unpack(f">{k}H", t[f + 4:f + 4 + 2 * k]))
    return sorted(found)


def substitute(t, ids, want=("ccmp", "liga", "calt")):
    """GSUB's default features for Latin text, as a browser applies them: single substitutions, ligatures (format 1)
    and chained contexts given by coverage (format 3), the kinds Pacifico and Inter use for these features."""
    if not t:
        return ids
    lookup_off = struct.unpack(">H", t[8:10])[0]
    nlook = struct.unpack(">H", t[lookup_off:lookup_off + 2])[0]
    offs = struct.unpack(f">{nlook}H", t[lookup_off + 2:lookup_off + 2 + 2 * nlook])
    h = lambda p: struct.unpack(">H", t[p:p + 2])[0]

    def subtables(li):
        L = lookup_off + offs[li]
        kind, nsub = h(L), h(L + 4)
        for s in struct.unpack(f">{nsub}H", t[L + 6:L + 6 + 2 * nsub]):
            S, k = L + s, kind
            if k == 7:   # extension: the real subtable is further on
                k, ext = struct.unpack(">HI", t[S + 2:S + 8])
                S += ext
            yield k, S

    def single(li, g):
        for k, S in subtables(li):
            if k != 1:
                continue
            cov = coverage(t, S + h(S + 2))
            if g in cov:
                if h(S) == 1:
                    return (g + struct.unpack(">h", t[S + 4:S + 6])[0]) & 0xFFFF
                return h(S + 6 + 2 * cov[g])
        return g

    def covs(S, p):
        n = h(p)
        return [coverage(t, S + h(p + 2 + 2 * j)) for j in range(n)], p + 2 + 2 * n

    ids = list(ids)
    for li in feature_lookups(t, want):
        i = 0
        while i < len(ids):
            step = 1
            for k, S in subtables(li):
                if k == 1:
                    ids[i] = single(li, ids[i])
                    break
                if k == 4 and h(S) == 1:
                    cov = coverage(t, S + h(S + 2))
                    if ids[i] not in cov:
                        continue
                    ls = S + h(S + 6 + 2 * cov[ids[i]])
                    hit = False
                    for j in range(h(ls)):
                        L = ls + h(ls + 2 + 2 * j)
                        lig, cc = h(L), h(L + 2)
                        if ids[i + 1:i + cc] == [h(L + 4 + 2 * q) for q in range(cc - 1)]:
                            ids[i:i + cc] = [lig]
                            hit = True
                            break
                    if hit:
                        break
                    continue
                if k == 6 and h(S) == 3:
                    back, p = covs(S, S + 2)
                    inp, p = covs(S, p)
                    ahead, p = covs(S, p)
                    if i < len(back) or i + len(inp) + len(ahead) > len(ids):
                        continue
                    if not (all(ids[i - 1 - j] in c for j, c in enumerate(back))
                            and all(ids[i + j] in c for j, c in enumerate(inp))
                            and all(ids[i + len(inp) + j] in c for j, c in enumerate(ahead))):
                        continue
                    for r in range(h(p)):
                        seq, sub = h(p + 2 + 4 * r), h(p + 4 + 4 * r)
                        ids[i + seq] = single(sub, ids[i + seq])
                    step = max(1, len(inp))
                    break
            i += step
    return ids


def gsub_features(t):
    if not t:
        return []
    feat_off = struct.unpack(">H", t[6:8])[0]
    n = struct.unpack(">H", t[feat_off:feat_off + 2])[0]
    return sorted({t[feat_off + 2 + 6 * i:feat_off + 6 + 6 * i].decode("latin-1") for i in range(n)})


def words(path, text):
    tables = unpack(path)
    upem = struct.unpack(">H", tables["head"][18:20])[0]
    nh = struct.unpack(">H", tables["hhea"][34:36])[0]
    hmtx = tables["hmtx"]
    advances = [struct.unpack(">H", hmtx[4 * i:4 * i + 2])[0] for i in range(nh)]
    table = glyphs(tables["glyf"])
    chars = cmap(tables["cmap"])
    ids = []
    for ch in text:
        if ord(ch) not in chars:
            raise SystemExit(f"woff2_outlines: {path} has no glyph for {ch!r}")
        ids.append(chars[ord(ch)])
    ids = substitute(tables.get("GSUB", b""), ids)
    contours, x = [], 0
    for i, g in enumerate(ids):
        contours += outline(table, g, x, 0)
        x += advances[min(g, nh - 1)]
        if i + 1 < len(ids):
            x += kerning(tables.get("GPOS", b""), g, ids[i + 1])
    return upem, contours, x, ids


if __name__ == "__main__":
    import sys
    if len(sys.argv) != 3:
        raise SystemExit("usage: woff2_outlines.py <font.woff2> <text>")
    upem, cs, adv, ids = words(sys.argv[1], sys.argv[2])
    t = unpack(sys.argv[1])
    print(f"{sys.argv[1]}: {upem} units per em, {len(cs)} contours, advance {adv}; glyphs {ids}; GSUB features in the font: "
          f"{', '.join(gsub_features(t.get('GSUB', b''))) or 'none'}")
