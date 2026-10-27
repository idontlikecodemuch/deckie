#!/usr/bin/env python3
"""Directed pairwise "A mixes into B" scoring (research.md B.9/B.10/E.3/E.4).

Reads features/*.json (+ candidates.json for cut/disc metadata) and writes
pairs.json, recs.json and recs.md next to this script. Works on a partial feature set.

  .venv/bin/python score.py
"""
import glob
import json
import math
import os
import sys
from collections import defaultdict

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
FEAT_DIR = os.path.join(HERE, "features")
W = {"tempo": 0.26, "key": 0.14, "energy": 0.11, "vocal": 0.11, "phrase": 0.08, "timbre": 0.12, "rhythm": 0.05, "style": 0.13}
MULTS = [(0.5, "1/2"), (2 / 3, "2/3"), (0.75, "3/4"), (1.0, "1"), (4 / 3, "4/3"), (1.5, "3/2"), (2.0, "2")]
PAIR_MIN = 0.45
LINE_MIN = 0.6
LONG_SECS = 270
LONG_BONUS = 0.03
TOPN = 8
VOC = 0.5


# ----------------------------------------------------------------------------- loading
def load():
    cands = {c["id"]: c for c in json.load(open(os.path.join(HERE, "candidates.json")))}
    T = []
    for f in sorted(glob.glob(os.path.join(FEAT_DIR, "*.json"))):
        try:
            d = json.load(open(f))
        except Exception as e:
            print(f"skip unreadable {f}: {e}", file=sys.stderr)
            continue
        c = cands.get(d["id"], {})
        pb = d["per_bar"]
        lufs = np.array(pb["lufs_st"], float)
        voc = np.array(pb["vocal_prob"], float)
        mi, mo = d["mix_in"], d["mix_out"]
        i0, i1 = mi["start_bar"] - 1, mi["end_bar"] - 1
        o0, o1 = mo["start_bar"] - 1, mo["end_bar"] - 1

        def pmean(a):
            a = a[np.isfinite(a)]
            return 10 * math.log10(np.mean(10 ** (a / 10))) if len(a) else -70.0

        integ = d["loudness"]["integrated_lufs"]
        emb = np.array(d["embedding_effnet"], float)
        T.append({
            "id": d["id"], "title": c.get("title", d.get("title")), "ver": c.get("ver", d.get("ver")) or "",
            "secs": c.get("secs") or d["duration_s"], "cut_key": c.get("cut_key") or d["id"],
            "is_longest": bool(c.get("is_longest", True)), "on_disc": bool(c.get("on_disc")),
            "disc": c.get("disc"), "folder": c.get("folder") or "", "hal": bool(c.get("hal")),
            "bpm": d["bpm"], "bpm_tag": d.get("bpm_tag"), "grid_conf": d["grid"]["confidence"],
            "bpm_in": (d.get("local_tempo") or {}).get("bpm_in") or d["bpm"],
            "bpm_out": (d.get("local_tempo") or {}).get("bpm_out") or d["bpm"],
            "tempo_change": bool((d.get("local_tempo") or {}).get("tempo_change")),
            "drift_pct": (d.get("local_tempo") or {}).get("drift_pct", 0.0),
            "in_trusted": bool((d.get("local_tempo") or {}).get("in_trusted", True)),
            "out_trusted": bool((d.get("local_tempo") or {}).get("out_trusted", True)),
            "steady_in_bar": (d.get("local_tempo") or {}).get("steady_in_bar"),
            "steady_out_bar": (d.get("local_tempo") or {}).get("steady_out_bar"),
            "n_bars": d["grid"]["n_bars"],
            "camelot": d["key"]["camelot"], "key_conf": d["key"]["confidence"],
            "in_bars": mi["bars"], "out_bars": mo["bars"],
            "in_rel": pmean(lufs[i0:i1]) - integ, "out_rel": pmean(lufs[o0:o1]) - integ,
            "voc_in": voc[i0:i1], "voc_out": voc[o0:o1], "voc_first16": voc[i0:i0 + 16],
            "pattern": np.array(d["onset_pattern_16"], float),
            "emb": emb / (np.linalg.norm(emb) + 1e-9),
            "fade_out": d.get("fade_out", False), "flags": d.get("flags", []),
            "kind": c.get("kind") or d.get("meta", {}).get("kind") or "", "era": c.get("era") or d.get("meta", {}).get("era") or "",
        })
    return T


