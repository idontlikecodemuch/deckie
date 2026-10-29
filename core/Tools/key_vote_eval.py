#!/usr/bin/env python3
"""The second key vote, evaluated offline: which cheap estimator, added to the engine's one, lifts the share of keys
that match the lab's where the lab is confident. No audio and no Swift: the lab's own sweep of chroma kinds and key
profiles over its 373 tracks (mixer/key_light.py, recorded per track in mixer/key_light_{stft,hpcp,cqt}.tsv and
mixer/key_ends_{stft,hpcp}.tsv) stands in for what a Swift port of each variant would give, as the STFT/edma column
stands in for the engine (the Mac bench's `key_engine` equals it on all 373 tracks; checked below).

  python3 -I core/Tools/key_vote_eval.py [--bench PATH] [--all]

Standard library and numpy only. Reads, from the repository: the five TSVs, mixer/features/<id>.json (the lab's key
and its confidence), and the first Mac bench sheet (docs/architecture/bench/pc-engine-2026-10-28-mac.json, from the
checkout if present, else `git show origin/main:<path>`, or the file given with --bench).

Terms. A key is a Camelot code (8A = A minor, 8B = C major). "Confident" is the lab's own cut: the lab's key
confidence (mixer/analyze.py's B.9 vote of Essentia's edma and bgate key profiles and madmom's CNN) at least 0.65,
as mixer/key_light.py and mixer/bench_mu.py both cut it: 311 of the 373 tracks. Against the lab's key a guess is
exact; relative (same number, other letter: the relative major or minor); neighbour (same letter, one step round the
wheel: a fifth away); or other (parallel major/minor included). The bench sheet's "neighbour" column is relative plus
neighbour (mixer/bench_mu.py's key_relation), so "exact or neighbour" below is exact + relative + neighbour.

A variant is a chroma kind (stft: librosa's chroma_stft, which the engine has; hpcp: key_light.py's hpcp(), a
harmonic-sum pitch-class profile from the STFT's spectral peaks, one new Swift port; cqt: librosa's constant-Q chroma,
a constant-Q transform the engine does not have) with one of six key profiles (krumhansl, temperley, shaath, edma,
bgate, braw: free, the engine already carries all six). Each variant gives per track a key, its correlation r with the
key's profile, and its margin (r minus the runner-up's r).

Vote rules tried (the engine's vote is always stft/edma):
  two votes      agree -> that key; disagree -> the larger margin, or the larger r, or the key an end window agrees
                 with (the mix-in or mix-out window's own key, from key_ends_stft or key_ends_hpcp; a tie or neither
                 -> the engine's, or the larger margin). "Disagree -> the engine's" is the engine itself.
  three votes    two or three agree -> that key; all differ -> the engine's, or the largest margin.
Every partner and pair of partners is tried (374 rules). No rule has a threshold or a weight: each is "agree -> that
key; disagree -> a fixed rule", and the profiles are published ones (below), none fitted to this set. The rule to
pick: the best exact rate on the confident tracks among the rules that do not lower "exact or neighbour", with the
fewest new ports (a second profile over the chroma the engine already computes if that clears 75 percent, hpcp() only
if it alone clears it, never CQT), and whose gain is not mostly (over half) in one lab folder; among rules still tied,
the lab's own decision rule, then the most folders gaining, then the fewest tracks changed.

The profiles, as mixer/key_light.py copies them verbatim from Essentia's key.cpp, and where Essentia's documentation
traces them: krumhansl, Krumhansl and Kessler's probe-tone ratings (Psychological Review 89, 1982; C. L. Krumhansl,
Cognitive Foundations of Musical Pitch, 1990); temperley, D. Temperley, "What's key for key? The Krumhansl-Schmuckler
key-finding algorithm reconsidered" (Music Perception 17, 1999); shaath, I. Shaath's Krumhansl-based profiles tuned
for popular and electronic music (MSc thesis, 2011, the basis of the KeyFinder program); edma, braw and bgate, Á.
Faraldo, E. Gómez, S. Jordà and P. Herrera, "Key estimation in electronic dance music" (ECIR 2016): edma derived
automatically from an electronic dance music corpus, braw the median profile per mode of a subset of the Beatport
dataset, bgate the same with its four least relevant degrees set to zero.

The lab folders (the bench sheet's `rel`): the crate's four CDs by their own labels (CD1 - 90s, CD2 - 2000s to now,
CD3 - Halloween, CD4 - House Electronic Ambient), the NOW Halloween compilation (rock and novelty songs), a handful of
other compilations, and the loose files at the top (mostly club remixes and edits).

Two checks against reading noise as gain, since the rules are scored on the same 311 tracks they are chosen on:
  held out   500 random halvings of the 311; on one half pick the family's best rule as above, score it on the
             other half against the engine. A family whose held-out gain is about zero only fits noise.
  Apple      agreement with Apple's Music Understanding key (the `mu` column, on 372 tracks), an estimator that
             had no part in the lab's key, so a rule that also moves towards it is not merely copying the lab.

Result (Oct 29, 2026, the first Mac bench sheet). Percent of the 311 confident tracks; nbr = relative + neighbour (the
sheet's column); chg / fix / brk = confident tracks whose key the rule changes, of them now right, right before and
wrong now; Apple = exact against Apple's key on its 372 tracks.

                                                                 exact   nbr  other  ex+nb   chg fix brk  Apple
  engine (stft.edma; the sheet's key_engine on all 373)           74.6  14.5   10.9   89.1     -   -   -   63.4
  stft.krumhansl / temperley / shaath alone                       68.2  17.0   14.8   85.2    55  13  33   59.4
                                                                  59.2  24.4   16.4   83.6   109  18  66   49.5
                                                                  69.1  16.4   14.5   85.5    47  11  28   59.7
  stft.bgate alone                                                73.0  17.4    9.6   90.4    38  11  16   61.3
  stft.braw alone                                                 74.9  18.0    7.1   92.9    43  17  16   64.0
  hpcp, best profile alone (edma; the six span 42.8 to 65.3)      64.3  19.0   16.7   83.3   131  40  72   53.5
  cqt, best profile alone (braw; the six span 44.4 to 59.2)       59.2  17.0   23.8   76.2   134  32  80   54.3
  two votes, engine + stft.braw, disagree -> larger margin        75.6  15.8    8.7   91.3    22  10   7   65.1
  two votes, engine + stft.bgate, disagree -> larger margin       75.6  16.1    8.4   91.6    18   8   5   63.2
  two votes, engine + stft.bgate, disagree -> stft end windows,   76.2  14.8    9.0   91.0    12   6   1   63.7
    else larger margin
* three votes, engine + stft.krumhansl + stft.bgate, majority     76.2  13.8   10.0   90.0     6   5   0   63.7
    else engine
  three votes, engine + stft.krumhansl + stft.braw, majority      76.2  13.8   10.0   90.0    10   7   2   64.5
    else engine
  three votes, engine + stft.braw + hpcp.edma, majority else      77.8  15.1    7.1   92.9    24  14   4   65.6
    largest margin (the best rule with hpcp(); not taken)
  three votes, engine + stft.braw + cqt.braw, majority else       76.5  16.1    7.4   92.6    26  12   6   65.3
    largest margin (the best rule with CQT; not taken)

  held out (best rule of a family picked on half, scored on the other half; gain in exact against the engine):
    no new port: mean +0.0 points (median 0.0, above zero in 46 percent of halvings); with hpcp(): mean +0.4 (median
    +0.6, 60 percent); with CQT: mean -0.3.

  by lab folder, exact on the confident tracks, engine -> picked rule (net tracks):
    CD1 - 90s 82.0 -> 82.0 (0 of 50); CD2 - 2000s to now 73.9 -> 76.1 (+1 of 46); CD3 - Halloween 70.0 -> 70.0
    (0 of 50); CD4 - House Electronic Ambient 71.2 -> 75.0 (+2 of 52); NOW Halloween 75.0 -> 75.0 (0 of 16); loose
    files 76.1 -> 77.3 (+1 of 88); other compilations 66.7 -> 77.8 (+1 of 9). Four folders gain, none loses, the
    largest share is 2 of the 5. Three of the five rules tied with it put 3 of their 5 in CD4 (flagged, not taken);
    the hpcp() rule gains in six folders, none losing.

* Picked: three votes over the chroma the engine already computes, each its own published key profile: edma (the
engine's), bgate and krumhansl; two or three agree -> that key; all three differ -> edma's. That is the lab's own
decision rule (mixer/analyze.py, B.9: Essentia's edma and bgate and madmom's CNN, falling back to edma) with
krumhansl in madmom's slot. It clears the mark with no new port: 237 of 311 exact (76.2 percent; the mark is 233.25
tracks, the engine 232), exact or neighbour 90.0 (89.1); 7 of the 373 tracks change key (6 confident: 5 now right,
none now wrong, 1 wrong either way); on all 373 against the lab 70.5 (68.9), on the 62 the lab is unsure of 41.9
(40.3), against Apple 63.7 (63.4). With the lab's B.9 confidence on the three votes (its one number, strength 0.6, from
the lab's code), the levels 1.0 / 0.65 / 0.6 / 0.45 / 0.3 hold 217 / 25 / 43 / 36 / 52 tracks and are exact on 81.1 /
76.2 / 75.0 / 61.5 / 60.0 percent of their confident tracks; 88 tracks fall under 0.5 and are flagged key_uncertain
(218 with the engine's one-estimator rule, whose margin steps were read off this sheet; 58 in the lab).

Caution: five tracks is the whole gain, a margin of 3.75 tracks over the mark. The held-out check says the no-port
family's gain does not carry to new music (it is within the noise of choosing among 40 rules on 311 tracks); on this
sheet it is reproducible, because the engine reproduces the lab's chroma. hpcp() is the one variant whose gain partly
survives (about +0.4 to +0.6 points out of sample against +3.2 on the sheet); a better key needs a better estimator,
not another profile on the same chroma.
"""
import argparse, csv, itertools, json, os, random, subprocess, sys
from collections import Counter
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MIXER = os.path.join(ROOT, "mixer")
BENCH = "docs/architecture/bench/pc-engine-2026-10-28-mac.json"
CONFIDENT = 0.65  # mixer/key_light.py and mixer/bench_mu.py: lab_conf >= 0.65
KINDS = ("stft", "hpcp", "cqt")
PROFILES = ("krumhansl", "temperley", "shaath", "edma", "bgate", "braw")
ENGINE = "stft.edma"
PORTS = {"stft": 0, "hpcp": 1, "cqt": 2}  # what a chroma kind costs to add: nothing, the hpcp() port, a constant-Q transform
# The rule this evaluation picks (see main()); the Swift engine carries it (DeckieCore/Key/KeyVote.swift).
CHOSEN = ("three", "stft.krumhansl", "stft.bgate", "engine")


