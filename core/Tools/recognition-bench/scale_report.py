#!/usr/bin/env python3
"""Time to answer and false matches against catalogue size.

  scale_report.py sample WORK                 pick the queries (eval half): every clean clip of a song that is not in
                                              the index, and 500 clips of songs that are (clean, room, room + crowd)
  scale_report.py report WORK [--threshold T] the table, from WORK/scale_<size>.tsv
"""
import glob, json, os, random, sys
import numpy as np


def sample(work):
    random.seed(11)
    truth = [json.loads(l) for l in open(os.path.join(work, "truth.jsonl"))]
    ev = [t for t in truth if t.get("split", t["role"]) == "eval"]
    absent = [t["qid"] for t in ev if t["role"] == "absent" and t["condition"] == "clean" and t["bucket"] != "noise"]
    rest = [t["qid"] for t in ev if t["role"] != "absent" and t["condition"] in ("clean", "room", "room+crowd+10", "room+crowd0")]
    random.shuffle(rest)
    ids = set(absent) | set(rest[:500])
    with open(os.path.join(work, "q_scale.tsv"), "w") as f:
        for l in open(os.path.join(work, "queries.tsv")):
            if l.split("_")[0] in ids:
                f.write(l)


def report(work, threshold):
    truth = {}
    for l in open(os.path.join(work, "truth.jsonl")):
        t = json.loads(l); truth[t["qid"]] = t
    kept = {l.split("\t")[0] for l in open(os.path.join(work, "songs.tsv")) if l.rstrip("\n").split("\t")[4] != "absent"}
    real = len(kept)
    # Held-out songs that are the same recording as an indexed song (see evaluate.py) are left out here too: found
    # in the largest run by over half of their queries naming one and the same song.
    twins = set()
    paths = sorted(glob.glob(os.path.join(work, "scale_*.tsv")), key=lambda p: int(p.split("_")[-1][:-4]))
    if paths:
        named = {}
        for l in open(paths[-1]):
            r = l.rstrip("\n").split("\t")
            t = truth[r[0].split("_")[0]]
            if len(r) >= 18 and t["role"] == "absent":
                named.setdefault(t["song"], []).append(r[4] if float(r[16]) >= threshold else None)
        for song, got in named.items():
            top = max(set(got), key=got.count)
            if top is not None and got.count(top) > len(got) / 2:
                twins.add(song)
    print("### Against catalogue size: one core, a sample of eval queries\n")
    if twins:
        print(f"({len(twins)} held-out song(s) that are the same recording as an indexed song are left out.)\n")
    print(f"The index holds {real} real songs; smaller sizes drop songs (queries whose song was dropped are left out of 'right'), larger ones add altered copies of real constellations.\n")
    print("| songs in the index | answer an 8 s query, ms: median / 95th | 3 s | 12 s | a song not in the index named anyway (3 / 5 / 8 / 12 s) | right, songs in the index (8 s) |\n|---|---|---|---|---|---|")
    for path in sorted(glob.glob(os.path.join(work, "scale_*.tsv")), key=lambda p: int(p.split("_")[-1][:-4])):
        size = int(path.split("_")[-1][:-4])
        rows = [l.rstrip("\n").split("\t") for l in open(path)]
        rows = [r for r in rows if len(r) >= 18 and truth[r[0].split("_")[0]]["song"] not in twins]
        ids = sorted(kept)[:size] if size < real else None
        def ms(length):
            v = np.array([float(r[3]) for r in rows if r[0].endswith(f"_{length}")])
            return f"{np.median(v):.0f} / {np.quantile(v, 0.95):.0f}"
        fa = []
        for length in (3, 5, 8, 12):
            sel = [r for r in rows if r[0].endswith(f"_{length}") and truth[r[0].split("_")[0]]["role"] == "absent"]
            fa.append(f"{sum(float(r[16]) >= threshold for r in sel)}")
        n_abs = sum(1 for r in rows if r[0].endswith("_8") and truth[r[0].split("_")[0]]["role"] == "absent")
        pos = [r for r in rows if r[0].endswith("_8") and truth[r[0].split("_")[0]]["role"] != "absent" and (ids is None or truth[r[0].split("_")[0]]["song"] in ids)]
        right = sum(1 for r in pos if float(r[16]) >= threshold and r[4] == truth[r[0].split("_")[0]]["song"])
        print(f"| {size} | {ms(8)} | {ms(3)} | {ms(12)} | {' / '.join(fa)} of {n_abs} | {100 * right / max(1, len(pos)):.0f} % of {len(pos)} |")


if __name__ == "__main__":
    work = sys.argv[2]
    if sys.argv[1] == "sample":
        sample(work)
    else:
        t = float(sys.argv[sys.argv.index("--threshold") + 1]) if "--threshold" in sys.argv else float(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "threshold.txt")).read())
        report(work, t)
