#!/usr/bin/env python3
"""Score a Deckie crate against the 90s/2000s sprint's data, keeping the two kinds of data apart.

Known facts (answer key): the track's artist and song name, from the compilations' own tags and the disc map
(the sprint's pool.json title "Artist - Song" and candidates.json artist/song).
Agreement with the early version (not truth): the sprint's BPM (hand overrides and folded values included), the
lab's key for the 373 candidates (key_parity_keys.tsv), the era and kind labels, the Halloween flag and the
version groupings (cut_key). Deckie writes none of era, kind, Halloween or cut_key yet, so those columns are
sprint-only and are reported as "no Deckie value".

Usage: sprint_check.py <crate.deckiecrate> [--pool "<music folder>/_pool build"] [--out sprint_check]
Writes <out>.tsv (one row per sprint track found in the crate, columns prefixed fact. / early. / deckie.)
and <out>.md (the summary, per bucket).
"""
import argparse, collections, csv, json, os, re, sys, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_POOL = "/Users/christophershannon/personal/90s2000 playlist/_pool build"


def norm(s):
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(ch for ch in s if not unicodedata.combining(ch)).casefold()
    s = s.replace("&", " and ").replace("’", "'")
    s = re.sub(r"\b(feat|ft|featuring)\.?\b", " feat ", s)
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def core(s):
    """Song name without bracketed or dashed version text: 'Missing (Todd Terry Club Mix)' -> 'missing'."""
    s = re.sub(r"[\(\[].*?[\)\]]", " ", s or "")
    s = re.split(r"\s+-\s+", s)[0]
    return norm(s)


def split_title(title):
    parts = re.split(r"\s+-\s+", title or "", maxsplit=1)
    return (parts[0], parts[1]) if len(parts) == 2 else ("", title or "")


