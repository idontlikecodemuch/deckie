#!/usr/bin/env python3
"""Chromaprint (the open fingerprint AcoustID uses) measured as a baseline on the recognition bench.

What it is: a bench baseline only. It shells out to the `fpcalc` command-line tool and to the small
matcher in chromaprint_match.c; nothing here is ever linked into a product, and no audio is kept.

How to run (WORK is the bench work folder holding songs.tsv, queries.tsv, truth.jsonl; results go to
WORK/chromaprint/):

  gcc -O3 -mpopcnt -o WORK/chromaprint/chromaprint_match chromaprint_match.c
  chromaprint_baseline.py catalogue WORK   fingerprint every catalogue song whole (fpcalc -raw, default algorithm)
  chromaprint_baseline.py queries WORK     pick the clips, write each to a temporary WAV, fingerprint, delete
  chromaprint_baseline.py match WORK       slide every query over every song at every offset (bit error rate)
  chromaprint_baseline.py report WORK      thresholds on the dev half, results on the eval half -> report.md

Heavy steps run under `nice -n 10` with at most 2 processes.
"""
import collections, json, os, statistics, subprocess, sys, tempfile, time, wave
from concurrent.futures import ThreadPoolExecutor

import numpy as np

LENGTHS = (3, 5, 8, 12)
JOBS = 2
BOOTH = ("room", "room+crowd+10", "room+crowd0", "blend0")
FPCALC = ["nice", "-n", "10", "fpcalc", "-raw", "-json", "-length", "1000000"]


def out_dir(work):
    d = os.path.join(work, "chromaprint")
    os.makedirs(d, exist_ok=True)
    return d


def catalogue_songs(work):
    rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(work, "songs.tsv"))]
    return [r for r in rows if r[4] != "absent"]