DANCE_KINDS = ("pool edit", "official remix", "dance original")
def style_term(A, B):
    """How alike the two records are as DJ material: remix/house/dance vs pop original vs library, era, Halloween."""
    fa = "dance" if A["kind"] in DANCE_KINDS else "pop"
    fb = "dance" if B["kind"] in DANCE_KINDS else "pop"
    st = 1.0 if fa == fb else 0.45
    if A["era"] and B["era"]:
        st -= 0.0 if A["era"] == B["era"] else 0.15
    if A["hal"] and B["hal"]:
        st = min(1.0, st + 0.1)
    return max(0.0, st)


# ----------------------------------------------------------------------------- terms
def cparse(c):
    return int(c[:-1]), c[-1]


def cshift(c, semis):
    n, l = cparse(c)
    m = (n - 1 + 7 * semis) % 12 + 1
    return f"{m}{l}"


def key_raw(a, b):
    na, la = cparse(a)
    nb, lb = cparse(b)
    if a == b:
        return 1.0, "same key"
    if la == lb:
        d = (nb - na) % 12
        return {1: (0.90, "+1 (fifth)"), 11: (0.90, "-1 (fifth)"), 2: (0.65, "+2 energy boost"),
                7: (0.50, "+1 semitone"), 5: (0.50, "-1 semitone"), 10: (0.45, "-2")}.get(d, (0.15, "clash"))
    if na == nb:
        return 0.85, "relative major/minor"
    return 0.15, "clash"


def key_term(A, B):
    raw, why = key_raw(A["camelot"], B["camelot"])
    best, shift = raw, 0
    for s in (1, -1, 2, -2):
        r2, _ = key_raw(A["camelot"], cshift(B["camelot"], s))
        if r2 >= 0.85:
            v = 0.85 - 0.12 * abs(s)
            if v > best:
                best, shift = v, s
    c = min(A["key_conf"], B["key_conf"])
    return best * (0.5 + 0.5 * c), raw, shift, why, c


def tempo_term(A, B):
    best = None
    for k, lab in MULTS:
        r = B["bpm_in"] * k / A["bpm_out"]
        d = abs(math.log(r))
        if best is None or d < best[0] - 1e-12:
            best = (d, k, lab, r)
    _, k, lab, r = best
    s = abs(r - 1) * 100
    if s > 18:
        return 0.0, k, lab, s, True
    # Mike's CDJ-1000MK3 pitch range goes to +/-16 percent: free to 3, gentle to 10, usable to 16
    t = 1.0 if s <= 3 else (1 - (s - 3) / 7 * 0.6 if s <= 10 else 0.4 - (s - 10) / 6 * 0.3)
    t = max(t, 0.05)
    if k in (0.5, 2.0):
        t = max(0.01, t - 0.10)
    elif k != 1.0:  # 2/3, 3/4, 4/3, 3/2: needs a tempo-change transition track or a brake, never a blend
        t = min(t, 0.35)
    return t, k, lab, s, False


def fold8(p):
    return (p[:8] + p[8:]) / 2


def up16(p8):
    return np.interp(np.arange(16) / 2.0, np.arange(8), p8)


def corr(x, y):
    x = x - x.mean()
    y = y - y.mean()
    den = np.linalg.norm(x) * np.linalg.norm(y)
    return float(x @ y / den) if den > 0 else 0.0