def relation(a, b):
    """mixer/key_light.py's relation, with parallel folded into other as the bench sheet folds it."""
    if a == b: return "exact"
    na, la, nb, lb = int(a[:-1]), a[-1], int(b[:-1]), b[-1]
    if na == nb: return "relative"
    if la == lb and (na - nb) % 12 in (1, 11): return "neighbour"
    return "other"


def read_tsv(name):
    with open(os.path.join(MIXER, name)) as fh:
        return {r["id"]: r for r in csv.DictReader(fh, delimiter="\t")}


def read_bench(path):
    if path:
        return json.load(open(path))
    local = os.path.join(ROOT, BENCH)
    if os.path.exists(local):
        return json.load(open(local))
    out = subprocess.run(["git", "-C", ROOT, "show", f"origin/main:{BENCH}"], capture_output=True, check=True, text=True)
    return json.loads(out.stdout)


class Sheet:
    def __init__(self, bench):
        self.tsv = {k: read_tsv(f"key_light_{k}.tsv") for k in KINDS}
        self.ends = {k: read_tsv(f"key_ends_{k}.tsv") for k in ("stft", "hpcp")}
        self.bench = {t["id"]: t for t in bench["tracks"]}
        self.ids = sorted(self.bench)
        for k, t in list(self.tsv.items()) + list(self.ends.items()):
            assert set(t) == set(self.ids), f"{k}: track ids differ from the bench sheet"
        self.lab, self.conf = {}, {}
        for i in self.ids:
            key = json.load(open(os.path.join(MIXER, "features", f"{i}.json")))["key"]
            self.lab[i], self.conf[i] = key["camelot"], key["confidence"]
            assert key["camelot"] == self.bench[i]["key_lab"] and key["confidence"] == self.bench[i]["key_confidence_lab"]
            assert key["camelot"] == self.tsv["stft"][i]["lab"]
        self.apple = {i: self.tsv["stft"][i]["mu"] for i in self.ids if self.tsv["stft"][i]["mu"]}
        self.confident = [i for i in self.ids if self.conf[i] >= CONFIDENT]
        # variant name -> id -> (camelot, r, margin)
        self.var = {f"{k}.{p}": {i: (self.tsv[k][i][p], float(self.tsv[k][i][p + "_r"]), float(self.tsv[k][i][p + "_margin"]))
                                 for i in self.ids} for k in KINDS for p in PROFILES}
        self.engine = {i: self.bench[i]["key_engine"] for i in self.ids}
        same = sum(1 for i in self.ids if self.engine[i] == self.var[ENGINE][i][0])
        assert same == len(self.ids), f"the engine's key differs from stft/edma on {len(self.ids) - same} tracks"


