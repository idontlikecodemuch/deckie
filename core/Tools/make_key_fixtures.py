#!/usr/bin/env python3
"""Write the reference decisions the key estimator's Swift port must reproduce: the lab's key logic from
mixer/key_light.py (best_key, relation, wheel_cost, segments, and the mix-window lines of main()'s --ends mode) run on
chroma matrices. Needs numpy only (no librosa: the chroma is made up here, not computed from audio).

  python3 core/Tools/make_key_fixtures.py        # from anywhere

The lab's functions are copied below verbatim, because importing key_light.py needs soundfile and librosa. The
script checks the copies against mixer/key_light.py's source (by syntax tree) before it writes anything, so a change
in the lab stops it.

The chroma: 50 random matrices and a few made by hand. The random ones come from SplitMix64 (integer arithmetic,
then (z >> 11) * 2^-53) and only +, -, *, / and comparisons, so the Swift tests rebuild the same matrices bit for bit
from the seed: a random profile, key and noise level per matrix, and frame by frame a chance of a key change, of a
chord-like flicker to a related key, and of a silent frame, each frame divided by its largest value as librosa's chroma
is. The matrices are 12 rows of frames in column (Fortran) order, as librosa returns chroma, so numpy's means over
frames add frame after frame, as they do in the lab.

The engine's key vote (DeckieCore/Key/KeyVote.swift) is the lab's own decision and confidence rule, mixer/analyze.py's
B.9 block, with three votes over the one chroma in the lab's three slots: the edma profile in Essentia edma's, bgate in
Essentia bgate's, krumhansl in madmom's (core/Tools/key_vote_eval.py chose them). That block is not a function and
analyze.py cannot be imported without Essentia and madmom, so the script reads the block, and the camelot helpers it
calls, out of analyze.py's source and runs them as they are: nothing of the rule is copied.

Output: core/Tests/DeckieCoreTests/Fixtures/key.json
  relation, wheel_cost   every pair of the 24 Camelot codes
  random                 per seed: the whole-track key by every profile, the segments (lab defaults, and with other
                         settings), both mix windows judged against a song key, and the key vote (`vote`: the three
                         votes' keys, then the lab's B.9 key, confidence and rule)
  hand                   the same for the hand-made matrices, given as blocks of identical frames
  sheet                  the key vote on the lab's own run of the estimator over its 373 tracks (mixer/key_light_stft.tsv:
                         each profile's key and r on the real audio), with the lab's key and confidence per track
  vote_cases             the B.9 block on made-up votes that reach every branch
"""
import ast, csv, inspect, json, os, sys, textwrap
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "core", "Tests", "DeckieCoreTests", "Fixtures")
LAB = os.path.join(ROOT, "mixer", "key_light.py")
ANALYZE = os.path.join(ROOT, "mixer", "analyze.py")
SHEET = os.path.join(ROOT, "mixer", "key_light_stft.tsv")
VOTES = ("edma", "bgate", "krumhansl")  # the engine's votes, in B.9's slots: Essentia edma, Essentia bgate, madmom

# ---- copied verbatim from mixer/key_light.py (checked by check_copies) ---------------------------------------------
PC = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
CAM_MAJ = ["8B", "3B", "10B", "5B", "12B", "7B", "2B", "9B", "4B", "11B", "6B", "1B"]
CAM_MIN = ["5A", "12A", "7A", "2A", "9A", "4A", "11A", "6A", "1A", "8A", "3A", "10A"]
PROFILES = {
 "krumhansl": ([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88], [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]),
 "temperley": ([5.0, 2.0, 3.5, 2.0, 4.5, 4.0, 2.0, 4.5, 2.0, 3.5, 1.5, 4.0], [5.0, 2.0, 3.5, 4.5, 2.0, 4.0, 2.0, 4.5, 3.5, 2.0, 1.5, 4.0]),
 "shaath": ([6.6, 2.0, 3.5, 2.3, 4.6, 4.0, 2.5, 5.2, 2.4, 3.7, 2.3, 3.4], [6.5, 2.7, 3.5, 5.4, 2.6, 3.5, 2.5, 5.2, 4.0, 2.7, 4.3, 3.2]),
 "edma": ([1.00, 0.29, 0.50, 0.40, 0.60, 0.56, 0.32, 0.80, 0.31, 0.45, 0.42, 0.39], [1.00, 0.31, 0.44, 0.58, 0.33, 0.49, 0.29, 0.78, 0.43, 0.29, 0.53, 0.32]),
 "bgate": ([1.00, 0.00, 0.42, 0.00, 0.53, 0.37, 0.00, 0.77, 0.00, 0.38, 0.21, 0.30], [1.00, 0.00, 0.36, 0.39, 0.00, 0.38, 0.00, 0.74, 0.27, 0.00, 0.42, 0.23]),
 "braw": ([1.0000, 0.1573, 0.4200, 0.1570, 0.5296, 0.3669, 0.1632, 0.7711, 0.1676, 0.3827, 0.2113, 0.2965], [1.0000, 0.2330, 0.3615, 0.3905, 0.2925, 0.3777, 0.1961, 0.7425, 0.2701, 0.2161, 0.4228, 0.2272]),
}
SR = 22050; NFFT = 8192; HOP = 2048   # 0.37 s frames, 2.7 Hz bins: enough for pitch classes down to the bass

