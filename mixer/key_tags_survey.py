#!/usr/bin/env python3
"""Research R, tag survey: how many music files already carry a key written by a DJ tool, in which tag, and in which
notation. Tags only: ffprobe reads the container's metadata (no audio is decoded) and, for MP3, a small reader lists the
ID3v2 frames (GEOB and PRIV owner names, which ffprobe does not show). No file is changed.

  .venv/bin/python key_tags_survey.py [--library <folder>] [--outside <folder with audio/ and the xlsx>]

Library default: ~/personal/90s2000 playlist. Folders whose name starts with "_" are skipped, except that the sprint's
_pool build/newfiles/probe.json (its tag_key column, read from TKEY) is summarised. With --outside, the GiantSteps-MTG-key
clips are surveyed too and any key tag is compared with the data set's human label. Writes key_tags_survey.tsv (per
folder counts; no file paths beyond the top folder name)."""
import json, os, re, struct, subprocess, sys, time, shutil
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
FFPROBE = shutil.which("ffprobe") or "/opt/homebrew/bin/ffprobe"
AUDIO = (".mp3", ".m4a", ".mp4", ".aac", ".flac", ".wav", ".aif", ".aiff", ".ogg", ".opus", ".alac", ".wma")

CAMELOT = re.compile(r"^(1[0-2]|0?[1-9])[AB]$", re.I)
OPENKEY = re.compile(r"^(1[0-2]|0?[1-9])[dm]$")
SHORT = re.compile(r"^[A-G][#b♯♭]?m?$")
LONG = re.compile(r"^[A-G][#b♯♭]? ?(maj|min|major|minor)$", re.I)
CAM_IN_TEXT = re.compile(r"(?<![\w.])(1[0-2]|0?[1-9])[AB](?![\w])")

def notation(v):
    v = v.strip()
    if CAMELOT.match(v): return "camelot"
    if OPENKEY.match(v): return "open key"
    if SHORT.match(v): return "short (Am, F#)"
    if LONG.match(v): return "long (A minor)"
    return "other"

def id3_frames(path):
    """[(frame id, description)] of the ID3v2 tag at the file's start: the description is the GEOB/PRIV/TXXX owner
    or description string. Reads the tag bytes only."""
    out = []
    try:
        with open(path, "rb") as fh:
            h = fh.read(10)
            if len(h) < 10 or h[:3] != b"ID3": return out
            ver = h[3]; size = (h[6] << 21) | (h[7] << 14) | (h[8] << 7) | h[9]
            data = fh.read(size)
        i = 0
        if h[5] & 0x40 and ver >= 3:   # extended header
            ext = struct.unpack(">I", data[:4])[0]
            i = ext if ver == 3 else ((data[0] << 21) | (data[1] << 14) | (data[2] << 7) | data[3])
            if ver == 3: i += 4
        while i + 10 <= len(data):
            fid = data[i:i + 4]
            if not re.match(rb"^[A-Z0-9]{4}$", fid): break
            b = data[i + 4:i + 8]
            fs = ((b[0] << 21) | (b[1] << 14) | (b[2] << 7) | b[3]) if ver == 4 else struct.unpack(">I", b)[0]
            body = data[i + 10:i + 10 + fs]; desc = ""
            if fid == b"PRIV": desc = body.split(b"\0", 1)[0].decode("latin-1", "replace")
            elif fid in (b"GEOB", b"TXXX") and body:
                enc = body[0]; rest = body[1:]
                if fid == b"GEOB": rest = rest.split(b"\0", 1)[1] if b"\0" in rest else b""   # skip MIME type
                if fid == b"GEOB": rest = rest.split(b"\0\0" if enc in (1, 2) else b"\0", 1)[1] if rest else b""   # skip file name
                term = b"\0\0" if enc in (1, 2) else b"\0"
                raw = rest.split(term, 1)[0]
                try: desc = raw.decode({0: "latin-1", 1: "utf-16", 2: "utf-16-be", 3: "utf-8"}.get(enc, "latin-1"), "replace")
                except Exception: desc = ""
            out.append((fid.decode(), desc.strip("\0 ")))
            i += 10 + fs
    except Exception:
        pass
    return out

def ffprobe_tags(path):
    p = subprocess.run([FFPROBE, "-v", "error", "-show_entries", "format_tags:stream_tags", "-of", "json", path],
                       capture_output=True, text=True)
    try: j = json.loads(p.stdout or "{}")
    except Exception: return {}
    tags = dict(j.get("format", {}).get("tags", {}) or {})
    for s in j.get("streams", []) or []:
        for k, v in (s.get("tags") or {}).items(): tags.setdefault(k, v)
    return tags