def counts(sheet, est, ids, ref=None):
    ref = ref or sheet.lab
    c = Counter(relation(est[i], ref[i]) for i in ids)
    return np.array([c["exact"], c["relative"], c["neighbour"], c["other"]])


# ---- the rules ------------------------------------------------------------------------------------------------------

def two_votes(sheet, b, how, ends=None):
    a_, b_ = sheet.var[ENGINE], sheet.var[b]
    out = {}
    for i in sheet.ids:
        ka, kb = a_[i][0], b_[i][0]
        if ka == kb:
            out[i] = ka
            continue
        if ends:
            e = (sheet.ends[ends][i]["mix_in"], sheet.ends[ends][i]["mix_out"])
            va, vb = e.count(ka), e.count(kb)
            if va != vb:
                out[i] = ka if va > vb else kb
                continue
            if how == "engine":
                out[i] = ka
                continue
        if how == "margin": out[i] = ka if a_[i][2] >= b_[i][2] else kb
        elif how == "r": out[i] = ka if a_[i][1] >= b_[i][1] else kb
        else: out[i] = ka
    return out


def three_votes(sheet, b, c, fallback):
    out = {}
    for i in sheet.ids:
        votes = [sheet.var[ENGINE][i], sheet.var[b][i], sheet.var[c][i]]
        top, n = Counter(v[0] for v in votes).most_common(1)[0]
        if n >= 2: out[i] = top
        elif fallback == "engine": out[i] = votes[0][0]
        else: out[i] = max(votes, key=lambda v: v[2])[0]  # the first of equal margins, as Swift's vote breaks ties
    return out


