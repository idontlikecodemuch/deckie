#!/usr/bin/env python3
"""compare_crates.py: compare two crate files made from the same music on two machines, field by field.

    python3 core/Tools/compare_crates.py A.deckiecrate B.deckiecrate [--summary out.md]

Each crate file may be a package folder or the single-file form (one uncompressed zip, read here with Python's own
zipfile module, so this is also a check that another program's zip reader opens Deckie's archive). Python's standard
library only.

What must be the same, exactly: the songs (their ids, which are the first 16 hexadecimal digits of the SHA-256 of
each file's bytes), their paths and names, every whole number (bar counts, bar numbers, sections, mix windows), every
text (key, labels, flags, and each song's `file.cover`, the name of its cover), every true or false, the import log's
entries, and which fields are present. The covers too (D36): both crate files must hold the same set of
`covers/*.jpg` files with identical bytes. A cover is named by the hash of the picture it was made from, so the names
are the same on any two machines; the bytes are the same between Linux and Windows, which make the thumbnail with
the same code (not between either and a Mac, whose system makes its own: this script compares Linux and Windows).

What may differ, and by how much (the tolerance, by field name). The two machines run the same code on the same
bytes, so every difference comes from arithmetic that is allowed to differ in its last digit: the C maths library
(glibc on Linux, Microsoft's on Windows: sin, exp, log and pow may differ in the last bit), the compiler's choice of
fused multiply-add, and ONNX Runtime, whose two builds (different compilers, different vector instructions) add the
same numbers in a different order, so the models' outputs agree to about four decimal places, not to the bit. The
crate file rounds every number to a fixed number of decimals, which hides almost all of it, but a value that sits on
a rounding edge can land one step either side. So:

  - a number written with d decimals may differ by 2 steps of its last decimal (2 x 10^-d);
  - times that come from the beat model's beats (the grid's first downbeat, tempo) get the same rule: beats are
    picked from the model's output on a 20 ms frame, and a fitted grid averages them, so a moved rounding shows up in
    the last decimals only. A whole frame's move would show as 0.02 s and fail, as it should;
  - `secs` (how long the analysis took), `analysed_at`, the device and platform labels, the crate's id and dates are
    different by nature and are not compared;
  - a fingerprint's `made_at` and `made_by` (when and on what it was made) are different by nature too; its points
    (prints/<id>.dkl) must be the same in at least 99 of 100 places;
  - per-bar series and the style vector are float16 (about three significant digits): values may differ by 0.05 (dB for
    the loudness and band series, probability for the vocal series) or, for the style vector (unit length, 1,024
    values), by 0.002 in any value.

Exits with 0 when everything is within these, 1 otherwise, and prints the largest difference found for every field
that differed at all, so the tolerance can be judged against what was measured.
"""
import json
import os
import struct
import sys
import zipfile

# Decimals by field name, as core/Sources/DeckieCrate/CrateFormat.swift writes them (CrateFormat.decimals).
DECIMALS = {
    "bpm": 3, "bpm_in": 3, "bpm_out": 3, "confidence": 3, "duration_s": 3, "first_sound_s": 3, "last_sound_s": 3,
    "lra": 3, "tag_bpm": 3, "first_downbeat_s": 4, "start_s": 4, "end_s": 4, "mean": 4, "onset_pattern_16": 4,
    "fit_mad_ms": 2, "integrated_lufs": 2, "true_peak_db": 2, "secs": 2, "time_s": 4, "frame_hop_s": 4,
    "threshold": 4, "score_p95": 4, "threshold_floor": 4, "threshold_fraction": 3, "beat_density_ratio": 3,
    "bright_margin_db": 2, "exposed_low_drop_db": 2, "exposed_density_ratio": 3, "strength": 3, "repetition": 3,
    "loudness_score": 3, "vocal_density": 3, "weight_repetition": 3, "weight_loudness": 3, "weight_vocal": 3,
    "min_repetition": 3, "short_margin": 3, "sung_share": 3, "seconds": 4,
}
STEPS = 2