def fpcalc(path):
    """Raw fingerprint of one file: (frames as uint32 array, wall seconds, cpu seconds)."""
    t = time.time()
    p = subprocess.Popen(FPCALC + [path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    data = p.stdout.read()
    _, _, ru = os.wait4(p.pid, 0)
    p.returncode = 0
    wall = time.time() - t
    try:
        fp = json.loads(data)["fingerprint"]
    except Exception:
        fp = []            # "Empty fingerprint": input shorter than Chromaprint's minimum
    return np.array(fp, dtype="<u4"), wall, ru.ru_utime + ru.ru_stime


def catalogue(work):
    d = out_dir(work)
    songs = catalogue_songs(work)
    with ThreadPoolExecutor(JOBS) as ex:
        res = list(ex.map(lambda s: fpcalc(s[1]), songs))
    pos = 0
    with open(os.path.join(d, "cat.u32"), "wb") as fb, open(os.path.join(d, "cat.idx"), "w") as fi, \
            open(os.path.join(d, "songs_fp.tsv"), "w") as ft:
        for s, (fp, wall, cpu) in zip(songs, res):
            fb.write(fp.tobytes())
            fi.write(f"{pos}\t{len(fp)}\n")
            ft.write(f"{s[0]}\t{s[3]}\t{len(fp)}\t{4 * len(fp)}\t{wall:.3f}\t{cpu:.3f}\n")
            pos += len(fp)
    print(f"{len(songs)} songs, {pos} frames, {4 * pos} bytes")


def cells_of(t):
    """Report cells a clip belongs to (speed-mixed booth cells are handled in select())."""
    if t["role"] == "absent":
        if t["condition"] != "clean":
            return None
        return "noise" if t["bucket"] == "noise" else f"absent {t['mode']} {t['percent']:+d}"
    if t["cell"] == "grid" and t["condition"] == "clean" and t["mode"] in ("vinyl", "tempo") \
            and abs(t["percent"]) in (0, 2, 6):
        return f"clean {t['mode']} {t['percent']:+d}"
    if t["cell"] == "booth" and t["condition"] in BOOTH:
        return f"{t['condition']} {t['mode']} {t['percent']:+d}"
    return None


def select(work):
    """qid -> (truth, split, tags). Tags: 'eval' cells take the first 100 clips in file order per
    (condition, mode, fader) cell; the speed-mixed booth cells are stored grouped by speed, so 'whole'
    is the first 20 of each of the five speeds and 'at0' the first 100 at fader 0. Dev: the first 50 of
    each of the six no-right-answer cells (300) and 100 clean clips (fader 0, then +-2)."""
    seen = collections.Counter()
    sel = {}
    for l in open(os.path.join(work, "truth.jsonl")):
        t = json.loads(l)
        split = t.get("split", t["role"])
        c = cells_of(t)
        if c is None:
            continue
        key = (split, c)
        k = seen[key]
        tags = []
        if split == "eval":
            if t["cell"] == "booth":
                if t["percent"] == 0 and k < 100:
                    tags.append("at0")
                if k < 20:
                    tags.append("whole")
            elif k < 100:
                tags.append("cell")
        else:
            if t["role"] == "absent" and k < 50:
                tags.append("devneg")
            if t["cell"] == "grid" and t["mode"] == "vinyl" and abs(t["percent"]) <= 2:
                n = sum(v for (s, cc), v in seen.items() if s == "dev" and cc.startswith("clean vinyl")
                        and cc.split()[-1] in ("+0", "-2", "+2") and cc != c) + k
                if t["percent"] == 0 or n < 100:
                    tags.append("devpos")
        seen[key] += 1
        if tags:
            sel[t["qid"]] = (t, split, tags)
    return sel


def queries(work):
    d = out_dir(work)
    sel = select(work)
    # dev clean: keep exactly the 40 at fader 0 plus the first 60 others
    pos = [q for q, (t, s, tags) in sel.items() if "devpos" in tags]
    zero = [q for q in pos if sel[q][0]["percent"] == 0]
    keep = set(zero) | set([q for q in pos if sel[q][0]["percent"] != 0][:100 - len(zero)])
    for q in pos:
        if q not in keep:
            sel[q][2].remove("devpos")
    sel = {q: v for q, v in sel.items() if v[2]}
    ids = {s[0]: i for i, s in enumerate(catalogue_songs(work))}
    jobs = []
    for l in open(os.path.join(work, "queries.tsv")):
        name, raw, first, count, rate = l.rstrip("\n").split("\t")
        qid, sec = name.rsplit("_", 1)
        if qid in sel and int(sec) in LENGTHS:
            jobs.append((name, raw, int(first), int(count), int(rate)))
    tmp = tempfile.mkdtemp(prefix="cpq_", dir=d)

    def one(j):
        name, raw, first, count, rate = j
        with open(raw, "rb") as f:
            f.seek(2 * first)
            pcm = f.read(2 * count)
        p = os.path.join(tmp, name + ".wav")
        with wave.open(p, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(pcm)
        try:
            return fpcalc(p)
        finally:
            os.remove(p)

    with ThreadPoolExecutor(JOBS) as ex:
        res = list(ex.map(one, jobs))
    os.rmdir(tmp)
    posn = 0
    with open(os.path.join(d, "q.u32"), "wb") as fb, open(os.path.join(d, "q.idx"), "w") as fi, \
            open(os.path.join(d, "q_sel.tsv"), "w") as fs:
        for j, (fp, wall, cpu) in zip(jobs, res):
            t, split, tags = sel[j[0].rsplit("_", 1)[0]]
            truth = ids.get(t["song"], -1) if t["role"] != "absent" else -1
            fb.write(fp.tobytes())
            fi.write(f"{posn}\t{len(fp)}\t{truth}\n")
            fs.write(f"{j[0]}\t{split}\t{','.join(tags)}\t{len(fp)}\t{cpu:.4f}\n")
            posn += len(fp)
    print(f"{len(jobs)} queries, {posn} frames")


def match(work):
    d = out_dir(work)
    lines = open(os.path.join(d, "q.idx")).read().splitlines()
    parts, procs = [], []
    for k in range(JOBS):
        p = os.path.join(d, f"q.idx.{k}")
        open(p, "w").write("\n".join(lines[k::JOBS]) + "\n")
        o = open(os.path.join(d, f"match.{k}.tsv"), "w")
        procs.append(subprocess.Popen(["nice", "-n", "10", os.path.join(d, "chromaprint_match"),
                                       os.path.join(d, "cat.u32"), os.path.join(d, "cat.idx"),
                                       os.path.join(d, "q.u32"), p], stdout=o))
        parts.append(p)
    for p in procs:
        if p.wait():
            sys.exit("matcher failed")
    outs = [open(os.path.join(d, f"match.{k}.tsv")).read().splitlines() for k in range(JOBS)]
    with open(os.path.join(d, "match.tsv"), "w") as f:
        for i in range(len(lines)):
            f.write(outs[i % JOBS][i // JOBS] + "\n")
    for k in range(JOBS):
        os.remove(parts[k]); os.remove(os.path.join(d, f"match.{k}.tsv"))
    print(len(lines), "queries matched")


def load(work):
    d = out_dir(work)
    songs = catalogue_songs(work)
    truth = {t["qid"]: t for t in (json.loads(l) for l in open(os.path.join(work, "truth.jsonl")))}
    rows = []
    for s, m in zip(open(os.path.join(d, "q_sel.tsv")), open(os.path.join(d, "match.tsv"))):
        name, split, tags, nf, cpu = s.rstrip("\n").split("\t")
        m = m.split("\t")
        qid, sec = name.rsplit("_", 1)
        b, r = int(m[1]), int(m[4])
        rows.append(dict(name=name, qid=qid, len=int(sec), split=split, tags=tags.split(","), t=truth[qid],
                         frames=int(m[0]), id=songs[b][0] if b >= 0 else None, score=float(m[2]),
                         id2=songs[r][0] if r >= 0 else None, score2=float(m[5]), true=float(m[6]),
                         wrong=float(m[8]), ms=float(m[9]), fp_cpu=float(cpu)))
    return rows


def med(x):
    x = list(x)
    return f"{statistics.median(x):.3f}" if x else "-"


def report(work):
    d = out_dir(work)
    rows = load(work)
    W = []
    P = W.append
    fps = [l.split("\t") for l in open(os.path.join(d, "songs_fp.tsv"))]
    byts = [int(f[3]) for f in fps]; secs = [float(f[1]) for f in fps]
    wall = [float(f[4]) for f in fps]; cpu = [float(f[5]) for f in fps]
    rate = sum(int(f[2]) for f in fps) / sum(secs)

    # No held-out song is set aside here: Chromaprint's error rate gives no clean way to tell a second
    # release of a catalogue track from a near neighbour, so every no-right-answer clip counts.
    def is_twin(r):
        return False

    T, negn = {}, {}
    for L in LENGTHS:
        neg = sorted(r["score"] for r in rows if "devneg" in r["tags"] and r["len"] == L and not is_twin(r))
        negn[L] = neg
        k = max(1, int(0.001 * len(neg)))          # all but at most one fall at or above the threshold
        T[L] = neg[k]

    def verdict(r):
        if r["frames"] == 0 or r["score"] >= T[r["len"]]:
            return "none"
        if r["t"]["role"] != "absent" and r["id"] == r["t"]["song"]:
            return "right"
        if r["id"] == r["t"].get("second"):
            return "second"
        return "wrong"

    for r in rows:
        r["v"] = verdict(r)
        r["top1"] = r["t"]["role"] != "absent" and r["id"] == r["t"]["song"]
    ev = [r for r in rows if r["split"] == "eval"]

    def grid(mode, pcs):
        return lambda r: "cell" in r["tags"] and r["t"]["cell"] == "grid" and r["t"]["mode"] == mode \
            and r["t"]["percent"] in pcs

    def booth(cond, tag):
        return lambda r: tag in r["tags"] and r["t"]["cell"] == "booth" and r["t"]["condition"] == cond

    cells = [("clean, fader 0", grid("vinyl", (0,))),
             ("clean, vinyl ±2", grid("vinyl", (-2, 2))), ("clean, vinyl ±6", grid("vinyl", (-6, 6))),
             ("clean, key held ±2", grid("tempo", (-2, 2))), ("clean, key held ±6", grid("tempo", (-6, 6)))]
    for c in BOOTH:
        cells += [(f"{c}, all five speeds", booth(c, "whole")), (f"{c}, fader 0 only", booth(c, "at0"))]

    def pct(k, n):
        return f"{100 * k / n:.0f}" if n else "-"

    P("# Chromaprint as a baseline on the recognition bench\n")
    P(open(os.path.join(d, "used.md")).read().rstrip() + "\n")
    P("## Thresholds (dev half only)\n")
    P("Score = bit error rate (differing bits / compared bits) of the best song at its best offset; lower is better. "
      "A song is named only when the score is under the threshold. Threshold per query length = the second-lowest "
      "score among the dev no-right-answer queries (so all but one of them are not named; with 300 clips the 99.9% "
      "rule and the all-but-one rule are the same thing).\n")
    P("| length | frames in the query | bits | dev no-right-answer clips | threshold | their lowest | their median | dev clean clips (true song's error rate, median) |\n|---|---|---|---|---|---|---|---|")
    for L in LENGTHS:
        fr = statistics.median(r["frames"] for r in rows if r["len"] == L)
        P(f"| {L} s | {fr:.0f} | {32 * fr:.0f} | {len(negn[L])} | {T[L]:.4f} | {negn[L][0]:.4f} | {statistics.median(negn[L]):.3f} | "
          f"{med(r['true'] for r in rows if 'devpos' in r['tags'] and r['len'] == L and r['t']['percent'] == 0)} |")
    P("")
    P("## Right / wrong by condition and length (eval half only)\n")
    P("Each entry: right % / wrong % (the rest is `none`), then in brackets top-1 % ignoring the threshold "
      "(is the true song the lowest error rate of all 969?). n = clips per entry. For blends, naming the other song "
      "of the mix is counted apart (see below), not as wrong; top-1 is for the first song only.\n")
    P("| condition | n | " + " | ".join(f"{L} s" for L in LENGTHS) + " |\n|---|---|" + "---|" * len(LENGTHS))
    for name, f in cells:
        cs = []
        n = 0
        for L in LENGTHS:
            s = [r for r in ev if f(r) and r["len"] == L]
            n = len(s)
            cs.append(f"{pct(sum(r['v'] == 'right' for r in s), n)} / {pct(sum(r['v'] == 'wrong' for r in s), n)} "
                      f"[{pct(sum(r['top1'] for r in s), n)}]")
        P(f"| {name} | {n} | " + " | ".join(cs) + " |")
    P("")
    P("Blend at equal level: how often the other song of the mix is the one named (under the threshold) / is top-1:\n")
    P("| condition | " + " | ".join(f"{L} s" for L in LENGTHS) + " |\n|---|" + "---|" * len(LENGTHS))
    for name, f in cells:
        if name.startswith("blend0"):
            cs = []
            for L in LENGTHS:
                s = [r for r in ev if f(r) and r["len"] == L]
                cs.append(f"{pct(sum(r['v'] == 'second' for r in s), len(s))} / "
                          f"{pct(sum(r['id'] == r['t'].get('second') for r in s), len(s))}")
            P(f"| {name} | " + " | ".join(cs) + " |")
    P("")
    P("## False names where there is no right answer (eval half only)\n")
    P("Counts of queries that named a song (score under the threshold). No held-out song is set aside.\n")
    P("| queries | " + " | ".join(f"{L} s" for L in LENGTHS) + " |\n|---|" + "---|" * len(LENGTHS))
    ab = lambda r: "cell" in r["tags"] and r["t"]["role"] == "absent"
    groups = [("absent songs, clean, all five speed cells", lambda r: ab(r) and r["t"]["bucket"] != "noise" and not is_twin(r)),
              ("absent songs, clean, fader 0 only", lambda r: ab(r) and r["t"]["bucket"] != "noise" and not is_twin(r) and r["t"]["percent"] == 0),
              ("noise alone", lambda r: ab(r) and r["t"]["bucket"] == "noise")]
    for name, f in groups:
        cs = []
        for L in LENGTHS:
            s = [r for r in ev if f(r) and r["len"] == L]
            cs.append(f"{sum(r['v'] != 'none' for r in s)} of {len(s)}")
        P(f"| {name} | " + " | ".join(cs) + " |")
    P("")
    P("## Size and time\n")
    P(f"- Frame rate measured: {rate:.3f} frames per second of audio, 32 bits each ({rate * 4:.1f} bytes per second).")
    P(f"- Bytes per song (raw, 4 bytes per frame): median {statistics.median(byts):.0f}, mean {statistics.mean(byts):.0f}, "
      f"largest {max(byts)}; whole catalogue of {len(fps)} songs {sum(byts)} bytes. Songs average {statistics.mean(secs):.0f} s.")
    P(f"- Seconds to fingerprint one song (fpcalc on the MP3, decode included), CPU time of the one process: median "
      f"{statistics.median(cpu):.2f}, mean {statistics.mean(cpu):.2f}; wall time on the shared machine: median "
      f"{statistics.median(wall):.2f}, mean {statistics.mean(wall):.2f}. That is {sum(cpu) / sum(secs) * 1000:.2f} ms of CPU per second of audio.")
    P("- Milliseconds to answer one query on one core (exhaustive slide over every song and offset, matcher only; wall time, "
      "machine shared, two matchers running): " + "; ".join(
          f"{L} s: median {statistics.median(r['ms'] for r in rows if r['len'] == L):.0f}" for L in LENGTHS) +
      f". Fingerprinting the query itself (fpcalc process on a WAV): median {1000 * statistics.median(r['fp_cpu'] for r in rows):.0f} ms CPU.")
    P("- The matcher is exhaustive (no index): its time grows in proportion to catalogue size times query length.\n")
    P("## Error-rate distributions (eval half)\n")
    P("Median bit error rate of the true song at its best offset, against the best of the 968 other songs; "
      "random bits give 0.5 for one alignment, and the minimum over about 1.5 million alignments is far lower for short queries.\n")
    P("| condition | length | true song, median | true song, 10th-90th percentile | best wrong song, median | threshold | true song under the threshold % |\n|---|---|---|---|---|---|---|")
    for name in ("clean, fader 0", "clean, vinyl ±2", "clean, vinyl ±6", "clean, key held ±6", "room, fader 0 only",
                 "room+crowd0, fader 0 only", "blend0, fader 0 only"):
        f = dict(cells)[name]
        for L in LENGTHS:
            s = [r for r in ev if f(r) and r["len"] == L]
            tr = sorted(r["true"] for r in s)
            P(f"| {name} | {L} s | {med(tr)} | {np.quantile(tr, 0.1):.3f}-{np.quantile(tr, 0.9):.3f} | "
              f"{med(r['wrong'] for r in s)} | {T[L]:.4f} | {pct(sum(x < T[L] for x in tr), len(tr))} |")
    P("")
    extra = os.path.join(d, "notes.md")
    if os.path.exists(extra):
        P(open(extra).read().rstrip() + "\n")
    open(os.path.join(d, "report.md"), "w").write("\n".join(W) + "\n")
    print("\n".join(W))


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("catalogue", "queries", "match", "report"):
        sys.exit(__doc__)
    {"catalogue": catalogue, "queries": queries, "match": match, "report": report}[sys.argv[1]](sys.argv[2])