def survey_file(path):
    """dict of findings for one file: key values by source, and DJ-tool fingerprints."""
    tags = ffprobe_tags(path); low = {k.lower(): (k, v) for k, v in tags.items()}
    frames = id3_frames(path) if path.lower().endswith(".mp3") else []
    f = {"keys": {}, "marks": set()}
    if "tkey" in low: f["keys"]["TKEY"] = low["tkey"][1]
    for k in ("initialkey", "initial key", "key"):
        if k in low and k != "tkey": f["keys"]["INITIALKEY field" if k != "key" else "KEY field"] = low[k][1]
    com = " ".join(v for k, v in tags.items() if k.lower() in ("comment", "comm", "description") or k.lower().startswith("comment"))
    if CAM_IN_TEXT.search(com) or re.search(r"energy\s*\d", com, re.I):
        m = CAM_IN_TEXT.search(com); f["keys"]["comment (Mixed In Key style)"] = m.group(0) if m else "energy only"
    title = tags.get("title", "") or tags.get("TITLE", "")
    m = re.match(r"^\s*((1[0-2]|0?[1-9])[AB])\s*[-_ ]", title)
    if m: f["keys"]["title prefix"] = m.group(1)
    if any(k.lower() in ("energylevel", "energy") for k in tags): f["marks"].add("energy field (Mixed In Key)")
    if any(k.upper().startswith("SERATO") for k in tags) or any(d.lower().startswith("serato") for fid, d in frames if fid == "GEOB"):
        f["marks"].add("Serato data")
    blob = " ".join(d for _, d in frames).lower() + " " + " ".join(tags).lower()
    if "rekordbox" in blob or "pioneer" in blob: f["marks"].add("rekordbox/Pioneer data")
    if "traktor" in blob: f["marks"].add("Traktor data")
    if "mixed in key" in blob or "mixedinkey" in blob: f["marks"].add("Mixed In Key data")
    return f

def walk(root):
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if not d.startswith("_") and not d.startswith(".")]
        for fn in fns:
            if fn.lower().endswith(AUDIO) and not fn.startswith("."):
                yield os.path.join(dp, fn)

def pc_mode(v):
    """(pitch class, mode) from a key value in any of the notations, or None."""
    PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    v = v.strip().replace("♯", "#").replace("♭", "b")
    import key_light as KL
    if CAMELOT.match(v):
        n, l = int(v[:-1]), v[-1].upper(); tab = KL.CAM_MAJ if l == "B" else KL.CAM_MIN
        return tab.index(f"{n}{l}"), "major" if l == "B" else "minor"
    if OPENKEY.match(v):   # open key: 1d = C major, 1m = A minor; each step a fifth up
        n = int(v[:-1]); return ((n - 1) * 7 + (0 if v[-1] == "d" else 9)) % 12, "major" if v[-1] == "d" else "minor"
    m = re.match(r"^([A-G])([#b]?)\s*(m|min|minor|maj|major)?$", v, re.I)
    if not m: return None
    pc = (PC[m.group(1).upper()] + {"#": 1, "b": -1, "": 0}[m.group(2)]) % 12
    q = (m.group(3) or "").lower()
    return pc, "minor" if q in ("m", "min", "minor") else "major"

