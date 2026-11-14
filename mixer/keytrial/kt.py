#!/usr/bin/env python3
"""Key trial (research X2): shared code. Data sets by path, labels, artist-grouped folds, the scorer.

Nothing here is tuned. The data sets are third-party and for evaluation only: they are read by path from
$DECKIE_KT_DATA and never committed. Layout (see README.md in this folder for the fetch commands):

  $DECKIE_KT_DATA/mtg/audio/<id> ....mp3      GiantSteps-MTG-key (Zenodo 1101082)  + Beatport-EDM-Key-Dataset.xlsx
  $DECKIE_KT_DATA/gsplus/audio/<id> ....mp3   GiantSteps+ (Zenodo 1095691)         + GiantSteps+.xlsx
  $DECKIE_KT_DATA/gs/audio/<id>.LOFI.mp3      GiantSteps Key (604)                 + repo/annotations/key/*.key
  $DECKIE_KT_CACHE                            features and model outputs (large; never committed)

A key is an integer 0..23: home note (pitch class, C = 0) + 12 if minor. That is key_parity.cam24's order."""
import os, re, sys, csv, zipfile, hashlib
from collections import Counter, defaultdict
from math import comb
import xml.etree.ElementTree as ET
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MIXER = os.path.dirname(HERE)
sys.path.insert(0, MIXER)
DATA = os.environ.get("DECKIE_KT_DATA", "")
CACHE = os.environ.get("DECKIE_KT_CACHE", "")

PC = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8,
      "A": 9, "A#": 10, "Bb": 10, "B": 11}
NOTE = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
CAM_MAJ = ["8B", "3B", "10B", "5B", "12B", "7B", "2B", "9B", "4B", "11B", "6B", "1B"]
CAM_MIN = ["5A", "12A", "7A", "2A", "9A", "4A", "11A", "6A", "1A", "8A", "3A", "10A"]
CAM = CAM_MAJ + CAM_MIN
PLAIN = re.compile(r"^([A-G][#b]?) ?(major|minor)$")
MODAL = re.compile(r"^([A-G][#b]?) ?(major|minor)( [a-z\-]+)?$")   # 'F minor aeolian', 'D major mixolydian'

def key_of(label, modal=False):
    """'A minor' -> 21. None for X, 'other', key changes ('A minor | A major') and, unless modal, modal names.
    With modal=True a label such as 'F minor aeolian' or 'E minor phrygian' counts by its third (minor)."""
    m = (MODAL if modal else PLAIN).match(str(label).strip())
    if not m or m.group(1) not in PC: return None
    return PC[m.group(1)] + (12 if m.group(2) == "minor" else 0)

def key_name(k): return f"{NOTE[k % 12]} {'minor' if k >= 12 else 'major'}"

def read_xlsx(path):
    """First sheet as a list of dicts (stdlib XML only; no code from the data set is run)."""
    M = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    z = zipfile.ZipFile(path)
    ss = ["".join(t.text or "" for t in si.iter(M + "t")) for si in ET.fromstring(z.read("xl/sharedStrings.xml")).iter(M + "si")]
    out, head = [], None
    for r in ET.fromstring(z.read("xl/worksheets/sheet1.xml")).iter(M + "row"):
        d = {}
        for c in r.findall(M + "c"):
            v = c.find(M + "v")
            if v is None: continue
            d[re.match("[A-Z]+", c.get("r")).group()] = ss[int(v.text)] if c.get("t") == "s" else v.text
        if head is None: head = d; continue
        out.append({head[k]: v for k, v in d.items() if k in head})
    return out

def audio_files(folder):
    files = {}
    for root, _, fs in os.walk(folder):
        for f in fs:
            m = re.match(r"(\d+)", f)
            if m and f.lower().endswith((".mp3", ".wav", ".flac", ".m4a")) and not f.startswith("."): files[m.group(1)] = os.path.join(root, f)
    return files

