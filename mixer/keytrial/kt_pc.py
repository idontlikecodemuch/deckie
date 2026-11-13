#!/usr/bin/env python3
"""Key trial: precision against coverage. A reader may show a key, show only the home note (mode open), or say 'not
sure'. Coverage is the share of songs that get an answer; precision is how often a shown answer is right.

  python kt_pc.py        (needs kt_bench.py, kt_modefeats.py; uses kt_cnn.py's outputs when they exist)
                         -> prints the tables; writes pc_curves.tsv

Confidence signals, none fitted (each only orders the clips; a product threshold would be set on one part of an outside
set and checked on another, which the selection / held-out columns show):
  margin     the reader's best key score minus its second best (the trained model: its top probability)
  agreement  how many of the three untrained readers (3f, A, B) name the shown key
  sections   the clip cut in three equal parts, each read alone: how many parts name the shown key
  combined   agreement + sections (0 to 6), ties broken by margin

Targets are the tools DJs use, from published tests (letter X): on the MTG clips Apple's framework (measured on the
same clips, letter R) and Mixed In Key 7 and KeyFinder (Faraldo et al. 2017, on 1,160 confident clips of the same
collection, so near but not the same clips); on the 604 GiantSteps Key clips rekordbox 3, Mixed In Key 7 and KeyFinder
(Knees et al. 2015). No tool has a published score on GiantSteps+ that this trial could verify."""
import os, sys, warnings
warnings.filterwarnings("ignore")
import numpy as np
import kt, kt_x
import key_overtones as KO
from kt_bench import frames, pcp_3f, pcp_A, pcp_B, scores24

TARGETS = {"mtg": [("Apple (same clips, all)", 65.2, 78.3), ("Mixed In Key 7 (Faraldo 2017)", 65.7, 81.8), ("KeyFinder (Faraldo 2017)", 54.8, 76.3)],
           "gs": [("rekordbox 3 (Knees 2015)", 71.9, None), ("Mixed In Key 7 (Knees 2015; Faraldo 2017)", 67.2, 82.5), ("KeyFinder (Knees 2015)", 45.4, None)],
           "gsplus": []}
COVS = (100, 90, 80, 70, 60, 50, 40, 30, 20)

def sec_one(cid):
    H, N = frames(cid); T = H.shape[0]; out = np.zeros((3, 3, 24), np.float32)
    for s in range(3):
        a, b = s * T // 3, (s + 1) * T // 3
        for j, (f, x) in enumerate(((pcp_3f, H[a:b]), (pcp_A, H[a:b]), (pcp_B, N[a:b]))): out[j, s] = scores24(f(x))
    return cid, out

def sections(name, ids):
    """(N, 3 readers, 3 sections, 24) scores; cached."""
    p = os.path.join(kt.CACHE, f"sections_{name}.npz")
    if os.path.exists(p):
        z = np.load(p); pos = {i: k for k, i in enumerate(z["ids"])}
        if all(i in pos for i in ids): return z["S"][np.array([pos[i] for i in ids])]
    from multiprocessing import Pool
    with Pool(2) as pool: res = dict(pool.imap_unordered(sec_one, ids, chunksize=8))
    S = np.array([res[i] for i in ids]); np.savez_compressed(p, ids=np.array(ids), S=S); return S

def rank(*keys):
    """order of clips, most confident first, by the given signals in turn (lexicographic)."""
    return np.lexsort(tuple(-np.asarray(k, float) for k in reversed(keys)))

def w1(pred, true): return np.array([kt.relation(int(p), int(t)) in ("exact", "fifth", "relative") for p, t in zip(pred, true)])