def bpm_relation(a, b, tol=0.02):
    if not a or not b:
        return "no value"
    for name, k in (("same", 1.0), ("double", 2.0), ("half", 0.5), ("3:2", 1.5), ("2:3", 2 / 3),
                    ("4:3", 4 / 3), ("3:4", 0.75)):
        if abs(b / a - k) <= tol * k:
            return name
    if abs(b / a - 1) <= 2 * tol:
        return "close (2 to 4 percent)"
    return "off"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("crate")
    ap.add_argument("--pool", default=DEFAULT_POOL)
    ap.add_argument("--out", default=os.path.join(HERE, "sprint_check"))
    a = ap.parse_args()

    crate = json.load(open(os.path.join(a.crate, "crate.json")))["tracks"]
    manifest = json.load(open(os.path.join(a.crate, "manifest.json")))
    by_rel = {t["file"]["rel"]: t for t in crate}
    # files the build dropped as byte-for-byte duplicates point at the file that has the record
    for e in manifest.get("import_log", {}).get("entries", []):
        if e.get("reason") == "duplicate":
            m = re.search(r"the same bytes as (.+), which has the record", e.get("message", ""))
            if m and m.group(1) in by_rel:
                by_rel[e["rel"]] = by_rel[m.group(1)]

    pool = json.load(open(os.path.join(a.pool, "newfiles", "pool.json")))
    cands = {c["id"]: c for c in json.load(open(os.path.join(a.pool, "mixer", "candidates.json")))}
    lab_key = {}
    kp = os.path.join(HERE, "key_parity_keys.tsv")
    if os.path.exists(kp):
        for r in csv.DictReader(open(kp), delimiter="\t"):
            lab_key[r["id"]] = (r["lab"], r["lab_confident"] == "1")

    rows, missing = [], []
    for p in pool:
        t = by_rel.get(p["path"])
        if t is None:
            missing.append(p)
            continue
        c = cands.get(p["id"])
        if c and c.get("artist") and c.get("song"):
            f_artist, f_song = c["artist"], c["song"]
        else:
            f_artist, f_song = split_title(p["title"])
        d_artist = (t.get("ident") or {}).get("artist") or ""
        d_title = (t.get("ident") or {}).get("title") or ""
        if not d_artist and not d_title:
            name_match = "deckie has no name"
        elif not d_artist:
            name_match = "deckie has no artist"
        elif norm(d_artist) == norm(f_artist) and norm(d_title) == norm(f_song):
            name_match = "exact"
        elif norm(d_artist) == norm(f_song) and norm(d_title) == norm(f_artist):
            name_match = "swapped"
        elif norm(d_artist) == norm(f_artist) and core(d_title) == core(f_song):
            name_match = "same song, version text differs"
        elif core(d_title) == core(f_song) and (norm(f_artist) in norm(d_artist) or norm(d_artist) in norm(f_artist)):
            name_match = "same song, artist text differs"
        elif core(d_title) == core(f_song):
            name_match = "same song, other artist"
        else:
            name_match = "different"

        g = t.get("grid") or {}
        d_bpm = g.get("bpm")
        d_key = ((t.get("key") or {}).get("camelot")) or ""
        lk = lab_key.get(p["id"])
        if lk and d_key:
            key_rel = "same" if lk[0] == d_key else ("neighbour" if camelot_neighbour(lk[0], d_key) else "off")
            key_rel += "" if lk[1] else " (lab unsure)"
        else:
            key_rel = ""
        rows.append({
            "rel": p["path"], "src": p["src"], "top": p["path"].split("/")[0] if "/" in p["path"] else "(root)",
            "fact.artist": f_artist, "fact.song": f_song,
            "deckie.artist": d_artist, "deckie.title": d_title, "name_match": name_match,
            "early.bpm": p.get("bpm"), "early.bpm_tag": p.get("bpm_tag", ""), "early.bpm_meas": p.get("bpm_meas", ""),
            "deckie.bpm": round(d_bpm, 2) if d_bpm else "", "deckie.bpm_confidence": g.get("confidence", ""),
            "bpm_agreement": bpm_relation(p.get("bpm"), d_bpm),
            "early.key": lk[0] if lk else "", "early.key_confident": (1 if lk and lk[1] else 0) if lk else "",
            "deckie.key": d_key, "key_agreement": key_rel,
            "early.era": p.get("era", ""), "early.kind": p.get("kind", ""), "early.hal": int(bool(p.get("hal"))),
            "early.cut_key": (c or {}).get("cut_key", ""), "early.is_longest": (c or {}).get("is_longest", ""),
            "deckie.era": (t.get("ident") or {}).get("era") or "", "deckie.kind": (t.get("ident") or {}).get("kind") or "",
            "deckie.cut_key": (t.get("ident") or {}).get("cut_key") or "",
        })

    cols = list(rows[0].keys())
    with open(a.out + ".tsv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, delimiter="\t")
        w.writeheader(); w.writerows(rows)

    out = []
    out.append(f"# Library crate against the sprint's data\n")
    out.append(f"Crate: {os.path.basename(a.crate)} ({len(crate)} tracks). Sprint pool: {len(pool)} entries, "
               f"{len(rows)} found in the crate, {len(missing)} not in it.\n")
    out.append("## Known facts: artist and song name (answer key)\n")
    out.append("Deckie's names come from the files' own tags; the sprint's from the compilations' tags and the disc map.\n")
    out.append(table(rows, "name_match"))
    out.append("\nPer source (the sprint's `src`: lib = the library's compilations, new = files added for the sprint, "
               "CD1..CD4 = the four-disc build, list = Mike's list):\n")
    out.append(bucket_table(rows, "src", "name_match", ("exact",)))
    out.append("\nPer compilation folder, worst first (share of exact matches):\n")
    out.append(bucket_table(rows, "top", "name_match", ("exact",), worst_first=True, limit=25))
    out.append("\n## Agreement with the early version (not truth)\n")
    out.append("BPM: the sprint's value, hand overrides and folded values included, against Deckie's grid BPM, within 2 percent.\n")
    out.append(table(rows, "bpm_agreement"))
    out.append("\nPer source:\n")
    out.append(bucket_table(rows, "src", "bpm_agreement", ("same",)))
    keyed = [r for r in rows if r["key_agreement"]]
    out.append(f"\nKey, for the {len(keyed)} of the 373 lab candidates in the crate (lab key from key_parity_keys.tsv):\n")
    out.append(table(keyed, "key_agreement"))
    out.append("\nEra, kind, Halloween flag and version groupings: Deckie writes none of these yet, so there is nothing "
               "to score; the sprint's values are in the sheet as early.era, early.kind, early.hal and early.cut_key.\n")
    if missing:
        out.append(f"\n## Sprint entries not found in the crate ({len(missing)})\n")
        out.append("Per source: " + ", ".join(f"{k} {v}" for k, v in collections.Counter(p["src"] for p in missing).most_common()) + "\n")
        for p in missing[:12]:
            out.append(f"- {p['path']}\n")
    open(a.out + ".md", "w").write("".join(out))
    print("".join(out))


def camelot_neighbour(a, b):
    try:
        na, ma = int(a[:-1]), a[-1]; nb, mb = int(b[:-1]), b[-1]
    except (ValueError, IndexError):
        return False
    if ma == mb:
        return (na - nb) % 12 in (1, 11)
    return na == nb


def table(rows, col):
    c = collections.Counter(r[col] for r in rows)
    n = len(rows) or 1
    lines = ["| value | tracks | share |", "|---|---:|---:|"]
    for k, v in c.most_common():
        lines.append(f"| {k} | {v} | {100*v/n:.1f}% |")
    return "\n".join(lines) + "\n"


def bucket_table(rows, by, col, good, worst_first=False, limit=None):
    g = collections.defaultdict(list)
    for r in rows:
        g[r[by]].append(r)
    items = []
    for k, rs in g.items():
        ok = sum(1 for r in rs if r[col] in good)
        items.append((k, len(rs), ok, ok / len(rs)))
    items.sort(key=(lambda x: x[3]) if worst_first else (lambda x: -x[1]))
    if limit:
        items = items[:limit]
    lines = [f"| {by} | tracks | {'/'.join(good)} | share |", "|---|---:|---:|---:|"]
    for k, n, ok, sh in items:
        lines.append(f"| {k} | {n} | {ok} | {100*sh:.1f}% |")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
