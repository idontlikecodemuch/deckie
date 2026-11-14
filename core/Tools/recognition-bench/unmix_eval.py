#!/usr/bin/env python3
"""The trial's test on DJ mixes with ground truth: UnmixDB (Schwarz and Fourer 2018, Zenodo 1422385, CC BY-NC-ND 4.0;
the tracks under the licences its attribution file lists). Nothing it reads or writes belongs in the repository.

Each UnmixDB mix plays three track excerpts in a row with beat-matched cross-fades, the second and third brought to the
first one's tempo three ways ("none": left alone; "resample": vinyl-style; "stretch": key held) and with one of four
effects on the whole mix (none, bass boost, compressor, distortion). Its label files give when each track starts,
fades and stops, and its speed factor.

  unmix_eval.py prepare UNMIX_DIR WORK     decode the excerpts and mixes (16 kHz mono), write the lists
  unmix_eval.py report WORK                tables from WORK/unmix/results.tsv

Between the two, run.sh fingerprints the excerpts into the same folder as the benchmark's own songs (so every mix is
matched against the excerpts AND the outside songs as distractors) and matches a window every 4 s along each mix.
A window counts as "one song" when it lies wholly between a track's fade-in end and its fade-out start, and as
"transition" when it touches a cross-fade.
"""
import glob, hashlib, json, os, subprocess, sys
from collections import defaultdict
from multiprocessing import Pool
import numpy as np

SR = 16000
LENGTHS = [5, 8, 12]
STEP = 4.0


def decode(job):
    src, dst = job
    if not os.path.exists(dst):
        r = subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-i", src, "-ac", "1", "-ar", str(SR), "-f", "s16le", dst + ".part"])
        if r.returncode != 0:
            return 0
        os.replace(dst + ".part", dst)
    return os.path.getsize(dst) / 2 / SR


def ref_id(name):
    return "u" + hashlib.sha1(name.encode()).hexdigest()[:12]


def labels(path):
    tracks = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        f = line.rstrip("\n").split("\t")
        if len(f) < 4:
            continue
        t0, t1, k, kind = float(f[0]), float(f[1]), int(f[2]), f[3]
        tr = tracks.setdefault(k, {})
        value = f[4].strip('"') if len(f) > 4 else ""
        if kind == "start":
            tr["start"] = t0; tr["name"] = value
        elif kind == "speed":
            tr["speed"] = float(value)
        elif kind in ("fadein", "fadeout"):
            tr[kind] = (t0, t1)
        elif kind == "stop":
            tr["stop"] = t0
    return tracks


