#!/usr/bin/env python3
"""Measures the finished recogniser (deckie-listen) the way a booth would use it: sound fed second by second.

  listen_eval.py clips WORK            the benchmark's 12 s clips as a list for deckie-listen (WORK/listen/clips_dev.tsv,
                                       clips_eval.tsv) and UnmixDB's mixes (WORK/listen/mixes.tsv)
  listen_eval.py bench WORK READINGS [dev|eval]
                                       from deckie-listen's readings of the clips: named right by 3, 5, 8 and 12 s,
                                       wrong names, and names given to songs that are not in the index
  listen_eval.py mixes WORK READINGS   from its readings of the mixes: share of each song's seconds with the right
                                       name, seconds to the first right name, wrong names, names held after a song ended
"""
import json, os, sys
from collections import defaultdict
import numpy as np


def truth_of(work):
    return {t["qid"]: t for t in (json.loads(l) for l in open(os.path.join(work, "truth.jsonl")))}


def clips(work):
    os.makedirs(os.path.join(work, "listen"), exist_ok=True)
    truth = truth_of(work)
    files = {"dev": open(os.path.join(work, "listen", "clips_dev.tsv"), "w"), "eval": open(os.path.join(work, "listen", "clips_eval.tsv"), "w")}
    n = 0
    for l in open(os.path.join(work, "queries.tsv")):
        f = l.rstrip("\n").split("\t")
        if not f[0].endswith("_12"):
            continue
        t = truth[f[0].split("_")[0]]
        files[t.get("split", t["role"])].write("\t".join([f[0].split("_")[0]] + f[1:]) + "\n"); n += 1
    for f in files.values():
        f.close()
    mixes = 0
    if os.path.exists(os.path.join(work, "unmix", "truth.jsonl")):
        names = sorted({json.loads(l)["mix"] for l in open(os.path.join(work, "unmix", "truth.jsonl"))})
        with open(os.path.join(work, "listen", "mixes.tsv"), "w") as f:
            for name in names:
                path = os.path.join(os.path.abspath(work), "unmix", "pcm", "mix_" + name + ".s16")
                f.write(f"{name}\t{path}\t0\t{os.path.getsize(path) // 2}\t16000\n"); mixes += 1
    print("clips:", n, "mixes:", mixes)


def readings(path):
    by = defaultdict(list)
    for l in open(path):
        f = l.rstrip("\n").split("\t")
        if len(f) >= 9:
            by[f[0]].append((float(f[1]), f[2], f[3], f[4], f[5], f[6], float(f[7]), float(f[8])))
    return by


def bench(work, path, half):
    truth = truth_of(work)
    by = readings(path)
    marks = (3, 5, 8, 12)
    # A held-out song that is the same recording as an indexed one (it names one same song in over half its clean clips).
    named = defaultdict(list)
    for q, rs in by.items():
        t = truth[q]
        if t["role"] == "absent" and t["bucket"] != "noise" and t["condition"] == "clean":
            ids = [r[2] for r in rs if r[1] != "nothingYet"]
            named[t["song"]].append(ids[0] if ids else None)
    twins = {s for s, got in named.items() if max(set(got), key=got.count) is not None and got.count(max(set(got), key=got.count)) > len(got) / 2}
    rows = defaultdict(lambda: {m: [0, 0] for m in marks})
    count = defaultdict(int)
    ms = []
    for q, rs in by.items():
        t = truth[q]
        if t.get("split", t["role"]) != half or t["song"] in twins and t["role"] == "absent":
            continue
        if t["role"] == "absent":
            key = "no right answer: " + ("noise alone" if t["bucket"] == "noise" else ("song not in the index, clean" if t["condition"] == "clean" else "song not in the index, room + crowd 0 dB"))
        elif t["cell"] == "grid":
            key = "clean, " + {"vinyl": "vinyl-style", "tempo": "key held", "atempo": "key held"}[t["mode"]]
        else:
            key = t["condition"]
        count[key] += 1
        ms += [r[7] for r in rs]
        for m in marks:
            upto = [r for r in rs if r[0] <= m + 1e-6 and r[1] != "nothingYet"]
            if t["role"] == "absent":
                rows[key][m][1] += bool(upto)
            else:
                good = {t["song"], t.get("second")}
                rows[key][m][0] += any(r[2] == t["song"] for r in upto)
                rows[key][m][1] += any(r[2] not in good for r in upto)
    print(f"### The listener on the benchmark's clips ({half} half): the right song named by / a wrong song named by, percent of clips\n")
    print("| condition | clips | " + " | ".join(f"{m} s" for m in marks) + " |\n|---|---|" + "---|" * len(marks))
    for key in sorted(k for k in rows if not k.startswith("no right")):
        n = count[key]
        print(f"| {key} | {n} | " + " | ".join(f"{100 * rows[key][m][0] / n:.0f} / {100 * rows[key][m][1] / n:.1f}" for m in marks) + " |")
    print("\n| no right answer: a song named anyway by | clips | " + " | ".join(f"{m} s" for m in marks) + " |\n|---|---|" + "---|" * len(marks))
    for key in sorted(k for k in rows if k.startswith("no right")):
        print(f"| {key[17:]} | {count[key]} | " + " | ".join(f"{rows[key][m][1]}" for m in marks) + " |")
    ms = np.array(ms)
    print(f"\nA reading took {np.median(ms):.0f} ms at the median, {np.quantile(ms, 0.95):.0f} at the 95th percentile, {ms.max():.0f} at most ({len(ms)} readings).")