def best_key(c, prof):
    """c: 12 pitch-class energies (C first). Returns (pc, mode, r, margin) by Pearson correlation over 24 keys."""
    c = np.asarray(c, float); c = c - c.mean()
    if np.linalg.norm(c) == 0: return (0, "major", 0.0, 0.0)
    scores = []
    for mode, p in (("major", prof[0]), ("minor", prof[1])):
        p = np.asarray(p, float); p = p - p.mean()
        for s in range(12):
            q = np.roll(p, s); scores.append((float(np.dot(c, q) / (np.linalg.norm(c) * np.linalg.norm(q))), s, mode))
    scores.sort(reverse=True); (r1, s1, m1), (r2, _, _) = scores[0], scores[1]
    return (s1, m1, r1, r1 - r2)

def camelot(pc, mode): return (CAM_MAJ if mode == "major" else CAM_MIN)[pc]
def relation(a, b):
    if a == b: return "exact"
    na, la, nb, lb = int(a[:-1]), a[-1], int(b[:-1]), b[-1]
    if na == nb: return "relative"
    if la == lb and (na - nb) % 12 in (1, 11): return "neighbour"
    if la != lb and (na - nb) % 12 in (3, 9): return "parallel"   # same tonic, other mode (12A C# minor vs 3B C# major)
    return "other"

def wheel_cost(a, b):
    """How far apart two Camelot keys sit: steps around the wheel plus one for a letter change; 0 for the same
    tonal area (same key, relative, neighbour, parallel major/minor)."""
    rel = relation(a, b)
    if rel in ("exact", "relative", "neighbour", "parallel"): return 0
    na, la, nb, lb = int(a[:-1]), a[-1], int(b[:-1]), b[-1]
    d = min((na - nb) % 12, (nb - na) % 12)
    return d + (1 if la != lb else 0)

def segments(C, prof, win_s=20.0, hop_s=5.0, persist=2, min_margin=0.04):
    """Windowed keys with hysteresis. A new key opens a segment only when it is outside the running key's tonal
    area, wins consecutive windows with a correlation margin of at least min_margin, and persists: `persist`
    windows for a far move (wheel cost 3 or more), twice that for a near one (cost 1 or 2), where harmonic
    flicker lives. Returns [(start_s, camelot, mean_r)]."""
    fps = SR / HOP; w = int(win_s * fps); h = int(hop_s * fps); n = C.shape[1]
    keys = []
    for a in range(0, max(1, n - w + 1), h):
        pc, mode, r, m = best_key(C[:, a:a + w].mean(axis=1), prof); keys.append((a / fps, camelot(pc, mode), r, m))
    if not keys: return []
    segs = [[0.0, keys[0][1], [keys[0][2]]]]; run = []
    for t, k, r, m in keys[1:]:
        cur = segs[-1][1]; cost = wheel_cost(k, cur)
        if cost == 0 or m < min_margin:
            segs[-1][2].append(r); run = []; continue
        if run and run[-1][1] != k: run = []
        run.append((t, k, r))
        need = persist if cost >= 3 else 2 * persist
        if len(run) >= need:
            segs.append([run[0][0], k, [x[2] for x in run]]); run = []
    return [(round(s, 1), k, round(float(np.mean(rs)), 3)) for s, k, rs in segs]