def prepare(unmix, work):
    out = os.path.join(os.path.abspath(work), "unmix")
    os.makedirs(os.path.join(out, "pcm"), exist_ok=True)
    refs = sorted(glob.glob(os.path.join(unmix, "**", "refsongs", "*.mp3"), recursive=True))
    mixes = sorted(glob.glob(os.path.join(unmix, "**", "mixes", "*.mp3"), recursive=True))
    jobs = [(p, os.path.join(out, "pcm", ref_id(os.path.basename(p)) + ".s16")) for p in refs]
    jobs += [(p, os.path.join(out, "pcm", "mix_" + os.path.splitext(os.path.basename(p))[0] + ".s16")) for p in mixes]
    with Pool(os.cpu_count()) as pool:
        secs = pool.map(decode, jobs)
    with open(os.path.join(out, "print-list.tsv"), "w") as f:
        for (p, dst), s in zip(jobs[:len(refs)], secs):
            if s > 0:
                f.write(f"{ref_id(os.path.basename(p))}\t{dst}\n")
    n = 0
    with open(os.path.join(out, "queries.tsv"), "w") as q, open(os.path.join(out, "truth.jsonl"), "w") as t:
        for (p, dst), s in zip(jobs[len(refs):], secs[len(refs):]):
            lab = p[:-4] + ".labels.txt"
            if s <= 0 or not os.path.exists(lab):
                continue
            tracks = labels(lab)
            name = os.path.splitext(os.path.basename(p))[0]          # e.g. set222mix3-resample-bass-06
            parts = name.split("-")
            at = 0.0
            while at + max(LENGTHS) <= s:
                for length in LENGTHS:
                    a, b = at, at + length
                    solo, audible = None, []
                    for k, tr in tracks.items():
                        begin = tr.get("fadein", (tr.get("start", 0), tr.get("start", 0)))
                        end = tr.get("fadeout", (tr.get("stop", s), tr.get("stop", s)))
                        if a < end[1] and b > begin[0]:
                            audible.append(k)
                        if a >= begin[1] and b <= end[0]:
                            solo = k
                    truth = dict(qid=f"x{n:06d}", mix=name, timescale=parts[1], effect=parts[2], at=at, length=length,
                                 kind="one song" if solo else "transition",
                                 songs=[ref_id(tracks[k]["name"]) for k in ([solo] if solo else audible) if "name" in tracks[k]],
                                 speeds=[tracks[k].get("speed", 1) for k in ([solo] if solo else audible) if "name" in tracks[k]])
                    q.write(f"x{n:06d}_{length}\t{dst}\t{int(a * SR)}\t{int(length * SR)}\t{SR}\n")
                    t.write(json.dumps(truth) + "\n")
                    n += 1
                at += STEP
    print("excerpts:", len(refs), "mixes:", len(mixes), "windows:", n)