def all_rules(sheet):
    """name -> (estimates, new ports, family)"""
    rules = {}
    partners = [v for v in sheet.var if v != ENGINE]
    def cost(*vs): return max(PORTS[v.split(".")[0]] for v in vs)
    for b in partners:
        rules[f"2: engine + {b}; disagree -> larger margin"] = (two_votes(sheet, b, "margin"), cost(b))
        rules[f"2: engine + {b}; disagree -> larger r"] = (two_votes(sheet, b, "r"), cost(b))
        for e in ("stft", "hpcp"):
            c = max(cost(b), PORTS[e])
            rules[f"2: engine + {b}; disagree -> {e} end windows, else engine"] = (two_votes(sheet, b, "engine", e), c)
            rules[f"2: engine + {b}; disagree -> {e} end windows, else margin"] = (two_votes(sheet, b, "margin", e), c)
    for b, c in itertools.combinations(partners, 2):
        for fb in ("engine", "margin"):
            rules[f"3: engine + {b} + {c}; majority, else {'engine' if fb == 'engine' else 'largest margin'}"] = (
                three_votes(sheet, b, c, fb), cost(b, c))
    return rules


def bucket(rel):
    """The lab folder a track sits in (the bench sheet's `rel`): the four crate CDs by their own labels (era or genre),
    the Halloween compilation, the other compilations, and the loose files at the top (mostly club remixes and edits)."""
    parts = rel.split("/")
    if parts[0] == "CDs v2": return parts[1]
    if len(parts) == 1: return "loose files (club remixes, edits)"
    if parts[0].startswith("VA - NOW That's What I Call Halloween"): return "NOW Halloween (2020)"
    return "other compilations"


