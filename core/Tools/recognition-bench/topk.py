#!/usr/bin/env python3
"""How often the right song is among the first pass's proposals (dev half), before any check.

  topk.py sample WORK                 pick the dev clips once (WORK/q_topk.tsv): clean, room, room + crowd at +10, 0 and
                                      -5 dB, and speaker + room + crowd, at 5, 8 and 12 s
  topk.py run WORK BENCH NAME [bench arguments...]    match with --proposals 100, save WORK/topk/NAME.tsv
  topk.py table WORK                  recall within the first 1, 10, 30, 50 and 100 proposals, per configuration
"""
import json, os, subprocess, sys

CONDS = ["clean", "room", "room+crowd+10", "room+crowd0", "room+crowd-5", "booth(speaker+room+crowd0)"]
KS = (1, 10, 30, 50, 100)


def truth_of(work):
    return {t["qid"]: t for t in (json.loads(l) for l in open(os.path.join(work, "truth.jsonl")))}


def sample(work):
    truth = truth_of(work)
    ids = {q for q, t in truth.items() if t["role"] == "dev" and t["condition"] in CONDS and (t["condition"] != "clean" or t["cell"] == "grid")}
    n = 0
    with open(os.path.join(work, "q_topk.tsv"), "w") as f:
        for l in open(os.path.join(work, "queries.tsv")):
            name = l.split("\t")[0]
            if name.split("_")[0] in ids and name.split("_")[1] in ("5", "8", "12"):
                f.write(l); n += 1
    print("queries:", n)


def run(work, bench, name, args):
    os.makedirs(os.path.join(work, "topk"), exist_ok=True)
    prints = "prints"
    if "--prints" in args:
        i = args.index("--prints"); prints = args[i + 1]; args = args[:i] + args[i + 2:]
    subprocess.run([bench, "match", "--prints", os.path.join(work, prints), "--queries", os.path.join(work, "q_topk.tsv"),
                    "--leave-out", os.path.join(work, "absent.txt"), "--out", os.path.join(work, "topk", name + ".tsv"),
                    "--memory-out", os.path.join(work, "topk", name + ".mem"), "--proposals", "100"] + args, check=True, stderr=subprocess.DEVNULL)


def table(work):
    truth = truth_of(work)
    print("Right song within the first 1 / 10 / 30 / 50 / 100 proposals, percent of dev queries (all three lengths pooled; 8 s alone in brackets for 50).\n")
    print("| first pass | memory, KB a song | " + " | ".join(c.replace("room+", "").replace("booth(speaker+room+crowd0)", "speaker + crowd 0") for c in CONDS) + " |")
    print("|---|---|" + "---|" * len(CONDS))
    for f in sorted(os.listdir(os.path.join(work, "topk")), key=lambda f: os.path.getmtime(os.path.join(work, "topk", f))):
        if not f.endswith(".tsv"):
            continue
        name = f[:-4]
        songs, memory, _, _ = (int(x) for x in open(os.path.join(work, "topk", name + ".mem")).read().split())
        rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(work, "topk", f))]
        cells = []
        for c in CONDS:
            sel = [r for r in rows if truth[r[0].split("_")[0]]["condition"] == c and len(r) >= 19]
            def rec(rs, k):
                return 100 * sum(1 for r in rs if truth[r[0].split("_")[0]]["song"] in r[18].split("\x1f")[:k]) / max(1, len(rs))
            eight = [r for r in sel if r[0].endswith("_8")]
            cells.append(" / ".join(f"{rec(sel, k):.0f}" for k in KS) + f" ({rec(eight, 50):.0f})")
        print(f"| {name} | {memory / 1e3 / songs:.0f} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    if sys.argv[1] == "sample":
        sample(sys.argv[2])
    elif sys.argv[1] == "run":
        run(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
    else:
        table(sys.argv[2])