# ---- end of the verbatim copy ---------------------------------------------------------------------------------------


def ends_window(C, name, w, ref, prof, gap=0.08):
    """One mix window of main()'s --ends mode. The lines between the markers are the lab's, unchanged except that
    `f.get(name)` is the argument `w` and `corr_for` is defined here (also verbatim); the result is returned instead of
    being stored in the row."""
    fps = SR / HOP
    def corr_for(cm, cam):
        """correlation of a given Camelot key's profile with a chroma mean"""
        pc = (CAM_MAJ + CAM_MIN).index(cam) % 12; mode = "major" if cam.endswith("B") else "minor"
        c = np.asarray(cm, float) - np.mean(cm); q = np.roll(np.asarray(prof[0] if mode == "major" else prof[1], float), pc); q = q - q.mean()
        return float(np.dot(c, q) / (np.linalg.norm(c) * np.linalg.norm(q) + 1e-12))
    # -- lab lines --
    w = w or {}; a, b = int(w.get("start_s", 0) * fps), int(w.get("end_s", 0) * fps)
    if b - a < int(8 * fps): a, b = (0, int(30 * fps)) if name == "mix_in" else (max(0, C.shape[1] - int(30 * fps)), C.shape[1])
    lo, hi, _ = slice(a, b).indices(C.shape[1])
    if hi <= lo:
        return {"empty": True}  # the lab would take the mean of nothing (NaN); the port returns no key
    cm = C[:, a:b].mean(axis=1); pc2, mode2, r2, m2 = best_key(cm, prof); k2 = camelot(pc2, mode2)
    r_whole_here = corr_for(cm, ref); far = wheel_cost(k2, ref) >= 2; flag = far and (r2 - r_whole_here) >= gap
    # -- end of lab lines --
    return {"empty": False, "frames": [lo, hi], "key": k2, "pc": pc2, "mode": mode2, "r": r2, "margin": m2,
            "r_song": r_whole_here, "gain": r2 - r_whole_here, "gain_2": round(r2 - r_whole_here, 2), "flag": flag}


def check_copies():
    """Stop if the copies above no longer match mixer/key_light.py (compared as syntax trees, so layout is free)."""
    lab = ast.parse(open(LAB).read())
    mine = ast.parse(inspect.getsource(sys.modules[__name__]))
    def defs(tree):
        out = {}
        for node in tree.body:
            if isinstance(node, ast.FunctionDef):
                out[node.name] = ast.dump(node)
            elif isinstance(node, ast.Assign):
                for t in node.targets:
                    if isinstance(t, ast.Name): out[t.id] = ast.dump(node.value)
                    elif isinstance(t, ast.Tuple): out[",".join(e.id for e in t.elts)] = ast.dump(node.value)
        return out
    a, b = defs(lab), defs(mine)
    names = ["PC", "CAM_MAJ", "CAM_MIN", "PROFILES", "best_key", "camelot", "relation", "wheel_cost", "segments"]
    for name in names:
        if name not in a or a.get(name) != b.get(name):
            sys.exit(f"{name} differs from mixer/key_light.py; copy it again")
    if "\nSR = 22050; NFFT = 8192; HOP = 2048" not in open(LAB).read():
        sys.exit("SR, NFFT or HOP differs from mixer/key_light.py")
    print("copies match mixer/key_light.py", file=sys.stderr)


def lab_key_decision():
    """mixer/analyze.py's key decision and confidence, taken from its source: the lines from the "key confidence (B.9)"
    comment to the `key = {...}` dict they feed, with the lab's PC, camelot, camelot_parse and camelot_neighbour, all
    run unchanged. Returns decide(k1, k2, mm_key) -> (camelot, confidence, rule), where k1, k2 and mm_key are the lab's
    (key name, scale, strength) for its three slots."""
    src = open(ANALYZE).read()
    env = {}
    for node in ast.parse(src).body:
        named = (isinstance(node, ast.FunctionDef) and node.name in ("camelot", "camelot_parse", "camelot_neighbour")) or (
            isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "PC" for t in node.targets))
        if named:
            exec(compile(ast.Module([node], []), ANALYZE, "exec"), env)
    assert {"PC", "camelot", "camelot_parse", "camelot_neighbour"} <= set(env), "analyze.py's camelot helpers moved"
    head = "    # ---------------------------------------------------------- key confidence (B.9)\n"
    start = src.index(head)
    end = src.index('    key = {"essentia_edma"', start)
    block = compile(textwrap.dedent(src[start:end]), ANALYZE + " (B.9)", "exec")

    def decide(k1, k2, mm_key):
        ns = dict(env, k1=k1, k2=k2, mm_key=mm_key)
        exec(block, ns)
        return ns["top"], ns["kc"], ns["rule"]
    return decide