def main():
    a = sys.argv; t0 = time.time()
    lib = a[a.index("--library") + 1] if "--library" in a else os.path.expanduser("~/personal/90s2000 playlist")
    outside = a[a.index("--outside") + 1] if "--outside" in a else None
    per = defaultdict(Counter); fmt = defaultdict(Counter); found = {}
    files = list(walk(lib))
    print(f"library: {len(files)} audio files", file=sys.stderr)
    for k, p in enumerate(files, 1):
        rel = os.path.relpath(p, lib); top = rel.split(os.sep)[0] if os.sep in rel else "(top level)"
        f = survey_file(p); c = per[top]; c["files"] += 1; found[os.path.realpath(p)] = f["keys"]
        if f["keys"]: c["any key"] += 1
        for src, v in f["keys"].items():
            c[src] += 1
            if src != "comment (Mixed In Key style)" or v != "energy only": fmt[top][notation(v)] += 1; fmt["ALL"][notation(v)] += 1
        for m in f["marks"]: c[m] += 1
        if k % 500 == 0: print(f"  {k}/{len(files)} {time.time() - t0:.0f}s", file=sys.stderr)
    # the sprint's probe.json (read from TKEY by probe_new.py)
    probe = os.path.join(lib, "_pool build", "newfiles", "probe.json")
    pj = json.load(open(probe)) if os.path.exists(probe) else []
    pc = Counter(); pf = Counter()
    for r in pj:
        pc["files"] += 1
        if r.get("tag_key"): pc["any key"] += 1; pc["TKEY"] += 1; pf[notation(r["tag_key"])] += 1
    # the outside set
    oc = Counter(); of = Counter(); match = Counter()
    if outside:
        import key_outside as KO
        ann = KO.read_annotations(os.path.join(outside, "Beatport-EDM-Key-Dataset.xlsx"))
        clips = []
        for dp, _, fns in os.walk(os.path.join(outside, "audio")):
            for fn in fns:
                m = re.match(r"(\d+)", fn)
                if m and fn.lower().endswith(AUDIO) and not fn.startswith("."): clips.append((m.group(1), os.path.join(dp, fn)))
        print(f"outside set: {len(clips)} clips", file=sys.stderr)
        for cid, p in clips:
            f = survey_file(p); oc["files"] += 1
            if f["keys"]: oc["any key"] += 1
            for src, v in f["keys"].items():
                oc[src] += 1; of[notation(v)] += 1
                lab = ann.get(cid, {}).get("camelot"); got = pc_mode(v)
                if lab and got:
                    import key_light as KL
                    match["compared"] += 1; match["exact"] += KL.camelot(*got) == lab
            for m in f["marks"]: oc[m] += 1
    # the crate tracks (candidates.json) whose file carries a TKEY: agreement with Apple's key and with row 3f
    # (key_parity_keys.tsv). Agreement, not accuracy: the crate has no human key labels.
    agree = Counter()
    kp, cj = os.path.join(HERE, "key_parity_keys.tsv"), os.path.join(HERE, "candidates.json")
    if os.path.exists(kp) and os.path.exists(cj):
        import csv, key_light as KL
        keys = {r["id"]: r for r in csv.DictReader(open(kp), delimiter="\t")}
        for c in json.load(open(cj)):
            v = found.get(os.path.realpath(c["path"]), {}).get("TKEY"); r = keys.get(c["id"])
            got = pc_mode(v) if v else None
            if not (got and r): continue
            tag = KL.camelot(*got); agree["crate tracks with TKEY"] += 1
            for ref in ("apple", "key_3f", "lab"):
                if r.get(ref): agree[ref + " n"] += 1; agree[ref + " same"] += tag == r[ref]
        print("crate tracks with a TKEY: " + ", ".join(f"{k} {v}" for k, v in sorted(agree.items())))
    cols = ["files", "any key", "TKEY", "INITIALKEY field", "KEY field", "comment (Mixed In Key style)", "title prefix",
            "energy field (Mixed In Key)", "Serato data", "rekordbox/Pioneer data", "Traktor data", "Mixed In Key data"]
    fcols = ["camelot", "open key", "short (Am, F#)", "long (A minor)", "other"]
    with open(os.path.join(HERE, "key_tags_survey.tsv"), "w") as fh:
        fh.write("source\t" + "\t".join(cols + ["format: " + x for x in fcols]) + "\n")
        tot = Counter()
        for top in sorted(per):
            tot.update(per[top])
            fh.write(top + "\t" + "\t".join(str(per[top][c]) for c in cols) + "\t" + "\t".join(str(fmt[top][x]) for x in fcols) + "\n")
        fh.write("LIBRARY TOTAL (folders not starting with _)\t" + "\t".join(str(tot[c]) for c in cols) + "\t" + "\t".join(str(fmt["ALL"][x]) for x in fcols) + "\n")
        fh.write("_pool build/newfiles/probe.json (tag_key)\t" + "\t".join(str(pc[c]) for c in cols) + "\t" + "\t".join(str(pf[x]) for x in fcols) + "\n")
        if outside:
            fh.write(f"outside set (GiantSteps-MTG-key clips); tag vs label exact {match['exact']} of {match['compared']}\t"
                     + "\t".join(str(oc[c]) for c in cols) + "\t" + "\t".join(str(of[x]) for x in fcols) + "\n")
        if agree:
            fh.write(f"crate tracks with TKEY: same key as Apple {agree['apple same']} of {agree['apple n']}, as row 3f {agree['key_3f same']} of {agree['key_3f n']}, "
                     f"as the lab {agree['lab same']} of {agree['lab n']}\t{agree['crate tracks with TKEY']}" + "\t" * (len(cols) + len(fcols) - 1) + "\n")
    print(open(os.path.join(HERE, "key_tags_survey.tsv")).read())
    print(f"survey took {time.time() - t0:.0f}s")

if __name__ == "__main__":
    main()