def rhythm_term(A, B, k):
    if k == 1.0:
        return max(0.0, corr(A["pattern"], B["pattern"]))
    if k == 2.0:  # B is half A's tempo: one B bar spans two A bars
        return max(0.0, corr(A["pattern"], up16(fold8(B["pattern"]))))
    if k == 0.5:
        return max(0.0, corr(up16(fold8(A["pattern"])), B["pattern"]))
    return 0.25  # 2/3, 3/4, ... : not comparable cell-by-cell


def transition(A, B, s, k, v, rhythm, L, steady=True):
    if not steady:  # no steady beat at A's end or B's start: echo A out and cut B in on its downbeat
        return "quick_blend_echo" if s <= 8 else "brake_cut"
    if s > 16 or (k not in (1.0, 0.5, 2.0) and rhythm < 0.5):
        return "brake_cut"
    # Mike mixes progressively: a blend is the default answer whenever the beats can be matched.
    # The vocal detector over-reports singing, so only heavy overlap pushes a pair to an effect exit.
    if v >= 0.6:
        return "quick_blend_echo" if s <= 16 else "brake_cut"
    if s > 6:
        return "ramped_blend"
    if v < 0.35 and A["out_bars"] >= 16 and B["in_bars"] >= 16:
        return "bass_swap_32" if (A["out_bars"] >= 32 and B["in_bars"] >= 32 and v < 0.2) else "bass_swap_16"
    if A["out_bars"] >= 8 and B["in_bars"] >= 8:
        return "bass_swap_8"
    return "quick_blend_echo" if A["voc_out"][-L:].mean() >= B["voc_in"][:L].mean() else "filter_sweep"


def move_options(A, B, s, k, v, tr):
    """Ordered menu of plausible moves for the pair, primary first; Mike picks, the app only suggests."""
    opts = [tr]
    matchable = s <= 16 and k in (1.0, 0.5, 2.0)
    def add(x):
        if x not in opts: opts.append(x)
    if matchable:
        if A["out_bars"] >= 16 and B["in_bars"] >= 16: add("bass_swap_16")
        elif A["out_bars"] >= 8 and B["in_bars"] >= 8: add("bass_swap_8")
        add("quick_blend_echo")
        if A["out_trusted"] and v < 0.6: add("filter_sweep")
    else:
        add("quick_blend_echo")
    add("brake_cut")
    return opts[:3]