def report(work, threshold):
    out = os.path.join(work, "unmix")
    truth = {}
    for line in open(os.path.join(out, "truth.jsonl")):
        t = json.loads(line); truth[t["qid"]] = t
    rows = []
    for line in open(os.path.join(out, "results.tsv")):
        f = line.rstrip("\n").split("\t")
        if len(f) >= 18:
            rows.append((truth[f[0].split("_")[0]], f[4], float(f[16]), float(f[8]), float(f[9]), f[10], float(f[17])))
    print(f"UnmixDB windows: {len(rows)}; threshold on the confidence {threshold:.2f} (the benchmark's, not chosen here).\n")
    # UnmixDB brings some tracks to the first one's tempo by factors far outside any pitch fader (0.71 to 2.0).
    # Those windows are counted apart: the matcher only tries speeds to 17 % either way.
    def beyond(t):
        return any(abs(v - 1) > 0.16 for v in t["speeds"])
    far = [r for r in rows if beyond(r[0]) and r[0]["kind"] == "one song"]
    rows = [r for r in rows if not beyond(r[0])]
    print("### One song playing at a speed beyond 16 % (outside the fader's range; not tried by the matcher)\n")
    print("| length | windows | right / wrong / none, percent |\n|---|---|---|")
    for l in LENGTHS:
        sel = [r for r in far if r[0]["length"] == l]
        if sel:
            right = sum(1 for r in sel if r[2] >= threshold and r[1] in r[0]["songs"])
            wrong = sum(1 for r in sel if r[2] >= threshold and r[1] not in r[0]["songs"])
            print(f"| {l} s | {len(sel)} | {100 * right / len(sel):.0f} / {100 * wrong / len(sel):.0f} / {100 * (len(sel) - right - wrong) / len(sel):.0f} |")
    print("\nEverything below is the windows within 16 %.\n")
    print("### One song playing: right / wrong / none, percent of windows\n")
    print("| time scaling | effect | windows | " + " | ".join(f"{l} s" for l in LENGTHS) + " |\n|---|---|---|" + "---|" * len(LENGTHS))
    scales = sorted({r[0]["timescale"] for r in rows}); effects = sorted({r[0]["effect"] for r in rows})
    for sc in scales:
        for ef in effects + ["all"]:
            cells = []; n = 0
            for l in LENGTHS:
                sel = [r for r in rows if r[0]["kind"] == "one song" and r[0]["timescale"] == sc and (ef == "all" or r[0]["effect"] == ef) and r[0]["length"] == l]
                n = len(sel)
                if not n:
                    cells.append("-"); continue
                right = sum(1 for r in sel if r[2] >= threshold and r[1] in r[0]["songs"])
                wrong = sum(1 for r in sel if r[2] >= threshold and r[1] not in r[0]["songs"])
                cells.append(f"{100 * right / n:.0f} / {100 * wrong / n:.0f} / {100 * (n - right - wrong) / n:.0f}")
            print(f"| {sc} | {ef} | {n} | " + " | ".join(cells) + " |")
    print("\n### During a cross-fade: one of the songs in the mix named / a song outside it named / none; both named\n")
    print("| time scaling | windows | " + " | ".join(f"{l} s" for l in LENGTHS) + " |\n|---|---|" + "---|" * len(LENGTHS))
    for sc in scales:
        cells = []; n = 0
        for l in LENGTHS:
            sel = [r for r in rows if r[0]["kind"] == "transition" and r[0]["timescale"] == sc and r[0]["length"] == l]
            n = len(sel)
            if not n:
                cells.append("-"); continue
            right = sum(1 for r in sel if r[2] >= threshold and r[1] in r[0]["songs"])
            wrong = sum(1 for r in sel if r[2] >= threshold and r[1] not in r[0]["songs"])
            both = sum(1 for r in sel if r[2] >= threshold and r[6] >= threshold and r[1] in r[0]["songs"] and r[5] in r[0]["songs"])
            cells.append(f"{100 * right / n:.0f} / {100 * wrong / n:.0f} / {100 * (n - right - wrong) / n:.0f}; {100 * both / n:.0f}")
        print(f"| {sc} | {n} | " + " | ".join(cells) + " |")
    print("\n### The speed reading against the labels' speed factor, one song playing, right answers (fader points)\n")
    print("| time scaling | length | n | share of windows off zero by 1 % or more | tempo reading: median / 90th error | pitch reading: median / 90th error (resample only) |\n|---|---|---|---|---|---|")
    for sc in scales:
        for l in LENGTHS:
            sel = [r for r in rows if r[0]["kind"] == "one song" and r[0]["timescale"] == sc and r[0]["length"] == l and r[2] >= threshold and r[1] in r[0]["songs"]]
            if not sel:
                continue
            true = np.array([r[0]["speeds"][r[0]["songs"].index(r[1])] for r in sel])
            e = np.abs((np.array([r[3] for r in sel]) - true) * 100)
            pe = np.abs((np.array([r[4] for r in sel]) - true) * 100)
            off = float(np.mean(np.abs(true - 1) >= 0.01))
            print(f"| {sc} | {l} s | {len(sel)} | {100 * off:.0f} | {np.median(e):.2f} / {np.quantile(e, 0.9):.2f} | " + (f"{np.median(pe):.2f} / {np.quantile(pe, 0.9):.2f}" if sc == "resample" else "-") + " |")
    by_mix = defaultdict(lambda: [0, 0])
    for r in rows:
        if r[0]["kind"] == "one song" and r[0]["length"] == 8:
            by_mix[r[0]["mix"]][1] += 1
            by_mix[r[0]["mix"]][0] += r[2] >= threshold and r[1] in r[0]["songs"]
    shares = sorted(a / b for a, b in by_mix.values() if b)
    if shares:
        print(f"\nBy mix (8 s, one song playing): {len(shares)} mixes; right in the worst mix {100 * shares[0]:.0f} %, the lowest tenth {100 * shares[len(shares) // 10]:.0f} %, the median mix {100 * shares[len(shares) // 2]:.0f} %.")


if __name__ == "__main__":
    if sys.argv[1] == "prepare":
        prepare(sys.argv[2], sys.argv[3])
    else:
        report(sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 3.0)