def curve(name, method, signal, order, pred, true, part, fh, apple=None, targets=()):
    ex = pred == true; ok1 = w1(pred, true); home = pred % 12 == true % 12; n = len(true)
    print(f"\n**{method}, ordered by {signal}** ({name}, {part}, {n} clips)\n\n| shown, percent | key right (95 percent interval) | within one step | home note right | minor share of shown |" + (" Apple right on the same clips | ours ahead / Apple ahead, p |" if apple is not None else "") + "\n|---:|---:|---:|---:|---:|" + ("---:|---:|" if apple is not None else ""))
    for c in COVS:
        k = max(1, int(round(n * c / 100))); s = order[:k]; lo, hi = kt.wilson(int(ex[s].sum()), k)
        line = f"| {c} | {100 * ex[s].mean():.1f} ({lo:.0f} to {hi:.0f}) | {100 * ok1[s].mean():.1f} | {100 * home[s].mean():.1f} | {100 * (true[s] >= 12).mean():.0f} |"
        if apple is not None:
            g, l, p = kt.paired(apple[s] == true[s], ex[s]); line += f" {100 * (apple[s] == true[s]).mean():.1f} | {g} / {l}, {p:.2g} |"
        print(line); fh.write(f"{name}\t{part}\t{method}\t{signal}\t{c}\t{100 * ex[s].mean():.2f}\t{lo:.2f}\t{hi:.2f}\t{100 * ok1[s].mean():.2f}\t{100 * home[s].mean():.2f}\n")
    grid = {}
    for c in COVS:
        k = max(1, int(round(n * c / 100))); s = order[:k]; grid[c] = (100 * ex[s].mean(), kt.wilson(int(ex[s].sum()), k)[0], 100 * ok1[s].mean())
    top = lambda f: max([c for c in COVS if f(grid[c])] or [0])
    for tn, tex, tw1 in targets:
        print(f"\n- against {tn}, exact {tex}: on the grid above, shown keys are as right with up to **{top(lambda g: g[0] >= tex)} percent** of clips shown, and clearly better (the whole 95 percent interval above it) with up to **{top(lambda g: g[1] >= tex)} percent**" +
              (f"; within one step ({tw1}): as right up to {top(lambda g: g[2] >= tw1)} percent." if tw1 else "."))