def vote_of(whole, decide):
    """The key vote from a matrix's whole-track keys (best_key's (pc, mode, r, margin) per profile)."""
    k = [(PC[whole[p][0]], whole[p][1], whole[p][2]) for p in VOTES]
    top, kc, rule = decide(*k)
    return {"keys": [camelot(whole[p][0], whole[p][1]) for p in VOTES], "camelot": top, "confidence": kc, "rule": rule}


def sheet(decide):
    """The vote on the lab's own per-track estimates (mixer/key_light_stft.tsv: Camelot code and r per profile, the r
    as the TSV rounds it), with the lab's key and confidence from the same rows."""
    rows = []
    codes = CAM_MAJ + CAM_MIN
    for r in csv.DictReader(open(SHEET), delimiter="\t"):
        votes = []
        for p in VOTES:
            i = codes.index(r[p])
            votes.append((PC[i % 12], "major" if i < 12 else "minor", float(r[p + "_r"])))
        top, kc, rule = decide(*votes)
        rows.append({"id": r["id"], "votes": [[r[p], float(r[p + "_r"]), float(r[p + "_margin"])] for p in VOTES],
                     "lab": r["lab"], "lab_conf": float(r["lab_conf"]), "camelot": top, "confidence": kc, "rule": rule})
    return rows


def vote_cases(decide):
    """Made-up votes for every branch of the rule: (C major, A minor, G major, ... as key names) with strengths either
    side of 0.6; each case is [[key, scale, r] x 3]."""
    S, W, X = 0.8, 0.5, 0.6  # strong, weak, and exactly the lab's 0.6
    cases = [
        [["C", "major", S], ["C", "major", S], ["C", "major", S]],     # all three agree
        [["C", "major", W], ["C", "major", S], ["C", "major", S]],     # all agree, edma's strength under 0.6 -> 0.6
        [["C", "major", X], ["C", "major", W], ["C", "major", W]],     # exactly 0.6 counts as strong
        [["C", "major", S], ["C", "major", S], ["G", "major", S]],     # 2 of 3, the third a neighbour (9B)
        [["C", "major", S], ["C", "major", S], ["A", "minor", S]],     # 2 of 3, the third the relative (8A)
        [["C", "major", S], ["C", "major", S], ["F#", "major", S]],    # 2 of 3, the third incompatible
        [["C", "major", W], ["C", "major", S], ["G", "major", S]],     # 2 of 3, strength (edma's) under 0.6 -> 0.3
        [["G", "major", S], ["C", "major", W], ["C", "major", S]],     # bgate and krumhansl agree: bgate's strength
        [["G", "major", W], ["C", "major", S], ["C", "major", W]],     # ... strong bgate, weak edma: 0.65
        [["G", "major", S], ["D", "major", S], ["G", "major", W]],     # edma and krumhansl agree: edma's strength
        [["G", "major", W], ["D", "major", S], ["G", "major", S]],     # ... weak edma: 0.3
        [["C", "major", S], ["G", "major", S], ["F#", "major", S]],    # no two agree -> edma's key, 0.3
        [["E", "minor", W], ["Bb", "major", S], ["D", "minor", S]],    # no two agree, weak edma
        [["C", "major", S], ["A", "minor", S], ["A", "minor", S]],     # the relative pair outvotes edma
    ]
    out = []
    for c in cases:
        top, kc, rule = decide(*[tuple(v) for v in c])
        out.append({"votes": c, "camelot": top, "confidence": kc, "rule": rule})
    return out


# ---- the made-up chroma ---------------------------------------------------------------------------------------------
MASK = (1 << 64) - 1
GOLDEN, M1, M2 = 0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9, 0x94D049BB133111EB