def dkl_points(data):
    """The (frame, packed pitch) points of a fingerprint file, or None when the bytes are not one."""
    if len(data) < 12 or data[:4] != b"DKL2":
        return None
    n = int.from_bytes(data[8:12], "little")
    points, i, frame = [], 12, 0
    for _ in range(n):
        delta = shift = 0
        while True:
            if i >= len(data):
                return None
            byte = data[i]; i += 1
            delta |= (byte & 0x7F) << shift
            if not byte & 0x80:
                break
            shift += 7
        if i + 2 > len(data):
            return None
        frame += delta
        points.append((frame, data[i] | data[i + 1] << 8))
        i += 2
    return points
# Not compared: different by nature on two machines or two runs.
SKIP = {"secs", "analysed_at", "device", "platform", "crate_id", "created_at", "built_at", "built_by", "devices_seen",
        "imported_at", "made_at", "made_by"}
# A song's fingerprint (prints/<id>.dkl, D35): the share of its points that must be the same on both machines. The
# points are peaks of a spectrogram, so a last-digit difference in the arithmetic can, rarely, tip which of two
# near-equal neighbours is the peak; the count of points is compared exactly through the record's `print.points`.
PRINT_SHARE = 0.99
SERIES_TOLERANCE = 0.05
STYLE_TOLERANCE = 0.002


def read(path):
    """The crate file's files, by their path inside it."""
    files = {}
    if os.path.isdir(path):
        for folder, _, names in os.walk(path):
            for name in names:
                full = os.path.join(folder, name)
                files[os.path.relpath(full, path).replace(os.sep, "/")] = open(full, "rb").read()
    else:
        with zipfile.ZipFile(path) as z:
            bad = z.testzip()
            if bad:
                sys.exit(f"{path}: Python's zipfile finds {bad} damaged")
            for info in z.infolist():
                if info.compress_type != zipfile.ZIP_STORED:
                    sys.exit(f"{path}: {info.filename} is compressed; the single-file form stores every file as it is")
                files[info.filename] = z.read(info)
    return files


class Report:
    def __init__(self):
        self.failures = []
        self.largest = {}  # field -> (difference, tolerance, where)

    def number(self, field, where, a, b, tolerance):
        d = abs(a - b)
        if d > 0 and d > self.largest.get(field, (0, 0, ""))[0]:
            self.largest[field] = (d, tolerance, where)
        if d > tolerance:
            self.failures.append(f"{where}: {a} against {b}, {d:.6g} apart (allowed {tolerance:g})")

    def walk(self, where, field, a, b):
        if field in SKIP:
            return
        if isinstance(a, dict) and isinstance(b, dict):
            for k in sorted(set(a) | set(b)):
                if k in SKIP:
                    continue
                if k not in a or k not in b:
                    self.failures.append(f"{where}.{k}: only in the {'second' if k not in a else 'first'}")
                else:
                    self.walk(f"{where}.{k}", k, a[k], b[k])
        elif isinstance(a, list) and isinstance(b, list):
            if len(a) != len(b):
                self.failures.append(f"{where}: {len(a)} items against {len(b)}")
            for i, (x, y) in enumerate(zip(a, b)):
                self.walk(f"{where}[{i}]", field, x, y)
        elif isinstance(a, bool) or isinstance(b, bool) or a is None or b is None or isinstance(a, str) or isinstance(b, str):
            if a != b:
                self.failures.append(f"{where}: {a!r} against {b!r}")
        elif isinstance(a, int) and isinstance(b, int) and field not in DECIMALS:
            if a != b:
                self.failures.append(f"{where}: {a} against {b}")
        else:
            if field not in DECIMALS:
                self.failures.append(f"{where}: a fractional number under a name with no listed decimals")
                return
            self.number(field, where, float(a), float(b), STEPS * 10.0 ** -DECIMALS[field] * 1.000001)