def main():
    fh = open(os.path.join(kt.HERE, "pc_curves.tsv"), "w"); fh.write("set\tpart\tmethod\tsignal\tshown_percent\texact\texact_lo\texact_hi\twithin_one_step\thome\n")
    M = kt_x.load_set("mtg"); M["GS"] = kt_x.load_set("gs"); apple = kt.apple_keys()
    for name, label, title in (("mtg", "key", "GiantSteps-MTG-key (the 1,270 clips Apple read)"), ("gsplus", "key_modal", "GiantSteps+ (single-key clips, modal labels by their third)"), ("gs", "key", "GiantSteps Key (604, original labels)")):
        D = M if name == "mtg" else kt_x.load_set(name, label)
        P = kt_x.readers(D, M); true = D["key"]; n = len(true); ar = np.arange(n); sel = np.ones(n, bool); ap = None
        if name == "mtg": ap = np.array([apple.get(i, -1) for i in D["ids"]]); sel = ap >= 0
        S = sections(name, D["ids"]); R = D["R"]
        k3, kA, kB, kBA = (P[x] for x in ("3f (letter R's first reader)", "A (harmonic discount)", "B (note transcription)", "B's home note + A's mode"))
        def margin(sc): o = np.sort(sc, axis=1); return o[:, -1] - o[:, -2]
        sec_key = S.argmax(3)                                                   # (N, reader, section)
        tB = kB % 12; secBA = (S[:, 2].argmax(2) % 12 == tB[:, None]) & ((S[:, 1][ar[:, None], np.arange(3)[None, :], 12 + tB[:, None]] > S[:, 1][ar[:, None], np.arange(3)[None, :], tB[:, None]]) == (kBA >= 12)[:, None])
        methods = [("row B", kB, {"margin": (margin(R["B"]),), "agreement": ((k3 == kB).astype(int) + (kA == kB), margin(R["B"])), "sections": ((sec_key[:, 2] == kB[:, None]).sum(1), margin(R["B"])),
                                  "combined": ((k3 == kB).astype(int) + (kA == kB) + (sec_key[:, 2] == kB[:, None]).sum(1), margin(R["B"]))}),
                   ("row B's home note + row A's mode", kBA, {"combined": ((k3 == kBA).astype(int) + (kA == kBA) + (kB == kBA) + secBA.sum(1), margin(R["B"]) + np.abs(D["sA"]))})]
        kM = P["multi-profile steps (gate, minor2) on row B's chroma"]
        methods.append(("published multi-profile steps (gate, second minor template) on row B's chroma", kM, {"combined": ((k3 == kM).astype(int) + (kA == kM) + (kB == kM) + (kBA == kM) + (sec_key[:, 2] % 12 == (kM % 12)[:, None]).sum(1), margin(R["B"]))}))
        lpp = D["prof_AB"]; prp = np.exp(lpp); kP = prp.argmax(1)
        lpe = D["prof_AB_eq"]; pre_ = np.exp(lpe); kE = pre_.argmax(1)
        methods.append(("learned profiles on rows A and B, modes weighed equally (EVALUATION ONLY)", kE, {"agreement with rows 3f, A and B, then probability": ((kE == kB).astype(int) + (kE == kA) + (kE == k3), pre_.max(1))}))
        methods.append(("learned profiles on rows A and B, 49 numbers (EVALUATION ONLY)", kP, {"its top probability": (prp.max(1),), "agreement with rows 3f, A and B, then probability": ((kP == kB).astype(int) + (kP == kA) + (kP == k3), prp.max(1))}))
        if "cnn_lp12" in D:
            lp = D["cnn_lp12"]; pr = np.exp(lp); pr /= pr.sum(1, keepdims=True); kC = pr.argmax(1); top = pr.max(1)
            methods.append(("trained model (EVALUATION ONLY)", kC, {"its top probability": (top,), "agreement with row B, then probability": ((kC == kB).astype(int), top),
                                                                     "agreement with rows 3f, A and B, then probability": ((kC == kB).astype(int) + (kC == kA) + (kC == k3), top)}))
            if "cnn_sec" in D:
                secC = (D["cnn_sec"].argmax(2) == kC[:, None]).sum(1); D["secC"] = secC
                methods[-1][2]["its own sections, then probability"] = (secC, top)
                methods[-1][2]["combined: agreement with 3f, A, B + its sections, then probability"] = ((kC == kB).astype(int) + (kC == kA) + (kC == k3) + secC, top)
            D["cnn_top"] = top; D["kC"] = kC
        print(f"\n## {title}")
        for mname, pred, sigs in methods:
            for sname, keys in sigs.items():
                idx = np.where(sel)[0]; order = rank(*[np.asarray(k)[idx] for k in keys])
                curve(name, mname, sname, order, pred[idx], true[idx], "all", fh, ap[idx] if ap is not None else None, TARGETS[name])
                if name == "mtg" and sname in ("combined", "agreement with rows 3f, A and B, then probability"):
                    for part, mask in (("selection folds 0-2", ~np.isin(D["fold"], kt.HELD)), ("held-out folds 3-4", np.isin(D["fold"], kt.HELD))):
                        idx2 = np.where(sel & mask)[0]; curve(name, mname, sname, rank(*[np.asarray(k)[idx2] for k in keys]), pred[idx2], true[idx2], part, fh, ap[idx2])
        # is each signal a confidence that can be trusted? exact rate at each level of the countable signals
        print(f"\n**How right each level of a signal is** ({name})\n\n| signal | level | clips | key right | within one step | home note right |\n|---|---:|---:|---:|---:|---:|")
        def levels(sname, lev, pred):
            for v in sorted(set(lev[sel])):
                s = sel & (lev == v); print(f"| {sname} | {v} | {int(s.sum())} | {100 * (pred[s] == true[s]).mean():.1f} | {100 * w1(pred[s], true[s]).mean():.1f} | {100 * (pred[s] % 12 == true[s] % 12).mean():.1f} |")
        levels("row B: readers 3f and A that agree with it", (k3 == kB).astype(int) + (kA == kB), kB)
        levels("row B: sections (of three) that name the same key", (sec_key[:, 2] == kB[:, None]).sum(1), kB)
        mg = margin(R["B"]); q = np.quantile(mg[sel], [0.25, 0.5, 0.75]); levels("row B: margin, quarter of the clips (0 lowest)", np.searchsorted(q, mg), kB)
        levels("B's home + A's mode: combined (0 to 6)", (k3 == kBA).astype(int) + (kA == kBA) + (kB == kBA) + secBA.sum(1), kBA)
        def calib(label, top, kC):
            b = np.minimum((top * 10).astype(int), 9)
            print(f"\n**{label}: stated probability against how often it is right** ({name}; a calibrated confidence has the two columns equal)\n\n| stated probability | clips | mean stated | key right |\n|---|---:|---:|---:|")
            ece = 0.0
            for v in range(10):
                s = sel & (b == v)
                if s.sum(): print(f"| {v / 10:.1f} to {(v + 1) / 10:.1f} | {int(s.sum())} | {100 * top[s].mean():.1f} | {100 * (kC[s] == true[s]).mean():.1f} |"); ece += s.sum() / sel.sum() * abs(top[s].mean() - (kC[s] == true[s]).mean())
            print(f"\nMean gap between stated and observed: {100 * ece:.1f} points.")
        calib("Learned profiles on rows A and B", prp.max(1), kP)
        levels("learned profiles (A and B): untrained readers (3f, A, B) that agree with it", (kP == kB).astype(int) + (kP == kA) + (kP == k3), kP)
        if "cnn_top" in D:
            top = D["cnn_top"]; kC = D["kC"]; calib("The trained model", top, kC)
            levels("trained model: untrained readers (3f, A, B) that agree with it", (kC == kB).astype(int) + (kC == kA) + (kC == k3), kC)
            if "secC" in D: levels("trained model: sections (of three) that name the same key", D["secC"], kC)
        # three answers: key, home note with the mode open, not sure
        print(f"\n**Three answers** ({name}): 'not sure' when rows A and B disagree on the home note; 'mode open' when they agree on the home note and disagree on the mode there; a key otherwise\n")
        hA = kA % 12 == kB % 12; mA = D["sA"] > 0; mB = R["B"][ar, 12 + tB] > R["B"][ar, tB]
        key_s = sel & hA & (mA == mB); open_s = sel & hA & (mA != mB); ns = sel & ~hA
        print("| answer | percent of clips | right, of those | what 'right' means |\n|---|---:|---:|---|")
        print(f"| a key | {100 * key_s.sum() / sel.sum():.1f} | {100 * (kBA[key_s] == true[key_s]).mean():.1f} | the key (within one step: {100 * w1(kBA[key_s], true[key_s]).mean():.1f}; home note: {100 * (tB[key_s] == true[key_s] % 12).mean():.1f}) |")
        print(f"| home note, mode open | {100 * open_s.sum() / sel.sum():.1f} | {100 * (tB[open_s] == true[open_s] % 12).mean():.1f} | the home note |")
        print(f"| not sure | {100 * ns.sum() / sel.sum():.1f} | | (row B's key would have been right on {100 * (kB[ns] == true[ns]).mean():.1f}, its home note on {100 * (tB[ns] == true[ns] % 12).mean():.1f}) |")
        if ap is not None: print(f"\nApple on the clips given a key: {100 * (ap[key_s] == true[key_s]).mean():.1f} exact; on the mode-open clips {100 * (ap[open_s] == true[open_s]).mean():.1f}; on the not-sure clips {100 * (ap[ns] == true[ns]).mean():.1f}.")
    fh.close()

if __name__ == "__main__":
    main()