class SplitMix64:
    def __init__(self, seed):
        self.x = seed & MASK

    def next(self):
        self.x = (self.x + GOLDEN) & MASK
        z = self.x
        z = ((z ^ (z >> 30)) * M1) & MASK
        z = ((z ^ (z >> 27)) * M2) & MASK
        return z ^ (z >> 31)

    def uniform(self):
        return (self.next() >> 11) * 2.0 ** -53

    def below(self, n):
        return int(self.uniform() * n)


def random_chroma(seed):
    """Frames x 12 from the seed; the draws come in this exact order (KeyTests.swift repeats it)."""
    g = SplitMix64(seed)
    n = 1 + g.below(2600)
    prof = list(PROFILES)[g.below(6)]
    noise = 0.2 + 0.8 * g.uniform()
    p_change = 0.004 * g.uniform()
    p_flicker = 0.3 * g.uniform()
    pc, major = g.below(12), g.uniform() < 0.5
    frames = []
    for t in range(n):
        if g.uniform() < p_change:
            pc, major = g.below(12), g.uniform() < 0.5
        if g.uniform() < 0.02:
            frames.append([0.0] * 12)
            continue
        fpc, fmaj = pc, major
        if g.uniform() < p_flicker:
            fpc, fmaj = (pc + [5, 7, 9, 2][g.below(4)]) % 12, g.uniform() < 0.5
        w = PROFILES[prof][0 if fmaj else 1]
        col = []
        for c in range(12):
            x = w[(c - fpc) % 12] + noise * (g.uniform() - 0.5)
            col.append(x if x > 0.0 else 0.0)
        mx = max(col)
        frames.append([v / mx for v in col] if mx > 0.0 else col)
    return frames, {"frames": n, "profile": prof, "noise": noise, "p_change": p_change, "p_flicker": p_flicker}


def profile_frame(prof, pc, major):
    w = PROFILES[prof][0 if major else 1]
    col = [w[(c - pc) % 12] for c in range(12)]
    return [v / max(col) for v in col]


def hand_made():
    """(name, blocks of [count, 12 values])"""
    triad = [1.0, 0, 0, 0, 1.0, 0, 0, 1.0, 0, 0, 0, 0]
    e = "edma"
    return [
        ("zeros", [[30, [0.0] * 12]]),
        ("ones", [[30, [1.0] * 12]]),
        ("tenths", [[30, [0.1] * 12]]),
        ("c_major_triad", [[30, triad]]),
        ("augmented", [[30, [1.0, 0, 0, 0, 1.0, 0, 0, 0, 1.0, 0, 0, 0]]]),
        ("diminished_seventh", [[30, [1.0, 0, 0, 1.0, 0, 0, 1.0, 0, 0, 1.0, 0, 0]]]),
        ("whole_tone", [[30, [1.0, 0, 1.0, 0, 1.0, 0, 1.0, 0, 1.0, 0, 1.0, 0]]]),
        ("single_a", [[30, [0, 0, 0, 0, 0, 0, 0, 0, 0, 1.0, 0, 0]]]),
        ("one_frame", [[1, triad]]),
        ("short_100", [[100, profile_frame(e, 7, True)]]),
        ("exactly_one_window", [[215, profile_frame(e, 2, False)]]),
        ("one_window_and_a_hop", [[268, profile_frame(e, 2, False)]]),
        ("far_move_c_to_f_sharp", [[300, profile_frame(e, 0, True)], [300, profile_frame(e, 6, True)]]),
        ("near_move_c_to_d", [[300, profile_frame(e, 0, True)], [300, profile_frame(e, 2, True)]]),
        ("relative_c_to_a_minor", [[300, profile_frame(e, 0, True)], [300, profile_frame(e, 9, False)]]),
        ("flicker_c_and_e", [[53, profile_frame(e, 0, True)], [53, profile_frame(e, 4, True)]] * 6),
        ("silence_then_g", [[200, [0.0] * 12], [400, profile_frame(e, 7, True)]]),
        ("krumhansl_shapes", [[150, profile_frame("krumhansl", 5, False)], [450, profile_frame("krumhansl", 10, True)]]),
    ]


