#!/usr/bin/env python3
"""Key trial: every reader on every set, on the four measures letter X asks for, plus the three things it asked to be
drawn: the major-against-minor trade-off as the mode threshold moves, the open mode (coverage against precision), and
the published multi-profile method scored away from the set its profiles were made from.

  python kt_x.py        (needs kt_bench.py, kt_modefeats.py; uses kt_cnn.py's outputs when they exist)
                        -> prints the tables; writes x_results.tsv and x_clips_<set>.tsv

Measures. exact: key right, on the major and minor halves (D16's bar as written compares each half with Apple's).
mean of halves: the two halves' exact rates averaged, so a lean toward one mode cannot buy points. within one step:
exact, or the relative key, or a fifth either way (same Camelot number, or one step round the wheel). shown: when a
reader may leave a key unshown, the share shown (coverage) and how often a shown key is right (precision).

The published multi-profile method (Faraldo, Jorda and Herrera, AES Semantic Audio 2017), from its paper and the
number tables in the authors' scripts (read as numbers; no code copied or run): row 3f's whitened 4-harmonic HPCP of
the peaks above 200 Hz, summed; scaled to its largest value; values under 0.2 set to zero (the gate); correlated with
bgate's major and minor profiles and a second minor profile ('minor2', a minor with a strong major third); the best of
the 36 wins and minor2 counts as minor. The 'amodal' template (all weight on the home note) is used here only to mark
a clip's mode as open. The 200 Hz high-pass is stood in for by dropping the spectral peaks below 200 Hz."""
import os, sys, warnings
warnings.filterwarnings("ignore")
import numpy as np
import kt
import key_parity as KP
import kt_mode as KM

BGATE3 = np.array([[1., 0.00, 0.42, 0.00, 0.53, 0.37, 0.00, 0.77, 0.00, 0.38, 0.21, 0.30],
                   [1., 0.00, 0.36, 0.39, 0.00, 0.38, 0.00, 0.74, 0.27, 0.00, 0.42, 0.23],
                   [1., 0.26, 0.35, 0.29, 0.44, 0.36, 0.21, 0.78, 0.26, 0.25, 0.32, 0.26]])     # major, minor, minor2
