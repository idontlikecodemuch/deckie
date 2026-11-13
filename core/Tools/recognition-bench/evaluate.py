#!/usr/bin/env python3
"""Turns the benchmark's results into tables (Markdown on standard output, numbers in WORK/summary.json).

  evaluate.py WORK [--results results.tsv] [--threshold T]

A query is "right" when the best song is the true one and its score reaches the threshold, "wrong" when another song
reaches it, "none" otherwise. The threshold is chosen on the dev half only: the lowest score that 99.9 % of the dev
queries with no right answer (songs left out of the index, noise alone) stay under. Everything in the tables is
the eval half, which played no part in any choice.
"""
import argparse, json, os, sys
from collections import defaultdict
import numpy as np

LENGTHS = [3, 5, 8, 12]


def load(work, results):
    truth = {}
    for line in open(os.path.join(work, "truth.jsonl")):
        t = json.loads(line); truth[t["qid"]] = t
    rows = []
    for line in open(results):
        f = line.rstrip("\n").split("\t")
        if len(f) < 16:
            continue
        qid, length = f[0].split("_")
        t = truth[qid]
        rows.append(dict(t=t, length=int(length), points=int(f[1]), ms_print=float(f[2]), ms_match=float(f[3]),
                         id=f[4], score=float(f[5]), matched=int(f[6]), offset=float(f[7]), tempo=float(f[8]), pitch=float(f[9]),
                         id2=f[10], score2=float(f[11])))
    return rows


