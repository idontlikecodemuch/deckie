#!/usr/bin/env python3
"""The size study: what the booth must hold in memory to match, against how well it still matches.

  size_study.py sample WORK                      pick the queries once (WORK/q_size.tsv)
  size_study.py run WORK BENCH NAME [bench arguments...]
                                                 one configuration: match the sample, add a row to WORK/size/rows.jsonl
  size_study.py table WORK                       the rows as a Markdown table

The sample, at 5, 8 and 12 s: from the eval half, 500 clean clips (the whole fader, both modes), the 500 room clips,
the 500 with crowd 10 dB under the music and the 500 at equal level, and every clip of a song that is not in the
index (clean, and with room and crowd); from the dev half, the clips with no right answer only, which set each
configuration's own threshold (the confidence that 99.9 % of them stay under), as in the main benchmark. Every figure
in the table is the eval half.
"""
import json, os, random, subprocess, sys, time
import numpy as np

LENGTHS = ("5", "8", "12")
CONDITIONS = [("clean", "clean"), ("room", "room"), ("room+crowd+10", "crowd +10"), ("room+crowd0", "crowd 0")]


def load_truth(work):
    truth = {}
    for l in open(os.path.join(work, "truth.jsonl")):
        t = json.loads(l); truth[t["qid"]] = t
    return truth


def sample(work):
    random.seed(21)
    truth = load_truth(work)
    ids = set()
    for t in truth.values():
        split = t.get("split", t["role"])
        if t["role"] == "absent":
            ids.add(t["qid"])
        elif split == "eval" and t["cell"] == "booth" and t["condition"] in ("room", "room+crowd+10", "room+crowd0"):
            ids.add(t["qid"])
    clean = [t["qid"] for t in truth.values() if t.get("split", t["role"]) == "eval" and t["cell"] == "grid" and t["mode"] != "atempo"]
    random.shuffle(clean)
    ids |= set(clean[:500])
    n = 0
    with open(os.path.join(work, "q_size.tsv"), "w") as f:
        for l in open(os.path.join(work, "queries.tsv")):
            name = l.split("\t")[0]
            if name.split("_")[0] in ids and name.split("_")[1] in LENGTHS:
                f.write(l); n += 1
    print("queries:", n)


def run(work, bench, name, args):
    out = os.path.join(work, "size")
    os.makedirs(out, exist_ok=True)
    res = os.path.join(out, name + ".tsv"); mem = os.path.join(out, name + ".mem")
    prints = "prints"
    if "--prints" in args:
        i = args.index("--prints"); prints = args[i + 1]; args = args[:i] + args[i + 2:]
    t0 = time.time()
    if "--join" in args:
        args = args + ["--join-map", os.path.join(out, name + ".join")]
    subprocess.run([bench, "match", "--prints", os.path.join(work, prints), "--queries", os.path.join(work, "q_size.tsv"),
                    "--leave-out", os.path.join(work, "absent.txt"), "--out", res, "--memory-out", mem,
                    "--jobs", str(os.cpu_count())] + args, check=True, stderr=subprocess.DEVNULL)
    with open(os.path.join(out, "rows.jsonl"), "a") as f:
        f.write(json.dumps(dict(name=name, args=" ".join(args), prints=prints, seconds=time.time() - t0)) + "\n")
    print(json.dumps({k: (round(v, 1) if isinstance(v, float) else v) for k, v in metrics(work, name, prints).items()}))