def score_pair(A, B, timbre_pct):
    tempo, k, klab, s, reject = tempo_term(A, B)
    if reject:
        return None
    key, kraw, shift, kwhy, kc = key_term(A, B)
    dE = B["in_rel"] - A["out_rel"]
    energy = 1 - min(max(abs(dE) - 2, 0), 8) / 8
    L = int(min(A["out_bars"], B["in_bars"]))
    pa = A["voc_out"][-L:]
    pb = B["voc_in"][:L]
    L = min(len(pa), len(pb))
    pa, pb = pa[len(pa) - L:], pb[:L]
    v = float(np.mean(pa * pb)) if L else 0.0
    clash = int(np.sum((pa >= VOC) & (pb >= VOC)))
    clean16 = len(B["voc_first16"]) >= 16 and bool(np.all(B["voc_first16"] < VOC))
    vocal = min(1.0, 1 - v + (0.1 if clean16 else 0.0))
    long_ok = A["out_bars"] >= 16 and B["in_bars"] >= 16
    steady = bool(A["out_trusted"] and B["in_trusted"])
    gconf = (0.7 + 0.3 * A["grid_conf"]) * (0.7 + 0.3 * B["grid_conf"])
    win = min(A["out_bars"], B["in_bars"])
    phrase = gconf * min(1.0, max(0.0, (win - 8) / 8.0))   # graded: 0 at 8 bars, full at 16
    drop_in = (not B["in_trusted"]) and B["steady_in_bar"] and B["steady_in_bar"] <= max(9, 0.3 * B["n_bars"])
    if not steady:
        phrase *= 0.6 if drop_in else 0.4
    timbre = timbre_pct
    rhythm = rhythm_term(A, B, k)
    style = style_term(A, B)
    terms = {"tempo": tempo, "key": key, "energy": energy, "vocal": vocal, "phrase": phrase,
             "timbre": timbre, "rhythm": rhythm, "style": style}
    base = sum(W[t] * terms[t] for t in W)
    tr = transition(A, B, s, k, v, rhythm, max(L, 1), steady)
    # hard gate: heavy vocal overlap only with a cut-style transition (always true by construction)
    if v >= 0.6 and tr not in ("quick_blend_echo", "brake_cut"):
        return None

    txt = {}
    if k in (0.5, 2.0):
        txt["tempo"] = f"half-time/double-time blend (x{klab}), {s:.1f}% stretch"
    elif k != 1.0:
        txt["tempo"] = f"tempo change x{klab} ({A['bpm_out']:.0f} -> {B['bpm_in']:.0f}): transition track or brake, no blend"
    elif s <= 0.5:
        txt["tempo"] = f"same tempo ({A['bpm_out']:.1f} BPM at A's end)"
    else:
        txt["tempo"] = (f"{'+' if B['bpm_in'] * k < A['bpm_out'] else '-'}{s:.1f}% stretch on B "
                        f"({A['bpm_out']:.1f} end -> {B['bpm_in']:.1f} start)")
    ktxt = f"{A['camelot']} -> {B['camelot']}"
    if shift:
        ktxt += f" (pitch-shift B by {shift:+d} st)"
    elif kwhy not in ("same key",):
        ktxt += f" ({kwhy})"
    if kc < 0.5:
        ktxt += ", key unsure"
    txt["key"] = ktxt
    txt["energy"] = (f"energy steady ({dE:+.1f} LU)" if abs(dE) <= 2 else
                     f"B enters {dE:+.1f} LU {'louder' if dE > 0 else 'quieter'}")
    if clean16:
        txt["vocal"] = "B has a clean 16-bar intro"
    elif clash:
        txt["vocal"] = f"vocals overlap {clash} of {L} bars"
    else:
        txt["vocal"] = "no vocal clash"
    if not steady:
        if not A["out_trusted"]:
            txt["phrase"] = "no steady beat at A's end (echo out, cut B in on its downbeat)"
        elif drop_in:
            txt["phrase"] = f"B's beat starts at bar {B['steady_in_bar']} (cut in there, skip the intro)"
        else:
            txt["phrase"] = "no steady beat at B's start (cut in on the downbeat)"
    elif not long_ok:
        txt["phrase"] = f"{win}-bar window (short of a 16-bar phrase)"
    elif phrase < 0.4:
        txt["phrase"] = "shaky beat grid"
    else:
        txt["phrase"] = f"{L}-bar phrases both sides"
    txt["style"] = ("same style" if style >= 0.9 else ("related style" if style >= 0.6 else "different style"))
    txt["timbre"] = (f"similar sound (closer than {timbre * 100:.0f}% of pairs)" if timbre >= 0.5
                     else f"different sound (closer than only {timbre * 100:.0f}% of pairs)")
    if k in (1.0, 2.0, 0.5):
        txt["rhythm"] = f"{'matching' if rhythm >= 0.6 else 'different'} groove (r={rhythm:.2f})"
    else:
        txt["rhythm"] = f"groove not comparable at x{klab}"
    order = sorted([t for t in terms if terms[t] > 0], key=lambda t: -terms[t])[:3]
    reasons = [txt[t] for t in order] + [txt[t] for t in terms if terms[t] < 0.4 and t not in order]
    return {"a": A["id"], "b": B["id"], "score_base": round(base, 4),
            "terms": {t: round(v_, 3) for t, v_ in terms.items()},
            "stretch_pct": round(s, 2), "multiplier": klab, "suggested_transition": tr,
            "moves": move_options(A, B, s, k, v, tr),
            "vocal_overlap": round(v, 3), "overlap_bars": L, "key_shift_st": shift,
            "energy_delta_lu": round(dE, 2), "reasons": reasons}