def mixes(work, path):
    by = readings(path)
    # Each mix's tracks from the labels behind unmix/truth.jsonl: rebuild solo spans from the 5 s windows.
    spans = defaultdict(lambda: defaultdict(lambda: [1e9, -1e9, 1.0]))   # mix -> song -> [first solo second, last, speed]
    audible = defaultdict(lambda: defaultdict(lambda: [1e9, -1e9]))
    meta = {}
    for l in open(os.path.join(work, "unmix", "truth.jsonl")):
        t = json.loads(l)
        if t["length"] != 5:
            continue
        meta[t["mix"]] = (t["timescale"], t["effect"])
        for s, v in zip(t["songs"], t["speeds"]):
            a = audible[t["mix"]][s]; a[0] = min(a[0], t["at"]); a[1] = max(a[1], t["at"] + 5)
            if t["kind"] == "one song":
                sp = spans[t["mix"]][s]; sp[0] = min(sp[0], t["at"]); sp[1] = max(sp[1], t["at"] + 5); sp[2] = v
    out = defaultdict(lambda: dict(seconds=0, right=0, wrong=0, first=[], songs=0, never=0, late=0, speed=[]))
    for mix, rs in by.items():
        if mix not in meta:
            continue
        for song, (a, b, v) in spans[mix].items():
            if abs(v - 1) > 0.16:
                key = ("beyond 16 %", meta[mix][1])
            else:
                key = meta[mix]
            o = out[key]; o["songs"] += 1
            inside = [r for r in rs if a + 1e-6 < r[0] <= b + 1e-6]
            o["seconds"] += len(inside)
            o["right"] += sum(1 for r in inside if r[1] != "nothingYet" and r[2] == song)
            o["wrong"] += sum(1 for r in inside if r[1] != "nothingYet" and r[2] != song and r[2] not in audible[mix])
            first = [r[0] for r in rs if r[0] > audible[mix][song][0] and r[1] != "nothingYet" and r[2] == song]
            if first:
                o["first"].append(max(0.0, first[0] - a))
                o["speed"] += [abs(float(r[4]) - (v - 1) * 100) for r in inside if r[1] != "nothingYet" and r[2] == song and r[4] != "-"]
            else:
                o["never"] += 1
            end = audible[mix][song][1]
            o["late"] += sum(1 for r in rs if r[0] > end + 3 and r[1] != "nothingYet" and r[2] == song)
    print("### The listener on the generated mixes (UnmixDB): each song while it plays alone\n")
    print("| time scaling | effect | songs | seconds with the right name, percent | seconds with a song outside the mix named | first right name, seconds after the song is alone: median / 90th | never named | seconds still named 3 s after the song ended | speed reading error, points: median / 90th |")
    print("|---|---|---|---|---|---|---|---|---|")
    for key in sorted(out):
        o = out[key]
        f = np.array(o["first"]) if o["first"] else np.array([0.0])
        sp = np.array(o["speed"]) if o["speed"] else np.array([0.0])
        print(f"| {key[0]} | {key[1]} | {o['songs']} | {100 * o['right'] / max(1, o['seconds']):.1f} | {o['wrong']} of {o['seconds']} | {np.median(f):.0f} / {np.quantile(f, 0.9):.0f} | {o['never']} | {o['late']} | {np.median(sp):.2f} / {np.quantile(sp, 0.9):.2f} |")


if __name__ == "__main__":
    if sys.argv[1] == "clips":
        clips(sys.argv[2])
    elif sys.argv[1] == "bench":
        bench(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "eval")
    else:
        mixes(sys.argv[2], sys.argv[3])