def by_bucket(sheet, rules, names):
    """Per lab folder: the confident tracks, the engine's exact rate, and for each rule its exact rate and net gain
    (tracks now right less tracks now wrong). Flags a rule whose net gain sits mostly (over half) in one folder."""
    base = sheet.engine
    groups = {}
    for i in sheet.confident:
        groups.setdefault(bucket(sheet.bench[i]["rel"]), []).append(i)
    order = sorted(groups, key=lambda g: (not g.startswith("CD"), g))
    print(f"  {'folder':36} {'n':>4} {'engine':>7}" + "".join(f" | {'rule ' + str(k + 1):>8} {'net':>4}" for k in range(len(names))))
    nets = [Counter() for _ in names]
    for g in order:
        ids = groups[g]
        line = f"  {g:36} {len(ids):4d} {sum(1 for i in ids if base[i] == sheet.lab[i]) / len(ids) * 100:6.1f}%"
        for k, m in enumerate(names):
            est = rules[m][0]
            net = sum(1 for i in ids if est[i] == sheet.lab[i]) - sum(1 for i in ids if base[i] == sheet.lab[i])
            nets[k][g] = net
            line += f" | {sum(1 for i in ids if est[i] == sheet.lab[i]) / len(ids) * 100:7.1f}% {net:+4d}"
        print(line)
    for k, m in enumerate(names):
        total = sum(nets[k].values())
        top, most = max(nets[k].items(), key=lambda kv: kv[1])
        gaining = sum(1 for v in nets[k].values() if v > 0)
        losing = sum(1 for v in nets[k].values() if v < 0)
        flag = "  ** most of the gain in one folder" if total > 0 and most > total / 2 else ""
        print(f"  rule {k + 1}: {m}\n          net {total:+d} tracks; {gaining} folders gain, {losing} lose; the largest "
              f"share, {most:+d}, in {top}{flag}")
    return nets


def chosen_name():
    _, b, c, fb = CHOSEN
    return f"3: engine + {b} + {c}; majority, else {'engine' if fb == 'engine' else 'largest margin'}"


# ---- printing -------------------------------------------------------------------------------------------------------