def metrics(work, name, prints="prints"):
    """One configuration's figures, worked out from its saved answers."""
    out = os.path.join(work, "size")
    res = os.path.join(out, name + ".tsv"); mem = os.path.join(out, name + ".mem")
    truth = load_truth(work)
    # With the copies test (--duplicate-all, --join), a song's copy or a joined file that contains it is the song.
    joined = {}
    if os.path.exists(os.path.join(out, name + ".join")):
        for l in open(os.path.join(out, name + ".join")):
            f = l.rstrip("\n").split("\t"); joined[f[0]] = set(f[1:])
    def same(answer, song):
        return answer == song or answer == song + "~copy" or song in joined.get(answer, ())
    rows = []
    for l in open(res):
        f = l.rstrip("\n").split("\t")
        if len(f) >= 18:
            t = truth[f[0].split("_")[0]]
            rows.append((t, f[0].split("_")[1], t["song"] if same(f[4], t["song"]) else f[4], float(f[16]), float(f[3])))
    neg = sorted(r[3] for r in rows if r[0]["role"] == "absent" and r[0].get("split") == "dev")
    T = float(np.quantile(neg, 0.999)) + 1e-6
    songs, memory, points, hashes = (int(x) for x in open(mem).read().split())
    disk = sum(os.path.getsize(os.path.join(work, prints, f)) for f in os.listdir(os.path.join(work, prints))) / len(os.listdir(os.path.join(work, prints)))
    row = dict(name=name, threshold=T, songs=songs, memory_kb_per_song=memory / 1e3 / songs,
               hashes_per_song=hashes / songs, disk_kb_per_song=disk / 1e3)
    wrong = total = 0
    for cond, label in CONDITIONS:
        for L in LENGTHS:
            sel = [r for r in rows if r[0]["role"] != "absent" and r[0]["condition"] == cond and r[1] == L and (cond != "clean" or r[0]["cell"] == "grid")]
            right = sum(1 for r in sel if r[3] >= T and r[2] == r[0]["song"])
            wrong += sum(1 for r in sel if r[3] >= T and r[2] != r[0]["song"]); total += len(sel)
            row[f"{label}/{L}"] = 100 * right / max(1, len(sel))
    row["wrong_per_1000"] = 1000 * wrong / max(1, total)
    # Songs that are not in the index, eval half, leaving out a held-out song that is the same recording as an
    # indexed one (over half of its clean queries name one same song, as in evaluate.py).
    by = {}
    for r in rows:
        if r[0]["role"] == "absent" and r[0]["bucket"] != "noise" and r[0]["condition"] == "clean":
            by.setdefault(r[0]["song"], []).append(r[2] if r[3] >= T else None)
    twins = {s for s, got in by.items() if max(set(got), key=got.count) is not None and got.count(max(set(got), key=got.count)) > len(got) / 2}
    ab = [r for r in rows if r[0]["role"] == "absent" and r[0].get("split") == "eval" and r[0]["song"] not in twins]
    row["absent_named_per_1000"] = 1000 * sum(1 for r in ab if r[3] >= T) / max(1, len(ab))
    ms = np.array([r[4] for r in rows if r[1] == "8"])
    row["ms_8s_median"] = float(np.median(ms)); row["ms_8s_p95"] = float(np.quantile(ms, 0.95))
    return row


def table(work):
    rows = {}
    for l in open(os.path.join(work, "size", "rows.jsonl")):
        r = json.loads(l)
        rows[r["name"]] = metrics(work, r["name"], r.get("prints", "prints"))
    print("| configuration | memory, KB a song | on disk, KB a song | clean 5 / 8 / 12 s | room | crowd 10 dB under | crowd at equal level | wrong per 1,000 | absent named per 1,000 | 8 s query, ms (four jobs): median / 95th |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for r in rows.values():
        cells = [" / ".join(f"{r[f'{label}/{L}']:.0f}" for L in LENGTHS) for _, label in CONDITIONS]
        print(f"| {r['name']} | {r['memory_kb_per_song']:.0f} | {r['disk_kb_per_song']:.0f} | " + " | ".join(cells) +
              f" | {r['wrong_per_1000']:.1f} | {r['absent_named_per_1000']:.1f} | {r['ms_8s_median']:.0f} / {r['ms_8s_p95']:.0f} |")


if __name__ == "__main__":
    if sys.argv[1] == "sample":
        sample(sys.argv[2])
    elif sys.argv[1] == "run":
        run(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
    else:
        table(sys.argv[2])