def float16s(data, offset=16):
    body = data[offset:]
    return struct.unpack(f"<{len(body) // 2}e", body)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    summary = sys.argv[sys.argv.index("--summary") + 1] if "--summary" in sys.argv else None
    if summary in args:
        args.remove(summary)
    if len(args) != 2:
        sys.exit(__doc__)
    fa, fb = read(args[0]), read(args[1])
    r = Report()
    for name in ("manifest.json", "crate.json"):
        if name not in fa or name not in fb:
            sys.exit(f"{name} is missing from {'the first' if name not in fa else 'the second'} crate file")
    r.walk("manifest", "", json.loads(fa["manifest.json"]), json.loads(fb["manifest.json"]))
    ta = {t["id"]: t for t in json.loads(fa["crate.json"])["tracks"]}
    tb = {t["id"]: t for t in json.loads(fb["crate.json"])["tracks"]}
    if set(ta) != set(tb):
        r.failures.append(f"the songs differ: only in the first {sorted(set(ta) - set(tb))}, only in the second {sorted(set(tb) - set(ta))}")
    for tid in sorted(set(ta) & set(tb)):
        name = ta[tid].get("file", {}).get("rel") or tid
        r.walk(name, "", ta[tid], tb[tid])
    sidecars = sorted(k for k in set(fa) | set(fb) if k.endswith(".bin"))
    for path in sidecars:
        if path not in fa or path not in fb:
            r.failures.append(f"{path}: only in the {'second' if path not in fa else 'first'}")
            continue
        a, b = fa[path], fb[path]
        if a[:16] != b[:16] or len(a) != len(b):
            r.failures.append(f"{path}: the headers or the sizes differ")
            continue
        kind = "style vector" if path.startswith("style/") else "per-bar series"
        tolerance = STYLE_TOLERANCE if path.startswith("style/") else SERIES_TOLERANCE
        for i, (x, y) in enumerate(zip(float16s(a), float16s(b))):
            if x != x and y != y:
                continue
            r.number(kind, f"{path}[{i}]", x, y, tolerance)

    prints = sorted(k for k in set(fa) | set(fb) if k.startswith("prints/") and k.endswith(".dkl"))
    same_prints = 0
    for path in prints:
        if path not in fa or path not in fb:
            r.failures.append(f"{path}: only in the {'second' if path not in fa else 'first'}")
            continue
        if fa[path] == fb[path]:
            same_prints += 1
            continue
        a, b = dkl_points(fa[path]), dkl_points(fb[path])
        if a is None or b is None:
            r.failures.append(f"{path}: not a fingerprint")
            continue
        shared = len(set(a) & set(b)) / max(1, max(len(a), len(b)))
        if shared < PRINT_SHARE:
            r.failures.append(f"{path}: only {100 * shared:.1f} % of the fingerprint's points are the same")
    covers = sorted(k for k in set(fa) | set(fb) if k.startswith("covers/") and k.endswith(".jpg"))
    for path in covers:
        if path not in fa or path not in fb:
            r.failures.append(f"{path}: only in the {'second' if path not in fa else 'first'}")
        elif fa[path] != fb[path]:
            r.failures.append(f"{path}: the bytes differ ({len(fa[path])} bytes against {len(fb[path])})")

    lines = [f"Compared {len(set(ta) & set(tb))} songs, {len(sidecars)} sidecar files, {len(covers)} covers, {len(prints)} fingerprints ({same_prints} identical byte for byte).", ""]
    if r.largest:
        lines += ["| Field | Largest difference | Allowed | Where |", "|---|---|---|---|"]
        for field in sorted(r.largest):
            d, tol, where = r.largest[field]
            lines.append(f"| `{field}` | {d:.6g} | {tol:g} | {where} |")
    else:
        lines.append("Every compared value is identical.")
    lines.append("")
    if r.failures:
        lines.append(f"**{len(r.failures)} difference(s) beyond the tolerance:**")
        lines += [f"- {f}" for f in r.failures[:50]]
    else:
        lines.append("Everything else is identical; nothing is beyond the tolerance.")
    text = "\n".join(lines) + "\n"
    print(text)
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text)
    sys.exit(1 if r.failures else 0)


if __name__ == "__main__":
    main()