REMIX = re.compile(r"^(.+?) (?:remix|rmx|rework|re-edit|bootleg|refix|vip)$", re.I)
def artist_names(artists, mix=""):
    """The names that make two clips 'the same artist': every credited artist and a named remixer."""
    names = {a.strip().lower() for a in str(artists or "").split(",") if a.strip()}
    m = REMIX.match(str(mix or "").strip())
    if m: names |= {a.strip().lower() for a in re.split(r",|&| and | vs\.? ", m.group(1)) if a.strip()}
    return names

def load(name):
    """Clips of one data set: list of dicts id, path, key (plain label or None), key_modal, conf, names, genre."""
    root = os.path.join(DATA, name); files = audio_files(os.path.join(root, "audio")); out = []
    if name == "gsplus": files.update(audio_files(os.path.join(DATA, "gs", "audio")))   # the same Beatport previews
    if name == "mtg":
        for r in read_xlsx(os.path.join(root, "Beatport-EDM-Key-Dataset.xlsx")):
            out.append({"id": r["id"], "label": r.get("main_key", ""), "key": key_of(r.get("main_key", "")), "conf": int(r.get("confidence", -1)),
                        "names": artist_names(r.get("artists"), r.get("mix")), "genre": r.get("genres", ""), "label_name": r.get("label", "")})
    elif name == "gsplus":
        for r in read_xlsx(os.path.join(root, "GiantSteps+.xlsx")):
            lab = r.get("global-key", "")
            out.append({"id": r["id"], "label": lab, "key": key_of(lab), "key_modal": key_of(lab, modal=True), "conf": int(r["confidence"]) if r.get("confidence") else -1,
                        "names": artist_names(r.get("artists"), r.get("mix")), "genre": r.get("genres", ""), "revised": r.get("+") == "+"})
    elif name == "gs":
        d = os.path.join(root, "repo", "annotations", "key")
        px = os.path.join(DATA, "gsplus", "GiantSteps+.xlsx"); plus = {r["id"]: r for r in read_xlsx(px)} if os.path.exists(px) else {}
        for f in sorted(os.listdir(d), key=lambda s: int(s.split(".")[0])):
            cid = f.split(".")[0]; lab = open(os.path.join(d, f)).read().strip(); p = plus.get(cid, {})
            out.append({"id": cid, "label": lab, "key": key_of(lab), "conf": -1, "names": artist_names(p.get("artists"), p.get("mix")), "genre": p.get("genres", "")})
    else: raise ValueError(name)
    for c in out: c["path"] = files.get(c["id"]); c["set"] = name
    return [c for c in out if c["path"]]

# ----------------------------------------------------------------------------------------------- folds
NFOLD = 5
HELD = (3, 4)          # the held-out part for any choice between untrained variants; folds 0-2 are the selection part

def artist_groups(clips):
    """Union-find over artist and remixer names: clips sharing any name fall in one group. A clip with no name is its
    own group. Returns a group number per clip."""
    parent = {}
    def find(x):
        while parent.setdefault(x, x) != x: parent[x] = parent[parent[x]]; x = parent[x]
        return x
    for i, c in enumerate(clips):
        nm = sorted(c["names"]) or [f"__clip{c['id']}"]
        for n in nm: parent[find(n)] = find(nm[0])
    roots = [find((sorted(c["names"]) or [f"__clip{c['id']}"])[0]) for c in clips]
    idx = {r: k for k, r in enumerate(sorted(set(roots)))}
    return [idx[r] for r in roots]

def folds(clips, n=NFOLD):
    """Deterministic artist-grouped folds: groups in a fixed pseudo-random order (md5 of the group's smallest clip id),
    largest first, each to the fold that is furthest behind on its share of major-key and minor-key clips. A clip's
    fold depends only on the data set's spreadsheet, not on any audio or result."""
    g = artist_groups(clips); members = defaultdict(list)
    for i, gi in enumerate(g): members[gi].append(i)
    order = sorted(members, key=lambda gi: (-len(members[gi]), hashlib.md5(str(min(int(clips[i]["id"]) for i in members[gi])).encode()).hexdigest()))
    cnt = np.zeros((n, 3)); fold = [0] * len(clips)       # per fold: major, minor, other-label clips
    tot = np.zeros(3)
    kind = lambda c: 2 if c["key"] is None else (1 if c["key"] >= 12 else 0)
    for c in clips: tot[kind(c)] += 1
    for gi in order:
        add = np.zeros(3)
        for i in members[gi]: add[kind(clips[i])] += 1
        cost = [float((((cnt[f] + add) / np.maximum(tot, 1)) ** 2).sum() - ((cnt[f] / np.maximum(tot, 1)) ** 2).sum()) for f in range(n)]
        f = int(np.argmin(cost)); cnt[f] += add
        for i in members[gi]: fold[i] = f
    return fold, g