MONO = np.array([1., 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

def corr_rot(c, prof):
    """Pearson r of c with the profile rotated to each of the 12 home notes."""
    c = c - c.mean(); n = np.linalg.norm(c)
    if n == 0: return np.zeros(12)
    out = np.zeros(12)
    for t in range(12):
        q = np.roll(prof, t); q = q - q.mean(); out[t] = c @ q / (n * np.linalg.norm(q))
    return out

def faraldo(C, three=True, gate=0.2):
    """keys (N,), and whether the one-note template beats all three (the 'amodal' mark)."""
    keys = np.zeros(len(C), int); amodal = np.zeros(len(C), bool)
    for i, c in enumerate(C):
        c = c / (c.max() + 1e-12)
        if gate: c = np.where(c < gate, 0.0, c)
        r = [corr_rot(c, p) for p in (BGATE3 if three else BGATE3[:2])]
        j = int(np.argmax([x.max() for x in r])); t = int(np.argmax(r[j]))
        keys[i] = t + (12 if j >= 1 else 0); amodal[i] = corr_rot(c, MONO).max() > max(x.max() for x in r)
    return keys, amodal

def load_set(name, label="key"):
    clips = kt.load(name); fold, grp = kt.folds(clips)
    Z = np.load(os.path.join(kt.CACHE, f"modefeats_{name}.npz")); pos = {i: k for k, i in enumerate(Z["ids"])}
    RZ = np.load(os.path.join(kt.CACHE, f"readers_{name}.npz")); rpos = {i: k for k, i in enumerate(RZ["ids"])}
    keep = [(c, f, g) for c, f, g in zip(clips, fold, grp) if c.get(label) is not None and c["id"] in pos]
    ids = [c["id"] for c, _, _ in keep]; ix = np.array([pos[i] for i in ids]); rx = np.array([rpos[i] for i in ids])
    D = {"name": name, "ids": ids, "key": np.array([c[label] for c, _, _ in keep]), "fold": np.array([f for _, f, _ in keep]),
         "names": [c["names"] for c, _, _ in keep], "genre": [str(c.get("genre") or "").split(",")[0].strip() for c, _, _ in keep], "conf": np.array([c["conf"] for c, _, _ in keep]),
         "F": {k: Z[k][ix].astype(np.float64) for k in Z.files if k != "ids"}, "R": {k: RZ[k][rx].astype(np.float64) for k in ("3f", "A", "B")}}
    return D

def cnn_lp(path, ids_key, lp_key, ids):
    if not os.path.exists(path): return None
    z = np.load(path); pos = {i: k for k, i in enumerate(z[ids_key])}
    if any(i not in pos for i in ids): return None
    return z[lp_key][np.array([pos[i] for i in ids])]

def readers(D, M):
    """name -> (keys, note). M: the MTG data, for the trained mode rule's fit on other sets."""
    n = len(D["key"]); ar = np.arange(n); R = D["R"]; F = D["F"]; out = {}
    for k, nm in (("3f", "3f (letter R's first reader)"), ("A", "A (harmonic discount)"), ("B", "B (note transcription)")): out[nm] = R[k].argmax(1)
    tB = R["B"].argmax(1) % 12
    sA = R["A"][ar, 12 + tB] - R["A"][ar, tB]
    out["B's home note + A's mode"] = tB + 12 * (sA > 0)
    for nm, src, three, gate in (("multi-profile, as published (200 Hz, gate, minor2)", "c_hp", True, 0.2), ("  the same without the 200 Hz cut", "c_3f", True, 0.2),
                                 ("  the same without minor2", "c_hp", False, 0.2), ("  the same without the gate", "c_hp", True, 0),
                                 ("  bgate's two profiles alone on row 3f's chroma", "c_3f", False, 0),
                                 ("multi-profile steps (gate, minor2) on row A's chroma", "c_A", True, 0.2), ("multi-profile steps (gate, minor2) on row B's chroma", "c_B", True, 0.2)):
        out[nm], am = faraldo(F[src], three, gate)
        if nm.startswith("multi-profile, as"): D["amodal"] = am
    # the 12-number trained mode rule on row B's chroma, at its natural setting (it leans minor as the training set does)
    s = np.zeros(n)
    if D["name"] == "mtg":
        tt = D["key"] % 12; mi = D["key"] >= 12
        for f in range(kt.NFOLD):
            te = D["fold"] == f; tr = ~te
            s[te], _ = KM.fit_predict("lr", KM.design(KM.sub(F, tr), tt[tr], "B12"), mi[tr].astype(int), KM.design(KM.sub(F, te), tB[te], "B12"))
    else:
        gn = set().union(*D["names"]); clean = np.array([not (x & gn) for x in M["names"]])
        s, _ = KM.fit_predict("lr", KM.design(KM.sub(M["F"], clean), M["key"][clean] % 12, "B12"), (M["key"][clean] >= 12).astype(int), KM.design(F, tB, "B12"))
    out["B's home note + trained 12-number mode rule (EVALUATION ONLY)"] = tB + 12 * (s > 0)
    D["sA"] = sA; D["sLR"] = s; D["tB"] = tB
    # learned profiles (kt_prof): out-of-fold on MTG; fitted on MTG's clips with no shared artist for the other sets
    import kt_prof as KPF
    for which, eq, nm in (("B", False, "learned profiles on row B's chroma, 25 numbers (EVALUATION ONLY)"), ("AB", False, "learned profiles on rows A and B, 49 numbers (EVALUATION ONLY)"),
                          ("AB", True, "  the same (rows A and B), major and minor weighed equally in the fit"),
                          ("all", False, "learned profiles on seven chromas, 169 numbers (EVALUATION ONLY)"), ("all", True, "  the same (seven chromas), major and minor weighed equally in the fit")):
        if D["name"] == "mtg":
            lp = np.zeros((n, 24))
            for f in range(kt.NFOLD):
                te = D["fold"] == f; lp[te] = KPF.predict(KM.sub(F, te), KPF.fit(KM.sub(F, ~te), D["key"][~te], which, eq), which)
        else:
            lp = KPF.predict(F, KPF.fit(KM.sub(M["F"], clean), M["key"][clean], which, eq), which)
        out[nm] = lp.argmax(1); D["prof_" + which + ("_eq" if eq else "")] = lp
    if D["name"] == "mtg" and "GS" in D:
        G = D["GS"]; gn2 = set().union(*D["names"]); gclean = np.array([not (x & gn2) for x in G["names"]])
        out["learned profiles on rows A and B, fitted on GiantSteps Key only (EVALUATION ONLY)"] = KPF.predict(F, KPF.fit(KM.sub(G["F"], gclean), G["key"][gclean], "AB"), "AB").argmax(1)
        out["  the same (rows A and B, GiantSteps Key only), major and minor weighed equally"] = KPF.predict(F, KPF.fit(KM.sub(G["F"], gclean), G["key"][gclean], "AB", True), "AB").argmax(1)
        out["learned profiles on seven chromas, fitted on GiantSteps Key only (EVALUATION ONLY)"] = KPF.predict(F, KPF.fit(KM.sub(G["F"], gclean), G["key"][gclean], "all"), "all").argmax(1)
        out["  the same (seven chromas, GiantSteps Key only), major and minor weighed equally"] = KPF.predict(F, KPF.fit(KM.sub(G["F"], gclean), G["key"][gclean], "all", True), "all").argmax(1)
    if D["name"] == "mtg":
        for col, nm in (("lp", "trained model, 5 artist-grouped folds (EVALUATION ONLY)"), ("lp12", "  the same, 12 pitch shifts averaged")):
            lp = cnn_lp(os.path.join(kt.CACHE, "cnn_cv_mtg.npz"), "ids", col, D["ids"])
            if lp is not None and int(np.load(os.path.join(kt.CACHE, "cnn_cv_mtg.npz"))["done"]) == kt.NFOLD - 1: out[nm] = lp.argmax(1); D["cnn_" + col] = lp
        sec = cnn_lp(os.path.join(kt.CACHE, "cnn_sections.npz"), "mtg_ids", "mtg_sec", D["ids"])
        if sec is not None: D["cnn_sec"] = sec
        lp = cnn_lp(os.path.join(kt.CACHE, "cnn_cross_gs_to_mtg.npz"), "ids", "lp12", D["ids"])
        if lp is not None: out["trained model, trained on GiantSteps Key only, 12 shifts (EVALUATION ONLY)"] = lp.argmax(1)
    else:
        pre = "gs" if D["name"] == "gs" else "gsp"
        for col, nm in (("lp", "trained model, trained on MTG only (EVALUATION ONLY)"), ("lp12", "  the same, 12 pitch shifts averaged")):
            lp = cnn_lp(os.path.join(kt.CACHE, "cnn_cross_mtg_to_gs.npz"), pre + "_ids", f"{pre}_{col}", D["ids"])
            if lp is not None: out[nm] = lp.argmax(1); D["cnn_" + col] = lp
        sec = cnn_lp(os.path.join(kt.CACHE, "cnn_sections.npz"), pre + "_ids", pre + "_sec", D["ids"])
        if sec is not None: D["cnn_sec"] = sec
    return out

def four(pred, true):
    a, ma, mi = kt.halves(pred, true); w1 = lambda s: s["exact"] + s["fifth"] + s["relative"]
    return {"n": a["n"], "exact": a["exact"], "ex_maj": ma["exact"], "ex_min": mi["exact"], "mean": (ma["exact"] + mi["exact"]) / 2,
            "w1": w1(a), "w1_maj": w1(ma), "w1_min": w1(mi), "home": a["home"], "home_maj": ma["home"], "home_min": mi["home"],
            "mh_maj": ma["mode_home"], "mh_min": mi["mode_home"], "mh_mean": (ma["mode_home"] + mi["mode_home"]) / 2,
            "fifth": a["fifth"], "relative": a["relative"], "parallel": a["parallel"], "other": a["other"], "mirex": a["mirex"]}

COLS = ("n", "exact", "ex_maj", "ex_min", "mean", "w1", "w1_maj", "w1_min", "home", "home_maj", "home_min", "mh_maj", "mh_min", "mh_mean", "parallel", "mirex")
HEAD = ("| reader | clips | exact: all | major | minor | mean of halves | within one step: all | major | minor | home note: all | major | minor | mode given home: major | minor | mean | parallel errors | MIREX |\n"
        "|---|---:|" + "---:|" * 15)
def row(name, r): return f"| {name} | {r['n']} | " + " | ".join(kt.fmt(r[c]) for c in COLS[1:]) + " |"

def shown_table(title, true, rules, apple=None):
    print(f"\n{title}\n\n| rule | shown, percent of clips | shown keys right | shown keys within one step | minor share of the shown clips |" + (" Apple right on the same clips |" if apple is not None else "") + "\n|---|---:|---:|---:|---:|" + ("---:|" if apple is not None else ""))
    for nm, pred, shown in rules:
        if not shown.any(): continue
        s = kt.stats(pred[shown], true[shown])
        print(f"| {nm} | {100 * shown.mean():.1f} | {s['exact']:.1f} | {s['exact'] + s['fifth'] + s['relative']:.1f} | {100 * (true[shown] >= 12).mean():.0f} |" +
              (f" {100 * (apple[shown] == true[shown]).mean():.1f} |" if apple is not None else ""))

def main():
    M = load_set("mtg"); M["GS"] = load_set("gs"); fh = open(os.path.join(kt.HERE, "x_results.tsv"), "w"); fh.write("set\treader\t" + "\t".join(COLS) + "\n")
    apple = kt.apple_keys()
    sets = [("mtg", "key", "GiantSteps-MTG-key, the 1,270 plain-key clips Apple read (the set D16's bar is defined on; Faraldo's profiles were made from it)"),
            ("gsplus", "key_modal", "GiantSteps+, single-key clips, a modal label counted by its third (the clean set for the untrained readers)"),
            ("gsplus", "key", "GiantSteps+, plain major and minor labels only"),
            ("gs", "key", "GiantSteps Key, the 604 clips with their original labels (the published scale)")]
    for name, label, title in sets:
        D = M if name == "mtg" else load_set(name, label)
        P = readers(D, M); true = D["key"]; sel = np.ones(len(true), bool)
        if name == "mtg":
            ap = np.array([apple.get(i, -1) for i in D["ids"]]); sel = ap >= 0; D["apple"] = ap
            P = {"Apple": ap, **P}
        print(f"\n## {title}: {int(sel.sum())} clips, {int((true[sel] < 12).sum())} major, {int((true[sel] >= 12).sum())} minor\n\n{HEAD}")
        res = {}
        for nm, pred in P.items():
            r = four(pred[sel], true[sel]); res[nm] = r; print(row(nm, r))
            fh.write(f"{name}:{label}\t{nm.strip()}\t" + "\t".join(kt.fmt(r[c], 2) for c in COLS) + "\n")
        if name == "mtg":
            a = res["Apple"]
            print(f"\nThe bar as written: major {a['ex_maj'] - 5:.1f}, minor {a['ex_min'] - 5:.1f}. Read as the mean of halves: {a['mean'] - 5:.1f}. Read as within one step: {a['w1'] - 5:.1f} (all clips).\n")
            print("| reader | bar as written (each half) | mean of halves | within one step |\n|---|---|---|---|")
            for nm, r in res.items():
                if nm == "Apple": continue
                yn = lambda b: "passes" if b else "fails"
                print(f"| {nm} | {yn(r['ex_maj'] >= a['ex_maj'] - 5 and r['ex_min'] >= a['ex_min'] - 5)} (minor {r['ex_min'] - a['ex_min']:+.1f}) | {yn(r['mean'] >= a['mean'] - 5)} ({r['mean'] - a['mean']:+.1f}) | {yn(r['w1'] >= a['w1'] - 5)} ({r['w1'] - a['w1']:+.1f}) |")
            # by style (D5: a gain that lives in one bucket is a flag)
            main = [nm for nm in P if nm in ("Apple", "B (note transcription)", "B's home note + A's mode", "learned profiles on rows A and B, 49 numbers (EVALUATION ONLY)",
                                              "  the same (rows A and B), major and minor weighed equally in the fit", "  the same, 12 pitch shifts averaged")]
            gen = np.array(D["genre"]); print("\nBy Beatport style, exact percent (clips, minor share)\n\n| style | clips | minor, percent | " + " | ".join(m.strip() for m in main) + " |\n|---|---:|---:|" + "---:|" * len(main))
            for g in sorted(set(gen[sel]), key=lambda g: -(sel & (gen == g)).sum()):
                m_ = sel & (gen == g)
                if m_.sum() >= 20: print(f"| {g} | {int(m_.sum())} | {100 * (true[m_] >= 12).mean():.0f} | " + " | ".join(f"{100 * (P[nm][m_] == true[m_]).mean():.0f}" for nm in main) + " |")
            print("\nBy the data set's confidence in its own label, exact percent\n\n| confidence | clips | " + " | ".join(m.strip() for m in main) + " |\n|---|---:|" + "---:|" * len(main))
            for cf in (2, 1, 0):
                m_ = sel & (D["conf"] == cf); print(f"| {cf} | {int(m_.sum())} | " + " | ".join(f"{100 * (P[nm][m_] == true[m_]).mean():.1f}" for nm in main) + " |")
            # letter X's arithmetic, re-derived from the per-clip results
            print("\nMinor half: where each reader's exact rate falls short of Apple's, by kind of error (points of the minor clips)\n\n| reader | exact gap | parallel | relative | fifth | other |\n|---|---:|---:|---:|---:|---:|")
            mi = sel & (true >= 12); sa = kt.stats(ap[mi], true[mi])
            for nm in ("3f (letter R's first reader)", "A (harmonic discount)", "B (note transcription)"):
                s = kt.stats(P[nm][mi], true[mi]); print(f"| {nm} | {sa['exact'] - s['exact']:.1f} | {s['parallel'] - sa['parallel']:.1f} | {s['relative'] - sa['relative']:.1f} | {s['fifth'] - sa['fifth']:.1f} | {s['other'] - sa['other']:.1f} |")
            # trade-off curves: row B's home note, the mode score shifted by a threshold
            for score, nm in ((D["sA"], "row A's profile match (minor r minus major r)"), (D["sLR"], "the trained 12-number rule (probability of minor minus one half)")):
                print(f"\nTrade-off, row B's home note, mode from {nm}: minor when the score is above the threshold\n\n| threshold | called minor, percent | exact: major | minor | mean of halves | all | bar as written |\n|---|---:|---:|---:|---:|---:|---|")
                for q in (0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100):
                    th = np.quantile(score[sel], q / 100) if q < 100 else score.max() + 1; th = -1e9 if q == 0 else th
                    r = four((D["tB"] + 12 * (score > th))[sel], true[sel])
                    print(f"| {'score 0' if False else f'{th:.3f}' if 0 < q < 100 else ('always minor' if q == 0 else 'always major')} | {100 * (score[sel] > th).mean():.0f} | {r['ex_maj']:.1f} | {r['ex_min']:.1f} | {r['mean']:.1f} | {r['exact']:.1f} | "
                          f"{'passes' if r['ex_maj'] >= a['ex_maj'] - 5 and r['ex_min'] >= a['ex_min'] - 5 else 'fails'} |")
                r = four((D["tB"] + 12 * (score > 0))[sel], true[sel]); print(f"| 0 (the rule as it stands) | {100 * (score[sel] > 0).mean():.0f} | {r['ex_maj']:.1f} | {r['ex_min']:.1f} | {r['mean']:.1f} | {r['exact']:.1f} | |")
        # open mode: the home note is always shown (row B's); the mode only when the rule says so
        tB = D["tB"]; tt = true % 12; mi_true = true >= 12; home_ok = tB == tt
        mA = D["sA"] > 0; mB = D["R"]["B"].argmax(1) >= 12
        m3 = D["R"]["3f"][np.arange(len(tB)), 12 + tB] > D["R"]["3f"][np.arange(len(tB)), tB]
        mBp = D["R"]["B"][np.arange(len(tB)), 12 + tB] > D["R"]["B"][np.arange(len(tB)), tB]
        print(f"\nOpen mode on {name}:{label} (the home note is row B's; a mode is named only on some clips)\n\n| rule for naming the mode | mode named, percent of clips | named mode right, where the home note is right | key right, of the clips with a mode named | key right, of all clips (open counts as not right) | home note right on the open clips |\n|---|---:|---:|---:|---:|---:|")
        def open_row(nm, given, mode):
            g = given & sel; ok = home_ok & (mode == mi_true)
            print(f"| {nm} | {100 * g.sum() / sel.sum():.1f} | {100 * ok[g].sum() / max(1, (home_ok & g).sum()):.1f} | {100 * ok[g].mean():.1f} | {100 * (ok & g).sum() / sel.sum():.1f} | "
                  f"{(100 * home_ok[sel & ~given].mean()) if (sel & ~given).any() else float('nan'):.1f} |")
        open_row("always (B's home note + A's mode)", np.ones(len(tB), bool), mA)
        open_row("rows A and B agree on the mode", mA == mBp, mA)
        open_row("rows 3f, A and B agree on the mode", (mA == mBp) & (mA == m3), mA)
        open_row("the one-note template does not win (not 'amodal')", ~D["amodal"], mA)
        for cov in (90, 80, 70, 60, 50):
            th = np.quantile(np.abs(D["sA"][sel]), 1 - cov / 100); open_row(f"A's mode margin in the top {cov} percent (threshold {th:.3f})", np.abs(D["sA"]) >= th, mA)
        print(f"\n'amodal' mark: {100 * D['amodal'][sel].mean():.1f} percent of clips; of them {100 * mi_true[sel & D['amodal']].mean() if (sel & D['amodal']).any() else float('nan'):.0f} percent are labelled minor.")
        # whole key shown or not
        kA, kB, k3 = P["A (harmonic discount)"], P["B (note transcription)"], P["3f (letter R's first reader)"]; kBA = P["B's home note + A's mode"]
        rules = [("B's home note + A's mode, always", kBA, np.ones(len(true), bool)), ("rows A and B give the same key", kB, kA == kB), ("rows 3f, A and B give the same key", kB, (kA == kB) & (k3 == kB)),
                 ("rows A and B agree on the home note and on the mode there", kBA, (kA % 12 == kB % 12) & (mA == mBp))]
        if "cnn_lp12" in D:
            kC = D["cnn_lp12"].argmax(1); pr = np.exp(D["cnn_lp12"]); pr = pr / pr.sum(1, keepdims=True); conf = pr.max(1)
            rules += [("trained model, always", kC, np.ones(len(true), bool)), ("trained model and row B give the same key", kC, kC == kB), ("trained model and row B agree on the home note", kC, kC % 12 == kB % 12)]
            for cov in (90, 80, 70, 60, 50):
                th = np.quantile(conf[sel], 1 - cov / 100); rules.append((f"trained model, its {cov} percent most confident clips", kC, conf >= th))
        shown_table(f"Keys shown or left unshown on {name}:{label}", true[sel], [(a_, b_[sel], c_[sel]) for a_, b_, c_ in rules], D["apple"][sel] if name == "mtg" else None)
        with open(os.path.join(kt.HERE, f"x_clips_{name}_{label}.tsv"), "w") as fc:
            names = list(P); fc.write("id\tkey\tfold\t" + "\t".join(n_.strip() for n_ in names) + "\n")
            for i in range(len(true)):
                fc.write(f"{D['ids'][i]}\t{kt.key_name(true[i])}\t{D['fold'][i]}\t" + "\t".join(kt.key_name(P[n_][i]) if P[n_][i] >= 0 else "" for n_ in names) + "\n")
    fh.close()

if __name__ == "__main__":
    main()
