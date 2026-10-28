#!/usr/bin/env python3
"""Write the reference numbers the DeckieCore tests compare against, using the lab's own Python
(mixer/analyze.py and mixer/score.py, imported unchanged; nothing in mixer/ is written).

  python3 core/Tools/make_fixtures.py            # from the repository root; needs numpy

Outputs, in core/Tests/DeckieCoreTests/Fixtures/:
  camelot.json        every key name and scale -> Camelot code; the key-compatibility table; pitch shifts
  gridfit.json        per track: the grid fit of the committed detected beats, by the current fit_grid
                      (both estimators) and by the IRLS path alone (what produced the committed numbers)
  pairs_summary.json  totals over every directed pair score.py produces
  pairs_sample.json   every SAMPLE_STEP-th pair in (a, b) order plus the TOP_N strongest, full records
"""
import json, os, sys, collections
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MIXER = os.path.join(ROOT, "mixer")
OUT = os.path.join(ROOT, "core", "Tests", "DeckieCoreTests", "Fixtures")
sys.path.insert(0, MIXER)
import analyze  # noqa: E402  (module-level code only sets paths and warnings)
import score    # noqa: E402

SAMPLE_STEP = 59
TOP_N = 100


def dump(name, obj):
    with open(os.path.join(OUT, name), "w") as f:
        json.dump(obj, f, separators=(",", ":"), sort_keys=True)
    print(f"wrote {name} ({os.path.getsize(os.path.join(OUT, name)) // 1024} KB)")


def camelot_fixture():
    names = sorted(analyze.PC)
    codes = {f"{k} {s}": analyze.camelot(k, s) for k in names for s in ("major", "minor")}
    all_codes = sorted({*codes.values()}, key=lambda c: (c[-1], int(c[:-1])))
    raw = {f"{a}>{b}": list(score.key_raw(a, b)) for a in all_codes for b in all_codes}
    shifts = {f"{c}{s:+d}": score.cshift(c, s) for c in all_codes for s in (-2, -1, 1, 2)}
    neighbour = {f"{a}>{b}": analyze.camelot_neighbour(a, b) for a in all_codes for b in all_codes}
    dump("camelot.json", {"codes": codes, "key_raw": raw, "shift": shifts, "neighbour": neighbour})


def gridfit_fixture():
    rows = {}
    for f in sorted(os.listdir(os.path.join(MIXER, "features"))):
        d = json.load(open(os.path.join(MIXER, "features", f)))
        b = np.sort(np.asarray(d["detected_beats_s"], float))
        downs = d["detected_downbeats_s"]
        full = analyze.fit_grid(b, downs, d["duration_s"])
        P, t0, _ = analyze._period_phase_irls(b)
        irls = analyze._grid_eval(b, downs, P, t0)
        w = analyze._period_phase_windows(b)
        win = None
        if w:
            win = analyze._grid_eval(b, downs, w[0], w[1])
            win.update({"trusted_windows": w[2]["trusted_windows"], "period_spread_pct": w[2]["period_spread_pct"]})
        keep = ("bpm", "period", "t0", "first_downbeat", "fit_mad_ms", "inlier_frac", "downbeat_agree", "confidence")
        rows[d["id"]] = {
            "n_beats": int(len(b)), "n_downbeats": int(len(downs)),
            "full": {**{k: full[k] for k in keep}, "method": full["method"]},
            "irls": {k: irls[k] for k in keep},
            "windows": None if win is None else {**{k: win[k] for k in keep},
                                                 "trusted_windows": win["trusted_windows"],
                                                 "period_spread_pct": win["period_spread_pct"]},
        }
    dump("gridfit.json", rows)
    return rows


def pairs_fixtures():
    T = score.load()
    n = len(T)
    E = np.stack([t["emb"] for t in T])
    C = E @ E.T
    iu = np.triu_indices(n, 1)
    vals = np.sort(C[iu])
    pct = np.searchsorted(vals, C, side="right") / max(1, len(vals))
    P = {}
    skipped_cut = rejected = 0
    for i, A in enumerate(T):
        for j, B in enumerate(T):
            if i == j:
                continue
            if A["cut_key"] == B["cut_key"]:
                skipped_cut += 1
                continue
            r = score.score_pair(A, B, float(pct[i, j]))
            if r is None:
                rejected += 1
            else:
                P[(A["id"], B["id"])] = r
    ordered = [P[k] for k in sorted(P)]
    by_tr = collections.Counter(p["suggested_transition"] for p in ordered)
    by_mult = collections.Counter(p["multiplier"] for p in ordered)
    term_sums = {t: round(float(sum(p["terms"][t] for p in ordered)), 3) for t in score.W}
    summary = {
        "n_tracks": n, "n_directed": n * (n - 1), "skipped_same_cut": skipped_cut, "rejected_tempo": rejected,
        "n_scored": len(ordered), "n_at_least_threshold": sum(1 for p in ordered if p["score_base"] + score.bonus(
            next(t for t in T if t["id"] == p["b"])) >= score.PAIR_MIN),
        "sum_score_base": round(float(sum(p["score_base"] for p in ordered)), 4),
        "term_sums": term_sums, "by_transition": dict(by_tr), "by_multiplier": dict(by_mult),
        "weights": score.W, "threshold": score.PAIR_MIN, "long_secs": score.LONG_SECS, "long_bonus": score.LONG_BONUS,
        "sample_step": SAMPLE_STEP, "top_n": TOP_N,
    }
    dump("pairs_summary.json", summary)
    sample = ordered[::SAMPLE_STEP]
    top = sorted(ordered, key=lambda p: (-p["score_base"], p["a"], p["b"]))[:TOP_N]
    seen = {(p["a"], p["b"]) for p in sample}
    sample += [p for p in top if (p["a"], p["b"]) not in seen]
    dump("pairs_sample.json", sample)
    print(f"{n} tracks, {len(ordered)} scored pairs, {len(sample)} in the sample")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    camelot_fixture()
    gridfit_fixture()
    pairs_fixtures()