def row(sheet, name, est, base=None):
    c = counts(sheet, est, sheet.confident); n = c.sum()
    p = c / n * 100
    ex_nb = c[:3].sum() / n * 100
    s = f"{p[0]:6.1f} {p[1]:6.1f} {p[2]:6.1f} {p[3]:6.1f} | {p[1] + p[2]:5.1f} {ex_nb:6.1f}"
    if base is not None:
        changed = sum(1 for i in sheet.confident if est[i] != base[i])
        fixed = sum(1 for i in sheet.confident if est[i] == sheet.lab[i] != base[i])
        broken = sum(1 for i in sheet.confident if base[i] == sheet.lab[i] != est[i])
        apple = counts(sheet, est, list(sheet.apple), sheet.apple)
        s += f" | {changed:3d} {fixed:3d} {broken:3d} | {apple[0] / apple.sum() * 100:5.1f}"
    return f"  {name:74} {s}"


HEAD = (f"  {'':74} {'exact':>6} {'rel':>6} {'nbr':>6} {'other':>6} | {'nbr*':>5} {'ex+nb':>6} | {'chg':>3} {'fix':>3} "
        f"{'brk':>3} | {'Apple':>5}")
LEGEND = ("  percent of the confident tracks; nbr* = relative + neighbour (the bench sheet's \"neighbour\"); ex+nb = exact\n"
          "  + relative + neighbour; chg / fix / brk = confident tracks whose key the rule changes from the engine's, of\n"
          "  them now exact, and exact before but not now; Apple = exact against Apple's key on all 372 tracks with one")


