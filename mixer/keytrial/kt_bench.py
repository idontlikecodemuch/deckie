#!/usr/bin/env python3
"""Key trial, phase 1: the bench. Re-runs letter R's three readers from this trial's own decode of the clips and
checks them, clip for clip, against the sheets letter R committed; fixes the folds; writes bench_readers.tsv.

  python kt_bench.py            (needs kt_extract.py to have run)

Readers (all from mixer/key_parity.py and mixer/key_overtones.py, unchanged):
  3f  whitened 4-harmonic HPCP, mean correlation over Faraldo's three profiles (letter R's recommended row)
  A   3f with the third and fifth harmonics' shares taken off each frame (A-both-frame-H4w)
  B   note transcription (NNLS, s = 0.7, full range), then the same decision (B-s07-full-faraldo)"""
import os, sys, csv
import numpy as np
import kt
import key_parity as KP
import key_overtones as KO

def frames(cid):
    """(H4w per frame (T, 12), notes (T, 84)) for a clip; H4w is cached beside the features."""
    p = os.path.join(kt.CACHE, "h4w", cid + ".npy"); z = np.load(os.path.join(kt.CACHE, "feat", cid + ".npz"))
    if os.path.exists(p): H = np.load(p)
    else:
        H = KP.hpcp(z["F"], z["M"], z["E"], n_harm=4, whiten=True, frame_norm=False).astype(np.float32)
        os.makedirs(os.path.dirname(p), exist_ok=True); np.save(p, H)
    return H, z["notes"].astype(np.float32)

def pcp_3f(H): return H.astype(np.float64).sum(axis=0)
def pcp_A(H): return KO.discount(H.astype(np.float64), "both").sum(axis=0)
def pcp_B(N):
    c = np.zeros(12); np.add.at(c, (np.arange(84) + 21) % 12, N.astype(np.float64).sum(axis=0)); return c

def scores24(pcp):
    """mean Pearson r over Faraldo's three profiles for the 24 keys (KP.decide's score)."""
    return sum(KP.corr24(pcp, KP.km(p)) for p in KP.FARALDO) / len(KP.FARALDO)

def one(cid):
    H, N = frames(cid)
    return cid, [scores24(f(x)) for f, x in ((pcp_3f, H), (pcp_A, H), (pcp_B, N))]

def readers(clips, jobs=4):
    """id -> {'3f','A','B'} -> 24 scores. Cached in $DECKIE_KT_CACHE/readers_<set>.npz."""
    from multiprocessing import Pool
    with Pool(jobs) as pool: res = dict(pool.imap_unordered(one, [c["id"] for c in clips], chunksize=8))
    return {cid: dict(zip(("3f", "A", "B"), r)) for cid, r in res.items()}

def table(title, rows, cols=("exact", "home", "mode_home", "fifth", "relative", "parallel", "other", "mirex")):
    print(f"\n{title}\n| reader | part | clips | exact | home note | mode given home | fifth | relative | parallel | other | MIREX |\n|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for name, pred, true in rows:
        for part, s in zip(("all", "major", "minor"), kt.halves(pred, true)):
            print(f"| {name} | {part} | {s['n']} | " + " | ".join(kt.fmt(s[c]) for c in cols) + " |")

def main():
    out = []
    apple = kt.apple_keys()
    old = {r["id"]: r for r in csv.DictReader(open(os.path.join(kt.MIXER, "key_overtones.tsv")), delimiter="\t")}
    for name in ("mtg", "gs", "gsplus"):
        allc = kt.load(name); fold, grp = kt.folds(allc)
        for c, f, g in zip(allc, fold, grp): c["fold"] = f; c["group"] = g
        have = [c for c in allc if os.path.exists(os.path.join(kt.CACHE, "feat", c["id"] + ".npz"))]
        R = readers(have)
        for c in have:
            for k in ("3f", "A", "B"): c[k] = int(np.argmax(R[c["id"]][k]))
            c["apple"] = apple.get(c["id"]) if name == "mtg" else None
        np.savez_compressed(os.path.join(kt.CACHE, f"readers_{name}.npz"), ids=np.array([c["id"] for c in have]),
                            **{k: np.array([R[c["id"]][k] for c in have], np.float32) for k in ("3f", "A", "B")})
        lab = [c for c in have if c["key"] is not None]
        true = np.array([c["key"] for c in lab])
        print(f"\n== {name}: clips in the sheet with audio {len(allc)}, features {len(have)}, plain-key labels {len(lab)} "
              f"({int((true < 12).sum())} major, {int((true >= 12).sum())} minor), artist groups {len(set(grp))}, "
              f"clips per fold {[sum(1 for c in lab if c['fold'] == f) for f in range(kt.NFOLD)]}, "
              f"minor share per fold {[round(100 * np.mean([c['key'] >= 12 for c in lab if c['fold'] == f])) for f in range(kt.NFOLD)]}")
        rows = [(k, np.array([c[k] for c in lab]), true) for k in ("3f", "A", "B")]
        table(f"{name}, all plain-key clips", rows)
        if name == "mtg":
            # agreement with letter R's committed per-clip keys
            for k, col in (("3f", "3f"), ("A", "A-both-frame-H4w"), ("B", "B-s07-full-faraldo")):
                both = [c for c in lab if c["id"] in old and old[c["id"]].get(col)]
                same = sum(kt.CAM[c[k]] == old[c["id"]][col] for c in both)
                print(f"\n{k}: same key as letter R's sheet on {same} of {len(both)} clips ({100 * same / max(1, len(both)):.2f} percent)")
            ap = [c for c in lab if c["apple"] is not None]; t = np.array([c["key"] for c in ap])
            table("mtg, the 1,270 clips Apple read", [("Apple", np.array([c["apple"] for c in ap]), t)] +
                  [(k, np.array([c[k] for c in ap]), t) for k in ("3f", "A", "B")])
            held = [c for c in ap if c["fold"] in kt.HELD]; t = np.array([c["key"] for c in held])
            table(f"mtg, held-out part (folds {kt.HELD}) of the 1,270", [("Apple", np.array([c["apple"] for c in held]), t)] +
                  [(k, np.array([c[k] for c in held]), t) for k in ("3f", "A", "B")])
        if name == "gsplus":
            mod = [c for c in have if c.get("key_modal") is not None]; t = np.array([c["key_modal"] for c in mod])
            table("gsplus, single-key clips with modal labels counted by their third", [(k, np.array([c[k] for c in mod]), t) for k in ("3f", "A", "B")])
        out += have
    with open(os.path.join(kt.HERE, "bench_readers.tsv"), "w") as fh:
        fh.write("set\tid\tlabel\tkey\tkey_modal\tconfidence\tfold\tgroup\tapple\t3f\tA\tB\n")
        nm = lambda k: "" if k is None else kt.key_name(k)
        for c in out:
            fh.write("\t".join(str(x) for x in (c["set"], c["id"], c["label"].strip(), nm(c["key"]), nm(c.get("key_modal")), c["conf"], c["fold"], c["group"],
                                                 nm(c.get("apple")), nm(c["3f"]), nm(c["A"]), nm(c["B"]))) + "\n")

if __name__ == "__main__":
    main()