# ----------------------------------------------------------------------------------------------- scoring
MIREX = {"exact": 1.0, "fifth": 0.5, "relative": 0.3, "parallel": 0.2}
def relation(pred, true):
    """MIREX relation of two keys 0..23. fifth: same mode, home notes a fifth apart either way. relative: C major and
    A minor. parallel: same home note, other mode."""
    if pred == true: return "exact"
    pt, pm, tt, tm = pred % 12, pred // 12, true % 12, true // 12
    if pm == tm and (pt - tt) % 12 in (5, 7): return "fifth"
    if pm != tm and pt == tt: return "parallel"
    if pm != tm and ((tm == 0 and (pt - tt) % 12 == 9) or (tm == 1 and (pt - tt) % 12 == 3)): return "relative"
    return "other"

def stats(pred, true):
    """The trial's scores, percent. exact: key right. home: home note right (exact + parallel). mode|home: of the clips
    whose home note is right, the share with the right mode. Plus the MIREX classes and weighted score."""
    pred = np.asarray(pred); true = np.asarray(true); n = len(true)
    if not n: return {"n": 0}
    c = Counter(relation(int(p), int(t)) for p, t in zip(pred, true))
    d = {k: 100 * c[k] / n for k in ("exact", "fifth", "relative", "parallel", "other")}
    home = c["exact"] + c["parallel"]
    d.update(n=n, home=100 * home / n, mode_home=100 * c["exact"] / home if home else float("nan"), n_home=home,
             mirex=100 * sum(MIREX.get(k, 0) * v for k, v in c.items()) / n)
    return d

def halves(pred, true):
    pred = np.asarray(pred); true = np.asarray(true); mi = true >= 12
    return stats(pred, true), stats(pred[~mi], true[~mi]), stats(pred[mi], true[mi])

def sign_p(g, l):
    """Two-sided exact sign test on the discordant clips (one reader right, the other wrong)."""
    n = g + l
    if not n: return 1.0
    k = min(g, l); return min(1.0, 2 * sum(comb(n, i) for i in range(k + 1)) / 2 ** n)

def paired(a_ok, b_ok):
    """gained, lost, p: clips where b is right and a wrong, the reverse, and the sign test."""
    a_ok = np.asarray(a_ok, bool); b_ok = np.asarray(b_ok, bool)
    g = int((b_ok & ~a_ok).sum()); l = int((a_ok & ~b_ok).sum()); return g, l, sign_p(g, l)

def wilson(k, n, z=1.96):
    """95 percent Wilson interval for a share k / n, in percent."""
    if not n: return (float("nan"), float("nan"))
    p = k / n; den = 1 + z * z / n; mid = (p + z * z / (2 * n)) / den
    half = z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return 100 * (mid - half), 100 * (mid + half)

def apple_keys():
    """id -> Apple's key (0..23) on the MTG clips, from the committed sheet of letter R (mixer/key_outside_apple.tsv)."""
    out = {}
    for r in csv.DictReader(open(os.path.join(MIXER, "key_outside_apple.tsv")), delimiter="\t"):
        if r["apple"] in CAM: out[r["id"]] = CAM.index(r["apple"])
    return out

# D16's bar: exact within five points of Apple's framework on the same clips, on each mode half (letter R: Apple
# 41.5 on the 386 major clips and 75.6 on the 884 minor clips of the 1,270 it read).
BAR_MARGIN = 5.0

def fmt(x, nd=1): return "" if x is None or (isinstance(x, float) and np.isnan(x)) else f"{x:.{nd}f}"