def held_out(sheet, rules, names, reps=500, seed=1):
    """Pick the best of `names` on one random half (best exact without lowering exact-or-neighbour), score on the other."""
    ids = sheet.confident
    ok = {n: np.array([relation(rules[n][0][i], sheet.lab[i]) for i in ids]) for n in names}
    base = np.array([relation(sheet.engine[i], sheet.lab[i]) for i in ids])
    rng = random.Random(seed)
    gains, picks = [], Counter()
    idx = list(range(len(ids)))
    for _ in range(reps):
        rng.shuffle(idx)
        a, b = np.array(idx[:len(idx) // 2]), np.array(idx[len(idx) // 2:])
        b_en = np.isin(base[a], ("exact", "relative", "neighbour")).sum()
        cand = [n for n in names if np.isin(ok[n][a], ("exact", "relative", "neighbour")).sum() >= b_en]
        best = max(cand, key=lambda n: (ok[n][a] == "exact").sum())
        picks[best] += 1
        gains.append(((ok[best][b] == "exact").sum() - (base[b] == "exact").sum()) / len(b) * 100)
    g = np.array(gains)
    return g.mean(), np.median(g), np.percentile(g, 10), (g > 0).mean(), picks.most_common(3)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--bench", help="the bench sheet JSON (default: the checkout's, else origin/main's)")
    ap.add_argument("--all", action="store_true", help="print every rule, not the best of each family")
    args = ap.parse_args()
    sheet = Sheet(read_bench(args.bench))
    n = len(sheet.confident)
    print(f"{len(sheet.ids)} tracks; {n} confident (lab key confidence >= {CONFIDENT}); the engine's key (bench "
          f"key_engine) equals stft.edma on all {len(sheet.ids)}; Apple's key on {len(sheet.apple)}\n")
    base = sheet.engine

    print("(a) the engine, and (b) each variant alone")
    print(HEAD)
    print(row(sheet, "engine (bench key_engine = stft.edma)", base, base))
    for v in sheet.var:
        if v != ENGINE:
            print(row(sheet, v, {i: sheet.var[v][i][0] for i in sheet.ids}, base))

    rules = all_rules(sheet)
    base_c = counts(sheet, base, sheet.confident)
    def ok(name):  # does not lower exact-or-neighbour
        return counts(sheet, rules[name][0], sheet.confident)[:3].sum() >= base_c[:3].sum()
    def exact(name): return counts(sheet, rules[name][0], sheet.confident)[0]
    families = [("same chroma, second profile (no new port)", 0), ("with hpcp() (one port)", 1),
                ("with a constant-Q transform (CQT)", 2)]
    print(f"\n(c) vote rules ({len(rules)} tried); per family, the rules that do not lower exact-or-neighbour, best "
          f"exact first{'' if args.all else ' (the top 8; --all for every rule)'}")
    print(HEAD)
    for label, cost in families:
        names = sorted((m for m in rules if rules[m][1] == cost), key=lambda m: (-exact(m), m))
        shown = [m for m in names if ok(m)] if not args.all else names
        print(f"  -- {label}: {len(names)} rules, {sum(1 for m in names if ok(m))} keep exact-or-neighbour")
        for m in shown[: None if args.all else 8]:
            print(row(sheet, m + ("" if ok(m) else "  [lowers ex+nb]"), rules[m][0], base))
    print(LEGEND)

    print("\n(d) held out: pick the best rule of a family on a random half of the confident tracks, score it on the "
          "other half (500 halvings); gain in exact, percentage points, against the engine")
    for label, cost in families:
        names = [m for m in rules if rules[m][1] <= cost]
        mean, med, p10, pos, picks = held_out(sheet, rules, names)
        print(f"  up to {label:44} mean {mean:+5.2f}  median {med:+5.2f}  10th percentile {p10:+5.2f}  "
              f"above zero {pos * 100:3.0f}%")
        for m, k in picks:
            print(f"      picked {k:3d} times: {m}")

    free = [m for m in rules if rules[m][1] == 0 and ok(m)]
    top = max(exact(m) for m in free)
    tied = sorted(m for m in free if exact(m) == top)
    hpcp_rule = max((m for m in rules if rules[m][1] == 1 and ok(m)), key=lambda m: (exact(m), -len(m)))
    print(f"\n(e) the pick. {sum(1 for m in free if exact(m) > 0.75 * n)} rules with no new port clear 75 percent without "
          f"lowering exact-or-neighbour, so nothing is ported (the best with hpcp(), {exact(hpcp_rule) / n * 100:.1f}, is "
          f"not taken).\n  Their best exact, {top} of {n}, is shared by {len(tied)} rules (1 to {len(tied)} below; the "
          f"last column is the best with hpcp(), for comparison). By lab folder, confident tracks:")
    nets = by_bucket(sheet, rules, tied + [hpcp_rule])[:len(tied)]
    low = [i for i in sheet.ids if sheet.conf[i] < CONFIDENT]
    # The pick among the tied: drop a rule whose gain sits mostly in one folder; then the lab's own decision rule (all
    # differ -> the engine's vote, as B.9 falls back to its first vote); then the most folders gaining; then the fewest
    # tracks changed.
    def spread(k):
        total = sum(nets[k].values())
        return total > 0 and max(nets[k].values()) <= total / 2
    def changes(m): return sum(1 for i in sheet.ids if rules[m][0][i] != base[i])
    pick = min((k for k in range(len(tied)) if spread(k)),
               key=lambda k: (not tied[k].endswith("else engine"), -sum(1 for v in nets[k].values() if v > 0),
                              changes(tied[k])))
    name = tied[pick]
    assert name == chosen_name(), f"the pick is {name}, CHOSEN says {chosen_name()}"
    est = rules[name][0]
    c = counts(sheet, est, sheet.confident)
    for k, m in enumerate(tied):
        a = counts(sheet, rules[m][0], list(sheet.apple), sheet.apple)
        lo = counts(sheet, rules[m][0], low)
        print(f"  {'*' if m == name else ' '} rule {k + 1}: ex+nb {counts(sheet, rules[m][0], sheet.confident)[:3].sum() / n * 100:5.1f}, "
              f"Apple exact {a[0] / a.sum() * 100:5.1f}, unsure-lab exact {lo[0] / lo.sum() * 100:5.1f}, tracks changed "
              f"{changes(m)}{'' if spread(k) else ', gain mostly in one folder'}")
    print(f"  * picked, rule {pick + 1}: {name}\n    (the gain is not mostly in one folder; the lab's own decision rule, "
          f"mixer/analyze.py B.9: two or three agree -> that key, else the first vote, edma; the most folders gaining)")
    print(f"  confident tracks: exact {c[0]} of {n} ({c[0] / n * 100:.1f} percent; the engine {base_c[0]}, "
          f"{base_c[0] / n * 100:.1f}); exact or neighbour {c[:3].sum()} ({c[:3].sum() / n * 100:.1f}; the engine "
          f"{base_c[:3].sum() / n * 100:.1f}); the mark of 75 percent is {0.75 * n:.2f} tracks")
    changed_all = [i for i in sheet.ids if est[i] != base[i]]
    print(f"  tracks whose key changes: {sum(1 for i in sheet.confident if est[i] != base[i])} of the {n} confident, "
          f"{len(changed_all)} of all {len(sheet.ids)}: " + " ".join(changed_all))
    for label, ids, ref in (("all 373 against the lab", sheet.ids, sheet.lab),
                            (f"the {len(low)} the lab is not confident on", low, sheet.lab),
                            ("all 372 against Apple", list(sheet.apple), sheet.apple)):
        a, b = counts(sheet, est, ids, ref), counts(sheet, base, ids, ref)
        print(f"  {label:36} exact {a[0] / a.sum() * 100:5.1f} (engine {b[0] / b.sum() * 100:5.1f}), exact or neighbour "
              f"{a[:3].sum() / a.sum() * 100:5.1f} (engine {b[:3].sum() / b.sum() * 100:5.1f})")
    # The confidence: the lab's B.9 rule with the three votes in the lab's three slots (DeckieEngine/KeyConfidence.swift):
    # edma for Essentia's edma, braw for its bgate, krumhansl for madmom's CNN. The strength is the r of the first of the
    # two profile slots that holds the decided key, else the larger of the two, as B.9 reads Essentia's strengths.
    _, third, second, _ = CHOSEN
    def neighbour(x, y):  # mixer/analyze.py's camelot_neighbour
        nx, lx, ny, ly = int(x[:-1]), x[-1], int(y[:-1]), y[-1]
        return (ny - nx) % 12 in (0, 1, 11) if lx == ly else nx == ny
    levels = {}
    for i in sheet.ids:
        v1, v2, v3 = sheet.var[ENGINE][i], sheet.var[second][i], sheet.var[third][i]
        key, nt = Counter((v1[0], v2[0], v3[0])).most_common(1)[0]
        if nt == 1: key = v1[0]
        assert key == est[i]
        strength = v1[1] if key == v1[0] else (v2[1] if key == v2[0] else max(v1[1], v2[1]))
        if nt == 3: kc = 1.0 if strength >= 0.6 else 0.6
        elif nt == 2:
            dissent = next(x for x in (v1[0], v2[0], v3[0]) if x != key)
            kc = 0.65 if neighbour(key, dissent) else 0.45
            if strength < 0.6: kc = 0.3
        else: kc = 0.3
        levels[i] = kc
    print("  the confidence, by the lab's B.9 rule on the three votes:")
    for kc in (1.0, 0.65, 0.6, 0.45, 0.3):
        ids = [i for i in sheet.confident if levels[i] == kc]
        a = counts(sheet, est, ids)
        print(f"    {kc:4}  {sum(1 for i in sheet.ids if levels[i] == kc):3d} tracks, {len(ids):3d} confident: exact "
              f"{a[0] / max(1, len(ids)) * 100:5.1f}, exact or neighbour {a[:3].sum() / max(1, len(ids)) * 100:5.1f}")
    print(f"    under 0.5, flagged key_uncertain: {sum(1 for i in sheet.ids if levels[i] < 0.5)} of {len(sheet.ids)} "
          f"(the engine's one-estimator rule: 218; the lab: {sum(1 for i in sheet.ids if sheet.conf[i] < 0.5)})")


if __name__ == "__main__":
    main()