def as_matrix(frames):
    return np.asfortranarray(np.array(frames, dtype=float).T.reshape(12, len(frames)))


def decide(C, g):
    """Everything the port must reproduce for one matrix; g picks the extra settings and windows."""
    n = C.shape[1]
    out = {"whole": {p: list(best_key(C.mean(axis=1), PROFILES[p])) for p in PROFILES}}
    out["segments"] = [list(s) for s in segments(C, PROFILES["edma"])]
    alt_prof = list(PROFILES)[g.below(6)]
    win, hop = [10.0, 20.0, 30.0][g.below(3)], [2.5, 5.0, 10.0][g.below(3)]
    persist, min_margin = 1 + g.below(3), [0.0, 0.02, 0.04, 0.1][g.below(4)]
    out["segments_alt"] = {"profile": alt_prof, "win_s": win, "hop_s": hop, "persist": persist, "min_margin": min_margin,
                           "result": [list(s) for s in segments(C, PROFILES[alt_prof], win, hop, persist, min_margin)]}
    secs = n / (SR / HOP)
    whole_key = camelot(*best_key(C.mean(axis=1), PROFILES["edma"])[:2])
    ref = whole_key if g.uniform() < 0.5 else (CAM_MAJ + CAM_MIN)[g.below(24)]
    ends = {"ref": ref}
    for name in ("mix_in", "mix_out"):
        kind = g.below(4)
        if kind == 0:
            w = None  # no window recorded: the lab's fallback
        elif kind == 1:  # a short window: also the fallback
            s0 = g.uniform() * secs
            w = {"start_s": s0, "end_s": s0 + 7.0 * g.uniform()}
        else:  # a real window, sometimes past the end
            s0 = g.uniform() * secs * (1.2 if kind == 3 else 0.8)
            w = {"start_s": s0, "end_s": s0 + 8.0 + 40.0 * g.uniform()}
        ends[name] = {"window": w, "result": ends_window(C, name, w, ref, PROFILES["edma"])}
    out["ends"] = ends
    return out


def main():
    check_copies()
    codes = CAM_MAJ + CAM_MIN
    doc = {"numpy": np.__version__,
           "relation": {f"{a}>{b}": relation(a, b) for a in codes for b in codes},
           "wheel_cost": {f"{a}>{b}": wheel_cost(a, b) for a in codes for b in codes},
           "random": [], "hand": []}
    b9 = lab_key_decision()
    for seed in range(1, 51):
        frames, meta = random_chroma(seed)
        C = as_matrix(frames)
        doc["random"].append({"seed": seed, **meta, **decide(C, SplitMix64(1000 + seed))})
    for i, (name, blocks) in enumerate(hand_made()):
        frames = [list(map(float, v)) for count, v in blocks for _ in range(count)]
        blocks = [[count, list(map(float, v))] for count, v in blocks]
        doc["hand"].append({"name": name, "blocks": blocks, **decide(as_matrix(frames), SplitMix64(5000 + i))})
    for case in doc["random"] + doc["hand"]:
        case["vote"] = vote_of(case["whole"], b9)
    doc["sheet"] = sheet(b9)
    doc["vote_cases"] = vote_cases(b9)
    path = os.path.join(OUT, "key.json")
    with open(path, "w") as f:
        json.dump(doc, f, separators=(",", ":"))
    multi = sum(1 for r in doc["random"] if len(r["segments"]) > 1)
    flags = sum(1 for r in doc["random"] + doc["hand"] for e in ("mix_in", "mix_out") if r["ends"][e]["result"].get("flag"))
    conf = [r for r in doc["sheet"] if r["lab_conf"] >= 0.65]
    exact = sum(1 for r in conf if r["camelot"] == r["lab"])
    split = sum(1 for r in doc["random"] + doc["hand"] if len(set(r["vote"]["keys"])) > 1)
    print(f"wrote {path} ({os.path.getsize(path) // 1024} KB): {len(doc['random'])} random matrices "
          f"({multi} with more than one segment), {len(doc['hand'])} made by hand, {flags} flagged windows; key vote "
          f"split on {split} matrices; on the sheet exact {exact} of {len(conf)} confident tracks; "
          f"{len(doc['vote_cases'])} made-up vote cases")


if __name__ == "__main__":
    main()
