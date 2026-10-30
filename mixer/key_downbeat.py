#!/usr/bin/env python3
"""Research R, the third cheap idea: chroma weighted toward the beat grid, on the outside set (GiantSteps-MTG-key).

The recommended reader (key_parity.recommended, row 3f) sums whitened HPCP frames with equal weight. Harmony is
carried most by what sounds on the strong beats (the bass note on the downbeat names the chord root, and chords
change on bar lines far more often than inside a bar: the metrical hierarchy of Lerdahl and Jackendoff 1983), so
frames on the downbeat and on the beat may deserve more weight than the frames between them. The beat grid comes
from Apple's Music Understanding run on the same clips (tools/mubench, <outdir>/<id>.mu.json: rhythm.bars and
rhythm.beats), standing in for the engine's grid, which is the same kind of thing.

Four weightings, all fixed before the run, none tuned (library-blind, D5): equal (the baseline, must reproduce
key_outside_results.tsv); downbeat frames only; beat frames only; metrical (downbeat frame 1, other beat frames 1/2,
frames between beats 1/4). Each is scored on every annotated clip and on the major and minor halves and the data
set's confidence levels separately. No variant is chosen here: the sheet shows all four.

usage (from mixer/): .venv/bin/python key_downbeat.py <mu outdir> <manifest.json> [--jobs 2] [--limit N] [--out key_downbeat.tsv]
"""
import argparse, csv, json, os, sys, warnings
from collections import Counter, defaultdict
warnings.filterwarnings("ignore")
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import key_parity as KP


VARIANTS = ("equal", "downbeat", "beat", "metrical")
MIREX = {"exact": 1.0, "fifth": 0.5, "relative": 0.3, "parallel": 0.2}


def secs(t):
    return float(t["value"]) / float(t.get("timescale") or 1) if isinstance(t, dict) else float(t)


def weights(n_frames, bars_s, beats_s):
    """Per-frame weights for each variant. A beat or bar start lands in the frame holding its time (frames are
    4096 samples at 44.1 kHz, about 93 ms, no overlap)."""
    fr = lambda ts: np.unique(np.clip((np.asarray(ts) * KP.SR44 / KP.H44).astype(int), 0, n_frames - 1))
    db, bt = fr(bars_s), fr(beats_s)
    w = {"equal": np.ones(n_frames)}
    d = np.zeros(n_frames); d[db] = 1.0; w["downbeat"] = d
    b = np.zeros(n_frames); b[bt] = 1.0; w["beat"] = b
    m = np.full(n_frames, 0.25); m[bt] = 0.5; m[db] = 1.0; w["metrical"] = m
    return w