# ----------------------------------------------------------------------------- views
def bonus(t):
    return LONG_BONUS if (t["secs"] or 0) >= LONG_SECS else 0.0


def dedupe(ids, T_by):
    """Keep one track per cut_key: the is_longest one, else the longest analysed."""
    best = {}
    for i in ids:
        t = T_by[i]
        k = t["cut_key"]
        cur = best.get(k)
        if cur is None or (t["is_longest"], t["secs"]) > (T_by[cur]["is_longest"], T_by[cur]["secs"]):
            best[k] = i
    return set(best.values())


def entry(p, other, T_by, bon):
    o = T_by[other]
    reasons = list(p["reasons"]) + (["longer cut"] if bon else [])
    return {"id": other, "title": f"{o['title']} {o['ver']}".strip(), "score": round(p["score_base"] + bon, 4),
            "reasons": reasons, "suggested_transition": p["suggested_transition"],
            "stretch_pct": p["stretch_pct"], "multiplier": p["multiplier"],
            "camelot_a": T_by[p["a"]]["camelot"], "camelot_b": T_by[p["b"]]["camelot"]}


def main():
    T = load()
    n = len(T)
    print(f"scoring {n} analysed tracks ({n * (n - 1)} directed pairs before gates)")
    if n < 2:
        print("need at least 2 analysed tracks")
        return
    T_by = {t["id"]: t for t in T}
    E = np.stack([t["emb"] for t in T])
    C = E @ E.T
    iu = np.triu_indices(n, 1)
    vals = np.sort(C[iu])
    pct = np.searchsorted(vals, C, side="right") / max(1, len(vals))

    P = {}
    for i, A in enumerate(T):
        for j, B in enumerate(T):
            if i == j or A["cut_key"] == B["cut_key"]:
                continue
            r = score_pair(A, B, float(pct[i, j]))
            if r is not None:
                P[(A["id"], B["id"])] = r

    pairs = []
    for (a, b), p in P.items():
        bon = bonus(T_by[b])
        sc = p["score_base"] + bon
        if sc >= PAIR_MIN:
            q = dict(p)
            q["score"] = round(sc, 4)
            if bon:
                q["reasons"] = q["reasons"] + ["longer cut"]
            pairs.append(q)
    pairs.sort(key=lambda p: -p["score"])
    keys = ["a", "b", "score", "score_base", "terms", "stretch_pct", "multiplier", "suggested_transition", "moves",
            "reasons", "vocal_overlap", "overlap_bars", "key_shift_st", "energy_delta_lu"]
    pairs = [{k: p[k] for k in keys} for p in pairs]
    json.dump({"n_tracks": n, "threshold": PAIR_MIN, "weights": W, "pairs": pairs},
              open(os.path.join(HERE, "pairs.json"), "w"), separators=(",", ":"))

    ids = [t["id"] for t in T]
    views = {"disc": dedupe([i for i in ids if T_by[i]["on_disc"]], T_by), "pool": dedupe(ids, T_by)}
    recs = {}
    for t in T:
        r = {"title": f"{t['title']} {t['ver']}".strip(), "on_disc": t["on_disc"], "disc": t["disc"],
             "folder": t["folder"], "bpm": t["bpm"], "camelot": t["camelot"]}
        for vname, cand in views.items():
            outs, ins = [], []
            for o in cand:
                if o == t["id"] or T_by[o]["cut_key"] == t["cut_key"]:
                    continue
                p = P.get((t["id"], o))
                if p:
                    outs.append(entry(p, o, T_by, bonus(T_by[o])))
                q = P.get((o, t["id"]))
                if q:
                    ins.append(entry(q, o, T_by, bonus(T_by[o])))
            outs.sort(key=lambda e: -e["score"])
            ins.sort(key=lambda e: -e["score"])
            r[vname] = {"out": outs[:TOPN], "in": ins[:TOPN]}
        recs[t["id"]] = r
    json.dump(recs, open(os.path.join(HERE, "recs.json"), "w"), indent=1)

    # ------------------------------------------------------------------ recs.md
    L = [f"# Mix recommendations", "",
         f"{n} analysed tracks scored; {len(P)} directed pairs passed the gates; "
         f"{len(pairs)} pairs with score >= {PAIR_MIN}. Score = 0.30 tempo + 0.20 key + 0.15 energy + "
         f"0.15 vocal + 0.10 phrase + 0.05 timbre + 0.05 rhythm (+{LONG_BONUS} for a candidate >= {LONG_SECS} s).", ""]
    disc_tracks = [t for t in T if t["on_disc"]]
    L.append(f"## On-disc tracks ({len(disc_tracks)} analysed): top 3 disc-view matches (A -> B)")
    for disc in ("S", "M", None):
        grp = [t for t in disc_tracks if t["disc"] == disc]
        if not grp:
            continue
        L += ["", f"### Disc {disc or '?'} ({'singalongs' if disc == 'S' else 'mix-ins' if disc == 'M' else ''})"]
        for folder in sorted({t["folder"] for t in grp}):
            L += ["", f"#### {folder}"]
            for t in sorted([x for x in grp if x["folder"] == folder], key=lambda x: x["bpm"]):
                tc = f", tempo change {t['bpm_in']:.0f}->{t['bpm_out']:.0f}" if t.get("tempo_change") else ""
                L.append(f"- **{t['title']} {t['ver']}".rstrip() + f"** ({t['bpm']:.1f} BPM, {t['camelot']}{tc})")
                outs = recs[t["id"]]["disc"]["out"][:3]
                if not outs:
                    L.append("  - (no disc match passed the gates)")
                for e in outs:
                    L.append(f"  - {e['score']:.2f} -> {e['title']} | {e['stretch_pct']:.1f}% "
                             f"(x{e['multiplier']}) | {e['camelot_a']}->{e['camelot_b']} | "
                             f"{e['suggested_transition']} | " + "; ".join(e["reasons"]))
    L += ["", "## 20 strongest pairs overall", ""]
    for p in pairs[:20]:
        A, B = T_by[p["a"]], T_by[p["b"]]
        L.append(f"- {p['score']:.2f} {A['title']} {A['ver']}".rstrip() + f" -> {B['title']} {B['ver']}".rstrip()
                 + f" | {p['stretch_pct']:.1f}% | {A['camelot']}->{B['camelot']} | {p['suggested_transition']} | "
                 + "; ".join(p["reasons"]))
    L += ["", f"## Tracks with no match >= {LINE_MIN} (pool view, either direction)", ""]
    lonely = []
    for t in T:
        r = recs[t["id"]]["pool"]
        best = max([e["score"] for e in r["out"] + r["in"]] or [0])
        if best < LINE_MIN:
            lonely.append((best, t))
    for best, t in sorted(lonely, key=lambda x: x[0]):
        L.append(f"- {t['title']} {t['ver']}".rstrip() + f" (best {best:.2f}; {t['bpm']:.1f} BPM, {t['camelot']}; "
                 f"flags: {', '.join(t['flags']) or '-'})")
    if not lonely:
        L.append("- none")
    open(os.path.join(HERE, "recs.md"), "w").write("\n".join(L) + "\n")
    print(f"wrote pairs.json ({len(pairs)} pairs >= {PAIR_MIN}), recs.json ({len(recs)} tracks), recs.md; "
          f"{len(lonely)} tracks without a match >= {LINE_MIN}")


if __name__ == "__main__":
    main()