def pct(a, b):
    return "-" if b == 0 else f"{100 * a / b:.0f}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("work"); ap.add_argument("--results"); ap.add_argument("--threshold", type=float)
    a = ap.parse_args()
    rows = load(a.work, a.results or os.path.join(a.work, "results.tsv"))

    def split(r):
        return r["t"].get("split", r["t"]["role"])
    neg_dev = sorted(r["score"] for r in rows if r["t"]["role"] == "absent" and split(r) == "dev")
    T = a.threshold if a.threshold is not None else (float(np.quantile(neg_dev, 0.999)) + 1e-6 if neg_dev else 0.0)
    out = {"threshold": T, "dev_negative_queries": len(neg_dev)}
    print(f"Threshold on the score: {T:.2f} (99.9th percentile of {len(neg_dev)} dev queries with no right answer; their highest {neg_dev[-1] if neg_dev else 0:.2f}).\n")

    def verdict(r):
        if r["score"] < T:
            return "none"
        if r["id"] == r["t"]["song"] and r["t"]["role"] != "absent":
            return "right"
        if r["id"] == r["t"].get("second"):
            return "second"
        return "wrong"
    for r in rows:
        r["v"] = verdict(r)
    ev = [r for r in rows if split(r) == "eval"]

    def cellrate(sel, what="right"):
        sel = list(sel)
        return sum(r["v"] == what for r in sel), len(sel)

    # 1. No right answer.
    print("### Queries with no right answer (eval half): how often a song is named anyway\n")
    print("| kind | " + " | ".join(f"{l} s" for l in LENGTHS) + " |\n|---|" + "---|" * len(LENGTHS))
    for name, f in [("song not in the index, clean", lambda r: r["t"]["bucket"] != "noise" and r["t"]["condition"] == "clean"),
                    ("song not in the index, room + crowd 0 dB", lambda r: r["t"]["bucket"] != "noise" and r["t"]["condition"] != "clean"),
                    ("noise alone (crowd, pink)", lambda r: r["t"]["bucket"] == "noise")]:
        cells = []
        for l in LENGTHS:
            sel = [r for r in ev if r["t"]["role"] == "absent" and r["length"] == l and f(r)]
            k = sum(r["v"] != "none" for r in sel)
            cells.append(f"{k} of {len(sel)}")
        print(f"| {name} | " + " | ".join(cells) + " |")
    k, n = sum(r["v"] != "none" for r in ev if r["t"]["role"] == "absent"), sum(1 for r in ev if r["t"]["role"] == "absent")
    out["eval_false_accepts"] = [k, n]

    # 2. The speed grid, clean.
    for mode, label in [("vinyl", "vinyl-style (time and pitch together)"), ("tempo", "tempo only, key held (Rubber Band)"), ("atempo", "tempo only, key held (ffmpeg atempo)")]:
        print(f"\n### Clean excerpts, {label}: right / wrong, percent of eval queries\n")
        print("| fader % | n | " + " | ".join(f"{l} s" for l in LENGTHS) + " |\n|---|---|" + "---|" * len(LENGTHS))
        speeds = sorted({r["t"]["percent"] for r in ev if r["t"]["cell"] == "grid" and r["t"]["mode"] == mode})
        tot = defaultdict(lambda: [0, 0, 0])
        for p in speeds:
            cells = []; n = 0
            for l in LENGTHS:
                sel = [r for r in ev if r["t"]["cell"] == "grid" and r["t"]["mode"] == mode and r["t"]["percent"] == p and r["length"] == l]
                n = len(sel)
                right = sum(r["v"] == "right" for r in sel); wrong = sum(r["v"] == "wrong" for r in sel)
                tot[l][0] += right; tot[l][1] += wrong; tot[l][2] += n
                cells.append(f"{pct(right, n)} / {pct(wrong, n)}")
            print(f"| {p:+d} | {n} | " + " | ".join(cells) + " |")
        print("| **all** | " + str(tot[LENGTHS[0]][2]) + " | " + " | ".join(f"**{100 * tot[l][0] / max(1, tot[l][2]):.1f}** / {100 * tot[l][1] / max(1, tot[l][2]):.1f}" for l in LENGTHS) + " |")
        out[f"grid_{mode}"] = {l: [tot[l][0], tot[l][1], tot[l][2]] for l in LENGTHS}

    # 3. By kind of music.
    print("\n### Clean excerpts by kind of music (all speeds, both modes): right, percent\n")
    print("| bucket | n | " + " | ".join(f"{l} s" for l in LENGTHS) + " |\n|---|---|" + "---|" * len(LENGTHS))
    for b in ("dance", "other", "gsplus"):
        cells = []; n = 0
        for l in LENGTHS:
            k, n = cellrate(r for r in ev if r["t"]["cell"] == "grid" and r["t"]["bucket"] == b and r["length"] == l)
            cells.append(pct(k, n))
        print(f"| {b} | {n} | " + " | ".join(cells) + " |")

    # 4. Booth conditions.
    print("\n### Booth conditions (five speeds pooled: 0, vinyl +12, vinyl -6, tempo +12, tempo -6): right / wrong, percent\n")
    print("| condition | n | " + " | ".join(f"{l} s" for l in LENGTHS) + " | named by 12 s |\n|---|---|" + "---|" * (len(LENGTHS) + 1))
    conditions = []
    for r in ev:
        if r["t"]["cell"] == "booth" and r["t"]["condition"] not in conditions:
            conditions.append(r["t"]["condition"])
    out["booth"] = {}
    for c in conditions:
        cells = []; n = 0
        for l in LENGTHS:
            sel = [r for r in ev if r["t"]["cell"] == "booth" and r["t"]["condition"] == c and r["length"] == l]
            n = len(sel)
            right = sum(r["v"] == "right" for r in sel); wrong = sum(r["v"] == "wrong" for r in sel)
            cells.append(f"{pct(right, n)} / {pct(wrong, n)}")
            out["booth"].setdefault(c, {})[l] = [right, wrong, n]
        named = defaultdict(bool)
        for r in ev:
            if r["t"]["cell"] == "booth" and r["t"]["condition"] == c and r["v"] == "right":
                named[r["t"]["qid"]] = True
        print(f"| {c} | {n} | " + " | ".join(cells) + f" | {pct(len(named), n)} |")

    print("\n### Booth conditions at 8 s, by speed: right, percent\n")
    speeds = [("vinyl", 0), ("vinyl", 12), ("vinyl", -6), ("tempo", 12), ("tempo", -6)]
    print("| condition | " + " | ".join(f"{m} {p:+d}" for m, p in speeds) + " |\n|---|" + "---|" * len(speeds))
    for c in conditions:
        cells = []
        for m, p in speeds:
            k, n = cellrate(r for r in ev if r["t"]["cell"] == "booth" and r["t"]["condition"] == c and r["length"] == 8 and r["t"]["mode"] == m and r["t"]["percent"] == p)
            cells.append(pct(k, n))
        print(f"| {c} | " + " | ".join(cells) + " |")

    # 5. Blends: which song is named.
    print("\n### Two songs at once: which is named (percent of eval queries; 'second' is the other song in the mix)\n")
    print("| condition | length | the song | second | another (wrong) | none | both in the top two |\n|---|---|---|---|---|---|---|")
    for c in [c for c in conditions if "blend" in c]:
        for l in LENGTHS:
            sel = [r for r in ev if r["t"]["cell"] == "booth" and r["t"]["condition"] == c and r["length"] == l]
            n = len(sel)
            both = sum(1 for r in sel if r["score2"] >= T and {r["id"], r["id2"]} == {r["t"]["song"], r["t"]["second"]})
            print(f"| {c} | {l} s | " + " | ".join(pct(sum(r["v"] == w for r in sel), n) for w in ("right", "second", "wrong", "none")) + f" | {pct(both, n)} |")

    # 6. The speed reading and the place.
    print("\n### The speed reading on right answers: error in fader points (read minus true), and the place in the song\n")
    print("| set | length | n | tempo reading: median / 90th / worst | pitch reading (vinyl only): median / 90th | vinyl or key-held told right | place within 0.5 s |\n|---|---|---|---|---|---|---|")
    out["speed"] = {}
    for name, f in [("clean, vinyl", lambda r: r["t"]["cell"] == "grid" and r["t"]["mode"] == "vinyl"),
                    ("clean, tempo only", lambda r: r["t"]["cell"] == "grid" and r["t"]["mode"] == "tempo"),
                    ("room", lambda r: r["t"]["condition"] == "room"),
                    ("room + crowd 0 dB", lambda r: r["t"]["condition"] == "room+crowd0"),
                    ("room + pink -5 dB", lambda r: r["t"]["condition"] == "room+pink-5"),
                    ("blend 0 dB", lambda r: r["t"]["condition"] == "blend0")]:
        for l in LENGTHS:
            sel = [r for r in ev if r["v"] == "right" and r["length"] == l and r["t"]["role"] != "absent" and f(r)]
            if not sel:
                continue
            e = np.array([abs((r["tempo"] - 1) * 100 - r["t"]["percent"]) for r in sel])
            vin = [r for r in sel if r["t"]["mode"] == "vinyl"]
            pe = np.array([abs((r["pitch"] - 1) * 100 - r["t"]["percent"]) for r in vin]) if vin else np.array([0.0])
            kind = [r for r in sel if abs(r["t"]["percent"]) >= 2]
            ok = sum(1 for r in kind if (abs(np.log(r["pitch"]) - np.log(r["tempo"])) < abs(np.log(r["pitch"]))) == (r["t"]["mode"] == "vinyl"))
            place = sum(1 for r in sel if abs(r["offset"] - r["t"]["s0"]) <= 0.5)
            print(f"| {name} | {l} s | {len(sel)} | {np.median(e):.2f} / {np.quantile(e, 0.9):.2f} / {e.max():.2f} | {np.median(pe):.2f} / {np.quantile(pe, 0.9):.2f} | {pct(ok, len(kind))} | {pct(place, len(sel))} |")
            out["speed"][f"{name}/{l}"] = [float(np.median(e)), float(np.quantile(e, 0.9)), float(e.max())]

    # 7. Cost.
    print("\n### Cost of a query on one core, milliseconds (all queries)\n")
    print("| length | points in the query (median) | fingerprint the query: median / 95th | match: median / 95th |\n|---|---|---|---|")
    for l in LENGTHS:
        sel = [r for r in rows if r["length"] == l]
        fp = np.array([r["ms_print"] for r in sel]); m = np.array([r["ms_match"] for r in sel])
        print(f"| {l} s | {int(np.median([r['points'] for r in sel]))} | {np.median(fp):.1f} / {np.quantile(fp, 0.95):.1f} | {np.median(m):.1f} / {np.quantile(m, 0.95):.1f} |")
    json.dump(out, open(os.path.join(a.work, "summary.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