def one(item):
    cid, path, mu_path = item
    try:
        mu = json.load(open(mu_path)).get("rhythm") or {}
        bars = [secs(x) for x in mu.get("bars") or []]; beats = [secs(x) for x in mu.get("beats") or []]
        if not bars or not beats:
            return cid, None, "no grid"
        y, _ = KP.load44(path)
        F, M, E, rms, Emax = KP.spectral_peaks(y)
        H = KP.hpcp(F, M, Emax[1 / 3], n_harm=4, whiten=True, frame_norm=False)
        out = {}
        for name, w in weights(H.shape[0], bars, beats).items():
            if w.sum() <= 0:
                out[name] = None; continue
            pcp = (H * w[:, None]).sum(axis=0) / w.sum()
            cam, margin, agree, sure = KP.decide(pcp)
            out[name] = (cam, round(margin, 4), agree, int(sure))
        return cid, (out, len(bars), len(beats)), None
    except Exception as e:
        return cid, None, str(e)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir"); ap.add_argument("manifest")
    ap.add_argument("--jobs", type=int, default=2); ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--out", default=os.path.join(HERE, "key_downbeat.tsv"))
    a = ap.parse_args()
    ours = {r["id"]: r for r in csv.DictReader(open(os.path.join(HERE, "key_outside_results.tsv")), delimiter="\t")}
    paths = {m["id"]: m["path"] for m in json.load(open(a.manifest))}
    items = []
    for cid in sorted(ours):
        mu = os.path.join(a.outdir, cid + ".mu.json")
        if cid in paths and os.path.exists(mu) and ours[cid].get("camelot"):
            items.append((cid, paths[cid], mu))
    if a.limit: items = items[:a.limit]
    print(f"{len(items)} annotated clips with a grid and audio; {a.jobs} worker(s)", flush=True)
    from multiprocessing import Pool
    rows, failed = [], Counter()
    with Pool(a.jobs) as pool:
        for i, (cid, res, err) in enumerate(pool.imap_unordered(one, items, chunksize=4), 1):
            if err:
                failed[err[:40]] += 1; continue
            out, nb, nbt = res; r = ours[cid]
            row = dict(id=cid, annotation=r["annotation"], camelot=r["camelot"], confidence=r.get("dataset_confidence", ""),
                       bars=nb, beats=nbt, ours=r["predicted"], ours_relation=r["relation"])
            for v in VARIANTS:
                if out.get(v):
                    cam, margin, agree, sure = out[v]
                    row[v] = cam; row[v + "_relation"] = KP.relation(cam, r["camelot"])[1]
                    row[v + "_margin"] = margin; row[v + "_sure"] = sure
                else:
                    row[v] = ""; row[v + "_relation"] = ""; row[v + "_margin"] = ""; row[v + "_sure"] = ""
            rows.append(row)
            if i % 50 == 0: print(f"  {i}/{len(items)}", flush=True)
    rows.sort(key=lambda r: r["id"])
    cols = list(rows[0].keys())
    with open(a.out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, delimiter="\t"); w.writeheader(); w.writerows(rows)
    if failed: print("failed:", dict(failed))
    report(rows)


def score(rows, col):
    c = Counter(r[col] for r in rows if r[col]); n = sum(c.values()) or 1
    mirex = sum(MIREX.get(k, 0) * v for k, v in c.items()) / n
    return n, c, mirex


def line(label, rows, col):
    n, c, mirex = score(rows, col)
    return (f"| {label} | {n} | {100*c['exact']/n:.1f} | {100*c['fifth']/n:.1f} | {100*c['relative']/n:.1f} | "
            f"{100*c['parallel']/n:.1f} | {100*(n-c['exact']-c['fifth']-c['relative']-c['parallel'])/n:.1f} | {100*mirex:.1f} |")


def report(rows):
    head = "| variant | clips | exact | fifth | relative | parallel | other | MIREX |\n|---|---:|---:|---:|---:|---:|---:|---:|"
    print("\n## All annotated clips\n" + head)
    print(line("stored 3f (key_outside_results)", rows, "ours_relation"))
    for v in VARIANTS: print(line(v, rows, v + "_relation"))
    for half, pred in (("major", lambda r: r["camelot"].endswith("B")), ("minor", lambda r: r["camelot"].endswith("A"))):
        sub = [r for r in rows if pred(r)]
        print(f"\n## {half} half ({len(sub)} clips)\n" + head)
        for v in VARIANTS: print(line(v, sub, v + "_relation"))
    for conf in sorted({r["confidence"] for r in rows}):
        sub = [r for r in rows if r["confidence"] == conf]
        print(f"\n## data set confidence {conf} ({len(sub)} clips)\n" + head)
        for v in VARIANTS: print(line(v, sub, v + "_relation"))
    # where the variants part from the baseline
    for v in VARIANTS[1:]:
        ch = [r for r in rows if r[v] and r[v] != r["equal"]]
        up = sum(1 for r in ch if r[v + "_relation"] == "exact" and r["equal_relation"] != "exact")
        down = sum(1 for r in ch if r["equal_relation"] == "exact" and r[v + "_relation"] != "exact")
        print(f"\n{v}: answer differs from equal on {len(ch)} clips; exact gained {up}, lost {down}, net {up-down:+d}")


if __name__ == "__main__":
    main()
